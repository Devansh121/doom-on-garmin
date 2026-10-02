// r_segs.c
//
// All the clipping: columns, horizontal spans, sky columns.
//
// Differences from the C code, all because walls, floors and ceilings
// are drawn as flat colors (see RData):
//  - no texturemid, and texture columns only with textured walls on
//    (TEXTURED=1 ./build.sh): then a column is the texture's band at
//    texturecolumn, lit through COLORMAP. Otherwise only which texture
//    and which light level a column uses matter.
//  - floor and ceiling spans are filled with the plane's color right
//    where R_RenderSegLoop marks them, instead of being stored in the
//    visplane for R_DrawPlanes. The light for a span is what R_MapPlane
//    would pick for its middle row.
//  - masked mid textures aren't drawn: maskedtexturecol space is
//    allocated in openings like in the C code, but not filled.

import Toybox.Graphics;
import Toybox.Lang;

module RSegs {

    const HEIGHTBITS = 12;
    const HEIGHTUNIT = 1 << HEIGHTBITS;

    // OPTIMIZE: closed two sided lines as single sided

    // True if any of the segs textures might be visible.
    var segtextured as Boolean = false;

    // False if the back side is the same plane.
    var markfloor as Boolean = false;
    var markceiling as Boolean = false;

    var maskedtexture as Boolean = false;
    var toptexture as Number = 0;
    var bottomtexture as Number = 0;
    var midtexture as Number = 0;

    var rw_normalangle as Number = 0;
    // only used with textured walls
    var rw_offset as Number = 0;
    var rw_centerangle as Number = 0;
    // angle to line origin
    var rw_angle1 as Number = 0;

    //
    // regular wall
    //
    var rw_x as Number = 0;
    var rw_stopx as Number = 0;
    var rw_distance as Number = 0;
    var rw_scale as Number = 0;
    var rw_scalestep as Number = 0;

    var worldtop as Number = 0;
    var worldbottom as Number = 0;
    var worldhigh as Number = 0;
    var worldlow as Number = 0;

    var pixhigh as Number = 0;
    var pixlow as Number = 0;
    var pixhighstep as Number = 0;
    var pixlowstep as Number = 0;

    var topfrac as Number = 0;
    var topstep as Number = 0;

    var bottomfrac as Number = 0;
    var bottomstep as Number = 0;

    // row of scalelight to use: walllights[i] is scalelight[walllights + i]
    var walllights as Number = 0;

    //
    // drawseg_t, one array per field.
    //
    const MAXDRAWSEGS = 256;
    const SIL_NONE = 0;
    const SIL_BOTTOM = 1;
    const SIL_TOP = 2;
    const SIL_BOTH = 3;

    var drawsegs_curline as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    var drawsegs_x1 as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    var drawsegs_x2 as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    var drawsegs_scale1 as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    var drawsegs_scale2 as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    var drawsegs_scalestep as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    // 0=none, 1=bottom, 2=top, 3=both
    var drawsegs_silhouette as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    // do not clip sprites above this
    var drawsegs_bsilheight as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    // do not clip sprites below this
    var drawsegs_tsilheight as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;

    // index of the next free drawseg (ds_p)
    var ds_p as Number = 0;

    // ---- sprite clipping (r_things), from r_segs.c / r_plane.c ----
    //
    // Pointers to clip lists become indexes into openings:
    // sprtopclip[x] is openings[drawsegs_sprtopclip[ds] + x]. NULL is -1.
    // openings is a ByteArray holding value + 1 (clip values run from -1
    // to viewheight), to keep it small.
    //
    // negonearray and screenheightarray (r_things.c) are the first
    // 2 * SCREENWIDTH entries of openings, so they can be pointed at the
    // same way; R_InitSprites and R_ExecuteSetViewSize fill them.
    //
    // MAXOPENINGS is SCREENWIDTH*64 in the C code, for up to 320
    // columns. E1M1 views use under 1000 at low detail, so this keeps a
    // few times that rather than 20 KB of heap.
    const NEGONEARRAY = 0;
    const SCREENHEIGHTARRAY = RMain.SCREENWIDTH;
    const FIRSTOPENING = 2 * RMain.SCREENWIDTH;
    const MAXOPENINGS = FIRSTOPENING + RMain.SCREENWIDTH * 12;
    var openings as ByteArray = new [MAXOPENINGS]b;
    var lastopening as Number = FIRSTOPENING;

    var drawsegs_sprtopclip as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    var drawsegs_sprbottomclip as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;
    var drawsegs_maskedtexturecol as Array<Number> = new [MAXDRAWSEGS] as Array<Number>;

    // Copies count clip values from clip[start..] to lastopening, the
    // memcpy in R_StoreWallRange. Returns the new list's pointer
    // (lastopening - start).
    function saveClip(clip as Array<Number>, start as Number, count as Number) as Number {
        var o = openings;
        var p = lastopening;
        if (p + count > MAXOPENINGS) {
            // R_DrawPlanes' check, made before writing past the end
            ISystem.I_Error("R_StoreWallRange: opening overflow");
        }
        // The C lists are shorts, and near a wall a column's clip can be far
        // off screen (topfrac gives yl in the thousands, or very negative).
        // Off-screen values clip a sprite the same as -1 / viewheight do
        // (all of the column visible, or none of it), so they're clamped to
        // that range to fit the bytes.
        var vh = RMain.viewheight;
        for (var i = 0; i < count; i++) {
            var c = clip[start + i];
            if (c < -1) {
                c = -1;
            } else if (c > vh) {
                c = vh;
            }
            o[p + i] = c + 1;
        }
        lastopening = p + count;
        return p - start;
    }
    // ---- end of sprite clipping ----

    // Rough count of work done this frame, so the BSP walk knows when to
    // hand control back before the watchdog trips.
    var work as Number = 0;

    // System.getTimer() time by which the current callback should hand
    // control back, set by DMain from a speed calibration. The step loops
    // check it as well as their work budgets. MAXINT (tests) means never.
    var deadline as Number = 0x7fffffff;

    // When set, R_StoreWallRange appends [curline, start, stop] and
    // R_RenderSegLoop appends [kind, x, yl, yh, a, b] to drawtrace, for
    // tests. kind 0 is a wall column (a = texture, b = colormap level),
    // 1 a ceiling span and 2 a floor span (a = picnum, b = height).
    var trace as Array<Number>? = null;
    var drawtrace as Array<Number>? = null;

    function R_RenderSegLoop() as Void {
        var ceilingclip = RPlane.ceilingclip;
        var floorclip = RPlane.floorclip;
        var scalelight = RMain.scalelight;
        var viewheight = RMain.viewheight;
        var dtrace = drawtrace;

        var texturecolors = RData.texturecolors;
        var midbase = midtexture * RMain.NUMCOLORMAPS;
        var topbase = toptexture * RMain.NUMCOLORMAPS;
        var bottombase = bottomtexture * RMain.NUMCOLORMAPS;
        var level = 0;

        var ceilingplane = RPlane.ceilingplane;
        var floorplane = RPlane.floorplane;
        if (markceiling) {
            planeSetup(ceilingplane);
        }
        var ceilbase = planebase;
        var ceillight = planelight;
        var ceilheight = planeheight;
        if (markfloor) {
            planeSetup(floorplane);
        }
        var floorbase = planebase;
        var floorlight = planelight;
        var floorheight = planeheight;

        // R_DrawColumn and the plane light lookup are inlined below; this
        // loop runs for every column of every wall, and calls plus module
        // lookups cost more than the drawing itself.
        var dc = RDraw.dc as Graphics.Dc;
        var colx = RDraw.colx;
        var rowy = RDraw.rowy;
        var lastcolor = RDraw.lastcolor;
        var yslope = RMain.yslope;
        var zlight = RMain.zlight;
        var flatcolors = RData.flatcolors;
        var skycolor = texturecolors[RData.skytexture * RMain.NUMCOLORMAPS];
        var fixedcolormap = RMain.fixedcolormap;
        var color;
        var px;
        var py;

        // The loop below runs for every column of every wall. Module
        // variables cost about 45x a local on the watch, so everything it
        // touches is copied into locals here and written back after.
        var stopx = rw_stopx;
        var tf = topfrac;
        var tstep = topstep;
        var bf = bottomfrac;
        var bstep = bottomstep;
        var scale = rw_scale;
        var scalestep = rw_scalestep;
        var ph = pixhigh;
        var phstep = pixhighstep;
        var pl = pixlow;
        var plstep = pixlowstep;
        var mceil = markceiling;
        var mfloor = markfloor;
        var mid_t = midtexture;
        var top_t = toptexture;
        var bottom_t = bottomtexture;
        var textured = segtextured;
        var wl = walllights;
        // textured walls: what R_GetColumn needs, see RData
        var texw = RMain.texturedwalls && textured;
        var centerangle = rw_centerangle;
        var offset = rw_offset;
        var distance = rw_distance;
        var finetangent = Tables.finetangent;
        var xtoviewangle = RMain.xtoviewangle;
        var widthmask = RData.texturewidthmask;
        var bands = RData.texturebands;
        var colormaps = RData.colormaps;
        var palette = RData.palette;
        var tc = 0;
        var k;
        var ceilheighth = ceilheight >> 16;
        var ceilheightl = ceilheight & 0xffff;
        var floorheighth = floorheight >> 16;
        var floorheightl = floorheight & 0xffff;

        for (var x = rw_x; x < stopx; x++) {

            // mark floor / ceiling areas
            var yl = (tf + HEIGHTUNIT - 1) >> HEIGHTBITS;

            // no space above wall?
            if (yl < ceilingclip[x] + 1) {
                yl = ceilingclip[x] + 1;
            }

            if (mceil) {
                var top = ceilingclip[x] + 1;
                var bottom = yl - 1;

                if (bottom >= floorclip[x]) {
                    bottom = floorclip[x] - 1;
                }

                if (top <= bottom) {
                    // ceilingplane->top[rw_x] = top;
                    // ceilingplane->bottom[rw_x] = bottom;
                    if (ceilbase < 0) {
                        color = skycolor;
                    } else if (fixedcolormap >= 0) {
                        color = flatcolors[ceilbase + fixedcolormap];
                    } else {
                        // R_MapPlane's light for the span's middle row
                        // FixedMul(planeheight, yslope[y]) in 32-bit halves, as MFixed does
                        var ys = yslope[(top + bottom) >> 1];
                        var yl16 = ys & 0xffff;
                        var yh16 = ys >> 16;
                        var index = ((((ceilheighth * yh16) << 16) + ceilheighth * yl16 + ceilheightl * yh16 + (((ceilheightl * yl16) >> 16) & 0xffff))) >> RMain.LIGHTZSHIFT;
                        if (index >= RMain.MAXLIGHTZ) {
                            index = RMain.MAXLIGHTZ - 1;
                        }
                        color = flatcolors[ceilbase + zlight[ceillight + index]];
                    }
                    color = color;
                    if (color != lastcolor) {
                        dc.setColor(color, color);
                        lastcolor = color;
                    }
                    px = colx[x];
                    py = rowy[top];
                    dc.fillRectangle(px, py, colx[x + 1] - px, rowy[bottom + 1] - py);
                    if (dtrace != null) {
                        dtrace.addAll([1, x, top, bottom, RPlane.visplanes_picnum[ceilingplane],
                                       RPlane.visplanes_height[ceilingplane] >> 16]);
                    }
                }
            }

            var yh = bf >> HEIGHTBITS;

            if (yh >= floorclip[x]) {
                yh = floorclip[x] - 1;
            }

            if (mfloor) {
                var top = yh + 1;
                var bottom = floorclip[x] - 1;
                if (top <= ceilingclip[x]) {
                    top = ceilingclip[x] + 1;
                }
                if (top <= bottom) {
                    // floorplane->top[rw_x] = top;
                    // floorplane->bottom[rw_x] = bottom;
                    if (floorbase < 0) {
                        color = skycolor;
                    } else if (fixedcolormap >= 0) {
                        color = flatcolors[floorbase + fixedcolormap];
                    } else {
                        // R_MapPlane's light for the span's middle row
                        // FixedMul(planeheight, yslope[y]) in 32-bit halves, as MFixed does
                        var ys = yslope[(top + bottom) >> 1];
                        var yl16 = ys & 0xffff;
                        var yh16 = ys >> 16;
                        var index = ((((floorheighth * yh16) << 16) + floorheighth * yl16 + floorheightl * yh16 + (((floorheightl * yl16) >> 16) & 0xffff))) >> RMain.LIGHTZSHIFT;
                        if (index >= RMain.MAXLIGHTZ) {
                            index = RMain.MAXLIGHTZ - 1;
                        }
                        color = flatcolors[floorbase + zlight[floorlight + index]];
                    }
                    color = color;
                    if (color != lastcolor) {
                        dc.setColor(color, color);
                        lastcolor = color;
                    }
                    px = colx[x];
                    py = rowy[top];
                    dc.fillRectangle(px, py, colx[x + 1] - px, rowy[bottom + 1] - py);
                    if (dtrace != null) {
                        dtrace.addAll([2, x, top, bottom, RPlane.visplanes_picnum[floorplane],
                                       RPlane.visplanes_height[floorplane] >> 16]);
                    }
                }
            }

            // texturecolumn and lighting are independent of wall tiers
            if (textured) {
                // calculate lighting
                var index = scale >> RMain.LIGHTSCALESHIFT;

                if (index >= RMain.MAXLIGHTSCALE) {
                    index = RMain.MAXLIGHTSCALE - 1;
                }

                // dc_colormap = wl[index];
                level = fixedcolormap >= 0 ? fixedcolormap : scalelight[wl + index];

                if (texw) {
                    // calculate texture offset
                    var t = finetangent[((centerangle + xtoviewangle[x]) >> Tables.ANGLETOFINESHIFT) & 0xfff];
                    // FixedMul (finetangent[angle], rw_distance), in halves
                    var th = t >> 16;
                    var tl = t & 0xffff;
                    var dh = distance >> 16;
                    var dl = distance & 0xffff;
                    tc = (offset - (((th * dh) << 16) + th * dl + tl * dh + (((tl * dl) >> 16) & 0xffff))) >> MFixed.FRACBITS;
                }
            }

            // draw the wall tiers
            if (mid_t != 0) {
                // single sided line
                // (colfunc draws nothing when dc_yh < dc_yl)
                if (yl <= yh) {
                    if (texw) {
                        // R_GetColumn: the texture's band at texturecolumn, lit
                        // through COLORMAP like dc_colormap does
                        k = mid_t * RData.TEXBANDS + ((tc & widthmask[mid_t]) * RData.TEXBANDS) / (widthmask[mid_t] + 1);
                        k = level * 256 + ((bands[k >> 2] >> ((k & 3) * 8)) & 0xff);
                        color = palette[(colormaps[k >> 2] >> ((k & 3) * 8)) & 0xff];
                    } else {
                        color = texturecolors[midbase + level];
                    }
                    if (color != lastcolor) {
                        dc.setColor(color, color);
                        lastcolor = color;
                    }
                    px = colx[x];
                    py = rowy[yl];
                    dc.fillRectangle(px, py, colx[x + 1] - px, rowy[yh + 1] - py);
                    if (dtrace != null) {
                        dtrace.addAll([0, x, yl, yh, mid_t, level]);
                    }
                }
                ceilingclip[x] = viewheight;
                floorclip[x] = -1;
            } else {
                // two sided line
                if (top_t != 0) {
                    // top wall
                    var mid = ph >> HEIGHTBITS;
                    ph += phstep;

                    if (mid >= floorclip[x]) {
                        mid = floorclip[x] - 1;
                    }

                    if (mid >= yl) {
                        if (texw) {
                            // R_GetColumn: the texture's band at texturecolumn, lit
                            // through COLORMAP like dc_colormap does
                            k = top_t * RData.TEXBANDS + ((tc & widthmask[top_t]) * RData.TEXBANDS) / (widthmask[top_t] + 1);
                            k = level * 256 + ((bands[k >> 2] >> ((k & 3) * 8)) & 0xff);
                            color = palette[(colormaps[k >> 2] >> ((k & 3) * 8)) & 0xff];
                        } else {
                            color = texturecolors[topbase + level];
                        }
                        if (color != lastcolor) {
                            dc.setColor(color, color);
                            lastcolor = color;
                        }
                        px = colx[x];
                        py = rowy[yl];
                        dc.fillRectangle(px, py, colx[x + 1] - px, rowy[mid + 1] - py);
                        if (dtrace != null) {
                            dtrace.addAll([0, x, yl, mid, top_t, level]);
                        }
                        ceilingclip[x] = mid;
                    } else {
                        ceilingclip[x] = yl - 1;
                    }
                } else {
                    // no top wall
                    if (mceil) {
                        ceilingclip[x] = yl - 1;
                    }
                }

                if (bottom_t != 0) {
                    // bottom wall
                    var mid = (pl + HEIGHTUNIT - 1) >> HEIGHTBITS;
                    pl += plstep;

                    // no space above wall?
                    if (mid <= ceilingclip[x]) {
                        mid = ceilingclip[x] + 1;
                    }

                    if (mid <= yh) {
                        if (texw) {
                            // R_GetColumn: the texture's band at texturecolumn, lit
                            // through COLORMAP like dc_colormap does
                            k = bottom_t * RData.TEXBANDS + ((tc & widthmask[bottom_t]) * RData.TEXBANDS) / (widthmask[bottom_t] + 1);
                            k = level * 256 + ((bands[k >> 2] >> ((k & 3) * 8)) & 0xff);
                            color = palette[(colormaps[k >> 2] >> ((k & 3) * 8)) & 0xff];
                        } else {
                            color = texturecolors[bottombase + level];
                        }
                        if (color != lastcolor) {
                            dc.setColor(color, color);
                            lastcolor = color;
                        }
                        px = colx[x];
                        py = rowy[mid];
                        dc.fillRectangle(px, py, colx[x + 1] - px, rowy[yh + 1] - py);
                        if (dtrace != null) {
                            dtrace.addAll([0, x, mid, yh, bottom_t, level]);
                        }
                        floorclip[x] = mid;
                    } else {
                        floorclip[x] = yh + 1;
                    }
                } else {
                    // no bottom wall
                    if (mfloor) {
                        floorclip[x] = yh + 1;
                    }
                }

                // save texturecol
                //  for backdrawing of masked mid texture
                // (maskedtexturecol[rw_x] = texturecolumn: texture
                // columns aren't tracked, masked mid textures aren't
                // drawn yet)
            }

            scale += scalestep;
            tf += tstep;
            bf += bstep;
        }
        rw_x = stopx;
        topfrac = tf;
        bottomfrac = bf;
        rw_scale = scale;
        pixhigh = ph;
        pixlow = pl;
        RDraw.lastcolor = lastcolor;
    }

    //
    // Plane colors. planeSetup leaves where the plane's colors start in
    // RData.flatcolors (or -1 for sky), its zlight row and
    // abs(height - viewz), the way R_DrawPlanes sets up each plane.
    //
    var planebase as Number = -1;
    var planelight as Number = 0;
    var planeheight as Number = 0;

    function planeSetup(plane as Number) as Void {
        var picnum = RPlane.visplanes_picnum[plane];
        if (picnum == RData.skyflatnum) {
            planebase = -1;
            return;
        }
        planebase = RData.flattranslation[picnum] * RMain.NUMCOLORMAPS;
        // planeheight = abs(pl->height-viewz);
        planeheight = MFixed.abs(RPlane.visplanes_height[plane] - RMain.viewz);
        // light = (pl->lightlevel >> LIGHTSEGSHIFT)+extralight;
        var light = (RPlane.visplanes_lightlevel[plane] >> RMain.LIGHTSEGSHIFT) + RMain.extralight;
        if (light >= RMain.LIGHTLEVELS) {
            light = RMain.LIGHTLEVELS - 1;
        }
        if (light < 0) {
            light = 0;
        }
        planelight = light * RMain.MAXLIGHTZ;
    }


    //
    // R_StoreWallRange
    // A wall segment will be drawn
    //  between start and stop pixels (inclusive).
    //
    function R_StoreWallRange(start as Number, stop as Number) as Void {
        // Split in three so R_StoreWallRangeSetup's locals are off the
        // stack while R_RenderSegLoop runs: Monkey C's stack only holds
        // about 220 slots, and this is the deepest point of a frame.
        if (R_StoreWallRangeSetup(start, stop)) {
            R_RenderSegLoop();
            R_StoreWallRangeFinish(start);
        }
    }

    // Everything R_StoreWallRange does before R_RenderSegLoop. Returns
    // false if the wall isn't stored (out of drawsegs).
    function R_StoreWallRangeSetup(start as Number, stop as Number) as Boolean {
        work += stop - start + 1;
        if (trace != null) {
            trace.add(RBsp.curline);
            trace.add(start);
            trace.add(stop);
        }

        // don't overflow and crash
        if (ds_p == MAXDRAWSEGS) {
            return false;
        }

        // This runs for every visible wall. On the watch a module
        // variable costs about 23 us to read or write against well under
        // 1 us for a local, so the work below is done in locals and the
        // module variables R_ScaleFromGlobalAngle and R_RenderSegLoop read
        // are set once each. The steps are the C code's.
        var curline = RBsp.curline;
        var frontsector = RBsp.frontsector;
        var backsector = RBsp.backsector;
        var sidedef = PSetup.segs_sidedef[curline];
        var linedef = PSetup.segs_linedef[curline];
        RBsp.sidedef = sidedef;
        RBsp.linedef = linedef;
        var viewz = RMain.viewz;
        var sectors_floorheight = PSetup.sectors_floorheight;
        var sectors_ceilingheight = PSetup.sectors_ceilingheight;
        var sectors_ceilingpic = PSetup.sectors_ceilingpic;
        var sectors_lightlevel = PSetup.sectors_lightlevel;
        var texturetranslation = RData.texturetranslation;
        var skyflatnum = RData.skyflatnum;
        var ffloor = sectors_floorheight[frontsector];
        var fceil = sectors_ceilingheight[frontsector];

        // mark the segment as visible for auto map
        PSetup.lines_flags[linedef] |= DoomData.ML_MAPPED;

        // calculate rw_distance for scale calculation
        var normalangle = PSetup.segs_angle[curline] + Tables.ANG90;
        rw_normalangle = normalangle;
        var offsetangle = normalangle - rw_angle1;
        if (offsetangle < 0) {
            offsetangle = -offsetangle;  // abs()
        }

        if ((offsetangle ^ DoomType.MININT) > (Tables.ANG90 ^ DoomType.MININT)) {
            offsetangle = Tables.ANG90;
        }

        var distangle = Tables.ANG90 - offsetangle;
        // curline->v1, packed x | y << 16 (see PSetup)
        var v1 = PSetup.vertexes_xy[PSetup.segs_v1[curline]];
        var hyp = RMain.R_PointToDist(v1 << 16, v1 & ~0xffff);
        var sineval = Tables.finesine[(distangle >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK];
        rw_distance = MFixed.FixedMul(hyp, sineval);

        var ds = ds_p;
        rw_x = start;
        drawsegs_x1[ds] = start;
        drawsegs_x2[ds] = stop;
        drawsegs_curline[ds] = curline;
        var stopx = stop + 1;
        rw_stopx = stopx;

        // calculate scale at both ends and step
        var viewangle = RMain.viewangle;
        var xtoviewangle = RMain.xtoviewangle;
        var scale = RMain.R_ScaleFromGlobalAngle(viewangle + xtoviewangle[start]);
        rw_scale = scale;
        drawsegs_scale1[ds] = scale;
        var scalestep = rw_scalestep;

        if (stop > start) {
            var scale2 = RMain.R_ScaleFromGlobalAngle(viewangle + xtoviewangle[stop]);
            drawsegs_scale2[ds] = scale2;
            scalestep = (scale2 - scale) / (stop - start);
            rw_scalestep = scalestep;
            drawsegs_scalestep[ds] = scalestep;
        } else {
            drawsegs_scale2[ds] = scale;
            // rw_scalestep keeps its old value, as in the C code.
        }

        // calculate texture boundaries
        //  and decide if floor / ceiling marks are needed
        var wtop = fceil - viewz;
        var wbottom = ffloor - viewz;
        var whigh = 0;
        var wlow = 0;

        var mid_t = 0;
        var top_t = 0;
        var bottom_t = 0;
        var masked = false;
        var mfloor;
        var mceil;
        drawsegs_maskedtexturecol[ds] = -1;

        if (backsector == -1) {
            // single sided line
            mid_t = texturetranslation[PSetup.sides_midtexture[sidedef]];
            // a single sided line is terminal, so it must mark ends
            mfloor = true;
            mceil = true;
            // (rw_midtexturemid only matters for texturing)
            drawsegs_silhouette[ds] = SIL_BOTH;
            drawsegs_sprtopclip[ds] = SCREENHEIGHTARRAY;
            drawsegs_sprbottomclip[ds] = NEGONEARRAY;
            drawsegs_bsilheight[ds] = DoomType.MAXINT;
            drawsegs_tsilheight[ds] = DoomType.MININT;
        } else {
            var bfloor = sectors_floorheight[backsector];
            var bceil = sectors_ceilingheight[backsector];

            // two sided line
            var sil = 0;
            var sprtop = -1;
            var sprbottom = -1;

            if (ffloor > bfloor) {
                sil = SIL_BOTTOM;
                drawsegs_bsilheight[ds] = ffloor;
            } else if (bfloor > viewz) {
                sil = SIL_BOTTOM;
                drawsegs_bsilheight[ds] = DoomType.MAXINT;
            }

            if (fceil < bceil) {
                sil |= SIL_TOP;
                drawsegs_tsilheight[ds] = fceil;
            } else if (bceil < viewz) {
                sil |= SIL_TOP;
                drawsegs_tsilheight[ds] = DoomType.MININT;
            }

            if (bceil <= ffloor) {
                sprbottom = NEGONEARRAY;
                drawsegs_bsilheight[ds] = DoomType.MAXINT;
                sil |= SIL_BOTTOM;
            }

            if (bfloor >= fceil) {
                sprtop = SCREENHEIGHTARRAY;
                drawsegs_tsilheight[ds] = DoomType.MININT;
                sil |= SIL_TOP;
            }
            drawsegs_silhouette[ds] = sil;
            drawsegs_sprtopclip[ds] = sprtop;
            drawsegs_sprbottomclip[ds] = sprbottom;

            whigh = bceil - viewz;
            wlow = bfloor - viewz;

            // hack to allow height changes in outdoor areas
            if (sectors_ceilingpic[frontsector] == skyflatnum
                && sectors_ceilingpic[backsector] == skyflatnum) {
                wtop = whigh;
            }

            var samelight = sectors_lightlevel[backsector] == sectors_lightlevel[frontsector];
            if (wlow != wbottom
                || PSetup.sectors_floorpic[backsector] != PSetup.sectors_floorpic[frontsector]
                || !samelight) {
                mfloor = true;
            } else {
                // same plane on both sides
                mfloor = false;
            }

            if (whigh != wtop
                || sectors_ceilingpic[backsector] != sectors_ceilingpic[frontsector]
                || !samelight) {
                mceil = true;
            } else {
                // same plane on both sides
                mceil = false;
            }

            if (bceil <= ffloor || bfloor >= fceil) {
                // closed door
                mceil = true;
                mfloor = true;
            }

            if (whigh < wtop) {
                // top texture
                top_t = texturetranslation[PSetup.sides_toptexture[sidedef]];
            }
            if (wlow > wbottom) {
                // bottom texture
                bottom_t = texturetranslation[PSetup.sides_bottomtexture[sidedef]];
            }

            // allocate space for masked texture tables
            if (PSetup.sides_midtexture[sidedef] != 0) {
                // masked midtexture
                masked = true;
                drawsegs_maskedtexturecol[ds] = lastopening - start;
                lastopening += stopx - start;
            }
        }

        // calculate rw_offset (only needed for textured lines)
        var textured = mid_t != 0 || top_t != 0 || bottom_t != 0 || masked;

        if (textured) {
            if (RMain.texturedwalls) {
                var oa = normalangle - rw_angle1;
                if ((oa ^ DoomType.MININT) > (Tables.ANG180 ^ DoomType.MININT)) {
                    oa = -oa;
                }
                if ((oa ^ DoomType.MININT) > (Tables.ANG90 ^ DoomType.MININT)) {
                    oa = Tables.ANG90;
                }
                sineval = Tables.finesine[(oa >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK];
                var offset = MFixed.FixedMul(hyp, sineval);
                if (((normalangle - rw_angle1) ^ DoomType.MININT) < (Tables.ANG180 ^ DoomType.MININT)) {
                    offset = -offset;
                }
                rw_offset = offset + PSetup.sides_textureoffset[sidedef] + PSetup.segs_offset[curline];
                rw_centerangle = Tables.ANG90 + viewangle - normalangle;
            }

            // calculate light table
            //  use different light tables
            //  for horizontal / vertical / diagonal
            // OPTIMIZE: get rid of LIGHTSEGSHIFT globally
            if (RMain.fixedcolormap < 0) {
                var lightnum = (sectors_lightlevel[frontsector] >> RMain.LIGHTSEGSHIFT) + RMain.extralight;

                var v2 = PSetup.vertexes_xy[PSetup.segs_v2[curline]];
                if ((v1 & ~0xffff) == (v2 & ~0xffff)) {
                    lightnum--;
                } else if ((v1 << 16) == (v2 << 16)) {
                    lightnum++;
                }

                if (lightnum < 0) {
                    walllights = 0;
                } else if (lightnum >= RMain.LIGHTLEVELS) {
                    walllights = (RMain.LIGHTLEVELS - 1) * RMain.MAXLIGHTSCALE;
                } else {
                    walllights = lightnum * RMain.MAXLIGHTSCALE;
                }
            }
        }

        // if a floor / ceiling plane is on the wrong side
        //  of the view plane, it is definitely invisible
        //  and doesn't need to be marked.

        if (ffloor >= viewz) {
            // above view plane
            mfloor = false;
        }

        if (fceil <= viewz && sectors_ceilingpic[frontsector] != skyflatnum) {
            // below view plane
            mceil = false;
        }

        // calculate incremental stepping values for texture edges
        wtop >>= 4;
        wbottom >>= 4;

        var centeryfrac4 = RMain.centeryfrac >> 4;
        topstep = -MFixed.FixedMul(scalestep, wtop);
        topfrac = centeryfrac4 - MFixed.FixedMul(wtop, scale);

        bottomstep = -MFixed.FixedMul(scalestep, wbottom);
        bottomfrac = centeryfrac4 - MFixed.FixedMul(wbottom, scale);

        if (backsector != -1) {
            whigh >>= 4;
            wlow >>= 4;

            if (whigh < wtop) {
                pixhigh = centeryfrac4 - MFixed.FixedMul(whigh, scale);
                pixhighstep = -MFixed.FixedMul(scalestep, whigh);
            }

            if (wlow > wbottom) {
                pixlow = centeryfrac4 - MFixed.FixedMul(wlow, scale);
                pixlowstep = -MFixed.FixedMul(scalestep, wlow);
            }
        }

        worldtop = wtop;
        worldbottom = wbottom;
        worldhigh = whigh;
        worldlow = wlow;
        midtexture = mid_t;
        toptexture = top_t;
        bottomtexture = bottom_t;
        maskedtexture = masked;
        segtextured = textured;
        markfloor = mfloor;
        markceiling = mceil;

        // render it: R_StoreWallRange calls R_RenderSegLoop next.
        // (R_CheckPlane only splits visplanes' column lists, which
        // aren't kept here)
        return true;
    }

    // The rest of R_StoreWallRange, after R_RenderSegLoop.
    function R_StoreWallRangeFinish(start as Number) as Void {
        var ds = ds_p;
        var stopx = rw_stopx;
        var masked = maskedtexture;

        // save sprite clipping info
        var sil2 = drawsegs_silhouette[ds];
        if (((sil2 & SIL_TOP) != 0 || masked)
            && drawsegs_sprtopclip[ds] == -1) {
            drawsegs_sprtopclip[ds] = saveClip(RPlane.ceilingclip, start, stopx - start);
        }

        if (((sil2 & SIL_BOTTOM) != 0 || masked)
            && drawsegs_sprbottomclip[ds] == -1) {
            drawsegs_sprbottomclip[ds] = saveClip(RPlane.floorclip, start, stopx - start);
        }

        if (masked && (sil2 & SIL_TOP) == 0) {
            sil2 |= SIL_TOP;
            drawsegs_tsilheight[ds] = DoomType.MININT;
        }
        if (masked && (sil2 & SIL_BOTTOM) == 0) {
            sil2 |= SIL_BOTTOM;
            drawsegs_bsilheight[ds] = DoomType.MAXINT;
        }
        drawsegs_silhouette[ds] = sil2;
        ds_p++;
    }
}
