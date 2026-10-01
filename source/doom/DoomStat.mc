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

    // Player spawn spots. Each one is a mapthing_t as
    // [x, y, angle, type, options], or null if the map has none.
    var playerstarts as Array<Array<Number>?> = new [MAXPLAYERS] as Array<Array<Number>?>;
}
