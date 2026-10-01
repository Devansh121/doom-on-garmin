// p_inter.c
//
// Handling interactions (i.e., collisions).
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PInter {

    //
    // ---- shared tables ----
    // a weapon is found with two clip loads,
    // a big item has five clip loads
    // (g_game.c's G_PlayerReborn reads maxammo)
    //
    var maxammo as Array<Number> = [200, 50, 300, 50] as Array<Number>;
    var clipammo as Array<Number> = [10, 4, 20, 1] as Array<Number>;
    // ---- end of shared tables ----

    function P_GivePower(player as Number, power as Number) as Boolean {
        return false;
    }

    function P_TouchSpecialThing(special as Number, toucher as Number) as Void {
    }

    function P_KillMobj(source as Number, target as Number) as Void {
    }

    function P_DamageMobj(target as Number, inflictor as Number, source as Number, damage as Number) as Void {
    }
}
