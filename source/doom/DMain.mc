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
// Until p_user/p_map are ported the view just flies around: no
// collision, view height follows the floor.

import Toybox.Lang;
import Toybox.System;

module DMain {

    // How much rendering one tick may do, in RSegs.work units.
    const RENDERBUDGET = 450;

    // startup progress
    var startupstep as Number = 0;
    var started as Boolean = false;

    // frame state
    var rendering as Boolean = false;
    var framedone as Boolean = false;

    // the stand-in player
    var px as Number = 0;
    var py as Number = 0;
    var pz as Number = 0;
    var pangle as Number = 0;

    // input, set by the view's delegate: -1, 0 or 1
    var forward as Number = 0;
    var turn as Number = 0;

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
                PSetup.P_SetupLevel(1, 1);
                startupstep++;
            }
            return;
        }
        if (s == 2) {
            if (PSetup.P_SetupLevelStep()) {
                System.println("P_SetupLevel: E1M1 done, " + System.getSystemStats().usedMemory + " bytes used");
                G_StartPlayer();
                startupstep++;
                started = true;
                fpsstart = System.getTimer();
            }
            return;
        }
    }

    // P_SpawnPlayer's position and angle, until there's a real mobj.
    function G_StartPlayer() as Void {
        var start = DoomStat.playerstarts[0] as Array<Number>;
        px = start[0] << MFixed.FRACBITS;
        py = start[1] << MFixed.FRACBITS;
        pangle = Tables.ANG45 * (start[2] / 45);
        P_ViewHeight();
    }

    function P_ViewHeight() as Void {
        var ss = RMain.R_PointInSubsector(px, py);
        pz = PSetup.sectors_floorheight[PSetup.subsectors_sector[ss]] + PLocal.VIEWHEIGHT;
    }

    // One game tic of the stand-in movement. angleturn and walking speed
    // are roughly what g_game.c / p_user.c give a walking player.
    function G_Ticker() as Void {
        if (turn != 0) {
            pangle -= turn * (640 << 16);
        }
        if (forward != 0) {
            var fine = (pangle >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;
            var speed = forward * 8 * MFixed.FRACUNIT;
            px += MFixed.FixedMul(speed, Tables.finesine[Tables.FINECOSINE + fine]);
            py += MFixed.FixedMul(speed, Tables.finesine[fine]);
            P_ViewHeight();
        }
    }

    //
    // D_Tick: called from the view's timer. Returns true when a finished
    // frame is ready to show.
    //
    function D_Tick() as Boolean {
        if (!started) {
            D_DoomMainStep();
            return true;
        }

        ticks++;
        if (!rendering) {
            // Game logic only runs between frames so a frame never shows a
            // half-moved view.
            G_Ticker();
            RMain.R_RenderPlayerView(px, py, pz, pangle);
            rendering = true;
        }

        if (RMain.R_RenderPlayerViewStep(RENDERBUDGET)) {
            rendering = false;
            frames++;
            var now = System.getTimer();
            if (now - fpsstart >= 2000) {
                fps = frames * 1000 / (now - fpsstart);
                frames = 0;
                fpsstart = now;
            }
            return true;
        }
        return false;
    }
}
