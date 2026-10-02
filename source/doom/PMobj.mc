// p_mobj.c / p_mobj.h
//
// Moving object handling. Spawn functions.
//
// mobj_t is stored one array per field, indexed by the mobj's thinker
// number (see PTick): mobjs_x[mo] is mo->x. Pointers to other mobjs are
// mobj numbers and -1 is NULL; subsector is a subsector number, state a
// state number into Info.states, info is Info.mobjinfo[type * MI_SIZE].
// spawnpoint (a mapthing_t) is flattened as mobjs_spawnpoint[mo * 5 + i]
// in mapthing_t field order: x, y, angle, type, options.

import Toybox.Lang;

(:extendedCode)
module PMobj {

    //
    // Misc. mobj flags
    //
    // Call P_SpecialThing when touched.
    const MF_SPECIAL = 1;
    // Blocks.
    const MF_SOLID = 2;
    // Can be hit.
    const MF_SHOOTABLE = 4;
    // Don't use the sector links (invisible but touchable).
    const MF_NOSECTOR = 8;
    // Don't use the blocklinks (inert but displayable)
    const MF_NOBLOCKMAP = 16;

    // Not to be activated by sound, deaf monster.
    const MF_AMBUSH = 32;
    // Will try to attack right back.
    const MF_JUSTHIT = 64;
    // Will take at least one step before attacking.
    const MF_JUSTATTACKED = 128;
    // On level spawning (initial position),
    //  hang from ceiling instead of stand on floor.
    const MF_SPAWNCEILING = 256;
    // Don't apply gravity (every tic),
    //  that is, object will float, keeping current height
    //  or changing it actively.
    const MF_NOGRAVITY = 512;

    // Movement flags.
    // This allows jumps from high places.
    const MF_DROPOFF = 0x400;
    // For players, will pick up items.
    const MF_PICKUP = 0x800;
    // Player cheat. ???
    const MF_NOCLIP = 0x1000;
    // Player: keep info about sliding along walls.
    const MF_SLIDE = 0x2000;
    // Allow moves to any height, no gravity.
    // For active floaters, e.g. cacodemons, pain elementals.
    const MF_FLOAT = 0x4000;
    // Don't cross lines
    //   ??? or look at heights on teleport.
    const MF_TELEPORT = 0x8000;
    // Don't hit same species, explode on block.
    // Player missiles as well as fireballs of various kinds.
    const MF_MISSILE = 0x10000;
    // Dropped by a demon, not level spawned.
    // E.g. ammo clips dropped by dying former humans.
    const MF_DROPPED = 0x20000;
    // Use fuzzy draw (shadow demons or spectres),
    //  temporary player invisibility powerup.
    const MF_SHADOW = 0x40000;
    // Flag: don't bleed when shot (use puff),
    //  barrels and shootable furniture shall not bleed.
    const MF_NOBLOOD = 0x80000;
    // Don't stop moving halfway off a step,
    //  that is, have dead bodies slide down all the way.
    const MF_CORPSE = 0x100000;
    // Floating to a height for a move, ???
    //  don't auto float to target's height.
    const MF_INFLOAT = 0x200000;

    // On kill, count this enemy object
    //  towards intermission kill total.
    // Happy gathering.
    const MF_COUNTKILL = 0x400000;

    // On picking up, count this item object
    //  towards intermission item total.
    const MF_COUNTITEM = 0x800000;

    // Special handling: skull in flight.
    // Neither a cacodemon nor a missile.
    const MF_SKULLFLY = 0x1000000;

    // Don't spawn this object
    //  in death match mode (e.g. key cards).
    const MF_NOTDMATCH = 0x2000000;

    // Player sprites in multiplayer modes are modified
    //  using an internal color lookup table for re-indexing.
    // If 0x4 0x8 or 0xc,
    //  use a translation table for player colormaps
    const MF_TRANSLATION = 0xc000000;
    // Hmm ???.
    const MF_TRANSSHIFT = 26;

    // p_local.h
    const ONFLOORZ = DoomType.MININT;
    const ONCEILINGZ = DoomType.MAXINT;

    // Time interval for item respawning.
    const ITEMQUESIZE = 128;

    // Info for drawing: position.
    var mobjs_x as Array<Number> = [] as Array<Number>;
    var mobjs_y as Array<Number> = [] as Array<Number>;
    var mobjs_z as Array<Number> = [] as Array<Number>;

    // More list: links in sector (if needed)
    var mobjs_snext as Array<Number> = [] as Array<Number>;
    var mobjs_sprev as Array<Number> = [] as Array<Number>;

    //More drawing info: to determine current sprite.
    var mobjs_angle as Array<Number> = [] as Array<Number>;   // orientation
    var mobjs_sprite as Array<Number> = [] as Array<Number>;  // used to find patch_t and flip value
    var mobjs_frame as Array<Number> = [] as Array<Number>;   // might be ORed with FF_FULLBRIGHT

    // Interaction info, by BLOCKMAP.
    // Links in blocks (if needed).
    var mobjs_bnext as Array<Number> = [] as Array<Number>;
    var mobjs_bprev as Array<Number> = [] as Array<Number>;

    var mobjs_subsector as Array<Number> = [] as Array<Number>;

    // The closest interval over all contacted Sectors.
    var mobjs_floorz as Array<Number> = [] as Array<Number>;
    var mobjs_ceilingz as Array<Number> = [] as Array<Number>;

    // For movement checking.
    var mobjs_radius as Array<Number> = [] as Array<Number>;
    var mobjs_height as Array<Number> = [] as Array<Number>;

    // Momentums, used to update position.
    var mobjs_momx as Array<Number> = [] as Array<Number>;
    var mobjs_momy as Array<Number> = [] as Array<Number>;
    var mobjs_momz as Array<Number> = [] as Array<Number>;

    // If == validcount, already checked.
    var mobjs_validcount as Array<Number> = [] as Array<Number>;

    var mobjs_type as Array<Number> = [] as Array<Number>;
    var mobjs_tics as Array<Number> = [] as Array<Number>;   // state tic counter
    var mobjs_state as Array<Number> = [] as Array<Number>;
    var mobjs_flags as Array<Number> = [] as Array<Number>;
    var mobjs_health as Array<Number> = [] as Array<Number>;

    // Movement direction, movement generation (zig-zagging).
    var mobjs_movedir as Array<Number> = [] as Array<Number>;   // 0-7
    var mobjs_movecount as Array<Number> = [] as Array<Number>; // when 0, select a new dir

    // Thing being chased/attacked (or NULL),
    // also the originator for missiles.
    var mobjs_target as Array<Number> = [] as Array<Number>;

    // Reaction time: if non 0, don't attack yet.
    // Used by player to freeze a bit after teleporting.
    var mobjs_reactiontime as Array<Number> = [] as Array<Number>;

    // If >0, the target will be chased
    // no matter what (even if shot)
    var mobjs_threshold as Array<Number> = [] as Array<Number>;

    // Additional info record for player avatars only.
    // Only valid if type == MT_PLAYER: the player number, -1 otherwise.
    var mobjs_player as Array<Number> = [] as Array<Number>;

    // Player number last looked for.
    var mobjs_lastlook as Array<Number> = [] as Array<Number>;

    // For nightmare respawn.
    var mobjs_spawnpoint as Array<Number> = [] as Array<Number>;

    // Thing being chased/attacked for tracers.
    var mobjs_tracer as Array<Number> = [] as Array<Number>;

    // p_mobj.c: item respawn queue, mapthing_t flattened like spawnpoint.
    var itemrespawnque as Array<Number> = new [ITEMQUESIZE * 5] as Array<Number>;
    var itemrespawntime as Array<Number> = new [ITEMQUESIZE] as Array<Number>;
    var iquehead as Number = 0;
    var iquetail as Number = 0;

    // Sizes the mobj pool to match the thinker pool; called from
    // P_InitThinkers.
    function P_InitMobjs(n as Number) as Void {
        mobjs_x = new [n] as Array<Number>;
        mobjs_y = new [n] as Array<Number>;
        mobjs_z = new [n] as Array<Number>;
        mobjs_snext = new [n] as Array<Number>;
        mobjs_sprev = new [n] as Array<Number>;
        mobjs_angle = new [n] as Array<Number>;
        mobjs_sprite = new [n] as Array<Number>;
        mobjs_frame = new [n] as Array<Number>;
        mobjs_bnext = new [n] as Array<Number>;
        mobjs_bprev = new [n] as Array<Number>;
        mobjs_subsector = new [n] as Array<Number>;
        mobjs_floorz = new [n] as Array<Number>;
        mobjs_ceilingz = new [n] as Array<Number>;
        mobjs_radius = new [n] as Array<Number>;
        mobjs_height = new [n] as Array<Number>;
        mobjs_momx = new [n] as Array<Number>;
        mobjs_momy = new [n] as Array<Number>;
        mobjs_momz = new [n] as Array<Number>;
        mobjs_validcount = new [n] as Array<Number>;
        mobjs_type = new [n] as Array<Number>;
        mobjs_tics = new [n] as Array<Number>;
        mobjs_state = new [n] as Array<Number>;
        mobjs_flags = new [n] as Array<Number>;
        mobjs_health = new [n] as Array<Number>;
        mobjs_movedir = new [n] as Array<Number>;
        mobjs_movecount = new [n] as Array<Number>;
        mobjs_target = new [n] as Array<Number>;
        mobjs_reactiontime = new [n] as Array<Number>;
        mobjs_threshold = new [n] as Array<Number>;
        mobjs_player = new [n] as Array<Number>;
        mobjs_lastlook = new [n] as Array<Number>;
        mobjs_spawnpoint = new [n * 5] as Array<Number>;
        mobjs_tracer = new [n] as Array<Number>;
    }

    // mobj->info->field
    function info(mo as Number, field as Number) as Number {
        return Info.mobjinfo[mobjs_type[mo] * Info.MI_SIZE + field];
    }

    //
    // P_SetMobjState
    // Returns true if the mobj is still present.
    //
    function P_SetMobjState(mobj as Number, state as Number) as Boolean {
        var states = Info.states;
        do {
            if (state == Info.S_NULL) {
                mobjs_state[mobj] = Info.S_NULL;
                P_RemoveMobj(mobj);
                return false;
            }

            var st = state * Info.ST_SIZE;
            mobjs_state[mobj] = state;
            mobjs_tics[mobj] = states[st + Info.ST_TICS];
            mobjs_sprite[mobj] = states[st + Info.ST_SPRITE];
            mobjs_frame[mobj] = states[st + Info.ST_FRAME];

            // Modified handling.
            // Call action functions when the state is set
            var action = states[st + Info.ST_ACTION];
            if (action != 0) {
                Actions.P_MobjAction(action, mobj);
            }

            state = states[st + Info.ST_NEXTSTATE];
        } while (mobjs_tics[mobj] == 0);

        return true;
    }

    //
    // P_ExplodeMissile
    //
    function P_ExplodeMissile(mo as Number) as Void {
        mobjs_momx[mo] = 0;
        mobjs_momy[mo] = 0;
        mobjs_momz[mo] = 0;

        P_SetMobjState(mo, Info.mobjinfo[mobjs_type[mo] * Info.MI_SIZE + Info.MI_DEATHSTATE]);

        mobjs_tics[mo] -= MRandom.P_Random() & 3;

        if (mobjs_tics[mo] < 1) {
            mobjs_tics[mo] = 1;
        }

        mobjs_flags[mo] &= ~MF_MISSILE;

        var deathsound = info(mo, Info.MI_DEATHSOUND);
        if (deathsound != 0) {
            SSound.S_StartSound(mo, deathsound);
        }
    }

    //
    // P_XYMovement
    //
    const STOPSPEED = 0x1000;
    const FRICTION = 0xe800;

    function P_XYMovement(mo as Number) as Void {
        // (momentum arrays in locals: module variable reads are slow on
        // the watch. Only these two, since this frame sits under P_TryMove
        // and the VM stack is small.)
        var mmomx = mobjs_momx;
        var mmomy = mobjs_momy;
        var ptryx;
        var ptryy;
        var player;
        var xmove;
        var ymove;

        if (mmomx[mo] == 0 && mmomy[mo] == 0) {
            if ((mobjs_flags[mo] & MF_SKULLFLY) != 0) {
                // the skull slammed into something
                mobjs_flags[mo] &= ~MF_SKULLFLY;
                mmomx[mo] = 0;
                mmomy[mo] = 0;
                mobjs_momz[mo] = 0;

                P_SetMobjState(mo, info(mo, Info.MI_SPAWNSTATE));
            }
            return;
        }

        player = mobjs_player[mo];

        if (mmomx[mo] > PLocal.MAXMOVE) {
            mmomx[mo] = PLocal.MAXMOVE;
        } else if (mmomx[mo] < -PLocal.MAXMOVE) {
            mmomx[mo] = -PLocal.MAXMOVE;
        }

        if (mmomy[mo] > PLocal.MAXMOVE) {
            mmomy[mo] = PLocal.MAXMOVE;
        } else if (mmomy[mo] < -PLocal.MAXMOVE) {
            mmomy[mo] = -PLocal.MAXMOVE;
        }

        xmove = mmomx[mo];
        ymove = mmomy[mo];

        do {
            if (xmove > PLocal.MAXMOVE / 2 || ymove > PLocal.MAXMOVE / 2) {
                ptryx = mobjs_x[mo] + xmove / 2;
                ptryy = mobjs_y[mo] + ymove / 2;
                xmove >>= 1;
                ymove >>= 1;
            } else {
                ptryx = mobjs_x[mo] + xmove;
                ptryy = mobjs_y[mo] + ymove;
                xmove = 0;
                ymove = 0;
            }

            if (!PMap.P_TryMove(mo, ptryx, ptryy)) {
                // blocked move
                if (mobjs_player[mo] != -1) {
                    // try to slide along it
                    PMap.P_SlideMove(mo);
                } else if ((mobjs_flags[mo] & MF_MISSILE) != 0) {
                    // explode a missile
                    var ceilingline = PMap.ceilingline;
                    if (ceilingline != -1
                        && PSetup.lines_backsector[ceilingline] != -1
                        && PSetup.sectors_ceilingpic[PSetup.lines_backsector[ceilingline]] == RData.skyflatnum) {
                        // Hack to prevent missiles exploding
                        // against the sky.
                        // Does not handle sky floors.
                        P_RemoveMobj(mo);
                        return;
                    }
                    P_ExplodeMissile(mo);
                } else {
                    mmomx[mo] = 0;
                    mmomy[mo] = 0;
                }
            }
        } while (xmove != 0 || ymove != 0);

        // slow down
        if (player != -1 && (DPlayer.players_cheats[player] & DPlayer.CF_NOMOMENTUM) != 0) {
            // debug option for no sliding at all
            mmomx[mo] = 0;
            mmomy[mo] = 0;
            return;
        }

        if ((mobjs_flags[mo] & (MF_MISSILE | MF_SKULLFLY)) != 0) {
            return;     // no friction for missiles ever
        }

        if (mobjs_z[mo] > mobjs_floorz[mo]) {
            return;     // no friction when airborne
        }

        if ((mobjs_flags[mo] & MF_CORPSE) != 0) {
            // do not stop sliding
            //  if halfway off a step with some momentum
            if (mmomx[mo] > MFixed.FRACUNIT / 4
                || mmomx[mo] < -MFixed.FRACUNIT / 4
                || mmomy[mo] > MFixed.FRACUNIT / 4
                || mmomy[mo] < -MFixed.FRACUNIT / 4) {
                if (mobjs_floorz[mo] != PSetup.sectors_floorheight[PSetup.subsectors_sector[mobjs_subsector[mo]]]) {
                    return;
                }
            }
        }

        if (mmomx[mo] > -STOPSPEED
            && mmomx[mo] < STOPSPEED
            && mmomy[mo] > -STOPSPEED
            && mmomy[mo] < STOPSPEED
            && (player == -1
                || (DPlayer.players_cmd_forwardmove[player] == 0
                    && DPlayer.players_cmd_sidemove[player] == 0))) {
            // if in a walking frame, stop moving
            if (player != -1
                && DoomType.ULT(mobjs_state[DPlayer.players_mo[player]] - Info.S_PLAY_RUN1, 4)) {
                P_SetMobjState(DPlayer.players_mo[player], Info.S_PLAY);
            }

            mmomx[mo] = 0;
            mmomy[mo] = 0;
        } else {
            // FixedMul(mom, FRICTION), inlined: MFixed.FixedMul's split
            // with b = FRICTION, whose high half is 0
            mmomx[mo] = (mmomx[mo] >> 16) * FRICTION + ((((mmomx[mo] & 0xffff) * FRICTION) >> 16) & 0xffff);
            mmomy[mo] = (mmomy[mo] >> 16) * FRICTION + ((((mmomy[mo] & 0xffff) * FRICTION) >> 16) & 0xffff);
        }
    }

    //
    // P_ZMovement
    //
    function P_ZMovement(mo as Number) as Void {
        var dist;
        var delta;
        var player = mobjs_player[mo];

        // check for smooth step up
        if (player != -1 && mobjs_z[mo] < mobjs_floorz[mo]) {
            DPlayer.players_viewheight[player] -= mobjs_floorz[mo] - mobjs_z[mo];

            DPlayer.players_deltaviewheight[player]
                = (PLocal.VIEWHEIGHT - DPlayer.players_viewheight[player]) >> 3;
        }

        // adjust height
        mobjs_z[mo] += mobjs_momz[mo];

        var target = mobjs_target[mo];
        if ((mobjs_flags[mo] & MF_FLOAT) != 0
            && target != -1) {
            // float down towards target if too close
            if ((mobjs_flags[mo] & MF_SKULLFLY) == 0
                && (mobjs_flags[mo] & MF_INFLOAT) == 0) {
                dist = PMapUtl.P_AproxDistance(mobjs_x[mo] - mobjs_x[target],
                                               mobjs_y[mo] - mobjs_y[target]);

                delta = (mobjs_z[target] + (mobjs_height[mo] >> 1)) - mobjs_z[mo];

                if (delta < 0 && dist < -(delta * 3)) {
                    mobjs_z[mo] -= PLocal.FLOATSPEED;
                } else if (delta > 0 && dist < (delta * 3)) {
                    mobjs_z[mo] += PLocal.FLOATSPEED;
                }
            }
        }

        // clip movement
        if (mobjs_z[mo] <= mobjs_floorz[mo]) {
            // hit the floor

            // Note (id):
            //  somebody left this after the setting momz to 0,
            //  kinda useless there.
            if ((mobjs_flags[mo] & MF_SKULLFLY) != 0) {
                // the skull slammed into something
                mobjs_momz[mo] = -mobjs_momz[mo];
            }

            if (mobjs_momz[mo] < 0) {
                if (player != -1
                    && mobjs_momz[mo] < -PLocal.GRAVITY * 8) {
                    // Squat down.
                    // Decrease viewheight for a moment
                    // after hitting the ground (hard),
                    // and utter appropriate sound.
                    DPlayer.players_deltaviewheight[player] = mobjs_momz[mo] >> 3;
                    SSound.S_StartSound(mo, SSound.sfx_oof);
                }
                mobjs_momz[mo] = 0;
            }
            mobjs_z[mo] = mobjs_floorz[mo];

            if ((mobjs_flags[mo] & MF_MISSILE) != 0
                && (mobjs_flags[mo] & MF_NOCLIP) == 0) {
                P_ExplodeMissile(mo);
                return;
            }
        } else if ((mobjs_flags[mo] & MF_NOGRAVITY) == 0) {
            if (mobjs_momz[mo] == 0) {
                mobjs_momz[mo] = -PLocal.GRAVITY * 2;
            } else {
                mobjs_momz[mo] -= PLocal.GRAVITY;
            }
        }

        if (mobjs_z[mo] + mobjs_height[mo] > mobjs_ceilingz[mo]) {
            // hit the ceiling
            if (mobjs_momz[mo] > 0) {
                mobjs_momz[mo] = 0;
            }
            // (a bare { } block in the C, Monkey C has none)
            mobjs_z[mo] = mobjs_ceilingz[mo] - mobjs_height[mo];

            if ((mobjs_flags[mo] & MF_SKULLFLY) != 0) {
                // the skull slammed into something
                mobjs_momz[mo] = -mobjs_momz[mo];
            }

            if ((mobjs_flags[mo] & MF_MISSILE) != 0
                && (mobjs_flags[mo] & MF_NOCLIP) == 0) {
                P_ExplodeMissile(mo);
                return;
            }
        }
    }

    //
    // P_NightmareRespawn
    //
    function P_NightmareRespawn(mobj as Number) as Void {
        var x;
        var y;
        var z;
        var ss;
        var mo;
        var sp = mobj * 5;

        x = mobjs_spawnpoint[sp] << MFixed.FRACBITS;
        y = mobjs_spawnpoint[sp + 1] << MFixed.FRACBITS;

        // somthing is occupying it's position?
        if (!PMap.P_CheckPosition(mobj, x, y)) {
            return;     // no respwan
        }

        // spawn a teleport fog at old spot
        // because of removal of the body?
        mo = P_SpawnMobj(mobjs_x[mobj],
                         mobjs_y[mobj],
                         PSetup.sectors_floorheight[PSetup.subsectors_sector[mobjs_subsector[mobj]]], Info.MT_TFOG);
        // initiate teleport sound
        SSound.S_StartSound(mo, SSound.sfx_telept);

        // spawn a teleport fog at the new spot
        ss = RMain.R_PointInSubsector(x, y);

        mo = P_SpawnMobj(x, y, PSetup.sectors_floorheight[PSetup.subsectors_sector[ss]], Info.MT_TFOG);

        SSound.S_StartSound(mo, SSound.sfx_telept);

        // spawn the new monster
        // (mthing is &mobj->spawnpoint, read from mobjs_spawnpoint)

        // spawn it
        if ((info(mobj, Info.MI_FLAGS) & MF_SPAWNCEILING) != 0) {
            z = ONCEILINGZ;
        } else {
            z = ONFLOORZ;
        }

        // inherit attributes from deceased one
        mo = P_SpawnMobj(x, y, z, mobjs_type[mobj]);
        for (var i = 0; i < 5; i++) {
            mobjs_spawnpoint[mo * 5 + i] = mobjs_spawnpoint[sp + i];
        }
        mobjs_angle[mo] = Tables.ANG45 * (mobjs_spawnpoint[sp + 2] / 45);

        if ((mobjs_spawnpoint[sp + 4] & DoomDef.MTF_AMBUSH) != 0) {
            mobjs_flags[mo] |= MF_AMBUSH;
        }

        mobjs_reactiontime[mo] = 18;

        // remove the old monster,
        P_RemoveMobj(mobj);
    }

    //
    // P_MobjThinker
    //
    function P_MobjThinker(mobj as Number) as Void {
        // momentum movement
        if (mobjs_momx[mobj] != 0
            || mobjs_momy[mobj] != 0
            || (mobjs_flags[mobj] & MF_SKULLFLY) != 0) {
            P_XYMovement(mobj);

            // FIXME: decent NOP/NULL/Nil function pointer please.
            if (PTick.thinkers_function[mobj] == PTick.TF_REMOVED) {
                return;     // mobj was removed
            }
        }
        if ((mobjs_z[mobj] != mobjs_floorz[mobj])
            || mobjs_momz[mobj] != 0) {
            P_ZMovement(mobj);

            // FIXME: decent NOP/NULL/Nil function pointer please.
            if (PTick.thinkers_function[mobj] == PTick.TF_REMOVED) {
                return;     // mobj was removed
            }
        }

        // cycle through states,
        // calling action functions at transitions
        if (mobjs_tics[mobj] != -1) {
            mobjs_tics[mobj]--;

            // you can cycle through multiple states in a tic
            if (mobjs_tics[mobj] == 0) {
                if (!P_SetMobjState(mobj, Info.states[mobjs_state[mobj] * Info.ST_SIZE + Info.ST_NEXTSTATE])) {
                    return;     // freed itself
                }
            }
        } else {
            // check for nightmare respawn
            if ((mobjs_flags[mobj] & MF_COUNTKILL) == 0) {
                return;
            }

            if (!GGame.respawnmonsters) {
                return;
            }

            mobjs_movecount[mobj]++;

            if (mobjs_movecount[mobj] < 12 * 35) {
                return;
            }

            if ((PTick.leveltime & 31) != 0) {
                return;
            }

            if (MRandom.P_Random() > 4) {
                return;
            }

            P_NightmareRespawn(mobj);
        }
    }

    //
    // P_SpawnMobj
    //
    function P_SpawnMobj(x as Number, y as Number, z as Number, type as Number) as Number {
        var mobj = PTick.P_AllocThinker();
        var mi = Info.mobjinfo;
        var info = type * Info.MI_SIZE;

        // memset (mobj, 0, sizeof (*mobj));
        mobjs_snext[mobj] = -1;
        mobjs_sprev[mobj] = -1;
        mobjs_bnext[mobj] = -1;
        mobjs_bprev[mobj] = -1;
        mobjs_angle[mobj] = 0;
        mobjs_momx[mobj] = 0;
        mobjs_momy[mobj] = 0;
        mobjs_momz[mobj] = 0;
        mobjs_validcount[mobj] = 0;
        mobjs_movedir[mobj] = 0;
        mobjs_movecount[mobj] = 0;
        mobjs_target[mobj] = -1;
        mobjs_reactiontime[mobj] = 0;
        mobjs_threshold[mobj] = 0;
        mobjs_player[mobj] = -1;
        mobjs_tracer[mobj] = -1;
        for (var i = 0; i < 5; i++) {
            mobjs_spawnpoint[mobj * 5 + i] = 0;
        }

        mobjs_type[mobj] = type;
        mobjs_x[mobj] = x;
        mobjs_y[mobj] = y;
        mobjs_radius[mobj] = mi[info + Info.MI_RADIUS];
        mobjs_height[mobj] = mi[info + Info.MI_HEIGHT];
        mobjs_flags[mobj] = mi[info + Info.MI_FLAGS];
        mobjs_health[mobj] = mi[info + Info.MI_SPAWNHEALTH];

        if (DoomStat.gameskill != DoomDef.sk_nightmare) {
            mobjs_reactiontime[mobj] = mi[info + Info.MI_REACTIONTIME];
        }

        mobjs_lastlook[mobj] = MRandom.P_Random() % DoomStat.MAXPLAYERS;
        // do not set the state with P_SetMobjState,
        // because action routines can not be called yet
        var state = mi[info + Info.MI_SPAWNSTATE];
        var st = state * Info.ST_SIZE;

        mobjs_state[mobj] = state;
        mobjs_tics[mobj] = Info.states[st + Info.ST_TICS];
        mobjs_sprite[mobj] = Info.states[st + Info.ST_SPRITE];
        mobjs_frame[mobj] = Info.states[st + Info.ST_FRAME];

        // set subsector and/or block links
        PMapUtl.P_SetThingPosition(mobj);

        var sector = PSetup.subsectors_sector[mobjs_subsector[mobj]];
        mobjs_floorz[mobj] = PSetup.sectors_floorheight[sector];
        mobjs_ceilingz[mobj] = PSetup.sectors_ceilingheight[sector];

        if (z == ONFLOORZ) {
            mobjs_z[mobj] = mobjs_floorz[mobj];
        } else if (z == ONCEILINGZ) {
            mobjs_z[mobj] = mobjs_ceilingz[mobj] - mi[info + Info.MI_HEIGHT];
        } else {
            mobjs_z[mobj] = z;
        }

        PTick.thinkers_function[mobj] = PTick.TF_MOBJ;

        PTick.P_AddThinker(mobj);

        return mobj;
    }

    //
    // P_RemoveMobj
    //
    function P_RemoveMobj(mobj as Number) as Void {
        var flags = mobjs_flags[mobj];
        var type = mobjs_type[mobj];
        if ((flags & MF_SPECIAL) != 0
            && (flags & MF_DROPPED) == 0
            && (type != Info.MT_INV)
            && (type != Info.MT_INS)) {
            for (var i = 0; i < 5; i++) {
                itemrespawnque[iquehead * 5 + i] = mobjs_spawnpoint[mobj * 5 + i];
            }
            itemrespawntime[iquehead] = PTick.leveltime;
            iquehead = (iquehead + 1) & (ITEMQUESIZE - 1);

            // lose one off the end?
            if (iquehead == iquetail) {
                iquetail = (iquetail + 1) & (ITEMQUESIZE - 1);
            }
        }

        // unlink from sector and block lists
        PMapUtl.P_UnsetThingPosition(mobj);

        // stop any playing sound
        SSound.S_StopSound(mobj);

        // free block
        PTick.P_RemoveThinker(mobj);
    }

    //
    // P_RespawnSpecials
    //
    function P_RespawnSpecials() as Void {
        var x;
        var y;
        var z;

        var ss;
        var mo;
        var mthing;

        var i;

        // only respawn items in deathmatch
        // (deathmatch is a Boolean on the watch and altdeath, 2, is never
        // set, so this always returns; the rest is kept as in the C)
        if (!altdeath) {
            return;
        }

        // nothing left to respawn?
        if (iquehead == iquetail) {
            return;
        }

        // wait at least 30 seconds
        if (PTick.leveltime - itemrespawntime[iquetail] < 30 * 35) {
            return;
        }

        mthing = iquetail * 5;

        x = itemrespawnque[mthing] << MFixed.FRACBITS;
        y = itemrespawnque[mthing + 1] << MFixed.FRACBITS;

        // spawn a teleport fog at the new spot
        ss = RMain.R_PointInSubsector(x, y);
        mo = P_SpawnMobj(x, y, PSetup.sectors_floorheight[PSetup.subsectors_sector[ss]], Info.MT_IFOG);
        SSound.S_StartSound(mo, SSound.sfx_itmbk);

        // find which type to spawn
        var mi = Info.mobjinfo;
        for (i = 0; i < Info.NUMMOBJTYPES; i++) {
            if (itemrespawnque[mthing + 3] == mi[i * Info.MI_SIZE + Info.MI_DOOMEDNUM]) {
                break;
            }
        }

        // spawn it
        if ((mi[i * Info.MI_SIZE + Info.MI_FLAGS] & MF_SPAWNCEILING) != 0) {
            z = ONCEILINGZ;
        } else {
            z = ONFLOORZ;
        }

        mo = P_SpawnMobj(x, y, z, i);
        for (var k = 0; k < 5; k++) {
            mobjs_spawnpoint[mo * 5 + k] = itemrespawnque[mthing + k];
        }
        mobjs_angle[mo] = Tables.ANG45 * (itemrespawnque[mthing + 2] / 45);

        // pull it from the que
        iquetail = (iquetail + 1) & (ITEMQUESIZE - 1);
    }

    // deathmatch == 2 (altdeath) in the C code.
    var altdeath as Boolean = false;

    //
    // P_SpawnPlayer
    // Called when a player is spawned on the level.
    // Most of the player structure stays unchanged
    //  between levels.
    //
    function P_SpawnPlayer(mthing as Array<Number>) as Void {
        var p;
        var x;
        var y;
        var z;

        var mobj;

        var i;

        // not playing?
        if (!DPlayer.playeringame[mthing[3] - 1]) {
            return;
        }

        p = mthing[3] - 1;

        if (DPlayer.players_playerstate[p] == DPlayer.PST_REBORN) {
            GGame.G_PlayerReborn(p);
        }

        x = mthing[0] << MFixed.FRACBITS;
        y = mthing[1] << MFixed.FRACBITS;
        z = ONFLOORZ;
        mobj = P_SpawnMobj(x, y, z, Info.MT_PLAYER);

        // set color translations for player sprites
        if (mthing[3] > 1) {
            mobjs_flags[mobj] |= (mthing[3] - 1) << MF_TRANSSHIFT;
        }

        mobjs_angle[mobj] = Tables.ANG45 * (mthing[2] / 45);
        mobjs_player[mobj] = p;
        mobjs_health[mobj] = DPlayer.players_health[p];

        DPlayer.players_mo[p] = mobj;
        DPlayer.players_playerstate[p] = DPlayer.PST_LIVE;
        DPlayer.players_refire[p] = 0;
        DPlayer.players_message[p] = null;
        DPlayer.players_damagecount[p] = 0;
        DPlayer.players_bonuscount[p] = 0;
        DPlayer.players_extralight[p] = 0;
        DPlayer.players_fixedcolormap[p] = 0;
        DPlayer.players_viewheight[p] = PLocal.VIEWHEIGHT;

        // setup gun psprite
        PPspr.P_SetupPsprites(p);

        // give all cards in death match mode
        if (DoomStat.deathmatch) {
            for (i = 0; i < DoomDef.NUMCARDS; i++) {
                DPlayer.players_cards[p * DoomDef.NUMCARDS + i] = 1;
            }
        }

        if (p == DPlayer.consoleplayer) {
            // wake up the status bar
            StStuff.ST_Start();
            // wake up the heads up text
            HuStuff.HU_Start();
        }
    }

    //
    // P_SpawnMapThing
    // The fields of the mapthing should
    // already be in host byte order.
    //
    // mthing is a mapthing_t as [x, y, angle, type, options].
    //
    function P_SpawnMapThing(mthing as Array<Number>) as Void {
        var i;
        var bit;
        var mobj;
        var x;
        var y;
        var z;
        var type = mthing[3];
        var options = mthing[4];

        // count deathmatch start positions
        // (single player only: deathmatch starts aren't kept)
        if (type == 11) {
            return;
        }

        // check for players specially
        if (type <= 4) {
            // save spots for respawning in network games
            DoomStat.playerstarts[type - 1] = mthing;
            if (!DoomStat.deathmatch) {
                P_SpawnPlayer(mthing);
            }

            return;
        }

        // check for apropriate skill level
        if (!DoomStat.netgame && (options & 16) != 0) {
            return;
        }

        if (DoomStat.gameskill == DoomDef.sk_baby) {
            bit = 1;
        } else if (DoomStat.gameskill == DoomDef.sk_nightmare) {
            bit = 4;
        } else {
            bit = 1 << (DoomStat.gameskill - 1);
        }

        if ((options & bit) == 0) {
            return;
        }

        // find which type to spawn
        var mi = Info.mobjinfo;
        for (i = 0; i < Info.NUMMOBJTYPES; i++) {
            if (type == mi[i * Info.MI_SIZE + Info.MI_DOOMEDNUM]) {
                break;
            }
        }

        if (i == Info.NUMMOBJTYPES) {
            ISystem.I_Error("P_SpawnMapThing: Unknown type " + type + " at (" + mthing[0] + ", " + mthing[1] + ")");
        }

        var flags = mi[i * Info.MI_SIZE + Info.MI_FLAGS];

        // don't spawn keycards and players in deathmatch
        if (DoomStat.deathmatch && (flags & MF_NOTDMATCH) != 0) {
            return;
        }

        // don't spawn any monsters if -nomonsters
        if (DoomStat.nomonsters
            && (i == Info.MT_SKULL
                || (flags & MF_COUNTKILL) != 0)) {
            return;
        }

        // spawn it
        x = mthing[0] << MFixed.FRACBITS;
        y = mthing[1] << MFixed.FRACBITS;

        if ((flags & MF_SPAWNCEILING) != 0) {
            z = ONCEILINGZ;
        } else {
            z = ONFLOORZ;
        }

        mobj = P_SpawnMobj(x, y, z, i);
        for (var k = 0; k < 5; k++) {
            mobjs_spawnpoint[mobj * 5 + k] = mthing[k];
        }

        if (mobjs_tics[mobj] > 0) {
            mobjs_tics[mobj] = 1 + (MRandom.P_Random() % mobjs_tics[mobj]);
        }
        if ((mobjs_flags[mobj] & MF_COUNTKILL) != 0) {
            DoomStat.totalkills++;
        }
        if ((mobjs_flags[mobj] & MF_COUNTITEM) != 0) {
            DoomStat.totalitems++;
        }

        mobjs_angle[mobj] = Tables.ANG45 * (mthing[2] / 45);
        if ((options & DoomDef.MTF_AMBUSH) != 0) {
            mobjs_flags[mobj] |= MF_AMBUSH;
        }
    }

    //
    // GAME SPAWN FUNCTIONS
    //

    //
    // P_SpawnPuff
    //
    function P_SpawnPuff(x as Number, y as Number, z as Number) as Void {
        var th;

        z += ((MRandom.P_Random() - MRandom.P_Random()) << 10);

        th = P_SpawnMobj(x, y, z, Info.MT_PUFF);
        mobjs_momz[th] = MFixed.FRACUNIT;
        mobjs_tics[th] -= MRandom.P_Random() & 3;

        if (mobjs_tics[th] < 1) {
            mobjs_tics[th] = 1;
        }

        // don't make punches spark on the wall
        if (PMap.attackrange == PLocal.MELEERANGE) {
            P_SetMobjState(th, Info.S_PUFF3);
        }
    }

    //
    // P_SpawnBlood
    //
    function P_SpawnBlood(x as Number, y as Number, z as Number, damage as Number) as Void {
        var th;

        z += ((MRandom.P_Random() - MRandom.P_Random()) << 10);
        th = P_SpawnMobj(x, y, z, Info.MT_BLOOD);
        mobjs_momz[th] = MFixed.FRACUNIT * 2;
        mobjs_tics[th] -= MRandom.P_Random() & 3;

        if (mobjs_tics[th] < 1) {
            mobjs_tics[th] = 1;
        }

        if (damage <= 12 && damage >= 9) {
            P_SetMobjState(th, Info.S_BLOOD2);
        } else if (damage < 9) {
            P_SetMobjState(th, Info.S_BLOOD3);
        }
    }

    //
    // P_CheckMissileSpawn
    // Moves the missile forward a bit
    //  and possibly explodes it right there.
    //
    function P_CheckMissileSpawn(th as Number) as Void {
        mobjs_tics[th] -= MRandom.P_Random() & 3;
        if (mobjs_tics[th] < 1) {
            mobjs_tics[th] = 1;
        }

        // move a little forward so an angle can
        // be computed if it immediately explodes
        mobjs_x[th] += (mobjs_momx[th] >> 1);
        mobjs_y[th] += (mobjs_momy[th] >> 1);
        mobjs_z[th] += (mobjs_momz[th] >> 1);

        if (!PMap.P_TryMove(th, mobjs_x[th], mobjs_y[th])) {
            P_ExplodeMissile(th);
        }
    }

    //
    // P_SpawnMissile
    //
    function P_SpawnMissile(source as Number, dest as Number, type as Number) as Number {
        var th;
        var an;
        var dist;

        th = P_SpawnMobj(mobjs_x[source],
                         mobjs_y[source],
                         mobjs_z[source] + 4 * 8 * MFixed.FRACUNIT, type);

        var seesound = info(th, Info.MI_SEESOUND);
        if (seesound != 0) {
            SSound.S_StartSound(th, seesound);
        }

        mobjs_target[th] = source;  // where it came from
        an = RMain.R_PointToAngle2(mobjs_x[source], mobjs_y[source], mobjs_x[dest], mobjs_y[dest]);

        // fuzzy player
        if ((mobjs_flags[dest] & MF_SHADOW) != 0) {
            an += (MRandom.P_Random() - MRandom.P_Random()) << 20;
        }

        mobjs_angle[th] = an;
        // angle_t is unsigned
        an = DoomType.USHR(an, Tables.ANGLETOFINESHIFT);
        var speed = info(th, Info.MI_SPEED);
        mobjs_momx[th] = MFixed.FixedMul(speed, Tables.finesine[Tables.FINECOSINE + an]);
        mobjs_momy[th] = MFixed.FixedMul(speed, Tables.finesine[an]);

        dist = PMapUtl.P_AproxDistance(mobjs_x[dest] - mobjs_x[source], mobjs_y[dest] - mobjs_y[source]);
        dist = dist / speed;

        if (dist < 1) {
            dist = 1;
        }

        mobjs_momz[th] = (mobjs_z[dest] - mobjs_z[source]) / dist;
        P_CheckMissileSpawn(th);

        return th;
    }

    //
    // P_SpawnPlayerMissile
    // Tries to aim at a nearby monster
    //
    function P_SpawnPlayerMissile(source as Number, type as Number) as Void {
        var th;
        var an;

        var x;
        var y;
        var z;
        var slope;

        // see which target is to be aimed at
        an = mobjs_angle[source];
        slope = PMap.P_AimLineAttack(source, an, 16 * 64 * MFixed.FRACUNIT);

        if (PMap.linetarget == -1) {
            an += 1 << 26;
            slope = PMap.P_AimLineAttack(source, an, 16 * 64 * MFixed.FRACUNIT);

            if (PMap.linetarget == -1) {
                an -= 2 << 26;
                slope = PMap.P_AimLineAttack(source, an, 16 * 64 * MFixed.FRACUNIT);
            }

            if (PMap.linetarget == -1) {
                an = mobjs_angle[source];
                slope = 0;
            }
        }

        x = mobjs_x[source];
        y = mobjs_y[source];
        z = mobjs_z[source] + 4 * 8 * MFixed.FRACUNIT;

        th = P_SpawnMobj(x, y, z, type);

        var seesound = info(th, Info.MI_SEESOUND);
        if (seesound != 0) {
            SSound.S_StartSound(th, seesound);
        }

        mobjs_target[th] = source;
        mobjs_angle[th] = an;
        var speed = info(th, Info.MI_SPEED);
        // angle_t is unsigned
        var fine = DoomType.USHR(an, Tables.ANGLETOFINESHIFT);
        mobjs_momx[th] = MFixed.FixedMul(speed, Tables.finesine[Tables.FINECOSINE + fine]);
        mobjs_momy[th] = MFixed.FixedMul(speed, Tables.finesine[fine]);
        mobjs_momz[th] = MFixed.FixedMul(speed, slope);

        P_CheckMissileSpawn(th);
    }
}
