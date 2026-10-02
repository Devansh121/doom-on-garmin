// g_game.c
//
// DESCRIPTION:  none
//
// Only the parts that set the game and the players up for a level are
// here: G_PlayerReborn, G_InitNew and G_DoLoadLevel, plus demo playback
// (see DEMO PLAYBACK below). There's no demo recording, savegames,
// netgames or menus on the watch.
//
// P_SetupLevel can't load a map in one callback (see PSetup), so
// G_DoLoadLevel only starts it; the caller then runs
// PSetup.P_SetupLevelStep until it returns true.

import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

(:extendedCode)
module GGame {

    // doomstat.h: nightmare mode flag, single player.
    var respawnmonsters as Boolean = false;

    var gamestate as Number = DoomDef.GS_DEMOSCREEN;

    //
    // G_PlayerReborn
    // Called after a player dies
    // almost everything is cleared and initialized
    //
    function G_PlayerReborn(player as Number) as Void {
        var p = player;
        var i;
        var killcount;
        var itemcount;
        var secretcount;

        // (no frags, single player only)
        killcount = DPlayer.players_killcount[player];
        itemcount = DPlayer.players_itemcount[player];
        secretcount = DPlayer.players_secretcount[player];

        // memset (p, 0, sizeof(*p));
        P_ClearPlayer(p);

        DPlayer.players_killcount[player] = killcount;
        DPlayer.players_itemcount[player] = itemcount;
        DPlayer.players_secretcount[player] = secretcount;

        // don't do anything immediately
        DPlayer.players_usedown[p] = 1;
        DPlayer.players_attackdown[p] = 1;
        DPlayer.players_playerstate[p] = DPlayer.PST_LIVE;
        DPlayer.players_health[p] = PLocal.MAXHEALTH;
        DPlayer.players_readyweapon[p] = DoomDef.wp_pistol;
        DPlayer.players_pendingweapon[p] = DoomDef.wp_pistol;
        DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + DoomDef.wp_fist] = 1;
        DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + DoomDef.wp_pistol] = 1;
        DPlayer.players_ammo[p * DoomDef.NUMAMMO + DoomDef.am_clip] = 50;

        for (i = 0; i < DoomDef.NUMAMMO; i++) {
            DPlayer.players_maxammo[p * DoomDef.NUMAMMO + i] = PInter.maxammo[i];
        }
    }

    // memset (&players[p], 0, sizeof(player_t)): every field of player
    // p back to zero, NULL pointers to -1.
    function P_ClearPlayer(p as Number) as Void {
        DPlayer.players_mo[p] = -1;
        DPlayer.players_playerstate[p] = 0;
        DPlayer.players_cmd_forwardmove[p] = 0;
        DPlayer.players_cmd_sidemove[p] = 0;
        DPlayer.players_cmd_angleturn[p] = 0;
        DPlayer.players_cmd_buttons[p] = 0;
        DPlayer.players_viewz[p] = 0;
        DPlayer.players_viewheight[p] = 0;
        DPlayer.players_deltaviewheight[p] = 0;
        DPlayer.players_bob[p] = 0;
        DPlayer.players_health[p] = 0;
        DPlayer.players_armorpoints[p] = 0;
        DPlayer.players_armortype[p] = 0;
        for (var i = 0; i < DoomDef.NUMPOWERS; i++) {
            DPlayer.players_powers[p * DoomDef.NUMPOWERS + i] = 0;
        }
        for (var i = 0; i < DoomDef.NUMCARDS; i++) {
            DPlayer.players_cards[p * DoomDef.NUMCARDS + i] = 0;
        }
        DPlayer.players_backpack[p] = false;
        DPlayer.players_readyweapon[p] = 0;
        DPlayer.players_pendingweapon[p] = 0;
        for (var i = 0; i < DoomDef.NUMWEAPONS; i++) {
            DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + i] = 0;
        }
        for (var i = 0; i < DoomDef.NUMAMMO; i++) {
            DPlayer.players_ammo[p * DoomDef.NUMAMMO + i] = 0;
            DPlayer.players_maxammo[p * DoomDef.NUMAMMO + i] = 0;
        }
        DPlayer.players_attackdown[p] = 0;
        DPlayer.players_usedown[p] = 0;
        DPlayer.players_cheats[p] = 0;
        DPlayer.players_refire[p] = 0;
        DPlayer.players_killcount[p] = 0;
        DPlayer.players_itemcount[p] = 0;
        DPlayer.players_secretcount[p] = 0;
        DPlayer.players_message[p] = null;
        DPlayer.players_damagecount[p] = 0;
        DPlayer.players_bonuscount[p] = 0;
        DPlayer.players_attacker[p] = -1;
        DPlayer.players_extralight[p] = 0;
        DPlayer.players_fixedcolormap[p] = 0;
        DPlayer.players_colormap[p] = 0;
        for (var i = 0; i < DPlayer.NUMPSPRITES; i++) {
            DPlayer.players_psprites_state[p * DPlayer.NUMPSPRITES + i] = -1;
            DPlayer.players_psprites_tics[p * DPlayer.NUMPSPRITES + i] = 0;
            DPlayer.players_psprites_sx[p * DPlayer.NUMPSPRITES + i] = 0;
            DPlayer.players_psprites_sy[p * DPlayer.NUMPSPRITES + i] = 0;
        }
        DPlayer.players_didsecret[p] = false;
    }

    //
    // G_DoLoadLevel
    //
    function G_DoLoadLevel() as Void {
        var i;

        // Set the sky map.
        // (skyflatnum and skytexture come from tools/wad2ciq.py, see
        // R_InitData; E1 only uses SKY1)

        gamestate = DoomDef.GS_LEVEL;

        for (i = 0; i < DoomStat.MAXPLAYERS; i++) {
            if (DPlayer.playeringame[i] && DPlayer.players_playerstate[i] == DPlayer.PST_DEAD) {
                DPlayer.players_playerstate[i] = DPlayer.PST_REBORN;
            }
        }

        // Only starts loading, see the header comment.
        PSetup.P_SetupLevel(DoomStat.gameepisode, DoomStat.gamemap);
    }

    //
    // G_ExitLevel
    //
    // gameaction_t; only the ones the watch needs.
    const ga_nothing = 0;
    const ga_completed = 1;
    const ga_victory = 2;
    const ga_worlddone = 3;

    var gameaction as Number = ga_nothing;
    var secretexit as Boolean = false;

    // wminfo.next: the next map, 0 biased
    var wminfo_next as Number = 0;

    function G_ExitLevel() as Void {
        secretexit = false;
        gameaction = ga_completed;
    }

    // Here's for the german edition.
    function G_SecretExitLevel() as Void {
        // IF NO WOLF3D LEVELS, NO SECRET EXIT!
        // (only matters for commercial)
        secretexit = true;
        gameaction = ga_completed;
    }

    //
    // G_PlayerFinishLevel
    // Call when a player completes a level.
    //
    function G_PlayerFinishLevel(player as Number) as Void {
        for (var i = 0; i < DoomDef.NUMPOWERS; i++) {
            DPlayer.players_powers[player * DoomDef.NUMPOWERS + i] = 0;
        }
        for (var i = 0; i < DoomDef.NUMCARDS; i++) {
            DPlayer.players_cards[player * DoomDef.NUMCARDS + i] = 0;
        }
        var mo = DPlayer.players_mo[player];
        PMobj.mobjs_flags[mo] &= ~PMobj.MF_SHADOW;  // cancel invisibility
        DPlayer.players_extralight[player] = 0;     // cancel gun flashes
        DPlayer.players_fixedcolormap[player] = 0;  // cancel ir gogles
        DPlayer.players_damagecount[player] = 0;    // no palette changes
        DPlayer.players_bonuscount[player] = 0;
    }

    //
    // G_DoCompleted
    //
    // There's no intermission screen (wi_stuff.c) yet, so this goes
    // straight on to G_DoWorldDone. Returns false on ga_victory (E1M8
    // done), which needs the finale.
    //
    function G_DoCompleted() as Boolean {
        gameaction = ga_nothing;

        for (var i = 0; i < DoomStat.MAXPLAYERS; i++) {
            if (DPlayer.playeringame[i]) {
                G_PlayerFinishLevel(i);  // take away cards and stuff
            }
        }

        // (gamemode is never commercial here)
        if (DoomStat.gamemap == 8) {
            // victory
            gameaction = ga_victory;
            return false;
        }

        if (DoomStat.gamemap == 9) {
            // exit secret level
            for (var i = 0; i < DoomStat.MAXPLAYERS; i++) {
                DPlayer.players_didsecret[i] = true;
            }
        }

        if (secretexit) {
            wminfo_next = 8;  // go to secret level
        } else if (DoomStat.gamemap == 9) {
            // returning from secret level
            switch (DoomStat.gameepisode) {
                case 1:
                    wminfo_next = 3;
                    break;
                case 2:
                    wminfo_next = 5;
                    break;
                case 3:
                    wminfo_next = 6;
                    break;
                case 4:
                    wminfo_next = 2;
                    break;
            }
        } else {
            wminfo_next = DoomStat.gamemap;  // go to next level
        }

        // WI_Start would run here; G_WorldDone when it's finished.
        G_DoWorldDone();
        return true;
    }

    //
    // G_DoWorldDone
    //
    function G_DoWorldDone() as Void {
        gamestate = DoomDef.GS_LEVEL;
        DoomStat.gamemap = wminfo_next + 1;
        G_DoLoadLevel();
        gameaction = ga_nothing;
    }

    //
    // G_InitNew
    // Can be called by the startup code or the menu task,
    // consoleplayer, displayplayer, playeringame[] should be set.
    //
    function G_InitNew(skill as Number, episode as Number, map as Number) as Void {
        var i;

        if (skill > DoomDef.sk_nightmare) {
            skill = DoomDef.sk_nightmare;
        }

        // This was quite messy with SPECIAL and commented parts.
        // Supposedly hacks to make the latest edition work.
        // It might not work properly.
        if (episode < 1) {
            episode = 1;
        }

        if (DoomStat.gamemode == DoomDef.retail) {
            if (episode > 4) {
                episode = 4;
            }
        } else if (DoomStat.gamemode == DoomDef.shareware) {
            if (episode > 1) {
                episode = 1;    // only start episode 1 on shareware
            }
        } else {
            if (episode > 3) {
                episode = 3;
            }
        }

        if (map < 1) {
            map = 1;
        }

        if ((map > 9)
            && (DoomStat.gamemode != DoomDef.commercial)) {
            map = 9;
        }

        MRandom.M_ClearRandom();

        if (skill == DoomDef.sk_nightmare || DoomStat.respawnparm) {
            respawnmonsters = true;
        } else {
            respawnmonsters = false;
        }

        var states = Info.states;
        var mobjinfo = Info.mobjinfo;
        if (DoomStat.fastparm || (skill == DoomDef.sk_nightmare && DoomStat.gameskill != DoomDef.sk_nightmare)) {
            for (i = Info.S_SARG_RUN1; i <= Info.S_SARG_PAIN2; i++) {
                states[i * Info.ST_SIZE + Info.ST_TICS] >>= 1;
            }
            mobjinfo[Info.MT_BRUISERSHOT * Info.MI_SIZE + Info.MI_SPEED] = 20 * MFixed.FRACUNIT;
            mobjinfo[Info.MT_HEADSHOT * Info.MI_SIZE + Info.MI_SPEED] = 20 * MFixed.FRACUNIT;
            mobjinfo[Info.MT_TROOPSHOT * Info.MI_SIZE + Info.MI_SPEED] = 20 * MFixed.FRACUNIT;
        } else if (skill != DoomDef.sk_nightmare && DoomStat.gameskill == DoomDef.sk_nightmare) {
            for (i = Info.S_SARG_RUN1; i <= Info.S_SARG_PAIN2; i++) {
                states[i * Info.ST_SIZE + Info.ST_TICS] <<= 1;
            }
            mobjinfo[Info.MT_BRUISERSHOT * Info.MI_SIZE + Info.MI_SPEED] = 15 * MFixed.FRACUNIT;
            mobjinfo[Info.MT_HEADSHOT * Info.MI_SIZE + Info.MI_SPEED] = 10 * MFixed.FRACUNIT;
            mobjinfo[Info.MT_TROOPSHOT * Info.MI_SIZE + Info.MI_SPEED] = 10 * MFixed.FRACUNIT;
        }

        // force players to be initialized upon first level load
        for (i = 0; i < DoomStat.MAXPLAYERS; i++) {
            DPlayer.players_playerstate[i] = DPlayer.PST_REBORN;
        }

        DoomStat.gameepisode = episode;
        DoomStat.gamemap = map;
        DoomStat.gameskill = skill;

        // set the sky map for the episode
        // (the sky texture is picked by tools/wad2ciq.py)

        G_DoLoadLevel();
    }

    //
    // DEMO PLAYBACK
    // G_DeferedPlayDemo, G_DoPlayDemo, G_ReadDemoTiccmd and the playback
    // half of G_CheckDemoStatus. tools/wad2ciq.py turns the DEMO lumps
    // into jsonData: the 13 header bytes one per number, then one number
    // per ticcmd with its 4 bytes packed little endian, ending with
    // DEMOMARKER. demo_p indexes those numbers.
    //
    const DEMOMARKER = 0x80;

    // gameaction_t ga_playdemo
    const ga_playdemo = 4;

    var demoplayback as Boolean = false;
    var demobuffer as Array<Number> = [] as Array<Number>;
    var demo_p as Number = 0;
    // DEMO1..3 by number: Monkey C can't look Rez ids up by name
    var defdemoname as Number = 0;
    // demoplayback is cleared once the stream ends, so keep track of it
    var demotics as Number = 0;

    //
    // G_PlayDemo
    //
    function G_DeferedPlayDemo(name as Number) as Void {
        defdemoname = name;
        gameaction = ga_playdemo;
    }

    function W_DemoLump(name as Number) as ResourceId {
        if (name == 2) {
            return Rez.JsonData.demo2;
        }
        if (name == 3) {
            return Rez.JsonData.demo3;
        }
        return Rez.JsonData.demo1;
    }

    // *demo_p++: Monkey C has no ++ inside an expression.
    function D_ReadByte() as Number {
        var v = demobuffer[demo_p];
        demo_p++;
        return v;
    }

    //
    // G_DoPlayDemo
    //
    // Like G_InitNew it only starts loading the level: the caller runs
    // PSetup.P_SetupLevelStep until it returns true.
    //
    function G_DoPlayDemo() as Void {
        var skill;
        var i;
        var episode;
        var map;

        gameaction = ga_nothing;
        demobuffer = WatchUi.loadResource(W_DemoLump(defdemoname)) as Array<Number>;
        demo_p = 0;
        // linuxdoom-1.10 only takes VERSION (110) here, but its game code
        // is the same as 1.9's and plays 1.9 demos, which is what the
        // shareware IWAD's DEMO lumps are. So take 109 as well.
        var version = D_ReadByte();
        if (version != 110 && version != 109) {
            System.println("Demo is from a different game version!");
            gameaction = ga_nothing;
            return;
        }

        skill = D_ReadByte();
        episode = D_ReadByte();
        map = D_ReadByte();
        DoomStat.deathmatch = D_ReadByte() != 0;
        DoomStat.respawnparm = D_ReadByte() != 0;
        DoomStat.fastparm = D_ReadByte() != 0;
        DoomStat.nomonsters = D_ReadByte() != 0;
        DPlayer.consoleplayer = D_ReadByte();

        for (i = 0; i < DoomStat.MAXPLAYERS; i++) {
            DPlayer.playeringame[i] = D_ReadByte() != 0;
        }
        // (netdemos can't be played: the watch only runs player 0)

        // don't spend a lot of time in loadlevel
        G_InitNew(skill, episode, map);

        demoplayback = true;
        demotics = 0;
    }

    //
    // DEMO RECORDING
    //
    function G_ReadDemoTiccmd(player as Number) as Void {
        var v = demobuffer[demo_p];
        if ((v & 0xFF) == DEMOMARKER) {
            // end of demo data stream
            G_CheckDemoStatus();
            return;
        }
        demo_p++;
        // the four bytes of the number, as signed / unsigned chars
        DPlayer.players_cmd_forwardmove[player] = (v << 24) >> 24;
        DPlayer.players_cmd_sidemove[player] = (v << 16) >> 24;
        // ((unsigned char)*demo_p++)<<8 into a short
        DPlayer.players_cmd_angleturn[player] = (((v >> 16) & 0xFF) << 24) >> 16;
        DPlayer.players_cmd_buttons[player] = (v >> 24) & 0xFF;
        demotics++;
    }

    //
    // G_CheckDemoStatus
    // Called after a death or level completion to allow demos to be ended
    // Returns true if a new demo loop action will take place
    //
    function G_CheckDemoStatus() as Boolean {
        if (demoplayback) {
            demobuffer = [] as Array<Number>;
            demoplayback = false;
            DoomStat.netgame = false;
            DoomStat.deathmatch = false;
            DPlayer.playeringame[1] = false;
            DPlayer.playeringame[2] = false;
            DPlayer.playeringame[3] = false;
            DoomStat.respawnparm = false;
            DoomStat.fastparm = false;
            DoomStat.nomonsters = false;
            DPlayer.consoleplayer = 0;
            DMain.D_AdvanceDemo();
            return true;
        }

        return false;
    }

    //
    // G_BuildTiccmd
    // Builds a ticcmd from all of the available inputs
    // or reads it from the demo buffer.
    // If recording a demo, write it out
    //
    // The watch only has a few buttons and the touchscreen. The view's
    // delegate sets these, standing in for gamekeydown[].
    var key_left as Boolean = false;
    var key_right as Boolean = false;
    var key_up as Boolean = false;
    var key_down as Boolean = false;
    var key_fire as Boolean = false;
    var key_use as Boolean = false;

    const SLOWTURNTICS = 6;

    var forwardmove as Array<Number> = [0x19, 0x32] as Array<Number>;
    var sidemove as Array<Number> = [0x18, 0x28] as Array<Number>;
    var angleturn as Array<Number> = [640, 1280, 320] as Array<Number>; // + slow turn

    var turnheld as Number = 0; // for accelerative turning

    function G_BuildTiccmd(player as Number) as Void {
        var forward = 0;
        var side = 0;
        var cmd_angleturn = 0;
        var buttons = 0;

        // no run key on the watch
        var speed = 0;
        var tspeed;

        // use two stage accelerative turning
        // on the keyboard and joystick
        if (key_right || key_left) {
            turnheld += 1;
        } else {
            turnheld = 0;
        }

        if (turnheld < SLOWTURNTICS) {
            tspeed = 2;  // slow turn
        } else {
            tspeed = speed;
        }

        // let movement keys cancel each other out
        if (key_right) {
            cmd_angleturn -= angleturn[tspeed];
        }
        if (key_left) {
            cmd_angleturn += angleturn[tspeed];
        }

        if (key_up) {
            forward += forwardmove[speed];
        }
        if (key_down) {
            forward -= forwardmove[speed];
        }

        // buttons
        if (key_fire) {
            buttons |= DPlayer.BT_ATTACK;
        }

        if (key_use) {
            buttons |= DPlayer.BT_USE;
        }

        if (forward > PLocal.MAXPLMOVE) {
            forward = PLocal.MAXPLMOVE;
        } else if (forward < -PLocal.MAXPLMOVE) {
            forward = -PLocal.MAXPLMOVE;
        }
        if (side > PLocal.MAXPLMOVE) {
            side = PLocal.MAXPLMOVE;
        } else if (side < -PLocal.MAXPLMOVE) {
            side = -PLocal.MAXPLMOVE;
        }

        DPlayer.players_cmd_forwardmove[player] = forward;
        DPlayer.players_cmd_sidemove[player] = side;
        DPlayer.players_cmd_angleturn[player] = cmd_angleturn;
        DPlayer.players_cmd_buttons[player] = buttons;
    }
}
