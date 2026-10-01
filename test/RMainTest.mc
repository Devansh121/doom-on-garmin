// Expected values come from the original r_main.c functions built
// against the original tables.c, see test/rmain_ref.c.

import Toybox.Lang;
import Toybox.Test;

function initRender() as Void {
    Tables.Tables_Init();
    // Full screen view (setblocks 11, viewheight 200) like the C
    // references, not the game's view above the status bar.
    RMain.screenblocks = 11;
    RMain.detaillevel = 1;
    RMain.initstep = 0;
    while (!RMain.R_InitStep()) {
    }
    // P_Init's R_InitSprites, since R_Subsector adds sprites
    if (Info.mobjinfo.size() == 0) {
        Info.Info_Init();
    }
    RThings.R_InitSprites(Info.sprnames);
}

(:test)
function testTextureMapping(logger as Test.Logger) as Boolean {
    initRender();
    Test.assertEqual(RMain.viewwidth, 160);
    Test.assertEqual(RMain.viewheight, 200);

    var sum = 0l;
    for (var i = 0; i < Tables.FINEANGLES / 2; i++) {
        sum += RMain.viewangletox[i].toLong() * (i + 1);
    }
    Test.assertEqual(sum, 371201800l);
    Test.assertEqual(RMain.viewangletox[1000], 160);
    Test.assertEqual(RMain.viewangletox[2048], 80);
    Test.assertEqual(RMain.viewangletox[3000], 9);

    Test.assertEqual(RMain.xtoviewangle[0], 537395200);
    Test.assertEqual(RMain.xtoviewangle[40], 317194240);
    Test.assertEqual(RMain.xtoviewangle[80], 0);
    Test.assertEqual(RMain.xtoviewangle[120], -317194240);
    Test.assertEqual(RMain.xtoviewangle[160], -537395200);
    Test.assertEqual(RMain.clipangle, 537395200);
    return true;
}

(:test)
function testPointToAngleAndDist(logger as Test.Logger) as Boolean {
    Tables.Tables_Init();
    var cases = [
        // viewx, viewy, x, y (map units), angle, dist
        [1056, -3616, 1200, -3500, 463381344, 12113665],
        [1056, -3616, 900, -3700, -1810041536, 11609226],
        [0, 0, -5, 300, 1085089033, 19663500],
        [0, 0, -300, -2, -2143144669, 19661400],
        [100, 100, 100, 100, 0, 0],
        [-2000, 500, 3000, -1500, -260043392, 352862131],
        [1056, -3616, 1056, -3000, 1073741823, 40370792],
        [1000, 1000, 999, -2000, -1073741825, 196611000]
    ];
    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        RMain.viewx = c[0] << 16;
        RMain.viewy = c[1] << 16;
        var x = c[2] << 16;
        var y = c[3] << 16;
        Test.assertEqualMessage(RMain.R_PointToAngle(x, y), c[4], "R_PointToAngle case " + i);
        if (x != RMain.viewx || y != RMain.viewy) {
            Test.assertEqualMessage(RMain.R_PointToDist(x, y), c[5], "R_PointToDist case " + i);
        }
    }
    return true;
}

(:test)
function testPointInSubsector(logger as Test.Logger) as Boolean {
    loadE1M1();
    var cases = [[1056, -3616, 103], [1500, -3200, 39], [3000, -3000, 168], [2000, -2500, 9], [-200, 200, 60]];
    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        Test.assertEqualMessage(RMain.R_PointInSubsector(c[0] << 16, c[1] << 16), c[2], "R_PointInSubsector " + i);
    }
    return true;
}

(:test)
function testInitData(logger as Test.Logger) as Boolean {
    initRender();
    // shareware TEXTURE1 has 125 textures, F_START..F_END 56 flats
    Test.assertEqual(RData.numtextures, 125);
    Test.assertEqual(RData.numflats, 56);
    // light level 0 is brightest, 31 is nearly black
    var c0 = RData.texturecolors[1 * 32];
    var c31 = RData.texturecolors[1 * 32 + 31];
    Test.assert(((c0 >> 16) & 0xff) > ((c31 >> 16) & 0xff));
    return true;
}
