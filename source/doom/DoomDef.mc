// doomdef.h
//
// Internally used data structures for virtually everything,
//  key definitions, lots of other stuff.

import Toybox.Lang;

(:extendedCode)
module DoomDef {

    // Game mode handling - identify IWAD version
    //  to handle IWAD dependend animations etc.
    const shareware = 0;    // DOOM 1 shareware, E1, M9
    const registered = 1;   // DOOM 1 registered, E3, M27
    const commercial = 2;   // DOOM 2 retail, E1 M34
    const retail = 3;       // DOOM 1 retail, E4, M36
    const indetermined = 4; // Well, no IWAD found.

    // State updates, number of tics / second.
    const TICRATE = 35;

    // The current state of the game: whether we are
    // playing, gazing at the intermission screen,
    // the game final animation, or a demo.
    const GS_LEVEL = 0;
    const GS_INTERMISSION = 1;
    const GS_FINALE = 2;
    const GS_DEMOSCREEN = 3;

    //
    // Difficulty/skill settings/filters.
    //

    // Skill flags.
    const MTF_EASY = 1;
    const MTF_NORMAL = 2;
    const MTF_HARD = 4;

    // Deaf monsters/do not react to sound.
    const MTF_AMBUSH = 8;

    const sk_baby = 0;
    const sk_easy = 1;
    const sk_medium = 2;
    const sk_hard = 3;
    const sk_nightmare = 4;

    //
    // Key cards.
    //
    const it_bluecard = 0;
    const it_yellowcard = 1;
    const it_redcard = 2;
    const it_blueskull = 3;
    const it_yellowskull = 4;
    const it_redskull = 5;
    const NUMCARDS = 6;

    // The defined weapons,
    //  including a marker indicating
    //  user has not changed weapon.
    const wp_fist = 0;
    const wp_pistol = 1;
    const wp_shotgun = 2;
    const wp_chaingun = 3;
    const wp_missile = 4;
    const wp_plasma = 5;
    const wp_bfg = 6;
    const wp_chainsaw = 7;
    const wp_supershotgun = 8;
    const NUMWEAPONS = 9;
    // No pending weapon change.
    const wp_nochange = 10;

    // Ammunition types defined.
    const am_clip = 0;   // Pistol / chaingun ammo.
    const am_shell = 1;  // Shotgun / double barreled shotgun.
    const am_cell = 2;   // Plasma rifle, BFG.
    const am_misl = 3;   // Missile launcher.
    const NUMAMMO = 4;
    const am_noammo = 5; // Unlimited for chainsaw / fist.

    // Power up artifacts.
    const pw_invulnerability = 0;
    const pw_strength = 1;
    const pw_invisibility = 2;
    const pw_ironfeet = 3;
    const pw_allmap = 4;
    const pw_infrared = 5;
    const NUMPOWERS = 6;

    //
    // Power up durations,
    //  how many seconds till expiration,
    //  assuming TICRATE is 35 ticks/second.
    //
    const INVULNTICS = 30 * TICRATE;
    const INVISTICS = 60 * TICRATE;
    const INFRATICS = 120 * TICRATE;
    const IRONTICS = 60 * TICRATE;
}
