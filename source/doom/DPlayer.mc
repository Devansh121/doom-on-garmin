// d_player.h, d_ticcmd.h, the button bits from d_event.h and
// pspdef_t from p_pspr.h
//
// player_t: the player's own state, apart from the mobj.
//
// Fields are arrays indexed by player number (players[p].health is
// players_health[p]); array fields are flattened, e.g.
// players_ammo[p * NUMAMMO + am_clip]. Only player 0 is ever in game on
// the watch, but keeping the index means the C code keeps its shape.
// Pointers to mobjs are mobj numbers, -1 for NULL.

import Toybox.Lang;

module DPlayer {

    const MAXPLAYERS = DoomStat.MAXPLAYERS;

    //
    // Player states.
    //
    const PST_LIVE = 0;   // Playing or camping.
    const PST_DEAD = 1;   // Dead on the ground, view follows killer.
    const PST_REBORN = 2; // Ready to restart/respawn???

    //
    // Player internal flags, for cheats and debug.
    //
    const CF_NOCLIP = 1;      // No clipping, walk through barriers.
    const CF_GODMODE = 2;     // No damage, no health loss.
    const CF_NOMOMENTUM = 4;  // Not really a cheat, just a debug aid.

    // d_event.h: button/action code definitions.
    const BT_ATTACK = 1;      // Press "Fire".
    const BT_USE = 2;         // Use button, to open doors, activate switches.
    const BT_SPECIAL = 128;   // Flag: game events, not really buttons.
    const BT_SPECIALMASK = 3;
    const BT_CHANGE = 4;      // Flag, weapon change pending.
    const BT_WEAPONMASK = 8 + 16 + 32; // The 3bit weapon mask and shift, convenience.
    const BT_WEAPONSHIFT = 3;

    // p_pspr.h: overlay psprites are scaled shapes
    // drawn directly on the view screen,
    // coordinates are given for a 320*200 view screen.
    const ps_weapon = 0;
    const ps_flash = 1;
    const NUMPSPRITES = 2;

    var players_mo as Array<Number> = [-1, -1, -1, -1] as Array<Number>;
    var players_playerstate as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // ticcmd_t cmd
    var players_cmd_forwardmove as Array<Number> = [0, 0, 0, 0] as Array<Number>; // *2048 for move
    var players_cmd_sidemove as Array<Number> = [0, 0, 0, 0] as Array<Number>;    // *2048 for move
    var players_cmd_angleturn as Array<Number> = [0, 0, 0, 0] as Array<Number>;   // <<16 for angle delta
    var players_cmd_buttons as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Determine POV,
    //  including viewpoint bobbing during movement.
    // Focal origin above r.z
    var players_viewz as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    // Base height above floor for viewz.
    var players_viewheight as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    // Bob/squat speed.
    var players_deltaviewheight as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    // bounded/scaled total momentum.
    var players_bob as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // This is only used between levels,
    // mo->health is used during levels.
    var players_health as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    var players_armorpoints as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    // Armor type is 0-2.
    var players_armortype as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Power ups. invinc and invis are tic counters.
    var players_powers as Array<Number> = new [MAXPLAYERS * DoomDef.NUMPOWERS] as Array<Number>;
    // cards[NUMCARDS], 0 or 1
    var players_cards as Array<Number> = new [MAXPLAYERS * DoomDef.NUMCARDS] as Array<Number>;
    var players_backpack as Array<Boolean> = [false, false, false, false] as Array<Boolean>;

    var players_readyweapon as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    // Is wp_nochange if not changing.
    var players_pendingweapon as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // weaponowned[NUMWEAPONS], 0 or 1
    var players_weaponowned as Array<Number> = new [MAXPLAYERS * DoomDef.NUMWEAPONS] as Array<Number>;
    var players_ammo as Array<Number> = new [MAXPLAYERS * DoomDef.NUMAMMO] as Array<Number>;
    var players_maxammo as Array<Number> = new [MAXPLAYERS * DoomDef.NUMAMMO] as Array<Number>;

    // True if button down last tic.
    var players_attackdown as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    var players_usedown as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Bit flags, for cheats and debug.
    // See cheat_t, above.
    var players_cheats as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Refired shots are less accurate.
    var players_refire as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Kills of other players, frags[MAXPLAYERS] flattened as
    // [p * MAXPLAYERS + other].
    var players_frags as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;

    // For intermission stats.
    var players_killcount as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    var players_itemcount as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    var players_secretcount as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Hint messages.
    var players_message as Array<String?> = [null, null, null, null] as Array<String?>;

    // For screen flashing (red or bright).
    var players_damagecount as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    var players_bonuscount as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Who did damage (NULL for floors/ceilings).
    var players_attacker as Array<Number> = [-1, -1, -1, -1] as Array<Number>;

    // So gun flashes light up areas.
    var players_extralight as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Current PLAYPAL, ???
    //  can be set to REDCOLORMAP for pain, etc.
    var players_fixedcolormap as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Player skin colorshift,
    //  0-3 for which color to draw player.
    var players_colormap as Array<Number> = [0, 0, 0, 0] as Array<Number>;

    // Overlay view sprites (gun, etc), psprites[NUMPSPRITES] flattened
    // as [p * NUMPSPRITES + n]. state is a state number, -1 (NULL) when
    // not active.
    var players_psprites_state as Array<Number> = new [MAXPLAYERS * NUMPSPRITES] as Array<Number>;
    var players_psprites_tics as Array<Number> = new [MAXPLAYERS * NUMPSPRITES] as Array<Number>;
    var players_psprites_sx as Array<Number> = new [MAXPLAYERS * NUMPSPRITES] as Array<Number>;
    var players_psprites_sy as Array<Number> = new [MAXPLAYERS * NUMPSPRITES] as Array<Number>;

    // True if secret level has been done.
    var players_didsecret as Array<Boolean> = [false, false, false, false] as Array<Boolean>;

    // playeringame[MAXPLAYERS], from g_game.c
    var playeringame as Array<Boolean> = [true, false, false, false] as Array<Boolean>;
    var consoleplayer as Number = 0;
}
