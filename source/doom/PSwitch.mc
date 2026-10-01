// p_switch.c
//
// Switches, buttons. Two-state animation. Exits.
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PSwitch {

    function P_InitSwitchList() as Void {
    }

    function P_ChangeSwitchTexture(line as Number, useAgain as Number) as Void {
    }

    function P_UseSpecialLine(thing as Number, line as Number, side as Number) as Boolean {
        return false;
    }
}
