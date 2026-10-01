// Expected values come from the original p_enemy.c functions with
// P_TryMove and P_CheckSight stubbed to the same fixed rules as here,
// see test/enemy_ref.c, and P_RecursiveSound on E1M1, see
// test/sound_ref.c.

import Toybox.Lang;
import Toybox.Test;

module EnemyTestRules {

    // Same rule as P_TryMove in test/enemy_ref.c: accept a move when a
    // hash of the destination's map units is < 3 (of 8), and move there.
    function tryMove(thing as Number, x as Number, y as Number) as Boolean {
        if ((((x >> 16) * 7 + (y >> 16) * 13) & 7) < 3) {
            PMobj.mobjs_x[thing] = x;
            PMobj.mobjs_y[thing] = y;
            return true;
        }
        return false;
    }

    function sightTrue(t1 as Number, t2 as Number) as Boolean {
        return true;
    }

    function sightFalse(t1 as Number, t2 as Number) as Boolean {
        return false;
    }
}

function initEnemy() as Void {
    initRender();
    Info.Info_Init();
    loadE1M1();
    PEnemy.testTryMove = new Lang.Method(EnemyTestRules, :tryMove);
    PEnemy.testCheckSight = new Lang.Method(EnemyTestRules, :sightTrue);
}

function doneEnemy() as Void {
    PEnemy.testTryMove = null;
    PEnemy.testCheckSight = null;
}

(:test)
function testNewChaseDir(logger as Test.Logger) as Boolean {
    initEnemy();
    var actor = PMobj.P_SpawnMobj(1056 << 16, -3616 << 16, PMobj.ONFLOORZ, Info.MT_TROOP);
    var target = PMobj.P_SpawnMobj(1056 << 16, -3616 << 16, PMobj.ONFLOORZ, Info.MT_PLAYER);
    PMobj.mobjs_target[actor] = target;
    MRandom.prndindex = 0;

    var spots = [[1200, -3400], [900, -3700], [1056, -3616], [1300, -3610], [1060, -3200], [700, -3000]];
    // movedir, movecount, x, y, prndindex after each P_NewChaseDir
    var chase = [
        [2, 13, 69206016, -236453888, 2],
        [2, 14, 69206016, -235929600, 4],
        [2, 5, 69206016, -235405312, 6],
        [2, 11, 69206016, -234881024, 8],
        [2, 14, 69206016, -234356736, 10],
        [2, 0, 69206016, -233832448, 12],
        [2, 10, 69206016, -233308160, 14],
        [2, 3, 69206016, -232783872, 16],
        [2, 0, 69206016, -232259584, 18],
        [2, 10, 69206016, -231735296, 20],
        [0, 13, 69730304, -231735296, 22],
        [0, 1, 70254592, -231735296, 24],
        [5, 9, 69878592, -232111296, 25],
        [5, 13, 69502592, -232487296, 26],
        [5, 4, 69126592, -232863296, 27],
        [4, 14, 68602304, -232863296, 29],
        [4, 0, 68078016, -232863296, 31],
        [6, 12, 68078016, -233387584, 33],
        [6, 9, 68078016, -233911872, 35],
        [4, 15, 67553728, -233911872, 37],
        [4, 2, 67029440, -233911872, 39],
        [6, 12, 67029440, -234436160, 41],
        [4, 12, 66505152, -234436160, 43],
        [6, 8, 66505152, -234960448, 45],
        [7, 4, 66881152, -235336448, 46],
        [0, 14, 67405440, -235336448, 48],
        [0, 8, 67929728, -235336448, 50],
        [6, 11, 67929728, -235860736, 52],
        [0, 8, 68454016, -235860736, 54],
        [6, 5, 68454016, -236385024, 56],
        [0, 9, 68978304, -236385024, 58],
        [0, 12, 69502592, -236385024, 60],
        [0, 10, 70026880, -236385024, 62],
        [0, 13, 70551168, -236385024, 64],
        [0, 4, 71075456, -236385024, 66],
        [0, 5, 71599744, -236385024, 68],
        [0, 1, 72124032, -236385024, 70],
        [0, 7, 72648320, -236385024, 72],
        [0, 12, 73172608, -236385024, 74],
        [0, 1, 73696896, -236385024, 76],
        [0, 11, 74221184, -236385024, 78],
        [0, 10, 74745472, -236385024, 80],
        [0, 9, 75269760, -236385024, 82],
        [0, 15, 75794048, -236385024, 84],
        [0, 6, 76318336, -236385024, 86],
        [0, 14, 76842624, -236385024, 88],
        [0, 3, 77366912, -236385024, 90],
        [0, 3, 77891200, -236385024, 92],
        [3, 13, 77515200, -236009024, 93],
        [2, 7, 77515200, -235484736, 95],
        [2, 11, 77515200, -234960448, 97],
        [2, 12, 77515200, -234436160, 99],
        [2, 1, 77515200, -233911872, 101],
        [2, 13, 77515200, -233387584, 103],
        [2, 6, 77515200, -232863296, 105],
        [2, 0, 77515200, -232339008, 107],
        [2, 4, 77515200, -231814720, 109],
        [2, 1, 77515200, -231290432, 111],
        [2, 1, 77515200, -230766144, 113],
        [2, 2, 77515200, -230241856, 115],
        [2, 1, 77515200, -229717568, 117],
        [2, 4, 77515200, -229193280, 119],
        [2, 12, 77515200, -228668992, 121],
        [2, 5, 77515200, -228144704, 123],
        [4, 11, 76990912, -228144704, 125],
        [2, 12, 76990912, -227620416, 127],
        [4, 8, 76466624, -227620416, 129],
        [2, 2, 76466624, -227096128, 131],
        [4, 5, 75942336, -227096128, 133],
        [2, 2, 75942336, -226571840, 135],
        [4, 13, 75418048, -226571840, 137],
        [2, 4, 75418048, -226047552, 139]
    ];
    for (var i = 0; i < chase.size(); i++) {
        if (i % 12 == 0) {
            PMobj.mobjs_x[target] = spots[i / 12][0] << 16;
            PMobj.mobjs_y[target] = spots[i / 12][1] << 16;
        }
        PEnemy.P_NewChaseDir(actor);
        var e = chase[i];
        Test.assertEqualMessage(PMobj.mobjs_movedir[actor], e[0], "movedir " + i);
        Test.assertEqualMessage(PMobj.mobjs_movecount[actor], e[1], "movecount " + i);
        Test.assertEqualMessage(PMobj.mobjs_x[actor], e[2], "x " + i);
        Test.assertEqualMessage(PMobj.mobjs_y[actor], e[3], "y " + i);
        Test.assertEqualMessage(MRandom.prndindex, e[4], "prndindex " + i);
    }
    doneEnemy();
    return true;
}

(:test)
function testMeleeRangeAndFaceTarget(logger as Test.Logger) as Boolean {
    initEnemy();
    var actor = PMobj.P_SpawnMobj(1056 << 16, -3616 << 16, PMobj.ONFLOORZ, Info.MT_TROOP);
    var target = PMobj.P_SpawnMobj(1056 << 16, -3616 << 16, PMobj.ONFLOORZ, Info.MT_PLAYER);
    PMobj.mobjs_target[actor] = target;
    MRandom.prndindex = 0;

    // ax, ay, tx, ty, shadow, P_CheckMeleeRange, angle after A_FaceTarget
    var faces = [
        [69206016, -236978176, 69206016, -236978176, 0, true, 0],
        [69206016, -236978176, 72089600, -236978176, 0, true, 0],
        [69206016, -236978176, 73072640, -236978176, 0, true, 0],
        [69206016, -236978176, 73138176, -236978176, 0, false, 0],
        [69206016, -236978176, 65536000, -234618880, 0, false, 1757072159],
        [69206016, -236978176, 67502080, -239861760, 0, true, -1438521217],
        [69206016, -236978176, 71434240, -239206400, 0, true, -536870912],
        [69206016, -236978176, 69206016, -229376000, 0, false, 1073741823],
        [69206016, -236978176, 69206016, -242483200, 0, false, -1073741824],
        [69206016, -236978176, 58982400, -236978176, 0, false, 2147483647],
        [0, 0, -196608, 65536, 0, true, 1927746431],
        [-131072000, 98304000, 163840000, -111411200, 0, false, -422463104],
        [69206016, -236978176, 70778880, -235929600, 1, true, 190048768],
        [69206016, -236978176, 85196800, -196608000, 1, false, 811809247],
        [69206016, -236978176, 52428800, -255590400, 1, false, -1382246785]
    ];
    for (var i = 0; i < faces.size(); i++) {
        var e = faces[i];
        PMobj.mobjs_x[actor] = e[0];
        PMobj.mobjs_y[actor] = e[1];
        PMobj.mobjs_x[target] = e[2];
        PMobj.mobjs_y[target] = e[3];
        PMobj.mobjs_flags[target] = e[4] != 0 ? PMobj.MF_SHADOW : 0;
        Test.assertEqualMessage(PEnemy.P_CheckMeleeRange(actor), e[5], "P_CheckMeleeRange " + i);
        PEnemy.A_FaceTarget(actor);
        Test.assertEqualMessage(PMobj.mobjs_angle[actor], e[6], "A_FaceTarget " + i);
    }

    // no target: nothing changes
    PMobj.mobjs_target[actor] = -1;
    Test.assertEqual(PEnemy.P_CheckMeleeRange(actor), false);
    PEnemy.A_FaceTarget(actor);
    Test.assertEqual(PMobj.mobjs_angle[actor], faces[faces.size() - 1][6]);
    doneEnemy();
    return true;
}

// A possessed at (1056, -3616) facing east, and the player at dx, dy
// from it (map units). Returns the possessed. lastlook starts at 0 (it's
// random from P_SpawnMobj), so player 0 is the first one looked at.
function lookSetup(dx as Number, dy as Number) as Number {
    initEnemy();
    var actor = PMobj.P_SpawnMobj(1056 << 16, -3616 << 16, PMobj.ONFLOORZ, Info.MT_POSSESSED);
    var player = PMobj.P_SpawnMobj((1056 + dx) << 16, (-3616 + dy) << 16, PMobj.ONFLOORZ, Info.MT_PLAYER);
    DPlayer.playeringame[0] = true;
    DPlayer.players_mo[0] = player;
    DPlayer.players_health[0] = 100;
    PMobj.mobjs_lastlook[actor] = 0;
    return actor;
}

(:test)
function testLook(logger as Test.Logger) as Boolean {
    // in front: target set, into the see state
    var actor = lookSetup(200, 40);
    var player = DPlayer.players_mo[0];
    var spawnstate = PMobj.info(actor, Info.MI_SPAWNSTATE);
    var seestate = PMobj.info(actor, Info.MI_SEESTATE);
    Test.assertEqual(PMobj.mobjs_state[actor], spawnstate);
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], player);
    Test.assertEqual(PMobj.mobjs_state[actor], seestate);

    // behind its back and far away: keeps standing
    actor = lookSetup(-200, 10);
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], -1);
    Test.assertEqual(PMobj.mobjs_state[actor], spawnstate);

    // behind but within MELEERANGE: reacts anyway
    actor = lookSetup(-40, 0);
    player = DPlayer.players_mo[0];
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], player);
    Test.assertEqual(PMobj.mobjs_state[actor], seestate);

    // starting from lastlook 1, player 0 is the "stop" player and isn't
    // looked at, like in the C; lastlook is left at 0 so the next look
    // finds it
    actor = lookSetup(200, 40);
    player = DPlayer.players_mo[0];
    PMobj.mobjs_lastlook[actor] = 1;
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], -1);
    Test.assertEqual(PMobj.mobjs_lastlook[actor], 0);
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], player);
    Test.assertEqual(PMobj.mobjs_state[actor], seestate);

    // out of sight
    actor = lookSetup(200, 40);
    PEnemy.testCheckSight = new Lang.Method(EnemyTestRules, :sightFalse);
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], -1);
    Test.assertEqual(PMobj.mobjs_state[actor], spawnstate);

    // dead player
    actor = lookSetup(200, 40);
    DPlayer.players_health[0] = 0;
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], -1);
    DPlayer.players_health[0] = 100;

    // still out of sight, but the player made a noise: the sector's
    // soundtarget wakes it without a sight check
    actor = lookSetup(-200, 10);
    player = DPlayer.players_mo[0];
    PEnemy.testCheckSight = new Lang.Method(EnemyTestRules, :sightFalse);
    PEnemy.P_NoiseAlert(player, player);
    var sec = PSetup.subsectors_sector[PMobj.mobjs_subsector[actor]];
    Test.assertEqual(PSetup.sectors_soundtarget[sec], player);
    PEnemy.A_Look(actor);
    Test.assertEqual(PMobj.mobjs_target[actor], player);
    Test.assertEqual(PMobj.mobjs_state[actor], seestate);
    doneEnemy();
    return true;
}

(:test)
function testRecursiveSound(logger as Test.Logger) as Boolean {
    initEnemy();
    // start sector, soundblock every fifth line, soundtraversed per sector
    var sound = [
        [0, false, "1111011111111111111111111111111111111111111111111111111111111111111101110001010000000"],
        [20, false, "1111011111111111111111111111111111111111111111111111111111111111111101110001010000000"],
        [37, false, "1111011111111111111111111111111111111111111111111111111111111111111101110001010000000"],
        [60, false, "1111011111111111111111111111111111111111111111111111111111111111111101110001010000000"],
        [84, false, "0000000000000000000000000000000000000000000000000000000000000000000000000000000000111"],
        [0, true, "1100001111111000000000000000000000000000000000000001122000000000000000020000000000000"],
        [20, true, "0012010000000111221111111111111111111111111111112000000222022220000000200000020000000"],
        [37, true, "0012010000000111221111111111111111111111111111112000000222022220000000200000020000000"],
        [60, true, "0020020000000222002222222222222222222222222222220000022111211110000002120002000000000"],
        [84, true, "0000000000000000000000000000000000000000000000000000000000000000000000000000000000111"]
    ];
    for (var i = 0; i < sound.size(); i++) {
        var e = sound[i];
        if (i == 5) {
            for (var j = 0; j < PSetup.numlines; j += 5) {
                PSetup.lines_flags[j] |= DoomData.ML_SOUNDBLOCK;
            }
        }
        PEnemy.soundtarget = 1000 + i;
        RMain.validcount++;
        PEnemy.P_RecursiveSound(e[0] as Number, 0);
        var got = "";
        for (var sec = 0; sec < PSetup.numsectors; sec++) {
            var flooded = PSetup.sectors_validcount[sec] == RMain.validcount;
            got += flooded ? PSetup.sectors_soundtraversed[sec] : 0;
            if (flooded) {
                Test.assertEqual(PSetup.sectors_soundtarget[sec], 1000 + i);
            }
        }
        Test.assertEqualMessage(got, e[2], "P_RecursiveSound from " + e[0] + " soundblock " + e[1]);
    }
    // put the line flags back for the other tests
    loadE1M1();
    doneEnemy();
    return true;
}
