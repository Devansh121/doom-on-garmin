// p_spec.c / p_spec.h
//
// Implements special effects:
// Texture animation, height or lighting changes
//  according to adjacent sectors, respective
//  utility functions, etc.
// Line Tag handling. Line and Sector triggers.
//
// sector_t* / line_t* arguments are sector and line numbers, NULL is -1.
// sector->lines[i] is PSetup.linebuffer[PSetup.sectors_lines[sec] + i],
// sector->specialdata is PSetup.sectors_specialdata[sec] (a thinker
// number). The specials themselves are PTick thinkers whose fields live
// in PTick.thinkers_data[t]; see the field constants in PDoors, PPlats,
// PFloor, PCeilng and PLights.

import Toybox.Lang;
import Toybox.System;

module PSpec {

    //
    // p_spec.h enums and constants, shared by the p_spec family and
    // its callers (p_enemy's A_BossDeath, p_switch, ...).
    //

    // at game start
    const MO_TELEPORTMAN = 14;

    // p_lights
    const GLOWSPEED = 8;
    const STROBEBRIGHT = 5;
    const FASTDARK = 15;
    const SLOWDARK = 35;

    // p_switch: bwhere_e
    const top = 0;
    const middle = 1;
    const bottom = 2;
    // max # of wall switches in a level
    const MAXSWITCHES = 50;
    // 4 players, 4 buttons each at once, max.
    const MAXBUTTONS = 16;
    // 1 second, in ticks.
    const BUTTONTIME = 35;

    // p_plats: plat_e
    const up = 0;
    const down = 1;
    const waiting = 2;
    const in_stasis = 3;
    // plattype_e
    const perpetualRaise = 0;
    const downWaitUpStay = 1;
    const raiseAndChange = 2;
    const raiseToNearestAndChange = 3;
    const blazeDWUS = 4;
    const PLATWAIT = 3;
    const PLATSPEED = MFixed.FRACUNIT;
    const MAXPLATS = 30;

    // p_doors: vldoor_e
    const normal = 0;
    const close30ThenOpen = 1;
    const close = 2;
    const open = 3;
    const raiseIn5Mins = 4;
    const blazeRaise = 5;
    const blazeOpen = 6;
    const blazeClose = 7;
    const VDOORSPEED = MFixed.FRACUNIT * 2;
    const VDOORWAIT = 150;

    // p_ceilng: ceiling_e
    const lowerToFloor = 0;
    const raiseToHighest = 1;
    const lowerAndCrush = 2;
    const crushAndRaise = 3;
    const fastCrushAndRaise = 4;
    const silentCrushAndRaise = 5;
    const CEILSPEED = MFixed.FRACUNIT;
    const CEILWAIT = 150;
    const MAXCEILINGS = 30;

    // p_floor: floor_e
    const lowerFloor = 0;            // lower floor to highest surrounding floor
    const lowerFloorToLowest = 1;    // lower floor to lowest surrounding floor
    const turboLower = 2;            // lower floor to highest surrounding floor VERY FAST
    const raiseFloor = 3;            // raise floor to lowest surrounding CEILING
    const raiseFloorToNearest = 4;   // raise floor to next highest surrounding floor
    const raiseToTexture = 5;        // raise floor to shortest height texture around it
    const lowerAndChange = 6;        // lower floor to lowest surrounding floor
                                     //  and change floorpic
    const raiseFloor24 = 7;
    const raiseFloor24AndChange = 8;
    const raiseFloorCrush = 9;
    const raiseFloorTurbo = 10;      // raise to next highest floor, turbo-speed
    const donutRaise = 11;
    const raiseFloor512 = 12;
    // stair_e
    const build8 = 0;   // slowly build by 8
    const turbo16 = 1;  // quickly build by 16
    // result_e
    const ok = 0;
    const crushed = 1;
    const pastdest = 2;
    const FLOORSPEED = MFixed.FRACUNIT;

    //
    // Animating textures and planes
    // There is another anim_t used in wi_stuff, unrelated.
    //
    // anim_t, one array per field, indexed by anim number.
    //
    const MAXANIMS = 32;

    var anims_istexture as Array<Boolean> = new [MAXANIMS] as Array<Boolean>;
    var anims_picnum as Array<Number> = new [MAXANIMS] as Array<Number>;
    var anims_basepic as Array<Number> = new [MAXANIMS] as Array<Number>;
    var anims_numpics as Array<Number> = new [MAXANIMS] as Array<Number>;
    var anims_speed as Array<Number> = new [MAXANIMS] as Array<Number>;
    // anims + lastanim: the number of anims in use
    var lastanim as Number = 0;

    //
    //      source animation definition
    //
    // animdef_t: istexture (if false, it is a flat), endname, startname,
    // speed. The C table ends with {-1}; here it's just its size.
    //
    // Floor/ceiling animation sequences,
    //  defined by first and last frame,
    //  i.e. the flat (64x64 tile) name to
    //  be used.
    // The full animation sequence is given
    //  using all the flats between the start
    //  and end entry, in the order found in
    //  the WAD file.
    //
    const animdefs = [
        [false, "NUKAGE3", "NUKAGE1", 8],
        [false, "FWATER4", "FWATER1", 8],
        [false, "SWATER4", "SWATER1", 8],
        [false, "LAVA4", "LAVA1", 8],
        [false, "BLOOD3", "BLOOD1", 8],

        // DOOM II flat animations.
        [false, "RROCK08", "RROCK05", 8],
        [false, "SLIME04", "SLIME01", 8],
        [false, "SLIME08", "SLIME05", 8],
        [false, "SLIME12", "SLIME09", 8],

        [true, "BLODGR4", "BLODGR1", 8],
        [true, "SLADRIP3", "SLADRIP1", 8],

        [true, "BLODRIP4", "BLODRIP1", 8],
        [true, "FIREWALL", "FIREWALA", 8],
        [true, "GSTFONT3", "GSTFONT1", 8],
        [true, "FIRELAVA", "FIRELAV3", 8],
        [true, "FIREMAG3", "FIREMAG1", 8],
        [true, "FIREBLU2", "FIREBLU1", 8],
        [true, "ROCKRED3", "ROCKRED1", 8],

        [true, "BFALL4", "BFALL1", 8],
        [true, "SFALL4", "SFALL1", 8],
        [true, "WFALL4", "WFALL1", 8],
        [true, "DBRAIN4", "DBRAIN1", 8]
    ];

    //
    //      Animating line specials
    //
    const MAXLINEANIMS = 64;

    //
    // P_InitPicAnims
    //
    function P_InitPicAnims() as Void {
        //	Init animation
        lastanim = 0;
        for (var i = 0; i < animdefs.size(); i++) {
            var def = animdefs[i] as Array;
            var istexture = def[0] as Boolean;
            var endname = def[1] as String;
            var startname = def[2] as String;
            if (istexture) {
                // different episode ?
                if (RData.R_CheckTextureNumForName(startname) == -1) {
                    continue;
                }

                anims_picnum[lastanim] = RData.R_TextureNumForName(endname);
                anims_basepic[lastanim] = RData.R_TextureNumForName(startname);
            } else {
                if (RData.W_CheckFlatNumForName(startname) == -1) {
                    continue;
                }

                anims_picnum[lastanim] = RData.R_FlatNumForName(endname);
                anims_basepic[lastanim] = RData.R_FlatNumForName(startname);
            }

            anims_istexture[lastanim] = istexture;
            anims_numpics[lastanim] = anims_picnum[lastanim] - anims_basepic[lastanim] + 1;

            if (anims_numpics[lastanim] < 2) {
                ISystem.I_Error("P_InitPicAnims: bad cycle from " + startname + " to " + endname);
            }

            anims_speed[lastanim] = def[3] as Number;
            lastanim++;
        }
    }

    //
    // UTILITIES
    //

    //
    // getSide()
    // Will return a side_t*
    //  given the number of the current sector,
    //  the line number, and the side (0/1) that you want.
    //
    function getSide(currentSector as Number, line as Number, side as Number) as Number {
        var l = PSetup.linebuffer[PSetup.sectors_lines[currentSector] + line];
        return PSetup.lines_sidenum[l * 2 + side];
    }

    //
    // getSector()
    // Will return a sector_t*
    //  given the number of the current sector,
    //  the line number and the side (0/1) that you want.
    //
    function getSector(currentSector as Number, line as Number, side as Number) as Number {
        var l = PSetup.linebuffer[PSetup.sectors_lines[currentSector] + line];
        return PSetup.sides_sector[PSetup.lines_sidenum[l * 2 + side]];
    }

    //
    // twoSided()
    // Given the sector number and the line number,
    //  it will tell you whether the line is two-sided or not.
    //
    function twoSided(sector as Number, line as Number) as Number {
        var l = PSetup.linebuffer[PSetup.sectors_lines[sector] + line];
        return PSetup.lines_flags[l] & DoomData.ML_TWOSIDED;
    }

    //
    // getNextSector()
    // Return sector_t * of sector next to current.
    // NULL if not two-sided line
    //
    function getNextSector(line as Number, sec as Number) as Number {
        if ((PSetup.lines_flags[line] & DoomData.ML_TWOSIDED) == 0) {
            return -1;
        }

        if (PSetup.lines_frontsector[line] == sec) {
            return PSetup.lines_backsector[line];
        }

        return PSetup.lines_frontsector[line];
    }

    //
    // P_FindLowestFloorSurrounding()
    // FIND LOWEST FLOOR HEIGHT IN SURROUNDING SECTORS
    //
    function P_FindLowestFloorSurrounding(sec as Number) as Number {
        var floorheight = PSetup.sectors_floorheight;
        var buffer = PSetup.linebuffer;
        var first = PSetup.sectors_lines[sec];
        var floor = floorheight[sec];

        for (var i = 0; i < PSetup.sectors_linecount[sec]; i++) {
            var check = buffer[first + i];
            var other = getNextSector(check, sec);

            if (other == -1) {
                continue;
            }

            if (floorheight[other] < floor) {
                floor = floorheight[other];
            }
        }
        return floor;
    }

    //
    // P_FindHighestFloorSurrounding()
    // FIND HIGHEST FLOOR HEIGHT IN SURROUNDING SECTORS
    //
    function P_FindHighestFloorSurrounding(sec as Number) as Number {
        var floorheight = PSetup.sectors_floorheight;
        var buffer = PSetup.linebuffer;
        var first = PSetup.sectors_lines[sec];
        var floor = -500 * MFixed.FRACUNIT;

        for (var i = 0; i < PSetup.sectors_linecount[sec]; i++) {
            var check = buffer[first + i];
            var other = getNextSector(check, sec);

            if (other == -1) {
                continue;
            }

            if (floorheight[other] > floor) {
                floor = floorheight[other];
            }
        }
        return floor;
    }

    //
    // P_FindNextHighestFloor
    // FIND NEXT HIGHEST FLOOR IN SURROUNDING SECTORS
    // Note: this should be doable w/o a fixed array.

    // 20 adjoining sectors max!
    const MAX_ADJOINING_SECTORS = 20;

    function P_FindNextHighestFloor(sec as Number, currentheight as Number) as Number {
        var floorheight = PSetup.sectors_floorheight;
        var buffer = PSetup.linebuffer;
        var first = PSetup.sectors_lines[sec];
        var height = currentheight;
        var heightlist = new [MAX_ADJOINING_SECTORS] as Array<Number>;
        var h = 0;

        for (var i = 0; i < PSetup.sectors_linecount[sec]; i++) {
            var check = buffer[first + i];
            var other = getNextSector(check, sec);

            if (other == -1) {
                continue;
            }

            if (floorheight[other] > height) {
                heightlist[h] = floorheight[other];
                h++;
            }

            // Check for overflow. Exit.
            if (h >= MAX_ADJOINING_SECTORS) {
                System.println("Sector with more than 20 adjoining sectors");
                break;
            }
        }

        // Find lowest height in list
        if (h == 0) {
            return currentheight;
        }

        var min = heightlist[0];

        // Range checking?
        for (var i = 1; i < h; i++) {
            if (heightlist[i] < min) {
                min = heightlist[i];
            }
        }

        return min;
    }

    //
    // FIND LOWEST CEILING IN THE SURROUNDING SECTORS
    //
    function P_FindLowestCeilingSurrounding(sec as Number) as Number {
        var ceilingheight = PSetup.sectors_ceilingheight;
        var buffer = PSetup.linebuffer;
        var first = PSetup.sectors_lines[sec];
        var height = DoomType.MAXINT;

        for (var i = 0; i < PSetup.sectors_linecount[sec]; i++) {
            var check = buffer[first + i];
            var other = getNextSector(check, sec);

            if (other == -1) {
                continue;
            }

            if (ceilingheight[other] < height) {
                height = ceilingheight[other];
            }
        }
        return height;
    }

    //
    // FIND HIGHEST CEILING IN THE SURROUNDING SECTORS
    //
    function P_FindHighestCeilingSurrounding(sec as Number) as Number {
        var ceilingheight = PSetup.sectors_ceilingheight;
        var buffer = PSetup.linebuffer;
        var first = PSetup.sectors_lines[sec];
        var height = 0;

        for (var i = 0; i < PSetup.sectors_linecount[sec]; i++) {
            var check = buffer[first + i];
            var other = getNextSector(check, sec);

            if (other == -1) {
                continue;
            }

            if (ceilingheight[other] > height) {
                height = ceilingheight[other];
            }
        }
        return height;
    }

    //
    // RETURN NEXT SECTOR # THAT LINE TAG REFERS TO
    //
    // Walks every sector (once per call); fine for the shareware maps.
    //
    function P_FindSectorFromLineTag(line as Number, start as Number) as Number {
        var tags = PSetup.sectors_tag;
        var tag = PSetup.lines_tag[line];
        var n = PSetup.numsectors;

        for (var i = start + 1; i < n; i++) {
            if (tags[i] == tag) {
                return i;
            }
        }

        return -1;
    }

    //
    // Find minimum light from an adjacent sector
    //
    function P_FindMinSurroundingLight(sector as Number, max as Number) as Number {
        var lightlevel = PSetup.sectors_lightlevel;
        var buffer = PSetup.linebuffer;
        var first = PSetup.sectors_lines[sector];
        var min = max;

        for (var i = 0; i < PSetup.sectors_linecount[sector]; i++) {
            var line = buffer[first + i];
            var check = getNextSector(line, sector);

            if (check == -1) {
                continue;
            }

            if (lightlevel[check] < min) {
                min = lightlevel[check];
            }
        }
        return min;
    }

    //
    // EVENTS
    // Events are operations triggered by using, crossing,
    // or shooting special lines, or by timed thinkers.
    //

    //
    // P_CrossSpecialLine - TRIGGER
    // Called every time a thing origin is about
    //  to cross a line with a non 0 special.
    //
    function P_CrossSpecialLine(linenum as Number, side as Number, thing as Number) as Void {
        var line = linenum;
        var specials = PSetup.lines_special;

        //	Triggers that other things can activate
        if (PMobj.mobjs_player[thing] == -1) {
            // Things that should NOT trigger specials...
            switch (PMobj.mobjs_type[thing]) {
                case Info.MT_ROCKET:
                case Info.MT_PLASMA:
                case Info.MT_BFG:
                case Info.MT_TROOPSHOT:
                case Info.MT_HEADSHOT:
                case Info.MT_BRUISERSHOT:
                    return;

                default:
                    break;
            }

            var ok = 0;
            switch (specials[line]) {
                case 39:  // TELEPORT TRIGGER
                case 97:  // TELEPORT RETRIGGER
                case 125: // TELEPORT MONSTERONLY TRIGGER
                case 126: // TELEPORT MONSTERONLY RETRIGGER
                case 4:   // RAISE DOOR
                case 10:  // PLAT DOWN-WAIT-UP-STAY TRIGGER
                case 88:  // PLAT DOWN-WAIT-UP-STAY RETRIGGER
                    ok = 1;
                    break;
            }
            if (ok == 0) {
                return;
            }
        }

        // Note: could use some const's here.
        switch (specials[line]) {
            // TRIGGERS.
            // All from here to RETRIGGERS.
            case 2:
                // Open Door
                PDoors.EV_DoDoor(line, open);
                specials[line] = 0;
                break;

            case 3:
                // Close Door
                PDoors.EV_DoDoor(line, close);
                specials[line] = 0;
                break;

            case 4:
                // Raise Door
                PDoors.EV_DoDoor(line, normal);
                specials[line] = 0;
                break;

            case 5:
                // Raise Floor
                PFloor.EV_DoFloor(line, raiseFloor);
                specials[line] = 0;
                break;

            case 6:
                // Fast Ceiling Crush & Raise
                PCeilng.EV_DoCeiling(line, fastCrushAndRaise);
                specials[line] = 0;
                break;

            case 8:
                // Build Stairs
                PFloor.EV_BuildStairs(line, build8);
                specials[line] = 0;
                break;

            case 10:
                // PlatDownWaitUp
                PPlats.EV_DoPlat(line, downWaitUpStay, 0);
                specials[line] = 0;
                break;

            case 12:
                // Light Turn On - brightest near
                PLights.EV_LightTurnOn(line, 0);
                specials[line] = 0;
                break;

            case 13:
                // Light Turn On 255
                PLights.EV_LightTurnOn(line, 255);
                specials[line] = 0;
                break;

            case 16:
                // Close Door 30
                PDoors.EV_DoDoor(line, close30ThenOpen);
                specials[line] = 0;
                break;

            case 17:
                // Start Light Strobing
                PLights.EV_StartLightStrobing(line);
                specials[line] = 0;
                break;

            case 19:
                // Lower Floor
                PFloor.EV_DoFloor(line, lowerFloor);
                specials[line] = 0;
                break;

            case 22:
                // Raise floor to nearest height and change texture
                PPlats.EV_DoPlat(line, raiseToNearestAndChange, 0);
                specials[line] = 0;
                break;

            case 25:
                // Ceiling Crush and Raise
                PCeilng.EV_DoCeiling(line, crushAndRaise);
                specials[line] = 0;
                break;

            case 30:
                // Raise floor to shortest texture height
                //  on either side of lines.
                PFloor.EV_DoFloor(line, raiseToTexture);
                specials[line] = 0;
                break;

            case 35:
                // Lights Very Dark
                PLights.EV_LightTurnOn(line, 35);
                specials[line] = 0;
                break;

            case 36:
                // Lower Floor (TURBO)
                PFloor.EV_DoFloor(line, turboLower);
                specials[line] = 0;
                break;

            case 37:
                // LowerAndChange
                PFloor.EV_DoFloor(line, lowerAndChange);
                specials[line] = 0;
                break;

            case 38:
                // Lower Floor To Lowest
                PFloor.EV_DoFloor(line, lowerFloorToLowest);
                specials[line] = 0;
                break;

            case 39:
                // TELEPORT!
                PTelept.EV_Teleport(line, side, thing);
                specials[line] = 0;
                break;

            case 40:
                // RaiseCeilingLowerFloor
                PCeilng.EV_DoCeiling(line, raiseToHighest);
                PFloor.EV_DoFloor(line, lowerFloorToLowest);
                specials[line] = 0;
                break;

            case 44:
                // Ceiling Crush
                PCeilng.EV_DoCeiling(line, lowerAndCrush);
                specials[line] = 0;
                break;

            case 52:
                // EXIT!
                GGame.G_ExitLevel();
                break;

            case 53:
                // Perpetual Platform Raise
                PPlats.EV_DoPlat(line, perpetualRaise, 0);
                specials[line] = 0;
                break;

            case 54:
                // Platform Stop
                PPlats.EV_StopPlat(line);
                specials[line] = 0;
                break;

            case 56:
                // Raise Floor Crush
                PFloor.EV_DoFloor(line, raiseFloorCrush);
                specials[line] = 0;
                break;

            case 57:
                // Ceiling Crush Stop
                PCeilng.EV_CeilingCrushStop(line);
                specials[line] = 0;
                break;

            case 58:
                // Raise Floor 24
                PFloor.EV_DoFloor(line, raiseFloor24);
                specials[line] = 0;
                break;

            case 59:
                // Raise Floor 24 And Change
                PFloor.EV_DoFloor(line, raiseFloor24AndChange);
                specials[line] = 0;
                break;

            case 104:
                // Turn lights off in sector(tag)
                PLights.EV_TurnTagLightsOff(line);
                specials[line] = 0;
                break;

            case 108:
                // Blazing Door Raise (faster than TURBO!)
                PDoors.EV_DoDoor(line, blazeRaise);
                specials[line] = 0;
                break;

            case 109:
                // Blazing Door Open (faster than TURBO!)
                PDoors.EV_DoDoor(line, blazeOpen);
                specials[line] = 0;
                break;

            case 100:
                // Build Stairs Turbo 16
                PFloor.EV_BuildStairs(line, turbo16);
                specials[line] = 0;
                break;

            case 110:
                // Blazing Door Close (faster than TURBO!)
                PDoors.EV_DoDoor(line, blazeClose);
                specials[line] = 0;
                break;

            case 119:
                // Raise floor to nearest surr. floor
                PFloor.EV_DoFloor(line, raiseFloorToNearest);
                specials[line] = 0;
                break;

            case 121:
                // Blazing PlatDownWaitUpStay
                PPlats.EV_DoPlat(line, blazeDWUS, 0);
                specials[line] = 0;
                break;

            case 124:
                // Secret EXIT
                GGame.G_SecretExitLevel();
                break;

            case 125:
                // TELEPORT MonsterONLY
                if (PMobj.mobjs_player[thing] == -1) {
                    PTelept.EV_Teleport(line, side, thing);
                    specials[line] = 0;
                }
                break;

            case 130:
                // Raise Floor Turbo
                PFloor.EV_DoFloor(line, raiseFloorTurbo);
                specials[line] = 0;
                break;

            case 141:
                // Silent Ceiling Crush & Raise
                PCeilng.EV_DoCeiling(line, silentCrushAndRaise);
                specials[line] = 0;
                break;

            // RETRIGGERS.  All from here till end.
            case 72:
                // Ceiling Crush
                PCeilng.EV_DoCeiling(line, lowerAndCrush);
                break;

            case 73:
                // Ceiling Crush and Raise
                PCeilng.EV_DoCeiling(line, crushAndRaise);
                break;

            case 74:
                // Ceiling Crush Stop
                PCeilng.EV_CeilingCrushStop(line);
                break;

            case 75:
                // Close Door
                PDoors.EV_DoDoor(line, close);
                break;

            case 76:
                // Close Door 30
                PDoors.EV_DoDoor(line, close30ThenOpen);
                break;

            case 77:
                // Fast Ceiling Crush & Raise
                PCeilng.EV_DoCeiling(line, fastCrushAndRaise);
                break;

            case 79:
                // Lights Very Dark
                PLights.EV_LightTurnOn(line, 35);
                break;

            case 80:
                // Light Turn On - brightest near
                PLights.EV_LightTurnOn(line, 0);
                break;

            case 81:
                // Light Turn On 255
                PLights.EV_LightTurnOn(line, 255);
                break;

            case 82:
                // Lower Floor To Lowest
                PFloor.EV_DoFloor(line, lowerFloorToLowest);
                break;

            case 83:
                // Lower Floor
                PFloor.EV_DoFloor(line, lowerFloor);
                break;

            case 84:
                // LowerAndChange
                PFloor.EV_DoFloor(line, lowerAndChange);
                break;

            case 86:
                // Open Door
                PDoors.EV_DoDoor(line, open);
                break;

            case 87:
                // Perpetual Platform Raise
                PPlats.EV_DoPlat(line, perpetualRaise, 0);
                break;

            case 88:
                // PlatDownWaitUp
                PPlats.EV_DoPlat(line, downWaitUpStay, 0);
                break;

            case 89:
                // Platform Stop
                PPlats.EV_StopPlat(line);
                break;

            case 90:
                // Raise Door
                PDoors.EV_DoDoor(line, normal);
                break;

            case 91:
                // Raise Floor
                PFloor.EV_DoFloor(line, raiseFloor);
                break;

            case 92:
                // Raise Floor 24
                PFloor.EV_DoFloor(line, raiseFloor24);
                break;

            case 93:
                // Raise Floor 24 And Change
                PFloor.EV_DoFloor(line, raiseFloor24AndChange);
                break;

            case 94:
                // Raise Floor Crush
                PFloor.EV_DoFloor(line, raiseFloorCrush);
                break;

            case 95:
                // Raise floor to nearest height
                // and change texture.
                PPlats.EV_DoPlat(line, raiseToNearestAndChange, 0);
                break;

            case 96:
                // Raise floor to shortest texture height
                // on either side of lines.
                PFloor.EV_DoFloor(line, raiseToTexture);
                break;

            case 97:
                // TELEPORT!
                PTelept.EV_Teleport(line, side, thing);
                break;

            case 98:
                // Lower Floor (TURBO)
                PFloor.EV_DoFloor(line, turboLower);
                break;

            case 105:
                // Blazing Door Raise (faster than TURBO!)
                PDoors.EV_DoDoor(line, blazeRaise);
                break;

            case 106:
                // Blazing Door Open (faster than TURBO!)
                PDoors.EV_DoDoor(line, blazeOpen);
                break;

            case 107:
                // Blazing Door Close (faster than TURBO!)
                PDoors.EV_DoDoor(line, blazeClose);
                break;

            case 120:
                // Blazing PlatDownWaitUpStay.
                PPlats.EV_DoPlat(line, blazeDWUS, 0);
                break;

            case 126:
                // TELEPORT MonsterONLY.
                if (PMobj.mobjs_player[thing] == -1) {
                    PTelept.EV_Teleport(line, side, thing);
                }
                break;

            case 128:
                // Raise To Nearest Floor
                PFloor.EV_DoFloor(line, raiseFloorToNearest);
                break;

            case 129:
                // Raise Floor Turbo
                PFloor.EV_DoFloor(line, raiseFloorTurbo);
                break;
        }
    }

    //
    // P_ShootSpecialLine - IMPACT SPECIALS
    // Called when a thing shoots a special line.
    //
    function P_ShootSpecialLine(thing as Number, line as Number) as Void {
        var special = PSetup.lines_special[line];

        //	Impacts that other things can activate.
        if (PMobj.mobjs_player[thing] == -1) {
            var ok = 0;
            switch (special) {
                case 46:
                    // OPEN DOOR IMPACT
                    ok = 1;
                    break;
            }
            if (ok == 0) {
                return;
            }
        }

        switch (special) {
            case 24:
                // RAISE FLOOR
                PFloor.EV_DoFloor(line, raiseFloor);
                PSwitch.P_ChangeSwitchTexture(line, 0);
                break;

            case 46:
                // OPEN DOOR
                PDoors.EV_DoDoor(line, open);
                PSwitch.P_ChangeSwitchTexture(line, 1);
                break;

            case 47:
                // RAISE FLOOR NEAR AND CHANGE
                PPlats.EV_DoPlat(line, raiseToNearestAndChange, 0);
                PSwitch.P_ChangeSwitchTexture(line, 0);
                break;
        }
    }

    //
    // P_PlayerInSpecialSector
    // Called every tic frame
    //  that the player origin is in a special sector
    //
    function P_PlayerInSpecialSector(player as Number) as Void {
        var mo = DPlayer.players_mo[player];
        var sector = PSetup.subsectors_sector[PMobj.mobjs_subsector[mo]];
        var ironfeet = DPlayer.players_powers[player * DoomDef.NUMPOWERS + DoomDef.pw_ironfeet];
        var leveltime = PTick.leveltime;

        // Falling, not all the way down yet?
        if (PMobj.mobjs_z[mo] != PSetup.sectors_floorheight[sector]) {
            return;
        }

        // Has hitten ground.
        switch (PSetup.sectors_special[sector]) {
            case 5:
                // HELLSLIME DAMAGE
                if (ironfeet == 0) {
                    if ((leveltime & 0x1f) == 0) {
                        PInter.P_DamageMobj(mo, -1, -1, 10);
                    }
                }
                break;

            case 7:
                // NUKAGE DAMAGE
                if (ironfeet == 0) {
                    if ((leveltime & 0x1f) == 0) {
                        PInter.P_DamageMobj(mo, -1, -1, 5);
                    }
                }
                break;

            case 16:
                // SUPER HELLSLIME DAMAGE
            case 4:
                // STROBE HURT
                if (ironfeet == 0 || (MRandom.P_Random() < 5)) {
                    if ((leveltime & 0x1f) == 0) {
                        PInter.P_DamageMobj(mo, -1, -1, 20);
                    }
                }
                break;

            case 9:
                // SECRET SECTOR
                DPlayer.players_secretcount[player]++;
                PSetup.sectors_special[sector] = 0;
                break;

            case 11:
                // EXIT SUPER DAMAGE! (for E1M8 finale)
                DPlayer.players_cheats[player] &= ~DPlayer.CF_GODMODE;

                if ((leveltime & 0x1f) == 0) {
                    PInter.P_DamageMobj(mo, -1, -1, 20);
                }

                if (DPlayer.players_health[player] <= 10) {
                    GGame.G_ExitLevel();
                }
                break;

            default:
                ISystem.I_Error("P_PlayerInSpecialSector: unknown special " + PSetup.sectors_special[sector]);
                break;
        }
    }

    //
    // P_UpdateSpecials
    // Animate planes, scroll walls, etc.
    //
    var levelTimer as Boolean = false;
    var levelTimeCount as Number = 0;

    function P_UpdateSpecials() as Void {
        var leveltime = PTick.leveltime;

        //	LEVEL TIMER
        if (levelTimer == true) {
            levelTimeCount--;
            if (levelTimeCount == 0) {
                GGame.G_ExitLevel();
            }
        }

        //	ANIMATE FLATS AND TEXTURES GLOBALLY
        var texturetranslation = RData.texturetranslation;
        var flattranslation = RData.flattranslation;
        for (var anim = 0; anim < lastanim; anim++) {
            var basepic = anims_basepic[anim];
            var numpics = anims_numpics[anim];
            var speed = anims_speed[anim];
            var istexture = anims_istexture[anim];
            for (var i = basepic; i < basepic + numpics; i++) {
                var pic = basepic + ((leveltime / speed + i) % numpics);
                if (istexture) {
                    texturetranslation[i] = pic;
                } else {
                    flattranslation[i] = pic;
                }
            }
        }

        //	ANIMATE LINE SPECIALS
        for (var i = 0; i < numlinespecials; i++) {
            var line = linespeciallist[i];
            switch (PSetup.lines_special[line]) {
                case 48:
                    // EFFECT FIRSTCOL SCROLL +
                    PSetup.sides_textureoffset[PSetup.lines_sidenum[line * 2]] += MFixed.FRACUNIT;
                    break;
            }
        }

        //	DO BUTTONS
        var btimer = PSwitch.buttonlist_btimer;
        for (var i = 0; i < MAXBUTTONS; i++) {
            if (btimer[i] != 0) {
                btimer[i]--;
                if (btimer[i] == 0) {
                    var side = PSetup.lines_sidenum[PSwitch.buttonlist_line[i] * 2];
                    switch (PSwitch.buttonlist_where[i]) {
                        case top:
                            PSetup.sides_toptexture[side] = PSwitch.buttonlist_btexture[i];
                            break;

                        case middle:
                            PSetup.sides_midtexture[side] = PSwitch.buttonlist_btexture[i];
                            break;

                        case bottom:
                            PSetup.sides_bottomtexture[side] = PSwitch.buttonlist_btexture[i];
                            break;
                    }
                    SSound.S_StartSound(PSwitch.buttonlist_soundorg[i], SSound.sfx_swtchn);
                    PSwitch.P_ClearButton(i);
                }
            }
        }
    }

    //
    // Special Stuff that can not be categorized
    //
    function EV_DoDonut(line as Number) as Number {
        var buffer = PSetup.linebuffer;
        var flags = PSetup.lines_flags;
        var back = PSetup.lines_backsector;
        var rtn = 0;

        // while ((secnum = P_FindSectorFromLineTag(line,secnum)) >= 0):
        // Monkey C has no assignment in expressions.
        for (var secnum = P_FindSectorFromLineTag(line, -1); secnum >= 0;
             secnum = P_FindSectorFromLineTag(line, secnum)) {
            var s1 = secnum;

            // ALREADY MOVING?  IF SO, KEEP GOING...
            if (PSetup.sectors_specialdata[s1] != -1) {
                continue;
            }

            rtn = 1;
            var s2 = getNextSector(buffer[PSetup.sectors_lines[s1]], s1);
            var s2lines = PSetup.sectors_lines[s2];
            for (var i = 0; i < PSetup.sectors_linecount[s2]; i++) {
                var l = buffer[s2lines + i];
                // (!s2->lines[i]->flags & ML_TWOSIDED) in the C code:
                // ! binds first, so this half is always false.
                if ((((flags[l] == 0) ? 1 : 0) & DoomData.ML_TWOSIDED) != 0
                    || (back[l] == s1)) {
                    continue;
                }
                var s3 = back[l];

                //	Spawn rising slime
                var floor = PTick.P_AllocThinker();
                var d = PFloor.newFloorMove();
                PTick.thinkers_data[floor] = d;
                PTick.P_AddThinker(floor);
                PSetup.sectors_specialdata[s2] = floor;
                PTick.thinkers_function[floor] = PTick.TF_MOVEFLOOR;
                d[PFloor.FM_TYPE] = donutRaise;
                d[PFloor.FM_CRUSH] = 0;
                d[PFloor.FM_DIRECTION] = 1;
                d[PFloor.FM_SECTOR] = s2;
                d[PFloor.FM_SPEED] = FLOORSPEED / 2;
                d[PFloor.FM_TEXTURE] = PSetup.sectors_floorpic[s3];
                d[PFloor.FM_NEWSPECIAL] = 0;
                d[PFloor.FM_FLOORDESTHEIGHT] = PSetup.sectors_floorheight[s3];

                //	Spawn lowering donut-hole
                floor = PTick.P_AllocThinker();
                d = PFloor.newFloorMove();
                PTick.thinkers_data[floor] = d;
                PTick.P_AddThinker(floor);
                PSetup.sectors_specialdata[s1] = floor;
                PTick.thinkers_function[floor] = PTick.TF_MOVEFLOOR;
                d[PFloor.FM_TYPE] = lowerFloor;
                d[PFloor.FM_CRUSH] = 0;
                d[PFloor.FM_DIRECTION] = -1;
                d[PFloor.FM_SECTOR] = s1;
                d[PFloor.FM_SPEED] = FLOORSPEED / 2;
                d[PFloor.FM_FLOORDESTHEIGHT] = PSetup.sectors_floorheight[s3];
                break;
            }
        }
        return rtn;
    }

    //
    // SPECIAL SPAWNING
    //

    //
    // P_SpawnSpecials
    // After the map has been loaded, scan for specials
    //  that spawn thinkers
    //
    var numlinespecials as Number = 0;
    var linespeciallist as Array<Number> = new [MAXLINEANIMS] as Array<Number>;

    // Parses command line parameters.
    //
    // Walks every sector and every line, so a big map may need it split
    // across callbacks; the shareware maps fit in one.
    function P_SpawnSpecials() as Void {
        // episode = 2 if there's a TEXTURE2 lump. It isn't used, and the
        // shareware IWAD has none.

        // See if -TIMER needs to be used.
        // (no command line on the watch, so no -avg or -timer)
        levelTimer = false;

        //	Init special SECTORs.
        var special = PSetup.sectors_special;
        for (var i = 0; i < PSetup.numsectors; i++) {
            var sector = i;
            if (special[sector] == 0) {
                continue;
            }

            switch (special[sector]) {
                case 1:
                    // FLICKERING LIGHTS
                    PLights.P_SpawnLightFlash(sector);
                    break;

                case 2:
                    // STROBE FAST
                    PLights.P_SpawnStrobeFlash(sector, FASTDARK, 0);
                    break;

                case 3:
                    // STROBE SLOW
                    PLights.P_SpawnStrobeFlash(sector, SLOWDARK, 0);
                    break;

                case 4:
                    // STROBE FAST/DEATH SLIME
                    PLights.P_SpawnStrobeFlash(sector, FASTDARK, 0);
                    special[sector] = 4;
                    break;

                case 8:
                    // GLOWING LIGHT
                    PLights.P_SpawnGlowingLight(sector);
                    break;
                case 9:
                    // SECRET SECTOR
                    DoomStat.totalsecret++;
                    break;

                case 10:
                    // DOOR CLOSE IN 30 SECONDS
                    PDoors.P_SpawnDoorCloseIn30(sector);
                    break;

                case 12:
                    // SYNC STROBE SLOW
                    PLights.P_SpawnStrobeFlash(sector, SLOWDARK, 1);
                    break;

                case 13:
                    // SYNC STROBE FAST
                    PLights.P_SpawnStrobeFlash(sector, FASTDARK, 1);
                    break;

                case 14:
                    // DOOR RAISE IN 5 MINUTES
                    PDoors.P_SpawnDoorRaiseIn5Mins(sector, i);
                    break;

                case 17:
                    PLights.P_SpawnFireFlicker(sector);
                    break;
            }
        }

        //	Init line EFFECTs
        var linespecial = PSetup.lines_special;
        numlinespecials = 0;
        for (var i = 0; i < PSetup.numlines; i++) {
            switch (linespecial[i]) {
                case 48:
                    // EFFECT FIRSTCOL SCROLL+
                    linespeciallist[numlinespecials] = i;
                    numlinespecials++;
                    break;
            }
        }

        //	Init other misc stuff
        for (var i = 0; i < MAXCEILINGS; i++) {
            PCeilng.activeceilings[i] = -1;
        }

        for (var i = 0; i < MAXPLATS; i++) {
            PPlats.activeplats[i] = -1;
        }

        for (var i = 0; i < MAXBUTTONS; i++) {
            PSwitch.P_ClearButton(i);
        }

        // UNUSED: no horizonal sliders.
        //	P_InitSlidingDoorFrames();
    }
}
