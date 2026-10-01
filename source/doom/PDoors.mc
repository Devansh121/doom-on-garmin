// p_doors.c
//
// Door animation code (opening/closing)
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PDoors {

    function T_VerticalDoor(door as Number) as Void {
    }

    function EV_DoLockedDoor(line as Number, type as Number, thing as Number) as Number {
        return 0;
    }

    function EV_DoDoor(line as Number, type as Number) as Number {
        return 0;
    }

    function EV_VerticalDoor(line as Number, thing as Number) as Void {
    }

    function P_SpawnDoorCloseIn30(sec as Number) as Void {
    }

    function P_SpawnDoorRaiseIn5Mins(sec as Number, secnum as Number) as Void {
    }
}
