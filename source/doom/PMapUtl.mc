// p_maputl.c
//
// DESCRIPTION:
//	Movement/collision utility functions,
//	as used by function in p_map.c.
//	BLOCKMAP Iterator functions,
//	and some PIT_* functions to use for iteration.
//
// Only the parts that need nothing but map geometry are here.
// P_UnsetThingPosition, P_SetThingPosition, P_BlockThingsIterator, the
// intercepts list, PIT_AddLineIntercepts, PIT_AddThingIntercepts,
// P_TraverseIntercepts and P_PathTraverse all need mobj_t, so they come
// with p_mobj.
//
// line_t* arguments are line numbers into the PSetup lines_* arrays.
// A divline_t {x, y, dx, dy} is a 4 element Array<Number>, indexed with
// the DL_* constants below.

import Toybox.Lang;

module PMapUtl {

    // divline_t fields
    const DL_X = 0;
    const DL_Y = 1;
    const DL_DX = 2;
    const DL_DY = 3;

    //
    // P_AproxDistance
    // Gives an estimation of distance (not exact)
    //
    function P_AproxDistance(dx as Number, dy as Number) as Number {
        dx = MFixed.abs(dx);
        dy = MFixed.abs(dy);
        if (dx < dy) {
            return dx + dy - (dx >> 1);
        }
        return dx + dy - (dy >> 1);
    }

    //
    // P_PointOnLineSide
    // Returns 0 or 1
    //
    function P_PointOnLineSide(x as Number, y as Number, line as Number) as Number {
        var ldx = PSetup.lines_dx[line];
        var ldy = PSetup.lines_dy[line];
        var v1 = PSetup.lines_v1[line];
        var lx = PSetup.vertexes_x[v1];
        var ly = PSetup.vertexes_y[v1];

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
    // P_BoxOnLineSide
    // Considers the line to be infinite
    // Returns side 0 or 1, -1 if box crosses the line.
    //
    function P_BoxOnLineSide(tmbox as Array<Number>, ld as Number) as Number {
        var p1 = 0;
        var p2 = 0;

        switch (PSetup.lines_slopetype[ld]) {
            case RDefs.ST_HORIZONTAL: {
                var ly = PSetup.vertexes_y[PSetup.lines_v1[ld]];
                p1 = tmbox[MBBox.BOXTOP] > ly ? 1 : 0;
                p2 = tmbox[MBBox.BOXBOTTOM] > ly ? 1 : 0;
                if (PSetup.lines_dx[ld] < 0) {
                    p1 ^= 1;
                    p2 ^= 1;
                }
                break;
            }

            case RDefs.ST_VERTICAL: {
                var lx = PSetup.vertexes_x[PSetup.lines_v1[ld]];
                p1 = tmbox[MBBox.BOXRIGHT] < lx ? 1 : 0;
                p2 = tmbox[MBBox.BOXLEFT] < lx ? 1 : 0;
                if (PSetup.lines_dy[ld] < 0) {
                    p1 ^= 1;
                    p2 ^= 1;
                }
                break;
            }

            case RDefs.ST_POSITIVE:
                p1 = P_PointOnLineSide(tmbox[MBBox.BOXLEFT], tmbox[MBBox.BOXTOP], ld);
                p2 = P_PointOnLineSide(tmbox[MBBox.BOXRIGHT], tmbox[MBBox.BOXBOTTOM], ld);
                break;

            case RDefs.ST_NEGATIVE:
                p1 = P_PointOnLineSide(tmbox[MBBox.BOXRIGHT], tmbox[MBBox.BOXTOP], ld);
                p2 = P_PointOnLineSide(tmbox[MBBox.BOXLEFT], tmbox[MBBox.BOXBOTTOM], ld);
                break;
        }

        if (p1 == p2) {
            return p1;
        }
        return -1;
    }

    //
    // P_PointOnDivlineSide
    // Returns 0 or 1.
    //
    function P_PointOnDivlineSide(x as Number, y as Number, line as Array<Number>) as Number {
        var lx = line[DL_X];
        var ly = line[DL_Y];
        var ldx = line[DL_DX];
        var ldy = line[DL_DY];

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

        // try to quickly decide by looking at sign bits
        if (((ldy ^ ldx ^ dx ^ dy) & 0x80000000) != 0) {
            if (((ldy ^ dx) & 0x80000000) != 0) {
                // (left is negative)
                return 1;
            }
            return 0;
        }

        var left = MFixed.FixedMul(ldy >> 8, dx >> 8);
        var right = MFixed.FixedMul(dy >> 8, ldx >> 8);

        if (right < left) {
            // front side
            return 0;
        }
        // back side
        return 1;
    }

    //
    // P_MakeDivline
    //
    function P_MakeDivline(li as Number, dl as Array<Number>) as Void {
        var v1 = PSetup.lines_v1[li];
        dl[DL_X] = PSetup.vertexes_x[v1];
        dl[DL_Y] = PSetup.vertexes_y[v1];
        dl[DL_DX] = PSetup.lines_dx[li];
        dl[DL_DY] = PSetup.lines_dy[li];
    }

    //
    // P_InterceptVector
    // Returns the fractional intercept point
    // along the first divline.
    // This is only called by the addthings
    // and addlines traversers.
    //
    // (the #else float debug version is left out, it was unused)
    //
    function P_InterceptVector(v2 as Array<Number>, v1 as Array<Number>) as Number {
        var den = MFixed.FixedMul(v1[DL_DY] >> 8, v2[DL_DX]) - MFixed.FixedMul(v1[DL_DX] >> 8, v2[DL_DY]);

        if (den == 0) {
            return 0;
        }
        //	I_Error ("P_InterceptVector: parallel");

        var num = MFixed.FixedMul((v1[DL_X] - v2[DL_X]) >> 8, v1[DL_DY])
                + MFixed.FixedMul((v2[DL_Y] - v1[DL_Y]) >> 8, v1[DL_DX]);

        var frac = MFixed.FixedDiv(num, den);

        return frac;
    }

    //
    // P_LineOpening
    // Sets opentop and openbottom to the window
    // through a two sided line.
    // OPTIMIZE: keep this precalculated
    //
    var opentop as Number = 0;
    var openbottom as Number = 0;
    var openrange as Number = 0;
    var lowfloor as Number = 0;

    function P_LineOpening(linedef as Number) as Void {
        if (PSetup.lines_sidenum[linedef * 2 + 1] == -1) {
            // single sided line
            openrange = 0;
            return;
        }

        var front = PSetup.lines_frontsector[linedef];
        var back = PSetup.lines_backsector[linedef];
        var ceiling = PSetup.sectors_ceilingheight;
        var floor = PSetup.sectors_floorheight;

        if (ceiling[front] < ceiling[back]) {
            opentop = ceiling[front];
        } else {
            opentop = ceiling[back];
        }

        if (floor[front] > floor[back]) {
            openbottom = floor[front];
            lowfloor = floor[back];
        } else {
            openbottom = floor[back];
            lowfloor = floor[front];
        }

        openrange = opentop - openbottom;
    }

    //
    // BLOCK MAP ITERATORS
    // For each line/thing in the given mapblock,
    // call the passed PIT_* function.
    // If the function returns false,
    // exit with false without checking anything else.
    //

    //
    // P_BlockLinesIterator
    // The validcount flags are used to avoid checking lines
    // that are marked in multiple mapblocks,
    // so increment validcount before the first call
    // to P_BlockLinesIterator, then make one or more calls
    // to it.
    //
    // func is a Method taking the line number and returning a Boolean.
    //
    function P_BlockLinesIterator(x as Number, y as Number, func as Method) as Boolean {
        var width = PSetup.bmapwidth;

        if (x < 0
            || y < 0
            || x >= width
            || y >= PSetup.bmapheight) {
            return true;
        }

        var blockmaplump = PSetup.blockmaplump;
        var linevalid = PSetup.lines_validcount;
        var valid = RMain.validcount;

        var offset = y * width + x;

        // blockmap is blockmaplump+4 in the C code
        offset = blockmaplump[4 + offset];

        // Every list starts with a 0, which the C loop doesn't skip, so
        // line 0 is offered in every block (once per validcount).
        for (var list = offset; blockmaplump[list] != -1; list++) {
            var ld = blockmaplump[list];

            if (linevalid[ld] == valid) {
                // line has already been checked
                continue;
            }

            linevalid[ld] = valid;

            if (!(func.invoke(ld) as Boolean)) {
                return false;
            }
        }
        // everything was checked
        return true;
    }
}
