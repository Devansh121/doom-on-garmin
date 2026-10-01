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
    // The rest of p_mobj.c (P_MobjThinker and movement, respawning,
    // P_SpawnPlayer, the missile/puff/blood spawners) isn't ported yet;
    // these keep the callers compiling until it is.
    //
    function P_MobjThinker(mobj as Number) as Void {
    }

    function P_RespawnSpecials() as Void {
    }

    function P_SpawnPlayer(mthing as Array<Number>) as Void {
    }

    function P_SpawnPuff(x as Number, y as Number, z as Number) as Void {
    }

    function P_SpawnBlood(x as Number, y as Number, z as Number, damage as Number) as Void {
    }

    function P_SpawnMissile(source as Number, dest as Number, type as Number) as Number {
        return -1;
    }

    function P_SpawnPlayerMissile(source as Number, type as Number) as Void {
    }

    function P_ExplodeMissile(mo as Number) as Void {
    }

    function P_CheckMissileSpawn(th as Number) as Void {
    }

    // P_SpawnMapThing
    // The fields of the mapthing should
    // already be in host byte order.
    function P_SpawnMapThing(mthing as Array<Number>) as Void {
        var type = mthing[3];

        // check for players specially
        if (type <= 4) {
            // save spots for respawning in network games
            DoomStat.playerstarts[type - 1] = mthing;
            return;
        }
    }
}
