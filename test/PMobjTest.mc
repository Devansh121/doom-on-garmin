import Toybox.Lang;
import Toybox.Test;

(:test)
function testSpawnAndRemoveMobj(logger as Test.Logger) as Boolean {
    initRender();
    Info.Info_Init();
    loadE1M1();

    var x = 1056 << 16;
    var y = -3616 << 16;
    var mo = PMobj.P_SpawnMobj(x, y, PMobj.ONFLOORZ, Info.MT_TROOP);
    var ss = RMain.R_PointInSubsector(x, y);
    var sec = PSetup.subsectors_sector[ss];

    Test.assertEqual(PMobj.mobjs_subsector[mo], ss);
    Test.assertEqual(PMobj.mobjs_z[mo], PSetup.sectors_floorheight[sec]);
    Test.assertEqual(PMobj.mobjs_health[mo], 60);
    Test.assertEqual(PSetup.sectors_thinglist[sec], mo);
    Test.assertEqual(PTick.thinkers_next[PTick.thinkers_prev[0]], 0);
    Test.assertEqual(PTick.thinkers_prev[0], mo);

    // a second one goes on the front of the sector list
    var mo2 = PMobj.P_SpawnMobj(x, y, PMobj.ONFLOORZ, Info.MT_POSSESSED);
    Test.assertEqual(PSetup.sectors_thinglist[sec], mo2);
    Test.assertEqual(PMobj.mobjs_snext[mo2], mo);

    PMobj.P_RemoveMobj(mo2);
    Test.assertEqual(PSetup.sectors_thinglist[sec], mo);
    Test.assertEqual(PTick.thinkers_function[mo2], PTick.TF_REMOVED);

    // the removed thinker is freed when its turn comes
    var free = PTick.numfree;
    PTick.P_RunThinkers();
    while (!PTick.P_RunThinkersStep(16)) {
    }
    Test.assertEqual(PTick.numfree, free + 1);
    Test.assertEqual(PTick.thinkers_prev[0], mo);
    return true;
}

// Starts a new game at sk_medium on E1M1 the way the app does, through
// G_InitNew, and runs the level setup to the end.
function newGameE1M1() as Void {
    if (Info.mobjinfo.size() == 0) {
        Info.Info_Init();
    }
    GGame.G_InitNew(DoomDef.sk_medium, 1, 1);
    var steps = 0;
    while (!PSetup.P_SetupLevelStep()) {
        steps++;
        Test.assert(steps < 1000);
    }
}

(:test)
function testSpawnMapThingsE1M1(logger as Test.Logger) as Boolean {
    initRender();
    newGameE1M1();

    // Worked out from the THINGS lump with P_SpawnMapThing's rules for
    // sk_medium: of 138 things, 5 deathmatch starts, 3 starts for other
    // players (not in game), 14 multiplayer only (options & 16) and 24
    // without the MTF_NORMAL bit are skipped, leaving 91 plus player 1.
    var count = 0;
    var mobjs = 0;
    for (var t = PTick.thinkers_next[0]; t != 0; t = PTick.thinkers_next[t]) {
        count++;
        if (PTick.thinkers_function[t] == PTick.TF_MOBJ) {
            mobjs++;
        }
    }
    Test.assertEqual(mobjs, 92);
    Test.assertEqual(count, 92);
    Test.assertEqual(DoomStat.totalkills, 6);
    Test.assertEqual(DoomStat.totalitems, 37);

    // P_SpawnPlayer: player 1 at its start, reborn by G_InitNew
    var start = DoomStat.playerstarts[0] as Array<Number>;
    Test.assertEqual(start[0], 1056);
    Test.assertEqual(start[1], -3616);
    var mo = DPlayer.players_mo[0];
    Test.assert(mo != -1);
    Test.assertEqual(PMobj.mobjs_type[mo], Info.MT_PLAYER);
    Test.assertEqual(PMobj.mobjs_player[mo], 0);
    Test.assertEqual(PMobj.mobjs_x[mo], 1056 << 16);
    Test.assertEqual(PMobj.mobjs_y[mo], -3616 << 16);
    Test.assertEqual(PMobj.mobjs_angle[mo], Tables.ANG90);
    var sec = PSetup.subsectors_sector[PMobj.mobjs_subsector[mo]];
    Test.assertEqual(PMobj.mobjs_z[mo], PSetup.sectors_floorheight[sec]);
    Test.assertEqual(PMobj.mobjs_health[mo], 100);
    Test.assertEqual(DPlayer.players_health[0], 100);
    Test.assertEqual(DPlayer.players_playerstate[0], DPlayer.PST_LIVE);
    Test.assertEqual(DPlayer.players_viewheight[0], PLocal.VIEWHEIGHT);
    Test.assertEqual(DPlayer.players_readyweapon[0], DoomDef.wp_pistol);
    Test.assertEqual(DPlayer.players_weaponowned[DoomDef.wp_fist], 1);
    Test.assertEqual(DPlayer.players_weaponowned[DoomDef.wp_pistol], 1);
    Test.assertEqual(DPlayer.players_weaponowned[DoomDef.wp_shotgun], 0);
    Test.assertEqual(DPlayer.players_ammo[DoomDef.am_clip], 50);
    Test.assertEqual(DPlayer.players_ammo[DoomDef.am_shell], 0);
    Test.assertEqual(DPlayer.players_maxammo[DoomDef.am_clip], 200);
    Test.assertEqual(DPlayer.players_maxammo[DoomDef.am_misl], 50);
    return true;
}

// Stand-in PIT_* function for P_BlockThingsIterator, like
// BlockLineCounter in MapUtlTest.mc.
class BlockThingCounter {
    var visits as Number = 0;
    var visitsum as Long = 0l;
    var stopafter as Number = 0;

    function initialize(stop as Number) {
        stopafter = stop;
    }

    function count(thing as Number) as Boolean {
        visits++;
        visitsum += visits.toLong() * thing;
        return visits != stopafter;
    }
}

// Expected values for the next three tests come from the original C
// functions, see test/mobj_ref.c.

(:test)
function testBlockThingsIterator(logger as Test.Logger) as Boolean {
    initRender();
    newGameE1M1();
    var blocks = [
        // x, y, stopafter, result, visits, visitsum
        [23, 19, 0, 1, 4, 592],
        [23, 19, 2, 0, 2, 183],
        [14, 9, 0, 1, 1, 1],
        [0, 0, 0, 1, 0, 0],
        [-1, 0, 0, 1, 0, 0],
        [0, -1, 0, 1, 0, 0],
        [36, 0, 0, 1, 0, 0],
        [0, 23, 0, 1, 0, 0]
    ];
    for (var i = 0; i < blocks.size(); i++) {
        var c = blocks[i];
        var counter = new BlockThingCounter(c[2]);
        var r = PMapUtl.P_BlockThingsIterator(c[0], c[1], counter.method(:count));
        Test.assertEqualMessage(r ? 1 : 0, c[3], "result " + i);
        Test.assertEqualMessage(counter.visits, c[4], "visits " + i);
        Test.assertEqualMessage(counter.visitsum, c[5].toLong(), "visitsum " + i);
    }

    // every block once
    var counter = new BlockThingCounter(0);
    for (var y = 0; y < PSetup.bmapheight; y++) {
        for (var x = 0; x < PSetup.bmapwidth; x++) {
            PMapUtl.P_BlockThingsIterator(x, y, counter.method(:count));
        }
    }
    Test.assertEqual(counter.visits, 92);
    Test.assertEqual(counter.visitsum, 208121l);
    return true;
}

// Traverser for P_PathTraverse: checksums the intercepts it is handed in
// order and stops after stopafter.
class InterceptCounter {
    var count as Number = 0;
    var sum as Long = 0l;
    var stopafter as Number = 0;

    function initialize(stop as Number) {
        stopafter = stop;
    }

    function trav(inp as Number) as Boolean {
        count++;
        var isaline = PMapUtl.intercepts_isaline[inp];
        sum += count.toLong() * (PMapUtl.intercepts_frac[inp].toLong() + (isaline ? 1000003l : 0l)
            + 7919l * PMapUtl.intercepts_d[inp]);
        return count != stopafter;
    }
}

(:test)
function testPathTraverse(logger as Test.Logger) as Boolean {
    initRender();
    newGameE1M1();
    // From the player start, from the busiest thing block and from a
    // block corner (nudged off the block lines). The earlyout trace from
    // the start hits a solid wall right away.
    var traces = [
        // x1, y1, x2, y2, flags, stopafter, result, intercepts, calls, checksum
        [69206016, -236978176, 203423744, -236978176, 3, 0, 1, 6, 6, 44258753l],
        [69206016, -236978176, 69206016, -102760448, 3, 0, 1, 6, 6, 27982614l],
        [69206016, -236978176, -29097984, -151781376, 3, 0, 1, 7, 7, 29186336l],
        [69206016, -236978176, 200278016, -282853376, 3, 0, 1, 14, 14, 210905700l],
        [69206016, -236978176, 200278016, -282853376, 7, 0, 0, 0, 0, 0l],
        [69206016, -236978176, 203423744, -236978176, 1, 3, 0, 5, 3, 11064319l],
        [69206016, -236978176, 69861376, -236584960, 3, 0, 1, 1, 1, 7919l],
        [69206016, -236978176, 68419584, -237961216, 1, 0, 1, 0, 0, 0l],
        [144703488, -155320320, 262668288, -96337920, 3, 0, 1, 7, 7, 95416770l],
        [144703488, -155320320, 77594624, -289538048, 2, 0, 1, 0, 0, 0l],
        [144703488, -155320320, 164364288, -289538048, 7, 0, 0, 1, 0, 0l],
        [-8912896, -243793920, 58195968, -210239488, 3, 0, 1, 10, 8, 51646853l]
    ];
    for (var i = 0; i < traces.size(); i++) {
        var c = traces[i];
        var counter = new InterceptCounter(c[5]);
        var r = PMapUtl.P_PathTraverse(c[0], c[1], c[2], c[3], c[4], counter.method(:trav));
        Test.assertEqualMessage(r ? 1 : 0, c[6], "result " + i);
        Test.assertEqualMessage(PMapUtl.intercept_p, c[7], "intercepts " + i);
        Test.assertEqualMessage(counter.count, c[8], "calls " + i);
        Test.assertEqualMessage(counter.sum, c[9], "checksum " + i);
    }
    return true;
}

// P_XYMovement from PMobj.mc with only P_TryMove swapped for a stub that
// always succeeds (moves the mobj, no relinking), like in mobj_ref.c.
// That way the friction and momentum decay can be checked without
// p_map.c.
function XYMovementFreeMove(mo as Number) as Void {
    var mobjs_x = PMobj.mobjs_x;
    var mobjs_y = PMobj.mobjs_y;
    var mobjs_z = PMobj.mobjs_z;
    var mobjs_momx = PMobj.mobjs_momx;
    var mobjs_momy = PMobj.mobjs_momy;
    var mobjs_momz = PMobj.mobjs_momz;
    var mobjs_flags = PMobj.mobjs_flags;
    var mobjs_floorz = PMobj.mobjs_floorz;
    var ptryx;
    var ptryy;
    var player;
    var xmove;
    var ymove;

    if (mobjs_momx[mo] == 0 && mobjs_momy[mo] == 0) {
        if ((mobjs_flags[mo] & PMobj.MF_SKULLFLY) != 0) {
            // the skull slammed into something
            mobjs_flags[mo] &= ~PMobj.MF_SKULLFLY;
            mobjs_momx[mo] = 0;
            mobjs_momy[mo] = 0;
            mobjs_momz[mo] = 0;

            PMobj.P_SetMobjState(mo, PMobj.info(mo, Info.MI_SPAWNSTATE));
        }
        return;
    }

    player = PMobj.mobjs_player[mo];

    if (mobjs_momx[mo] > PLocal.MAXMOVE) {
        mobjs_momx[mo] = PLocal.MAXMOVE;
    } else if (mobjs_momx[mo] < -PLocal.MAXMOVE) {
        mobjs_momx[mo] = -PLocal.MAXMOVE;
    }

    if (mobjs_momy[mo] > PLocal.MAXMOVE) {
        mobjs_momy[mo] = PLocal.MAXMOVE;
    } else if (mobjs_momy[mo] < -PLocal.MAXMOVE) {
        mobjs_momy[mo] = -PLocal.MAXMOVE;
    }

    xmove = mobjs_momx[mo];
    ymove = mobjs_momy[mo];

    do {
        if (xmove > PLocal.MAXMOVE / 2 || ymove > PLocal.MAXMOVE / 2) {
            ptryx = mobjs_x[mo] + xmove / 2;
            ptryy = mobjs_y[mo] + ymove / 2;
            xmove >>= 1;
            ymove >>= 1;
        } else {
            ptryx = mobjs_x[mo] + xmove;
            ptryy = mobjs_y[mo] + ymove;
            xmove = 0;
            ymove = 0;
        }

        // P_TryMove stub: always succeeds
        mobjs_x[mo] = ptryx;
        mobjs_y[mo] = ptryy;
    } while (xmove != 0 || ymove != 0);

    // slow down
    if (player != -1 && (DPlayer.players_cheats[player] & DPlayer.CF_NOMOMENTUM) != 0) {
        // debug option for no sliding at all
        mobjs_momx[mo] = 0;
        mobjs_momy[mo] = 0;
        return;
    }

    if ((mobjs_flags[mo] & (PMobj.MF_MISSILE | PMobj.MF_SKULLFLY)) != 0) {
        return;     // no friction for missiles ever
    }

    if (mobjs_z[mo] > mobjs_floorz[mo]) {
        return;     // no friction when airborne
    }

    if ((mobjs_flags[mo] & PMobj.MF_CORPSE) != 0) {
        // do not stop sliding
        //  if halfway off a step with some momentum
        if (mobjs_momx[mo] > MFixed.FRACUNIT / 4
            || mobjs_momx[mo] < -MFixed.FRACUNIT / 4
            || mobjs_momy[mo] > MFixed.FRACUNIT / 4
            || mobjs_momy[mo] < -MFixed.FRACUNIT / 4) {
            if (mobjs_floorz[mo] != PSetup.sectors_floorheight[PSetup.subsectors_sector[PMobj.mobjs_subsector[mo]]]) {
                return;
            }
        }
    }

    if (mobjs_momx[mo] > -PMobj.STOPSPEED
        && mobjs_momx[mo] < PMobj.STOPSPEED
        && mobjs_momy[mo] > -PMobj.STOPSPEED
        && mobjs_momy[mo] < PMobj.STOPSPEED
        && (player == -1
            || (DPlayer.players_cmd_forwardmove[player] == 0
                && DPlayer.players_cmd_sidemove[player] == 0))) {
        // if in a walking frame, stop moving
        if (player != -1
            && DoomType.ULT(PMobj.mobjs_state[DPlayer.players_mo[player]] - Info.S_PLAY_RUN1, 4)) {
            PMobj.P_SetMobjState(DPlayer.players_mo[player], Info.S_PLAY);
        }

        mobjs_momx[mo] = 0;
        mobjs_momy[mo] = 0;
    } else {
        mobjs_momx[mo] = MFixed.FixedMul(mobjs_momx[mo], PMobj.FRICTION);
        mobjs_momy[mo] = MFixed.FixedMul(mobjs_momy[mo], PMobj.FRICTION);
    }
}

(:test)
function testXYMovementFriction(logger as Test.Logger) as Boolean {
    initRender();
    loadE1M1();
    // A free mobj at the player start: plain friction, a diagonal, one
    // over MAXMOVE (clamped, then moved in two halves), one just over
    // STOPSPEED, airborne and missiles (no friction) and a corpse.
    // z is relative to the floor.
    var moves = [
        // momx, momy, z, flags, tics, x, y, momx, momy, tics until stopped
        [524288, 196608, 0, 0, 60, 74761315, -234895087, 0, 0, 51],
        [-327680, 459986, 0, 0, 60, 65738693, -232111309, 0, 0, 49],
        [3276800, -2949120, 0, 0, 60, 90120200, -257892856, 5345, -5355, -1],
        [1310720, 1310720, 0, 0, 3, 72781056, -233403136, 975560, 975560, -1],
        [4097, -4095, 0, 0, 3, 69213825, -236985983, 0, 0, 2],
        [393216, 0, 524288, 0, 3, 70385664, -236978176, 393216, 0, -1],
        [393216, 131072, 0, 65536, 3, 70385664, -236584960, 393216, 131072, -1],
        [65536, 32768, 0, 1048576, 60, 69868489, -236646967, 0, 0, 30]
    ];
    var x = 1056 << 16;
    var y = -3616 << 16;
    for (var i = 0; i < moves.size(); i++) {
        var c = moves[i];
        var mo = PMobj.P_SpawnMobj(x, y, PMobj.ONFLOORZ, Info.MT_BARREL);
        var floor = PMobj.mobjs_floorz[mo];
        PMobj.mobjs_z[mo] = floor + c[2];
        PMobj.mobjs_flags[mo] = c[3];
        PMobj.mobjs_momx[mo] = c[0];
        PMobj.mobjs_momy[mo] = c[1];
        var stopped = -1;
        for (var j = 0; j < c[4]; j++) {
            XYMovementFreeMove(mo);
            if (stopped < 0 && PMobj.mobjs_momx[mo] == 0 && PMobj.mobjs_momy[mo] == 0) {
                stopped = j + 1;
            }
        }
        Test.assertEqualMessage(PMobj.mobjs_x[mo], c[5], "x " + i);
        Test.assertEqualMessage(PMobj.mobjs_y[mo], c[6], "y " + i);
        Test.assertEqualMessage(PMobj.mobjs_momx[mo], c[7], "momx " + i);
        Test.assertEqualMessage(PMobj.mobjs_momy[mo], c[8], "momy " + i);
        Test.assertEqualMessage(stopped, c[9], "stopped " + i);
    }
    return true;
}
