// p_plats.c
//
// Plats (i.e. elevator platforms) code, raising/lowering.
//
// A plat_t is a PTick thinker (TF_PLATRAISE, or TF_NULL while in stasis)
// whose fields are PTick.thinkers_data[plat][PL_*], in the struct's order.

import Toybox.Lang;

(:extendedCode)
module PPlats {

    // plat_t fields
    const PL_SECTOR = 0;     // sector_t*
    const PL_SPEED = 1;
    const PL_LOW = 2;
    const PL_HIGH = 3;
    const PL_WAIT = 4;
    const PL_COUNT = 5;
    const PL_STATUS = 6;     // plat_e
    const PL_OLDSTATUS = 7;  // plat_e
    const PL_CRUSH = 8;      // boolean, 0 or 1
    const PL_TAG = 9;
    const PL_TYPE = 10;      // plattype_e
    const PL_SIZE = 11;

    // plat_t* activeplats[MAXPLATS], as thinker numbers, -1 for NULL
    var activeplats as Array<Number> = [
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
    ] as Array<Number>;

    //
    // Move a plat up and down
    //
    function T_PlatRaise(plat as Number) as Void {
        var p = PTick.thinkers_data[plat] as Array<Number>;
        var sector = p[PL_SECTOR];
        var res;

        switch (p[PL_STATUS]) {
            case PSpec.up:
                res = PFloor.T_MovePlane(sector,
                                         p[PL_SPEED],
                                         p[PL_HIGH],
                                         p[PL_CRUSH] != 0, 0, 1);

                if (p[PL_TYPE] == PSpec.raiseAndChange
                    || p[PL_TYPE] == PSpec.raiseToNearestAndChange) {
                    if ((PTick.leveltime & 7) == 0) {
                        SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_stnmov);
                    }
                }

                if (res == PSpec.crushed && (p[PL_CRUSH] == 0)) {
                    p[PL_COUNT] = p[PL_WAIT];
                    p[PL_STATUS] = PSpec.down;
                    SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_pstart);
                } else {
                    if (res == PSpec.pastdest) {
                        p[PL_COUNT] = p[PL_WAIT];
                        p[PL_STATUS] = PSpec.waiting;
                        SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_pstop);

                        switch (p[PL_TYPE]) {
                            case PSpec.blazeDWUS:
                            case PSpec.downWaitUpStay:
                                P_RemoveActivePlat(plat);
                                break;

                            case PSpec.raiseAndChange:
                            case PSpec.raiseToNearestAndChange:
                                P_RemoveActivePlat(plat);
                                break;

                            default:
                                break;
                        }
                    }
                }
                break;

            case PSpec.down:
                res = PFloor.T_MovePlane(sector, p[PL_SPEED], p[PL_LOW], false, 0, -1);

                if (res == PSpec.pastdest) {
                    p[PL_COUNT] = p[PL_WAIT];
                    p[PL_STATUS] = PSpec.waiting;
                    SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_pstop);
                }
                break;

            case PSpec.waiting:
                p[PL_COUNT]--;
                if (p[PL_COUNT] == 0) {
                    if (PSetup.sectors_floorheight[sector] == p[PL_LOW]) {
                        p[PL_STATUS] = PSpec.up;
                    } else {
                        p[PL_STATUS] = PSpec.down;
                    }
                    SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_pstart);
                }
            case PSpec.in_stasis:
                break;
        }
    }

    //
    // Do Platforms
    //  "amount" is only used for SOME platforms.
    //
    function EV_DoPlat(line as Number, type as Number, amount as Number) as Number {
        var rtn = 0;

        //	Activate all <type> plats that are in_stasis
        switch (type) {
            case PSpec.perpetualRaise:
                P_ActivateInStasis(PSetup.lines_tag[line]);
                break;

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

            // Find lowest & highest floors around sector
            rtn = 1;
            // plat = Z_Malloc( sizeof(*plat), PU_LEVSPEC, 0); the fields
            // start at 0 rather than whatever the zone had in it.
            var plat = PTick.P_AllocThinker();
            var p = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
            PTick.thinkers_data[plat] = p;
            PTick.P_AddThinker(plat);

            p[PL_TYPE] = type;
            p[PL_SECTOR] = sec;
            PSetup.sectors_specialdata[sec] = plat;
            PTick.thinkers_function[plat] = PTick.TF_PLATRAISE;
            p[PL_CRUSH] = 0;
            p[PL_TAG] = PSetup.lines_tag[line];

            switch (type) {
                case PSpec.raiseToNearestAndChange:
                    p[PL_SPEED] = PSpec.PLATSPEED / 2;
                    PSetup.sectors_floorpic[sec] = PSetup.sectors_floorpic[PSetup.sides_sector[PSetup.lines_sidenum[line * 2]]];
                    p[PL_HIGH] = PSpec.P_FindNextHighestFloor(sec, PSetup.sectors_floorheight[sec]);
                    p[PL_WAIT] = 0;
                    p[PL_STATUS] = PSpec.up;
                    // NO MORE DAMAGE, IF APPLICABLE
                    PSetup.sectors_special[sec] = 0;

                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_stnmov);
                    break;

                case PSpec.raiseAndChange:
                    p[PL_SPEED] = PSpec.PLATSPEED / 2;
                    PSetup.sectors_floorpic[sec] = PSetup.sectors_floorpic[PSetup.sides_sector[PSetup.lines_sidenum[line * 2]]];
                    p[PL_HIGH] = PSetup.sectors_floorheight[sec] + amount * MFixed.FRACUNIT;
                    p[PL_WAIT] = 0;
                    p[PL_STATUS] = PSpec.up;

                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_stnmov);
                    break;

                case PSpec.downWaitUpStay:
                    p[PL_SPEED] = PSpec.PLATSPEED * 4;
                    p[PL_LOW] = PSpec.P_FindLowestFloorSurrounding(sec);

                    if (p[PL_LOW] > PSetup.sectors_floorheight[sec]) {
                        p[PL_LOW] = PSetup.sectors_floorheight[sec];
                    }

                    p[PL_HIGH] = PSetup.sectors_floorheight[sec];
                    p[PL_WAIT] = 35 * PSpec.PLATWAIT;
                    p[PL_STATUS] = PSpec.down;
                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_pstart);
                    break;

                case PSpec.blazeDWUS:
                    p[PL_SPEED] = PSpec.PLATSPEED * 8;
                    p[PL_LOW] = PSpec.P_FindLowestFloorSurrounding(sec);

                    if (p[PL_LOW] > PSetup.sectors_floorheight[sec]) {
                        p[PL_LOW] = PSetup.sectors_floorheight[sec];
                    }

                    p[PL_HIGH] = PSetup.sectors_floorheight[sec];
                    p[PL_WAIT] = 35 * PSpec.PLATWAIT;
                    p[PL_STATUS] = PSpec.down;
                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_pstart);
                    break;

                case PSpec.perpetualRaise:
                    p[PL_SPEED] = PSpec.PLATSPEED;
                    p[PL_LOW] = PSpec.P_FindLowestFloorSurrounding(sec);

                    if (p[PL_LOW] > PSetup.sectors_floorheight[sec]) {
                        p[PL_LOW] = PSetup.sectors_floorheight[sec];
                    }

                    p[PL_HIGH] = PSpec.P_FindHighestFloorSurrounding(sec);

                    if (p[PL_HIGH] < PSetup.sectors_floorheight[sec]) {
                        p[PL_HIGH] = PSetup.sectors_floorheight[sec];
                    }

                    p[PL_WAIT] = 35 * PSpec.PLATWAIT;
                    p[PL_STATUS] = MRandom.P_Random() & 1;

                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_pstart);
                    break;
            }
            P_AddActivePlat(plat);
        }
        return rtn;
    }

    function P_ActivateInStasis(tag as Number) as Void {
        for (var i = 0; i < PSpec.MAXPLATS; i++) {
            var plat = activeplats[i];
            if (plat != -1) {
                var p = PTick.thinkers_data[plat] as Array<Number>;
                if (p[PL_TAG] == tag && p[PL_STATUS] == PSpec.in_stasis) {
                    p[PL_STATUS] = p[PL_OLDSTATUS];
                    PTick.thinkers_function[plat] = PTick.TF_PLATRAISE;
                }
            }
        }
    }

    function EV_StopPlat(line as Number) as Void {
        var tag = PSetup.lines_tag[line];
        for (var j = 0; j < PSpec.MAXPLATS; j++) {
            var plat = activeplats[j];
            if (plat != -1) {
                var p = PTick.thinkers_data[plat] as Array<Number>;
                if (p[PL_STATUS] != PSpec.in_stasis && p[PL_TAG] == tag) {
                    p[PL_OLDSTATUS] = p[PL_STATUS];
                    p[PL_STATUS] = PSpec.in_stasis;
                    PTick.thinkers_function[plat] = PTick.TF_NULL;
                }
            }
        }
    }

    function P_AddActivePlat(plat as Number) as Void {
        for (var i = 0; i < PSpec.MAXPLATS; i++) {
            if (activeplats[i] == -1) {
                activeplats[i] = plat;
                return;
            }
        }
        ISystem.I_Error("P_AddActivePlat: no more plats!");
    }

    function P_RemoveActivePlat(plat as Number) as Void {
        for (var i = 0; i < PSpec.MAXPLATS; i++) {
            if (plat == activeplats[i]) {
                var p = PTick.thinkers_data[activeplats[i]] as Array<Number>;
                PSetup.sectors_specialdata[p[PL_SECTOR]] = -1;
                PTick.P_RemoveThinker(activeplats[i]);
                activeplats[i] = -1;

                return;
            }
        }
        ISystem.I_Error("P_RemoveActivePlat: can't find plat!");
    }
}
