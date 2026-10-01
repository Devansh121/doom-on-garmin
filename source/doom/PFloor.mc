// p_floor.c
//
// Floor animation: raising stairs.
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PFloor {

    function T_MovePlane(sector as Number, speed as Number, dest as Number, crush as Boolean, floorOrCeiling as Number, direction as Number) as Number {
        return 0;
    }

    function T_MoveFloor(floor as Number) as Void {
    }

    function EV_DoFloor(line as Number, floortype as Number) as Number {
        return 0;
    }

    function EV_BuildStairs(line as Number, type as Number) as Number {
        return 0;
    }
}
