// p_spec.c / p_spec.h
//
// Implements special effects:
// Texture animation, height or lighting changes
//  according to adjacent sectors, respective
//  utility functions, etc.
// Line Tag handling. Line and Sector triggers.
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

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

    function P_InitPicAnims() as Void {
    }

    function P_SpawnSpecials() as Void {
    }

    function P_UpdateSpecials() as Void {
    }

    function P_ShootSpecialLine(thing as Number, line as Number) as Void {
    }

    function P_CrossSpecialLine(linenum as Number, side as Number, thing as Number) as Void {
    }

    function P_PlayerInSpecialSector(player as Number) as Void {
    }

    function twoSided(sector as Number, line as Number) as Number {
        return 0;
    }

    function getSector(currentSector as Number, line as Number, side as Number) as Number {
        return 0;
    }

    function getSide(currentSector as Number, line as Number, side as Number) as Number {
        return 0;
    }

    function P_FindLowestFloorSurrounding(sec as Number) as Number {
        return 0;
    }

    function P_FindHighestFloorSurrounding(sec as Number) as Number {
        return 0;
    }

    function P_FindNextHighestFloor(sec as Number, currentheight as Number) as Number {
        return 0;
    }

    function P_FindLowestCeilingSurrounding(sec as Number) as Number {
        return 0;
    }

    function P_FindHighestCeilingSurrounding(sec as Number) as Number {
        return 0;
    }

    function P_FindSectorFromLineTag(line as Number, start as Number) as Number {
        return 0;
    }

    function P_FindMinSurroundingLight(sector as Number, max as Number) as Number {
        return 0;
    }

    function getNextSector(line as Number, sec as Number) as Number {
        return 0;
    }

    function EV_DoDonut(line as Number) as Number {
        return 0;
    }
}
