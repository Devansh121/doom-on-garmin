// r_main.c / r_main.h
//
// Rendering main loop and setup functions,
//  utility functions (BSP, geometry, trigonometry).
// See tables.c, too.
//
// Angles are angle_t (unsigned) in the C code. They're plain Numbers here;
// add/sub wrap the same way, and every angle>>ANGLETOFINESHIFT is masked
// with FINEMASK so the arithmetic shift gives the same index as C's
// logical one.

import Toybox.Lang;

module RMain {

    // doomdef.h
    const SCREENWIDTH = 320;
    const SCREENHEIGHT = 200;

    // Fineangles in the SCREENWIDTH wide window.
    const FIELDOFVIEW = 2048;

    //
    // Lighting LUT.
    // Used for z-depth cuing per column/row,
    //  and other lighting effects (sector ambient, flash).
    //

    // Lighting constants.
    // Now why not 32 levels here?
    const LIGHTLEVELS = 16;
    const LIGHTSEGSHIFT = 4;

    const MAXLIGHTSCALE = 48;
    const LIGHTSCALESHIFT = 12;
    const MAXLIGHTZ = 128;
    const LIGHTZSHIFT = 20;

    // Number of diminishing brightness levels.
    // There a 0-31, i.e. 32 LUT in the COLORMAP lump.
    const NUMCOLORMAPS = 32;

    const DISTMAP = 2;

    // increment every time a check is made
    var validcount as Number = 1;

    var centerx as Number = 0;
    var centery as Number = 0;

    var centerxfrac as Number = 0;
    var centeryfrac as Number = 0;
    var projection as Number = 0;

    // just for profiling purposes
    var framecount as Number = 0;

    var sscount as Number = 0;
    var linecount as Number = 0;
    var loopcount as Number = 0;

    var viewx as Number = 0;
    var viewy as Number = 0;
    var viewz as Number = 0;

    var viewangle as Number = 0;

    var viewcos as Number = 0;
    var viewsin as Number = 0;

    // 0 = high, 1 = low
    var detailshift as Number = 0;

    var viewwidth as Number = 0;
    var scaledviewwidth as Number = 0;
    var viewheight as Number = 0;

    //
    // precalculated math tables
    //
    var clipangle as Number = 0;

    // The viewangletox[viewangle + FINEANGLES/4] lookup
    // maps the visible view angles to screen X coordinates,
    // flattening the arc to a flat projection plane.
    // There will be many angles mapped to the same X.
    var viewangletox as Array<Number> = new [Tables.FINEANGLES / 2] as Array<Number>;

    // The xtoviewangleangle[] table maps a screen pixel
    // to the lowest viewangle that maps back to x ranges
    // from clipangle to -clipangle.
    var xtoviewangle as Array<Number> = new [SCREENWIDTH + 1] as Array<Number>;

    // r_plane.c, but filled in by R_ExecuteSetViewSize.
    var yslope as Array<Number> = new [SCREENHEIGHT] as Array<Number>;
    var distscale as Array<Number> = new [SCREENWIDTH] as Array<Number>;

    // The light tables hold COLORMAP numbers instead of pointers into
    // colormaps. scalelight[i][j] is scalelight[i * MAXLIGHTSCALE + j],
    // zlight[i][j] is zlight[i * MAXLIGHTZ + j].
    var scalelight as Array<Number> = new [LIGHTLEVELS * MAXLIGHTSCALE] as Array<Number>;
    var scalelightfixed as Array<Number> = new [MAXLIGHTSCALE] as Array<Number>;
    var zlight as Array<Number> = new [LIGHTLEVELS * MAXLIGHTZ] as Array<Number>;

    // bumped light from gun blasts
    var extralight as Number = 0;

    // -1 when not using a fixed colormap (NULL in C)
    var fixedcolormap as Number = -1;

    var setsizeneeded as Boolean = false;
    var setblocks as Number = 0;
    var setdetail as Number = 0;

    //
    // R_PointOnSide
    // Traverse BSP (sub) tree,
    //  check point against partition plane.
    // Returns side 0 (front) or 1 (back).
    //
    function R_PointOnSide(x as Number, y as Number, node as Number) as Number {
        var ndx = PSetup.nodes_dx[node];
        var ndy = PSetup.nodes_dy[node];

        if (ndx == 0) {
            if (x <= PSetup.nodes_x[node]) {
                return ndy > 0 ? 1 : 0;
            }
            return ndy < 0 ? 1 : 0;
        }
        if (ndy == 0) {
            if (y <= PSetup.nodes_y[node]) {
                return ndx < 0 ? 1 : 0;
            }
            return ndx > 0 ? 1 : 0;
        }

        var dx = (x - PSetup.nodes_x[node]);
        var dy = (y - PSetup.nodes_y[node]);

        // Try to quickly decide by looking at sign bits.
        if (((ndy ^ ndx ^ dx ^ dy) & 0x80000000) != 0) {
            if (((ndy ^ dx) & 0x80000000) != 0) {
                // (left is negative)
                return 1;
            }
            return 0;
        }

        var left = MFixed.FixedMul(ndy >> MFixed.FRACBITS, dx);
        var right = MFixed.FixedMul(dy, ndx >> MFixed.FRACBITS);

        if (right < left) {
            // front side
            return 0;
        }
        // back side
        return 1;
    }

    function R_PointOnSegSide(x as Number, y as Number, line as Number) as Number {
        var lx = PSetup.vertexes_x[PSetup.segs_v1[line]];
        var ly = PSetup.vertexes_y[PSetup.segs_v1[line]];

        var ldx = PSetup.vertexes_x[PSetup.segs_v2[line]] - lx;
        var ldy = PSetup.vertexes_y[PSetup.segs_v2[line]] - ly;

        if (ldx == 0) {
            if (x <= lx) {
                return ldy > 0 ? 1 : 0;
            }
            return ldy < 0 ? 1 : 0;
        }
        if (ldy == 0) {
            if (y <= ly) {
                return ldx < 0 ? 1 : 0;
            }
            return ldx > 0 ? 1 : 0;
        }

        var dx = (x - lx);
        var dy = (y - ly);

        // Try to quickly decide by looking at sign bits.
        if (((ldy ^ ldx ^ dx ^ dy) & 0x80000000) != 0) {
            if (((ldy ^ dx) & 0x80000000) != 0) {
                // (left is negative)
                return 1;
            }
            return 0;
        }

        var left = MFixed.FixedMul(ldy >> MFixed.FRACBITS, dx);
        var right = MFixed.FixedMul(dy, ldx >> MFixed.FRACBITS);

        if (right < left) {
            // front side
            return 0;
        }
        // back side
        return 1;
    }

    //
    // R_PointToAngle
    // To get a global angle from cartesian coordinates,
    //  the coordinates are flipped until they are in
    //  the first octant of the coordinate system, then
    //  the y (<=x) is scaled and divided by x to get a
    //  tangent (slope) value which is looked up in the
    //  tantoangle[] table.
    //
    function R_PointToAngle(x as Number, y as Number) as Number {
        var tantoangle = Tables.tantoangle;
        x -= viewx;
        y -= viewy;

        if ((x == 0) && (y == 0)) {
            return 0;
        }

        if (x >= 0) {
            // x >=0
            if (y >= 0) {
                // y>= 0
                if (x > y) {
                    // octant 0
                    return tantoangle[Tables.SlopeDiv(y, x)];
                } else {
                    // octant 1
                    return Tables.ANG90 - 1 - tantoangle[Tables.SlopeDiv(x, y)];
                }
            } else {
                // y<0
                y = -y;

                if (x > y) {
                    // octant 8
                    return -tantoangle[Tables.SlopeDiv(y, x)];
                } else {
                    // octant 7
                    return Tables.ANG270 + tantoangle[Tables.SlopeDiv(x, y)];
                }
            }
        } else {
            // x<0
            x = -x;

            if (y >= 0) {
                // y>= 0
                if (x > y) {
                    // octant 3
                    return Tables.ANG180 - 1 - tantoangle[Tables.SlopeDiv(y, x)];
                } else {
                    // octant 2
                    return Tables.ANG90 + tantoangle[Tables.SlopeDiv(x, y)];
                }
            } else {
                // y<0
                y = -y;

                if (x > y) {
                    // octant 4
                    return Tables.ANG180 + tantoangle[Tables.SlopeDiv(y, x)];
                } else {
                    // octant 5
                    return Tables.ANG270 - 1 - tantoangle[Tables.SlopeDiv(x, y)];
                }
            }
        }
    }

    function R_PointToAngle2(x1 as Number, y1 as Number, x2 as Number, y2 as Number) as Number {
        viewx = x1;
        viewy = y1;

        return R_PointToAngle(x2, y2);
    }

    function R_PointToDist(x as Number, y as Number) as Number {
        var dx = MFixed.abs(x - viewx);
        var dy = MFixed.abs(y - viewy);

        if (dy > dx) {
            var temp = dx;
            dx = dy;
            dy = temp;
        }

        var angle = ((Tables.tantoangle[MFixed.FixedDiv(dy, dx) >> Tables.DBITS] + Tables.ANG90)
                     >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;

        // use as cosine
        return MFixed.FixedDiv(dx, Tables.finesine[angle]);
    }

    //
    // R_ScaleFromGlobalAngle
    // Returns the texture mapping scale
    //  for the current line (horizontal span)
    //  at the given angle.
    // rw_distance must be calculated first.
    //
    function R_ScaleFromGlobalAngle(visangle as Number) as Number {
        var anglea = Tables.ANG90 + (visangle - viewangle);
        var angleb = Tables.ANG90 + (visangle - RSegs.rw_normalangle);

        // both sines are allways positive
        var sinea = Tables.finesine[(anglea >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK];
        var sineb = Tables.finesine[(angleb >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK];
        var num = MFixed.FixedMul(projection, sineb) << detailshift;
        var den = MFixed.FixedMul(RSegs.rw_distance, sinea);

        var scale;
        if (den > num >> 16) {
            scale = MFixed.FixedDiv(num, den);

            if (scale > 64 * MFixed.FRACUNIT) {
                scale = 64 * MFixed.FRACUNIT;
            } else if (scale < 256) {
                scale = 256;
            }
        } else {
            scale = 64 * MFixed.FRACUNIT;
        }

        return scale;
    }

    //
    // R_InitTextureMapping
    //
    // Split in three so each part fits in a watchdog slice; run them in
    // order with R_InitTextureMapping_Angles over the whole table first.
    //
    var focallength as Number = 0;

    function R_InitTextureMapping_Angles(first as Number, last as Number) as Void {
        var finetangent = Tables.finetangent;
        var table = viewangletox;
        var cxfrac = centerxfrac;
        var vw = viewwidth;

        // Use tangent table to generate viewangletox:
        //  viewangletox will give the next greatest x
        //  after the view angle.
        //
        // Calc focallength
        //  so FIELDOFVIEW angles covers SCREENWIDTH.
        if (first == 0) {
            focallength = MFixed.FixedDiv(cxfrac, finetangent[Tables.FINEANGLES / 4 + FIELDOFVIEW / 2]);
        }
        var fl = focallength;

        for (var i = first; i < last; i++) {
            var t;
            if (finetangent[i] > MFixed.FRACUNIT * 2) {
                t = -1;
            } else if (finetangent[i] < -MFixed.FRACUNIT * 2) {
                t = vw + 1;
            } else {
                t = MFixed.FixedMul(finetangent[i], fl);
                t = (cxfrac - t + MFixed.FRACUNIT - 1) >> MFixed.FRACBITS;

                if (t < -1) {
                    t = -1;
                } else if (t > vw + 1) {
                    t = vw + 1;
                }
            }
            table[i] = t;
        }
    }

    function R_InitTextureMapping_X() as Void {
        var table = viewangletox;

        // Scan viewangletox[] to generate xtoviewangle[]:
        //  xtoviewangle will give the smallest view angle
        //  that maps to x.
        //
        // The C code restarts the scan at i = 0 for every x. viewangletox
        // never increases with i, so walking x downwards lets the scan
        // carry on where it left off, with the same result.
        var i = 0;
        for (var x = viewwidth; x >= 0; x--) {
            while (table[i] > x) {
                i++;
            }
            xtoviewangle[x] = (i << Tables.ANGLETOFINESHIFT) - Tables.ANG90;
        }
    }

    function R_InitTextureMapping_Fence(first as Number, last as Number) as Void {
        var table = viewangletox;
        var vw = viewwidth;

        // Take out the fencepost cases from viewangletox.
        for (var i = first; i < last; i++) {
            if (table[i] == -1) {
                table[i] = 0;
            } else if (table[i] == vw + 1) {
                table[i] = vw;
            }
        }

        clipangle = xtoviewangle[0];
    }

    //
    // R_InitLightTables
    // Only inits the zlight table,
    //  because the scalelight table changes with view size.
    //
    // Run for each light level i in turn.
    //
    function R_InitLightTables(i as Number) as Void {
        // Calculate the light levels to use
        //  for each level / distance combination.
        var startmap = ((LIGHTLEVELS - 1 - i) * 2) * NUMCOLORMAPS / LIGHTLEVELS;
        for (var j = 0; j < MAXLIGHTZ; j++) {
            var scale = MFixed.FixedDiv((SCREENWIDTH / 2 * MFixed.FRACUNIT), (j + 1) << LIGHTZSHIFT);
            scale >>= LIGHTSCALESHIFT;
            var level = startmap - scale / DISTMAP;

            if (level < 0) {
                level = 0;
            }

            if (level >= NUMCOLORMAPS) {
                level = NUMCOLORMAPS - 1;
            }

            zlight[i * MAXLIGHTZ + j] = level;
        }
    }

    //
    // R_SetViewSize
    // Do not really change anything here,
    //  because it might be in the middle of a refresh.
    // The change will take effect next refresh.
    //
    function R_SetViewSize(blocks as Number, detail as Number) as Void {
        setsizeneeded = true;
        setblocks = blocks;
        setdetail = detail;
    }

    //
    // R_ExecuteSetViewSize
    //
    // The texture mapping part is left to the caller (see R_InitStep),
    // since it needs several slices.
    //
    function R_ExecuteSetViewSize() as Void {
        setsizeneeded = false;

        if (setblocks == 11) {
            scaledviewwidth = SCREENWIDTH;
            viewheight = SCREENHEIGHT;
        } else {
            scaledviewwidth = setblocks * 32;
            viewheight = (setblocks * 168 / 10) & ~7;
        }

        detailshift = setdetail;
        viewwidth = scaledviewwidth >> detailshift;

        centery = viewheight / 2;
        centerx = viewwidth / 2;
        centerxfrac = centerx << MFixed.FRACBITS;
        centeryfrac = centery << MFixed.FRACBITS;
        projection = centerxfrac;

        // colfunc/spanfunc are always RDraw.R_DrawColumn, which already
        // sizes its columns from viewwidth.
        RDraw.R_InitBuffer(viewwidth, viewheight);
    }

    function R_ExecuteSetViewSize_Tables() as Void {
        // planes
        for (var i = 0; i < viewheight; i++) {
            var dy = ((i - viewheight / 2) << MFixed.FRACBITS) + MFixed.FRACUNIT / 2;
            dy = MFixed.abs(dy);
            yslope[i] = MFixed.FixedDiv((viewwidth << detailshift) / 2 * MFixed.FRACUNIT, dy);
        }

        for (var i = 0; i < viewwidth; i++) {
            var cosadj = MFixed.abs(Tables.finesine[Tables.FINECOSINE
                + ((xtoviewangle[i] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK)]);
            distscale[i] = MFixed.FixedDiv(MFixed.FRACUNIT, cosadj);
        }

        // Calculate the light levels to use
        //  for each level / scale combination.
        for (var i = 0; i < LIGHTLEVELS; i++) {
            var startmap = ((LIGHTLEVELS - 1 - i) * 2) * NUMCOLORMAPS / LIGHTLEVELS;
            for (var j = 0; j < MAXLIGHTSCALE; j++) {
                var level = startmap - j * SCREENWIDTH / (viewwidth << detailshift) / DISTMAP;

                if (level < 0) {
                    level = 0;
                }

                if (level >= NUMCOLORMAPS) {
                    level = NUMCOLORMAPS - 1;
                }

                scalelight[i * MAXLIGHTSCALE + j] = level;
            }
        }
    }

    //
    // R_Init
    //
    // R_Init runs as a series of steps, see R_InitStep.
    //
    var initstep as Number = 0;

    // Returns true once everything R_Init does is done.
    function R_InitStep() as Boolean {
        var s = initstep;
        initstep++;
        if (s == 0) {
            RData.R_InitData();

            // viewwidth / viewheight / detailLevel are set by the defaults
            R_SetViewSize(11, 1);
            R_ExecuteSetViewSize();
            return false;
        }
        // viewangletox in 8 slices of 512
        if (s <= 8) {
            R_InitTextureMapping_Angles((s - 1) * 512, s * 512);
            return false;
        }
        if (s == 9) {
            R_InitTextureMapping_X();
            R_InitTextureMapping_Fence(0, Tables.FINEANGLES / 2);
            // Nothing else reads finetangent until textured walls need
            // texturecolumn, so give its 20 KB back.
            Tables.finetangent = [] as Array<Number>;
            return false;
        }
        if (s == 10) {
            R_ExecuteSetViewSize_Tables();
            return false;
        }
        if (s < 11 + LIGHTLEVELS) {
            R_InitLightTables(s - 11);
            return false;
        }
        framecount = 0;
        return true;
    }

    //
    // R_PointInSubsector
    //
    function R_PointInSubsector(x as Number, y as Number) as Number {
        // single subsector is a special case
        if (PSetup.numnodes == 0) {
            return 0;
        }

        var nodenum = PSetup.numnodes - 1;

        while ((nodenum & DoomData.NF_SUBSECTOR) == 0) {
            var side = R_PointOnSide(x, y, nodenum);
            nodenum = PSetup.nodes_children[nodenum * 2 + side];
        }

        return nodenum & ~DoomData.NF_SUBSECTOR;
    }

    //
    // R_SetupFrame
    //
    // Takes the view position directly so tests can render from any spot;
    // R_RenderPlayerView fills it in from the player.
    //
    function R_SetupFrame(x as Number, y as Number, z as Number, angle as Number) as Void {
        viewx = x;
        viewy = y;
        viewangle = angle;
        extralight = 0;

        viewz = z;

        var fine = (viewangle >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        viewsin = Tables.finesine[fine];
        viewcos = Tables.finesine[Tables.FINECOSINE + fine];

        sscount = 0;

        fixedcolormap = -1;

        framecount++;
        validcount++;
    }

    //
    // R_RenderView
    //
    // Sets the frame up; R_RenderPlayerViewStep then does the drawing a
    // slice at a time.
    //
    function R_RenderPlayerView(player as Number) as Void {
        // R_SetupFrame (player)
        var mo = DPlayer.players_mo[player];
        R_SetupFrame(PMobj.mobjs_x[mo], PMobj.mobjs_y[mo], DPlayer.players_viewz[player], PMobj.mobjs_angle[mo]);
        extralight = DPlayer.players_extralight[player];
        // player->fixedcolormap is 0 for none; here -1 means none
        fixedcolormap = DPlayer.players_fixedcolormap[player] != 0 ? DPlayer.players_fixedcolormap[player] : -1;

        // Clear buffers.
        RBsp.R_ClearClipSegs();
        RBsp.R_ClearDrawSegs();
        RPlane.R_ClearPlanes();
        RSegs.work = 0;

        // The head node is the last node output.
        RBsp.R_RenderBSPNode(PSetup.numnodes - 1);
    }

    // Returns true once the frame is complete. R_DrawPlanes is folded
    // into r_segs, and R_DrawMasked comes with r_things.
    function R_RenderPlayerViewStep(budget as Number) as Boolean {
        return RBsp.R_RenderBSPNodeStep(RSegs.work + budget);
    }
}
