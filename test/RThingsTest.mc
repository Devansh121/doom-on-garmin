// Expected values come from the original r_things.c code run over the
// same map and sprite data, see test/rthings_ref.c: for each view, the
// vissprites R_AddSprites / R_ProjectSprite make during the BSP walk
// (x1, x2, scale, texturemid, patch, xiscale, startfrac, gz, gzt,
// colormap), then the order R_SortVisSprites puts them in and the
// cliptop / clipbot arrays R_DrawSprite builds for each, all hashed.

import Toybox.Lang;
import Toybox.Test;

function thingsRenderView(view as Array) as Void {
    RMain.R_SetupFrame((view[0] as Number) << 16, (view[1] as Number) << 16, (view[3] as Number) << 16,
                       (Tables.ANG45 / 45) * (view[2] as Number));
    RBsp.R_ClearClipSegs();
    RBsp.R_ClearDrawSegs();
    RPlane.R_ClearPlanes();
    RThings.R_ClearSprites();
    RSegs.work = 0;
    RBsp.R_RenderBSPNode(PSetup.numnodes - 1);
    var budget = 0;
    do {
        budget += 40;
    } while (!RBsp.R_RenderBSPNodeStep(budget));
}

(:test)
function testProjectSpritesMatchesC(logger as Test.Logger) as Boolean {
    initRender();
    loadE1M1();

    // the things P_SpawnMapThing spawned, as in the C reference
    var mobjs = 0;
    for (var t = PTick.thinkers_next[0]; t != 0; t = PTick.thinkers_next[t]) {
        if (PTick.thinkers_function[t] == PTick.TF_MOBJ) {
            mobjs++;
        }
    }
    Test.assertEqual(mobjs, 92);

    var views = [
        // x, y, angle (degrees), z, vissprites, projection hash, sort hash, clip hash
        [1056, -3616, 90, 41, 7, 567622388l, 861019894l, 695490862l],
        [1056, -3616, 0, 41, 2, 452017879l, 31l, 764119716l],
        [1500, -3200, 135, 41, 8, 246028880l, 435140371l, 610759986l],
        [3000, -3000, 180, 41, 3, 243647087l, 1953l, 747825703l],
        [2000, -2500, 270, 41, 1, 850486132l, 0l, 433271767l],
        [1056, -3400, 45, 41, 4, 118121984l, 90336l, 836122768l],
        [1200, -2600, 0, 41, 1, 700508438l, 0l, 304666223l],
        [2900, -3300, 120, 41, 5, 335501415l, 2891680l, 708378859l],
        [1500, -2200, 300, 41, 6, 256864139l, 31520955l, 295351617l],
        [900, -3400, 90, 41, 5, 448245463l, 1936540l, 76565881l],
        [500, -3300, 0, 33, 20, 867866505l, 426506129l, 569954567l]
    ];
    for (var v = 0; v < views.size(); v++) {
        var view = views[v];
        thingsRenderView(view);

        var count = RThings.vissprite_p;
        Test.assertEqualMessage(count, view[4], "vissprites view " + v);
        var trace = [] as Array<Number>;
        for (var s = 0; s < count; s++) {
            trace.addAll([RThings.vissprites_x1[s], RThings.vissprites_x2[s], RThings.vissprites_scale[s],
                          RThings.vissprites_texturemid[s], RThings.vissprites_patch[s], RThings.vissprites_xiscale[s],
                          RThings.vissprites_startfrac[s], RThings.vissprites_gz[s], RThings.vissprites_gzt[s],
                          RThings.vissprites_colormap[s]]);
        }
        Test.assertEqualMessage(hashTrace(trace), view[5], "projection hash view " + v);

        RThings.R_SortVisSpritesStart();
        while (!RThings.R_SortVisSpritesStep()) {
        }
        var order = [] as Array<Number>;
        var clips = [] as Array<Number>;
        if (count > 0) {
            for (var s = RThings.vissprites_next[RThings.VSPRSORTEDHEAD]; s != RThings.VSPRSORTEDHEAD;
                 s = RThings.vissprites_next[s]) {
                order.add(s);
                RThings.R_ClipSprite(s);
                for (var x = RThings.vissprites_x1[s]; x <= RThings.vissprites_x2[s]; x++) {
                    // clipbot / cliptop hold value + 2
                    clips.add(RThings.cliptop[x] - 2);
                    clips.add(RThings.clipbot[x] - 2);
                }
            }
        }
        Test.assertEqualMessage(order.size(), count, "sorted count view " + v);
        Test.assertEqualMessage(hashTrace(order), view[6], "sort hash view " + v);
        Test.assertEqualMessage(hashTrace(clips), view[7], "clip hash view " + v);
    }
    return true;
}

// One sprite partly behind the edge of a solid wall: columns 41..53 are
// hidden (cliptop = screenheightarray, clipbot = negonearray), the rest
// open.
(:test)
function testSpriteClipBehindWallEdge(logger as Test.Logger) as Boolean {
    initRender();
    loadE1M1();
    thingsRenderView([900, -3400, 90, 41]);

    var spr = 1;
    Test.assertEqual(RThings.vissprites_x1[spr], 28);
    Test.assertEqual(RThings.vissprites_x2[spr], 53);
    RThings.R_ClipSprite(spr);
    for (var x = 28; x <= 53; x++) {
        var open = x <= 40;
        Test.assertEqualMessage(RThings.cliptop[x] - 2, open ? -1 : 200, "cliptop " + x);
        Test.assertEqualMessage(RThings.clipbot[x] - 2, open ? 200 : -1, "clipbot " + x);
    }

    // Drawing it clips to the open columns: one strip, 28..40.
    RThings.drawtrace = [] as Array<Number>;
    RThings.R_DrawSprite(spr);
    var trace = RThings.drawtrace as Array<Number>;
    RThings.drawtrace = null;
    Test.assertEqual(trace.size(), 5);
    Test.assertEqual(trace[0], RThings.vissprites_patch[spr]);
    Test.assertEqual(trace[1], 28);
    Test.assertEqual(trace[2], 40);
    return true;
}

// The whole masked pass, sprites and psprites, runs through in budgeted
// steps.
(:test)
function testDrawMaskedSteps(logger as Test.Logger) as Boolean {
    initRender();
    // a fresh player, as G_InitNew leaves it, so the pistol gets drawn
    GGame.G_PlayerReborn(0);
    DPlayer.players_playerstate[0] = DPlayer.PST_REBORN;
    loadE1M1();
    // raised all the way (WEAPONTOP) rather than still coming up
    Test.assert(DPlayer.players_psprites_state[DPlayer.ps_weapon] >= 0);
    DPlayer.players_psprites_sy[DPlayer.ps_weapon] = 32 << 16;
    thingsRenderView([500, -3300, 0, 33]);
    RThings.drawtrace = [] as Array<Number>;
    var steps = 0;
    while (!RThings.R_DrawMaskedStep(RSegs.work + 20)) {
        steps++;
        Test.assert(steps < 1000);
    }
    var trace = RThings.drawtrace as Array<Number>;
    RThings.drawtrace = null;
    Test.assert(steps > 1);
    // 20 sprites, most hidden or off to the side, then the pistol
    Test.assert(trace.size() / 5 >= 9);
    Test.assertEqual(trace[trace.size() - 5], 8);
    return true;
}
