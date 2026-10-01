// Expected values come from the original r_segs.c / r_plane.c code run
// over the same data, see test/rsegs_ref.c: every wall column and every
// floor/ceiling span marked, hashed in order.

import Toybox.Lang;
import Toybox.Test;

function hashTrace(trace as Array<Number>) as Long {
    var m = 1000000007l;
    var h = 0l;
    for (var i = 0; i < trace.size(); i++) {
        var v = trace[i].toLong();
        h = (h * 31 + ((v % m) + m)) % m;
    }
    return h;
}

(:test)
function testRenderSegsMatchesC(logger as Test.Logger) as Boolean {
    initRender();
    loadE1M1();

    var views = [
        // x, y, angle (degrees), draw calls, hash
        [1056, -3616, 90, 986, 826471027l],
        [1056, -3616, 0, 429, 396507715l],
        [1500, -3200, 135, 799, 198944915l],
        [3000, -3000, 180, 780, 90467688l],
        [2000, -2500, 270, 1005, 806594611l]
    ];
    for (var v = 0; v < views.size(); v++) {
        var view = views[v];
        RMain.R_SetupFrame(view[0] << 16, view[1] << 16, 41 << 16, (Tables.ANG45 / 45) * view[2]);
        RBsp.R_ClearClipSegs();
        RBsp.R_ClearDrawSegs();
        RPlane.R_ClearPlanes();
        RSegs.work = 0;
        RSegs.drawtrace = [] as Array<Number>;

        RBsp.R_RenderBSPNode(PSetup.numnodes - 1);
        var budget = 0;
        do {
            budget += 40;
        } while (!RBsp.R_RenderBSPNodeStep(budget));

        var trace = RSegs.drawtrace as Array<Number>;
        RSegs.drawtrace = null;
        Test.assertEqualMessage(trace.size() / 6, view[3], "draw calls view " + v);
        Test.assertEqualMessage(hashTrace(trace), view[4], "draw hash view " + v);
    }
    return true;
}
