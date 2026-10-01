// p_ceilng.c
//
// Ceiling aninmation (lowering, crushing, raising)
//
// A ceiling_t is a PTick thinker (TF_MOVECEILING, or TF_NULL while in
// stasis) whose fields are PTick.thinkers_data[ceiling][CE_*], in the
// struct's order.

import Toybox.Lang;

(:extendedCode)
module PCeilng {

    // ceiling_t fields
    const CE_TYPE = 0;          // ceiling_e
    const CE_SECTOR = 1;        // sector_t*
    const CE_BOTTOMHEIGHT = 2;
    const CE_TOPHEIGHT = 3;
    const CE_SPEED = 4;
    const CE_CRUSH = 5;         // boolean, 0 or 1
    // 1 = up, 0 = waiting, -1 = down
    const CE_DIRECTION = 6;
    // ID
    const CE_TAG = 7;
    const CE_OLDDIRECTION = 8;
    const CE_SIZE = 9;

    //
    // CEILINGS
    //

    // ceiling_t* activeceilings[MAXCEILINGS], as thinker numbers, -1 for NULL
    var activeceilings as Array<Number> = [
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
    ] as Array<Number>;

    //
    // T_MoveCeiling
    //
    function T_MoveCeiling(ceiling as Number) as Void {
        var c = PTick.thinkers_data[ceiling] as Array<Number>;
        var sector = c[CE_SECTOR];
        var res;

        switch (c[CE_DIRECTION]) {
            case 0:
                // IN STASIS
                break;
            case 1:
                // UP
                res = PFloor.T_MovePlane(sector,
                                         c[CE_SPEED],
                                         c[CE_TOPHEIGHT],
                                         false, 1, c[CE_DIRECTION]);

                if ((PTick.leveltime & 7) == 0) {
                    switch (c[CE_TYPE]) {
                        case PSpec.silentCrushAndRaise:
                            break;
                        default:
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_stnmov);
                            // ?
                            break;
                    }
                }

                if (res == PSpec.pastdest) {
                    switch (c[CE_TYPE]) {
                        case PSpec.raiseToHighest:
                            P_RemoveActiveCeiling(ceiling);
                            break;

                        case PSpec.silentCrushAndRaise:
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_pstop);
                        case PSpec.fastCrushAndRaise:
                        case PSpec.crushAndRaise:
                            c[CE_DIRECTION] = -1;
                            break;

                        default:
                            break;
                    }
                }
                break;

            case -1:
                // DOWN
                res = PFloor.T_MovePlane(sector,
                                         c[CE_SPEED],
                                         c[CE_BOTTOMHEIGHT],
                                         c[CE_CRUSH] != 0, 1, c[CE_DIRECTION]);

                if ((PTick.leveltime & 7) == 0) {
                    switch (c[CE_TYPE]) {
                        case PSpec.silentCrushAndRaise: break;
                        default:
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_stnmov);
                    }
                }

                if (res == PSpec.pastdest) {
                    switch (c[CE_TYPE]) {
                        case PSpec.silentCrushAndRaise:
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_pstop);
                        case PSpec.crushAndRaise:
                            c[CE_SPEED] = PSpec.CEILSPEED;
                        case PSpec.fastCrushAndRaise:
                            c[CE_DIRECTION] = 1;
                            break;

                        case PSpec.lowerAndCrush:
                        case PSpec.lowerToFloor:
                            P_RemoveActiveCeiling(ceiling);
                            break;

                        default:
                            break;
                    }
                } else { // ( res != pastdest )
                    if (res == PSpec.crushed) {
                        switch (c[CE_TYPE]) {
                            case PSpec.silentCrushAndRaise:
                            case PSpec.crushAndRaise:
                            case PSpec.lowerAndCrush:
                                c[CE_SPEED] = PSpec.CEILSPEED / 8;
                                break;

                            default:
                                break;
                        }
                    }
                }
                break;
        }
    }

    //
    // EV_DoCeiling
    // Move a ceiling up/down and all around!
    //
    function EV_DoCeiling(line as Number, type as Number) as Number {
        var rtn = 0;

        //	Reactivate in-stasis ceilings...for certain types.
        switch (type) {
            case PSpec.fastCrushAndRaise:
            case PSpec.silentCrushAndRaise:
            case PSpec.crushAndRaise:
                P_ActivateInStasisCeiling(line);
            default:
                break;
        }

        // while ((secnum = P_FindSectorFromLineTag(line,secnum)) >= 0):
        // Monkey C has no assignment in expressions.
        for (var secnum = PSpec.P_FindSectorFromLineTag(line, -1); secnum >= 0;
             secnum = PSpec.P_FindSectorFromLineTag(line, secnum)) {
            var sec = secnum;
            if (PSetup.sectors_specialdata[sec] != -1) {
                continue;
            }

            // new door thinker
            rtn = 1;
            // ceiling = Z_Malloc (sizeof(*ceiling), PU_LEVSPEC, 0); the
            // fields start at 0 rather than whatever the zone had in it.
            var ceiling = PTick.P_AllocThinker();
            var c = [0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
            PTick.thinkers_data[ceiling] = c;
            PTick.P_AddThinker(ceiling);
            PSetup.sectors_specialdata[sec] = ceiling;
            PTick.thinkers_function[ceiling] = PTick.TF_MOVECEILING;
            c[CE_SECTOR] = sec;
            c[CE_CRUSH] = 0;

            switch (type) {
                case PSpec.fastCrushAndRaise:
                    c[CE_CRUSH] = 1;
                    c[CE_TOPHEIGHT] = PSetup.sectors_ceilingheight[sec];
                    c[CE_BOTTOMHEIGHT] = PSetup.sectors_floorheight[sec] + (8 * MFixed.FRACUNIT);
                    c[CE_DIRECTION] = -1;
                    c[CE_SPEED] = PSpec.CEILSPEED * 2;
                    break;

                case PSpec.silentCrushAndRaise:
                case PSpec.crushAndRaise:
                    c[CE_CRUSH] = 1;
                    c[CE_TOPHEIGHT] = PSetup.sectors_ceilingheight[sec];
                case PSpec.lowerAndCrush:
                case PSpec.lowerToFloor:
                    c[CE_BOTTOMHEIGHT] = PSetup.sectors_floorheight[sec];
                    if (type != PSpec.lowerToFloor) {
                        c[CE_BOTTOMHEIGHT] += 8 * MFixed.FRACUNIT;
                    }
                    c[CE_DIRECTION] = -1;
                    c[CE_SPEED] = PSpec.CEILSPEED;
                    break;

                case PSpec.raiseToHighest:
                    c[CE_TOPHEIGHT] = PSpec.P_FindHighestCeilingSurrounding(sec);
                    c[CE_DIRECTION] = 1;
                    c[CE_SPEED] = PSpec.CEILSPEED;
                    break;
            }

            c[CE_TAG] = PSetup.sectors_tag[sec];
            c[CE_TYPE] = type;
            P_AddActiveCeiling(ceiling);
        }
        return rtn;
    }

    //
    // Add an active ceiling
    //
    function P_AddActiveCeiling(c as Number) as Void {
        for (var i = 0; i < PSpec.MAXCEILINGS; i++) {
            if (activeceilings[i] == -1) {
                activeceilings[i] = c;
                return;
            }
        }
    }

    //
    // Remove a ceiling's thinker
    //
    function P_RemoveActiveCeiling(c as Number) as Void {
        for (var i = 0; i < PSpec.MAXCEILINGS; i++) {
            if (activeceilings[i] == c) {
                var d = PTick.thinkers_data[activeceilings[i]] as Array<Number>;
                PSetup.sectors_specialdata[d[CE_SECTOR]] = -1;
                PTick.P_RemoveThinker(activeceilings[i]);
                activeceilings[i] = -1;
                break;
            }
        }
    }

    //
    // Restart a ceiling that's in-stasis
    //
    function P_ActivateInStasisCeiling(line as Number) as Void {
        var tag = PSetup.lines_tag[line];
        for (var i = 0; i < PSpec.MAXCEILINGS; i++) {
            var ceiling = activeceilings[i];
            if (ceiling != -1) {
                var c = PTick.thinkers_data[ceiling] as Array<Number>;
                if (c[CE_TAG] == tag && c[CE_DIRECTION] == 0) {
                    c[CE_DIRECTION] = c[CE_OLDDIRECTION];
                    PTick.thinkers_function[ceiling] = PTick.TF_MOVECEILING;
                }
            }
        }
    }

    //
    // EV_CeilingCrushStop
    // Stop a ceiling from crushing!
    //
    function EV_CeilingCrushStop(line as Number) as Number {
        var tag = PSetup.lines_tag[line];
        var rtn = 0;
        for (var i = 0; i < PSpec.MAXCEILINGS; i++) {
            var ceiling = activeceilings[i];
            if (ceiling != -1) {
                var c = PTick.thinkers_data[ceiling] as Array<Number>;
                if (c[CE_TAG] == tag && c[CE_DIRECTION] != 0) {
                    c[CE_OLDDIRECTION] = c[CE_DIRECTION];
                    PTick.thinkers_function[ceiling] = PTick.TF_NULL;
                    c[CE_DIRECTION] = 0;  // in-stasis
                    rtn = 1;
                }
            }
        }

        return rtn;
    }
}
