// Plays DEMO1..3 from doom1.wad through the port, the way Doom checks
// its own determinism, and compares every tic against the original game
// code: test/demo_ref.c plays the same demos with the linuxdoom-1.10
// p_*.c files, and test/gen_demo_expect.py turns its output into
// DemoExpect.mc (a hash of every tic's state plus the full state every
// 250 tics).
//
// The flow is the C's: G_DeferedPlayDemo / G_DoPlayDemo (G_InitNew,
// M_ClearRandom, P_SetupLevel), then per tic G_ReadDemoTiccmd into
// player 0's cmd and P_Ticker, until DEMOMARKER.

import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// true prints every tic's state line ("DEMOn <line>", the format
// demo_ref.c prints) to diff against the C's output by hand
const DEMOTRACE = false;

const DEMOFIELDS = ["tic", "x", "y", "z", "angle", "momx", "momy", "health", "armor",
    "readyweapon", "clip", "prndindex", "leveltime", "thinkers", "mobjs",
    "kills", "items", "secrets", "mobjhash", "sectorhash"];

// mix() in demo_ref.c: rotate left 5, xor in the value
function demoMix(h as Number, v as Number) as Number {
    return ((h << 5) | ((h >> 27) & 0x1F)) ^ v;
}

// print_tic in demo_ref.c. demoMix is written out inline: a call per
// value would be most of the test's time.
function demoState(tic as Number) as Array<Number> {
    var mo = DPlayer.players_mo[0];
    var next = PTick.thinkers_next;
    var funcs = PTick.thinkers_function;
    var mx = PMobj.mobjs_x;
    var my = PMobj.mobjs_y;
    var mz = PMobj.mobjs_z;
    var mangle = PMobj.mobjs_angle;
    var mtype = PMobj.mobjs_type;
    var mstate = PMobj.mobjs_state;
    var mtics = PMobj.mobjs_tics;
    var mhealth = PMobj.mobjs_health;
    var mflags = PMobj.mobjs_flags;
    var mtarget = PMobj.mobjs_target;
    var nthinkers = 0;
    var nmobjs = 0;
    var h = 0;
    for (var t = next[0]; t != 0; t = next[t]) {
        nthinkers++;
        if (funcs[t] == PTick.TF_MOBJ) {
            nmobjs++;
            var target = mtarget[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mx[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ my[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mz[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mangle[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mtype[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mstate[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mtics[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mhealth[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ mflags[t];
            h = ((h << 5) | ((h >> 27) & 0x1F)) ^ (target != -1 ? mtype[target] : -1);
        }
    }
    var mh = h;
    var fh = PSetup.sectors_floorheight;
    var ch = PSetup.sectors_ceilingheight;
    var ll = PSetup.sectors_lightlevel;
    var sp = PSetup.sectors_special;
    var fp = PSetup.sectors_floorpic;
    h = 0;
    for (var i = 0; i < PSetup.numsectors; i++) {
        h = ((h << 5) | ((h >> 27) & 0x1F)) ^ fh[i];
        h = ((h << 5) | ((h >> 27) & 0x1F)) ^ ch[i];
        h = ((h << 5) | ((h >> 27) & 0x1F)) ^ ll[i];
        h = ((h << 5) | ((h >> 27) & 0x1F)) ^ sp[i];
        h = ((h << 5) | ((h >> 27) & 0x1F)) ^ fp[i];
    }
    return [tic, mx[mo], my[mo], mz[mo], mangle[mo],
        PMobj.mobjs_momx[mo], PMobj.mobjs_momy[mo], DPlayer.players_health[0],
        DPlayer.players_armorpoints[0], DPlayer.players_readyweapon[0],
        DPlayer.players_ammo[DoomDef.am_clip], MRandom.prndindex, PTick.leveltime,
        nthinkers, nmobjs, DPlayer.players_killcount[0], DPlayer.players_itemcount[0],
        DPlayer.players_secretcount[0], mh, h];
}

// line_hash in gen_demo_expect.py
function demoHash(state as Array<Number>) as Number {
    var h = 0;
    for (var i = 0; i < state.size(); i++) {
        h = demoMix(h, state[i]);
    }
    return (h ^ (h >> 16)) & 0xFFFF;
}

function demoLine(state as Array<Number>) as String {
    var s = "";
    for (var i = 0; i < state.size(); i++) {
        s += (i > 0 ? " " : "") + state[i];
    }
    return s;
}

function demoLoadLevel() as Void {
    var steps = 0;
    while (!PSetup.P_SetupLevelStep()) {
        steps++;
        Test.assert(steps < 2000);
    }
}

// What the demo being played is checked against, and how far it got.
// Module variables rather than locals: the play code's deepest calls
// (A_Look -> A_Chase -> P_NewChaseDir ... -> P_PointOnLineSide) come
// close to the VM's stack limit, and the test harness's frames are a
// little deeper than the game's (DoomView.tick, D_Tick, D_TickFrame,
// D_RunTics), so the frames under the test function are kept small.
var demoN as Number = 0;
var demoTics as Number = 0;
var demoHashes as String = "";
var demoChecks as Array<Array<Number>> = [] as Array<Array<Number>>;
var demoLimit as Number = -1;
var demoLogger as Test.Logger? = null;
var demoStart as Number = 0;
var demoTic as Number = 0;
var demoCheck as Number = 0;
var demoFirstBad as Number = -1;

// Sets demo n up: G_DeferedPlayDemo, then G_Ticker's ga_playdemo
// (G_DoPlayDemo: G_InitNew, M_ClearRandom, P_SetupLevel). limit stops it
// early, for a quick check; -1 plays it all.
function demoSetup(n as Number, tics as Number, hashes as String, checks as Array<Array<Number>>,
                   limit as Number, logger as Test.Logger) as Void {
    demoStart = System.getTimer();
    demoN = n;
    demoTics = tics;
    demoHashes = hashes;
    demoChecks = checks;
    demoLimit = limit;
    demoLogger = logger;
    demoTic = 0;
    demoCheck = 0;
    demoFirstBad = -1;

    initRender();
    Info.Info_Init();
    PSetup.P_Init();
    DoomStat.gameskill = DoomDef.sk_medium;

    GGame.G_DeferedPlayDemo(n);
    GGame.G_DoPlayDemo();
    Test.assert(GGame.demoplayback);
    demoLoadLevel();
}

// The tic loop: G_Ticker until the demo's over, it's diverged or the
// limit is reached. P_Ticker is P_TickerStart, then P_TickerStep's
// steps written out with the whole thinker list in one go (unit tests
// have no watchdog): one frame less, which the deepest calls need.
function demoRun() as Void {
    while (demoReadTic()) {
        PTick.P_TickerStart();
        PTick.P_RunThinkersStep(0x7FFFFFFF);
        PSpec.P_UpdateSpecials();
        PMobj.P_RespawnSpecials();
        PTick.leveltime++;
        PTick.tickerstage = 0;
        DoomStat.gametic++;
        if (!demoCompare()) {
            break;
        }
    }
}

// G_Ticker up to P_Ticker. False at DEMOMARKER.
function demoReadTic() as Boolean {
    // do player reborns if needed
    if (DPlayer.players_playerstate[0] == DPlayer.PST_REBORN) {
        (demoLogger as Test.Logger).debug("tic " + demoTic + ": reborn, level reloaded");
        GGame.G_DoLoadLevel();
        demoLoadLevel();
    }
    Test.assert(GGame.gameaction == GGame.ga_nothing);

    // get commands
    GGame.G_BuildTiccmd(0);
    GGame.G_ReadDemoTiccmd(0);
    if (!GGame.demoplayback) {
        // DEMOMARKER: G_CheckDemoStatus
        DMain.advancedemo = false;
        return false;
    }
    return true;
}

// Compares the tic's state with the C's: its hash every tic, all fields
// at the checkpoints.
function demoCompare() as Boolean {
    var tic = demoTic;
    var logger = demoLogger as Test.Logger;
    var state = demoState(tic);
    if (DEMOTRACE) {
        System.println("DEMO" + demoN + " " + demoLine(state));
    }
    if (demoFirstBad == -1 && tic < demoTics
        && demoHash(state) != demoHashes.substring(tic * 4, tic * 4 + 4).toNumberWithBase(16)) {
        demoFirstBad = tic;
        logger.error("DEMO" + demoN + ": first divergence at tic " + tic + ", port's state: " + demoLine(state));
    }
    if (demoCheck < demoChecks.size() && demoChecks[demoCheck][0] == tic) {
        var expect = demoChecks[demoCheck];
        for (var i = 0; i < expect.size(); i++) {
            if (state[i] != expect[i]) {
                logger.error("DEMO" + demoN + " tic " + tic + ": " + DEMOFIELDS[i] + " is " + state[i] + ", C has " + expect[i]);
                demoFirstBad = demoFirstBad == -1 ? tic : demoFirstBad;
            }
        }
        demoCheck++;
        if (demoFirstBad != -1) {
            return false;
        }
    }
    demoTic++;
    return demoTic != demoLimit;
}

// Fails at the first tic whose state differs from the C's, naming it,
// and lists the fields that differ at the checkpoint after it.
function demoFinish() as Void {
    (demoLogger as Test.Logger).debug("DEMO" + demoN + ": " + demoTic + " tics in " + (System.getTimer() - demoStart) + " ms");
    Test.assertMessage(demoFirstBad == -1, "DEMO" + demoN + " diverges from the C at tic " + demoFirstBad);
    if (demoLimit == -1) {
        Test.assertEqual(demoTic, demoTics);
        Test.assertEqual(demoCheck, demoChecks.size());
    }
}

(:test)
function testDemo1MatchesC(logger as Test.Logger) as Boolean {
    demoSetup(1, DemoExpect.DEMO1_TICS, DemoExpect.demo1Hashes(), DemoExpect.demo1Checks(), -1, logger);
    demoRun();
    demoFinish();
    return true;
}

(:test)
function testDemo2MatchesC(logger as Test.Logger) as Boolean {
    demoSetup(2, DemoExpect.DEMO2_TICS, DemoExpect.demo2Hashes(), DemoExpect.demo2Checks(), -1, logger);
    demoRun();
    demoFinish();
    return true;
}

(:test)
function testDemo3MatchesC(logger as Test.Logger) as Boolean {
    demoSetup(3, DemoExpect.DEMO3_TICS, DemoExpect.demo3Hashes(), DemoExpect.demo3Checks(), -1, logger);
    demoRun();
    demoFinish();
    return true;
}

// The first 100 tics of DEMO3, a quick check while working on play code.
(:test)
function testDemo3StartMatchesC(logger as Test.Logger) as Boolean {
    demoSetup(3, DemoExpect.DEMO3_TICS, DemoExpect.demo3Hashes(), DemoExpect.demo3Checks(), 100, logger);
    demoRun();
    demoFinish();
    return true;
}
