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
    // R_AddLine
    // Clips the given segment
    // and adds any visible pieces to the line list.
    //
    function R_AddLine(line as Number) as Void {
        var clipangle = RMain.clipangle;

        // Culled lines still cost something; count them so the frame
        // budget sees it.
        RSegs.work++;

        curline = line;

        // OPTIMIZE: quickly reject orthogonal back sides.
        var v1 = PSetup.segs_v1[line];
        var v2 = PSetup.segs_v2[line];
        var angle1 = RMain.R_PointToAngle(PSetup.vertexes_x[v1], PSetup.vertexes_y[v1]);
        var angle2 = RMain.R_PointToAngle(PSetup.vertexes_x[v2], PSetup.vertexes_y[v2]);

        // Clip to view edges.
        // OPTIMIZE: make constant out of 2*clipangle (FIELDOFVIEW).
        var span = angle1 - angle2;

        // Back side? I.e. backface culling?
        if (DoomType.UGE(span, Tables.ANG180)) {
            return;
        }

        // Global angle needed by segcalc.
        RSegs.rw_angle1 = angle1;
        angle1 -= RMain.viewangle;
        angle2 -= RMain.viewangle;

        var tspan = angle1 + clipangle;
        if (DoomType.UGT(tspan, 2 * clipangle)) {
            tspan -= 2 * clipangle;

            // Totally off the left edge?
            if (DoomType.UGE(tspan, span)) {
                return;
            }

            angle1 = clipangle;
        }
        tspan = clipangle - angle2;
        if (DoomType.UGT(tspan, 2 * clipangle)) {
            tspan -= 2 * clipangle;

            // Totally off the left edge?
            if (DoomType.UGE(tspan, span)) {
                return;
            }
            angle2 = -clipangle;
        }

        // The seg is in the view range,
        // but not necessarily visible.
        angle1 = DoomType.USHR(angle1 + Tables.ANG90, Tables.ANGLETOFINESHIFT);
        angle2 = DoomType.USHR(angle2 + Tables.ANG90, Tables.ANGLETOFINESHIFT);
        var x1 = RMain.viewangletox[angle1];
        var x2 = RMain.viewangletox[angle2];

        // Does not cross a pixel?
        if (x1 == x2) {
            return;
        }

        backsector = PSetup.segs_backsector[line];

        // Single sided line?
        if (backsector == -1) {
            // goto clipsolid
            R_ClipSolidWallSegment(x1, x2 - 1);
            return;
        }

        var bceil = PSetup.sectors_ceilingheight[backsector];
        var bfloor = PSetup.sectors_floorheight[backsector];
        var fceil = PSetup.sectors_ceilingheight[frontsector];
        var ffloor = PSetup.sectors_floorheight[frontsector];

        // Closed door.
        if (bceil <= ffloor || bfloor >= fceil) {
            // goto clipsolid
            R_ClipSolidWallSegment(x1, x2 - 1);
            return;
        }

        // Window.
        if (bceil != fceil || bfloor != ffloor) {
            // goto clippass
            R_ClipPassWallSegment(x1, x2 - 1);
            return;
        }

        // Reject empty lines used for triggers
        //  and special events.
        // Identical floor and ceiling on both sides,
        // identical light levels on both sides,
        // and no middle texture.
        if (PSetup.sectors_ceilingpic[backsector] == PSetup.sectors_ceilingpic[frontsector]
            && PSetup.sectors_floorpic[backsector] == PSetup.sectors_floorpic[frontsector]
            && PSetup.sectors_lightlevel[backsector] == PSetup.sectors_lightlevel[frontsector]
            && PSetup.sides_midtexture[PSetup.segs_sidedef[line]] == 0) {
            return;
        }

        // clippass:
        R_ClipPassWallSegment(x1, x2 - 1);
    }

    //
    // R_CheckBBox
    // Checks BSP node/subtree bounding box.
    // Returns true
    //  if some part of the bbox might be visible.
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

    // bspcoord is nodes_bbox[b .. b+3]
    function R_CheckBBox(b as Number) as Boolean {
        var bspcoord = PSetup.nodes_bbox;
        var viewx = RMain.viewx;
        var viewy = RMain.viewy;
        var clipangle = RMain.clipangle;
        var boxx;
        var boxy;

        // Find the corners of the box
        // that define the edges from current viewpoint.
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
        if (boxpos == 5) {
            return true;
        }

        var c = boxpos * 4;
        var x1 = bspcoord[b + checkcoord[c]];
        var y1 = bspcoord[b + checkcoord[c + 1]];
        var x2 = bspcoord[b + checkcoord[c + 2]];
        var y2 = bspcoord[b + checkcoord[c + 3]];

        // check clip list for an open space
        var angle1 = RMain.R_PointToAngle(x1, y1) - RMain.viewangle;
        var angle2 = RMain.R_PointToAngle(x2, y2) - RMain.viewangle;

        var span = angle1 - angle2;

        // Sitting on a line?
        if (DoomType.UGE(span, Tables.ANG180)) {
            return true;
        }

        var tspan = angle1 + clipangle;

        if (DoomType.UGT(tspan, 2 * clipangle)) {
            tspan -= 2 * clipangle;

            // Totally off the left edge?
            if (DoomType.UGE(tspan, span)) {
                return false;
            }

            angle1 = clipangle;
        }
        tspan = clipangle - angle2;
        if (DoomType.UGT(tspan, 2 * clipangle)) {
            tspan -= 2 * clipangle;

            // Totally off the left edge?
            if (DoomType.UGE(tspan, span)) {
                return false;
            }

            angle2 = -clipangle;
        }

        // Find the first clippost
        //  that touches the source post
        //  (adjacent pixels are touching).
        angle1 = DoomType.USHR(angle1 + Tables.ANG90, Tables.ANGLETOFINESHIFT);
        angle2 = DoomType.USHR(angle2 + Tables.ANG90, Tables.ANGLETOFINESHIFT);
        var sx1 = RMain.viewangletox[angle1];
        var sx2 = RMain.viewangletox[angle2];

        // Does not cross a pixel.
        if (sx1 == sx2) {
            return false;
        }
        sx2--;

        var start = 0;
        while (solidsegs_last[start] < sx2) {
            start++;
        }

        if (sx1 >= solidsegs_first[start] && sx2 <= solidsegs_last[start]) {
            // The clippost contains the new span.
            return false;
        }

        return true;
    }

    //
    // R_Subsector
    // Determine floor/ceiling planes.
    // Add sprites of things in sector.
    // Draw one or more line segments.
    //
    function R_Subsector(num as Number) as Void {
        RMain.sscount++;
        frontsector = PSetup.subsectors_sector[num];
        var count = PSetup.subsectors_numlines[num];
        var line = PSetup.subsectors_firstline[num];

        if (PSetup.sectors_floorheight[frontsector] < RMain.viewz) {
            RPlane.floorplane = RPlane.R_FindPlane(PSetup.sectors_floorheight[frontsector],
                                                   PSetup.sectors_floorpic[frontsector],
                                                   PSetup.sectors_lightlevel[frontsector]);
        } else {
            RPlane.floorplane = -1;
        }

        if (PSetup.sectors_ceilingheight[frontsector] > RMain.viewz
            || PSetup.sectors_ceilingpic[frontsector] == RData.skyflatnum) {
            RPlane.ceilingplane = RPlane.R_FindPlane(PSetup.sectors_ceilingheight[frontsector],
                                                     PSetup.sectors_ceilingpic[frontsector],
                                                     PSetup.sectors_lightlevel[frontsector]);
        } else {
            RPlane.ceilingplane = -1;
        }

        // R_AddSprites (frontsector) comes with r_things.

        while (count > 0) {
            count--;
            R_AddLine(line);
            line++;
        }
    }

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

    // Keeps walking until the tree is done (returns true) or until
    // RSegs.work reaches budget (returns false, call again to resume).
    function R_RenderBSPNodeStep(budget as Number) as Boolean {
        var stack = bspstack;
        var children = PSetup.nodes_children;
        var sp = bspsp;

        while (sp > 0) {
            if (RSegs.work >= budget) {
                bspsp = sp;
                return false;
            }
            sp--;
            var bspnum = stack[sp];

            if (bspnum < -1) {
                // Possibly divide back space.
                var e = -bspnum - 2;
                var node = e >> 1;
                var side = e & 1;
                if (R_CheckBBox(node * 8 + (side ^ 1) * 4)) {
                    stack[sp] = children[node * 2 + (side ^ 1)];
                    sp++;
                }
                continue;
            }

            // Found a subsector?
            if ((bspnum & DoomData.NF_SUBSECTOR) != 0) {
                if (bspnum == -1) {
                    R_Subsector(0);
                } else {
                    R_Subsector(bspnum & ~DoomData.NF_SUBSECTOR);
                }
                continue;
            }

            // Decide which side the view point is on.
            var side = RMain.R_PointOnSide(RMain.viewx, RMain.viewy, bspnum);

            // Recursively divide front space, then come back for the
            // back space.
            stack[sp] = -(bspnum * 2 + side) - 2;
            stack[sp + 1] = children[bspnum * 2 + side];
            sp += 2;
        }
        bspsp = 0;
        return true;
    }
}
