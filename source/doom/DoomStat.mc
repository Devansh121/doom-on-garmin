// doomstat.h
//
// All the global variables that store the internal state.
// Theoretically speaking, the internal state of the engine
//  should be found by looking at the variables collected
//  here, and every relevant module will have to include
//  this header file.

import Toybox.Lang;

module DoomStat {

    const MAXPLAYERS = 4;

    // Defaults for menu, methinks.
    var gameskill as Number = DoomDef.sk_medium;
    var gameepisode as Number = 1;
    var gamemap as Number = 1;

    // The shareware IWAD is the only one we load.
    var gamemode as Number = DoomDef.shareware;

    // Single player only on the watch.
    var netgame as Boolean = false;
    var deathmatch as Boolean = false;
    var respawnparm as Boolean = false;
    var fastparm as Boolean = false;
    var nomonsters as Boolean = false;

    // Player spawn spots. Each one is a mapthing_t as
    // [x, y, angle, type, options], or null if the map has none.
    var playerstarts as Array<Array<Number>?> = new [MAXPLAYERS] as Array<Array<Number>?>;
}
