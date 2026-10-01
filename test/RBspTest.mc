// Expected values come from the original r_bsp.c functions, see
// test/rbsp_ref.c: for each view, the subsectors visited and every
// R_StoreWallRange call folded into a checksum.

import Toybox.Lang;
import Toybox.Test;

(:test)
function testRenderBSPNodeMatchesC(logger as Test.Logger) as Boolean {
    initRender();
    loadE1M1();

    var views = [
        // x, y, angle (degrees), sscount, ranges, checksum, first two ranges
        [1056, -3616, 90, 33, 34, 15873412813l, [294, 35, 125, 290, 35, 40]],
        [1056, -3616, 0, 16, 10, 913265916l, [305, 107, 159, 307, 58, 106]],
        [1500, -3200, 135, 34, 34, 16465386138l, [122, 1, 69, 124, 0, 0]],
        [3000, -3000, 180, 26, 23, 7117583623l, [497, 65, 159, 498, 0, 64]],
        [2000, -2500, 270, 13, 16, 2292237020l, [32, 91, 92, 42, 87, 90]],
        [-200, 200, 30, 1, 0, 0l, null]
    ];
    for (var v = 0; v < views.size(); v++) {
        var view = views[v];
        RMain.R_SetupFrame(view[0] << 16, view[1] << 16, 41 << 16, (Tables.ANG45 / 45) * view[2]);
        RBsp.R_ClearClipSegs();
        RBsp.R_ClearDrawSegs();
        RPlane.R_ClearPlanes();
        RSegs.work = 0;
        RSegs.trace = [] as Array<Number>;

        RBsp.R_RenderBSPNode(PSetup.numnodes - 1);
        // Small budget so the walk gets paused and resumed many times.
        var budget = 0;
        do {
            budget += 8;
        } while (!RBsp.R_RenderBSPNodeStep(budget));

        var trace = RSegs.trace as Array<Number>;
        RSegs.trace = null;
        var count = trace.size() / 3;
        var sum = 0l;
        for (var i = 0; i < count; i++) {
            sum += (i + 1).toLong() * (trace[i * 3] * 100000l + trace[i * 3 + 1] * 1000 + trace[i * 3 + 2]);
        }
        Test.assertEqualMessage(RMain.sscount, view[3], "sscount view " + v);
        Test.assertEqualMessage(count, view[4], "range count view " + v);
        Test.assertEqualMessage(sum, view[5], "range checksum view " + v);
        var firsts = view[6] as Array<Number>?;
        if (firsts != null) {
            for (var k = 0; k < 6; k++) {
                Test.assertEqualMessage(trace[k], firsts[k], "range " + k + " view " + v);
            }
        }
    }
    return true;
}
