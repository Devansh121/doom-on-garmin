// p_telept.c
//
// Teleportation.

import Toybox.Lang;

module PTelept {

    //
    // TELEPORTATION
    //
    // For every sector with the line's tag this walks the whole thinker
    // list, so it's sectors x thinkers; it may need splitting on a busy
    // map.
    //
    function EV_Teleport(line as Number, side as Number, thing as Number) as Number {
        // don't teleport missiles
        if ((PMobj.mobjs_flags[thing] & PMobj.MF_MISSILE) != 0) {
            return 0;
        }

        // Don't teleport if hit back of line,
        //  so you can get out of teleporter.
        if (side == 1) {
            return 0;
        }

        var tag = PSetup.lines_tag[line];
        var tags = PSetup.sectors_tag;
        var next = PTick.thinkers_next;
        var funcs = PTick.thinkers_function;
        var types = PMobj.mobjs_type;
        for (var i = 0; i < PSetup.numsectors; i++) {
            if (tags[i] == tag) {
                for (var thinker = next[0]; thinker != 0; thinker = next[thinker]) {
                    // not a mobj
                    if (funcs[thinker] != PTick.TF_MOBJ) {
                        continue;
                    }

                    var m = thinker;

                    // not a teleportman
                    if (types[m] != Info.MT_TELEPORTMAN) {
                        continue;
                    }

                    var sector = PSetup.subsectors_sector[PMobj.mobjs_subsector[m]];
                    // wrong sector
                    if (sector != i) {
                        continue;
                    }

                    var oldx = PMobj.mobjs_x[thing];
                    var oldy = PMobj.mobjs_y[thing];
                    var oldz = PMobj.mobjs_z[thing];

                    if (!PMap.P_TeleportMove(thing, PMobj.mobjs_x[m], PMobj.mobjs_y[m])) {
                        return 0;
                    }

                    PMobj.mobjs_z[thing] = PMobj.mobjs_floorz[thing];  //fixme: not needed?
                    var player = PMobj.mobjs_player[thing];
                    if (player != -1) {
                        DPlayer.players_viewz[player] = PMobj.mobjs_z[thing] + DPlayer.players_viewheight[player];
                    }

                    // spawn teleport fog at source and destination
                    var fog = PMobj.P_SpawnMobj(oldx, oldy, oldz, Info.MT_TFOG);
                    SSound.S_StartSound(fog, SSound.sfx_telept);
                    var an = (PMobj.mobjs_angle[m] >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
                    fog = PMobj.P_SpawnMobj(PMobj.mobjs_x[m] + 20 * Tables.finesine[Tables.FINECOSINE + an],
                                            PMobj.mobjs_y[m] + 20 * Tables.finesine[an],
                                            PMobj.mobjs_z[thing], Info.MT_TFOG);

                    // emit sound, where?
                    SSound.S_StartSound(fog, SSound.sfx_telept);

                    // don't move for a bit
                    if (player != -1) {
                        PMobj.mobjs_reactiontime[thing] = 18;
                    }

                    PMobj.mobjs_angle[thing] = PMobj.mobjs_angle[m];
                    PMobj.mobjs_momx[thing] = 0;
                    PMobj.mobjs_momy[thing] = 0;
                    PMobj.mobjs_momz[thing] = 0;
                    return 1;
                }
            }
        }
        return 0;
    }
}
