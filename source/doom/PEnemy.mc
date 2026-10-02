// p_enemy.c
//
// DESCRIPTION:
//	Enemy thinking, AI.
//	Action Pointer Functions
//	that are associated with states/frames.
//
// mobj_t* are mobj numbers (see PMobj), -1 for NULL; sector_t* and
// line_t* are PSetup indexes.

import Toybox.Lang;

(:extendedCode)
module PEnemy {

    // dirtype_t
    const DI_EAST = 0;
    const DI_NORTHEAST = 1;
    const DI_NORTH = 2;
    const DI_NORTHWEST = 3;
    const DI_WEST = 4;
    const DI_SOUTHWEST = 5;
    const DI_SOUTH = 6;
    const DI_SOUTHEAST = 7;
    const DI_NODIR = 8;
    const NUMDIRS = 9;

    //
    // P_NewChaseDir related LUT.
    //
    const opposite = [
        DI_WEST, DI_SOUTHWEST, DI_SOUTH, DI_SOUTHEAST,
        DI_EAST, DI_NORTHEAST, DI_NORTH, DI_NORTHWEST, DI_NODIR
    ] as Array<Number>;

    const diags = [
        DI_NORTHWEST, DI_NORTHEAST, DI_SOUTHWEST, DI_SOUTHEAST
    ] as Array<Number>;

    // Monkey C can't stub out another module's function, so unit tests
    // put a fixed P_TryMove / P_CheckSight rule here. Always null in the
    // game, where these go straight to PMap / PSight.
    var testTryMove as Method? = null;
    var testCheckSight as Method? = null;

    function P_TryMove(thing as Number, x as Number, y as Number) as Boolean {
        var t = testTryMove;
        if (t != null) {
            return t.invoke(thing, x, y) as Boolean;
        }
        return PMap.P_TryMove(thing, x, y);
    }

    function P_CheckSight(t1 as Number, t2 as Number) as Boolean {
        var t = testCheckSight;
        if (t != null) {
            return t.invoke(t1, t2) as Boolean;
        }
        return PSight.P_CheckSight(t1, t2);
    }

    //
    // ENEMY THINKING
    // Enemies are allways spawned
    // with targetplayer = -1, threshold = 0
    // Most monsters are spawned unaware of all players,
    // but some can be made preaware
    //

    //
    // Called by P_NoiseAlert.
    // Recursively traverse adjacent sectors,
    // sound blocking lines cut off traversal.
    //
    // Monkey C's call stack overflows after a dozen or so of these
    // frames (E1M1 already goes deeper), so the recursion runs on an
    // explicit stack instead, visiting lines in exactly the same order.
    // A sector is only entered again when it's reached with fewer sound
    // blocks than before, so it's on the stack at most twice and the
    // depth is bounded by 2 * numsectors. A noise can still flood the
    // whole map (every line of every reachable sector), which may need
    // splitting for the watchdog on big maps.
    //
    var soundtarget as Number = -1;

    // the recursion's frames: sector, soundblocks, next line index
    var soundstack_sec as Array<Number> = [] as Array<Number>;
    var soundstack_blocks as Array<Number> = [] as Array<Number>;
    var soundstack_i as Array<Number> = [] as Array<Number>;

    function P_RecursiveSound(sec as Number, soundblocks as Number) as Void {
        var validcount = PSetup.sectors_validcount;
        var soundtraversed = PSetup.sectors_soundtraversed;
        var soundtargets = PSetup.sectors_soundtarget;
        var linebuffer = PSetup.linebuffer;
        var sectorlines = PSetup.sectors_lines;
        var linecounts = PSetup.sectors_linecount;
        var flags = PSetup.lines_flags;
        var sidenum = PSetup.lines_sidenum;
        var sidesector = PSetup.sides_sector;
        var valid = RMain.validcount;
        var target = soundtarget;

        var maxdepth = 2 * PSetup.numsectors + 1;
        if (soundstack_sec.size() < maxdepth) {
            soundstack_sec = new [maxdepth] as Array<Number>;
            soundstack_blocks = new [maxdepth] as Array<Number>;
            soundstack_i = new [maxdepth] as Array<Number>;
        }
        var stacksec = soundstack_sec;
        var stackblocks = soundstack_blocks;
        var stacki = soundstack_i;

        // wake up all monsters in this sector
        if (validcount[sec] == valid
            && soundtraversed[sec] <= soundblocks + 1) {
            return;     // already flooded
        }

        validcount[sec] = valid;
        soundtraversed[sec] = soundblocks + 1;
        soundtargets[sec] = target;

        stacksec[0] = sec;
        stackblocks[0] = soundblocks;
        stacki[0] = 0;
        var depth = 1;

        while (depth > 0) {
            var top = depth - 1;
            sec = stacksec[top];
            soundblocks = stackblocks[top];
            var i = stacki[top];

            // for (i=0 ;i<sec->linecount ; i++)
            if (i >= linecounts[sec]) {
                depth--;    // return from this sector
                continue;
            }
            stacki[top] = i + 1;

            var check = linebuffer[sectorlines[sec] + i];
            if ((flags[check] & DoomData.ML_TWOSIDED) == 0) {
                continue;
            }

            PMapUtl.P_LineOpening(check);

            if (PMapUtl.openrange <= 0) {
                continue;   // closed door
            }

            var other;
            if (sidesector[sidenum[check * 2]] == sec) {
                other = sidesector[sidenum[check * 2 + 1]];
            } else {
                other = sidesector[sidenum[check * 2]];
            }

            var blocks;
            if ((flags[check] & DoomData.ML_SOUNDBLOCK) != 0) {
                if (soundblocks != 0) {
                    continue;
                }
                blocks = 1;
            } else {
                blocks = soundblocks;
            }

            // P_RecursiveSound (other, blocks)
            if (validcount[other] == valid
                && soundtraversed[other] <= blocks + 1) {
                continue;   // already flooded
            }

            validcount[other] = valid;
            soundtraversed[other] = blocks + 1;
            soundtargets[other] = target;

            stacksec[depth] = other;
            stackblocks[depth] = blocks;
            stacki[depth] = 0;
            depth++;
        }
    }

    //
    // P_NoiseAlert
    // If a monster yells at a player,
    // it will alert other monsters to the player.
    //
    function P_NoiseAlert(target as Number, emmiter as Number) as Void {
        soundtarget = target;
        RMain.validcount++;
        P_RecursiveSound(PSetup.subsectors_sector[PMobj.mobjs_subsector[emmiter]], 0);
    }

    //
    // P_CheckMeleeRange
    //
    function P_CheckMeleeRange(actor as Number) as Boolean {
        var pl = PMobj.mobjs_target[actor];
        if (pl == -1) {
            return false;
        }

        var dist = PMapUtl.P_AproxDistance(PMobj.mobjs_x[pl] - PMobj.mobjs_x[actor],
                                           PMobj.mobjs_y[pl] - PMobj.mobjs_y[actor]);

        if (dist >= PLocal.MELEERANGE - 20 * MFixed.FRACUNIT + PMobj.info(pl, Info.MI_RADIUS)) {
            return false;
        }

        if (!P_CheckSight(actor, pl)) {
            return false;
        }

        return true;
    }

    //
    // P_CheckMissileRange
    //
    function P_CheckMissileRange(actor as Number) as Boolean {
        var target = PMobj.mobjs_target[actor];

        if (!P_CheckSight(actor, target)) {
            return false;
        }

        if ((PMobj.mobjs_flags[actor] & PMobj.MF_JUSTHIT) != 0) {
            // the target just hit the enemy,
            // so fight back!
            PMobj.mobjs_flags[actor] &= ~PMobj.MF_JUSTHIT;
            return true;
        }

        if (PMobj.mobjs_reactiontime[actor] != 0) {
            return false;   // do not attack yet
        }

        // OPTIMIZE: get this from a global checksight
        var dist = PMapUtl.P_AproxDistance(PMobj.mobjs_x[actor] - PMobj.mobjs_x[target],
                                           PMobj.mobjs_y[actor] - PMobj.mobjs_y[target]) - 64 * MFixed.FRACUNIT;

        if (PMobj.info(actor, Info.MI_MELEESTATE) == 0) {
            dist -= 128 * MFixed.FRACUNIT;  // no melee attack, so fire more
        }

        dist >>= 16;

        var type = PMobj.mobjs_type[actor];
        if (type == Info.MT_VILE) {
            if (dist > 14 * 64) {
                return false;   // too far away
            }
        }

        if (type == Info.MT_UNDEAD) {
            if (dist < 196) {
                return false;   // close for fist attack
            }
            dist >>= 1;
        }

        if (type == Info.MT_CYBORG
            || type == Info.MT_SPIDER
            || type == Info.MT_SKULL) {
            dist >>= 1;
        }

        if (dist > 200) {
            dist = 200;
        }

        if (type == Info.MT_CYBORG && dist > 160) {
            dist = 160;
        }

        if (MRandom.P_Random() < dist) {
            return false;
        }

        return true;
    }

    //
    // P_Move
    // Move in the current direction,
    // returns false if the move is blocked.
    //
    const xspeed = [MFixed.FRACUNIT, 47000, 0, -47000, -MFixed.FRACUNIT, -47000, 0, 47000] as Array<Number>;
    const yspeed = [0, 47000, MFixed.FRACUNIT, 47000, 0, -47000, -MFixed.FRACUNIT, -47000] as Array<Number>;

    function P_Move(actor as Number) as Boolean {
        var movedir = PMobj.mobjs_movedir[actor];

        if (movedir == DI_NODIR) {
            return false;
        }

        // (unsigned)actor->movedir >= 8
        if (movedir < 0 || movedir >= 8) {
            ISystem.I_Error("Weird actor->movedir!");
        }

        var speed = Info.mobjinfo[PMobj.mobjs_type[actor] * Info.MI_SIZE + Info.MI_SPEED];
        var tryx = PMobj.mobjs_x[actor] + speed * xspeed[movedir];
        var tryy = PMobj.mobjs_y[actor] + speed * yspeed[movedir];

        // warning: 'catch', 'throw', and 'try'
        // are all C++ reserved words
        // (P_TryMove above written out here: one call and one frame less
        // per monster step, ahead of P_CheckPosition's deep call chain)
        var try_ok = testTryMove != null
            ? (testTryMove as Method).invoke(actor, tryx, tryy) as Boolean
            : PMap.P_TryMove(actor, tryx, tryy);

        if (!try_ok) {
            // open any specials
            if ((PMobj.mobjs_flags[actor] & PMobj.MF_FLOAT) != 0 && PMap.floatok) {
                // must adjust height
                if (PMobj.mobjs_z[actor] < PMap.tmfloorz) {
                    PMobj.mobjs_z[actor] += PLocal.FLOATSPEED;
                } else {
                    PMobj.mobjs_z[actor] -= PLocal.FLOATSPEED;
                }

                PMobj.mobjs_flags[actor] |= PMobj.MF_INFLOAT;
                return true;
            }

            if (PMap.numspechit == 0) {
                return false;
            }

            PMobj.mobjs_movedir[actor] = DI_NODIR;
            var good = false;
            // while (numspechit--), which leaves it at -1 like the C
            while (true) {
                var n = PMap.numspechit;
                PMap.numspechit = n - 1;
                if (n == 0) {
                    break;
                }
                var ld = PMap.spechit[n - 1];
                // if the special is not a door
                // that can be opened,
                // return false
                if (PSwitch.P_UseSpecialLine(actor, ld, 0)) {
                    good = true;
                }
            }
            return good;
        } else {
            PMobj.mobjs_flags[actor] &= ~PMobj.MF_INFLOAT;
        }

        if ((PMobj.mobjs_flags[actor] & PMobj.MF_FLOAT) == 0) {
            PMobj.mobjs_z[actor] = PMobj.mobjs_floorz[actor];
        }
        return true;
    }

    //
    // TryWalk
    // Attempts to move actor on
    // in its current (ob->moveangle) direction.
    // If blocked by either a wall or an actor
    // returns FALSE
    // If move is either clear or blocked only by a door,
    // returns TRUE and sets...
    // If a door is in the way,
    // an OpenDoor call is made to start it opening.
    //
    function P_TryWalk(actor as Number) as Boolean {
        if (!P_Move(actor)) {
            return false;
        }

        PMobj.mobjs_movecount[actor] = MRandom.P_Random() & 15;
        return true;
    }

    function P_NewChaseDir(actor as Number) as Void {
        var target = PMobj.mobjs_target[actor];
        var d = [0, 0, 0] as Array<Number>;

        if (target == -1) {
            ISystem.I_Error("P_NewChaseDir: called with no target");
        }

        var olddir = PMobj.mobjs_movedir[actor];
        var turnaround = opposite[olddir];

        var deltax = PMobj.mobjs_x[target] - PMobj.mobjs_x[actor];
        var deltay = PMobj.mobjs_y[target] - PMobj.mobjs_y[actor];

        if (deltax > 10 * MFixed.FRACUNIT) {
            d[1] = DI_EAST;
        } else if (deltax < -10 * MFixed.FRACUNIT) {
            d[1] = DI_WEST;
        } else {
            d[1] = DI_NODIR;
        }

        if (deltay < -10 * MFixed.FRACUNIT) {
            d[2] = DI_SOUTH;
        } else if (deltay > 10 * MFixed.FRACUNIT) {
            d[2] = DI_NORTH;
        } else {
            d[2] = DI_NODIR;
        }

        // try direct route
        if (d[1] != DI_NODIR
            && d[2] != DI_NODIR) {
            PMobj.mobjs_movedir[actor] = diags[((deltay < 0 ? 1 : 0) << 1) + (deltax > 0 ? 1 : 0)];
            if (PMobj.mobjs_movedir[actor] != turnaround && P_TryWalk(actor)) {
                return;
            }
        }

        // try other directions
        if (MRandom.P_Random() > 200
            || MFixed.abs(deltay) > MFixed.abs(deltax)) {
            var tdir = d[1];
            d[1] = d[2];
            d[2] = tdir;
        }

        if (d[1] == turnaround) {
            d[1] = DI_NODIR;
        }
        if (d[2] == turnaround) {
            d[2] = DI_NODIR;
        }

        if (d[1] != DI_NODIR) {
            PMobj.mobjs_movedir[actor] = d[1];
            if (P_TryWalk(actor)) {
                // either moved forward or attacked
                return;
            }
        }

        if (d[2] != DI_NODIR) {
            PMobj.mobjs_movedir[actor] = d[2];

            if (P_TryWalk(actor)) {
                return;
            }
        }

        // there is no direct path to the player,
        // so pick another direction.
        if (olddir != DI_NODIR) {
            PMobj.mobjs_movedir[actor] = olddir;

            if (P_TryWalk(actor)) {
                return;
            }
        }

        // randomly determine direction of search
        if ((MRandom.P_Random() & 1) != 0) {
            for (var tdir = DI_EAST; tdir <= DI_SOUTHEAST; tdir++) {
                if (tdir != turnaround) {
                    PMobj.mobjs_movedir[actor] = tdir;

                    if (P_TryWalk(actor)) {
                        return;
                    }
                }
            }
        } else {
            for (var tdir = DI_SOUTHEAST; tdir != (DI_EAST - 1); tdir--) {
                if (tdir != turnaround) {
                    PMobj.mobjs_movedir[actor] = tdir;

                    if (P_TryWalk(actor)) {
                        return;
                    }
                }
            }
        }

        if (turnaround != DI_NODIR) {
            PMobj.mobjs_movedir[actor] = turnaround;
            if (P_TryWalk(actor)) {
                return;
            }
        }

        PMobj.mobjs_movedir[actor] = DI_NODIR;  // can not move
    }

    //
    // P_LookForPlayers
    // If allaround is false, only look 180 degrees in front.
    // Returns true if a player is targeted.
    //
    // Each "continue" of the C for (;;) goes to the lastlook increment;
    // here a skipped player falls through to it at the bottom.
    //
    function P_LookForPlayers(actor as Number, allaround as Boolean) as Boolean {
        var c = 0;
        var stop = (PMobj.mobjs_lastlook[actor] - 1) & 3;

        while (true) {
            var lastlook = PMobj.mobjs_lastlook[actor];

            if (DPlayer.playeringame[lastlook]) {
                // c++ == 2
                var done = c == 2;
                c++;
                if (done
                    || lastlook == stop) {
                    // done looking
                    return false;
                }

                var mo = DPlayer.players_mo[lastlook];
                var seen = true;

                if (DPlayer.players_health[lastlook] <= 0) {
                    seen = false;       // dead
                } else if (!P_CheckSight(actor, mo)) {
                    seen = false;       // out of sight
                } else if (!allaround) {
                    var an = RMain.R_PointToAngle2(PMobj.mobjs_x[actor],
                                                   PMobj.mobjs_y[actor],
                                                   PMobj.mobjs_x[mo],
                                                   PMobj.mobjs_y[mo])
                        - PMobj.mobjs_angle[actor];

                    if (DoomType.UGT(an, Tables.ANG90) && DoomType.ULT(an, Tables.ANG270)) {
                        var dist = PMapUtl.P_AproxDistance(PMobj.mobjs_x[mo] - PMobj.mobjs_x[actor],
                                                           PMobj.mobjs_y[mo] - PMobj.mobjs_y[actor]);
                        // if real close, react anyway
                        if (dist > PLocal.MELEERANGE) {
                            seen = false;   // behind back
                        }
                    }
                }

                if (seen) {
                    PMobj.mobjs_target[actor] = mo;
                    return true;
                }
            }

            PMobj.mobjs_lastlook[actor] = (lastlook + 1) & 3;
        }

        return false;
    }

    // line_t junk: the EV_ functions take a line number, so the junk
    // line is the spare lines_tag slot PSetup keeps past the map's lines.
    function junkline(tag as Number) as Number {
        var junk = PSetup.numlines;
        PSetup.lines_tag[junk] = tag;
        return junk;
    }

    //
    // A_KeenDie
    // DOOM II special, map 32.
    // Uses special tag 666.
    //
    // Walks every thinker in the level.
    //
    function A_KeenDie(mo as Number) as Void {
        A_Fall(mo);

        // scan the remaining thinkers
        // to see if all Keens are dead
        var next = PTick.thinkers_next;
        var funcs = PTick.thinkers_function;
        var types = PMobj.mobjs_type;
        var health = PMobj.mobjs_health;
        var type = types[mo];
        for (var th = next[0]; th != 0; th = next[th]) {
            if (funcs[th] != PTick.TF_MOBJ) {
                continue;
            }

            if (th != mo
                && types[th] == type
                && health[th] > 0) {
                // other Keen not dead
                return;
            }
        }

        PDoors.EV_DoDoor(junkline(666), PSpec.open);
    }

    //
    // ACTION ROUTINES
    //

    //
    // A_Look
    // Stay in state until a player is sighted.
    //
    function A_Look(actor as Number) as Void {
        PMobj.mobjs_threshold[actor] = 0;   // any shot will wake up
        var targ = PSetup.sectors_soundtarget[PSetup.subsectors_sector[PMobj.mobjs_subsector[actor]]];

        // the gotos to seeyou become a flag
        var seeyou = false;
        if (targ != -1
            && (PMobj.mobjs_flags[targ] & PMobj.MF_SHOOTABLE) != 0) {
            PMobj.mobjs_target[actor] = targ;

            if ((PMobj.mobjs_flags[actor] & PMobj.MF_AMBUSH) != 0) {
                if (P_CheckSight(actor, targ)) {
                    seeyou = true;
                }
            } else {
                seeyou = true;
            }
        }

        if (!seeyou) {
            if (!P_LookForPlayers(actor, false)) {
                return;
            }
        }

        // go into chase state
        // seeyou:
        var seesound = PMobj.info(actor, Info.MI_SEESOUND);
        if (seesound != 0) {
            var sound = seesound;

            switch (seesound) {
                case SSound.sfx_posit1:
                case SSound.sfx_posit2:
                case SSound.sfx_posit3:
                    sound = SSound.sfx_posit1 + MRandom.P_Random() % 3;
                    break;

                case SSound.sfx_bgsit1:
                case SSound.sfx_bgsit2:
                    sound = SSound.sfx_bgsit1 + MRandom.P_Random() % 2;
                    break;

                default:
                    sound = seesound;
                    break;
            }

            var type = PMobj.mobjs_type[actor];
            if (type == Info.MT_SPIDER
                || type == Info.MT_CYBORG) {
                // full volume
                SSound.S_StartSound(-1, sound);
            } else {
                SSound.S_StartSound(actor, sound);
            }
        }

        PMobj.P_SetMobjState(actor, PMobj.info(actor, Info.MI_SEESTATE));
    }

    //
    // A_Chase
    // Actor has a melee attack,
    // so it tries to close as fast as possible
    //
    function A_Chase(actor as Number) as Void {
        // (flags and the mobjinfo row in locals instead of the PMobj.info
        // calls: calls and module variable reads are slow on the watch.
        // Only these, since this frame is under P_Move and P_CheckSight.)
        var mflags = PMobj.mobjs_flags;
        var mi = Info.mobjinfo;
        var info = PMobj.mobjs_type[actor] * Info.MI_SIZE;

        if (PMobj.mobjs_reactiontime[actor] != 0) {
            PMobj.mobjs_reactiontime[actor]--;
        }

        // modify target threshold
        if (PMobj.mobjs_threshold[actor] != 0) {
            var t = PMobj.mobjs_target[actor];
            if (t == -1
                || PMobj.mobjs_health[t] <= 0) {
                PMobj.mobjs_threshold[actor] = 0;
            } else {
                PMobj.mobjs_threshold[actor]--;
            }
        }

        // turn towards movement direction if not there yet
        var movedir = PMobj.mobjs_movedir[actor];
        if (movedir < 8) {
            var angle = PMobj.mobjs_angle[actor] & (7 << 29);
            var delta = angle - (movedir << 29);

            if (delta > 0) {
                angle -= Tables.ANG90 / 2;
            } else if (delta < 0) {
                angle += Tables.ANG90 / 2;
            }
            PMobj.mobjs_angle[actor] = angle;
        }

        var target = PMobj.mobjs_target[actor];
        if (target == -1
            || (mflags[target] & PMobj.MF_SHOOTABLE) == 0) {
            // look for a new target
            if (P_LookForPlayers(actor, true)) {
                return;     // got a new target
            }

            PMobj.P_SetMobjState(actor, mi[info + Info.MI_SPAWNSTATE]);
            return;
        }

        // do not attack twice in a row
        if ((mflags[actor] & PMobj.MF_JUSTATTACKED) != 0) {
            mflags[actor] &= ~PMobj.MF_JUSTATTACKED;
            if (DoomStat.gameskill != DoomDef.sk_nightmare && !DoomStat.fastparm) {
                P_NewChaseDir(actor);
            }
            return;
        }

        // check for melee attack
        var meleestate = mi[info + Info.MI_MELEESTATE];
        if (meleestate != 0
            && P_CheckMeleeRange(actor)) {
            var attacksound = mi[info + Info.MI_ATTACKSOUND];
            if (attacksound != 0) {
                SSound.S_StartSound(actor, attacksound);
            }

            PMobj.P_SetMobjState(actor, meleestate);
            return;
        }

        // check for missile attack
        // (both gotos to nomissile become this if)
        var missilestate = mi[info + Info.MI_MISSILESTATE];
        if (missilestate != 0) {
            if (!(DoomStat.gameskill < DoomDef.sk_nightmare
                  && !DoomStat.fastparm && PMobj.mobjs_movecount[actor] != 0)
                && P_CheckMissileRange(actor)) {
                PMobj.P_SetMobjState(actor, missilestate);
                mflags[actor] |= PMobj.MF_JUSTATTACKED;
                return;
            }
        }

        // ?
        // nomissile:
        // possibly choose another target
        if (DoomStat.netgame
            && PMobj.mobjs_threshold[actor] == 0
            && !P_CheckSight(actor, PMobj.mobjs_target[actor])) {
            if (P_LookForPlayers(actor, true)) {
                return;     // got a new target
            }
        }

        // chase towards player
        PMobj.mobjs_movecount[actor]--;
        if (PMobj.mobjs_movecount[actor] < 0
            || !P_Move(actor)) {
            P_NewChaseDir(actor);
        }

        // make active sound
        var activesound = mi[info + Info.MI_ACTIVESOUND];
        if (activesound != 0
            && MRandom.P_Random() < 3) {
            SSound.S_StartSound(actor, activesound);
        }
    }

    //
    // A_FaceTarget
    //
    function A_FaceTarget(actor as Number) as Void {
        var target = PMobj.mobjs_target[actor];
        if (target == -1) {
            return;
        }

        PMobj.mobjs_flags[actor] &= ~PMobj.MF_AMBUSH;

        PMobj.mobjs_angle[actor] = RMain.R_PointToAngle2(PMobj.mobjs_x[actor],
                                                         PMobj.mobjs_y[actor],
                                                         PMobj.mobjs_x[target],
                                                         PMobj.mobjs_y[target]);

        if ((PMobj.mobjs_flags[target] & PMobj.MF_SHADOW) != 0) {
            PMobj.mobjs_angle[actor] += (MRandom.P_Random() - MRandom.P_Random()) << 21;
        }
    }

    //
    // A_PosAttack
    //
    function A_PosAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);
        var angle = PMobj.mobjs_angle[actor];
        var slope = PMap.P_AimLineAttack(actor, angle, PLocal.MISSILERANGE);

        SSound.S_StartSound(actor, SSound.sfx_pistol);
        angle += (MRandom.P_Random() - MRandom.P_Random()) << 20;
        var damage = ((MRandom.P_Random() % 5) + 1) * 3;
        PMap.P_LineAttack(actor, angle, PLocal.MISSILERANGE, slope, damage);
    }

    function A_SPosAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        SSound.S_StartSound(actor, SSound.sfx_shotgn);
        A_FaceTarget(actor);
        var bangle = PMobj.mobjs_angle[actor];
        var slope = PMap.P_AimLineAttack(actor, bangle, PLocal.MISSILERANGE);

        for (var i = 0; i < 3; i++) {
            var angle = bangle + ((MRandom.P_Random() - MRandom.P_Random()) << 20);
            var damage = ((MRandom.P_Random() % 5) + 1) * 3;
            PMap.P_LineAttack(actor, angle, PLocal.MISSILERANGE, slope, damage);
        }
    }

    function A_CPosAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        SSound.S_StartSound(actor, SSound.sfx_shotgn);
        A_FaceTarget(actor);
        var bangle = PMobj.mobjs_angle[actor];
        var slope = PMap.P_AimLineAttack(actor, bangle, PLocal.MISSILERANGE);

        var angle = bangle + ((MRandom.P_Random() - MRandom.P_Random()) << 20);
        var damage = ((MRandom.P_Random() % 5) + 1) * 3;
        PMap.P_LineAttack(actor, angle, PLocal.MISSILERANGE, slope, damage);
    }

    function A_CPosRefire(actor as Number) as Void {
        // keep firing unless target got out of sight
        A_FaceTarget(actor);

        if (MRandom.P_Random() < 40) {
            return;
        }

        var target = PMobj.mobjs_target[actor];
        if (target == -1
            || PMobj.mobjs_health[target] <= 0
            || !P_CheckSight(actor, target)) {
            PMobj.P_SetMobjState(actor, PMobj.info(actor, Info.MI_SEESTATE));
        }
    }

    function A_SpidRefire(actor as Number) as Void {
        // keep firing unless target got out of sight
        A_FaceTarget(actor);

        if (MRandom.P_Random() < 10) {
            return;
        }

        var target = PMobj.mobjs_target[actor];
        if (target == -1
            || PMobj.mobjs_health[target] <= 0
            || !P_CheckSight(actor, target)) {
            PMobj.P_SetMobjState(actor, PMobj.info(actor, Info.MI_SEESTATE));
        }
    }

    function A_BspiAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);

        // launch a missile
        PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_ARACHPLAZ);
    }

    //
    // A_TroopAttack
    //
    function A_TroopAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);
        if (P_CheckMeleeRange(actor)) {
            SSound.S_StartSound(actor, SSound.sfx_claw);
            var damage = (MRandom.P_Random() % 8 + 1) * 3;
            PInter.P_DamageMobj(PMobj.mobjs_target[actor], actor, actor, damage);
            return;
        }

        // launch a missile
        PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_TROOPSHOT);
    }

    function A_SargAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);
        if (P_CheckMeleeRange(actor)) {
            var damage = ((MRandom.P_Random() % 10) + 1) * 4;
            PInter.P_DamageMobj(PMobj.mobjs_target[actor], actor, actor, damage);
        }
    }

    function A_HeadAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);
        if (P_CheckMeleeRange(actor)) {
            var damage = (MRandom.P_Random() % 6 + 1) * 10;
            PInter.P_DamageMobj(PMobj.mobjs_target[actor], actor, actor, damage);
            return;
        }

        // launch a missile
        PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_HEADSHOT);
    }

    function A_CyberAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);
        PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_ROCKET);
    }

    function A_BruisAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        if (P_CheckMeleeRange(actor)) {
            SSound.S_StartSound(actor, SSound.sfx_claw);
            var damage = (MRandom.P_Random() % 8 + 1) * 10;
            PInter.P_DamageMobj(PMobj.mobjs_target[actor], actor, actor, damage);
            return;
        }

        // launch a missile
        PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_BRUISERSHOT);
    }

    //
    // A_SkelMissile
    //
    function A_SkelMissile(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);
        PMobj.mobjs_z[actor] += 16 * MFixed.FRACUNIT;  // so missile spawns higher
        var mo = PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_TRACER);
        PMobj.mobjs_z[actor] -= 16 * MFixed.FRACUNIT;  // back to normal

        PMobj.mobjs_x[mo] += PMobj.mobjs_momx[mo];
        PMobj.mobjs_y[mo] += PMobj.mobjs_momy[mo];
        PMobj.mobjs_tracer[mo] = PMobj.mobjs_target[actor];
    }

    const TRACEANGLE = 0xc000000;

    function A_Tracer(actor as Number) as Void {
        if ((DoomStat.gametic & 3) != 0) {
            return;
        }

        var x = PMobj.mobjs_x[actor];
        var y = PMobj.mobjs_y[actor];
        var z = PMobj.mobjs_z[actor];

        // spawn a puff of smoke behind the rocket
        PMobj.P_SpawnPuff(x, y, z);

        var th = PMobj.P_SpawnMobj(x - PMobj.mobjs_momx[actor],
                                   y - PMobj.mobjs_momy[actor],
                                   z, Info.MT_SMOKE);

        PMobj.mobjs_momz[th] = MFixed.FRACUNIT;
        PMobj.mobjs_tics[th] -= MRandom.P_Random() & 3;
        if (PMobj.mobjs_tics[th] < 1) {
            PMobj.mobjs_tics[th] = 1;
        }

        // adjust direction
        var dest = PMobj.mobjs_tracer[actor];

        if (dest == -1 || PMobj.mobjs_health[dest] <= 0) {
            return;
        }

        // change angle
        var exact = RMain.R_PointToAngle2(x, y, PMobj.mobjs_x[dest], PMobj.mobjs_y[dest]);

        var angle = PMobj.mobjs_angle[actor];
        if (exact != angle) {
            if (DoomType.UGT(exact - angle, 0x80000000)) {
                angle -= TRACEANGLE;
                if (DoomType.ULT(exact - angle, 0x80000000)) {
                    angle = exact;
                }
            } else {
                angle += TRACEANGLE;
                if (DoomType.UGT(exact - angle, 0x80000000)) {
                    angle = exact;
                }
            }
            PMobj.mobjs_angle[actor] = angle;
        }

        var speed = PMobj.info(actor, Info.MI_SPEED);
        exact = (angle >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        PMobj.mobjs_momx[actor] = MFixed.FixedMul(speed, Tables.finesine[Tables.FINECOSINE + exact]);
        PMobj.mobjs_momy[actor] = MFixed.FixedMul(speed, Tables.finesine[exact]);

        // change slope
        var dist = PMapUtl.P_AproxDistance(PMobj.mobjs_x[dest] - x,
                                           PMobj.mobjs_y[dest] - y);

        dist = dist / speed;

        if (dist < 1) {
            dist = 1;
        }
        var slope = (PMobj.mobjs_z[dest] + 40 * MFixed.FRACUNIT - z) / dist;

        if (slope < PMobj.mobjs_momz[actor]) {
            PMobj.mobjs_momz[actor] -= MFixed.FRACUNIT / 8;
        } else {
            PMobj.mobjs_momz[actor] += MFixed.FRACUNIT / 8;
        }
    }

    function A_SkelWhoosh(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }
        A_FaceTarget(actor);
        SSound.S_StartSound(actor, SSound.sfx_skeswg);
    }

    function A_SkelFist(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);

        if (P_CheckMeleeRange(actor)) {
            var damage = ((MRandom.P_Random() % 10) + 1) * 6;
            SSound.S_StartSound(actor, SSound.sfx_skepch);
            PInter.P_DamageMobj(PMobj.mobjs_target[actor], actor, actor, damage);
        }
    }

    //
    // PIT_VileCheck
    // Detect a corpse that could be raised.
    //
    var corpsehit as Number = -1;
    var vileobj as Number = -1;
    var viletryx as Number = 0;
    var viletryy as Number = 0;

    function PIT_VileCheck(thing as Number) as Boolean {
        if ((PMobj.mobjs_flags[thing] & PMobj.MF_CORPSE) == 0) {
            return true;    // not a monster
        }

        if (PMobj.mobjs_tics[thing] != -1) {
            return true;    // not lying still yet
        }

        if (PMobj.info(thing, Info.MI_RAISESTATE) == Info.S_NULL) {
            return true;    // monster doesn't have a raise state
        }

        var maxdist = PMobj.info(thing, Info.MI_RADIUS)
            + Info.mobjinfo[Info.MT_VILE * Info.MI_SIZE + Info.MI_RADIUS];

        if (MFixed.abs(PMobj.mobjs_x[thing] - viletryx) > maxdist
            || MFixed.abs(PMobj.mobjs_y[thing] - viletryy) > maxdist) {
            return true;    // not actually touching
        }

        corpsehit = thing;
        PMobj.mobjs_momx[thing] = 0;
        PMobj.mobjs_momy[thing] = 0;
        PMobj.mobjs_height[thing] <<= 2;
        var check = PMap.P_CheckPosition(thing, PMobj.mobjs_x[thing], PMobj.mobjs_y[thing]);
        PMobj.mobjs_height[thing] >>= 2;

        if (!check) {
            return true;    // doesn't fit here
        }

        return false;       // got one, so stop checking
    }

    //
    // A_VileChase
    // Check for ressurecting a body
    //
    function A_VileChase(actor as Number) as Void {
        var movedir = PMobj.mobjs_movedir[actor];
        if (movedir != DI_NODIR) {
            // check for corpses to raise
            var speed = PMobj.info(actor, Info.MI_SPEED);
            viletryx = PMobj.mobjs_x[actor] + speed * xspeed[movedir];
            viletryy = PMobj.mobjs_y[actor] + speed * yspeed[movedir];

            var xl = (viletryx - PSetup.bmaporgx - PLocal.MAXRADIUS * 2) >> PLocal.MAPBLOCKSHIFT;
            var xh = (viletryx - PSetup.bmaporgx + PLocal.MAXRADIUS * 2) >> PLocal.MAPBLOCKSHIFT;
            var yl = (viletryy - PSetup.bmaporgy - PLocal.MAXRADIUS * 2) >> PLocal.MAPBLOCKSHIFT;
            var yh = (viletryy - PSetup.bmaporgy + PLocal.MAXRADIUS * 2) >> PLocal.MAPBLOCKSHIFT;

            vileobj = actor;
            var check = new Lang.Method(PEnemy, :PIT_VileCheck);
            for (var bx = xl; bx <= xh; bx++) {
                for (var by = yl; by <= yh; by++) {
                    // Call PIT_VileCheck to check
                    // whether object is a corpse
                    // that canbe raised.
                    if (!PMapUtl.P_BlockThingsIterator(bx, by, check)) {
                        // got one!
                        var temp = PMobj.mobjs_target[actor];
                        PMobj.mobjs_target[actor] = corpsehit;
                        A_FaceTarget(actor);
                        PMobj.mobjs_target[actor] = temp;

                        PMobj.P_SetMobjState(actor, Info.S_VILE_HEAL1);
                        SSound.S_StartSound(corpsehit, SSound.sfx_slop);

                        PMobj.P_SetMobjState(corpsehit, PMobj.info(corpsehit, Info.MI_RAISESTATE));
                        PMobj.mobjs_height[corpsehit] <<= 2;
                        PMobj.mobjs_flags[corpsehit] = PMobj.info(corpsehit, Info.MI_FLAGS);
                        PMobj.mobjs_health[corpsehit] = PMobj.info(corpsehit, Info.MI_SPAWNHEALTH);
                        PMobj.mobjs_target[corpsehit] = -1;

                        return;
                    }
                }
            }
        }

        // Return to normal attack.
        A_Chase(actor);
    }

    //
    // A_VileStart
    //
    function A_VileStart(actor as Number) as Void {
        SSound.S_StartSound(actor, SSound.sfx_vilatk);
    }

    //
    // A_Fire
    // Keep fire in front of player unless out of sight
    //
    function A_StartFire(actor as Number) as Void {
        SSound.S_StartSound(actor, SSound.sfx_flamst);
        A_Fire(actor);
    }

    function A_FireCrackle(actor as Number) as Void {
        SSound.S_StartSound(actor, SSound.sfx_flame);
        A_Fire(actor);
    }

    function A_Fire(actor as Number) as Void {
        var dest = PMobj.mobjs_tracer[actor];
        if (dest == -1) {
            return;
        }

        // don't move it if the vile lost sight
        if (!P_CheckSight(PMobj.mobjs_target[actor], dest)) {
            return;
        }

        var an = (PMobj.mobjs_angle[dest] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;

        PMapUtl.P_UnsetThingPosition(actor);
        PMobj.mobjs_x[actor] = PMobj.mobjs_x[dest] + MFixed.FixedMul(24 * MFixed.FRACUNIT, Tables.finesine[Tables.FINECOSINE + an]);
        PMobj.mobjs_y[actor] = PMobj.mobjs_y[dest] + MFixed.FixedMul(24 * MFixed.FRACUNIT, Tables.finesine[an]);
        PMobj.mobjs_z[actor] = PMobj.mobjs_z[dest];
        PMapUtl.P_SetThingPosition(actor);
    }

    //
    // A_VileTarget
    // Spawn the hellfire
    //
    function A_VileTarget(actor as Number) as Void {
        var target = PMobj.mobjs_target[actor];
        if (target == -1) {
            return;
        }

        A_FaceTarget(actor);

        // (x twice is in the original, A_Fire moves it right away)
        var fog = PMobj.P_SpawnMobj(PMobj.mobjs_x[target],
                                    PMobj.mobjs_x[target],
                                    PMobj.mobjs_z[target], Info.MT_FIRE);

        PMobj.mobjs_tracer[actor] = fog;
        PMobj.mobjs_target[fog] = actor;
        PMobj.mobjs_tracer[fog] = target;
        A_Fire(fog);
    }

    //
    // A_VileAttack
    //
    function A_VileAttack(actor as Number) as Void {
        var target = PMobj.mobjs_target[actor];
        if (target == -1) {
            return;
        }

        A_FaceTarget(actor);

        if (!P_CheckSight(actor, target)) {
            return;
        }

        SSound.S_StartSound(actor, SSound.sfx_barexp);
        PInter.P_DamageMobj(target, actor, actor, 20);
        PMobj.mobjs_momz[target] = 1000 * MFixed.FRACUNIT / PMobj.info(target, Info.MI_MASS);

        var an = (PMobj.mobjs_angle[actor] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;

        var fire = PMobj.mobjs_tracer[actor];

        if (fire == -1) {
            return;
        }

        // move the fire between the vile and the player
        PMobj.mobjs_x[fire] = PMobj.mobjs_x[target] - MFixed.FixedMul(24 * MFixed.FRACUNIT, Tables.finesine[Tables.FINECOSINE + an]);
        PMobj.mobjs_y[fire] = PMobj.mobjs_y[target] - MFixed.FixedMul(24 * MFixed.FRACUNIT, Tables.finesine[an]);
        PMap.P_RadiusAttack(fire, actor, 70);
    }

    //
    // Mancubus attack,
    // firing three missiles (bruisers)
    // in three different directions?
    // Doesn't look like it.
    //
    const FATSPREAD = Tables.ANG90 / 8;

    function A_FatRaise(actor as Number) as Void {
        A_FaceTarget(actor);
        SSound.S_StartSound(actor, SSound.sfx_manatk);
    }

    function A_FatAttack1(actor as Number) as Void {
        A_FaceTarget(actor);
        // Change direction  to ...
        PMobj.mobjs_angle[actor] += FATSPREAD;
        PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_FATSHOT);

        var mo = PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_FATSHOT);
        PMobj.mobjs_angle[mo] += FATSPREAD;
        var an = (PMobj.mobjs_angle[mo] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        PMobj.mobjs_momx[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[Tables.FINECOSINE + an]);
        PMobj.mobjs_momy[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[an]);
    }

    function A_FatAttack2(actor as Number) as Void {
        A_FaceTarget(actor);
        // Now here choose opposite deviation.
        PMobj.mobjs_angle[actor] -= FATSPREAD;
        PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_FATSHOT);

        var mo = PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_FATSHOT);
        PMobj.mobjs_angle[mo] -= FATSPREAD * 2;
        var an = (PMobj.mobjs_angle[mo] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        PMobj.mobjs_momx[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[Tables.FINECOSINE + an]);
        PMobj.mobjs_momy[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[an]);
    }

    function A_FatAttack3(actor as Number) as Void {
        A_FaceTarget(actor);

        var mo = PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_FATSHOT);
        PMobj.mobjs_angle[mo] -= FATSPREAD / 2;
        var an = (PMobj.mobjs_angle[mo] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        PMobj.mobjs_momx[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[Tables.FINECOSINE + an]);
        PMobj.mobjs_momy[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[an]);

        mo = PMobj.P_SpawnMissile(actor, PMobj.mobjs_target[actor], Info.MT_FATSHOT);
        PMobj.mobjs_angle[mo] += FATSPREAD / 2;
        an = (PMobj.mobjs_angle[mo] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        PMobj.mobjs_momx[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[Tables.FINECOSINE + an]);
        PMobj.mobjs_momy[mo] = MFixed.FixedMul(PMobj.info(mo, Info.MI_SPEED), Tables.finesine[an]);
    }

    //
    // SkullAttack
    // Fly at the player like a missile.
    //
    const SKULLSPEED = 20 * MFixed.FRACUNIT;

    function A_SkullAttack(actor as Number) as Void {
        var dest = PMobj.mobjs_target[actor];
        if (dest == -1) {
            return;
        }

        PMobj.mobjs_flags[actor] |= PMobj.MF_SKULLFLY;

        SSound.S_StartSound(actor, PMobj.info(actor, Info.MI_ATTACKSOUND));
        A_FaceTarget(actor);
        var an = (PMobj.mobjs_angle[actor] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
        PMobj.mobjs_momx[actor] = MFixed.FixedMul(SKULLSPEED, Tables.finesine[Tables.FINECOSINE + an]);
        PMobj.mobjs_momy[actor] = MFixed.FixedMul(SKULLSPEED, Tables.finesine[an]);
        var dist = PMapUtl.P_AproxDistance(PMobj.mobjs_x[dest] - PMobj.mobjs_x[actor],
                                           PMobj.mobjs_y[dest] - PMobj.mobjs_y[actor]);
        dist = dist / SKULLSPEED;

        if (dist < 1) {
            dist = 1;
        }
        PMobj.mobjs_momz[actor] = (PMobj.mobjs_z[dest] + (PMobj.mobjs_height[dest] >> 1) - PMobj.mobjs_z[actor]) / dist;
    }

    //
    // A_PainShootSkull
    // Spawn a lost soul and launch it at the target
    //
    // Counting the skulls walks every thinker in the level.
    //
    function A_PainShootSkull(actor as Number, angle as Number) as Void {
        // count total number of skull currently on the level
        var count = 0;

        var next = PTick.thinkers_next;
        var funcs = PTick.thinkers_function;
        var types = PMobj.mobjs_type;
        var currentthinker = next[0];
        while (currentthinker != 0) {
            if ((funcs[currentthinker] == PTick.TF_MOBJ)
                && types[currentthinker] == Info.MT_SKULL) {
                count++;
            }
            currentthinker = next[currentthinker];
        }

        // if there are allready 20 skulls on the level,
        // don't spit another one
        if (count > 20) {
            return;
        }

        // okay, there's playe for another one
        var an = (angle >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;

        var prestep =
            4 * MFixed.FRACUNIT
            + 3 * (PMobj.info(actor, Info.MI_RADIUS) + Info.mobjinfo[Info.MT_SKULL * Info.MI_SIZE + Info.MI_RADIUS]) / 2;

        var x = PMobj.mobjs_x[actor] + MFixed.FixedMul(prestep, Tables.finesine[Tables.FINECOSINE + an]);
        var y = PMobj.mobjs_y[actor] + MFixed.FixedMul(prestep, Tables.finesine[an]);
        var z = PMobj.mobjs_z[actor] + 8 * MFixed.FRACUNIT;

        var newmobj = PMobj.P_SpawnMobj(x, y, z, Info.MT_SKULL);

        // Check for movements.
        if (!P_TryMove(newmobj, PMobj.mobjs_x[newmobj], PMobj.mobjs_y[newmobj])) {
            // kill it immediately
            PInter.P_DamageMobj(newmobj, actor, actor, 10000);
            return;
        }

        PMobj.mobjs_target[newmobj] = PMobj.mobjs_target[actor];
        A_SkullAttack(newmobj);
    }

    //
    // A_PainAttack
    // Spawn a lost soul and launch it at the target
    //
    function A_PainAttack(actor as Number) as Void {
        if (PMobj.mobjs_target[actor] == -1) {
            return;
        }

        A_FaceTarget(actor);
        A_PainShootSkull(actor, PMobj.mobjs_angle[actor]);
    }

    function A_PainDie(actor as Number) as Void {
        A_Fall(actor);
        A_PainShootSkull(actor, PMobj.mobjs_angle[actor] + Tables.ANG90);
        A_PainShootSkull(actor, PMobj.mobjs_angle[actor] + Tables.ANG180);
        A_PainShootSkull(actor, PMobj.mobjs_angle[actor] + Tables.ANG270);
    }

    function A_Scream(actor as Number) as Void {
        var deathsound = PMobj.info(actor, Info.MI_DEATHSOUND);
        var sound = deathsound;

        switch (deathsound) {
            case 0:
                return;

            case SSound.sfx_podth1:
            case SSound.sfx_podth2:
            case SSound.sfx_podth3:
                sound = SSound.sfx_podth1 + MRandom.P_Random() % 3;
                break;

            case SSound.sfx_bgdth1:
            case SSound.sfx_bgdth2:
                sound = SSound.sfx_bgdth1 + MRandom.P_Random() % 2;
                break;

            default:
                sound = deathsound;
                break;
        }

        // Check for bosses.
        var type = PMobj.mobjs_type[actor];
        if (type == Info.MT_SPIDER
            || type == Info.MT_CYBORG) {
            // full volume
            SSound.S_StartSound(-1, sound);
        } else {
            SSound.S_StartSound(actor, sound);
        }
    }

    function A_XScream(actor as Number) as Void {
        SSound.S_StartSound(actor, SSound.sfx_slop);
    }

    function A_Pain(actor as Number) as Void {
        var painsound = PMobj.info(actor, Info.MI_PAINSOUND);
        if (painsound != 0) {
            SSound.S_StartSound(actor, painsound);
        }
    }

    function A_Fall(actor as Number) as Void {
        // actor is on ground, it can be walked over
        PMobj.mobjs_flags[actor] &= ~PMobj.MF_SOLID;

        // So change this if corpse objects
        // are meant to be obstacles.
    }

    //
    // A_Explode
    //
    function A_Explode(thingy as Number) as Void {
        PMap.P_RadiusAttack(thingy, PMobj.mobjs_target[thingy], 128);
    }

    //
    // A_BossDeath
    // Possibly trigger special effects
    // if on first boss level
    //
    // Walks every thinker in the level.
    //
    function A_BossDeath(mo as Number) as Void {
        var type = PMobj.mobjs_type[mo];
        var gamemap = DoomStat.gamemap;

        if (DoomStat.gamemode == DoomDef.commercial) {
            if (gamemap != 7) {
                return;
            }

            if ((type != Info.MT_FATSO)
                && (type != Info.MT_BABY)) {
                return;
            }
        } else {
            switch (DoomStat.gameepisode) {
                case 1:
                    if (gamemap != 8) {
                        return;
                    }

                    if (type != Info.MT_BRUISER) {
                        return;
                    }
                    break;

                case 2:
                    if (gamemap != 8) {
                        return;
                    }

                    if (type != Info.MT_CYBORG) {
                        return;
                    }
                    break;

                case 3:
                    if (gamemap != 8) {
                        return;
                    }

                    if (type != Info.MT_SPIDER) {
                        return;
                    }

                    break;

                case 4:
                    switch (gamemap) {
                        case 6:
                            if (type != Info.MT_CYBORG) {
                                return;
                            }
                            break;

                        case 8:
                            if (type != Info.MT_SPIDER) {
                                return;
                            }
                            break;

                        default:
                            return;
                    }
                    break;

                default:
                    if (gamemap != 8) {
                        return;
                    }
                    break;
            }
        }

        // make sure there is a player alive for victory
        var i;
        for (i = 0; i < DoomStat.MAXPLAYERS; i++) {
            if (DPlayer.playeringame[i] && DPlayer.players_health[i] > 0) {
                break;
            }
        }

        if (i == DoomStat.MAXPLAYERS) {
            return;     // no one left alive, so do not end game
        }

        // scan the remaining thinkers to see
        // if all bosses are dead
        var next = PTick.thinkers_next;
        var funcs = PTick.thinkers_function;
        var types = PMobj.mobjs_type;
        var health = PMobj.mobjs_health;
        for (var th = next[0]; th != 0; th = next[th]) {
            if (funcs[th] != PTick.TF_MOBJ) {
                continue;
            }

            if (th != mo
                && types[th] == type
                && health[th] > 0) {
                // other boss not dead
                return;
            }
        }

        // victory!
        if (DoomStat.gamemode == DoomDef.commercial) {
            if (gamemap == 7) {
                if (type == Info.MT_FATSO) {
                    PFloor.EV_DoFloor(junkline(666), PSpec.lowerFloorToLowest);
                    return;
                }

                if (type == Info.MT_BABY) {
                    PFloor.EV_DoFloor(junkline(667), PSpec.raiseToTexture);
                    return;
                }
            }
        } else {
            switch (DoomStat.gameepisode) {
                case 1:
                    PFloor.EV_DoFloor(junkline(666), PSpec.lowerFloorToLowest);
                    return;

                case 4:
                    switch (gamemap) {
                        case 6:
                            PDoors.EV_DoDoor(junkline(666), PSpec.blazeOpen);
                            return;

                        case 8:
                            PFloor.EV_DoFloor(junkline(666), PSpec.lowerFloorToLowest);
                            return;
                    }
                    break;
            }
        }

        GGame.G_ExitLevel();
    }

    function A_Hoof(mo as Number) as Void {
        SSound.S_StartSound(mo, SSound.sfx_hoof);
        A_Chase(mo);
    }

    function A_Metal(mo as Number) as Void {
        SSound.S_StartSound(mo, SSound.sfx_metal);
        A_Chase(mo);
    }

    function A_BabyMetal(mo as Number) as Void {
        SSound.S_StartSound(mo, SSound.sfx_bspwlk);
        A_Chase(mo);
    }

    // (A_OpenShotgun2, A_LoadShotgun2 and A_CloseShotgun2 are defined
    // here in p_enemy.c, but they're weapon actions and live in PPspr.)

    var braintargets as Array<Number> = new [32] as Array<Number>;
    var numbraintargets as Number = 0;
    var braintargeton as Number = 0;

    // Walks every thinker in the level.
    function A_BrainAwake(mo as Number) as Void {
        // find all the target spots
        numbraintargets = 0;
        braintargeton = 0;

        var next = PTick.thinkers_next;
        var funcs = PTick.thinkers_function;
        var types = PMobj.mobjs_type;
        for (var thinker = next[0];
             thinker != 0;
             thinker = next[thinker]) {
            if (funcs[thinker] != PTick.TF_MOBJ) {
                continue;   // not a mobj
            }

            if (types[thinker] == Info.MT_BOSSTARGET) {
                braintargets[numbraintargets] = thinker;
                numbraintargets++;
            }
        }

        SSound.S_StartSound(-1, SSound.sfx_bossit);
    }

    function A_BrainPain(mo as Number) as Void {
        SSound.S_StartSound(-1, SSound.sfx_bospn);
    }

    function A_BrainScream(mo as Number) as Void {
        var mx = PMobj.mobjs_x[mo];
        for (var x = mx - 196 * MFixed.FRACUNIT; x < mx + 320 * MFixed.FRACUNIT; x += MFixed.FRACUNIT * 8) {
            var y = PMobj.mobjs_y[mo] - 320 * MFixed.FRACUNIT;
            var z = 128 + MRandom.P_Random() * 2 * MFixed.FRACUNIT;
            var th = PMobj.P_SpawnMobj(x, y, z, Info.MT_ROCKET);
            PMobj.mobjs_momz[th] = MRandom.P_Random() * 512;

            PMobj.P_SetMobjState(th, Info.S_BRAINEXPLODE1);

            PMobj.mobjs_tics[th] -= MRandom.P_Random() & 7;
            if (PMobj.mobjs_tics[th] < 1) {
                PMobj.mobjs_tics[th] = 1;
            }
        }

        SSound.S_StartSound(-1, SSound.sfx_bosdth);
    }

    function A_BrainExplode(mo as Number) as Void {
        var x = PMobj.mobjs_x[mo] + (MRandom.P_Random() - MRandom.P_Random()) * 2048;
        var y = PMobj.mobjs_y[mo];
        var z = 128 + MRandom.P_Random() * 2 * MFixed.FRACUNIT;
        var th = PMobj.P_SpawnMobj(x, y, z, Info.MT_ROCKET);
        PMobj.mobjs_momz[th] = MRandom.P_Random() * 512;

        PMobj.P_SetMobjState(th, Info.S_BRAINEXPLODE1);

        PMobj.mobjs_tics[th] -= MRandom.P_Random() & 7;
        if (PMobj.mobjs_tics[th] < 1) {
            PMobj.mobjs_tics[th] = 1;
        }
    }

    function A_BrainDie(mo as Number) as Void {
        GGame.G_ExitLevel();
    }

    // static int easy in A_BrainSpit
    var easy as Number = 0;

    function A_BrainSpit(mo as Number) as Void {
        easy ^= 1;
        if (DoomStat.gameskill <= DoomDef.sk_easy && (easy == 0)) {
            return;
        }

        // shoot a cube at current target
        var targ = braintargets[braintargeton];
        braintargeton = (braintargeton + 1) % numbraintargets;

        // spawn brain missile
        var newmobj = PMobj.P_SpawnMissile(mo, targ, Info.MT_SPAWNSHOT);
        PMobj.mobjs_target[newmobj] = targ;
        PMobj.mobjs_reactiontime[newmobj] =
            ((PMobj.mobjs_y[targ] - PMobj.mobjs_y[mo]) / PMobj.mobjs_momy[newmobj])
            / Info.states[PMobj.mobjs_state[newmobj] * Info.ST_SIZE + Info.ST_TICS];

        SSound.S_StartSound(-1, SSound.sfx_bospit);
    }

    // travelling cube sound
    function A_SpawnSound(mo as Number) as Void {
        SSound.S_StartSound(mo, SSound.sfx_boscub);
        A_SpawnFly(mo);
    }

    function A_SpawnFly(mo as Number) as Void {
        PMobj.mobjs_reactiontime[mo]--;
        if (PMobj.mobjs_reactiontime[mo] != 0) {
            return;     // still flying
        }

        var targ = PMobj.mobjs_target[mo];

        // First spawn teleport fog.
        var fog = PMobj.P_SpawnMobj(PMobj.mobjs_x[targ], PMobj.mobjs_y[targ], PMobj.mobjs_z[targ], Info.MT_SPAWNFIRE);
        SSound.S_StartSound(fog, SSound.sfx_telept);

        // Randomly select monster to spawn.
        var r = MRandom.P_Random();
        var type;

        // Probability distribution (kind of :),
        // decreasing likelihood.
        if (r < 50) {
            type = Info.MT_TROOP;
        } else if (r < 90) {
            type = Info.MT_SERGEANT;
        } else if (r < 120) {
            type = Info.MT_SHADOWS;
        } else if (r < 130) {
            type = Info.MT_PAIN;
        } else if (r < 160) {
            type = Info.MT_HEAD;
        } else if (r < 162) {
            type = Info.MT_VILE;
        } else if (r < 172) {
            type = Info.MT_UNDEAD;
        } else if (r < 192) {
            type = Info.MT_BABY;
        } else if (r < 222) {
            type = Info.MT_FATSO;
        } else if (r < 246) {
            type = Info.MT_KNIGHT;
        } else {
            type = Info.MT_BRUISER;
        }

        var newmobj = PMobj.P_SpawnMobj(PMobj.mobjs_x[targ], PMobj.mobjs_y[targ], PMobj.mobjs_z[targ], type);
        if (P_LookForPlayers(newmobj, true)) {
            PMobj.P_SetMobjState(newmobj, PMobj.info(newmobj, Info.MI_SEESTATE));
        }

        // telefrag anything in this spot
        PMap.P_TeleportMove(newmobj, PMobj.mobjs_x[newmobj], PMobj.mobjs_y[newmobj]);

        // remove self (i.e., cube).
        PMobj.P_RemoveMobj(mo);
    }

    function A_PlayerScream(mo as Number) as Void {
        // Default death sound.
        var sound = SSound.sfx_pldeth;

        if ((DoomStat.gamemode == DoomDef.commercial)
            && (PMobj.mobjs_health[mo] < -50)) {
            // IF THE PLAYER DIES
            // LESS THAN -50% WITHOUT GIBBING
            sound = SSound.sfx_pdiehi;
        }

        SSound.S_StartSound(mo, sound);
    }
}
