// Expected values are read straight off info.c, sounds.h and p_mobj.h.

import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

function stateField(n as Number, field as Number) as Number {
    return Info.states[n * Info.ST_SIZE + field];
}

function mobjField(t as Number, field as Number) as Number {
    return Info.mobjinfo[t * Info.MI_SIZE + field];
}

(:test)
function testInfoCounts(logger as Test.Logger) as Boolean {
    // Drop any copy an earlier test loaded so the RAM figure is honest.
    Info.sprnames = [] as Array<String>;
    Info.states = [] as Array<Number>;
    Info.mobjinfo = [] as Array<Number>;
    var before = System.getSystemStats().usedMemory;
    Info.Info_Init();
    var after = System.getSystemStats().usedMemory;
    logger.debug("Info_Init uses " + (after - before) + " bytes");

    Test.assertEqual(Info.NUMSPRITES, 138);
    Test.assertEqual(Info.NUMSTATES, 967);
    Test.assertEqual(Info.NUMMOBJTYPES, 137);
    Test.assertEqual(Info.sprnames.size(), Info.NUMSPRITES);
    Test.assertEqual(Info.states.size(), Info.NUMSTATES * Info.ST_SIZE);
    Test.assertEqual(Info.mobjinfo.size(), Info.NUMMOBJTYPES * Info.MI_SIZE);

    Test.assertEqual(Info.sprnames[Info.SPR_TROO], "TROO");
    Test.assertEqual(Info.sprnames[Info.SPR_PLAY], "PLAY");
    Test.assertEqual(Info.sprnames[Info.SPR_TLP2], "TLP2");
    Test.assertEqual(Info.S_TECH2LAMP4, Info.NUMSTATES - 1);
    Test.assertEqual(Info.MT_MISC86, Info.NUMMOBJTYPES - 1);
    return true;
}

(:test)
function testInfoStates(logger as Test.Logger) as Boolean {
    Info.Info_Init();
    var cases = [
        // state, sprite, frame, tics, action, nextstate, misc1, misc2
        // {SPR_TROO,0,-1,{NULL},S_NULL,0,0}
        [Info.S_NULL, Info.SPR_TROO, 0, -1, 0, Info.S_NULL, 0, 0],
        // {SPR_SHTG,4,0,{A_Light0},S_NULL,0,0}
        [Info.S_LIGHTDONE, Info.SPR_SHTG, 4, 0, 1, Info.S_NULL, 0, 0],
        // {SPR_PISG,1,6,{A_FirePistol},S_PISTOL3,0,0}
        [Info.S_PISTOL2, Info.SPR_PISG, 1, 6, 7, Info.S_PISTOL3, 0, 0],
        // {SPR_PISF,32768,7,{A_Light1},S_LIGHTDONE,0,0}
        [Info.S_PISTOLFLASH, Info.SPR_PISF, 32768, 7, 8, Info.S_LIGHTDONE, 0, 0],
        // {SPR_PLAY,0,-1,{NULL},S_NULL,0,0}
        [Info.S_PLAY, Info.SPR_PLAY, 0, -1, 0, Info.S_NULL, 0, 0],
        // {SPR_PLAY,0,4,{NULL},S_PLAY_RUN2,0,0}
        [Info.S_PLAY_RUN1, Info.SPR_PLAY, 0, 4, 0, Info.S_PLAY_RUN2, 0, 0],
        // {SPR_TROO,0,10,{A_Look},S_TROO_STND2,0,0}
        [Info.S_TROO_STND, Info.SPR_TROO, 0, 10, 29, Info.S_TROO_STND2, 0, 0],
        // {SPR_BAR1,0,6,{NULL},S_BAR2,0,0}
        [Info.S_BAR1, Info.SPR_BAR1, 0, 6, 0, Info.S_BAR2, 0, 0]
    ];
    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        for (var f = 0; f < Info.ST_SIZE; f++) {
            Test.assertEqualMessage(stateField(c[0], f), c[1 + f], "state " + c[0] + " field " + f);
        }
    }
    // Spot-check the enum values against their row in states[] (line - 136).
    Test.assertEqual(Info.S_PLAY, 149);
    Test.assertEqual(Info.S_PISTOLFLASH, 17);
    return true;
}

(:test)
function testInfoMobjinfo(logger as Test.Logger) as Boolean {
    Info.Info_Init();
    var fracunit = MFixed.FRACUNIT;

    var t = Info.MT_PLAYER;
    Test.assertEqual(t, 0);
    Test.assertEqual(mobjField(t, Info.MI_DOOMEDNUM), -1);
    Test.assertEqual(mobjField(t, Info.MI_SPAWNSTATE), Info.S_PLAY);
    Test.assertEqual(mobjField(t, Info.MI_SPAWNHEALTH), 100);
    Test.assertEqual(mobjField(t, Info.MI_SEESTATE), Info.S_PLAY_RUN1);
    Test.assertEqual(mobjField(t, Info.MI_PAINSTATE), Info.S_PLAY_PAIN);
    Test.assertEqual(mobjField(t, Info.MI_PAINCHANCE), 255);
    Test.assertEqual(mobjField(t, Info.MI_PAINSOUND), 25); // sfx_plpain
    Test.assertEqual(mobjField(t, Info.MI_MISSILESTATE), Info.S_PLAY_ATK1);
    Test.assertEqual(mobjField(t, Info.MI_DEATHSOUND), 57); // sfx_pldeth
    Test.assertEqual(mobjField(t, Info.MI_RADIUS), 16 * fracunit);
    Test.assertEqual(mobjField(t, Info.MI_HEIGHT), 56 * fracunit);
    Test.assertEqual(mobjField(t, Info.MI_MASS), 100);
    // MF_SOLID|MF_SHOOTABLE|MF_DROPOFF|MF_PICKUP|MF_NOTDMATCH
    Test.assertEqual(mobjField(t, Info.MI_FLAGS), 2 | 4 | 0x400 | 0x800 | 0x2000000);
    Test.assertEqual(mobjField(t, Info.MI_RAISESTATE), Info.S_NULL);

    t = Info.MT_TROOP;
    Test.assertEqual(mobjField(t, Info.MI_DOOMEDNUM), 3001);
    Test.assertEqual(mobjField(t, Info.MI_SPAWNSTATE), Info.S_TROO_STND);
    Test.assertEqual(mobjField(t, Info.MI_SPAWNHEALTH), 60);
    Test.assertEqual(mobjField(t, Info.MI_SEESOUND), 39); // sfx_bgsit1
    Test.assertEqual(mobjField(t, Info.MI_MELEESTATE), Info.S_TROO_ATK1);
    Test.assertEqual(mobjField(t, Info.MI_SPEED), 8);
    Test.assertEqual(mobjField(t, Info.MI_RADIUS), 20 * fracunit);
    // MF_SOLID|MF_SHOOTABLE|MF_COUNTKILL
    Test.assertEqual(mobjField(t, Info.MI_FLAGS), 2 | 4 | 0x400000);
    Test.assertEqual(mobjField(t, Info.MI_RAISESTATE), Info.S_TROO_RAISE1);

    t = Info.MT_BARREL;
    Test.assertEqual(mobjField(t, Info.MI_DOOMEDNUM), 2035);
    Test.assertEqual(mobjField(t, Info.MI_SPAWNSTATE), Info.S_BAR1);
    Test.assertEqual(mobjField(t, Info.MI_DEATHSTATE), Info.S_BEXP);
    Test.assertEqual(mobjField(t, Info.MI_DEATHSOUND), 82); // sfx_barexp
    Test.assertEqual(mobjField(t, Info.MI_RADIUS), 10 * fracunit);
    Test.assertEqual(mobjField(t, Info.MI_HEIGHT), 42 * fracunit);
    // MF_SOLID|MF_SHOOTABLE|MF_NOBLOOD
    Test.assertEqual(mobjField(t, Info.MI_FLAGS), 2 | 4 | 0x80000);
    return true;
}
