// Expected values come from the original p_maputl.c functions run on the
// same E1M1 data, see test/maputl_ref.c.

import Toybox.Lang;
import Toybox.Test;

(:test)
function testAproxDistance(logger as Test.Logger) as Boolean {
    // dx, dy, P_AproxDistance; the big ones overflow the same way as C,
    // and abs(MININT) stays MININT
    var aprox = [
        [0, 0, 0],
        [196608, 262144, 360448],
        [-196608, 262144, 360448],
        [262144, -196608, 360448],
        [65536, 65536, 98304],
        [1, 0, 1],
        [0, -1, 1],
        [3, 3, 5],
        [-7, 5, 10],
        [2147483647, 0, 2147483647],
        [2147483647, 2147483647, -1073741825],
        [-2147483648, 0, -1073741824],
        [-2147483648, 327680, -1073414144],
        [1073741824, 1073741824, 1610612736]
    ];
    for (var i = 0; i < aprox.size(); i++) {
        var c = aprox[i];
        Test.assertEqualMessage(PMapUtl.P_AproxDistance(c[0], c[1]), c[2], "P_AproxDistance " + c[0] + " " + c[1]);
    }
    return true;
}

(:test)
function testPointOnLineSide(logger as Test.Logger) as Boolean {
    loadE1M1();
    // Lines 9, 0, 1, 2, 43, 5, 41, 6 are the first of each slopetype
    // pointing either way. The points are v1, v2, the midpoint, a step to
    // either side, one fixed unit off the midpoint, and two far away.
    // P_PointOnDivlineSide's sign bit shortcut and >>8 precision can
    // disagree with P_PointOnLineSide (line 6 at v1).
    var lineside = [
        // line, slopetype, x, y, P_PointOnLineSide, P_PointOnDivlineSide
        [9, 0, 58720256, -222298112, 0, 0],
        [9, 0, 60817408, -222298112, 0, 0],
        [9, 0, 59768832, -222298112, 0, 0],
        [9, 0, 59768832, -222429184, 0, 0],
        [9, 0, 59768832, -222167040, 1, 1],
        [9, 0, 59768833, -222298112, 0, 0],
        [9, 0, 59768832, -222298113, 0, 0],
        [9, 0, 59736064, -222276267, 1, 1],
        [9, 0, 255328256, -353370112, 0, 0],
        [9, 0, -268959744, -221839360, 1, 1],
        [0, 0, 71303168, -241172480, 1, 1],
        [0, 0, 67108864, -241172480, 1, 1],
        [0, 0, 69206016, -241172480, 1, 1],
        [0, 0, 69206016, -240910336, 0, 0],
        [0, 0, 69206016, -241434624, 1, 1],
        [0, 0, 69206017, -241172480, 1, 1],
        [0, 0, 69206016, -241172481, 1, 1],
        [0, 0, 69173248, -241150635, 0, 0],
        [0, 0, 267911168, -372244480, 1, 1],
        [0, 0, -256376832, -240713728, 0, 0],
        [1, 1, 67108864, -241172480, 1, 1],
        [1, 1, 67108864, -239075328, 1, 1],
        [1, 1, 67108864, -240123904, 1, 1],
        [1, 1, 67239936, -240123904, 0, 0],
        [1, 1, 66977792, -240123904, 1, 1],
        [1, 1, 67108865, -240123904, 0, 0],
        [1, 1, 67108864, -240123905, 1, 1],
        [1, 1, 67076096, -240102059, 1, 1],
        [1, 1, 263716864, -372244480, 0, 0],
        [1, 1, -260571136, -240713728, 1, 1],
        [2, 1, 71303168, -239075328, 0, 0],
        [2, 1, 71303168, -241172480, 0, 0],
        [2, 1, 71303168, -240123904, 0, 0],
        [2, 1, 71172096, -240123904, 0, 0],
        [2, 1, 71434240, -240123904, 1, 1],
        [2, 1, 71303169, -240123904, 1, 1],
        [2, 1, 71303168, -240123905, 0, 0],
        [2, 1, 71270400, -240102059, 0, 0],
        [2, 1, 267911168, -370147328, 1, 1],
        [2, 1, -256376832, -238616576, 0, 0],
        [43, 2, 54525952, -192937984, 1, 1],
        [43, 2, 63438848, -188743680, 1, 1],
        [43, 2, 58982400, -190840832, 1, 1],
        [43, 2, 59244544, -191397888, 0, 0],
        [43, 2, 58720256, -190283776, 1, 1],
        [43, 2, 58982401, -190840832, 1, 1],
        [43, 2, 58982400, -190840833, 0, 0],
        [43, 2, 58949632, -190818987, 1, 1],
        [43, 2, 251133952, -324009984, 0, 0],
        [43, 2, -273154048, -192479232, 1, 1],
        [5, 2, 83886080, -232783872, 1, 1],
        [5, 2, 75497472, -239075328, 1, 1],
        [5, 2, 79691776, -235929600, 1, 1],
        [5, 2, 79298560, -235405312, 0, 0],
        [5, 2, 80084992, -236453888, 1, 1],
        [5, 2, 79691777, -235929600, 1, 1],
        [5, 2, 79691776, -235929601, 1, 1],
        [5, 2, 79659008, -235907755, 0, 0],
        [5, 2, 280494080, -363855872, 1, 1],
        [5, 2, -243793920, -232325120, 0, 0],
        [41, 3, 79691776, -201326592, 1, 1],
        [41, 3, 88080384, -203423744, 1, 1],
        [41, 3, 83886080, -202375168, 1, 1],
        [41, 3, 83755008, -202899456, 0, 0],
        [41, 3, 84017152, -201850880, 1, 1],
        [41, 3, 83886081, -202375168, 1, 1],
        [41, 3, 83886080, -202375169, 0, 0],
        [41, 3, 83853312, -202353323, 1, 1],
        [41, 3, 276299776, -332398592, 0, 0],
        [41, 3, -247988224, -200867840, 0, 0],
        [6, 3, 62914560, -239075328, 1, 0],
        [6, 3, 54525952, -232783872, 1, 1],
        [6, 3, 58720256, -235929600, 1, 1],
        [6, 3, 59113472, -235405312, 0, 0],
        [6, 3, 58327040, -236453888, 1, 1],
        [6, 3, 58720257, -235929600, 1, 1],
        [6, 3, 58720256, -235929601, 1, 1],
        [6, 3, 58687488, -235907755, 1, 1],
        [6, 3, 259522560, -370147328, 0, 0],
        [6, 3, -264765440, -238616576, 1, 1]
    ];
    var dl = [0, 0, 0, 0] as Array<Number>;
    for (var i = 0; i < lineside.size(); i++) {
        var c = lineside[i];
        Test.assertEqualMessage(PSetup.lines_slopetype[c[0]], c[1], "slopetype " + c[0]);
        Test.assertEqualMessage(PMapUtl.P_PointOnLineSide(c[2], c[3], c[0]), c[4], "P_PointOnLineSide case " + i);
        PMapUtl.P_MakeDivline(c[0], dl);
        Test.assertEqualMessage(PMapUtl.P_PointOnDivlineSide(c[2], c[3], dl), c[5], "P_PointOnDivlineSide case " + i);
    }
    return true;
}

(:test)
function testBoxOnLineSide(logger as Test.Logger) as Boolean {
    loadE1M1();
    // 32 unit boxes on the midpoint (straddling), off to each diagonal,
    // and one with an edge exactly on v1
    var boxside = [
        // line, top, bottom, left, right, P_BoxOnLineSide
        [9, -221249536, -223346688, 58720256, 60817408, -1],
        [9, -217055232, -219152384, 62914560, 65011712, 1],
        [9, -225443840, -227540992, 54525952, 56623104, 0],
        [9, -225443840, -227540992, 62914560, 65011712, 0],
        [9, -217055232, -219152384, 54525952, 56623104, 1],
        [9, -222298112, -223346688, 58720256, 59768832, 0],
        [0, -240123904, -242221056, 68157440, 70254592, -1],
        [0, -235929600, -238026752, 72351744, 74448896, 0],
        [0, -244318208, -246415360, 63963136, 66060288, 1],
        [0, -244318208, -246415360, 72351744, 74448896, 1],
        [0, -235929600, -238026752, 63963136, 66060288, 0],
        [0, -241172480, -242221056, 71303168, 72351744, 1],
        [1, -239075328, -241172480, 66060288, 68157440, -1],
        [1, -234881024, -236978176, 70254592, 72351744, 0],
        [1, -243269632, -245366784, 61865984, 63963136, 1],
        [1, -243269632, -245366784, 70254592, 72351744, 0],
        [1, -234881024, -236978176, 61865984, 63963136, 1],
        [1, -241172480, -242221056, 67108864, 68157440, 0],
        [2, -239075328, -241172480, 70254592, 72351744, -1],
        [2, -234881024, -236978176, 74448896, 76546048, 1],
        [2, -243269632, -245366784, 66060288, 68157440, 0],
        [2, -243269632, -245366784, 74448896, 76546048, 1],
        [2, -234881024, -236978176, 66060288, 68157440, 0],
        [2, -239075328, -240123904, 71303168, 72351744, 1],
        [43, -189792256, -191889408, 57933824, 60030976, -1],
        [43, -185597952, -187695104, 62128128, 64225280, 1],
        [43, -193986560, -196083712, 53739520, 55836672, 0],
        [43, -193986560, -196083712, 62128128, 64225280, 0],
        [43, -185597952, -187695104, 53739520, 55836672, 1],
        [43, -192937984, -193986560, 54525952, 55574528, -1],
        [5, -234881024, -236978176, 78643200, 80740352, -1],
        [5, -230686720, -232783872, 82837504, 84934656, -1],
        [5, -239075328, -241172480, 74448896, 76546048, -1],
        [5, -239075328, -241172480, 82837504, 84934656, 1],
        [5, -230686720, -232783872, 74448896, 76546048, 0],
        [5, -232783872, -233832448, 83886080, 84934656, 1],
        [41, -201326592, -203423744, 82837504, 84934656, -1],
        [41, -197132288, -199229440, 87031808, 89128960, 1],
        [41, -205520896, -207618048, 78643200, 80740352, 0],
        [41, -205520896, -207618048, 87031808, 89128960, 0],
        [41, -197132288, -199229440, 78643200, 80740352, 1],
        [41, -201326592, -202375168, 79691776, 80740352, -1],
        [6, -234881024, -236978176, 57671680, 59768832, -1],
        [6, -230686720, -232783872, 61865984, 63963136, 0],
        [6, -239075328, -241172480, 53477376, 55574528, 1],
        [6, -239075328, -241172480, 61865984, 63963136, -1],
        [6, -230686720, -232783872, 53477376, 55574528, -1],
        [6, -239075328, -240123904, 62914560, 63963136, -1]
    ];
    var box = [0, 0, 0, 0] as Array<Number>;
    for (var i = 0; i < boxside.size(); i++) {
        var c = boxside[i];
        box[MBBox.BOXTOP] = c[1];
        box[MBBox.BOXBOTTOM] = c[2];
        box[MBBox.BOXLEFT] = c[3];
        box[MBBox.BOXRIGHT] = c[4];
        Test.assertEqualMessage(PMapUtl.P_BoxOnLineSide(box, c[0]), c[5], "P_BoxOnLineSide case " + i);
    }
    return true;
}

(:test)
function testInterceptVector(logger as Test.Logger) as Boolean {
    loadE1M1();
    // every pair of the lines above; parallel pairs give den == 0
    var intercept = [
        // v2 line, v1 line, frac
        [9, 9, 0],
        [9, 0, 0],
        [9, 1, 262144],
        [9, 2, 393216],
        [9, 43, -2080768],
        [9, 5, 1223338],
        [9, 41, 3276800],
        [9, 6, -567978],
        [0, 9, 0],
        [0, 0, 0],
        [0, 1, 65536],
        [0, 2, 0],
        [0, 43, 1863680],
        [0, 5, -21845],
        [0, 41, -2621440],
        [0, 6, 87381],
        [1, 9, 589824],
        [1, 0, 0],
        [1, 1, 0],
        [1, 2, 0],
        [1, 43, 1692370],
        [1, 5, -131072],
        [1, 41, 1343488],
        [1, 6, -32768],
        [2, 9, -524288],
        [2, 0, 65536],
        [2, 1, 0],
        [2, 2, 0],
        [2, 43, -1688515],
        [2, 5, 98304],
        [2, 41, -1245184],
        [2, 6, 196608],
        [43, 9, -458752],
        [43, 0, -753664],
        [43, 1, 92521],
        [43, 2, 123361],
        [43, 43, 0],
        [43, 5, 1628052],
        [43, 41, -21399],
        [43, 6, -240035],
        [5, 9, -109226],
        [5, 0, 87381],
        [5, 1, 131072],
        [5, 2, 98304],
        [5, 43, -1500429],
        [5, 5, 0],
        [5, 41, -237568],
        [5, 6, 114688],
        [41, 9, 655360],
        [41, 0, 1245184],
        [41, 1, -98304],
        [41, 2, -65536],
        [41, 43, -219344],
        [41, 5, 270336],
        [41, 41, 0],
        [41, 6, -786432],
        [6, 9, 174762],
        [6, 0, -21845],
        [6, 1, -32768],
        [6, 2, -65536],
        [6, 43, 320573],
        [6, 5, -49152],
        [6, 41, 655360],
        [6, 6, 0]
    ];
    var a = [0, 0, 0, 0] as Array<Number>;
    var b = [0, 0, 0, 0] as Array<Number>;
    for (var i = 0; i < intercept.size(); i++) {
        var c = intercept[i];
        PMapUtl.P_MakeDivline(c[0], a);
        PMapUtl.P_MakeDivline(c[1], b);
        Test.assertEqualMessage(PMapUtl.P_InterceptVector(a, b), c[2], "P_InterceptVector case " + i);
    }

    // traces from the player start, as P_PathTraverse builds them
    var traces = [
        // trace x, y, dx, dy, line, frac
        [69206016, -236978176, 65536000, 0, 9, 0],
        [69206016, -236978176, 65536000, 0, 2, 2097],
        [69206016, -236978176, 65536000, 0, 41, 153092],
        [69206016, -236978176, -19660800, 52428800, 9, 18350],
        [69206016, -236978176, -19660800, 52428800, 2, -6990],
        [69206016, -236978176, -19660800, 52428800, 41, 52790],
        [69206016, -236978176, 134152192, -134152192, 9, -7171],
        [69206016, -236978176, 134152192, -134152192, 2, 1024],
        [69206016, -236978176, 134152192, -134152192, 41, -24929],
        [0, 0, 65536, 65536, 9, -222298112],
        [0, 0, 65536, 65536, 2, 71303168],
        [0, 0, 65536, 65536, 41, -145122918]
    ];
    for (var i = 0; i < traces.size(); i++) {
        var c = traces[i];
        var trace = [c[0], c[1], c[2], c[3]] as Array<Number>;
        PMapUtl.P_MakeDivline(c[4], b);
        Test.assertEqualMessage(PMapUtl.P_InterceptVector(trace, b), c[5], "P_InterceptVector trace " + i);
    }
    return true;
}

(:test)
function testLineOpening(logger as Test.Logger) as Boolean {
    loadE1M1();
    // the last row is single sided: only openrange changes
    var opening = [
        // line, openrange, opentop, openbottom, lowfloor (front floor higher?)
        [26, 12058624, 12582912, 524288, -1048576],  // back
        [29, 12058624, 12582912, 524288, -1048576],  // back
        [30, 12058624, 12582912, 524288, -3670016],  // back
        [270, 524288, 6815744, 6291456, -3145728],  // front
        [385, 4718592, 4718592, 0, -524288],  // front
        [0, 0, 4718592, 0, -524288]  // single sided
    ];
    for (var i = 0; i < opening.size(); i++) {
        var c = opening[i];
        PMapUtl.P_LineOpening(c[0]);
        Test.assertEqualMessage(PMapUtl.openrange, c[1], "openrange " + c[0]);
        Test.assertEqualMessage(PMapUtl.opentop, c[2], "opentop " + c[0]);
        Test.assertEqualMessage(PMapUtl.openbottom, c[3], "openbottom " + c[0]);
        Test.assertEqualMessage(PMapUtl.lowfloor, c[4], "lowfloor " + c[0]);
    }

    // every line in order, single sided ones keep the previous values
    PMapUtl.opentop = 0;
    PMapUtl.openbottom = 0;
    PMapUtl.openrange = 0;
    PMapUtl.lowfloor = 0;
    var sum = 0l;
    for (var i = 0; i < PSetup.numlines; i++) {
        PMapUtl.P_LineOpening(i);
        sum += (i + 1).toLong() * ((PMapUtl.openrange >> 8) + 3 * (PMapUtl.opentop >> 8)
            + 5 * (PMapUtl.openbottom >> 8) + 7 * (PMapUtl.lowfloor >> 8));
    }
    Test.assertEqual(sum, 6773358592l);
    return true;
}

// Stand-in PIT_* function: counts visits and sums the visited line numbers
// weighted by visit order, and stops after stopafter visits.
class BlockLineCounter {
    var visits as Number = 0;
    var visitsum as Long = 0l;
    var stopafter as Number = 0;

    function initialize(stop as Number) {
        stopafter = stop;
    }

    function count(ld as Number) as Boolean {
        visits++;
        visitsum += visits.toLong() * ld;
        return visits != stopafter;
    }
}

(:test)
function testBlockLinesIterator(logger as Test.Logger) as Boolean {
    loadE1M1();
    Test.assertEqual(PSetup.bmapwidth, 36);
    Test.assertEqual(PSetup.bmapheight, 23);

    // Block 29,2 is the busiest (13 entries). Every list starts with line
    // 0, so even an empty block like 0,0 visits it once. Out of range
    // blocks return true without visiting anything.
    var blocks = [
        // x, y, stopafter, result, visits, visitsum
        [0, 0, 0, 1, 1, 0l],
        [29, 2, 0, 1, 13, 29981l],
        [29, 2, 3, 0, 3, 1531l],
        [17, 18, 0, 1, 5, 2103l],
        [12, 13, 0, 1, 1, 0l],
        [30, 2, 0, 1, 5, 4366l],
        [-1, 0, 0, 1, 0, 0l],
        [0, -1, 0, 1, 0, 0l],
        [36, 0, 0, 1, 0, 0l],
        [0, 23, 0, 1, 0, 0l],
        [35, 22, 0, 1, 1, 0l]
    ];
    for (var i = 0; i < blocks.size(); i++) {
        var c = blocks[i];
        RMain.validcount++;
        var counter = new BlockLineCounter(c[2]);
        var r = PMapUtl.P_BlockLinesIterator(c[0], c[1], counter.method(:count));
        Test.assertEqualMessage(r, c[3] == 1, "P_BlockLinesIterator result " + i);
        Test.assertEqualMessage(counter.visits, c[4], "P_BlockLinesIterator visits " + i);
        Test.assertEqualMessage(counter.visitsum, c[5], "P_BlockLinesIterator visitsum " + i);
    }

    // one validcount over the 5x5 blocks around 29,2: lines in several
    // blocks count once
    RMain.validcount++;
    var counter = new BlockLineCounter(0);
    var fn = counter.method(:count);
    for (var y = 0; y <= 4; y++) {
        for (var x = 27; x <= 31; x++) {
            PMapUtl.P_BlockLinesIterator(x, y, fn);
        }
    }
    Test.assertEqual(counter.visits, 51);
    Test.assertEqual(counter.visitsum, 410290l);

    // the whole map visits every line exactly once
    RMain.validcount++;
    counter = new BlockLineCounter(0);
    fn = counter.method(:count);
    for (var y = 0; y < PSetup.bmapheight; y++) {
        for (var x = 0; x < PSetup.bmapwidth; x++) {
            PMapUtl.P_BlockLinesIterator(x, y, fn);
        }
    }
    Test.assertEqual(counter.visits, 475);
    Test.assertEqual(counter.visitsum, 26299201l);
    return true;
}

(:test)
function testPointInSubsectorMatchesRenderer(logger as Test.Logger) as Boolean {
    // P_PointInSubsector is R_PointInSubsector written out for speed; it
    // has to land in the same subsector everywhere, including points on
    // partition lines and far off the map.
    loadE1M1();
    var seed = 12345;
    for (var i = 0; i < 3000; i++) {
        seed = seed * 1103515245 + 12345;
        var x = ((seed >> 8) & 0x1fff) - 1024;
        seed = seed * 1103515245 + 12345;
        var y = -((seed >> 8) & 0x1fff);
        seed = seed * 1103515245 + 12345;
        var frac = (seed >> 4) & 0xffff;
        if ((i & 3) == 0) {
            frac = 0;   // whole map units, often right on a partition
        }
        var fx = (x << 16) + frac;
        var fy = (y << 16) + frac;
        Test.assertEqualMessage(PMapUtl.P_PointInSubsector(fx, fy), RMain.R_PointInSubsector(fx, fy), "point " + fx + " " + fy);
    }
    // node origins themselves
    for (var n = 0; n < PSetup.numnodes; n++) {
        var fx = PSetup.nodes_x[n];
        var fy = PSetup.nodes_y[n];
        Test.assertEqual(PMapUtl.P_PointInSubsector(fx, fy), RMain.R_PointInSubsector(fx, fy));
        Test.assertEqual(PMapUtl.P_PointInSubsector(fx + PSetup.nodes_dx[n], fy - 1), RMain.R_PointInSubsector(fx + PSetup.nodes_dx[n], fy - 1));
    }
    Test.assertEqual(PMapUtl.P_PointInSubsector(DoomType.MAXINT, DoomType.MININT), RMain.R_PointInSubsector(DoomType.MAXINT, DoomType.MININT));
    return true;
}
