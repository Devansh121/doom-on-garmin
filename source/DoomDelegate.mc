import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// d_event.h / i_video.c's job: turn watch input into Doom's keys, which
// G_BuildTiccmd reads.
//
// Buttons: UP/DOWN hold = turn left/right, START hold = walk forward,
// BACK = quit.
// Touch: hold the upper half = fire, the lower half = use (doors,
// switches).
class DoomDelegate extends WatchUi.InputDelegate {

    function initialize() {
        InputDelegate.initialize();
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        return setKey(evt.getKey(), true);
    }

    function onKeyReleased(evt as WatchUi.KeyEvent) as Boolean {
        return setKey(evt.getKey(), false);
    }

    function setKey(key as Number, down as Boolean) as Boolean {
        if (key == WatchUi.KEY_UP) {
            GGame.key_left = down;
        } else if (key == WatchUi.KEY_DOWN) {
            GGame.key_right = down;
        } else if (key == WatchUi.KEY_ENTER) {
            GGame.key_up = down;
        } else {
            return false;
        }
        return true;
    }

    function onDrag(evt as WatchUi.DragEvent) as Boolean {
        if (evt.getType() == WatchUi.DRAG_TYPE_STOP) {
            GGame.key_fire = false;
            GGame.key_use = false;
            return true;
        }
        var y = evt.getCoordinates()[1];
        var upper = y < System.getDeviceSettings().screenHeight / 2;
        GGame.key_fire = upper;
        GGame.key_use = !upper;
        return true;
    }
}
