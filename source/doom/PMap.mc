// p_map.c
//
// Movement, collision handling.
// Shooting and aiming.
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PMap {

    // p_map.c globals used by p_mobj.c. Stubs until p_map.c is ported.
    // keep track of the line that lowers the ceiling,
    // so missiles don't explode against sky hack walls
    var ceilingline as Number = -1;
    // who got hit (or NULL)
    var linetarget as Number = -1;
    var attackrange as Number = 0;

    function P_CheckPosition(thing as Number, x as Number, y as Number) as Boolean {
        return false;
    }

    function P_TryMove(thing as Number, x as Number, y as Number) as Boolean {
        return false;
    }

    function P_TeleportMove(thing as Number, x as Number, y as Number) as Boolean {
        return false;
    }

    function P_SlideMove(mo as Number) as Void {
    }

    function P_UseLines(player as Number) as Void {
    }

    function P_ChangeSector(sector as Number, crunch as Boolean) as Boolean {
        return false;
    }

    function P_AimLineAttack(t1 as Number, angle as Number, distance as Number) as Number {
        return 0;
    }

    function P_LineAttack(t1 as Number, angle as Number, distance as Number, slope as Number, damage as Number) as Void {
    }

    function P_RadiusAttack(spot as Number, source as Number, damage as Number) as Void {
    }
}
