// r_things.c
//
// Refresh of things, i.e. objects represented by sprites.
//
// Differences from the C code:
//  - Sprites are drawn as whole bitmaps instead of column by column (a
//    Monkey C loop per pixel column is far too slow). R_DrawVisSprite
//    splits the sprite's columns into strips that share the same
//    cliptop / clipbot, clips the view bitmap's Dc to each strip and
//    draws the scaled patch there with drawBitmap2 and an
//    AffineTransform (a negative x scale when flipped). The patches are
//    PNGs made by tools/sprites2ciq.py, loaded on demand into a small
//    cache.
//  - The bitmaps are full bright (COLORMAP 0). Light diminishing is
//    approximated with drawBitmap2's tint, see lighttint.
//  - The sprite tables R_InitSprites builds (spritedef_t /
//    spriteframe_t) and R_InitSpriteLumps' sizes and offsets come
//    precomputed from tools/sprites2ciq.py (see its docstring for the
//    layout); R_InitSprites just loads them.
//  - vissprite_t is one array per field, indexed by vissprite number;
//    the sorted list's links are vissprites_next / _prev, with the list
//    heads stored as extra entries past MAXVISSPRITES.
//  - R_DrawMasked runs as R_DrawMaskedStep, resumable after the BSP so
//    the watchdog doesn't trip; it counts RSegs.work like the walls do.
//  - Masked mid textures (R_RenderMaskedSegRange) aren't drawn yet.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

module RThings {

    const MINZ = MFixed.FRACUNIT * 4;
    const BASEYCENTER = 100;

    // r_things.h has 128. Each vissprite costs 15 array slots of heap,
    // and E1 views have well under 64 sprites; past the limit sprites
    // are dropped, as in the C code.
    const MAXVISSPRITES = 64;

    // p_pspr.h
    const FF_FULLBRIGHT = 0x8000; // flag in thing->frame
    const FF_FRAMEMASK = 0x7fff;

    //
    // Sprite rotation 0 is facing the viewer,
    //  rotation 1 is one angle turn CLOCKWISE around the axis.
    // This is not the same as the angle,
    //  which increases counter clockwise (protractor).
    // There was a lot of stuff grabbed wrong, so I changed it...
    //
    var pspritescale as Number = 0;
    var pspriteiscale as Number = 0;

    // row of RMain.scalelight to use: spritelights[i] is
    // scalelight[spritelights + i]
    var spritelights as Number = 0;

    // negonearray and screenheightarray live at the start of
    // RSegs.openings (RSegs.NEGONEARRAY / RSegs.SCREENHEIGHTARRAY), so
    // drawseg clip lists can point at them like in the C code.

    //
    // INITIALIZATION FUNCTIONS
    //

    // variables used to look up
    //  and range check thing_t sprites patches
    // sprites / spriteframes, flattened by tools/sprites2ciq.py:
    //  spriteframes[s] .. spriteframes[s + 1] - 1 are sprite s's frames.
    //  A frame without rotations is (lump << 1 | flip) << 1; one with
    //  rotations is 1 | pos << 1, and rotation r's lump << 1 | flip is
    //  the 10-bit field r % 3 of spriteframes[pos + r / 3].
    //  R_SpriteFrameLump does the lookup.
    var spriteframes as Array<Number> = [] as Array<Number>;
    var numsprites as Number = 0;

    // r_data.c R_InitSpriteLumps: per lump
    //  width | (leftoffset + 256) << 8 | (topoffset + 256) << 17
    // in pixels. spritewidth[lump] is spritewidth(lump) and so on.
    var spritelumpinfo as Array<Number> = [] as Array<Number>;
    var numspritelumps as Number = 0;

    function spritewidth(lump as Number) as Number {
        return (spritelumpinfo[lump] & 0xff) << MFixed.FRACBITS;
    }

    function spriteoffset(lump as Number) as Number {
        return (((spritelumpinfo[lump] >> 8) & 0x1ff) - 256) << MFixed.FRACBITS;
    }

    function spritetopoffset(lump as Number) as Number {
        return (((spritelumpinfo[lump] >> 17) & 0x1ff) - 256) << MFixed.FRACBITS;
    }

    // sprframe->lump[rot] << 1 | sprframe->flip[rot] for frame entry
    // sprframe (rot is ignored without rotations, as lump[0] is used)
    function R_SpriteFrameLump(sprframe as Number, rot as Number) as Number {
        if ((sprframe & 1) == 0) {
            return sprframe >> 1;
        }
        return (spriteframes[(sprframe >> 1) + rot / 3] >> ((rot % 3) * 10)) & 0x3ff;
    }

    //
    // R_InitSprites
    // Called at program start.
    //
    // namelist is only checked against the tables: R_InitSpriteDefs ran
    // in tools/sprites2ciq.py over the same sprnames.
    //
    function R_InitSprites(namelist as Array<String>) as Void {
        var openings = RSegs.openings;
        for (var i = 0; i < RMain.SCREENWIDTH; i++) {
            // negonearray[i] = -1;
            openings[RSegs.NEGONEARRAY + i] = 0;
        }

        // R_InitSpriteLumps
        spritelumpinfo = WatchUi.loadResource(Rez.JsonData.spritelumpinfo) as Array<Number>;
        numspritelumps = spritelumpinfo.size();

        // R_InitSpriteDefs
        spriteframes = WatchUi.loadResource(Rez.JsonData.spriteframes) as Array<Number>;
        numsprites = namelist.size();
        if (spriteframes[0] != numsprites + 1) {
            ISystem.I_Error("R_InitSprites: sprite tables don't match sprnames");
        }

        R_ClearSpriteCache();
        R_InitLightTint();
    }

    //
    // GAME FUNCTIONS
    //
    // vissprite_t, one array per field. Index MAXVISSPRITES is the
    // unsorted list head, MAXVISSPRITES + 1 vsprsortedhead and
    // MAXVISSPRITES + 2 overflowsprite.
    const UNSORTED = MAXVISSPRITES;
    const VSPRSORTEDHEAD = MAXVISSPRITES + 1;
    const OVERFLOWSPRITE = MAXVISSPRITES + 2;
    const VISSIZE = MAXVISSPRITES + 3;

    // Doubly linked list.
    var vissprites_prev as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_next as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_x1 as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_x2 as Array<Number> = new [VISSIZE] as Array<Number>;
    // for line side calculation
    var vissprites_gx as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_gy as Array<Number> = new [VISSIZE] as Array<Number>;
    // global bottom / top for silhouette clipping
    var vissprites_gz as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_gzt as Array<Number> = new [VISSIZE] as Array<Number>;
    // horizontal position of x1
    var vissprites_startfrac as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_scale as Array<Number> = new [VISSIZE] as Array<Number>;
    // negative if flipped
    var vissprites_xiscale as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_texturemid as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_patch as Array<Number> = new [VISSIZE] as Array<Number>;
    // for color translation and shadow draw,
    //  maxbright frames as well
    // A COLORMAP number; -1 is NULL (shadow draw).
    var vissprites_colormap as Array<Number> = new [VISSIZE] as Array<Number>;
    var vissprites_mobjflags as Array<Number> = new [VISSIZE] as Array<Number>;

    // index of the next free vissprite
    var vissprite_p as Number = 0;

    //
    // R_ClearSprites
    // Called at frame start.
    //
    function R_ClearSprites() as Void {
        vissprite_p = 0;
        maskedphase = MP_SORT;
        sortstarted = false;
    }

    //
    // R_NewVisSprite
    //
    function R_NewVisSprite() as Number {
        if (vissprite_p == MAXVISSPRITES) {
            return OVERFLOWSPRITE;
        }

        vissprite_p++;
        return vissprite_p - 1;
    }

    //
    // Sprite bitmaps: W_CacheLumpNum for sprite lumps. A few recently
    // used patches are kept loaded, replaced round robin.
    //
    // Each loaded bitmap costs a few hundred bytes of heap (its pixels
    // go to the graphics pool).
    const CACHESIZE = 16;
    var cachelump as Array<Number> = new [CACHESIZE] as Array<Number>;
    var cachebitmap as Array<Graphics.BitmapType?> = new [CACHESIZE] as Array<Graphics.BitmapType?>;
    var cachenext as Number = 0;

    function R_ClearSpriteCache() as Void {
        for (var i = 0; i < CACHESIZE; i++) {
            cachelump[i] = -1;
            cachebitmap[i] = null;
        }
        cachenext = 0;
    }

    function R_CacheSpriteLump(lump as Number) as Graphics.BitmapType {
        var lumps = cachelump;
        for (var i = 0; i < CACHESIZE; i++) {
            if (lumps[i] == lump) {
                return cachebitmap[i] as Graphics.BitmapType;
            }
        }
        var i = cachenext;
        cachenext = (i + 1) % CACHESIZE;
        // drop the old one first so both aren't loaded at once
        cachebitmap[i] = null;
        var bitmap = WatchUi.loadResource(SpriteLumps.W_SpriteLumpId(lump)) as Graphics.BitmapType;
        lumps[i] = lump;
        cachebitmap[i] = bitmap;
        return bitmap;
    }

    //
    // Lighting. The patches are full bright; a COLORMAP level is
    // approximated by tinting with the gray that COLORMAP's darkening
    // gives white at that level (lighttint[level]). Level 0 draws
    // untinted.
    //
    var lighttint as Array<Number> = [] as Array<Number>;

    function R_InitLightTint() as Void {
        lighttint = new [RMain.NUMCOLORMAPS] as Array<Number>;
        for (var i = 0; i < RMain.NUMCOLORMAPS; i++) {
            // COLORMAP level i scales brightness by about (32 - i) / 32
            var g = 255 * (RMain.NUMCOLORMAPS - i) / RMain.NUMCOLORMAPS;
            lighttint[i] = (g << 16) | (g << 8) | g;
        }
    }

    // mfloorclip / mceilingclip: the clip arrays R_DrawVisSprite uses,
    // or null for the whole view height (screenheightarray /
    // negonearray, as for psprites).
    // (clipbot / cliptop: ByteArrays holding value + 2, see R_DrawSprite)
    var mfloorclip as ByteArray? = null;
    var mceilingclip as ByteArray? = null;

    var spryscale as Number = 0;
    var sprtopscreen as Number = 0;

    var transform as Graphics.AffineTransform? = null;

    // When set, R_DrawVisSprite appends [patch, x1, x2, top, bottom] for
    // every strip it draws, for tests.
    var drawtrace as Array<Number>? = null;

    //
    // R_DrawVisSprite
    //  mfloorclip and mceilingclip should also be set.
    //
    // R_DrawMaskedColumn's job is done per strip of columns, see the
    // header comment.
    //
    function R_DrawVisSprite(vis as Number, x1 as Number, x2 as Number) as Void {
        var patch = vissprites_patch[vis];
        var bitmap = R_CacheSpriteLump(patch);
        var colormap = vissprites_colormap[vis];

        var dc_texturemid = vissprites_texturemid[vis];
        var xiscale = vissprites_xiscale[vis];
        spryscale = vissprites_scale[vis];
        sprtopscreen = RMain.centeryfrac - MFixed.FixedMul(dc_texturemid, spryscale);

        // Texture column frac = startfrac + (x - x1) * xiscale at the
        // left edge of view column x, so texel u starts at view column
        // x1 + (u - startfrac) / xiscale; texel row v starts at view row
        // (sprtopscreen + v * spryscale) >> FRACBITS. Map both to view
        // bitmap pixels.
        var colw = RDraw.VIEW_W.toFloat() / RMain.viewwidth;
        var rowh = RDraw.VIEW_H.toFloat() / RMain.viewheight;
        var xi = xiscale.toFloat();
        var m00 = colw * MFixed.FRACUNIT / xi;
        var m02 = colw * (vissprites_x1[vis] - vissprites_startfrac[vis] / xi);
        var m11 = rowh * spryscale / MFixed.FRACUNIT;
        var m12 = rowh * sprtopscreen / MFixed.FRACUNIT;
        var t = transform;
        if (t == null) {
            t = new Graphics.AffineTransform();
            transform = t;
        }
        t.setMatrix([m00, 0.0, m02, 0.0, m11, m12]);

        var options;
        if (colormap == 0) {
            options = {:transform => t};
        } else if (colormap < 0) {
            // NULL colormap = shadow draw (R_DrawFuzzColumn): a dark
            // shape stands in for the fuzz effect
            options = {:transform => t, :tintColor => 0x202020};
        } else {
            options = {:transform => t, :tintColor => lighttint[colormap]};
        }

        // Rows the patch covers; clip limits outside them don't matter,
        // which lets unclipped columns merge into one strip.
        var ptop = (sprtopscreen >> MFixed.FRACBITS) - 1;
        var height = bitmap.getHeight();
        var pbottom = ((sprtopscreen + spryscale * height) >> MFixed.FRACBITS) + 1;

        var dc = RDraw.dc as Graphics.Dc;
        var colx = RDraw.colx;
        var rowy = RDraw.rowy;
        var viewheight = RMain.viewheight;
        var floorclip = mfloorclip;
        var ceilingclip = mceilingclip;
        var trace = drawtrace;
        var strips = 0;

        var x = x1;
        while (x <= x2) {
            var top = ceilingclip != null ? ceilingclip[x] - 2 : -1;
            var bottom = floorclip != null ? floorclip[x] - 2 : viewheight;
            if (top < ptop) {
                top = ptop;
            }
            if (bottom > pbottom) {
                bottom = pbottom;
            }
            var xe = x + 1;
            if (ceilingclip != null && floorclip != null) {
                while (xe <= x2) {
                    var t2 = ceilingclip[xe] - 2;
                    var b2 = floorclip[xe] - 2;
                    if (t2 < ptop) {
                        t2 = ptop;
                    }
                    if (b2 > pbottom) {
                        b2 = pbottom;
                    }
                    if (t2 != top || b2 != bottom) {
                        break;
                    }
                    xe++;
                }
            } else {
                xe = x2 + 1;
            }

            // rows top + 1 .. bottom - 1 are open
            if (top < -1) {
                top = -1;
            }
            if (bottom > viewheight) {
                bottom = viewheight;
            }
            if (top + 1 < bottom) {
                var px = colx[x];
                var py = rowy[top + 1];
                dc.setClip(px, py, colx[xe] - px, rowy[bottom] - py);
                dc.drawBitmap2(0, 0, bitmap, options);
                strips++;
                if (trace != null) {
                    trace.addAll([patch, x, xe - 1, top, bottom]);
                }
            }
            x = xe;
        }
        dc.clearClip();
        RSegs.work += 2 + strips * 2 + (x2 - x1 + 1) / 8;
    }

    //
    // R_ProjectSprite
    // Generates a vissprite for a thing
    //  if it might be visible.
    //
    function R_ProjectSprite(thing as Number) as Void {
        var thingx = PMobj.mobjs_x[thing];
        var thingy = PMobj.mobjs_y[thing];
        var viewcos = RMain.viewcos;
        var viewsin = RMain.viewsin;

        // transform the origin point
        var tr_x = thingx - RMain.viewx;
        var tr_y = thingy - RMain.viewy;

        var gxt = MFixed.FixedMul(tr_x, viewcos);
        var gyt = -MFixed.FixedMul(tr_y, viewsin);

        var tz = gxt - gyt;

        // thing is behind view plane?
        if (tz < MINZ) {
            return;
        }

        var xscale = MFixed.FixedDiv(RMain.projection, tz);

        gxt = -MFixed.FixedMul(tr_x, viewsin);
        gyt = MFixed.FixedMul(tr_y, viewcos);
        var tx = -(gyt + gxt);

        // too far off the side?
        if (MFixed.abs(tx) > (tz << 2)) {
            return;
        }

        // decide which patch to use for sprite relative to player
        var sprite = PMobj.mobjs_sprite[thing];
        var frame = PMobj.mobjs_frame[thing];
        var sf = spriteframes;
        if (sprite < 0 || sprite >= numsprites) {
            ISystem.I_Error("R_ProjectSprite: invalid sprite number " + sprite);
        }
        var sprdef = sf[sprite];
        if ((frame & FF_FRAMEMASK) >= sf[sprite + 1] - sprdef) {
            ISystem.I_Error("R_ProjectSprite: invalid sprite frame " + sprite + " : " + frame);
        }
        var sprframe = sf[sprdef + (frame & FF_FRAMEMASK)];

        var entry;
        if ((sprframe & 1) != 0) {
            // choose a different rotation based on player view
            var ang = RMain.R_PointToAngle(thingx, thingy);
            var rot = DoomType.USHR(ang - PMobj.mobjs_angle[thing] + (Tables.ANG45 / 2) * 9, 29);
            entry = R_SpriteFrameLump(sprframe, rot);
        } else {
            // use single rotation for all views
            entry = R_SpriteFrameLump(sprframe, 0);
        }
        var lump = entry >> 1;
        var flip = (entry & 1) != 0;

        // calculate edges of the shape
        tx -= spriteoffset(lump);
        var x1 = (RMain.centerxfrac + MFixed.FixedMul(tx, xscale)) >> MFixed.FRACBITS;

        // off the right side?
        if (x1 > RMain.viewwidth) {
            return;
        }

        tx += spritewidth(lump);
        var x2 = ((RMain.centerxfrac + MFixed.FixedMul(tx, xscale)) >> MFixed.FRACBITS) - 1;

        // off the left side
        if (x2 < 0) {
            return;
        }

        // store information in a vissprite
        var vis = R_NewVisSprite();
        var flags = PMobj.mobjs_flags[thing];
        vissprites_mobjflags[vis] = flags;
        vissprites_scale[vis] = xscale << RMain.detailshift;
        vissprites_gx[vis] = thingx;
        vissprites_gy[vis] = thingy;
        var gz = PMobj.mobjs_z[thing];
        vissprites_gz[vis] = gz;
        vissprites_gzt[vis] = gz + spritetopoffset(lump);
        vissprites_texturemid[vis] = vissprites_gzt[vis] - RMain.viewz;
        var vx1 = x1 < 0 ? 0 : x1;
        vissprites_x1[vis] = vx1;
        vissprites_x2[vis] = x2 >= RMain.viewwidth ? RMain.viewwidth - 1 : x2;
        var iscale = MFixed.FixedDiv(MFixed.FRACUNIT, xscale);

        var startfrac;
        var xiscale;
        if (flip) {
            startfrac = spritewidth(lump) - 1;
            xiscale = -iscale;
        } else {
            startfrac = 0;
            xiscale = iscale;
        }

        if (vx1 > x1) {
            startfrac += xiscale * (vx1 - x1);
        }
        vissprites_startfrac[vis] = startfrac;
        vissprites_xiscale[vis] = xiscale;
        vissprites_patch[vis] = lump;

        // get light level
        if ((flags & PMobj.MF_SHADOW) != 0) {
            // shadow draw
            vissprites_colormap[vis] = -1;
        } else if (RMain.fixedcolormap >= 0) {
            // fixed map
            vissprites_colormap[vis] = RMain.fixedcolormap;
        } else if ((frame & FF_FULLBRIGHT) != 0) {
            // full bright
            vissprites_colormap[vis] = 0;
        } else {
            // diminished light
            var index = xscale >> (RMain.LIGHTSCALESHIFT - RMain.detailshift);

            if (index >= RMain.MAXLIGHTSCALE) {
                index = RMain.MAXLIGHTSCALE - 1;
            }

            vissprites_colormap[vis] = RMain.scalelight[spritelights + index];
        }
    }

    //
    // R_AddSprites
    // During BSP traversal, this adds sprites by sector.
    //
    function R_AddSprites(sec as Number) as Void {
        // BSP is traversed by subsector.
        // A sector might have been split into several
        //  subsectors during BSP building.
        // Thus we check whether its already added.
        if (PSetup.sectors_validcount[sec] == RMain.validcount) {
            return;
        }

        // Well, now it will be done.
        PSetup.sectors_validcount[sec] = RMain.validcount;

        var lightnum = (PSetup.sectors_lightlevel[sec] >> RMain.LIGHTSEGSHIFT) + RMain.extralight;

        if (lightnum < 0) {
            spritelights = 0;
        } else if (lightnum >= RMain.LIGHTLEVELS) {
            spritelights = (RMain.LIGHTLEVELS - 1) * RMain.MAXLIGHTSCALE;
        } else {
            spritelights = lightnum * RMain.MAXLIGHTSCALE;
        }

        // Handle all things in sector.
        var snext = PMobj.mobjs_snext;
        for (var thing = PSetup.sectors_thinglist[sec]; thing != -1; thing = snext[thing]) {
            R_ProjectSprite(thing);
            RSegs.work += 3;
        }
    }

    //
    // R_DrawPSprite
    //
    function R_DrawPSprite(psp as Number) as Void {
        var states = Info.states;
        var st = DPlayer.players_psprites_state[psp] * Info.ST_SIZE;
        var sprite = states[st + Info.ST_SPRITE];
        var frame = states[st + Info.ST_FRAME];
        var sf = spriteframes;

        // decide which patch to use
        if (sprite < 0 || sprite >= numsprites) {
            ISystem.I_Error("R_ProjectSprite: invalid sprite number " + sprite);
        }
        var sprdef = sf[sprite];
        if ((frame & FF_FRAMEMASK) >= sf[sprite + 1] - sprdef) {
            ISystem.I_Error("R_ProjectSprite: invalid sprite frame " + sprite + " : " + frame);
        }
        var sprframe = sf[sprdef + (frame & FF_FRAMEMASK)];

        var entry = R_SpriteFrameLump(sprframe, 0);
        var lump = entry >> 1;
        var flip = (entry & 1) != 0;

        // calculate edges of the shape
        var tx = DPlayer.players_psprites_sx[psp] - 160 * MFixed.FRACUNIT;

        tx -= spriteoffset(lump);
        var x1 = (RMain.centerxfrac + MFixed.FixedMul(tx, pspritescale)) >> MFixed.FRACBITS;

        // off the right side
        if (x1 > RMain.viewwidth) {
            return;
        }

        tx += spritewidth(lump);
        var x2 = ((RMain.centerxfrac + MFixed.FixedMul(tx, pspritescale)) >> MFixed.FRACBITS) - 1;

        // off the left side
        if (x2 < 0) {
            return;
        }

        // store information in a vissprite
        // (vis = &avis: the overflow slot isn't in any list, so it
        // serves as the local avis)
        var vis = OVERFLOWSPRITE;
        vissprites_mobjflags[vis] = 0;
        vissprites_texturemid[vis] = (BASEYCENTER << MFixed.FRACBITS) + MFixed.FRACUNIT / 2
            - (DPlayer.players_psprites_sy[psp] - spritetopoffset(lump));
        var vx1 = x1 < 0 ? 0 : x1;
        vissprites_x1[vis] = vx1;
        vissprites_x2[vis] = x2 >= RMain.viewwidth ? RMain.viewwidth - 1 : x2;
        vissprites_scale[vis] = pspritescale << RMain.detailshift;

        var startfrac;
        var xiscale;
        if (flip) {
            xiscale = -pspriteiscale;
            startfrac = spritewidth(lump) - 1;
        } else {
            xiscale = pspriteiscale;
            startfrac = 0;
        }

        if (vx1 > x1) {
            startfrac += xiscale * (vx1 - x1);
        }
        vissprites_startfrac[vis] = startfrac;
        vissprites_xiscale[vis] = xiscale;

        vissprites_patch[vis] = lump;

        var player = RMain.viewplayer;
        var invis = DPlayer.players_powers[player * DoomDef.NUMPOWERS + DoomDef.pw_invisibility];
        if (invis > 4 * 32 || (invis & 8) != 0) {
            // shadow draw
            vissprites_colormap[vis] = -1;
        } else if (RMain.fixedcolormap >= 0) {
            // fixed color
            vissprites_colormap[vis] = RMain.fixedcolormap;
        } else if ((frame & FF_FULLBRIGHT) != 0) {
            // full bright
            vissprites_colormap[vis] = 0;
        } else {
            // local light
            vissprites_colormap[vis] = RMain.scalelight[spritelights + RMain.MAXLIGHTSCALE - 1];
        }

        R_DrawVisSprite(vis, vissprites_x1[vis], vissprites_x2[vis]);
    }

    //
    // R_DrawPlayerSprites
    //
    function R_DrawPlayerSprites() as Void {
        var player = RMain.viewplayer;

        // get light level
        var mo = DPlayer.players_mo[player];
        var sector = PSetup.subsectors_sector[PMobj.mobjs_subsector[mo]];
        var lightnum = (PSetup.sectors_lightlevel[sector] >> RMain.LIGHTSEGSHIFT) + RMain.extralight;

        if (lightnum < 0) {
            spritelights = 0;
        } else if (lightnum >= RMain.LIGHTLEVELS) {
            spritelights = (RMain.LIGHTLEVELS - 1) * RMain.MAXLIGHTSCALE;
        } else {
            spritelights = lightnum * RMain.MAXLIGHTSCALE;
        }

        // clip to screen bounds
        mfloorclip = null;
        mceilingclip = null;

        // add all active psprites
        for (var i = 0; i < DPlayer.NUMPSPRITES; i++) {
            var psp = player * DPlayer.NUMPSPRITES + i;
            var state = DPlayer.players_psprites_state[psp];
            // (state is null before P_SetupPsprites ever ran)
            if (state != null && state >= 0) {
                R_DrawPSprite(psp);
            }
        }
    }

    //
    // R_SortVisSprites
    //
    // Resumable: R_SortVisSpritesStart links the list, then each
    // R_SortVisSpritesStep pulls out one sprite (the C loop body over i).
    //
    var sortcount as Number = 0;
    var sorti as Number = 0;

    function R_SortVisSpritesStart() as Void {
        var next = vissprites_next;
        var prev = vissprites_prev;
        var count = vissprite_p;
        sortcount = count;
        sorti = 0;

        next[UNSORTED] = UNSORTED;
        prev[UNSORTED] = UNSORTED;

        // pull the vissprites out by scale
        next[VSPRSORTEDHEAD] = VSPRSORTEDHEAD;
        prev[VSPRSORTEDHEAD] = VSPRSORTEDHEAD;

        if (count == 0) {
            return;
        }

        for (var ds = 0; ds < count; ds++) {
            next[ds] = ds + 1;
            prev[ds] = ds - 1;
        }

        prev[0] = UNSORTED;
        next[UNSORTED] = 0;
        next[count - 1] = UNSORTED;
        prev[UNSORTED] = count - 1;
    }

    // Returns true once all are sorted.
    function R_SortVisSpritesStep() as Boolean {
        if (sorti >= sortcount) {
            return true;
        }
        sorti++;
        var next = vissprites_next;
        var prev = vissprites_prev;
        var scale = vissprites_scale;

        var bestscale = DoomType.MAXINT;
        var best = 0;
        var n = 0;
        for (var ds = next[UNSORTED]; ds != UNSORTED; ds = next[ds]) {
            if (scale[ds] < bestscale) {
                bestscale = scale[ds];
                best = ds;
            }
            n++;
        }
        prev[next[best]] = prev[best];
        next[prev[best]] = next[best];
        next[best] = VSPRSORTEDHEAD;
        prev[best] = prev[VSPRSORTEDHEAD];
        next[prev[VSPRSORTEDHEAD]] = best;
        prev[VSPRSORTEDHEAD] = best;
        RSegs.work += 1 + n / 8;
        return sorti >= sortcount;
    }

    //
    // R_DrawSprite
    //
    // clipbot / cliptop are locals in the C code. They're ByteArrays
    // holding value + 2 (values run from -2, "not set yet", to
    // viewheight) to save heap.
    var clipbot as ByteArray = new [RMain.SCREENWIDTH]b;
    var cliptop as ByteArray = new [RMain.SCREENWIDTH]b;

    function R_DrawSprite(spr as Number) as Void {
        R_ClipSprite(spr);

        mfloorclip = clipbot;
        mceilingclip = cliptop;
        R_DrawVisSprite(spr, vissprites_x1[spr], vissprites_x2[spr]);
    }

    // The clipping half of R_DrawSprite: fills clipbot / cliptop for
    // spr's columns.
    function R_ClipSprite(spr as Number) as Void {
        var cb = clipbot;
        var ct = cliptop;
        var sx1 = vissprites_x1[spr];
        var sx2 = vissprites_x2[spr];
        var sprscale = vissprites_scale[spr];
        var gz = vissprites_gz[spr];
        var gzt = vissprites_gzt[spr];

        var ds_x1 = RSegs.drawsegs_x1;
        var ds_x2 = RSegs.drawsegs_x2;
        var ds_silhouette = RSegs.drawsegs_silhouette;
        var ds_maskedtexturecol = RSegs.drawsegs_maskedtexturecol;
        var ds_scale1 = RSegs.drawsegs_scale1;
        var ds_scale2 = RSegs.drawsegs_scale2;
        var openings = RSegs.openings;

        for (var x = sx1; x <= sx2; x++) {
            // clipbot[x] = cliptop[x] = -2;
            cb[x] = 0;
            ct[x] = 0;
        }

        // Scan drawsegs from end to start for obscuring segs.
        // The first drawseg that has a greater scale
        //  is the clip seg.
        var ds;
        for (ds = RSegs.ds_p - 1; ds >= 0; ds--) {
            // determine if the drawseg obscures the sprite
            if (ds_x1[ds] > sx2
                || ds_x2[ds] < sx1
                || (ds_silhouette[ds] == 0
                    && ds_maskedtexturecol[ds] == -1)) {
                // does not cover sprite
                continue;
            }

            var r1 = ds_x1[ds] < sx1 ? sx1 : ds_x1[ds];
            var r2 = ds_x2[ds] > sx2 ? sx2 : ds_x2[ds];

            var lowscale;
            var scale;
            if (ds_scale1[ds] > ds_scale2[ds]) {
                lowscale = ds_scale2[ds];
                scale = ds_scale1[ds];
            } else {
                lowscale = ds_scale1[ds];
                scale = ds_scale2[ds];
            }

            if (scale < sprscale
                || (lowscale < sprscale
                    && RMain.R_PointOnSegSide(vissprites_gx[spr], vissprites_gy[spr], RSegs.drawsegs_curline[ds]) == 0)) {
                // masked mid texture?
                // (R_RenderMaskedSegRange (ds, r1, r2) isn't ported:
                // masked mid textures aren't drawn yet)

                // seg is behind sprite
                continue;
            }

            // clip this piece of the sprite
            var silhouette = ds_silhouette[ds];

            // (bsilheight / tsilheight are only set with their
            // silhouette bit; unset they're null, not stale like in C, so
            // only compare when the bit is there to clear)
            if ((silhouette & RSegs.SIL_BOTTOM) != 0 && gz >= RSegs.drawsegs_bsilheight[ds]) {
                silhouette &= ~RSegs.SIL_BOTTOM;
            }

            if ((silhouette & RSegs.SIL_TOP) != 0 && gzt <= RSegs.drawsegs_tsilheight[ds]) {
                silhouette &= ~RSegs.SIL_TOP;
            }

            // openings hold value + 1 (see RSegs) and clipbot / cliptop
            // value + 2, so a copied value goes up by one; == 0 is == -2
            if (silhouette == 1) {
                // bottom sil
                var bot = RSegs.drawsegs_sprbottomclip[ds];
                for (var x = r1; x <= r2; x++) {
                    if (cb[x] == 0) {
                        cb[x] = openings[bot + x] + 1;
                    }
                }
            } else if (silhouette == 2) {
                // top sil
                var top = RSegs.drawsegs_sprtopclip[ds];
                for (var x = r1; x <= r2; x++) {
                    if (ct[x] == 0) {
                        ct[x] = openings[top + x] + 1;
                    }
                }
            } else if (silhouette == 3) {
                // both
                var bot = RSegs.drawsegs_sprbottomclip[ds];
                var top = RSegs.drawsegs_sprtopclip[ds];
                for (var x = r1; x <= r2; x++) {
                    if (cb[x] == 0) {
                        cb[x] = openings[bot + x] + 1;
                    }
                    if (ct[x] == 0) {
                        ct[x] = openings[top + x] + 1;
                    }
                }
            }
            RSegs.work += (r2 - r1) / 16;
        }

        // all clipping has been performed, so draw the sprite

        // check for unclipped columns
        var viewheight = RMain.viewheight;
        for (var x = sx1; x <= sx2; x++) {
            if (cb[x] == 0) {
                cb[x] = viewheight + 2;
            }

            if (ct[x] == 0) {
                // -1
                ct[x] = 1;
            }
        }
        RSegs.work += 1 + RSegs.ds_p / 8 + (sx2 - sx1 + 1) / 8;
    }

    //
    // R_DrawMasked
    //
    // As steps: sort, then the sprites back to front, then the
    // psprites. R_ClearSprites starts it over.
    //
    const MP_SORT = 0;
    const MP_SPRITES = 1;
    const MP_PSPRITES = 2;
    const MP_DONE = 3;
    var maskedphase as Number = MP_SORT;
    var sortstarted as Boolean = false;
    var maskedspr as Number = 0;

    // Draws until RSegs.work reaches budget (returns false, call again)
    // or everything is drawn (returns true).
    function R_DrawMaskedStep(budget as Number) as Boolean {
        if (maskedphase == MP_SORT) {
            if (!sortstarted) {
                R_SortVisSpritesStart();
                sortstarted = true;
            }
            while (!R_SortVisSpritesStep()) {
                if (RSegs.work >= budget) {
                    return false;
                }
            }
            maskedphase = MP_SPRITES;
            maskedspr = vissprites_next[VSPRSORTEDHEAD];
        }

        if (maskedphase == MP_SPRITES) {
            // draw all vissprites back to front
            while (maskedspr != VSPRSORTEDHEAD) {
                if (RSegs.work >= budget) {
                    return false;
                }
                R_DrawSprite(maskedspr);
                maskedspr = vissprites_next[maskedspr];
            }

            // render any remaining masked mid textures
            // (R_RenderMaskedSegRange isn't ported yet)

            maskedphase = MP_PSPRITES;
        }

        if (maskedphase == MP_PSPRITES) {
            if (RSegs.work >= budget) {
                return false;
            }
            // draw the psprites on top of everything
            //  but does not draw on side views
            R_DrawPlayerSprites();
            maskedphase = MP_DONE;
        }
        return true;
    }
}
