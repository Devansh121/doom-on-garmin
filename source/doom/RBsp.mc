// r_bsp.c
//
// BSP traversal, handling of LineSegs for rendering.
//
// R_RenderBSPNode is recursive in the C code. A recursive walk can't be
// paused, and a frame has to be spread over several watchdog slices, so
// the traversal here keeps its own stack and visits nodes in exactly the
// same order: front child first, then the back child if R_CheckBBox
// (evaluated after the front side is done, as in C) says it's visible.

import Toybox.Lang;
import Toybox.System;

module RBsp {

    var curline as Number = -1;
    var sidedef as Number = -1;
    var linedef as Number = -1;
    var frontsector as Number = -1;
    var backsector as Number = -1;

    //
    // ClipWallSegment
    // Clips the given range of columns
    // and includes it in the new clip list.
    //
    // cliprange_t, one array per field. One spare slot past MAXSEGS
    // because the crunch loop in R_ClipSolidWallSegment copies the entry
    // at newend.
    const MAXSEGS = 32;
    var solidsegs_first as Array<Number> = new [MAXSEGS + 1] as Array<Number>;
    var solidsegs_last as Array<Number> = new [MAXSEGS + 1] as Array<Number>;

    // newend is one past the last valid seg
    var newend as Number = 0;

    //
    // R_ClearDrawSegs
    //
    function R_ClearDrawSegs() as Void {
        RSegs.ds_p = 0;
    }

    //
    // R_ClipSolidWallSegment
    // Does handle solid walls,
    //  e.g. single sided LineDefs (middle texture)
    //  that entirely block the view.
    //
    function R_ClipSolidWallSegment(first as Number, last as Number) as Void {
        var sf = solidsegs_first;
        var sl = solidsegs_last;

        // Find the first range that touches the range
        //  (adjacent pixels are touching).
        var start = 0;
        while (sl[start] < first - 1) {
            start++;
        }

        if (first < sf[start]) {
            if (last < sf[start] - 1) {
                // Post is entirely visible (above start),
                //  so insert a new clippost.
                RSegs.R_StoreWallRange(first, last);
                var n = newend;
                newend++;

                while (n != start) {
                    sf[n] = sf[n - 1];
                    sl[n] = sl[n - 1];
                    n--;
                }
                sf[n] = first;
                sl[n] = last;
                return;
            }

            // There is a fragment above *start.
            RSegs.R_StoreWallRange(first, sf[start] - 1);
            // Now adjust the clip size.
            sf[start] = first;
        }

        // Bottom contained in start?
        if (last <= sl[start]) {
            return;
        }

        var next = start;
        var crunch = false;
        while (last >= sf[next + 1] - 1) {
            // There is a fragment between two posts.
            RSegs.R_StoreWallRange(sl[next] + 1, sf[next + 1] - 1);
            next++;

            if (last <= sl[next]) {
                // Bottom is contained in next.
                // Adjust the clip size.
                sl[start] = sl[next];
                crunch = true;
                break;
            }
        }

        if (!crunch) {
            // There is a fragment after *next.
            RSegs.R_StoreWallRange(sl[next] + 1, last);
            // Adjust the clip size.
            sl[start] = last;
        }

        // Remove start+1 to next from the clip list,
        // because start now covers their area.
        // crunch:
        if (next == start) {
            // Post just extended past the bottom of one post.
            return;
        }

        // while (next++ != newend) *++start = *next;
        while (true) {
            var old = next;
            next++;
            if (old == newend) {
                break;
            }
            // Remove a post.
            start++;
            sf[start] = sf[next];
            sl[start] = sl[next];
        }
        newend = start + 1;
    }

    //
    // R_ClipPassWallSegment
    // Clips the given range of columns,
    //  but does not includes it in the clip list.
    // Does handle windows,
    //  e.g. LineDefs with upper and lower texture.
    //
    function R_ClipPassWallSegment(first as Number, last as Number) as Void {
        var sf = solidsegs_first;
        var sl = solidsegs_last;

        // Find the first range that touches the range
        //  (adjacent pixels are touching).
        var start = 0;
        while (sl[start] < first - 1) {
            start++;
        }

        if (first < sf[start]) {
            if (last < sf[start] - 1) {
                // Post is entirely visible (above start).
                RSegs.R_StoreWallRange(first, last);
                return;
            }

            // There is a fragment above *start.
            RSegs.R_StoreWallRange(first, sf[start] - 1);
        }

        // Bottom contained in start?
        if (last <= sl[start]) {
            return;
        }

        while (last >= sf[start + 1] - 1) {
            // There is a fragment between two posts.
            RSegs.R_StoreWallRange(sl[start] + 1, sf[start + 1] - 1);
            start++;

            if (last <= sl[start]) {
                return;
            }
        }

        // There is a fragment after *next.
        RSegs.R_StoreWallRange(sl[start] + 1, last);
    }

    //
    // R_ClearClipSegs
    //
    function R_ClearClipSegs() as Void {
        solidsegs_first[0] = -0x7fffffff;
        solidsegs_last[0] = -1;
        solidsegs_first[1] = RMain.viewwidth;
        solidsegs_last[1] = 0x7fffffff;
        newend = 2;
    }

    //
    // R_CheckBBox
    // Checks BSP node/subtree bounding box.
    // Returns true
    //  if some part of the bbox might be visible.
    //
    // (Done inline in R_RenderBSPNodeStep.)
    //
    // checkcoord[12][4], flattened
    var checkcoord as Array<Number> = [
        3, 0, 2, 1,
        3, 0, 2, 0,
        3, 1, 2, 0,
        0, 0, 0, 0,
        2, 0, 2, 1,
        0, 0, 0, 0,
        3, 1, 3, 0,
        0, 0, 0, 0,
        2, 0, 3, 1,
        2, 1, 3, 1,
        2, 1, 3, 0,
        0, 0, 0, 0
    ] as Array<Number>;

    //
    // RenderBSPNode
    // Renders all subsectors below a given node,
    //  traversing subtree recursively.
    // Just call with BSP root.
    //
    // Each stack entry is a node number, or a "check the back side" entry
    // stored as -(node * 2 + side) - 2 once the front child is pushed.
    //
    const MAXBSPSTACK = 128;
    var bspstack as Array<Number> = new [MAXBSPSTACK] as Array<Number>;
    var bspsp as Number = 0;

    function R_RenderBSPNode(bspnum as Number) as Void {
        bspstack[0] = bspnum;
        bspsp = 1;
    }

    //
    // The seg ranges R_SubsectorLines found for the current subsector, in
    // the order R_AddLine would have clipped them.
    //
    const MAXQUEUE = 64;
    var qline as Array<Number> = new [MAXQUEUE] as Array<Number>;
    var qback as Array<Number> = new [MAXQUEUE] as Array<Number>;
    var qangle as Array<Number> = new [MAXQUEUE] as Array<Number>;
    var qx1 as Array<Number> = new [MAXQUEUE] as Array<Number>;
    var qx2 as Array<Number> = new [MAXQUEUE] as Array<Number>;
    var qsolid as Array<Boolean> = new [MAXQUEUE] as Array<Boolean>;
    var qcount as Number = 0;

    // R_Subsector with R_AddLine and its R_PointToAngle calls inlined,
    // except that a visible range is queued instead of clipped straight
    // away. R_AddLine's tests only look at angles and sector heights, never
    // at the clip list, so clipping the queue afterwards in order gives
    // the same result.
    function R_SubsectorLines(num as Number) as Void {
        var ss_sector = PSetup.subsectors_sector;
        var ss_numlines = PSetup.subsectors_numlines;
        var ss_firstline = PSetup.subsectors_firstline;
        var segs_v1 = PSetup.segs_v1;
        var segs_v2 = PSetup.segs_v2;
        var segs_backsector = PSetup.segs_backsector;
        var segs_sidedef = PSetup.segs_sidedef;
        var vxy = PSetup.vertexes_xy;
        var floorheight = PSetup.sectors_floorheight;
        var ceilingheight = PSetup.sectors_ceilingheight;
        var floorpic = PSetup.sectors_floorpic;
        var ceilingpic = PSetup.sectors_ceilingpic;
        var lightlevel = PSetup.sectors_lightlevel;
        var midtexture = PSetup.sides_midtexture;
        var viewx = RMain.viewx;
        var viewy = RMain.viewy;
        var viewz = RMain.viewz;
        var viewangle = RMain.viewangle;
        var clipangle = RMain.clipangle;
        var clip2 = 2 * clipangle;
        var viewangletox = RMain.viewangletox;
        var tantoangle = Tables.tantoangle;
        var skyflatnum = RData.skyflatnum;
        var MININT = DoomType.MININT;
        var px1 = 0;
        var py1 = 0;
        var px2 = 0;
        var py2 = 0;
        var angle1 = 0;
        var angle2 = 0;
        qcount = 0;

        RMain.sscount++;
        var front = ss_sector[num];
        frontsector = front;
        var count = ss_numlines[num];
        var line = ss_firstline[num];
        var ffloor = floorheight[front];
        var fceil = ceilingheight[front];

        if (ffloor < viewz) {
            RPlane.floorplane = RPlane.R_FindSectorPlane(front, false);
        } else {
            RPlane.floorplane = -1;
        }
        if (fceil > viewz || ceilingpic[front] == skyflatnum) {
            RPlane.ceilingplane = RPlane.R_FindSectorPlane(front, true);
        } else {
            RPlane.ceilingplane = -1;
        }

        RThings.R_AddSprites(front);

        for (; count > 0; count--) {
            // R_AddLine (line)
            RSegs.work++;
            curline = line;
            // the vertexes are packed x | y << 16 (see PSetup)
            px1 = vxy[segs_v1[line]];
            py1 = px1 & ~0xffff;
            px1 = px1 << 16;
            px2 = vxy[segs_v2[line]];
            py2 = px2 & ~0xffff;
            px2 = px2 << 16;
                // R_PointToAngle for both points (see RMain), folded so
            // the two share one block
            for (var k = 0; k < 2; k++) {
                var x = (k == 0 ? px1 : px2) - viewx;
                var y = (k == 0 ? py1 : py2) - viewy;
                var t;
                if (x == 0 && y == 0) {
                    t = 0;
                } else {
                    var xneg = x < 0;
                    var yneg = y < 0;
                    if (xneg) {
                        x = -x;
                    }
                    if (yneg) {
                        y = -y;
                    }
                    var xbig = x > y;
                    var num2 = xbig ? y : x;
                    var den = xbig ? x : y;
                    var q;
                    if (num2 >= 0 && num2 < 0x10000000 && den >= 512) {
                        q = (num2 << 3) / (den >> 8);
                        if (q > Tables.SLOPERANGE) {
                            q = Tables.SLOPERANGE;
                        }
                    } else {
                        q = Tables.SlopeDiv(num2, den);
                    }
                    t = tantoangle[q];
                    if (!xneg) {
                        if (!yneg) {
                            t = xbig ? t : Tables.ANG90 - 1 - t;
                        } else {
                            t = xbig ? -t : Tables.ANG270 + t;
                        }
                    } else if (!yneg) {
                        t = xbig ? Tables.ANG180 - 1 - t : Tables.ANG90 + t;
                    } else {
                        t = xbig ? Tables.ANG180 + t : Tables.ANG270 - 1 - t;
                    }
                }
                if (k == 0) {
                    angle1 = t;
                } else {
                    angle2 = t;
                }
            }
            var span = angle1 - angle2;

            // Back side? I.e. backface culling?  (span >= ANG180)
            if ((span ^ MININT) >= (Tables.ANG180 ^ MININT)) {
                line++;
                continue;
            }

            // Global angle needed by segcalc.
            var rw_angle1 = angle1;
            angle1 -= viewangle;
            angle2 -= viewangle;

            var tspan = angle1 + clipangle;
            if ((tspan ^ MININT) > (clip2 ^ MININT)) {
                tspan -= clip2;
                // Totally off the left edge?
                if ((tspan ^ MININT) >= (span ^ MININT)) {
                    line++;
                    continue;
                }
                angle1 = clipangle;
            }
            tspan = clipangle - angle2;
            if ((tspan ^ MININT) > (clip2 ^ MININT)) {
                tspan -= clip2;
                if ((tspan ^ MININT) >= (span ^ MININT)) {
                    line++;
                    continue;
                }
                angle2 = -clipangle;
            }

            // The seg is in the view range,
            // but not necessarily visible.
            var x1 = viewangletox[((angle1 + Tables.ANG90) >> Tables.ANGLETOFINESHIFT) & 0x1fff];
            var x2 = viewangletox[((angle2 + Tables.ANG90) >> Tables.ANGLETOFINESHIFT) & 0x1fff];

            // Does not cross a pixel?
            if (x1 == x2) {
                line++;
                continue;
            }

            var back = segs_backsector[line];

            var solid = false;
            var queued = false;
            if (back == -1) {
                // Single sided line: clipsolid
                solid = true;
                queued = true;
            } else {
                var bceil = ceilingheight[back];
                var bfloor = floorheight[back];
                if (bceil <= ffloor || bfloor >= fceil) {
                    // Closed door: clipsolid
                    solid = true;
                    queued = true;
                } else if (bceil != fceil || bfloor != ffloor) {
                    // Window: clippass
                    queued = true;
                } else if (!(ceilingpic[back] == ceilingpic[front]
                             && floorpic[back] == floorpic[front]
                             && lightlevel[back] == lightlevel[front]
                             && midtexture[segs_sidedef[line]] == 0)) {
                    // not an empty trigger line: clippass
                    queued = true;
                }
            }
            if (queued) {
                qline[qcount] = line;
                qback[qcount] = back;
                qangle[qcount] = rw_angle1;
                qx1[qcount] = x1;
                qx2[qcount] = x2;
                qsolid[qcount] = solid;
                qcount++;
            }
            line++;
        }
    }

    // Keeps walking until the tree is done (returns true) or until
    // RSegs.work reaches budget (returns false, call again to resume).
    // Keeps walking until the tree is done (returns true) or until
    // RSegs.work reaches budget (returns false, call again to resume).
    //
    // On the watch a function call costs ~50 us and a module variable
    // read ~23 us, against well under 1 us for a local, and this loop
    // visits every node and every seg of every visible subsector. So
    // R_PointOnSide, R_CheckBBox, R_Subsector, R_AddLine and their
    // R_PointToAngle calls (and DoomType's unsigned compares) are done
    // inline here on locals loaded once per call. The steps and their
    // order are the C code's (r_bsp.c's R_CheckBBox, R_Subsector and
    // R_AddLine, and r_main.c's R_PointOnSide / R_PointToAngle).
    function R_RenderBSPNodeStep(budget as Number) as Boolean {
        var stack = bspstack;
        var sp = bspsp;
        var deadline = RSegs.deadline;

        var children = PSetup.nodes_children;
        var nodes_x = PSetup.nodes_x;
        var nodes_y = PSetup.nodes_y;
        var nodes_dx = PSetup.nodes_dx;
        var nodes_dy = PSetup.nodes_dy;
        var bspcoord = PSetup.nodes_bbox;
        var sf = solidsegs_first;
        var sl = solidsegs_last;
        var cc = checkcoord;

        var viewx = RMain.viewx;
        var viewy = RMain.viewy;
        var viewangle = RMain.viewangle;
        var clipangle = RMain.clipangle;
        var clip2 = 2 * clipangle;
        var viewangletox = RMain.viewangletox;
        var tantoangle = Tables.tantoangle;
        var MININT = DoomType.MININT;

        // the two endpoints whose angles R_PointToAngle is asked for
        var px1 = 0;
        var py1 = 0;
        var px2 = 0;
        var py2 = 0;
        var angle1 = 0;
        var angle2 = 0;

        while (sp > 0) {
            if (RSegs.work >= budget || System.getTimer() >= deadline) {
                bspsp = sp;
                return false;
            }
            sp--;
            var bspnum = stack[sp];

            // kind of step: 0 = divide a node, 1 = R_CheckBBox on the
            // back side of a node, 2 = R_Subsector
            var kind;
            var node = 0;
            var side = 0;
            if (bspnum < -1) {
                var e = -bspnum - 2;
                node = e >> 1;
                side = e & 1;
                kind = 1;
            } else if ((bspnum & DoomData.NF_SUBSECTOR) != 0) {
                kind = 2;
            } else {
                kind = 0;
            }

            if (kind == 0) {
                // R_PointOnSide (viewx, viewy, bsp)
                var ndx = nodes_dx[bspnum];
                var ndy = nodes_dy[bspnum];
                if (ndx == 0) {
                    if (viewx <= nodes_x[bspnum]) {
                        side = ndy > 0 ? 1 : 0;
                    } else {
                        side = ndy < 0 ? 1 : 0;
                    }
                } else if (ndy == 0) {
                    if (viewy <= nodes_y[bspnum]) {
                        side = ndx < 0 ? 1 : 0;
                    } else {
                        side = ndx > 0 ? 1 : 0;
                    }
                } else {
                    var dx = viewx - nodes_x[bspnum];
                    var dy = viewy - nodes_y[bspnum];
                    if (((ndy ^ ndx ^ dx ^ dy) & 0x80000000) != 0) {
                        side = ((ndy ^ dx) & 0x80000000) != 0 ? 1 : 0;
                    } else {
                        // FixedMul (node->dy>>FRACBITS, dx) etc., see RMain
                        var a = ndy >> 16;
                        var left = a * (dx >> 16) + ((a * (dx & 0xffff)) >> 16);
                        a = ndx >> 16;
                        var right = a * (dy >> 16) + ((a * (dy & 0xffff)) >> 16);
                        side = right < left ? 0 : 1;
                    }
                }

                // Recursively divide front space, then come back for the
                // back space.
                stack[sp] = -(bspnum * 2 + side) - 2;
                stack[sp + 1] = children[bspnum * 2 + side];
                sp += 2;
                continue;
            }

            if (kind == 1) {
                // Possibly divide back space: R_CheckBBox (bsp->bbox[side^1])
                var b = node * 8 + (side ^ 1) * 4;
                var boxx;
                var boxy;
                if (viewx <= bspcoord[b + MBBox.BOXLEFT]) {
                    boxx = 0;
                } else if (viewx < bspcoord[b + MBBox.BOXRIGHT]) {
                    boxx = 1;
                } else {
                    boxx = 2;
                }
                if (viewy >= bspcoord[b + MBBox.BOXTOP]) {
                    boxy = 0;
                } else if (viewy > bspcoord[b + MBBox.BOXBOTTOM]) {
                    boxy = 1;
                } else {
                    boxy = 2;
                }
                var boxpos = (boxy << 2) + boxx;
                var visible = true;
                if (boxpos != 5) {
                    var c = boxpos * 4;
                    px1 = bspcoord[b + cc[c]];
                    py1 = bspcoord[b + cc[c + 1]];
                    px2 = bspcoord[b + cc[c + 2]];
                    py2 = bspcoord[b + cc[c + 3]];
                    // R_PointToAngle for both points (see RMain), folded so
                    // the two share one block
                    for (var k = 0; k < 2; k++) {
                        var x = (k == 0 ? px1 : px2) - viewx;
                        var y = (k == 0 ? py1 : py2) - viewy;
                        var t;
                        if (x == 0 && y == 0) {
                            t = 0;
                        } else {
                            var xneg = x < 0;
                            var yneg = y < 0;
                            if (xneg) {
                                x = -x;
                            }
                            if (yneg) {
                                y = -y;
                            }
                            var xbig = x > y;
                            var num2 = xbig ? y : x;
                            var den = xbig ? x : y;
                            var q;
                            if (num2 >= 0 && num2 < 0x10000000 && den >= 512) {
                                q = (num2 << 3) / (den >> 8);
                                if (q > Tables.SLOPERANGE) {
                                    q = Tables.SLOPERANGE;
                                }
                            } else {
                                q = Tables.SlopeDiv(num2, den);
                            }
                            t = tantoangle[q];
                            if (!xneg) {
                                if (!yneg) {
                                    t = xbig ? t : Tables.ANG90 - 1 - t;
                                } else {
                                    t = xbig ? -t : Tables.ANG270 + t;
                                }
                            } else if (!yneg) {
                                t = xbig ? Tables.ANG180 - 1 - t : Tables.ANG90 + t;
                            } else {
                                t = xbig ? Tables.ANG180 + t : Tables.ANG270 - 1 - t;
                            }
                        }
                        if (k == 0) {
                            angle1 = t;
                        } else {
                            angle2 = t;
                        }
                    }
                    angle1 -= viewangle;
                    angle2 -= viewangle;
                    var span = angle1 - angle2;

                    // Sitting on a line?  (span >= ANG180, unsigned)
                    if ((span ^ MININT) < (Tables.ANG180 ^ MININT)) {
                        var tspan = angle1 + clipangle;
                        if ((tspan ^ MININT) > (clip2 ^ MININT)) {
                            tspan -= clip2;
                            // Totally off the left edge?
                            if ((tspan ^ MININT) >= (span ^ MININT)) {
                                visible = false;
                            }
                            angle1 = clipangle;
                        }
                        if (visible) {
                            tspan = clipangle - angle2;
                            if ((tspan ^ MININT) > (clip2 ^ MININT)) {
                                tspan -= clip2;
                                if ((tspan ^ MININT) >= (span ^ MININT)) {
                                    visible = false;
                                }
                                angle2 = -clipangle;
                            }
                        }
                        if (visible) {
                            // Find the first clippost that touches the
                            // source post.
                            var sx1 = viewangletox[((angle1 + Tables.ANG90) >> Tables.ANGLETOFINESHIFT) & 0x1fff];
                            var sx2 = viewangletox[((angle2 + Tables.ANG90) >> Tables.ANGLETOFINESHIFT) & 0x1fff];
                            if (sx1 == sx2) {
                                // Does not cross a pixel.
                                visible = false;
                            } else {
                                sx2--;
                                var start = 0;
                                while (sl[start] < sx2) {
                                    start++;
                                }
                                if (sx1 >= sf[start] && sx2 <= sl[start]) {
                                    // The clippost contains the new span.
                                    visible = false;
                                }
                            }
                        }
                    }
                }
                if (visible) {
                    stack[sp] = children[node * 2 + (side ^ 1)];
                    sp++;
                }
                continue;
            }

            // R_Subsector: work out the subsector's visible seg ranges,
            // then clip them in order. Doing the clipping here instead of
            // inside R_SubsectorLines keeps that function's locals off the
            // stack while R_StoreWallRange and R_RenderSegLoop run; Monkey
            // C's stack only holds about 220 slots.
            R_SubsectorLines(bspnum == -1 ? 0 : (bspnum & ~DoomData.NF_SUBSECTOR));
            for (var i = 0; i < qcount; i++) {
                curline = qline[i];
                backsector = qback[i];
                RSegs.rw_angle1 = qangle[i];
                if (qsolid[i]) {
                    R_ClipSolidWallSegment(qx1[i], qx2[i] - 1);
                } else {
                    R_ClipPassWallSegment(qx1[i], qx2[i] - 1);
                }
            }
        }
        bspsp = 0;
        return true;
    }
}
