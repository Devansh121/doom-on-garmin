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
                GGame.G_InitNew(DoomStat.gameskill, 1, 1);
                startupstep++;
            }
            return;
        }
        if (s == 2) {
            if (PSetup.P_SetupLevelStep()) {
                System.println("P_SetupLevel: E1M1 done, " + System.getSystemStats().usedMemory + " bytes used");
                startupstep++;
                started = true;
                fpsstart = System.getTimer();
            }
            return;
        }
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
                // G_Ticker: build the player's command and start the tic
                GGame.G_BuildTiccmd(DPlayer.consoleplayer);
                PTick.P_TickerStart();
                ticrunning = true;
            }
            if (!PTick.P_TickerStep(budget)) {
                return false;
            }
            budget = PTick.budgetleft;
            ticrunning = false;
            ticsleft--;
            DoomStat.gametic++;

            // G_DoReborn: single player just reloads the level
            if (DPlayer.players_playerstate[DPlayer.consoleplayer] == DPlayer.PST_REBORN) {
                GGame.G_DoLoadLevel();
                startupstep = 2;
                started = false;
                return false;
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
            D_StartFrame();
            return true;
        }
        return false;
    }
}
