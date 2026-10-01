// p_lights.c
//
// Handle Sector base lighting effects.
// Muzzle flash?
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module PLights {

    function T_FireFlicker(flick as Number) as Void {
    }

    function P_SpawnFireFlicker(sector as Number) as Void {
    }

    function T_LightFlash(flash as Number) as Void {
    }

    function P_SpawnLightFlash(sector as Number) as Void {
    }

    function T_StrobeFlash(flash as Number) as Void {
    }

    function P_SpawnStrobeFlash(sector as Number, fastOrSlow as Number, inSync as Number) as Void {
    }

    function EV_StartLightStrobing(line as Number) as Void {
    }

    function EV_TurnTagLightsOff(line as Number) as Void {
    }

    function EV_LightTurnOn(line as Number, bright as Number) as Void {
    }

    function T_Glow(g as Number) as Void {
    }

    function P_SpawnGlowingLight(sector as Number) as Void {
    }
}
