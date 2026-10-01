// Reference values come from the C functions in m_fixed.c / tables.c
// compiled with gcc (see test/fixed_ref.c).

import Toybox.Lang;
import Toybox.Test;

(:test)
function testFixedMulDiv(logger as Test.Logger) as Boolean {
    var cases = [
        [65536, 65536, 65536, 65536],
        [-196608, 131072, -393216, -98304],
        [123456789, -98765, -186053616, -81920357],
        [1073741824, 1073741824, 0, 65536],
        [-2147483647, 3, -98304, -2147483648],
        [70000, 1, 1, 2147483647],
        [1, -1, -1, -65536],
        [-500000000, 7, -53406, -2147483648]
    ];
    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        Test.assertEqualMessage(MFixed.FixedMul(c[0], c[1]), c[2], "FixedMul " + c[0] + " " + c[1]);
        Test.assertEqualMessage(MFixed.FixedDiv(c[0], c[1]), c[3], "FixedDiv " + c[0] + " " + c[1]);
    }
    return true;
}

(:test)
function testSlopeDiv(logger as Test.Logger) as Boolean {
    var cases = [
        [0, 600, 0],
        [100, 100, 2048],
        [65536, 65536, 2048],
        [1073741824, 536870912, 0],
        [-1294967296, -2147483648, 301],
        [536870911, 4000000, 2048]
    ];
    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        Test.assertEqualMessage(Tables.SlopeDiv(c[0], c[1]), c[2], "SlopeDiv " + c[0] + " " + c[1]);
    }
    return true;
}

(:test)
function testTables(logger as Test.Logger) as Boolean {
    Tables.Tables_Init();
    Test.assertEqual(Tables.finesine.size(), 10240);
    Test.assertEqual(Tables.finetangent.size(), 4096);
    Test.assertEqual(Tables.tantoangle.size(), 2049);
    // finecosine[0] is finesine[FINEANGLES/4], i.e. cos(0) ~= FRACUNIT.
    Test.assertEqual(Tables.finesine[Tables.FINECOSINE], 65535);
    Test.assertEqual(Tables.tantoangle[Tables.SLOPERANGE], Tables.ANG45);
    return true;
}

// The 32-bit FixedMul has to agree with the Long version everywhere,
// including the wraparound cases.
(:test)
function testFixedMulMatchesLong(logger as Test.Logger) as Boolean {
    var x = 12345;
    for (var i = 0; i < 4000; i++) {
        // xorshift for a spread of signs and magnitudes
        x = x ^ (x << 13);
        x = x ^ ((x >> 17) & 0x7fff);
        x = x ^ (x << 5);
        var a = x;
        var b = (x * 1103515245 + 12345) >> (i % 17);
        var want = ((a.toLong() * b) >> 16).toNumber();
        Test.assertEqualMessage(MFixed.FixedMul(a, b), want, "FixedMul " + a + " " + b);
    }
    var edges = [0, 1, -1, 65535, 65536, -65536, 0x7fffffff, 0x80000000, 0x10000, 0x7fff0000];
    for (var i = 0; i < edges.size(); i++) {
        for (var j = 0; j < edges.size(); j++) {
            var a = edges[i];
            var b = edges[j];
            Test.assertEqualMessage(MFixed.FixedMul(a, b), ((a.toLong() * b) >> 16).toNumber(), "edge " + a + " " + b);
        }
    }
    return true;
}
