import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Buttons: UP/DOWN hold = turn left/right, START hold = walk forward, BACK = quit.
// Touch: hold left/right third = turn, middle = walk forward, bottom fifth = walk back.
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
            DMain.turn = down ? -1 : 0;
        } else if (key == WatchUi.KEY_DOWN) {
            DMain.turn = down ? 1 : 0;
        } else if (key == WatchUi.KEY_ENTER) {
            DMain.forward = down ? 1 : 0;
        } else {
            return false;
        }
        return true;
    }

    function onDrag(evt as WatchUi.DragEvent) as Boolean {
        if (evt.getType() == WatchUi.DRAG_TYPE_STOP) {
            DMain.turn = 0;
            DMain.forward = 0;
            return true;
        }
        var c = evt.getCoordinates();
        var x = c[0];
        var y = c[1];
        var s = System.getDeviceSettings();
        var w = s.screenWidth;
        var h = s.screenHeight;
        DMain.turn = 0;
        DMain.forward = 0;
        if (y > h * 4 / 5) {
            DMain.forward = -1;
        } else if (x < w / 3) {
            DMain.turn = -1;
        } else if (x > w * 2 / 3) {
            DMain.turn = 1;
        } else {
            DMain.forward = 1;
        }
        return true;
    }
}
