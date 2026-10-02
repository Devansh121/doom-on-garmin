// p_sight.c
//
// DESCRIPTION:
//	LineOfSight/Visibility checks, uses REJECT Lookup Table.
//
// divline_t is a 4 element Array<Number> indexed with PMapUtl.DL_*.
// node_t starts with the same four fields; where the C casts a node to a
// divline_t, P_CrossBSPNode reads the node's x, y, dx, dy directly.
//
// Watchdog: P_CheckSight walks every BSP node and subsector the trace
// passes through, so a long sight line across the map can get expensive.
// If it trips the watchdog it will need splitting like R_RenderBSPNode.

import Toybox.Lang;

(:extendedCode)
module PSight {

    //
    // P_CheckSight
    //
    var sightzstart as Number = 0;   // eye z of looker
    var topslope as Number = 0;
    var bottomslope as Number = 0;   // slopes to top and bottom of target

    var strace as Array<Number> = [0, 0, 0, 0] as Array<Number>;  // from t1 to t2
    var t2x as Number = 0;
    var t2y as Number = 0;

    var sightcounts as Array<Number> = [0, 0] as Array<Number>;

    //
    // P_DivlineSide
    // Returns side 0 (front), 1 (back), or 2 (on).
    //
    function P_DivlineSide(x as Number, y as Number, node as Array<Number>) as Number {
        var nx = node[PMapUtl.DL_X];
        var ny = node[PMapUtl.DL_Y];
        var ndx = node[PMapUtl.DL_DX];
        var ndy = node[PMapUtl.DL_DY];

        if (ndx == 0) {
            if (x == nx) {
                return 2;
            }

            if (x <= nx) {
                return ndy > 0 ? 1 : 0;
            }

            return ndy < 0 ? 1 : 0;
        }

        if (ndy == 0) {
            // (x, not y, as in the original)
            if (x == ny) {
                return 2;
            }

            if (y <= ny) {
                return ndx < 0 ? 1 : 0;
            }

            return ndx > 0 ? 1 : 0;
        }

        var dx = (x - nx);
        var dy = (y - ny);

        var left = (ndy >> MFixed.FRACBITS) * (dx >> MFixed.FRACBITS);
        var right = (dy >> MFixed.FRACBITS) * (ndx >> MFixed.FRACBITS);

        if (right < left) {
            // front side
            return 0;
        }

        if (left == right) {
            return 2;
        }
        // back side
        return 1;
    }

    //
    // P_InterceptVector2
    // Returns the fractional intercept point
    // along the first divline.
    // This is only called by the addthings and addlines traversers.
    //
    function P_InterceptVector2(v2 as Array<Number>, v1 as Array<Number>) as Number {
        var den = MFixed.FixedMul(v1[PMapUtl.DL_DY] >> 8, v2[PMapUtl.DL_DX])
                - MFixed.FixedMul(v1[PMapUtl.DL_DX] >> 8, v2[PMapUtl.DL_DY]);

        if (den == 0) {
            return 0;
        }
        //	I_Error ("P_InterceptVector: parallel");

        var num = MFixed.FixedMul((v1[PMapUtl.DL_X] - v2[PMapUtl.DL_X]) >> 8, v1[PMapUtl.DL_DY])
                + MFixed.FixedMul((v2[PMapUtl.DL_Y] - v1[PMapUtl.DL_Y]) >> 8, v1[PMapUtl.DL_DX]);
        var frac = MFixed.FixedDiv(num, den);

        return frac;
    }

    //
    // P_CrossSubsector
    // Returns true
    //  if strace crosses the given subsector successfully.
    //
    // P_CrossBSPNode has its own inlined copy of this, see there; this
    // one is kept as the C reads.
    //
    function P_CrossSubsector(num as Number) as Boolean {
        // module arrays copied into locals for the loop
        var segs_linedef = PSetup.segs_linedef;
        var lines_validcount = PSetup.lines_validcount;
        var lines_v1 = PSetup.lines_v1;
        var lines_v2 = PSetup.lines_v2;
        var vx = PSetup.vertexes_x;
        var vy = PSetup.vertexes_y;
        var floorheight = PSetup.sectors_floorheight;
        var ceilingheight = PSetup.sectors_ceilingheight;
        var valid = RMain.validcount;
        var tr = strace;
        var divl = [0, 0, 0, 0] as Array<Number>;

        if (num >= PSetup.numsubsectors) {
            ISystem.I_Error("P_CrossSubsector: ss " + num + " with numss = " + PSetup.numsubsectors);
        }

        // check lines
        var count = PSetup.subsectors_numlines[num];
        var seg = PSetup.subsectors_firstline[num];

        for (; count != 0; seg++, count--) {
            var line = segs_linedef[seg];

            // allready checked other side?
            if (lines_validcount[line] == valid) {
                continue;
            }

            lines_validcount[line] = valid;

            var v1 = lines_v1[line];
            var v2 = lines_v2[line];
            var s1 = P_DivlineSide(vx[v1], vy[v1], tr);
            var s2 = P_DivlineSide(vx[v2], vy[v2], tr);

            // line isn't crossed?
            if (s1 == s2) {
                continue;
            }

            divl[PMapUtl.DL_X] = vx[v1];
            divl[PMapUtl.DL_Y] = vy[v1];
            divl[PMapUtl.DL_DX] = vx[v2] - vx[v1];
            divl[PMapUtl.DL_DY] = vy[v2] - vy[v1];
            s1 = P_DivlineSide(tr[PMapUtl.DL_X], tr[PMapUtl.DL_Y], divl);
            s2 = P_DivlineSide(t2x, t2y, divl);

            // line isn't crossed?
            if (s1 == s2) {
                continue;
            }

            // stop because it is not two sided anyway
            // might do this after updating validcount?
            if ((PSetup.lines_flags[line] & DoomData.ML_TWOSIDED) == 0) {
                return false;
            }

            // crosses a two sided line
            var front = PSetup.segs_frontsector[seg];
            var back = PSetup.segs_backsector[seg];

            // no wall to block sight with?
            if (floorheight[front] == floorheight[back]
                && ceilingheight[front] == ceilingheight[back]) {
                continue;
            }

            // possible occluder
            // because of ceiling height differences
            var opentop;
            if (ceilingheight[front] < ceilingheight[back]) {
                opentop = ceilingheight[front];
            } else {
                opentop = ceilingheight[back];
            }

            // because of ceiling height differences
            var openbottom;
            if (floorheight[front] > floorheight[back]) {
                openbottom = floorheight[front];
            } else {
                openbottom = floorheight[back];
            }

            // quick test for totally closed doors
            if (openbottom >= opentop) {
                return false;   // stop
            }

            var frac = P_InterceptVector2(tr, divl);

            if (floorheight[front] != floorheight[back]) {
                var slope = MFixed.FixedDiv(openbottom - sightzstart, frac);
                if (slope > bottomslope) {
                    bottomslope = slope;
                }
            }

            if (ceilingheight[front] != ceilingheight[back]) {
                var slope = MFixed.FixedDiv(opentop - sightzstart, frac);
                if (slope < topslope) {
                    topslope = slope;
                }
            }

            if (topslope <= bottomslope) {
                return false;   // stop
            }
        }
        // passed the subsector ok
        return true;
    }

    //
    // P_CrossBSPNode
    // Returns true
    //  if strace crosses the given node successfully.
    //
    // The C recursion goes as deep as the BSP tree, and Monkey C's call
    // stack overflows long before that, so this walks with its own stack.
    // Same order as the C: the start side first, then the far side only if
    // the trace crosses the partition. A false anywhere means blocked.
    //
    // Entries are a node/subsector number to cross, or -(node * 2 + side) - 2
    // for "the start side of node is done, check the partition".
    //
    // Every monster looking for the player runs this, so it is written for
    // the watch, where a call or a module variable read costs tens of
    // microseconds: P_CrossSubsector and the P_DivlineSide tests against
    // the nodes and strace are inlined, with the arrays the walk touches on
    // every node and line in locals. Lines that actually cross the trace
    // (rare next to the ones that don't) go through P_DivlineSide,
    // P_InterceptVector2 and the module variables like the C. All locals
    // are declared up front and reused: the VM stack only holds a couple
    // of hundred slots and this sits at the top of A_Chase's call chain.
    //
    const MAXSIGHTSTACK = 128;
    var sightstack as Array<Number> = new [MAXSIGHTSTACK] as Array<Number>;

    // divl in P_CrossSubsector, reused between calls
    var crossdiv as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    function P_CrossBSPNode(bspnum as Number) as Boolean {
        var stack = sightstack;
        var children = PSetup.nodes_children;
        var nodes_x = PSetup.nodes_x;
        var nodes_y = PSetup.nodes_y;
        var nodes_dx = PSetup.nodes_dx;
        var nodes_dy = PSetup.nodes_dy;
        var segs_linedef = PSetup.segs_linedef;
        var lines_validcount = PSetup.lines_validcount;
        var lines_v1 = PSetup.lines_v1;
        var lines_v2 = PSetup.lines_v2;
        var vx = PSetup.vertexes_x;
        var vy = PSetup.vertexes_y;
        var valid = RMain.validcount;
        var sx = strace[PMapUtl.DL_X];
        var sy = strace[PMapUtl.DL_Y];
        var ex = t2x;
        var ey = t2y;
        // P_DivlineSide(x, y, strace) for a strace that isn't axis
        // aligned only needs these
        var sdxh = strace[PMapUtl.DL_DX];
        var sdyh = strace[PMapUtl.DL_DY];
        var straight = sdxh == 0 || sdyh == 0;
        sdxh >>= MFixed.FRACBITS;
        sdyh >>= MFixed.FRACBITS;

        var sp = 1;
        var side;
        var s;
        var nx;
        var ny;
        var ndx;
        var ndy;
        var count;
        var seg;
        var line;
        var v1;
        var v2;

        stack[0] = bspnum;

        while (sp > 0) {
            sp--;
            bspnum = stack[sp];

            if (bspnum < -1) {
                bspnum = -bspnum - 2;
                side = bspnum & 1;
                bspnum >>= 1;

                // the partition plane is crossed here
                // (side == P_DivlineSide(t2x, t2y, bsp), inlined)
                nx = nodes_x[bspnum];
                ny = nodes_y[bspnum];
                ndx = nodes_dx[bspnum];
                ndy = nodes_dy[bspnum];
                if (ndx == 0) {
                    if (ex == nx) {
                        s = 2;
                    } else if (ex <= nx) {
                        s = ndy > 0 ? 1 : 0;
                    } else {
                        s = ndy < 0 ? 1 : 0;
                    }
                } else if (ndy == 0) {
                    // (x, not y, as in the original)
                    if (ex == ny) {
                        s = 2;
                    } else if (ey <= ny) {
                        s = ndx < 0 ? 1 : 0;
                    } else {
                        s = ndx > 0 ? 1 : 0;
                    }
                } else {
                    // left = ndx, right = ndy from here on
                    ndx = (ndy >> MFixed.FRACBITS) * ((ex - nx) >> MFixed.FRACBITS);
                    ndy = ((ey - ny) >> MFixed.FRACBITS) * (nodes_dx[bspnum] >> MFixed.FRACBITS);
                    if (ndy < ndx) {
                        s = 0;
                    } else if (ndx == ndy) {
                        s = 2;
                    } else {
                        s = 1;
                    }
                }
                if (side == s) {
                    // the line doesn't touch the other side
                    continue;
                }

                // cross the ending side
                stack[sp] = children[bspnum * 2 + (side ^ 1)];
                sp++;
                continue;
            }

            if ((bspnum & DoomData.NF_SUBSECTOR) != 0) {
                // P_CrossSubsector(bspnum == -1 ? 0 : bspnum & ~NF_SUBSECTOR),
                // inlined
                bspnum = bspnum == -1 ? 0 : bspnum & ~DoomData.NF_SUBSECTOR;

                if (bspnum >= PSetup.numsubsectors) {
                    ISystem.I_Error("P_CrossSubsector: ss " + bspnum + " with numss = " + PSetup.numsubsectors);
                }

                // check lines
                count = PSetup.subsectors_numlines[bspnum];
                seg = PSetup.subsectors_firstline[bspnum];

                for (; count != 0; seg++, count--) {
                    line = segs_linedef[seg];

                    // allready checked other side?
                    if (lines_validcount[line] == valid) {
                        continue;
                    }

                    lines_validcount[line] = valid;

                    v1 = lines_v1[line];
                    v2 = lines_v2[line];
                    if (straight) {
                        side = P_DivlineSide(vx[v1], vy[v1], strace);
                        s = P_DivlineSide(vx[v2], vy[v2], strace);
                    } else {
                        // P_DivlineSide(x, y, strace), inlined; left in
                        // ndx, right in ndy
                        ndx = sdyh * ((vx[v1] - sx) >> MFixed.FRACBITS);
                        ndy = ((vy[v1] - sy) >> MFixed.FRACBITS) * sdxh;
                        side = ndy < ndx ? 0 : (ndx == ndy ? 2 : 1);
                        ndx = sdyh * ((vx[v2] - sx) >> MFixed.FRACBITS);
                        ndy = ((vy[v2] - sy) >> MFixed.FRACBITS) * sdxh;
                        s = ndy < ndx ? 0 : (ndx == ndy ? 2 : 1);
                    }

                    // line isn't crossed?
                    if (side == s) {
                        continue;
                    }

                    if (!P_CrossLine(seg, line, v1, v2)) {
                        return false;
                    }
                }
                // passed the subsector ok
                continue;
            }

            // decide which side the start point is on
            // (P_DivlineSide(strace x, y, bspnum), inlined)
            nx = nodes_x[bspnum];
            ny = nodes_y[bspnum];
            ndx = nodes_dx[bspnum];
            ndy = nodes_dy[bspnum];
            if (ndx == 0) {
                if (sx == nx) {
                    side = 2;
                } else if (sx <= nx) {
                    side = ndy > 0 ? 1 : 0;
                } else {
                    side = ndy < 0 ? 1 : 0;
                }
            } else if (ndy == 0) {
                // (x, not y, as in the original)
                if (sx == ny) {
                    side = 2;
                } else if (sy <= ny) {
                    side = ndx < 0 ? 1 : 0;
                } else {
                    side = ndx > 0 ? 1 : 0;
                }
            } else {
                // left = ndx, right = ndy from here on
                ndx = (ndy >> MFixed.FRACBITS) * ((sx - nx) >> MFixed.FRACBITS);
                ndy = ((sy - ny) >> MFixed.FRACBITS) * (nodes_dx[bspnum] >> MFixed.FRACBITS);
                if (ndy < ndx) {
                    side = 0;
                } else if (ndx == ndy) {
                    side = 2;
                } else {
                    side = 1;
                }
            }
            if (side == 2) {
                side = 0;   // an "on" should cross both sides
            }

            // cross the starting side, then come back for the partition
            stack[sp] = -(bspnum * 2 + side) - 2;
            stack[sp + 1] = children[bspnum * 2 + side];
            sp += 2;
        }
        return true;
    }

    // The rest of P_CrossSubsector's line loop, for a line (of seg, from
    // vertex v1 to v2) whose ends are on opposite sides of strace.
    // Returns false if it blocks the sight line.
    function P_CrossLine(seg as Number, line as Number, v1 as Number, v2 as Number) as Boolean {
        var vx = PSetup.vertexes_x;
        var vy = PSetup.vertexes_y;
        var divl = crossdiv;

        divl[PMapUtl.DL_X] = vx[v1];
        divl[PMapUtl.DL_Y] = vy[v1];
        divl[PMapUtl.DL_DX] = vx[v2] - vx[v1];
        divl[PMapUtl.DL_DY] = vy[v2] - vy[v1];
        var s1 = P_DivlineSide(strace[PMapUtl.DL_X], strace[PMapUtl.DL_Y], divl);
        var s2 = P_DivlineSide(t2x, t2y, divl);

        // line isn't crossed?
        if (s1 == s2) {
            return true;
        }

        // stop because it is not two sided anyway
        // might do this after updating validcount?
        if ((PSetup.lines_flags[line] & DoomData.ML_TWOSIDED) == 0) {
            return false;
        }

        // crosses a two sided line
        var floorheight = PSetup.sectors_floorheight;
        var ceilingheight = PSetup.sectors_ceilingheight;
        var front = PSetup.segs_frontsector[seg];
        var back = PSetup.segs_backsector[seg];

        // no wall to block sight with?
        if (floorheight[front] == floorheight[back]
            && ceilingheight[front] == ceilingheight[back]) {
            return true;
        }

        // possible occluder
        // because of ceiling height differences
        var opentop;
        if (ceilingheight[front] < ceilingheight[back]) {
            opentop = ceilingheight[front];
        } else {
            opentop = ceilingheight[back];
        }

        // because of ceiling height differences
        var openbottom;
        if (floorheight[front] > floorheight[back]) {
            openbottom = floorheight[front];
        } else {
            openbottom = floorheight[back];
        }

        // quick test for totally closed doors
        if (openbottom >= opentop) {
            return false;   // stop
        }

        var frac = P_InterceptVector2(strace, divl);

        if (floorheight[front] != floorheight[back]) {
            var slope = MFixed.FixedDiv(openbottom - sightzstart, frac);
            if (slope > bottomslope) {
                bottomslope = slope;
            }
        }

        if (ceilingheight[front] != ceilingheight[back]) {
            var slope = MFixed.FixedDiv(opentop - sightzstart, frac);
            if (slope < topslope) {
                topslope = slope;
            }
        }

        if (topslope <= bottomslope) {
            return false;   // stop
        }
        return true;
    }

    //
    // P_CheckSight
    // Returns true
    //  if a straight line between t1 and t2 is unobstructed.
    // Uses REJECT.
    //
    function P_CheckSight(t1 as Number, t2 as Number) as Boolean {
        // First check for trivial rejection.

        // Determine subsector entries in REJECT table.
        var s1 = PSetup.subsectors_sector[PMobj.mobjs_subsector[t1]];
        var s2 = PSetup.subsectors_sector[PMobj.mobjs_subsector[t2]];
        var pnum = s1 * PSetup.numsectors + s2;
        // bytenum = pnum>>3, bitnum = 1 << (pnum&7) in the C code; the
        // lump is packed 32 bits per number here (see wad2ciq.py).
        var bitnum = 1 << (pnum & 31);

        // Check in REJECT table.
        if ((PSetup.rejectmatrix[pnum >> 5] & bitnum) != 0) {
            sightcounts[0]++;

            // can't possibly be connected
            return false;
        }

        // An unobstructed LOS is possible.
        // Now look from eyes of t1 to any part of t2.
        sightcounts[1]++;

        RMain.validcount++;

        var z1 = PMobj.mobjs_z[t1];
        var h1 = PMobj.mobjs_height[t1];
        sightzstart = z1 + h1 - (h1 >> 2);
        topslope = (PMobj.mobjs_z[t2] + PMobj.mobjs_height[t2]) - sightzstart;
        bottomslope = (PMobj.mobjs_z[t2]) - sightzstart;

        strace[PMapUtl.DL_X] = PMobj.mobjs_x[t1];
        strace[PMapUtl.DL_Y] = PMobj.mobjs_y[t1];
        t2x = PMobj.mobjs_x[t2];
        t2y = PMobj.mobjs_y[t2];
        strace[PMapUtl.DL_DX] = PMobj.mobjs_x[t2] - PMobj.mobjs_x[t1];
        strace[PMapUtl.DL_DY] = PMobj.mobjs_y[t2] - PMobj.mobjs_y[t1];

        // the head node is the last node output
        return P_CrossBSPNode(PSetup.numnodes - 1);
    }
}
