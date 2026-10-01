// p_mobj.c
//
// Moving object handling. Spawn functions.
//
// Only the player start bookkeeping of P_SpawnMapThing so far; spawning
// actual mobjs needs info.c.

import Toybox.Lang;

module PMobj {

    // P_SpawnMapThing
    // The fields of the mapthing should
    // already be in host byte order.
    function P_SpawnMapThing(mthing as Array<Number>) as Void {
        var type = mthing[3];

        // check for players specially
        if (type <= 4) {
            // save spots for respawning in network games
            DoomStat.playerstarts[type - 1] = mthing;
            return;
        }
    }
}
