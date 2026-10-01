// Expected values come from the original st_lib.c / st_stuff.c code,
// see test/st_ref.c: the patches STlib_drawNum draws for a few numbers,
// and the face ST_updateFaceWidget picks on each tic of a scripted run
// (getting hit from every side, the ouch face, a weapon pickup, rapid
// fire, god mode, invulnerability, dying), with a fixed random number.

import Toybox.Lang;
import Toybox.Test;

(:test)
function testDrawNumMatchesC(logger as Test.Logger) as Boolean {
    var tallnum = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] as Array<Number>;
    var shortnum = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19] as Array<Number>;
    // widget (0 tall at ST_AMMOX, 1 short at ST_AMMO0X, 2 two-digit tall
    // at ST_FRAGSX), number, then lump, x, y per patch and -1, x, y, w,
    // h per V_CopyRect
    var cases = [
        [0, 0, [-1, 2, 171, 42, 16, 0, 30, 171]],
        [1, 0, [-1, 276, 173, 12, 6, 10, 284, 173]],
        [2, 0, [-1, 110, 171, 28, 16, 0, 124, 171]],
        [0, 7, [-1, 2, 171, 42, 16, 7, 30, 171]],
        [1, 7, [-1, 276, 173, 12, 6, 17, 284, 173]],
        [2, 7, [-1, 110, 171, 28, 16, 7, 124, 171]],
        [0, 50, [-1, 2, 171, 42, 16, 0, 30, 171, 5, 16, 171]],
        [1, 50, [-1, 276, 173, 12, 6, 10, 284, 173, 15, 280, 173]],
        [2, 50, [-1, 110, 171, 28, 16, 0, 124, 171, 5, 110, 171]],
        [0, 123, [-1, 2, 171, 42, 16, 3, 30, 171, 2, 16, 171, 1, 2, 171]],
        [1, 123, [-1, 276, 173, 12, 6, 13, 284, 173, 12, 280, 173, 11, 276, 173]],
        [2, 123, [-1, 110, 171, 28, 16, 3, 124, 171, 2, 110, 171]],
        [0, 999, [-1, 2, 171, 42, 16, 9, 30, 171, 9, 16, 171, 9, 2, 171]],
        [1, 999, [-1, 276, 173, 12, 6, 19, 284, 173, 19, 280, 173, 19, 276, 173]],
        [2, 999, [-1, 110, 171, 28, 16, 9, 124, 171, 9, 110, 171]],
        [0, 1000, [-1, 2, 171, 42, 16, 0, 30, 171, 0, 16, 171, 0, 2, 171]],
        [1, 1000, [-1, 276, 173, 12, 6, 10, 284, 173, 10, 280, 173, 10, 276, 173]],
        [2, 1000, [-1, 110, 171, 28, 16, 0, 124, 171, 0, 110, 171]],
        [0, 1994, [-1, 2, 171, 42, 16]],
        [1, 1994, [-1, 276, 173, 12, 6]],
        [2, 1994, [-1, 110, 171, 28, 16]],
        [0, -5, [-1, 2, 171, 42, 16, 5, 30, 171, 79, 22, 171]],
        [1, -5, [-1, 276, 173, 12, 6, 15, 284, 173, 79, 276, 173]],
        [2, -5, [-1, 110, 171, 28, 16, 5, 124, 171, 79, 116, 171]],
        [0, -42, [-1, 2, 171, 42, 16, 2, 30, 171, 4, 16, 171, 79, 8, 171]],
        [1, -42, [-1, 276, 173, 12, 6, 12, 284, 173, 14, 280, 173, 79, 272, 173]],
        [2, -42, [-1, 110, 171, 28, 16, 9, 124, 171, 79, 116, 171]],
        [0, -123, [-1, 2, 171, 42, 16, 9, 30, 171, 9, 16, 171, 79, 8, 171]],
        [1, -123, [-1, 276, 173, 12, 6, 19, 284, 173, 19, 280, 173, 79, 272, 173]],
        [2, -123, [-1, 110, 171, 28, 16, 9, 124, 171, 79, 116, 171]]
    ];
    var n = new st_number_t();
    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var kind = c[0] as Number;
        if (kind == 0) {
            StLib.STlib_initNum(n, StStuff.ST_AMMOX, StStuff.ST_AMMOY, tallnum, c[1] as Number, true, StStuff.ST_AMMOWIDTH);
        } else if (kind == 1) {
            StLib.STlib_initNum(n, StStuff.ST_AMMO0X, StStuff.ST_AMMO0Y, shortnum, c[1] as Number, true, StStuff.ST_AMMO0WIDTH);
        } else {
            StLib.STlib_initNum(n, StStuff.ST_FRAGSX, StStuff.ST_FRAGSY, tallnum, c[1] as Number, true, StStuff.ST_FRAGSWIDTH);
        }
        StLib.drawtrace = [] as Array<Number>;
        StLib.STlib_drawNum(n, true);
        var trace = StLib.drawtrace as Array<Number>;
        StLib.drawtrace = null;
        var expect = c[2] as Array<Number>;
        Test.assertEqualMessage(trace.size(), expect.size(), "draw calls for case " + i);
        for (var k = 0; k < expect.size(); k++) {
            Test.assertEqualMessage(trace[k], expect[k], "draw value " + k + " for case " + i);
        }
        Test.assertEqual(n.oldnum, c[1]);
    }

    // updateNum skips an unchanged number, and draws nothing when off
    StLib.drawtrace = [] as Array<Number>;
    StLib.STlib_updateNum(n, false);
    n.on = false;
    n.num = 5;
    StLib.STlib_updateNum(n, true);
    Test.assertEqual((StLib.drawtrace as Array<Number>).size(), 0);
    StLib.drawtrace = null;
    return true;
}

// Same table as script[] in st_ref.c: tics, health, damagecount,
// bonuscount, attacker spot (0 none), player angle (degrees),
// weaponowned bits, attackdown, cheats, invulnerability tics.
const FACE_SCRIPT = [
    [40, 100, 0, 0, 0, 0, 3, 0, 0, 0],     // idle, looking around
    [1, 90, 10, 0, 1, 0, 3, 0, 0, 0],      // hit from the left
    [34, 90, 9, 0, 1, 0, 3, 0, 0, 0],
    [40, 90, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 80, 10, 0, 2, 0, 3, 0, 0, 0],      // hit from the right
    [40, 80, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 75, 8, 0, 3, 0, 3, 0, 0, 0],       // head-on
    [40, 75, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 72, 8, 0, 1, 90, 3, 0, 0, 0],      // left spot, facing it
    [40, 72, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 70, 8, 0, 4, 0, 3, 0, 0, 0],       // from behind
    [40, 70, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 68, 8, 0, 5, 0, 3, 0, 0, 0],       // front left diagonal
    [40, 68, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 66, 8, 0, 2, 270, 3, 0, 0, 0],     // right spot, facing it
    [40, 66, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 95, 5, 0, 1, 0, 3, 0, 0, 0],       // health up by 25 while hit: ouch
    [40, 95, 0, 0, 0, 0, 3, 0, 0, 0],
    [3, 60, 6, 0, 0, 0, 3, 0, 0, 0],       // hurt by the floor
    [1, 85, 3, 0, 0, 0, 3, 0, 0, 0],       // ... with the ouch bug
    [40, 85, 0, 0, 0, 0, 3, 0, 0, 0],
    [1, 85, 0, 6, 0, 0, 7, 0, 0, 0],       // picked up the shotgun
    [80, 85, 0, 5, 0, 0, 7, 0, 0, 0],
    [90, 85, 0, 0, 0, 0, 7, 1, 0, 0],      // holding fire
    [20, 85, 0, 0, 0, 0, 7, 0, 0, 0],
    [10, 85, 0, 0, 0, 0, 7, 0, 2, 0],      // iddqd
    [20, 85, 0, 0, 0, 0, 7, 0, 0, 0],
    [5, 85, 0, 0, 0, 0, 7, 0, 0, 30],      // invulnerability sphere
    [20, 85, 0, 0, 0, 0, 7, 0, 0, 0],
    [20, 15, 0, 0, 0, 0, 7, 0, 0, 0],      // nearly dead
    [5, 0, 0, 0, 0, 0, 7, 0, 0, 0],        // dead
];
const FACE_SPOTS = [[0, 0], [0, 100], [0, -100], [100, 10], [-100, 5], [70, 80]];

(:test)
function testFaceWidgetMatchesC(logger as Test.Logger) as Boolean {
    var expect = [
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3,
        3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
        2, 2, 2, 2, 2, 2, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 9, 9, 9, 9, 9, 9, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 8, 8, 8, 8, 8, 8, 12, 12, 12, 12, 12, 12, 12,
        12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
        12, 12, 12, 12, 12, 10, 10, 10, 10, 10, 10, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
        12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
        9, 9, 9, 9, 9, 9, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 8, 8, 8, 8, 8, 8, 5, 5,
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
        5, 5, 5, 2, 2, 2, 2, 2, 2, 15, 15, 15, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 1, 1, 1, 1, 6, 6, 6, 6, 6, 6,
        6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        6, 6, 6, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 7, 7, 7, 7,
        7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 2, 2, 2, 2, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 0, 0, 0, 40, 40, 40, 40, 40, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 32, 32, 32, 32, 32, 32, 41, 41, 41,
        41, 41
    ];

    Tables.Tables_Init();
    // two mobjs: 1 is the player, 2 the attacker
    if (PMobj.mobjs_x.size() < 3) {
        PMobj.P_InitMobjs(3);
    }
    var p = 0;
    var mo = 1;
    var badguy = 2;
    DPlayer.players_mo[p] = mo;
    PMobj.mobjs_x[mo] = 0;
    PMobj.mobjs_y[mo] = 0;
    for (var i = 0; i < DoomDef.NUMWEAPONS; i++) {
        DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + i] = (3 >> i) & 1;
    }
    for (var i = 0; i < DoomDef.NUMPOWERS; i++) {
        DPlayer.players_powers[p * DoomDef.NUMPOWERS + i] = 0;
    }

    // ST_initData, and the C statics' initial values
    StStuff.ST_initData();
    StStuff.st_facecount = 0;
    StStuff.priority = 0;
    StStuff.lastattackdown = -1;
    StStuff.oldhealth = -1;
    StStuff.lastcalc = 0;

    var tic = 0;
    for (var s = 0; s < FACE_SCRIPT.size(); s++) {
        var c = FACE_SCRIPT[s];
        for (var t = 0; t < c[0]; t++) {
            DPlayer.players_health[p] = c[1];
            DPlayer.players_damagecount[p] = c[2];
            DPlayer.players_bonuscount[p] = c[3];
            DPlayer.players_attacker[p] = c[4] != 0 ? badguy : -1;
            PMobj.mobjs_x[badguy] = FACE_SPOTS[c[4]][0] << 16;
            PMobj.mobjs_y[badguy] = FACE_SPOTS[c[4]][1] << 16;
            PMobj.mobjs_angle[mo] = (Tables.ANG45 / 45) * c[5];
            for (var i = 0; i < DoomDef.NUMWEAPONS; i++) {
                DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + i] = (c[6] >> i) & 1;
            }
            DPlayer.players_attackdown[p] = c[7];
            DPlayer.players_cheats[p] = c[8];
            DPlayer.players_powers[p * DoomDef.NUMPOWERS + DoomDef.pw_invulnerability] = c[9];

            // ST_Ticker with a fixed random number
            StStuff.st_randomnumber = (tic * 37 + 11) & 255;
            StStuff.ST_updateFaceWidget();
            StStuff.st_oldhealth = DPlayer.players_health[p];
            Test.assertEqualMessage(StStuff.st_faceindex, expect[tic], "face at tic " + tic);
            tic++;
        }
    }
    Test.assertEqual(tic, expect.size());

    DPlayer.players_cheats[p] = 0;
    DPlayer.players_attacker[p] = -1;
    return true;
}

// The first ST_Drawer after ST_Start and a tic draws the whole bar:
// background, every widget, the arms background before the arms
// numbers (yellow 2 for the pistol, grey 3-7), and the face. The next
// one draws nothing when nothing changed.
(:test)
function testFirstDrawRefreshesAll(logger as Test.Logger) as Boolean {
    Tables.Tables_Init();
    GGame.G_PlayerReborn(0);
    StStuff.ST_Start();
    StStuff.ST_Ticker();
    StLib.drawtrace = [] as Array<Number>;
    StStuff.ST_Drawer(false, false);
    var trace = StLib.drawtrace as Array<Number>;
    var tail = [80, 104, 168, 12, 111, 172, 23, 123, 172, 24, 135, 172,
                25, 111, 182, 26, 123, 182, 27, 135, 182,
                HudLumps.FACES + StStuff.st_faceindex, 143, 168];
    // background first
    Test.assertEqual(trace.slice(0, 5).toString(), [-1, 0, 168, 320, 32].toString());
    Test.assertEqual(trace.slice(trace.size() - tail.size(), null).toString(), tail.toString());

    StLib.drawtrace = [] as Array<Number>;
    StStuff.ST_Drawer(false, false);
    Test.assertEqual((StLib.drawtrace as Array<Number>).size(), 0);
    StLib.drawtrace = null;
    return true;
}
