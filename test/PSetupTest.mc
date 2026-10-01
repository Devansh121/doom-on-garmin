// Expected values were computed separately in Python from the same
// converted E1M1 lumps.

import Toybox.Lang;
import Toybox.Test;

function loadE1M1() as Void {
    // P_LoadThings spawns mobjs, which needs mobjinfo and states
    if (Info.mobjinfo.size() == 0) {
        Info.Info_Init();
    }
    PSetup.P_SetupLevel(1, 1);
    var steps = 0;
    while (!PSetup.P_SetupLevelStep()) {
        steps++;
        Test.assert(steps < 1000);
    }
}

(:test)
function testSetupLevelE1M1(logger as Test.Logger) as Boolean {
    loadE1M1();

    Test.assertEqual(PSetup.numvertexes, 467);
    Test.assertEqual(PSetup.numsectors, 85);
    Test.assertEqual(PSetup.numlines, 475);
    Test.assertEqual(PSetup.numsides, 648);
    Test.assertEqual(PSetup.numsegs, 732);
    Test.assertEqual(PSetup.numsubsectors, 237);
    Test.assertEqual(PSetup.numnodes, 236);
    Test.assertEqual(PSetup.linebuffer.size(), 642);

    var expect = [
        // sector, linecount, soundorg x, y, blockbox top, bottom, left, right
        [0, 4, 105381888, -163577856, 19, 17, 17, 19],
        [37, 12, 68157440, -211812352, 14, 11, 12, 15],
        [84, 4, 197132288, -305397760, 2, 1, 29, 30]
    ];
    for (var i = 0; i < expect.size(); i++) {
        var e = expect[i];
        var s = e[0];
        Test.assertEqualMessage(PSetup.sectors_linecount[s], e[1], "linecount " + s);
        Test.assertEqualMessage(PSetup.sectors_soundorg_x[s], e[2], "soundorg x " + s);
        Test.assertEqualMessage(PSetup.sectors_soundorg_y[s], e[3], "soundorg y " + s);
        for (var k = 0; k < 4; k++) {
            Test.assertEqualMessage(PSetup.sectors_blockbox[s * 4 + k], e[4 + k], "blockbox " + s + " " + k);
        }
    }

    var start = DoomStat.playerstarts[0] as Array<Number>;
    Test.assertEqual(start[0], 1056);
    Test.assertEqual(start[1], -3616);
    Test.assertEqual(start[2], 90);
    return true;
}
