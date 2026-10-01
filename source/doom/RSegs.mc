// r_segs.c
//
// All the clipping: columns, horizontal spans, sky columns.
//
// Differences from the C code, all because walls, floors and ceilings
// are drawn as flat colors (see RData):
//  - no texture columns or texturemid: only which texture and which
//    light level a column uses matter.
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
        for (var i = 0; i < count; i++) {
            o[p + i] = clip[start + i] + 1;
        }
        lastopening = p + count;
        return p - start;
    }
    // ---- end of sprite clipping ----

    // Rough count of work done this frame, so the BSP walk knows when to
    // hand control back before the watchdog trips.
    var work as Number = 0;

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

        for (; rw_x < rw_stopx; rw_x++) {
            var x = rw_x;

            // mark floor / ceiling areas
            var yl = (topfrac + HEIGHTUNIT - 1) >> HEIGHTBITS;

            // no space above wall?
            if (yl < ceilingclip[x] + 1) {
                yl = ceilingclip[x] + 1;
            }

            if (markceiling) {
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
                        var index = (((ceilheight.toLong() * yslope[(top + bottom) >> 1]) >> 16).toNumber()) >> RMain.LIGHTZSHIFT;
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

            var yh = bottomfrac >> HEIGHTBITS;

            if (yh >= floorclip[x]) {
                yh = floorclip[x] - 1;
            }

            if (markfloor) {
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
                        var index = (((floorheight.toLong() * yslope[(top + bottom) >> 1]) >> 16).toNumber()) >> RMain.LIGHTZSHIFT;
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
            if (segtextured) {
                // calculate lighting
                var index = rw_scale >> RMain.LIGHTSCALESHIFT;

                if (index >= RMain.MAXLIGHTSCALE) {
                    index = RMain.MAXLIGHTSCALE - 1;
                }

                // dc_colormap = walllights[index];
                level = RMain.fixedcolormap >= 0 ? RMain.fixedcolormap : scalelight[walllights + index];
            }

            // draw the wall tiers
            if (midtexture != 0) {
                // single sided line
                // (colfunc draws nothing when dc_yh < dc_yl)
                if (yl <= yh) {
                    color = texturecolors[midbase + level];
                    if (color != lastcolor) {
                        dc.setColor(color, color);
                        lastcolor = color;
                    }
                    px = colx[x];
                    py = rowy[yl];
                    dc.fillRectangle(px, py, colx[x + 1] - px, rowy[yh + 1] - py);
                    if (dtrace != null) {
                        dtrace.addAll([0, x, yl, yh, midtexture, level]);
                    }
                }
                ceilingclip[x] = viewheight;
                floorclip[x] = -1;
            } else {
                // two sided line
                if (toptexture != 0) {
                    // top wall
                    var mid = pixhigh >> HEIGHTBITS;
                    pixhigh += pixhighstep;

                    if (mid >= floorclip[x]) {
                        mid = floorclip[x] - 1;
                    }

                    if (mid >= yl) {
                        color = texturecolors[topbase + level];
                        if (color != lastcolor) {
                            dc.setColor(color, color);
                            lastcolor = color;
                        }
                        px = colx[x];
                        py = rowy[yl];
                        dc.fillRectangle(px, py, colx[x + 1] - px, rowy[mid + 1] - py);
                        if (dtrace != null) {
                            dtrace.addAll([0, x, yl, mid, toptexture, level]);
                        }
                        ceilingclip[x] = mid;
                    } else {
                        ceilingclip[x] = yl - 1;
                    }
                } else {
                    // no top wall
                    if (markceiling) {
                        ceilingclip[x] = yl - 1;
                    }
                }

                if (bottomtexture != 0) {
                    // bottom wall
                    var mid = (pixlow + HEIGHTUNIT - 1) >> HEIGHTBITS;
                    pixlow += pixlowstep;

                    // no space above wall?
                    if (mid <= ceilingclip[x]) {
                        mid = ceilingclip[x] + 1;
                    }

                    if (mid <= yh) {
                        color = texturecolors[bottombase + level];
                        if (color != lastcolor) {
                            dc.setColor(color, color);
                            lastcolor = color;
                        }
                        px = colx[x];
                        py = rowy[mid];
                        dc.fillRectangle(px, py, colx[x + 1] - px, rowy[yh + 1] - py);
                        if (dtrace != null) {
                            dtrace.addAll([0, x, mid, yh, bottomtexture, level]);
                        }
                        floorclip[x] = mid;
                    } else {
                        floorclip[x] = yh + 1;
                    }
                } else {
                    // no bottom wall
                    if (markfloor) {
                        floorclip[x] = yh + 1;
                    }
                }

                // save texturecol
                //  for backdrawing of masked mid texture
                // (maskedtexturecol[rw_x] = texturecolumn: texture
                // columns aren't tracked, masked mid textures aren't
                // drawn yet)
            }

            rw_scale += rw_scalestep;
            topfrac += topstep;
            bottomfrac += bottomstep;
        }
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
        work += stop - start + 1;
        if (trace != null) {
            trace.add(RBsp.curline);
            trace.add(start);
            trace.add(stop);
        }

        // don't overflow and crash
        if (ds_p == MAXDRAWSEGS) {
            return;
        }

        var curline = RBsp.curline;
        var frontsector = RBsp.frontsector;
        var backsector = RBsp.backsector;
        var sidedef = PSetup.segs_sidedef[curline];
        var linedef = PSetup.segs_linedef[curline];
        RBsp.sidedef = sidedef;
        RBsp.linedef = linedef;
        var viewz = RMain.viewz;

        // mark the segment as visible for auto map
        PSetup.lines_flags[linedef] |= DoomData.ML_MAPPED;

        // calculate rw_distance for scale calculation
        rw_normalangle = PSetup.segs_angle[curline] + Tables.ANG90;
        var offsetangle = MFixed.abs(rw_normalangle - rw_angle1);

        if (DoomType.UGT(offsetangle, Tables.ANG90)) {
            offsetangle = Tables.ANG90;
        }

        var distangle = Tables.ANG90 - offsetangle;
        var v1 = PSetup.segs_v1[curline];
        var hyp = RMain.R_PointToDist(PSetup.vertexes_x[v1], PSetup.vertexes_y[v1]);
        var sineval = Tables.finesine[(distangle >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK];
        rw_distance = MFixed.FixedMul(hyp, sineval);

        var ds = ds_p;
        rw_x = start;
        drawsegs_x1[ds] = start;
        drawsegs_x2[ds] = stop;
        drawsegs_curline[ds] = curline;
        rw_stopx = stop + 1;

        // calculate scale at both ends and step
        rw_scale = RMain.R_ScaleFromGlobalAngle(RMain.viewangle + RMain.xtoviewangle[start]);
        drawsegs_scale1[ds] = rw_scale;

        if (stop > start) {
            drawsegs_scale2[ds] = RMain.R_ScaleFromGlobalAngle(RMain.viewangle + RMain.xtoviewangle[stop]);
            rw_scalestep = (drawsegs_scale2[ds] - rw_scale) / (stop - start);
            drawsegs_scalestep[ds] = rw_scalestep;
        } else {
            drawsegs_scale2[ds] = drawsegs_scale1[ds];
            // rw_scalestep keeps its old value, as in the C code.
        }

        // calculate texture boundaries
        //  and decide if floor / ceiling marks are needed
        worldtop = PSetup.sectors_ceilingheight[frontsector] - viewz;
        worldbottom = PSetup.sectors_floorheight[frontsector] - viewz;

        midtexture = 0;
        toptexture = 0;
        bottomtexture = 0;
        maskedtexture = false;
        drawsegs_maskedtexturecol[ds] = -1;

        if (backsector == -1) {
            // single sided line
            midtexture = RData.texturetranslation[PSetup.sides_midtexture[sidedef]];
            // a single sided line is terminal, so it must mark ends
            markfloor = true;
            markceiling = true;
            // (rw_midtexturemid only matters for texturing)
            drawsegs_silhouette[ds] = SIL_BOTH;
            drawsegs_sprtopclip[ds] = SCREENHEIGHTARRAY;
            drawsegs_sprbottomclip[ds] = NEGONEARRAY;
            drawsegs_bsilheight[ds] = DoomType.MAXINT;
            drawsegs_tsilheight[ds] = DoomType.MININT;
        } else {
            var ffloor = PSetup.sectors_floorheight[frontsector];
            var fceil = PSetup.sectors_ceilingheight[frontsector];
            var bfloor = PSetup.sectors_floorheight[backsector];
            var bceil = PSetup.sectors_ceilingheight[backsector];

            // two sided line
            drawsegs_sprtopclip[ds] = -1;
            drawsegs_sprbottomclip[ds] = -1;
            drawsegs_silhouette[ds] = 0;

            if (ffloor > bfloor) {
                drawsegs_silhouette[ds] = SIL_BOTTOM;
                drawsegs_bsilheight[ds] = ffloor;
            } else if (bfloor > viewz) {
                drawsegs_silhouette[ds] = SIL_BOTTOM;
                drawsegs_bsilheight[ds] = DoomType.MAXINT;
            }

            if (fceil < bceil) {
                drawsegs_silhouette[ds] |= SIL_TOP;
                drawsegs_tsilheight[ds] = fceil;
            } else if (bceil < viewz) {
                drawsegs_silhouette[ds] |= SIL_TOP;
                drawsegs_tsilheight[ds] = DoomType.MININT;
            }

            if (bceil <= ffloor) {
                drawsegs_sprbottomclip[ds] = NEGONEARRAY;
                drawsegs_bsilheight[ds] = DoomType.MAXINT;
                drawsegs_silhouette[ds] |= SIL_BOTTOM;
            }

            if (bfloor >= fceil) {
                drawsegs_sprtopclip[ds] = SCREENHEIGHTARRAY;
                drawsegs_tsilheight[ds] = DoomType.MININT;
                drawsegs_silhouette[ds] |= SIL_TOP;
            }

            worldhigh = bceil - viewz;
            worldlow = bfloor - viewz;

            // hack to allow height changes in outdoor areas
            if (PSetup.sectors_ceilingpic[frontsector] == RData.skyflatnum
                && PSetup.sectors_ceilingpic[backsector] == RData.skyflatnum) {
                worldtop = worldhigh;
            }

            if (worldlow != worldbottom
                || PSetup.sectors_floorpic[backsector] != PSetup.sectors_floorpic[frontsector]
                || PSetup.sectors_lightlevel[backsector] != PSetup.sectors_lightlevel[frontsector]) {
                markfloor = true;
            } else {
                // same plane on both sides
                markfloor = false;
            }

            if (worldhigh != worldtop
                || PSetup.sectors_ceilingpic[backsector] != PSetup.sectors_ceilingpic[frontsector]
                || PSetup.sectors_lightlevel[backsector] != PSetup.sectors_lightlevel[frontsector]) {
                markceiling = true;
            } else {
                // same plane on both sides
                markceiling = false;
            }

            if (bceil <= ffloor || bfloor >= fceil) {
                // closed door
                markceiling = true;
                markfloor = true;
            }

            if (worldhigh < worldtop) {
                // top texture
                toptexture = RData.texturetranslation[PSetup.sides_toptexture[sidedef]];
            }
            if (worldlow > worldbottom) {
                // bottom texture
                bottomtexture = RData.texturetranslation[PSetup.sides_bottomtexture[sidedef]];
            }

            // allocate space for masked texture tables
            if (PSetup.sides_midtexture[sidedef] != 0) {
                // masked midtexture
                maskedtexture = true;
                drawsegs_maskedtexturecol[ds] = lastopening - rw_x;
                lastopening += rw_stopx - rw_x;
            }
        }

        // calculate rw_offset (only needed for textured lines)
        segtextured = midtexture != 0 || toptexture != 0 || bottomtexture != 0 || maskedtexture;

        if (segtextured) {
            // (rw_offset and rw_centerangle only matter for texturing)

            // calculate light table
            //  use different light tables
            //  for horizontal / vertical / diagonal
            // OPTIMIZE: get rid of LIGHTSEGSHIFT globally
            if (RMain.fixedcolormap < 0) {
                var lightnum = (PSetup.sectors_lightlevel[frontsector] >> RMain.LIGHTSEGSHIFT) + RMain.extralight;

                var v2 = PSetup.segs_v2[curline];
                if (PSetup.vertexes_y[v1] == PSetup.vertexes_y[v2]) {
                    lightnum--;
                } else if (PSetup.vertexes_x[v1] == PSetup.vertexes_x[v2]) {
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

        if (PSetup.sectors_floorheight[frontsector] >= viewz) {
            // above view plane
            markfloor = false;
        }

        if (PSetup.sectors_ceilingheight[frontsector] <= viewz
            && PSetup.sectors_ceilingpic[frontsector] != RData.skyflatnum) {
            // below view plane
            markceiling = false;
        }

        // calculate incremental stepping values for texture edges
        worldtop >>= 4;
        worldbottom >>= 4;

        var centeryfrac4 = RMain.centeryfrac >> 4;
        topstep = -MFixed.FixedMul(rw_scalestep, worldtop);
        topfrac = centeryfrac4 - MFixed.FixedMul(worldtop, rw_scale);

        bottomstep = -MFixed.FixedMul(rw_scalestep, worldbottom);
        bottomfrac = centeryfrac4 - MFixed.FixedMul(worldbottom, rw_scale);

        if (backsector != -1) {
            worldhigh >>= 4;
            worldlow >>= 4;

            if (worldhigh < worldtop) {
                pixhigh = centeryfrac4 - MFixed.FixedMul(worldhigh, rw_scale);
                pixhighstep = -MFixed.FixedMul(rw_scalestep, worldhigh);
            }

            if (worldlow > worldbottom) {
                pixlow = centeryfrac4 - MFixed.FixedMul(worldlow, rw_scale);
                pixlowstep = -MFixed.FixedMul(rw_scalestep, worldlow);
            }
        }

        // render it
        // (R_CheckPlane only splits visplanes' column lists, which
        // aren't kept here)
        R_RenderSegLoop();

        // save sprite clipping info
        if (((drawsegs_silhouette[ds] & SIL_TOP) != 0 || maskedtexture)
            && drawsegs_sprtopclip[ds] == -1) {
            drawsegs_sprtopclip[ds] = saveClip(RPlane.ceilingclip, start, rw_stopx - start);
        }

        if (((drawsegs_silhouette[ds] & SIL_BOTTOM) != 0 || maskedtexture)
            && drawsegs_sprbottomclip[ds] == -1) {
            drawsegs_sprbottomclip[ds] = saveClip(RPlane.floorclip, start, rw_stopx - start);
        }

        if (maskedtexture && (drawsegs_silhouette[ds] & SIL_TOP) == 0) {
            drawsegs_silhouette[ds] |= SIL_TOP;
            drawsegs_tsilheight[ds] = DoomType.MININT;
        }
        if (maskedtexture && (drawsegs_silhouette[ds] & SIL_BOTTOM) == 0) {
            drawsegs_silhouette[ds] |= SIL_BOTTOM;
            drawsegs_bsilheight[ds] = DoomType.MAXINT;
        }
        ds_p++;
    }
}
