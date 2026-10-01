// p_switch.c
//
// Switches, buttons. Two-state animation. Exits.

import Toybox.Lang;

module PSwitch {

    //
    // CHANGE THE TEXTURE OF A WALL SWITCH TO ITS OPPOSITE
    //
    // switchlist_t: name1, name2, episode. The C table ends with an
    // episode 0 entry, kept here.
    //
    const alphSwitchList = [
        // Doom shareware episode 1 switches
        ["SW1BRCOM", "SW2BRCOM", 1],
        ["SW1BRN1", "SW2BRN1", 1],
        ["SW1BRN2", "SW2BRN2", 1],
        ["SW1BRNGN", "SW2BRNGN", 1],
        ["SW1BROWN", "SW2BROWN", 1],
        ["SW1COMM", "SW2COMM", 1],
        ["SW1COMP", "SW2COMP", 1],
        ["SW1DIRT", "SW2DIRT", 1],
        ["SW1EXIT", "SW2EXIT", 1],
        ["SW1GRAY", "SW2GRAY", 1],
        ["SW1GRAY1", "SW2GRAY1", 1],
        ["SW1METAL", "SW2METAL", 1],
        ["SW1PIPE", "SW2PIPE", 1],
        ["SW1SLAD", "SW2SLAD", 1],
        ["SW1STARG", "SW2STARG", 1],
        ["SW1STON1", "SW2STON1", 1],
        ["SW1STON2", "SW2STON2", 1],
        ["SW1STONE", "SW2STONE", 1],
        ["SW1STRTN", "SW2STRTN", 1],

        // Doom registered episodes 2&3 switches
        ["SW1BLUE", "SW2BLUE", 2],
        ["SW1CMT", "SW2CMT", 2],
        ["SW1GARG", "SW2GARG", 2],
        ["SW1GSTON", "SW2GSTON", 2],
        ["SW1HOT", "SW2HOT", 2],
        ["SW1LION", "SW2LION", 2],
        ["SW1SATYR", "SW2SATYR", 2],
        ["SW1SKIN", "SW2SKIN", 2],
        ["SW1VINE", "SW2VINE", 2],
        ["SW1WOOD", "SW2WOOD", 2],

        // Doom II switches
        ["SW1PANEL", "SW2PANEL", 3],
        ["SW1ROCK", "SW2ROCK", 3],
        ["SW1MET2", "SW2MET2", 3],
        ["SW1WDMET", "SW2WDMET", 3],
        ["SW1BRIK", "SW2BRIK", 3],
        ["SW1MOD1", "SW2MOD1", 3],
        ["SW1ZIM", "SW2ZIM", 3],
        ["SW1STON6", "SW2STON6", 3],
        ["SW1TEK", "SW2TEK", 3],
        ["SW1MARB", "SW2MARB", 3],
        ["SW1SKULL", "SW2SKULL", 3],

        ["", "", 0]
    ];

    var switchlist as Array<Number> = new [PSpec.MAXSWITCHES * 2] as Array<Number>;
    var numswitches as Number = 0;

    // button_t buttonlist[MAXBUTTONS], one array per field.
    // line is a line number and soundorg a sound origin (see
    // SSound.S_SectorOrigin), -1 for NULL.
    var buttonlist_line as Array<Number> = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1] as Array<Number>;
    var buttonlist_where as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;   // bwhere_e
    var buttonlist_btexture as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    var buttonlist_btimer as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    var buttonlist_soundorg as Array<Number> = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1] as Array<Number>;

    // memset(&buttonlist[i],0,sizeof(button_t))
    function P_ClearButton(i as Number) as Void {
        buttonlist_line[i] = -1;
        buttonlist_where[i] = 0;
        buttonlist_btexture[i] = 0;
        buttonlist_btimer[i] = 0;
        buttonlist_soundorg[i] = -1;
    }

    //
    // P_InitSwitchList
    // Only called at game initialization.
    //
    function P_InitSwitchList() as Void {
        var episode = 1;

        if (DoomStat.gamemode == DoomDef.registered) {
            episode = 2;
        } else if (DoomStat.gamemode == DoomDef.commercial) {
            episode = 3;
        }

        var index = 0;
        for (var i = 0; i < PSpec.MAXSWITCHES; i++) {
            var sw = alphSwitchList[i] as Array;
            if ((sw[2] as Number) == 0) {
                numswitches = index / 2;
                switchlist[index] = -1;
                break;
            }

            if ((sw[2] as Number) <= episode) {
                switchlist[index] = RData.R_TextureNumForName(sw[0] as String);
                index++;
                switchlist[index] = RData.R_TextureNumForName(sw[1] as String);
                index++;
            }
        }
    }

    //
    // Start a button counting down till it turns off.
    //
    function P_StartButton(line as Number, w as Number, texture as Number, time as Number) as Void {
        // See if button is already pressed
        for (var i = 0; i < PSpec.MAXBUTTONS; i++) {
            if (buttonlist_btimer[i] != 0 && buttonlist_line[i] == line) {
                return;
            }
        }

        for (var i = 0; i < PSpec.MAXBUTTONS; i++) {
            if (buttonlist_btimer[i] == 0) {
                buttonlist_line[i] = line;
                buttonlist_where[i] = w;
                buttonlist_btexture[i] = texture;
                buttonlist_btimer[i] = time;
                buttonlist_soundorg[i] = SSound.S_SectorOrigin(PSetup.lines_frontsector[line]);
                return;
            }
        }

        ISystem.I_Error("P_StartButton: no button slots left!");
    }

    //
    // Function that changes wall texture.
    // Tell it if switch is ok to use again (1=yes, it's a button).
    //
    function P_ChangeSwitchTexture(line as Number, useAgain as Number) as Void {
        if (useAgain == 0) {
            PSetup.lines_special[line] = 0;
        }

        var side = PSetup.lines_sidenum[line * 2];
        var texTop = PSetup.sides_toptexture[side];
        var texMid = PSetup.sides_midtexture[side];
        var texBot = PSetup.sides_bottomtexture[side];

        var sound = SSound.sfx_swtchn;

        // EXIT SWITCH?
        if (PSetup.lines_special[line] == 11) {
            sound = SSound.sfx_swtchx;
        }

        for (var i = 0; i < numswitches * 2; i++) {
            // S_StartSound(buttonlist->soundorg, ...): the C code plays it
            // from the first button's origin, whichever line that was.
            if (switchlist[i] == texTop) {
                SSound.S_StartSound(buttonlist_soundorg[0], sound);
                PSetup.sides_toptexture[side] = switchlist[i ^ 1];

                if (useAgain != 0) {
                    P_StartButton(line, PSpec.top, switchlist[i], PSpec.BUTTONTIME);
                }

                return;
            } else {
                if (switchlist[i] == texMid) {
                    SSound.S_StartSound(buttonlist_soundorg[0], sound);
                    PSetup.sides_midtexture[side] = switchlist[i ^ 1];

                    if (useAgain != 0) {
                        P_StartButton(line, PSpec.middle, switchlist[i], PSpec.BUTTONTIME);
                    }

                    return;
                } else {
                    if (switchlist[i] == texBot) {
                        SSound.S_StartSound(buttonlist_soundorg[0], sound);
                        PSetup.sides_bottomtexture[side] = switchlist[i ^ 1];

                        if (useAgain != 0) {
                            P_StartButton(line, PSpec.bottom, switchlist[i], PSpec.BUTTONTIME);
                        }

                        return;
                    }
                }
            }
        }
    }

    //
    // P_UseSpecialLine
    // Called when a thing uses a special line.
    // Only the front sides of lines are usable.
    //
    function P_UseSpecialLine(thing as Number, line as Number, side as Number) as Boolean {
        // Err...
        // Use the back sides of VERY SPECIAL lines...
        if (side != 0) {
            switch (PSetup.lines_special[line]) {
                case 124:
                    // Sliding door open&close
                    // UNUSED?
                    break;

                default:
                    return false;
            }
        }

        // Switches that other things can activate.
        if (PMobj.mobjs_player[thing] == -1) {
            // never open secret doors
            if ((PSetup.lines_flags[line] & DoomData.ML_SECRET) != 0) {
                return false;
            }

            switch (PSetup.lines_special[line]) {
                case 1:   // MANUAL DOOR RAISE
                case 32:  // MANUAL BLUE
                case 33:  // MANUAL RED
                case 34:  // MANUAL YELLOW
                    break;

                default:
                    return false;
            }
        }

        // do something
        switch (PSetup.lines_special[line]) {
            // MANUALS
            case 1:   // Vertical Door
            case 26:  // Blue Door/Locked
            case 27:  // Yellow Door /Locked
            case 28:  // Red Door /Locked

            case 31:  // Manual door open
            case 32:  // Blue locked door open
            case 33:  // Red locked door open
            case 34:  // Yellow locked door open

            case 117: // Blazing door raise
            case 118: // Blazing door open
                PDoors.EV_VerticalDoor(line, thing);
                break;

            //UNUSED - Door Slide Open&Close
            // case 124:
            // EV_SlidingDoor (line, thing);
            // break;

            // SWITCHES
            case 7:
                // Build Stairs
                if (PFloor.EV_BuildStairs(line, PSpec.build8) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 9:
                // Change Donut
                if (PSpec.EV_DoDonut(line) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 11:
                // Exit level
                P_ChangeSwitchTexture(line, 0);
                GGame.G_ExitLevel();
                break;

            case 14:
                // Raise Floor 32 and change texture
                if (PPlats.EV_DoPlat(line, PSpec.raiseAndChange, 32) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 15:
                // Raise Floor 24 and change texture
                if (PPlats.EV_DoPlat(line, PSpec.raiseAndChange, 24) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 18:
                // Raise Floor to next highest floor
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloorToNearest) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 20:
                // Raise Plat next highest floor and change texture
                if (PPlats.EV_DoPlat(line, PSpec.raiseToNearestAndChange, 0) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 21:
                // PlatDownWaitUpStay
                if (PPlats.EV_DoPlat(line, PSpec.downWaitUpStay, 0) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 23:
                // Lower Floor to Lowest
                if (PFloor.EV_DoFloor(line, PSpec.lowerFloorToLowest) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 29:
                // Raise Door
                if (PDoors.EV_DoDoor(line, PSpec.normal) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 41:
                // Lower Ceiling to Floor
                if (PCeilng.EV_DoCeiling(line, PSpec.lowerToFloor) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 71:
                // Turbo Lower Floor
                if (PFloor.EV_DoFloor(line, PSpec.turboLower) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 49:
                // Ceiling Crush And Raise
                if (PCeilng.EV_DoCeiling(line, PSpec.crushAndRaise) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 50:
                // Close Door
                if (PDoors.EV_DoDoor(line, PSpec.close) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 51:
                // Secret EXIT
                P_ChangeSwitchTexture(line, 0);
                GGame.G_SecretExitLevel();
                break;

            case 55:
                // Raise Floor Crush
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloorCrush) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 101:
                // Raise Floor
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloor) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 102:
                // Lower Floor to Surrounding floor height
                if (PFloor.EV_DoFloor(line, PSpec.lowerFloor) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 103:
                // Open Door
                if (PDoors.EV_DoDoor(line, PSpec.open) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 111:
                // Blazing Door Raise (faster than TURBO!)
                if (PDoors.EV_DoDoor(line, PSpec.blazeRaise) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 112:
                // Blazing Door Open (faster than TURBO!)
                if (PDoors.EV_DoDoor(line, PSpec.blazeOpen) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 113:
                // Blazing Door Close (faster than TURBO!)
                if (PDoors.EV_DoDoor(line, PSpec.blazeClose) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 122:
                // Blazing PlatDownWaitUpStay
                if (PPlats.EV_DoPlat(line, PSpec.blazeDWUS, 0) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 127:
                // Build Stairs Turbo 16
                if (PFloor.EV_BuildStairs(line, PSpec.turbo16) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 131:
                // Raise Floor Turbo
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloorTurbo) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 133:
                // BlzOpenDoor BLUE
            case 135:
                // BlzOpenDoor RED
            case 137:
                // BlzOpenDoor YELLOW
                if (PDoors.EV_DoLockedDoor(line, PSpec.blazeOpen, thing) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            case 140:
                // Raise Floor 512
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloor512) != 0) {
                    P_ChangeSwitchTexture(line, 0);
                }
                break;

            // BUTTONS
            case 42:
                // Close Door
                if (PDoors.EV_DoDoor(line, PSpec.close) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 43:
                // Lower Ceiling to Floor
                if (PCeilng.EV_DoCeiling(line, PSpec.lowerToFloor) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 45:
                // Lower Floor to Surrounding floor height
                if (PFloor.EV_DoFloor(line, PSpec.lowerFloor) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 60:
                // Lower Floor to Lowest
                if (PFloor.EV_DoFloor(line, PSpec.lowerFloorToLowest) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 61:
                // Open Door
                if (PDoors.EV_DoDoor(line, PSpec.open) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 62:
                // PlatDownWaitUpStay
                if (PPlats.EV_DoPlat(line, PSpec.downWaitUpStay, 1) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 63:
                // Raise Door
                if (PDoors.EV_DoDoor(line, PSpec.normal) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 64:
                // Raise Floor to ceiling
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloor) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 66:
                // Raise Floor 24 and change texture
                if (PPlats.EV_DoPlat(line, PSpec.raiseAndChange, 24) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 67:
                // Raise Floor 32 and change texture
                if (PPlats.EV_DoPlat(line, PSpec.raiseAndChange, 32) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 65:
                // Raise Floor Crush
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloorCrush) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 68:
                // Raise Plat to next highest floor and change texture
                if (PPlats.EV_DoPlat(line, PSpec.raiseToNearestAndChange, 0) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 69:
                // Raise Floor to next highest floor
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloorToNearest) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 70:
                // Turbo Lower Floor
                if (PFloor.EV_DoFloor(line, PSpec.turboLower) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 114:
                // Blazing Door Raise (faster than TURBO!)
                if (PDoors.EV_DoDoor(line, PSpec.blazeRaise) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 115:
                // Blazing Door Open (faster than TURBO!)
                if (PDoors.EV_DoDoor(line, PSpec.blazeOpen) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 116:
                // Blazing Door Close (faster than TURBO!)
                if (PDoors.EV_DoDoor(line, PSpec.blazeClose) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 123:
                // Blazing PlatDownWaitUpStay
                if (PPlats.EV_DoPlat(line, PSpec.blazeDWUS, 0) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 132:
                // Raise Floor Turbo
                if (PFloor.EV_DoFloor(line, PSpec.raiseFloorTurbo) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 99:
                // BlzOpenDoor BLUE
            case 134:
                // BlzOpenDoor RED
            case 136:
                // BlzOpenDoor YELLOW
                if (PDoors.EV_DoLockedDoor(line, PSpec.blazeOpen, thing) != 0) {
                    P_ChangeSwitchTexture(line, 1);
                }
                break;

            case 138:
                // Light Turn On
                PLights.EV_LightTurnOn(line, 255);
                P_ChangeSwitchTexture(line, 1);
                break;

            case 139:
                // Light Turn Off
                PLights.EV_LightTurnOn(line, 35);
                P_ChangeSwitchTexture(line, 1);
                break;
        }

        return true;
    }
}
