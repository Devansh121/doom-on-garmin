// p_doors.c
//
// Door animation code (opening/closing)
//
// A vldoor_t is a PTick thinker (TF_VERTICALDOOR) whose fields are
// PTick.thinkers_data[door][VD_*]. The fields keep the struct's order, so
// code that treats another special's thinker as a door (EV_VerticalDoor
// on a sector whose specialdata is a plat, say) touches the same field
// it would in the C code.
//
// The sliding door code (EV_SlidingDoor, P_InitSlidingDoorFrames) is
// #if 0'd in the C source and isn't ported.

import Toybox.Lang;

(:extendedCode)
module PDoors {

    // vldoor_t fields
    const VD_TYPE = 0;          // vldoor_e
    const VD_SECTOR = 1;        // sector_t*
    const VD_TOPHEIGHT = 2;
    const VD_SPEED = 3;
    // 1 = up, 0 = waiting at top, -1 = down
    const VD_DIRECTION = 4;
    // tics to wait at the top
    const VD_TOPWAIT = 5;
    // (keep in case a door going down is reset)
    // when it reaches 0, start going down
    const VD_TOPCOUNTDOWN = 6;
    const VD_SIZE = 7;

    // d_englsh.h
    const PD_BLUEO = "You need a blue key to activate this object";
    const PD_REDO = "You need a red key to activate this object";
    const PD_YELLOWO = "You need a yellow key to activate this object";
    const PD_BLUEK = "You need a blue key to open this door";
    const PD_REDK = "You need a red key to open this door";
    const PD_YELLOWK = "You need a yellow key to open this door";

    // door = Z_Malloc (sizeof(*door), PU_LEVSPEC, 0);
    // P_AddThinker (&door->thinker);
    // sec->specialdata = door;
    // door->thinker.function.acp1 = (actionf_p1) T_VerticalDoor;
    // The fields start at 0 rather than whatever the zone had in it.
    function newDoor(sec as Number) as Number {
        var door = PTick.P_AllocThinker();
        PTick.thinkers_data[door] = [0, 0, 0, 0, 0, 0, 0] as Array<Number>;
        PTick.P_AddThinker(door);
        PSetup.sectors_specialdata[sec] = door;
        PTick.thinkers_function[door] = PTick.TF_VERTICALDOOR;
        return door;
    }

    //
    // VERTICAL DOORS
    //

    //
    // T_VerticalDoor
    //
    function T_VerticalDoor(door as Number) as Void {
        var d = PTick.thinkers_data[door] as Array<Number>;
        var sector = d[VD_SECTOR];
        var res;

        switch (d[VD_DIRECTION]) {
            case 0:
                // WAITING
                d[VD_TOPCOUNTDOWN]--;
                if (d[VD_TOPCOUNTDOWN] == 0) {
                    switch (d[VD_TYPE]) {
                        case PSpec.blazeRaise:
                            d[VD_DIRECTION] = -1; // time to go back down
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_bdcls);
                            break;

                        case PSpec.normal:
                            d[VD_DIRECTION] = -1; // time to go back down
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_dorcls);
                            break;

                        case PSpec.close30ThenOpen:
                            d[VD_DIRECTION] = 1;
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_doropn);
                            break;

                        default:
                            break;
                    }
                }
                break;

            case 2:
                //  INITIAL WAIT
                d[VD_TOPCOUNTDOWN]--;
                if (d[VD_TOPCOUNTDOWN] == 0) {
                    switch (d[VD_TYPE]) {
                        case PSpec.raiseIn5Mins:
                            d[VD_DIRECTION] = 1;
                            d[VD_TYPE] = PSpec.normal;
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_doropn);
                            break;

                        default:
                            break;
                    }
                }
                break;

            case -1:
                // DOWN
                res = PFloor.T_MovePlane(sector,
                                         d[VD_SPEED],
                                         PSetup.sectors_floorheight[sector],
                                         false, 1, d[VD_DIRECTION]);
                if (res == PSpec.pastdest) {
                    switch (d[VD_TYPE]) {
                        case PSpec.blazeRaise:
                        case PSpec.blazeClose:
                            PSetup.sectors_specialdata[sector] = -1;
                            PTick.P_RemoveThinker(door);  // unlink and free
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_bdcls);
                            break;

                        case PSpec.normal:
                        case PSpec.close:
                            PSetup.sectors_specialdata[sector] = -1;
                            PTick.P_RemoveThinker(door);  // unlink and free
                            break;

                        case PSpec.close30ThenOpen:
                            d[VD_DIRECTION] = 0;
                            d[VD_TOPCOUNTDOWN] = 35 * 30;
                            break;

                        default:
                            break;
                    }
                } else if (res == PSpec.crushed) {
                    switch (d[VD_TYPE]) {
                        case PSpec.blazeClose:
                        case PSpec.close:  // DO NOT GO BACK UP!
                            break;

                        default:
                            d[VD_DIRECTION] = 1;
                            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_doropn);
                            break;
                    }
                }
                break;

            case 1:
                // UP
                res = PFloor.T_MovePlane(sector,
                                         d[VD_SPEED],
                                         d[VD_TOPHEIGHT],
                                         false, 1, d[VD_DIRECTION]);

                if (res == PSpec.pastdest) {
                    switch (d[VD_TYPE]) {
                        case PSpec.blazeRaise:
                        case PSpec.normal:
                            d[VD_DIRECTION] = 0; // wait at top
                            d[VD_TOPCOUNTDOWN] = d[VD_TOPWAIT];
                            break;

                        case PSpec.close30ThenOpen:
                        case PSpec.blazeOpen:
                        case PSpec.open:
                            PSetup.sectors_specialdata[sector] = -1;
                            PTick.P_RemoveThinker(door);  // unlink and free
                            break;

                        default:
                            break;
                    }
                }
                break;
        }
    }

    //
    // EV_DoLockedDoor
    // Move a locked door up/down
    //
    function EV_DoLockedDoor(line as Number, type as Number, thing as Number) as Number {
        var p = PMobj.mobjs_player[thing];

        if (p == -1) {
            return 0;
        }

        var cards = DPlayer.players_cards;
        var c = p * DoomDef.NUMCARDS;

        switch (PSetup.lines_special[line]) {
            case 99:  // Blue Lock
            case 133:
                if (p == -1) {
                    return 0;
                }
                if (cards[c + DoomDef.it_bluecard] == 0 && cards[c + DoomDef.it_blueskull] == 0) {
                    DPlayer.players_message[p] = PD_BLUEO;
                    SSound.S_StartSound(-1, SSound.sfx_oof);
                    return 0;
                }
                break;

            case 134: // Red Lock
            case 135:
                if (p == -1) {
                    return 0;
                }
                if (cards[c + DoomDef.it_redcard] == 0 && cards[c + DoomDef.it_redskull] == 0) {
                    DPlayer.players_message[p] = PD_REDO;
                    SSound.S_StartSound(-1, SSound.sfx_oof);
                    return 0;
                }
                break;

            case 136: // Yellow Lock
            case 137:
                if (p == -1) {
                    return 0;
                }
                if (cards[c + DoomDef.it_yellowcard] == 0
                    && cards[c + DoomDef.it_yellowskull] == 0) {
                    DPlayer.players_message[p] = PD_YELLOWO;
                    SSound.S_StartSound(-1, SSound.sfx_oof);
                    return 0;
                }
                break;
        }

        return EV_DoDoor(line, type);
    }

    function EV_DoDoor(line as Number, type as Number) as Number {
        var rtn = 0;

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
            var door = newDoor(sec);
            var d = PTick.thinkers_data[door] as Array<Number>;

            d[VD_SECTOR] = sec;
            d[VD_TYPE] = type;
            d[VD_TOPWAIT] = PSpec.VDOORWAIT;
            d[VD_SPEED] = PSpec.VDOORSPEED;

            switch (type) {
                case PSpec.blazeClose:
                    d[VD_TOPHEIGHT] = PSpec.P_FindLowestCeilingSurrounding(sec);
                    d[VD_TOPHEIGHT] -= 4 * MFixed.FRACUNIT;
                    d[VD_DIRECTION] = -1;
                    d[VD_SPEED] = PSpec.VDOORSPEED * 4;
                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_bdcls);
                    break;

                case PSpec.close:
                    d[VD_TOPHEIGHT] = PSpec.P_FindLowestCeilingSurrounding(sec);
                    d[VD_TOPHEIGHT] -= 4 * MFixed.FRACUNIT;
                    d[VD_DIRECTION] = -1;
                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_dorcls);
                    break;

                case PSpec.close30ThenOpen:
                    d[VD_TOPHEIGHT] = PSetup.sectors_ceilingheight[sec];
                    d[VD_DIRECTION] = -1;
                    SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_dorcls);
                    break;

                case PSpec.blazeRaise:
                case PSpec.blazeOpen:
                    d[VD_DIRECTION] = 1;
                    d[VD_TOPHEIGHT] = PSpec.P_FindLowestCeilingSurrounding(sec);
                    d[VD_TOPHEIGHT] -= 4 * MFixed.FRACUNIT;
                    d[VD_SPEED] = PSpec.VDOORSPEED * 4;
                    if (d[VD_TOPHEIGHT] != PSetup.sectors_ceilingheight[sec]) {
                        SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_bdopn);
                    }
                    break;

                case PSpec.normal:
                case PSpec.open:
                    d[VD_DIRECTION] = 1;
                    d[VD_TOPHEIGHT] = PSpec.P_FindLowestCeilingSurrounding(sec);
                    d[VD_TOPHEIGHT] -= 4 * MFixed.FRACUNIT;
                    if (d[VD_TOPHEIGHT] != PSetup.sectors_ceilingheight[sec]) {
                        SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_doropn);
                    }
                    break;

                default:
                    break;
            }
        }
        return rtn;
    }

    //
    // EV_VerticalDoor : open a door manually, no tag value
    //
    function EV_VerticalDoor(line as Number, thing as Number) as Void {
        var side = 0;  // only front sides can be used

        //	Check for locks
        var player = PMobj.mobjs_player[thing];
        var cards = DPlayer.players_cards;
        var c = player * DoomDef.NUMCARDS;

        switch (PSetup.lines_special[line]) {
            case 26: // Blue Lock
            case 32:
                if (player == -1) {
                    return;
                }

                if (cards[c + DoomDef.it_bluecard] == 0 && cards[c + DoomDef.it_blueskull] == 0) {
                    DPlayer.players_message[player] = PD_BLUEK;
                    SSound.S_StartSound(-1, SSound.sfx_oof);
                    return;
                }
                break;

            case 27: // Yellow Lock
            case 34:
                if (player == -1) {
                    return;
                }

                if (cards[c + DoomDef.it_yellowcard] == 0
                    && cards[c + DoomDef.it_yellowskull] == 0) {
                    DPlayer.players_message[player] = PD_YELLOWK;
                    SSound.S_StartSound(-1, SSound.sfx_oof);
                    return;
                }
                break;

            case 28: // Red Lock
            case 33:
                if (player == -1) {
                    return;
                }

                if (cards[c + DoomDef.it_redcard] == 0 && cards[c + DoomDef.it_redskull] == 0) {
                    DPlayer.players_message[player] = PD_REDK;
                    SSound.S_StartSound(-1, SSound.sfx_oof);
                    return;
                }
                break;
        }

        // if the sector has an active thinker, use it
        var sec = PSetup.sides_sector[PSetup.lines_sidenum[line * 2 + (side ^ 1)]];

        if (PSetup.sectors_specialdata[sec] != -1) {
            // door = sec->specialdata, whatever kind of special it is
            var d = PTick.thinkers_data[PSetup.sectors_specialdata[sec]] as Array<Number>;
            switch (PSetup.lines_special[line]) {
                case 1: // ONLY FOR "RAISE" DOORS, NOT "OPEN"s
                case 26:
                case 27:
                case 28:
                case 117:
                    if (d[VD_DIRECTION] == -1) {
                        d[VD_DIRECTION] = 1;  // go back up
                    } else {
                        if (player == -1) {
                            return;  // JDC: bad guys never close doors
                        }

                        d[VD_DIRECTION] = -1;  // start going down immediately
                    }
                    return;
            }
        }

        // for proper sound
        switch (PSetup.lines_special[line]) {
            case 117: // BLAZING DOOR RAISE
            case 118: // BLAZING DOOR OPEN
                SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_bdopn);
                break;

            case 1:   // NORMAL DOOR SOUND
            case 31:
                SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_doropn);
                break;

            default:  // LOCKED DOOR SOUND
                SSound.S_StartSound(SSound.S_SectorOrigin(sec), SSound.sfx_doropn);
                break;
        }

        // new door thinker
        var door = newDoor(sec);
        var d = PTick.thinkers_data[door] as Array<Number>;
        d[VD_SECTOR] = sec;
        d[VD_DIRECTION] = 1;
        d[VD_SPEED] = PSpec.VDOORSPEED;
        d[VD_TOPWAIT] = PSpec.VDOORWAIT;

        switch (PSetup.lines_special[line]) {
            case 1:
            case 26:
            case 27:
            case 28:
                d[VD_TYPE] = PSpec.normal;
                break;

            case 31:
            case 32:
            case 33:
            case 34:
                d[VD_TYPE] = PSpec.open;
                PSetup.lines_special[line] = 0;
                break;

            case 117: // blazing door raise
                d[VD_TYPE] = PSpec.blazeRaise;
                d[VD_SPEED] = PSpec.VDOORSPEED * 4;
                break;
            case 118: // blazing door open
                d[VD_TYPE] = PSpec.blazeOpen;
                PSetup.lines_special[line] = 0;
                d[VD_SPEED] = PSpec.VDOORSPEED * 4;
                break;
        }

        // find the top and bottom of the movement range
        d[VD_TOPHEIGHT] = PSpec.P_FindLowestCeilingSurrounding(sec);
        d[VD_TOPHEIGHT] -= 4 * MFixed.FRACUNIT;
    }

    //
    // Spawn a door that closes after 30 seconds
    //
    function P_SpawnDoorCloseIn30(sec as Number) as Void {
        var door = newDoor(sec);
        var d = PTick.thinkers_data[door] as Array<Number>;

        PSetup.sectors_special[sec] = 0;

        d[VD_SECTOR] = sec;
        d[VD_DIRECTION] = 0;
        d[VD_TYPE] = PSpec.normal;
        d[VD_SPEED] = PSpec.VDOORSPEED;
        d[VD_TOPCOUNTDOWN] = 30 * 35;
    }

    //
    // Spawn a door that opens after 5 minutes
    //
    function P_SpawnDoorRaiseIn5Mins(sec as Number, secnum as Number) as Void {
        var door = newDoor(sec);
        var d = PTick.thinkers_data[door] as Array<Number>;

        PSetup.sectors_special[sec] = 0;

        d[VD_SECTOR] = sec;
        d[VD_DIRECTION] = 2;
        d[VD_TYPE] = PSpec.raiseIn5Mins;
        d[VD_SPEED] = PSpec.VDOORSPEED;
        d[VD_TOPHEIGHT] = PSpec.P_FindLowestCeilingSurrounding(sec);
        d[VD_TOPHEIGHT] -= 4 * MFixed.FRACUNIT;
        d[VD_TOPWAIT] = PSpec.VDOORWAIT;
        d[VD_TOPCOUNTDOWN] = 5 * 60 * 35;
    }
}
