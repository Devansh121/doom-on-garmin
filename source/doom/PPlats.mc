// p_plats.c
//
// Plats (i.e. elevator platforms) code, raising/lowering.
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PPlats {

    function T_PlatRaise(plat as Number) as Void {
    }

    function EV_DoPlat(line as Number, type as Number, amount as Number) as Number {
        return 0;
    }

    function P_AddActivePlat(plat as Number) as Void {
    }

    function P_RemoveActivePlat(plat as Number) as Void {
    }

    function EV_StopPlat(line as Number) as Void {
    }

    function P_ActivateInStasis(tag as Number) as Void {
    }
}
