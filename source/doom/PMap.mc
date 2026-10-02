// p_map.c
//
// DESCRIPTION:
//	Movement, collision handling.
//	Shooting and aiming.
//
// mobj_t* and line_t* are mobj and line numbers, -1 for NULL. The PIT_*
// and PTR_* callbacks are handed to the PMapUtl iterators as Lang.Method
// objects; a PTR_* function gets an intercept number and reads the
// intercept through PMapUtl.intercepts_frac / _isaline / _d.
//
// Watchdog: P_CheckPosition and P_TryMove only look at the blocks under
// the thing, but P_RadiusAttack and P_ChangeSector walk every block in
// a box (P_ChangeSector the whole sector's blockbox, calling
// P_CheckPosition for every thing in it) and may need splitting.

import Toybox.Lang;

(:extendedCode)
module PMap {

    var tmbbox as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    var tmthing as Number = -1;
    var tmflags as Number = 0;
    var tmx as Number = 0;
    var tmy as Number = 0;

    // If "floatok" true, move would be ok
    // if within "tmfloorz - tmceilingz".
    var floatok as Boolean = false;

    var tmfloorz as Number = 0;
    var tmceilingz as Number = 0;
    var tmdropoffz as Number = 0;

    // keep track of the line that lowers the ceiling,
    // so missiles don't explode against sky hack walls
    var ceilingline as Number = -1;

    // keep track of special lines as they are hit,
    // but don't process them until the move is proven valid
    const MAXSPECIALCROSS = 8;

    var spechit as Array<Number> = new [MAXSPECIALCROSS] as Array<Number>;
    var numspechit as Number = 0;

    //
    // TELEPORT MOVE
    //

    //
    // PIT_StompThing
    //
    function PIT_StompThing(thing as Number) as Boolean {
        if ((PMobj.mobjs_flags[thing] & PMobj.MF_SHOOTABLE) == 0) {
            return true;
        }

        var blockdist = PMobj.mobjs_radius[thing] + PMobj.mobjs_radius[tmthing];

        if (MFixed.abs(PMobj.mobjs_x[thing] - tmx) >= blockdist
            || MFixed.abs(PMobj.mobjs_y[thing] - tmy) >= blockdist) {
            // didn't hit it
            return true;
        }

        // don't clip against self
        if (thing == tmthing) {
            return true;
        }

        // monsters don't stomp things except on boss level
        if (PMobj.mobjs_player[tmthing] == -1 && DoomStat.gamemap != 30) {
            return false;
        }

        PInter.P_DamageMobj(thing, tmthing, tmthing, 10000);

        return true;
    }

    //
    // P_TeleportMove
    //
    function P_TeleportMove(thing as Number, x as Number, y as Number) as Boolean {
        // kill anything occupying the position
        tmthing = thing;
        tmflags = PMobj.mobjs_flags[thing];

        tmx = x;
        tmy = y;

        var radius = PMobj.mobjs_radius[tmthing];
        tmbbox[MBBox.BOXTOP] = y + radius;
        tmbbox[MBBox.BOXBOTTOM] = y - radius;
        tmbbox[MBBox.BOXRIGHT] = x + radius;
        tmbbox[MBBox.BOXLEFT] = x - radius;

        var newsubsec = PMapUtl.P_PointInSubsector(x, y);
        ceilingline = -1;

        // The base floor/ceiling is from the subsector
        // that contains the point.
        // Any contacted lines the step closer together
        // will adjust them.
        var sector = PSetup.subsectors_sector[newsubsec];
        tmfloorz = PSetup.sectors_floorheight[sector];
        tmdropoffz = tmfloorz;
        tmceilingz = PSetup.sectors_ceilingheight[sector];

        RMain.validcount++;
        numspechit = 0;

        // stomp on any things contacted
        var xl = (tmbbox[MBBox.BOXLEFT] - PSetup.bmaporgx - PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
        var xh = (tmbbox[MBBox.BOXRIGHT] - PSetup.bmaporgx + PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
        var yl = (tmbbox[MBBox.BOXBOTTOM] - PSetup.bmaporgy - PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
        var yh = (tmbbox[MBBox.BOXTOP] - PSetup.bmaporgy + PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;

        var func = new Lang.Method(PMap, :PIT_StompThing);
        for (var bx = xl; bx <= xh; bx++) {
            for (var by = yl; by <= yh; by++) {
                if (!PMapUtl.P_BlockThingsIterator(bx, by, func)) {
                    return false;
                }
            }
        }

        // the move is ok,
        // so link the thing into its new position
        PMapUtl.P_UnsetThingPosition(thing);

        PMobj.mobjs_floorz[thing] = tmfloorz;
        PMobj.mobjs_ceilingz[thing] = tmceilingz;
        PMobj.mobjs_x[thing] = x;
        PMobj.mobjs_y[thing] = y;

        PMapUtl.P_SetThingPosition(thing);

        return true;
    }

    //
    // MOVEMENT ITERATOR FUNCTIONS
    //

    //
    // PIT_CheckLine
    // Adjusts tmfloorz and tmceilingz as lines are contacted
    //
    function PIT_CheckLine(ld as Number) as Boolean {
        // ld->bbox, worked out from the vertexes: line_t's bbox isn't
        // stored, to save RAM.
        var x1 = PSetup.vertexes_x[PSetup.lines_v1[ld]];
        var x2 = PSetup.vertexes_x[PSetup.lines_v2[ld]];
        var y1 = PSetup.vertexes_y[PSetup.lines_v1[ld]];
        var y2 = PSetup.vertexes_y[PSetup.lines_v2[ld]];
        var left = x1 < x2 ? x1 : x2;
        var right = x1 < x2 ? x2 : x1;
        var bottom = y1 < y2 ? y1 : y2;
        var top = y1 < y2 ? y2 : y1;
        if (tmbbox[MBBox.BOXRIGHT] <= left
            || tmbbox[MBBox.BOXLEFT] >= right
            || tmbbox[MBBox.BOXTOP] <= bottom
            || tmbbox[MBBox.BOXBOTTOM] >= top) {
            return true;
        }

        if (PMapUtl.P_BoxOnLineSide(tmbbox, ld) != -1) {
            return true;
        }

        // A line has been hit

        // The moving thing's destination position will cross
        // the given line.
        // If this should not be allowed, return false.
        // If the line is special, keep track of it
        // to process later if the move is proven ok.
        // NOTE: specials are NOT sorted by order,
        // so two special lines that are only 8 pixels apart
        // could be crossed in either order.

        if (PSetup.lines_backsector[ld] == -1) {
            return false;   // one sided line
        }

        if ((PMobj.mobjs_flags[tmthing] & PMobj.MF_MISSILE) == 0) {
            var flags = PSetup.lines_flags[ld];
            if ((flags & DoomData.ML_BLOCKING) != 0) {
                return false;   // explicitly blocking everything
            }

            if (PMobj.mobjs_player[tmthing] == -1 && (flags & DoomData.ML_BLOCKMONSTERS) != 0) {
                return false;   // block monsters only
            }
        }

        // set openrange, opentop, openbottom
        PMapUtl.P_LineOpening(ld);

        // adjust floor / ceiling heights
        if (PMapUtl.opentop < tmceilingz) {
            tmceilingz = PMapUtl.opentop;
            ceilingline = ld;
        }

        if (PMapUtl.openbottom > tmfloorz) {
            tmfloorz = PMapUtl.openbottom;
        }

        if (PMapUtl.lowfloor < tmdropoffz) {
            tmdropoffz = PMapUtl.lowfloor;
        }

        // if contacted a special line, add it to the list
        if (PSetup.lines_special[ld] != 0) {
            // The C writes past the end of spechit[8] here (the
            // spechit overflow). Monkey C would throw, so the array
            // grows instead.
            if (numspechit < spechit.size()) {
                spechit[numspechit] = ld;
            } else {
                spechit.add(ld);
            }
            numspechit++;
        }

        return true;
    }

    //
    // PIT_CheckThing
    //
    function PIT_CheckThing(thing as Number) as Boolean {
        var flags = PMobj.mobjs_flags[thing];
        if ((flags & (PMobj.MF_SOLID | PMobj.MF_SPECIAL | PMobj.MF_SHOOTABLE)) == 0) {
            return true;
        }

        var blockdist = PMobj.mobjs_radius[thing] + PMobj.mobjs_radius[tmthing];

        if (MFixed.abs(PMobj.mobjs_x[thing] - tmx) >= blockdist
            || MFixed.abs(PMobj.mobjs_y[thing] - tmy) >= blockdist) {
            // didn't hit it
            return true;
        }

        // don't clip against self
        if (thing == tmthing) {
            return true;
        }

        // check for skulls slamming into things
        if ((PMobj.mobjs_flags[tmthing] & PMobj.MF_SKULLFLY) != 0) {
            var damage = ((MRandom.P_Random() % 8) + 1) * PMobj.info(tmthing, Info.MI_DAMAGE);

            PInter.P_DamageMobj(thing, tmthing, tmthing, damage);

            PMobj.mobjs_flags[tmthing] &= ~PMobj.MF_SKULLFLY;
            PMobj.mobjs_momx[tmthing] = 0;
            PMobj.mobjs_momy[tmthing] = 0;
            PMobj.mobjs_momz[tmthing] = 0;

            PMobj.P_SetMobjState(tmthing, PMobj.info(tmthing, Info.MI_SPAWNSTATE));

            return false;   // stop moving
        }

        // missiles can hit other things
        if ((PMobj.mobjs_flags[tmthing] & PMobj.MF_MISSILE) != 0) {
            // see if it went over / under
            if (PMobj.mobjs_z[tmthing] > PMobj.mobjs_z[thing] + PMobj.mobjs_height[thing]) {
                return true;    // overhead
            }
            if (PMobj.mobjs_z[tmthing] + PMobj.mobjs_height[tmthing] < PMobj.mobjs_z[thing]) {
                return true;    // underneath
            }

            var target = PMobj.mobjs_target[tmthing];
            if (target != -1) {
                var ttype = PMobj.mobjs_type[target];
                var type = PMobj.mobjs_type[thing];
                if (ttype == type
                    || (ttype == Info.MT_KNIGHT && type == Info.MT_BRUISER)
                    || (ttype == Info.MT_BRUISER && type == Info.MT_KNIGHT)) {
                    // Don't hit same species as originator.
                    if (thing == target) {
                        return true;
                    }

                    if (type != Info.MT_PLAYER) {
                        // Explode, but do no damage.
                        // Let players missile other players.
                        return false;
                    }
                }
            }

            if ((flags & PMobj.MF_SHOOTABLE) == 0) {
                // didn't do any damage
                return (flags & PMobj.MF_SOLID) == 0;
            }

            // damage / explode
            var damage = ((MRandom.P_Random() % 8) + 1) * PMobj.info(tmthing, Info.MI_DAMAGE);
            PInter.P_DamageMobj(thing, tmthing, target, damage);

            // don't traverse any more
            return false;
        }

        // check for special pickup
        if ((flags & PMobj.MF_SPECIAL) != 0) {
            var solid = (flags & PMobj.MF_SOLID) != 0;
            if ((tmflags & PMobj.MF_PICKUP) != 0) {
                // can remove thing
                PInter.P_TouchSpecialThing(thing, tmthing);
            }
            return !solid;
        }

        return (flags & PMobj.MF_SOLID) == 0;
    }

    //
    // MOVEMENT CLIPPING
    //

    //
    // P_CheckPosition
    // This is purely informative, nothing is modified
    // (except things picked up).
    //
    // in:
    //  a mobj_t (can be valid or invalid)
    //  a position to be checked
    //   (doesn't need to be related to the mobj_t->x,y)
    //
    // during:
    //  special things are touched if MF_PICKUP
    //  early out on solid lines?
    //
    // out:
    //  newsubsec
    //  floorz
    //  ceilingz
    //  tmdropoffz
    //   the lowest point contacted
    //   (monsters won't move to a dropoff)
    //  speciallines[]
    //  numspeciallines
    //
    // Every monster step and every player move runs this, so for the
    // watch the two block loops don't go through P_BlockThingsIterator /
    // P_BlockLinesIterator and a Method call per thing and line; they are
    // written out in P_CheckThingBlocks and P_CheckLineBlocks below.
    function P_CheckPosition(thing as Number, x as Number, y as Number) as Boolean {
        tmthing = thing;
        tmflags = PMobj.mobjs_flags[thing];

        tmx = x;
        tmy = y;

        var radius = PMobj.mobjs_radius[tmthing];
        tmbbox[MBBox.BOXTOP] = y + radius;
        tmbbox[MBBox.BOXBOTTOM] = y - radius;
        tmbbox[MBBox.BOXRIGHT] = x + radius;
        tmbbox[MBBox.BOXLEFT] = x - radius;

        var newsubsec = PMapUtl.P_PointInSubsector(x, y);
        ceilingline = -1;

        // The base floor / ceiling is from the subsector
        // that contains the point.
        // Any contacted lines the step closer together
        // will adjust them.
        var sector = PSetup.subsectors_sector[newsubsec];
        tmfloorz = PSetup.sectors_floorheight[sector];
        tmdropoffz = tmfloorz;
        tmceilingz = PSetup.sectors_ceilingheight[sector];

        RMain.validcount++;
        numspechit = 0;

        if ((tmflags & PMobj.MF_NOCLIP) != 0) {
            return true;
        }

        // Check things first, possibly picking things up.
        // The bounding box is extended by MAXRADIUS
        // because mobj_ts are grouped into mapblocks
        // based on their origin point, and can overlap
        // into adjacent blocks by up to MAXRADIUS units.
        var xl = (tmbbox[MBBox.BOXLEFT] - PSetup.bmaporgx - PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
        var xh = (tmbbox[MBBox.BOXRIGHT] - PSetup.bmaporgx + PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
        var yl = (tmbbox[MBBox.BOXBOTTOM] - PSetup.bmaporgy - PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
        var yh = (tmbbox[MBBox.BOXTOP] - PSetup.bmaporgy + PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;

        if (!P_CheckThingBlocks(xl, xh, yl, yh)) {
            return false;
        }

        // check lines
        xl = (tmbbox[MBBox.BOXLEFT] - PSetup.bmaporgx) >> PLocal.MAPBLOCKSHIFT;
        xh = (tmbbox[MBBox.BOXRIGHT] - PSetup.bmaporgx) >> PLocal.MAPBLOCKSHIFT;
        yl = (tmbbox[MBBox.BOXBOTTOM] - PSetup.bmaporgy) >> PLocal.MAPBLOCKSHIFT;
        yh = (tmbbox[MBBox.BOXTOP] - PSetup.bmaporgy) >> PLocal.MAPBLOCKSHIFT;

        return P_CheckLineBlocks(xl, xh, yl, yh);
    }

    // P_CheckPosition's
    //  for bx, by: if (!P_BlockThingsIterator(bx, by, PIT_CheckThing))
    //  return false;
    // The tests PIT_CheckThing starts with (none of SOLID / SPECIAL /
    // SHOOTABLE, not within blockdist, tmthing itself) only return true
    // without touching anything, so they're done here with the mobj
    // arrays in locals, and only the things that get past them are handed
    // to PIT_CheckThing, in the same order. bnext is read after the call,
    // like the iterator does.
    function P_CheckThingBlocks(xl as Number, xh as Number, yl as Number, yh as Number) as Boolean {
        var mflags = PMobj.mobjs_flags;
        var mradius = PMobj.mobjs_radius;
        var mx = PMobj.mobjs_x;
        var my = PMobj.mobjs_y;
        var bnext = PMobj.mobjs_bnext;
        var blocklinks = PSetup.blocklinks;
        var thing = tmthing;
        var radius = mradius[thing];
        var x = tmx;
        var y = tmy;
        var mobj;
        var d;

        for (var bx = xl; bx <= xh; bx++) {
            for (var by = yl; by <= yh; by++) {
                if (bx < 0
                    || by < 0
                    || bx >= PSetup.bmapwidth
                    || by >= PSetup.bmapheight) {
                    continue;
                }
                for (mobj = blocklinks[by * PSetup.bmapwidth + bx];
                     mobj != -1;
                     mobj = bnext[mobj]) {
                    if ((mflags[mobj] & (PMobj.MF_SOLID | PMobj.MF_SPECIAL | PMobj.MF_SHOOTABLE)) == 0) {
                        continue;
                    }

                    // blockdist is mradius[mobj] + radius
                    d = mx[mobj] - x;
                    if ((d < 0 ? -d : d) >= mradius[mobj] + radius) {
                        // didn't hit it
                        continue;
                    }
                    d = my[mobj] - y;
                    if ((d < 0 ? -d : d) >= mradius[mobj] + radius) {
                        // didn't hit it
                        continue;
                    }

                    // don't clip against self
                    if (mobj == thing) {
                        continue;
                    }

                    if (!PIT_CheckThing(mobj)) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    // P_CheckPosition's
    //  for bx, by: if (!P_BlockLinesIterator(bx, by, PIT_CheckLine))
    //  return false;
    // with the iterator (see it for the blockmap unpacking and the leading
    // 0 of each list) written out, and PIT_CheckLine's bounding box test,
    // which only returns true, done here before calling it.
    function P_CheckLineBlocks(xl as Number, xh as Number, yl as Number, yh as Number) as Boolean {
        var blockmaplump = PSetup.blockmaplump;
        var linevalid = PSetup.lines_validcount;
        var valid = RMain.validcount;
        var lines_v1 = PSetup.lines_v1;
        var lines_v2 = PSetup.lines_v2;
        var vx = PSetup.vertexes_x;
        var vy = PSetup.vertexes_y;
        var bbox = tmbbox;
        var list;
        var w;
        var ld;
        var a;
        var b;

        for (var bx = xl; bx <= xh; bx++) {
            for (var by = yl; by <= yh; by++) {
                if (bx < 0
                    || by < 0
                    || bx >= PSetup.bmapwidth
                    || by >= PSetup.bmapheight) {
                    continue;
                }

                list = 4 + by * PSetup.bmapwidth + bx;
                w = blockmaplump[list >> 1];
                list = (list & 1) != 0 ? w >> 16 : (w << 16) >> 16;

                for (; true; list++) {
                    w = blockmaplump[list >> 1];
                    ld = (list & 1) != 0 ? w >> 16 : (w << 16) >> 16;
                    if (ld == -1) {
                        break;
                    }

                    if (linevalid[ld] == valid) {
                        // line has already been checked
                        continue;
                    }

                    linevalid[ld] = valid;

                    // PIT_CheckLine: ld->bbox from the vertexes
                    a = vx[lines_v1[ld]];
                    b = vx[lines_v2[ld]];
                    if (bbox[MBBox.BOXRIGHT] <= (a < b ? a : b)
                        || bbox[MBBox.BOXLEFT] >= (a < b ? b : a)) {
                        continue;
                    }
                    a = vy[lines_v1[ld]];
                    b = vy[lines_v2[ld]];
                    if (bbox[MBBox.BOXTOP] <= (a < b ? a : b)
                        || bbox[MBBox.BOXBOTTOM] >= (a < b ? b : a)) {
                        continue;
                    }

                    if (!PIT_CheckLine(ld)) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    //
    // P_TryMove
    // Attempt to move to a new position,
    // crossing special lines unless MF_TELEPORT is set.
    //
    function P_TryMove(thing as Number, x as Number, y as Number) as Boolean {
        floatok = false;
        if (!P_CheckPosition(thing, x, y)) {
            return false;   // solid wall or thing
        }

        var flags = PMobj.mobjs_flags[thing];
        var height = PMobj.mobjs_height[thing];
        var z = PMobj.mobjs_z[thing];

        if ((flags & PMobj.MF_NOCLIP) == 0) {
            if (tmceilingz - tmfloorz < height) {
                return false;   // doesn't fit
            }

            floatok = true;

            if ((flags & PMobj.MF_TELEPORT) == 0
                && tmceilingz - z < height) {
                return false;   // mobj must lower itself to fit
            }

            if ((flags & PMobj.MF_TELEPORT) == 0
                && tmfloorz - z > 24 * MFixed.FRACUNIT) {
                return false;   // too big a step up
            }

            if ((flags & (PMobj.MF_DROPOFF | PMobj.MF_FLOAT)) == 0
                && tmfloorz - tmdropoffz > 24 * MFixed.FRACUNIT) {
                return false;   // don't stand over a dropoff
            }
        }

        // the move is ok,
        // so link the thing into its new position
        PMapUtl.P_UnsetThingPosition(thing);

        var oldx = PMobj.mobjs_x[thing];
        var oldy = PMobj.mobjs_y[thing];
        PMobj.mobjs_floorz[thing] = tmfloorz;
        PMobj.mobjs_ceilingz[thing] = tmceilingz;
        PMobj.mobjs_x[thing] = x;
        PMobj.mobjs_y[thing] = y;

        PMapUtl.P_SetThingPosition(thing);

        // if any special lines were hit, do the effect
        if ((PMobj.mobjs_flags[thing] & (PMobj.MF_TELEPORT | PMobj.MF_NOCLIP)) == 0) {
            // while (numspechit--), which leaves numspechit at -1
            while (true) {
                var n = numspechit;
                numspechit--;
                if (n == 0) {
                    break;
                }
                // see if the line was crossed
                var ld = spechit[numspechit];
                var side = PMapUtl.P_PointOnLineSide(PMobj.mobjs_x[thing], PMobj.mobjs_y[thing], ld);
                var oldside = PMapUtl.P_PointOnLineSide(oldx, oldy, ld);
                if (side != oldside) {
                    if (PSetup.lines_special[ld] != 0) {
                        PSpec.P_CrossSpecialLine(ld, oldside, thing);
                    }
                }
            }
        }

        return true;
    }

    //
    // P_ThingHeightClip
    // Takes a valid thing and adjusts the thing->floorz,
    // thing->ceilingz, and possibly thing->z.
    // This is called for all nearby monsters
    // whenever a sector changes height.
    // If the thing doesn't fit,
    // the z will be set to the lowest value
    // and false will be returned.
    //
    function P_ThingHeightClip(thing as Number) as Boolean {
        var onfloor = (PMobj.mobjs_z[thing] == PMobj.mobjs_floorz[thing]);

        P_CheckPosition(thing, PMobj.mobjs_x[thing], PMobj.mobjs_y[thing]);
        // what about stranding a monster partially off an edge?

        PMobj.mobjs_floorz[thing] = tmfloorz;
        PMobj.mobjs_ceilingz[thing] = tmceilingz;

        if (onfloor) {
            // walking monsters rise and fall with the floor
            PMobj.mobjs_z[thing] = PMobj.mobjs_floorz[thing];
        } else {
            // don't adjust a floating monster unless forced to
            if (PMobj.mobjs_z[thing] + PMobj.mobjs_height[thing] > PMobj.mobjs_ceilingz[thing]) {
                PMobj.mobjs_z[thing] = PMobj.mobjs_ceilingz[thing] - PMobj.mobjs_height[thing];
            }
        }

        if (PMobj.mobjs_ceilingz[thing] - PMobj.mobjs_floorz[thing] < PMobj.mobjs_height[thing]) {
            return false;
        }

        return true;
    }

    //
    // SLIDE MOVE
    // Allows the player to slide along any angled walls.
    //
    var bestslidefrac as Number = 0;
    var secondslidefrac as Number = 0;

    var bestslideline as Number = -1;
    var secondslideline as Number = -1;

    var slidemo as Number = -1;

    var tmxmove as Number = 0;
    var tmymove as Number = 0;

    //
    // P_HitSlideLine
    // Adjusts the xmove / ymove
    // so that the next move will slide along the wall.
    //
    function P_HitSlideLine(ld as Number) as Void {
        if (PSetup.lines_slopetype[ld] == RDefs.ST_HORIZONTAL) {
            tmymove = 0;
            return;
        }

        if (PSetup.lines_slopetype[ld] == RDefs.ST_VERTICAL) {
            tmxmove = 0;
            return;
        }

        var side = PMapUtl.P_PointOnLineSide(PMobj.mobjs_x[slidemo], PMobj.mobjs_y[slidemo], ld);

        var lineangle = RMain.R_PointToAngle2(0, 0, PSetup.lines_dx[ld], PSetup.lines_dy[ld]);

        if (side == 1) {
            lineangle += Tables.ANG180;
        }

        var moveangle = RMain.R_PointToAngle2(0, 0, tmxmove, tmymove);
        var deltaangle = moveangle - lineangle;

        // angle_t is unsigned
        if (DoomType.UGT(deltaangle, Tables.ANG180)) {
            deltaangle += Tables.ANG180;
        }
        //	I_Error ("SlideLine: ang>ANG180");

        lineangle = DoomType.USHR(lineangle, Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        deltaangle = DoomType.USHR(deltaangle, Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;

        var movelen = PMapUtl.P_AproxDistance(tmxmove, tmymove);
        var newlen = MFixed.FixedMul(movelen, Tables.finesine[Tables.FINECOSINE + deltaangle]);

        tmxmove = MFixed.FixedMul(newlen, Tables.finesine[Tables.FINECOSINE + lineangle]);
        tmymove = MFixed.FixedMul(newlen, Tables.finesine[lineangle]);
    }

    //
    // PTR_SlideTraverse
    //
    function PTR_SlideTraverse(in as Number) as Boolean {
        if (!PMapUtl.intercepts_isaline[in]) {
            ISystem.I_Error("PTR_SlideTraverse: not a line?");
        }

        var li = PMapUtl.intercepts_d[in];

        // (goto isblocking becomes a flag)
        var isblocking = false;
        if ((PSetup.lines_flags[li] & DoomData.ML_TWOSIDED) == 0) {
            if (PMapUtl.P_PointOnLineSide(PMobj.mobjs_x[slidemo], PMobj.mobjs_y[slidemo], li) != 0) {
                // don't hit the back side
                return true;
            }
            isblocking = true;
        } else {
            // set openrange, opentop, openbottom
            PMapUtl.P_LineOpening(li);

            var height = PMobj.mobjs_height[slidemo];
            var z = PMobj.mobjs_z[slidemo];
            if (PMapUtl.openrange < height) {
                isblocking = true;      // doesn't fit
            } else if (PMapUtl.opentop - z < height) {
                isblocking = true;      // mobj is too high
            } else if (PMapUtl.openbottom - z > 24 * MFixed.FRACUNIT) {
                isblocking = true;      // too big a step up
            }
        }

        if (!isblocking) {
            // this line doesn't block movement
            return true;
        }

        // the line does block movement,
        // see if it is closer than best so far
        var frac = PMapUtl.intercepts_frac[in];
        if (frac < bestslidefrac) {
            secondslidefrac = bestslidefrac;
            secondslideline = bestslideline;
            bestslidefrac = frac;
            bestslideline = li;
        }

        return false;   // stop
    }

    //
    // P_SlideMove
    // The momx / momy move is bad, so try to slide
    // along a wall.
    // Find the first line hit, move flush to it,
    // and slide along it
    //
    // This is a kludgy mess.
    //
    // (the retry and stairstep gotos become a loop and P_SlideStairstep)
    //
    function P_SlideMove(mo as Number) as Void {
        slidemo = mo;
        var hitcount = 0;
        var trav = new Lang.Method(PMap, :PTR_SlideTraverse);

        // retry:
        while (true) {
            hitcount++;
            if (hitcount == 3) {
                P_SlideStairstep(mo);   // don't loop forever
                return;
            }

            var x = PMobj.mobjs_x[mo];
            var y = PMobj.mobjs_y[mo];
            var radius = PMobj.mobjs_radius[mo];
            var momx = PMobj.mobjs_momx[mo];
            var momy = PMobj.mobjs_momy[mo];
            var leadx;
            var leady;
            var trailx;
            var traily;

            // trace along the three leading corners
            if (momx > 0) {
                leadx = x + radius;
                trailx = x - radius;
            } else {
                leadx = x - radius;
                trailx = x + radius;
            }

            if (momy > 0) {
                leady = y + radius;
                traily = y - radius;
            } else {
                leady = y - radius;
                traily = y + radius;
            }

            bestslidefrac = MFixed.FRACUNIT + 1;

            PMapUtl.P_PathTraverse(leadx, leady, leadx + momx, leady + momy,
                                   PLocal.PT_ADDLINES, trav);
            PMapUtl.P_PathTraverse(trailx, leady, trailx + momx, leady + momy,
                                   PLocal.PT_ADDLINES, trav);
            PMapUtl.P_PathTraverse(leadx, traily, leadx + momx, traily + momy,
                                   PLocal.PT_ADDLINES, trav);

            // move up to the wall
            if (bestslidefrac == MFixed.FRACUNIT + 1) {
                // the move most have hit the middle, so stairstep
                P_SlideStairstep(mo);
                return;
            }

            // fudge a bit to make sure it doesn't hit
            bestslidefrac -= 0x800;
            if (bestslidefrac > 0) {
                var newx = MFixed.FixedMul(momx, bestslidefrac);
                var newy = MFixed.FixedMul(momy, bestslidefrac);

                if (!P_TryMove(mo, PMobj.mobjs_x[mo] + newx, PMobj.mobjs_y[mo] + newy)) {
                    P_SlideStairstep(mo);
                    return;
                }
            }

            // Now continue along the wall.
            // First calculate remainder.
            bestslidefrac = MFixed.FRACUNIT - (bestslidefrac + 0x800);

            if (bestslidefrac > MFixed.FRACUNIT) {
                bestslidefrac = MFixed.FRACUNIT;
            }

            if (bestslidefrac <= 0) {
                return;
            }

            tmxmove = MFixed.FixedMul(PMobj.mobjs_momx[mo], bestslidefrac);
            tmymove = MFixed.FixedMul(PMobj.mobjs_momy[mo], bestslidefrac);

            P_HitSlideLine(bestslideline);  // clip the moves

            PMobj.mobjs_momx[mo] = tmxmove;
            PMobj.mobjs_momy[mo] = tmymove;

            if (!P_TryMove(mo, PMobj.mobjs_x[mo] + tmxmove, PMobj.mobjs_y[mo] + tmymove)) {
                continue;   // goto retry
            }
            return;
        }
    }

    // stairstep: label in P_SlideMove
    function P_SlideStairstep(mo as Number) as Void {
        if (!P_TryMove(mo, PMobj.mobjs_x[mo], PMobj.mobjs_y[mo] + PMobj.mobjs_momy[mo])) {
            P_TryMove(mo, PMobj.mobjs_x[mo] + PMobj.mobjs_momx[mo], PMobj.mobjs_y[mo]);
        }
    }

    //
    // P_LineAttack
    //
    var linetarget as Number = -1;  // who got hit (or NULL)
    var shootthing as Number = -1;

    // Height if not aiming up or down
    // ???: use slope for monsters?
    var shootz as Number = 0;

    var la_damage as Number = 0;
    var attackrange as Number = 0;

    var aimslope as Number = 0;

    // slopes to top and bottom of target
    // (topslope and bottomslope live in PSight, as in p_sight.c)

    //
    // PTR_AimTraverse
    // Sets linetaget and aimslope when a target is aimed at.
    //
    function PTR_AimTraverse(in as Number) as Boolean {
        if (PMapUtl.intercepts_isaline[in]) {
            var li = PMapUtl.intercepts_d[in];

            if ((PSetup.lines_flags[li] & DoomData.ML_TWOSIDED) == 0) {
                return false;   // stop
            }

            // Crosses a two sided line.
            // A two sided line will restrict
            // the possible target ranges.
            PMapUtl.P_LineOpening(li);

            if (PMapUtl.openbottom >= PMapUtl.opentop) {
                return false;   // stop
            }

            var dist = MFixed.FixedMul(attackrange, PMapUtl.intercepts_frac[in]);

            var front = PSetup.lines_frontsector[li];
            var back = PSetup.lines_backsector[li];
            if (PSetup.sectors_floorheight[front] != PSetup.sectors_floorheight[back]) {
                var slope = MFixed.FixedDiv(PMapUtl.openbottom - shootz, dist);
                if (slope > PSight.bottomslope) {
                    PSight.bottomslope = slope;
                }
            }

            if (PSetup.sectors_ceilingheight[front] != PSetup.sectors_ceilingheight[back]) {
                var slope = MFixed.FixedDiv(PMapUtl.opentop - shootz, dist);
                if (slope < PSight.topslope) {
                    PSight.topslope = slope;
                }
            }

            if (PSight.topslope <= PSight.bottomslope) {
                return false;   // stop
            }

            return true;        // shot continues
        }

        // shoot a thing
        var th = PMapUtl.intercepts_d[in];
        if (th == shootthing) {
            return true;        // can't shoot self
        }

        if ((PMobj.mobjs_flags[th] & PMobj.MF_SHOOTABLE) == 0) {
            return true;        // corpse or something
        }

        // check angles to see if the thing can be aimed at
        var dist = MFixed.FixedMul(attackrange, PMapUtl.intercepts_frac[in]);
        var thingtopslope = MFixed.FixedDiv(PMobj.mobjs_z[th] + PMobj.mobjs_height[th] - shootz, dist);

        if (thingtopslope < PSight.bottomslope) {
            return true;        // shot over the thing
        }

        var thingbottomslope = MFixed.FixedDiv(PMobj.mobjs_z[th] - shootz, dist);

        if (thingbottomslope > PSight.topslope) {
            return true;        // shot under the thing
        }

        // this thing can be hit!
        if (thingtopslope > PSight.topslope) {
            thingtopslope = PSight.topslope;
        }

        if (thingbottomslope < PSight.bottomslope) {
            thingbottomslope = PSight.bottomslope;
        }

        aimslope = (thingtopslope + thingbottomslope) / 2;
        linetarget = th;

        return false;           // don't go any farther
    }

    //
    // PTR_ShootTraverse
    //
    function PTR_ShootTraverse(in as Number) as Boolean {
        var trace = PMapUtl.trace;
        var infrac = PMapUtl.intercepts_frac[in];

        if (PMapUtl.intercepts_isaline[in]) {
            var li = PMapUtl.intercepts_d[in];

            if (PSetup.lines_special[li] != 0) {
                PSpec.P_ShootSpecialLine(shootthing, li);
            }

            // (goto hitline becomes a flag)
            var hitline = false;
            var front = PSetup.lines_frontsector[li];
            var back = PSetup.lines_backsector[li];

            if ((PSetup.lines_flags[li] & DoomData.ML_TWOSIDED) == 0) {
                hitline = true;
            } else {
                // crosses a two sided line
                PMapUtl.P_LineOpening(li);

                var dist = MFixed.FixedMul(attackrange, infrac);

                if (PSetup.sectors_floorheight[front] != PSetup.sectors_floorheight[back]) {
                    var slope = MFixed.FixedDiv(PMapUtl.openbottom - shootz, dist);
                    if (slope > aimslope) {
                        hitline = true;
                    }
                }

                if (!hitline
                    && PSetup.sectors_ceilingheight[front] != PSetup.sectors_ceilingheight[back]) {
                    var slope = MFixed.FixedDiv(PMapUtl.opentop - shootz, dist);
                    if (slope < aimslope) {
                        hitline = true;
                    }
                }
            }

            if (!hitline) {
                // shot continues
                return true;
            }

            // hit line
            // position a bit closer
            var frac = infrac - MFixed.FixedDiv(4 * MFixed.FRACUNIT, attackrange);
            var x = trace[PMapUtl.DL_X] + MFixed.FixedMul(trace[PMapUtl.DL_DX], frac);
            var y = trace[PMapUtl.DL_Y] + MFixed.FixedMul(trace[PMapUtl.DL_DY], frac);
            var z = shootz + MFixed.FixedMul(aimslope, MFixed.FixedMul(frac, attackrange));

            if (PSetup.sectors_ceilingpic[front] == RData.skyflatnum) {
                // don't shoot the sky!
                if (z > PSetup.sectors_ceilingheight[front]) {
                    return false;
                }

                // it's a sky hack wall
                if (back != -1 && PSetup.sectors_ceilingpic[back] == RData.skyflatnum) {
                    return false;
                }
            }

            // Spawn bullet puffs.
            PMobj.P_SpawnPuff(x, y, z);

            // don't go any farther
            return false;
        }

        // shoot a thing
        var th = PMapUtl.intercepts_d[in];
        if (th == shootthing) {
            return true;        // can't shoot self
        }

        if ((PMobj.mobjs_flags[th] & PMobj.MF_SHOOTABLE) == 0) {
            return true;        // corpse or something
        }

        // check angles to see if the thing can be aimed at
        var dist = MFixed.FixedMul(attackrange, infrac);
        var thingtopslope = MFixed.FixedDiv(PMobj.mobjs_z[th] + PMobj.mobjs_height[th] - shootz, dist);

        if (thingtopslope < aimslope) {
            return true;        // shot over the thing
        }

        var thingbottomslope = MFixed.FixedDiv(PMobj.mobjs_z[th] - shootz, dist);

        if (thingbottomslope > aimslope) {
            return true;        // shot under the thing
        }

        // hit thing
        // position a bit closer
        var frac = infrac - MFixed.FixedDiv(10 * MFixed.FRACUNIT, attackrange);

        var x = trace[PMapUtl.DL_X] + MFixed.FixedMul(trace[PMapUtl.DL_DX], frac);
        var y = trace[PMapUtl.DL_Y] + MFixed.FixedMul(trace[PMapUtl.DL_DY], frac);
        var z = shootz + MFixed.FixedMul(aimslope, MFixed.FixedMul(frac, attackrange));

        // Spawn bullet puffs or blod spots,
        // depending on target type.
        if ((PMobj.mobjs_flags[th] & PMobj.MF_NOBLOOD) != 0) {
            PMobj.P_SpawnPuff(x, y, z);
        } else {
            PMobj.P_SpawnBlood(x, y, z, la_damage);
        }

        if (la_damage != 0) {
            PInter.P_DamageMobj(th, shootthing, shootthing, la_damage);
        }

        // don't go any farther
        return false;
    }

    //
    // P_AimLineAttack
    //
    function P_AimLineAttack(t1 as Number, angle as Number, distance as Number) as Number {
        // angle_t is unsigned
        angle = DoomType.USHR(angle, Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        shootthing = t1;

        var x2 = PMobj.mobjs_x[t1] + (distance >> MFixed.FRACBITS) * Tables.finesine[Tables.FINECOSINE + angle];
        var y2 = PMobj.mobjs_y[t1] + (distance >> MFixed.FRACBITS) * Tables.finesine[angle];
        shootz = PMobj.mobjs_z[t1] + (PMobj.mobjs_height[t1] >> 1) + 8 * MFixed.FRACUNIT;

        // can't shoot outside view angles
        PSight.topslope = 100 * MFixed.FRACUNIT / 160;
        PSight.bottomslope = -100 * MFixed.FRACUNIT / 160;

        attackrange = distance;
        linetarget = -1;

        PMapUtl.P_PathTraverse(PMobj.mobjs_x[t1], PMobj.mobjs_y[t1],
                               x2, y2,
                               PLocal.PT_ADDLINES | PLocal.PT_ADDTHINGS,
                               new Lang.Method(PMap, :PTR_AimTraverse));

        if (linetarget != -1) {
            return aimslope;
        }

        return 0;
    }

    //
    // P_LineAttack
    // If damage == 0, it is just a test trace
    // that will leave linetarget set.
    //
    function P_LineAttack(t1 as Number, angle as Number, distance as Number, slope as Number, damage as Number) as Void {
        // angle_t is unsigned
        angle = DoomType.USHR(angle, Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        shootthing = t1;
        la_damage = damage;
        var x2 = PMobj.mobjs_x[t1] + (distance >> MFixed.FRACBITS) * Tables.finesine[Tables.FINECOSINE + angle];
        var y2 = PMobj.mobjs_y[t1] + (distance >> MFixed.FRACBITS) * Tables.finesine[angle];
        shootz = PMobj.mobjs_z[t1] + (PMobj.mobjs_height[t1] >> 1) + 8 * MFixed.FRACUNIT;
        attackrange = distance;
        aimslope = slope;

        PMapUtl.P_PathTraverse(PMobj.mobjs_x[t1], PMobj.mobjs_y[t1],
                               x2, y2,
                               PLocal.PT_ADDLINES | PLocal.PT_ADDTHINGS,
                               new Lang.Method(PMap, :PTR_ShootTraverse));
    }

    //
    // USE LINES
    //
    var usething as Number = -1;

    function PTR_UseTraverse(in as Number) as Boolean {
        var line = PMapUtl.intercepts_d[in];

        if (PSetup.lines_special[line] == 0) {
            PMapUtl.P_LineOpening(line);
            if (PMapUtl.openrange <= 0) {
                SSound.S_StartSound(usething, SSound.sfx_noway);

                // can't use through a wall
                return false;
            }
            // not a special line, but keep checking
            return true;
        }

        var side = 0;
        if (PMapUtl.P_PointOnLineSide(PMobj.mobjs_x[usething], PMobj.mobjs_y[usething], line) == 1) {
            side = 1;
        }

        //	return false;		// don't use back side

        PSwitch.P_UseSpecialLine(usething, line, side);

        // can't use for than one special line in a row
        return false;
    }

    //
    // P_UseLines
    // Looks for special lines in front of the player to activate.
    //
    // player is a player number.
    //
    function P_UseLines(player as Number) as Void {
        var mo = DPlayer.players_mo[player];
        usething = mo;

        // mo->angle is unsigned
        var angle = DoomType.USHR(PMobj.mobjs_angle[mo], Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;

        var x1 = PMobj.mobjs_x[mo];
        var y1 = PMobj.mobjs_y[mo];
        var x2 = x1 + (PLocal.USERANGE >> MFixed.FRACBITS) * Tables.finesine[Tables.FINECOSINE + angle];
        var y2 = y1 + (PLocal.USERANGE >> MFixed.FRACBITS) * Tables.finesine[angle];

        PMapUtl.P_PathTraverse(x1, y1, x2, y2, PLocal.PT_ADDLINES,
                               new Lang.Method(PMap, :PTR_UseTraverse));
    }

    //
    // RADIUS ATTACK
    //
    var bombsource as Number = -1;
    var bombspot as Number = -1;
    var bombdamage as Number = 0;

    //
    // PIT_RadiusAttack
    // "bombsource" is the creature
    // that caused the explosion at "bombspot".
    //
    function PIT_RadiusAttack(thing as Number) as Boolean {
        if ((PMobj.mobjs_flags[thing] & PMobj.MF_SHOOTABLE) == 0) {
            return true;
        }

        // Boss spider and cyborg
        // take no damage from concussion.
        var type = PMobj.mobjs_type[thing];
        if (type == Info.MT_CYBORG
            || type == Info.MT_SPIDER) {
            return true;
        }

        var dx = MFixed.abs(PMobj.mobjs_x[thing] - PMobj.mobjs_x[bombspot]);
        var dy = MFixed.abs(PMobj.mobjs_y[thing] - PMobj.mobjs_y[bombspot]);

        var dist = dx > dy ? dx : dy;
        dist = (dist - PMobj.mobjs_radius[thing]) >> MFixed.FRACBITS;

        if (dist < 0) {
            dist = 0;
        }

        if (dist >= bombdamage) {
            return true;    // out of range
        }

        if (PSight.P_CheckSight(thing, bombspot)) {
            // must be in direct path
            PInter.P_DamageMobj(thing, bombspot, bombsource, bombdamage - dist);
        }

        return true;
    }

    //
    // P_RadiusAttack
    // Source is the creature that caused the explosion at spot.
    //
    function P_RadiusAttack(spot as Number, source as Number, damage as Number) as Void {
        var dist = (damage + PLocal.MAXRADIUS) << MFixed.FRACBITS;
        var yh = (PMobj.mobjs_y[spot] + dist - PSetup.bmaporgy) >> PLocal.MAPBLOCKSHIFT;
        var yl = (PMobj.mobjs_y[spot] - dist - PSetup.bmaporgy) >> PLocal.MAPBLOCKSHIFT;
        var xh = (PMobj.mobjs_x[spot] + dist - PSetup.bmaporgx) >> PLocal.MAPBLOCKSHIFT;
        var xl = (PMobj.mobjs_x[spot] - dist - PSetup.bmaporgx) >> PLocal.MAPBLOCKSHIFT;
        bombspot = spot;
        bombsource = source;
        bombdamage = damage;

        var func = new Lang.Method(PMap, :PIT_RadiusAttack);
        for (var y = yl; y <= yh; y++) {
            for (var x = xl; x <= xh; x++) {
                PMapUtl.P_BlockThingsIterator(x, y, func);
            }
        }
    }

    //
    // SECTOR HEIGHT CHANGING
    // After modifying a sectors floor or ceiling height,
    // call this routine to adjust the positions
    // of all things that touch the sector.
    //
    // If anything doesn't fit anymore, true will be returned.
    // If crunch is true, they will take damage
    //  as they are being crushed.
    // If Crunch is false, you should set the sector height back
    //  the way it was and call P_ChangeSector again
    //  to undo the changes.
    //
    var crushchange as Boolean = false;
    var nofit as Boolean = false;

    //
    // PIT_ChangeSector
    //
    function PIT_ChangeSector(thing as Number) as Boolean {
        if (P_ThingHeightClip(thing)) {
            // keep checking
            return true;
        }

        // crunch bodies to giblets
        if (PMobj.mobjs_health[thing] <= 0) {
            PMobj.P_SetMobjState(thing, Info.S_GIBS);

            PMobj.mobjs_flags[thing] &= ~PMobj.MF_SOLID;
            PMobj.mobjs_height[thing] = 0;
            PMobj.mobjs_radius[thing] = 0;

            // keep checking
            return true;
        }

        // crunch dropped items
        if ((PMobj.mobjs_flags[thing] & PMobj.MF_DROPPED) != 0) {
            PMobj.P_RemoveMobj(thing);

            // keep checking
            return true;
        }

        if ((PMobj.mobjs_flags[thing] & PMobj.MF_SHOOTABLE) == 0) {
            // assume it is bloody gibs or something
            return true;
        }

        nofit = true;

        if (crushchange && (PTick.leveltime & 3) == 0) {
            PInter.P_DamageMobj(thing, -1, -1, 10);

            // spray blood in a random direction
            var mo = PMobj.P_SpawnMobj(PMobj.mobjs_x[thing],
                                       PMobj.mobjs_y[thing],
                                       PMobj.mobjs_z[thing] + PMobj.mobjs_height[thing] / 2, Info.MT_BLOOD);

            PMobj.mobjs_momx[mo] = (MRandom.P_Random() - MRandom.P_Random()) << 12;
            PMobj.mobjs_momy[mo] = (MRandom.P_Random() - MRandom.P_Random()) << 12;
        }

        // keep checking (crush other things)
        return true;
    }

    //
    // P_ChangeSector
    //
    function P_ChangeSector(sector as Number, crunch as Boolean) as Boolean {
        nofit = false;
        crushchange = crunch;

        var b = sector * 4;
        var blockbox = PSetup.sectors_blockbox;
        var func = new Lang.Method(PMap, :PIT_ChangeSector);

        // re-check heights for all things near the moving sector
        for (var x = blockbox[b + MBBox.BOXLEFT]; x <= blockbox[b + MBBox.BOXRIGHT]; x++) {
            for (var y = blockbox[b + MBBox.BOXBOTTOM]; y <= blockbox[b + MBBox.BOXTOP]; y++) {
                PMapUtl.P_BlockThingsIterator(x, y, func);
            }
        }

        return nofit;
    }
}
