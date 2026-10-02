// d_main.c
//
// DOOM main program (D_DoomMain) and game loop (D_DoomLoop),
// plus functions to determine game mode (shareware, registered),
// parse command line parameters, configure game parameters (turbo),
// and call the startup functions.
//
// There's no loop to sit in on Connect IQ: the app gets a timer callback
// and must return quickly. D_DoomMain is a list of startup steps run one
// per tick, and after that each tick does a slice of the frame (see
// D_Tick). The frame only gets shown once it's finished.
//

import Toybox.Lang;
import Toybox.System;

(:extendedCode)
module DMain {

    // How much rendering one tick may do, in RSegs.work units.
    const RENDERBUDGET = 450;

    // How many thinkers one tick may run.
    const THINKBUDGET = 128;

    // startup progress
    var startupstep as Number = 0;
    var started as Boolean = false;

    // frame state
    var rendering as Boolean = false;
    var framedone as Boolean = false;



    // stats for the overlay
    var frames as Number = 0;
    var fps as Number = 0;
    var fpsstart as Number = 0;
    var ticks as Number = 0;

    // Timing for the overlay, per frame: wall-clock ms, ms spent in tics
    // and in rendering, and how many callbacks the frame took.
    var framestart as Number = 0;
    var ticms as Number = 0;
    var renderms as Number = 0;
    var callbacks as Number = 0;
    var lastframems as Number = 0;
    var lastticms as Number = 0;
    var lastrenderms as Number = 0;
    var lastcallbacks as Number = 0;

    function D_Stats() as String {
        return lastframems + "ms T" + lastticms + " R" + lastrenderms + " cb" + lastcallbacks;
    }

    function D_StartupMessage() as String {
        return started ? "" : "Loading " + startupstep;
    }

    //
    // D_DoomMain, one step per call.
    //
    function D_DoomMainStep() as Void {
        var s = startupstep;
        if (s == 0) {
            System.println("Tables_Init: Init trig tables.");
            Tables.Tables_Init();
            startupstep++;
            return;
        }
        if (s == 1) {
            if (RMain.R_InitStep()) {
                System.println("R_Init: Init DOOM refresh daemon.");
                Info.Info_Init();
                System.println("P_Init: Init Playloop state.");
                PSetup.P_Init();
                if (DEMO != 0) {
                    // D_DoAdvanceDemo's G_DeferedPlayDemo, and the
                    // G_DoPlayDemo the next G_Ticker would do
                    GGame.G_DeferedPlayDemo(DEMO);
                    GGame.G_DoPlayDemo();
                } else {
                    GGame.G_InitNew(DoomStat.gameskill, 1, 1);
                }
                startupstep++;
            }
            return;
        }
        if (s == 2) {
            if (PSetup.P_SetupLevelStep()) {
                System.println("P_SetupLevel: E" + DoomStat.gameepisode + "M" + DoomStat.gamemap + " done, " + System.getSystemStats().usedMemory + " bytes used");
                startupstep++;
                started = true;
                fpsstart = System.getTimer();
            }
            return;
        }
    }

    //
    // DEMO LOOP
    //
    // Which demo to play instead of starting E1M1: 0 for none (the
    // normal game), 1..3 for DEMO1..3. build.sh sets it from DOOM_DEMO
    // in generated/source/DemoConfig.mc.
    const DEMO = DemoConfig.DEMO;

    var advancedemo as Boolean = false;

    //
    // D_AdvanceDemo
    // Called after each demo or intro demosequence finishes
    //
    function D_AdvanceDemo() as Void {
        advancedemo = true;
    }

    //
    // This cycles through the demo sequences.
    // There are no title, credit or help pages on the watch, so this
    // goes straight on to the next demo: DEMO1, DEMO2, DEMO3, DEMO1...
    //
    function D_DoAdvanceDemo() as Void {
        advancedemo = false;
        GGame.G_DeferedPlayDemo(GGame.defdemoname % 3 + 1);
        GGame.G_DoPlayDemo();
    }

    //
    // D_DoomLoop
    //
    // Each frame: run the game tics that are due (G_Ticker / P_Ticker),
    // then render, each spread over as many timer callbacks as the
    // watchdog needs. TryRunTics' job of keeping game time in step with
    // real time is done by running up to MAXTICS tics per frame.
    //
    const MAXTICS = 3;

    // phases of a frame
    const PH_TICS = 0;
    const PH_RENDER = 1;
    var phase as Number = PH_TICS;
    var ticsleft as Number = 0;
    var ticrunning as Boolean = false;
    var lasttime as Number = 0;

    function D_StartFrame() as Void {
        var now = System.getTimer();
        var due = (now - lasttime) * DoomDef.TICRATE / 1000;
        if (due < 1) {
            due = 1;
        } else if (due > MAXTICS) {
            due = MAXTICS;
        }
        lasttime = now;
        ticsleft = due;
        phase = PH_TICS;
    }

    // Runs this frame's due tics with the thinker budget for one
    // callback. Returns true once they've all run, leaving whatever budget
    // is unused in PTick.budgetleft.
    function D_RunTics(budget as Number) as Boolean {
        while (ticsleft > 0) {
            if (!ticrunning) {
                // G_Ticker: build the player's command and start the tic.
                // A demo's ticcmd replaces it, like G_Ticker does with
                // netcmds; on the demo's last tic it doesn't.
                GGame.G_BuildTiccmd(DPlayer.consoleplayer);
                if (GGame.demoplayback) {
                    GGame.G_ReadDemoTiccmd(DPlayer.consoleplayer);
                }
                PTick.P_TickerStart();
                ticrunning = true;
            }
            if (!PTick.P_TickerStep(budget)) {
                return false;
            }
            budget = PTick.budgetleft;
            ticrunning = false;
            // rest of G_Ticker's GS_LEVEL case, after P_Ticker
            StStuff.ST_Ticker();
            HuStuff.HU_Ticker();
            ticsleft--;
            DoomStat.gametic++;

            // D_PageTicker / D_DoAdvanceDemo: the demo is over, play
            // the next one
            if (advancedemo) {
                D_DoAdvanceDemo();
                startupstep = 2;
                started = false;
                return false;
            }

            // G_DoReborn: single player just reloads the level
            if (DPlayer.players_playerstate[DPlayer.consoleplayer] == DPlayer.PST_REBORN) {
                GGame.G_DoLoadLevel();
                startupstep = 2;
                started = false;
                return false;
            }

            // G_Ticker's gameaction: a level was finished
            if (GGame.gameaction == GGame.ga_completed) {
                if (GGame.G_DoCompleted()) {
                    startupstep = 2;
                    started = false;
                    return false;
                }
            }
        }
        PTick.budgetleft = budget;
        return true;
    }

    //
    // D_Tick: called from the view's timer. Returns true when a finished
    // frame is ready to show.
    //
    function D_Tick() as Boolean {
        if (!started) {
            D_DoomMainStep();
            if (started) {
                lasttime = System.getTimer();
                D_StartFrame();
            }
            return true;
        }

        ticks++;
        callbacks++;
        var t0 = System.getTimer();
        var result = D_TickFrame();
        var spent = System.getTimer() - t0;
        if (phase == PH_TICS && !result) {
            ticms += spent;
        } else {
            renderms += spent;
        }
        return result;
    }

    function D_TickFrame() as Boolean {
        // One budget per callback: tics first, then whatever is left
        // goes to rendering, so a callback doesn't end half used.
        var renderbudget = RENDERBUDGET;
        if (phase == PH_TICS) {
            if (!D_RunTics(THINKBUDGET)) {
                return !started;
            }
            RMain.R_RenderPlayerView(DPlayer.consoleplayer);
            phase = PH_RENDER;
            renderbudget = RENDERBUDGET * PTick.budgetleft / THINKBUDGET;
            if (renderbudget <= 0) {
                return false;
            }
        }

        if (RMain.R_RenderPlayerViewStep(renderbudget)) {
            frames++;
            var now = System.getTimer();
            if (now - fpsstart >= 2000) {
                fps = frames * 1000 / (now - fpsstart);
                frames = 0;
                fpsstart = now;
            }
            var t = System.getTimer();
            lastframems = t - framestart;
            framestart = t;
            lastticms = ticms;
            lastrenderms = renderms;
            lastcallbacks = callbacks;
            D_LogFrame();
            RMain.bspms = 0;
            RMain.maskedms = 0;
            ticms = 0;
            renderms = 0;
            callbacks = 0;
            D_StartFrame();
            return true;
        }
        return false;
    }

    // One line per frame in debug builds: the simulator's console, or on
    // the watch GARMIN/APPS/LOGS/<app>.TXT if that file exists. Release
    // builds (-r) leave it out.
    (:debug)
    function D_LogFrame() as Void {
        System.println("FRAME F=" + lastframems + " T=" + lastticms + " R=" + lastrenderms
            + " bsp=" + RMain.bspms + " masked=" + RMain.maskedms + " cb=" + lastcallbacks
            + " tic=" + DoomStat.gametic);
    }

    (:release)
    function D_LogFrame() as Void {
    }
}
