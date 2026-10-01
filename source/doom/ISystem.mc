// i_system.c / i_system.h
//
// System specific interface stuff.

import Toybox.Lang;
import Toybox.System;

class DoomError extends Lang.Exception {

    function initialize(msg as String) {
        Exception.initialize();
        mMessage = msg;
    }
}

module ISystem {

    function I_Error(error as String) as Void {
        System.println("Error: " + error);
        throw new DoomError(error);
    }
}
