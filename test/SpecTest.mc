// Expected values come from the original p_spec.c, p_doors.c, p_plats.c,
// p_floor.c, p_ceilng.c, p_lights.c and p_switch.c run on the same E1M1
// sectors, see test/spec_ref.c. Both sides start each case from a fresh
// map with no thinkers, the random index at 0 and P_ChangeSector never
// blocking anything.

import Toybox.Lang;
import Toybox.Test;

// E1M1 as P_SetupLevel leaves it, minus everything that was spawned: the
// things (their thinkers would use P_Random and P_ChangeSector would
// find them) and P_SpawnSpecials' lights, whose sector specials come
// back from the lump. That's what spec_ref.c's load() gives.
function loadSpecE1M1() as Void {
    initRender();
    if (Info.mobjinfo.size() == 0) {
        Info.Info_Init();
    }
    loadE1M1();
    PSetup.P_Init();

    PTick.P_InitThinkers(PSetup.numthings);
    PTick.leveltime = 0;
    MRandom.M_ClearRandom();
    for (var i = 0; i < PSetup.blocklinks.size(); i++) {
        PSetup.blocklinks[i] = -1;
    }
    var special = PSetup.W_LevelData(MapLumps.SECTORS_SPECIAL);
    for (var i = 0; i < PSetup.numsectors; i++) {
        PSetup.sectors_thinglist[i] = -1;
        PSetup.sectors_specialdata[i] = -1;
        PSetup.sectors_special[i] = special[i];
    }
    for (var i = 0; i < PSpec.MAXPLATS; i++) {
        PPlats.activeplats[i] = -1;
    }
    for (var i = 0; i < PSpec.MAXCEILINGS; i++) {
        PCeilng.activeceilings[i] = -1;
    }
    for (var i = 0; i < PSpec.MAXBUTTONS; i++) {
        PSwitch.P_ClearButton(i);
    }
    for (var i = 0; i < RData.numtextures; i++) {
        RData.texturetranslation[i] = i;
    }
    for (var i = 0; i < RData.numflats; i++) {
        RData.flattranslation[i] = i;
    }
    PSpec.numlinespecials = 0;
}

// One tic of P_Ticker without the player.
function specTic() as Void {
    PTick.P_RunThinkers();
    while (!PTick.P_RunThinkersStep(64)) {
    }
    PSpec.P_UpdateSpecials();
    PTick.leveltime++;
}

// Runs tics and folds the sector's heights into a checksum; [1] is the
// first tic the sector had no specialdata, -1 for never.
function specHashSector(s as Number, tics as Number) as Array {
    var h = 0l;
    var first = -1;
    for (var t = 0; t < tics; t++) {
        specTic();
        h += (t + 1).toLong() * ((PSetup.sectors_floorheight[s] >> 8) + 3l * (PSetup.sectors_ceilingheight[s] >> 8));
        if (first == -1 && PSetup.sectors_specialdata[s] == -1) {
            first = t + 1;
        }
    }
    return [h, first];
}

(:test)
function testSpecUtilities(logger as Test.Logger) as Boolean {
    loadSpecE1M1();

    // P_InitSwitchList / P_InitPicAnims: NUKAGE1-3 and SLADRIP1-3
    Test.assertEqual(PSwitch.numswitches, 19);
    Test.assertEqual(PSpec.lastanim, 2);
    Test.assertEqual(PSpec.anims_istexture[0], false);
    Test.assertEqual(PSpec.anims_picnum[0], 53);
    Test.assertEqual(PSpec.anims_basepic[0], 51);
    Test.assertEqual(PSpec.anims_numpics[0], 3);
    Test.assertEqual(PSpec.anims_istexture[1], true);
    Test.assertEqual(PSpec.anims_picnum[1], 63);
    Test.assertEqual(PSpec.anims_basepic[1], 61);
    Test.assertEqual(RData.R_TextureNumForName("sladrip1"), 61);
    Test.assertEqual(RData.R_CheckTextureNumForName("-"), 0);
    Test.assertEqual(RData.R_CheckTextureNumForName("NOPE"), -1);
    Test.assertEqual(RData.R_FlatNumForName("F_SKY1"), RData.skyflatnum);

    var rows = [
        // sector, lowestfloor, highestfloor, nexthighestfloor, lowestceiling, highestceiling, minlight
        [0, 0, 0, 0, 0, 14680064, 128],
        [4, 0, 0, 0, 4718592, 5767168, 160],
        [12, 0, 0, 0, 14680064, 14680064, 255],
        [24, -524288, 6815744, 524288, 7864320, 14680064, 128],
        [36, -524288, 6815744, 6815744, 12582912, 14680064, 128],
        [48, -8912896, -7864320, -7864320, -1572864, 3145728, 128],
        [59, -3145728, -3145728, 6291456, 6815744, 11534336, 128],
        [60, -3145728, -1572864, -1572864, 11534336, 11534336, 144],
        [70, -3145728, 6815744, 6815744, 6815744, 12058624, 128],
        [72, -1572864, -1572864, -1572864, 3145728, 6815744, 128],
        [84, -1572864, -1572864, -1572864, -1572864, 5767168, 255]
    ];
    var sum = 0l;
    var r = 0;
    for (var i = 0; i < PSetup.numsectors; i++) {
        var v = [
            PSpec.P_FindLowestFloorSurrounding(i),
            PSpec.P_FindHighestFloorSurrounding(i),
            PSpec.P_FindNextHighestFloor(i, PSetup.sectors_floorheight[i]),
            PSpec.P_FindLowestCeilingSurrounding(i),
            PSpec.P_FindHighestCeilingSurrounding(i),
            PSpec.P_FindMinSurroundingLight(i, PSetup.sectors_lightlevel[i])
        ];
        for (var k = 0; k < 6; k++) {
            sum += (i + 1).toLong() * (k + 1) * (v[k] >> 8);
        }
        if (r < rows.size() && rows[r][0] == i) {
            for (var k = 0; k < 6; k++) {
                Test.assertEqualMessage(v[k], rows[r][k + 1], "sector " + i + " function " + k);
            }
            r++;
        }
    }
    Test.assertEqual(r, rows.size());
    Test.assertEqual(sum, 917491712l);

    Test.assertEqual(PSpec.P_FindSectorFromLineTag(195, -1), 70);
    Test.assertEqual(PSpec.P_FindSectorFromLineTag(308, -1), 59);
    Test.assertEqual(PSpec.P_FindSectorFromLineTag(308, 59), -1);
    return true;
}

(:test)
function testVerticalDoor(logger as Test.Logger) as Boolean {
    loadSpecE1M1();

    // a monster opens line 151's door (sector 4), a player closes it
    // while it waits, then the monster reopens it on the way down
    var monster = PTick.P_AllocThinker();
    PMobj.mobjs_player[monster] = -1;
    var player = PTick.P_AllocThinker();
    PMobj.mobjs_player[player] = 0;

    var expect = [
        // tic, ceiling, direction (99: no door)
        [1, 131072, 1],
        [2, 262144, 1],
        [3, 393216, 1],
        [20, 2621440, 1],
        [40, 4456448, 0],
        [60, 4456448, 0],
        [80, 4325376, -1],
        [99, 1835008, -1],
        [100, 1966080, 1],
        [101, 2097152, 1],
        [120, 4456448, 0],
        [140, 4456448, 0],
        [160, 4456448, 0],
        [180, 4456448, 0],
        [200, 4456448, 0],
        [220, 4456448, 0],
        [240, 4456448, 0],
        [255, 4456448, 0],
        [260, 4456448, 0]
    ];
    var s = 4;
    var e = 0;
    PDoors.EV_VerticalDoor(151, monster);
    for (var t = 1; t <= 260; t++) {
        if (t == 20) {
            PDoors.EV_VerticalDoor(151, monster);   // ignored, still going up
        }
        if (t == 80) {
            PDoors.EV_VerticalDoor(151, player);    // close it now
        }
        if (t == 100) {
            PDoors.EV_VerticalDoor(151, monster);   // going down: back up
        }
        specTic();
        if (e < expect.size() && expect[e][0] == t) {
            var d = PSetup.sectors_specialdata[s];
            var dir = d == -1 ? 99 : (PTick.thinkers_data[d] as Array<Number>)[PDoors.VD_DIRECTION];
            Test.assertEqualMessage(PSetup.sectors_ceilingheight[s], expect[e][1], "door ceiling at tic " + t);
            Test.assertEqualMessage(dir, expect[e][2], "door direction at tic " + t);
            e++;
        }
    }
    Test.assertEqual(e, expect.size());
    return true;
}

(:test)
function testDoDoor(logger as Test.Logger) as Boolean {
    var expect = [
        // type, rtn, hash, tics till done, floor, ceiling
        [0, 1, 8505724928l, 152, 6815744, 6815744],
        [1, 1, 8557352960l, -1, 6815744, 6815744],
        [2, 1, 8557352960l, 41, 6815744, 6815744],
        [3, 1, 8294604800l, 1, 6815744, 6553600],
        [4, 1, 13468467200l, -1, 6815744, 12058624],
        [5, 1, 8505724928l, 152, 6815744, 6815744],
        [6, 1, 8294604800l, 1, 6815744, 6553600],
        [7, 1, 8541992960l, 11, 6815744, 6815744]
    ];
    for (var i = 0; i < expect.size(); i++) {
        var c = expect[i];
        loadSpecE1M1();
        Test.assertEqualMessage(PDoors.EV_DoDoor(195, c[0]), c[1], "EV_DoDoor rtn " + c[0]);
        var h = specHashSector(70, 400);
        Test.assertEqualMessage(h[0], c[2], "EV_DoDoor hash " + c[0]);
        Test.assertEqualMessage(h[1], c[3], "EV_DoDoor done " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_floorheight[70], c[4], "EV_DoDoor floor " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_ceilingheight[70], c[5], "EV_DoDoor ceiling " + c[0]);
    }
    return true;
}

(:test)
function testDoPlat(logger as Test.Logger) as Boolean {
    var expect = [
        // type, amount, rtn, hash, tics till done, floor, ceiling, floorpic, prndindex
        [0, 0, 1, 11095847424l, -1, -786432, 12058624, 10, 1],
        [1, 0, 1, 12958564352l, 183, 6815744, 12058624, 10, 0],
        [2, 24, 1, 13958857728l, 49, 8388608, 12058624, 12, 0],
        [3, 0, 1, 13468467200l, 1, 6815744, 12058624, 12, 0],
        [4, 0, 1, 13118259200l, 145, 6815744, 12058624, 10, 0]
    ];
    for (var i = 0; i < expect.size(); i++) {
        var c = expect[i];
        loadSpecE1M1();
        Test.assertEqualMessage(PPlats.EV_DoPlat(195, c[0], c[1]), c[2], "EV_DoPlat rtn " + c[0]);
        var h = specHashSector(70, 400);
        Test.assertEqualMessage(h[0], c[3], "EV_DoPlat hash " + c[0]);
        Test.assertEqualMessage(h[1], c[4], "EV_DoPlat done " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_floorheight[70], c[5], "EV_DoPlat floor " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_ceilingheight[70], c[6], "EV_DoPlat ceiling " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_floorpic[70], c[7], "EV_DoPlat floorpic " + c[0]);
        Test.assertEqualMessage(MRandom.prndindex, c[8], "EV_DoPlat prndindex " + c[0]);
    }

    // a perpetual plat stopped at 50 and restarted at 120
    loadSpecE1M1();
    PPlats.EV_DoPlat(195, PSpec.perpetualRaise, 0);
    var h = 0l;
    for (var t = 1; t <= 300; t++) {
        if (t == 50) {
            PPlats.EV_StopPlat(195);
        }
        if (t == 120) {
            PPlats.EV_DoPlat(195, PSpec.perpetualRaise, 0);
        }
        specTic();
        h += t.toLong() * (PSetup.sectors_floorheight[70] >> 8);
    }
    Test.assertEqual(h, 688217600l);
    Test.assertEqual(PSetup.sectors_floorheight[70], -1310720);
    return true;
}

(:test)
function testDoFloor(logger as Test.Logger) as Boolean {
    var expect = [
        // type, rtn, hash, tics till done, floor, ceiling, floorpic, special
        [0, 1, 30276003840l, 145, -3145728, 11534336, 10, 0],
        [1, 1, 30276003840l, 145, -3145728, 11534336, 10, 0],
        [2, 1, 30657786880l, 35, -2621440, 11534336, 10, 0],
        [3, 1, 39695645696l, 9, 6815744, 11534336, 10, 0],
        [4, 1, 39193190400l, 1, 6291456, 11534336, 10, 0],
        [5, 1, 43699559424l, 73, 11010048, 11534336, 10, 0],
        [6, 1, 30276003840l, 145, -3145728, 11534336, 53, 7],
        [7, 1, 40700032000l, 25, 7864320, 11534336, 10, 0],
        [8, 1, 40700032000l, 25, 7864320, 11534336, 12, 12],
        [9, 1, 39193190400l, 1, 6291456, 11534336, 10, 0],
        [10, 1, 39193190400l, 1, 6291456, 11534336, 10, 0],
        [12, 1, 65625104384l, 513, 39845888, 11534336, 10, 0]
    ];
    for (var i = 0; i < expect.size(); i++) {
        var c = expect[i];
        loadSpecE1M1();
        Test.assertEqualMessage(PFloor.EV_DoFloor(308, c[0]), c[1], "EV_DoFloor rtn " + c[0]);
        var h = specHashSector(59, 700);
        Test.assertEqualMessage(h[0], c[2], "EV_DoFloor hash " + c[0]);
        Test.assertEqualMessage(h[1], c[3], "EV_DoFloor done " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_floorheight[59], c[4], "EV_DoFloor floor " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_ceilingheight[59], c[5], "EV_DoFloor ceiling " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_floorpic[59], c[6], "EV_DoFloor floorpic " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_special[59], c[7], "EV_DoFloor special " + c[0]);
    }

    var stairs = [
        // type, hash, tics till done, floor, sectors still moving
        [0, 7304559616l, 33, 6815744, 2],
        [1, 7397365760l, 5, 7340032, 0]
    ];
    for (var i = 0; i < stairs.size(); i++) {
        var c = stairs[i];
        loadSpecE1M1();
        Test.assertEqual(PFloor.EV_BuildStairs(308, c[0]), 1);
        var h = specHashSector(59, 300);
        var moving = 0;
        for (var s = 0; s < PSetup.numsectors; s++) {
            if (PSetup.sectors_specialdata[s] != -1) {
                moving++;
            }
        }
        Test.assertEqualMessage(h[0], c[1], "EV_BuildStairs hash " + c[0]);
        Test.assertEqualMessage(h[1], c[2], "EV_BuildStairs done " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_floorheight[59], c[3], "EV_BuildStairs floor " + c[0]);
        Test.assertEqualMessage(moving, c[4], "EV_BuildStairs moving " + c[0]);
    }
    return true;
}

(:test)
function testDoCeiling(logger as Test.Logger) as Boolean {
    var expect = [
        // type, rtn, hash, tics till done, floor, ceiling
        [0, 1, 17789736960l, 81, 6291456, 6291456],
        [1, 1, 28801843200l, 1, 6291456, 11534336],
        [2, 1, 18879740928l, 73, 6291456, 6815744],
        [3, 1, 24033011712l, -1, 6291456, 10485760],
        [4, 1, 23932164096l, -1, 6291456, 10485760],
        [5, 1, 24033011712l, -1, 6291456, 10485760]
    ];
    for (var i = 0; i < expect.size(); i++) {
        var c = expect[i];
        loadSpecE1M1();
        Test.assertEqualMessage(PCeilng.EV_DoCeiling(308, c[0]), c[1], "EV_DoCeiling rtn " + c[0]);
        var h = specHashSector(59, 600);
        Test.assertEqualMessage(h[0], c[2], "EV_DoCeiling hash " + c[0]);
        Test.assertEqualMessage(h[1], c[3], "EV_DoCeiling done " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_floorheight[59], c[4], "EV_DoCeiling floor " + c[0]);
        Test.assertEqualMessage(PSetup.sectors_ceilingheight[59], c[5], "EV_DoCeiling ceiling " + c[0]);
    }

    // a crusher stopped at 40 and restarted at 90
    loadSpecE1M1();
    PCeilng.EV_DoCeiling(308, PSpec.crushAndRaise);
    var h = 0l;
    for (var t = 1; t <= 300; t++) {
        if (t == 40) {
            PCeilng.EV_CeilingCrushStop(308);
        }
        if (t == 90) {
            PCeilng.EV_DoCeiling(308, PSpec.crushAndRaise);
        }
        specTic();
        h += t.toLong() * (PSetup.sectors_ceilingheight[59] >> 8);
    }
    Test.assertEqual(h, 1551874304l);
    Test.assertEqual(PSetup.sectors_ceilingheight[59], 8847360);
    return true;
}

(:test)
function testSpawnSpecialsAndLights(logger as Test.Logger) as Boolean {
    loadSpecE1M1();
    DoomStat.totalsecret = 0;
    PSpec.P_SpawnSpecials();
    Test.assertEqual(DoomStat.totalsecret, 3);
    Test.assertEqual(PSpec.numlinespecials, 8);
    Test.assertEqual(MRandom.prndindex, 1);

    var expect = [
        // tic, sector 40 (flash), 44, 45 (glow), 72 (sync strobe)
        [1, 144, 247, 247, 128],
        [2, 144, 239, 239, 128],
        [25, 255, 207, 207, 128],
        [50, 255, 167, 167, 128],
        [75, 144, 135, 135, 128],
        [100, 255, 175, 175, 128],
        [125, 255, 215, 215, 128],
        [150, 255, 247, 247, 128],
        [175, 255, 207, 207, 128],
        [200, 255, 167, 167, 255]
    ];
    var ls = [40, 44, 45, 72];
    var light = PSetup.sectors_lightlevel;
    var h = 0l;
    var e = 0;
    for (var t = 1; t <= 200; t++) {
        specTic();
        for (var k = 0; k < 4; k++) {
            h += t.toLong() * (k + 1) * light[ls[k]];
        }
        if (e < expect.size() && expect[e][0] == t) {
            for (var k = 0; k < 4; k++) {
                Test.assertEqualMessage(light[ls[k]], expect[e][k + 1], "light " + ls[k] + " at tic " + t);
            }
            e++;
        }
    }
    Test.assertEqual(h, 35743825l);
    Test.assertEqual(MRandom.prndindex, 7);

    // NUKAGE1-3 and SLADRIP1-3 animate, the scrolling lines move along
    Test.assertEqual(RData.flattranslation[51], 51);
    Test.assertEqual(RData.flattranslation[52], 52);
    Test.assertEqual(RData.flattranslation[53], 53);
    Test.assertEqual(RData.texturetranslation[61], 62);
    Test.assertEqual(RData.texturetranslation[62], 63);
    Test.assertEqual(RData.texturetranslation[63], 61);
    Test.assertEqual(PSetup.sides_textureoffset[PSetup.lines_sidenums[352] & 0xffff], 13631488);

    // the light thinkers on their own, from random index 17
    loadSpecE1M1();
    MRandom.prndindex = 17;
    PLights.P_SpawnLightFlash(40);
    PLights.P_SpawnStrobeFlash(72, PSpec.FASTDARK, 0);
    PLights.P_SpawnFireFlicker(59);
    PLights.P_SpawnGlowingLight(13);
    light = PSetup.sectors_lightlevel;
    h = 0l;
    for (var t = 1; t <= 150; t++) {
        specTic();
        h += t.toLong() * (light[40] + 2 * light[72] + 3 * light[59] + 4 * light[13]);
    }
    Test.assertEqual(h, 22972220l);
    Test.assertEqual(MRandom.prndindex, 63);
    Test.assertEqual(light[40], 144);
    Test.assertEqual(light[72], 128);
    Test.assertEqual(light[59], 144);
    Test.assertEqual(light[13], 255);

    PLights.EV_TurnTagLightsOff(308);
    Test.assertEqual(light[59], 128);
    PLights.EV_LightTurnOn(308, 0);
    Test.assertEqual(light[59], 192);
    PLights.EV_StartLightStrobing(195);
    for (var t = 0; t < 40; t++) {
        specTic();
    }
    Test.assertEqual(light[70], 0);
    Test.assertEqual(MRandom.prndindex, 75);
    return true;
}

(:test)
function testSwitchTexture(logger as Test.Logger) as Boolean {
    loadSpecE1M1();
    // the exit switch, line 330: SW1EXIT (100) to SW2EXIT (119)
    var s = PSetup.lines_sidenums[330] & 0xffff;
    Test.assertEqual(s, 452);
    Test.assertEqual(PSetup.sides_midtexture[s], 100);

    // as a button it flips back after BUTTONTIME
    PSwitch.P_ChangeSwitchTexture(330, 1);
    Test.assertEqual(PSetup.sides_toptexture[s], 0);
    Test.assertEqual(PSetup.sides_midtexture[s], 119);
    Test.assertEqual(PSetup.sides_bottomtexture[s], 0);
    Test.assertEqual(PSetup.lines_special[330], 11);
    for (var t = 0; t < PSpec.BUTTONTIME - 1; t++) {
        PSpec.P_UpdateSpecials();
    }
    Test.assertEqual(PSetup.sides_midtexture[s], 119);
    PSpec.P_UpdateSpecials();
    Test.assertEqual(PSetup.sides_midtexture[s], 100);

    // as a switch it stays and the line is used up
    PSwitch.P_ChangeSwitchTexture(330, 0);
    Test.assertEqual(PSetup.sides_midtexture[s], 119);
    Test.assertEqual(PSetup.lines_special[330], 0);
    return true;
}

(:test)
function testSpawnSpecialsInSetup(logger as Test.Logger) as Boolean {
    // P_SetupLevel ends with P_SpawnSpecials: 3 secrets, 8 scrolling lines
    // and the E1M1 lights (1 flash, 2 glows, 1 strobe) on the thinker list
    initRender();
    if (Info.mobjinfo.size() == 0) {
        Info.Info_Init();
    }
    loadE1M1();
    Test.assertEqual(DoomStat.totalsecret, 3);
    Test.assertEqual(PSpec.numlinespecials, 8);
    Test.assertEqual(PSetup.sectors_special[40], 0);
    Test.assertEqual(PSetup.sectors_special[13], 7);
    var lights = 0;
    for (var t = PTick.thinkers_next[0]; t != 0; t = PTick.thinkers_next[t]) {
        var f = PTick.thinkers_function[t];
        if (f == PTick.TF_LIGHTFLASH || f == PTick.TF_GLOW || f == PTick.TF_STROBEFLASH) {
            lights++;
        }
    }
    Test.assertEqual(lights, 4);
    return true;
}
