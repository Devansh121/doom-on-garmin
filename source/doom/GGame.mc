// g_game.c
//
// DESCRIPTION:  none
//
// Only the parts that set the game and the players up for a level are
// here: G_PlayerReborn, G_InitNew and G_DoLoadLevel. There are no demos,
// savegames, netgames or menus on the watch.
//
// P_SetupLevel can't load a map in one callback (see PSetup), so
// G_DoLoadLevel only starts it; the caller then runs
// PSetup.P_SetupLevelStep until it returns true.

import Toybox.Lang;

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
    // Not ported yet (no intermission); stub for the p_spec family.
    function G_ExitLevel() as Void {
    }

    // Here's for the german edition.
    // Not ported yet; stub for the p_spec family.
    function G_SecretExitLevel() as Void {
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

    // stub until the rest of g_game.c is ported; A_BossDeath and
    // A_BrainDie call it
    function G_ExitLevel() as Void {
    }
}
