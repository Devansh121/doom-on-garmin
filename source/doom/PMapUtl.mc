// p_maputl.c
//
// DESCRIPTION:
//	Movement/collision utility functions,
//	as used by function in p_map.c.
//	BLOCKMAP Iterator functions,
//	and some PIT_* functions to use for iteration.
//
// line_t* arguments are line numbers into the PSetup lines_* arrays.
// A divline_t {x, y, dx, dy} is a 4 element Array<Number>, indexed with
// the DL_* constants below.

import Toybox.Lang;

(:extendedCode)
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

    //
    // THING POSITION SETTING
    //

    //
    // P_UnsetThingPosition
    // Unlinks a thing from block map and sectors.
    // On each position change, BLOCKMAP and other
    // lookups maintaining lists ot things inside
    // these structures need to be updated.
    //
    function P_UnsetThingPosition(thing as Number) as Void {
        var flags = PMobj.mobjs_flags[thing];
        var snext = PMobj.mobjs_snext[thing];
        var sprev = PMobj.mobjs_sprev[thing];

        if ((flags & PMobj.MF_NOSECTOR) == 0) {
            // inert things don't need to be in blockmap?
            // unlink from subsector
            if (snext != -1) {
                PMobj.mobjs_sprev[snext] = sprev;
            }

            if (sprev != -1) {
                PMobj.mobjs_snext[sprev] = snext;
            } else {
                PSetup.sectors_thinglist[PSetup.subsectors_sector[PMobj.mobjs_subsector[thing]]] = snext;
            }
        }

        if ((flags & PMobj.MF_NOBLOCKMAP) == 0) {
            var bnext = PMobj.mobjs_bnext[thing];
            var bprev = PMobj.mobjs_bprev[thing];

            // inert things don't need to be in blockmap
            // unlink from block map
            if (bnext != -1) {
                PMobj.mobjs_bprev[bnext] = bprev;
            }

            if (bprev != -1) {
                PMobj.mobjs_bnext[bprev] = bnext;
            } else {
                var blockx = (PMobj.mobjs_x[thing] - PSetup.bmaporgx) >> PLocal.MAPBLOCKSHIFT;
                var blocky = (PMobj.mobjs_y[thing] - PSetup.bmaporgy) >> PLocal.MAPBLOCKSHIFT;

                if (blockx >= 0 && blockx < PSetup.bmapwidth
                    && blocky >= 0 && blocky < PSetup.bmapheight) {
                    PSetup.blocklinks[blocky * PSetup.bmapwidth + blockx] = bnext;
                }
            }
        }
    }

    //
    // P_SetThingPosition
    // Links a thing into both a block and a subsector
    // based on it's x y.
    // Sets thing->subsector properly
    //
    function P_SetThingPosition(thing as Number) as Void {
        var flags = PMobj.mobjs_flags[thing];

        // link into subsector
        var ss = RMain.R_PointInSubsector(PMobj.mobjs_x[thing], PMobj.mobjs_y[thing]);
        PMobj.mobjs_subsector[thing] = ss;

        if ((flags & PMobj.MF_NOSECTOR) == 0) {
            // invisible things don't go into the sector links
            var sec = PSetup.subsectors_sector[ss];

            PMobj.mobjs_sprev[thing] = -1;
            PMobj.mobjs_snext[thing] = PSetup.sectors_thinglist[sec];

            if (PSetup.sectors_thinglist[sec] != -1) {
                PMobj.mobjs_sprev[PSetup.sectors_thinglist[sec]] = thing;
            }

            PSetup.sectors_thinglist[sec] = thing;
        }

        // link into blockmap
        if ((flags & PMobj.MF_NOBLOCKMAP) == 0) {
            // inert things don't need to be in blockmap
            var blockx = (PMobj.mobjs_x[thing] - PSetup.bmaporgx) >> PLocal.MAPBLOCKSHIFT;
            var blocky = (PMobj.mobjs_y[thing] - PSetup.bmaporgy) >> PLocal.MAPBLOCKSHIFT;

            if (blockx >= 0
                && blockx < PSetup.bmapwidth
                && blocky >= 0
                && blocky < PSetup.bmapheight) {
                var link = blocky * PSetup.bmapwidth + blockx;
                PMobj.mobjs_bprev[thing] = -1;
                PMobj.mobjs_bnext[thing] = PSetup.blocklinks[link];
                if (PSetup.blocklinks[link] != -1) {
                    PMobj.mobjs_bprev[PSetup.blocklinks[link]] = thing;
                }

                PSetup.blocklinks[link] = thing;
            } else {
                // thing is off the map
                PMobj.mobjs_bnext[thing] = -1;
                PMobj.mobjs_bprev[thing] = -1;
            }
        }
    }

    //
    // P_BlockThingsIterator
    //
    // func is a Method taking the mobj number and returning a Boolean.
    //
    function P_BlockThingsIterator(x as Number, y as Number, func as Method) as Boolean {
        if (x < 0
            || y < 0
            || x >= PSetup.bmapwidth
            || y >= PSetup.bmapheight) {
            return true;
        }

        var bnext = PMobj.mobjs_bnext;
        for (var mobj = PSetup.blocklinks[y * PSetup.bmapwidth + x];
             mobj != -1;
             mobj = bnext[mobj]) {
            if (!(func.invoke(mobj) as Boolean)) {
                return false;
            }
        }
        return true;
    }

    //
    // INTERCEPT ROUTINES
    //
    // intercept_t intercepts[MAXINTERCEPTS] as parallel arrays: frac,
    // isaline, and d, which is a line number when isaline and a mobj
    // number otherwise. intercept_p is the count of entries in use.
    //
    var intercepts_frac as Array<Number> = new [PLocal.MAXINTERCEPTS] as Array<Number>;
    var intercepts_isaline as Array<Boolean> = new [PLocal.MAXINTERCEPTS] as Array<Boolean>;
    var intercepts_d as Array<Number> = new [PLocal.MAXINTERCEPTS] as Array<Number>;
    var intercept_p as Number = 0;

    var trace as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    var earlyout as Boolean = false;
    var ptflags as Number = 0;

    // The C code writes past the end of intercepts[] when a trace
    // crosses more than MAXINTERCEPTS things and lines (the famous
    // intercepts overflow). Monkey C would throw instead, so extra
    // intercepts are dropped.
    function P_AddIntercept(frac as Number, isaline as Boolean, d as Number) as Void {
        if (intercept_p >= PLocal.MAXINTERCEPTS) {
            return;
        }
        intercepts_frac[intercept_p] = frac;
        intercepts_isaline[intercept_p] = isaline;
        intercepts_d[intercept_p] = d;
        intercept_p++;
    }

    //
    // PIT_AddLineIntercepts.
    // Looks for lines in the given block
    // that intercept the given trace
    // to add to the intercepts list.
    //
    // A line is crossed if its endpoints
    // are on opposite sides of the trace.
    // Returns true if earlyout and a solid line hit.
    //
    function PIT_AddLineIntercepts(ld as Number) as Boolean {
        var s1;
        var s2;
        var frac;
        var dl = [0, 0, 0, 0] as Array<Number>;
        var v1 = PSetup.lines_v1[ld];
        var v2 = PSetup.lines_v2[ld];

        // avoid precision problems with two routines
        if (trace[DL_DX] > MFixed.FRACUNIT * 16
            || trace[DL_DY] > MFixed.FRACUNIT * 16
            || trace[DL_DX] < -MFixed.FRACUNIT * 16
            || trace[DL_DY] < -MFixed.FRACUNIT * 16) {
            s1 = P_PointOnDivlineSide(PSetup.vertexes_x[v1], PSetup.vertexes_y[v1], trace);
            s2 = P_PointOnDivlineSide(PSetup.vertexes_x[v2], PSetup.vertexes_y[v2], trace);
        } else {
            s1 = P_PointOnLineSide(trace[DL_X], trace[DL_Y], ld);
            s2 = P_PointOnLineSide(trace[DL_X] + trace[DL_DX], trace[DL_Y] + trace[DL_DY], ld);
        }

        if (s1 == s2) {
            return true;    // line isn't crossed
        }

        // hit the line
        P_MakeDivline(ld, dl);
        frac = P_InterceptVector(trace, dl);

        if (frac < 0) {
            return true;    // behind source
        }

        // try to early out the check
        if (earlyout
            && frac < MFixed.FRACUNIT
            && PSetup.lines_backsector[ld] == -1) {
            return false;   // stop checking
        }

        P_AddIntercept(frac, true, ld);

        return true;    // continue
    }

    //
    // PIT_AddThingIntercepts
    //
    function PIT_AddThingIntercepts(thing as Number) as Boolean {
        var x1;
        var y1;
        var x2;
        var y2;

        var s1;
        var s2;

        var tracepositive;

        var dl = [0, 0, 0, 0] as Array<Number>;

        var frac;

        var tx = PMobj.mobjs_x[thing];
        var ty = PMobj.mobjs_y[thing];
        var radius = PMobj.mobjs_radius[thing];

        tracepositive = (trace[DL_DX] ^ trace[DL_DY]) > 0;

        // check a corner to corner crossection for hit
        if (tracepositive) {
            x1 = tx - radius;
            y1 = ty + radius;

            x2 = tx + radius;
            y2 = ty - radius;
        } else {
            x1 = tx - radius;
            y1 = ty - radius;

            x2 = tx + radius;
            y2 = ty + radius;
        }

        s1 = P_PointOnDivlineSide(x1, y1, trace);
        s2 = P_PointOnDivlineSide(x2, y2, trace);

        if (s1 == s2) {
            return true;    // line isn't crossed
        }

        dl[DL_X] = x1;
        dl[DL_Y] = y1;
        dl[DL_DX] = x2 - x1;
        dl[DL_DY] = y2 - y1;

        frac = P_InterceptVector(trace, dl);

        if (frac < 0) {
            return true;    // behind source
        }

        P_AddIntercept(frac, false, thing);

        return true;    // keep going
    }

    //
    // P_TraverseIntercepts
    // Returns true if the traverser function returns true
    // for all lines.
    //
    // func is a Method taking the intercept index and returning a
    // Boolean.
    //
    function P_TraverseIntercepts(func as Method, maxfrac as Number) as Boolean {
        var count;
        var dist;
        var scan;
        var inp;
        var fracs = intercepts_frac;
        var end = intercept_p;

        count = end;

        inp = 0;    // shut up compiler warning

        while (count > 0) {
            count--;
            dist = DoomType.MAXINT;
            for (scan = 0; scan < end; scan++) {
                if (fracs[scan] < dist) {
                    dist = fracs[scan];
                    inp = scan;
                }
            }

            if (dist > maxfrac) {
                return true;    // checked everything in range
            }

            // (the #if 0 UNUSED block is left out)

            if (!(func.invoke(inp) as Boolean)) {
                return false;   // don't bother going farther
            }

            fracs[inp] = DoomType.MAXINT;
        }

        return true;    // everything was traversed
    }

    //
    // P_PathTraverse
    // Traces a line from x1,y1 to x2,y2,
    // calling the traverser function for each.
    // Returns true if the traverser function returns true
    // for all lines.
    //
    // trav is a Method taking the intercept index. Visits up to 64
    // blocks and sorts up to MAXINTERCEPTS intercepts, so a long trace
    // through a busy area may need splitting for the watchdog.
    //
    function P_PathTraverse(x1 as Number, y1 as Number, x2 as Number, y2 as Number,
                            flags as Number, trav as Method) as Boolean {
        var xt1;
        var yt1;
        var xt2;
        var yt2;

        var xstep;
        var ystep;

        var partial;

        var xintercept;
        var yintercept;

        var mapx;
        var mapy;

        var mapxstep;
        var mapystep;

        var count;

        earlyout = (flags & PLocal.PT_EARLYOUT) != 0;

        RMain.validcount++;
        intercept_p = 0;

        if (((x1 - PSetup.bmaporgx) & (PLocal.MAPBLOCKSIZE - 1)) == 0) {
            x1 += MFixed.FRACUNIT;  // don't side exactly on a line
        }

        if (((y1 - PSetup.bmaporgy) & (PLocal.MAPBLOCKSIZE - 1)) == 0) {
            y1 += MFixed.FRACUNIT;  // don't side exactly on a line
        }

        trace[DL_X] = x1;
        trace[DL_Y] = y1;
        trace[DL_DX] = x2 - x1;
        trace[DL_DY] = y2 - y1;

        x1 -= PSetup.bmaporgx;
        y1 -= PSetup.bmaporgy;
        xt1 = x1 >> PLocal.MAPBLOCKSHIFT;
        yt1 = y1 >> PLocal.MAPBLOCKSHIFT;

        x2 -= PSetup.bmaporgx;
        y2 -= PSetup.bmaporgy;
        xt2 = x2 >> PLocal.MAPBLOCKSHIFT;
        yt2 = y2 >> PLocal.MAPBLOCKSHIFT;

        if (xt2 > xt1) {
            mapxstep = 1;
            partial = MFixed.FRACUNIT - ((x1 >> PLocal.MAPBTOFRAC) & (MFixed.FRACUNIT - 1));
            ystep = MFixed.FixedDiv(y2 - y1, MFixed.abs(x2 - x1));
        } else if (xt2 < xt1) {
            mapxstep = -1;
            partial = (x1 >> PLocal.MAPBTOFRAC) & (MFixed.FRACUNIT - 1);
            ystep = MFixed.FixedDiv(y2 - y1, MFixed.abs(x2 - x1));
        } else {
            mapxstep = 0;
            partial = MFixed.FRACUNIT;
            ystep = 256 * MFixed.FRACUNIT;
        }

        yintercept = (y1 >> PLocal.MAPBTOFRAC) + MFixed.FixedMul(partial, ystep);

        if (yt2 > yt1) {
            mapystep = 1;
            partial = MFixed.FRACUNIT - ((y1 >> PLocal.MAPBTOFRAC) & (MFixed.FRACUNIT - 1));
            xstep = MFixed.FixedDiv(x2 - x1, MFixed.abs(y2 - y1));
        } else if (yt2 < yt1) {
            mapystep = -1;
            partial = (y1 >> PLocal.MAPBTOFRAC) & (MFixed.FRACUNIT - 1);
            xstep = MFixed.FixedDiv(x2 - x1, MFixed.abs(y2 - y1));
        } else {
            mapystep = 0;
            partial = MFixed.FRACUNIT;
            xstep = 256 * MFixed.FRACUNIT;
        }
        xintercept = (x1 >> PLocal.MAPBTOFRAC) + MFixed.FixedMul(partial, xstep);

        // Step through map blocks.
        // Count is present to prevent a round off error
        // from skipping the break.
        mapx = xt1;
        mapy = yt1;

        var addlines = new Lang.Method(PMapUtl, :PIT_AddLineIntercepts);
        var addthings = new Lang.Method(PMapUtl, :PIT_AddThingIntercepts);

        for (count = 0; count < 64; count++) {
            if ((flags & PLocal.PT_ADDLINES) != 0) {
                if (!P_BlockLinesIterator(mapx, mapy, addlines)) {
                    return false;   // early out
                }
            }

            if ((flags & PLocal.PT_ADDTHINGS) != 0) {
                if (!P_BlockThingsIterator(mapx, mapy, addthings)) {
                    return false;   // early out
                }
            }

            if (mapx == xt2
                && mapy == yt2) {
                break;
            }

            if ((yintercept >> MFixed.FRACBITS) == mapy) {
                yintercept += ystep;
                mapx += mapxstep;
            } else if ((xintercept >> MFixed.FRACBITS) == mapx) {
                xintercept += xstep;
                mapy += mapystep;
            }
        }
        // go through the sorted list
        return P_TraverseIntercepts(trav, MFixed.FRACUNIT);
    }
}
