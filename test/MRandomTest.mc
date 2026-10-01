// Expected values come from the original m_random.c, see
// test/random_ref.c.

import Toybox.Lang;
import Toybox.Test;

(:test)
function testRandomSequence(logger as Test.Logger) as Boolean {
    MRandom.M_ClearRandom();
    var p = [8, 109, 220, 222, 241];
    for (var i = 0; i < p.size(); i++) {
        Test.assertEqualMessage(MRandom.P_Random(), p[i], "P_Random " + i);
    }
    // M_Random has its own index, so it starts over from the top
    var m = [8, 109, 220];
    for (var i = 0; i < m.size(); i++) {
        Test.assertEqualMessage(MRandom.M_Random(), m[i], "M_Random " + i);
    }
    p = [149, 107, 75];
    for (var i = 0; i < p.size(); i++) {
        Test.assertEqualMessage(MRandom.P_Random(), p[i], "P_Random " + (i + 5));
    }
    Test.assertEqual(MRandom.prndindex, 8);
    Test.assertEqual(MRandom.rndindex, 3);
    return true;
}

(:test)
function testRandomWrap(logger as Test.Logger) as Boolean {
    MRandom.M_ClearRandom();
    var sum = 0;
    for (var i = 0; i < 255; i++) {
        sum += MRandom.P_Random();
    }
    Test.assertEqual(sum, 32986);
    // the 256th draw wraps the index back to rndtable[0]
    Test.assertEqual(MRandom.P_Random(), 0);
    Test.assertEqual(MRandom.prndindex, 0);
    Test.assertEqual(MRandom.P_Random(), 8);

    MRandom.M_ClearRandom();
    var w = 0l;
    for (var i = 0; i < 1000; i++) {
        w += MRandom.M_Random().toLong() * (i + 1);
    }
    Test.assertEqual(w, 63888113l);
    Test.assertEqual(MRandom.rndindex, 232);
    Test.assertEqual(MRandom.prndindex, 0);
    return true;
}
