// p_ceilng.c
//
// Ceiling aninmation (lowering, crushing, raising)
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PCeilng {

    function T_MoveCeiling(ceiling as Number) as Void {
    }

    function EV_DoCeiling(line as Number, type as Number) as Number {
        return 0;
    }

    function P_AddActiveCeiling(c as Number) as Void {
    }

    function P_RemoveActiveCeiling(c as Number) as Void {
    }

    function EV_CeilingCrushStop(line as Number) as Number {
        return 0;
    }

    function P_ActivateInStasisCeiling(line as Number) as Void {
    }
}
