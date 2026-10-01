import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class DoomView extends WatchUi.View {

    // Screen strips per frame; lower = faster, blockier.
    const COLS = 76;
    const TICK_MS = 50;
    const MOVE_STEP = 0.12;
    const TURN_STEP = 0.10;

    var caster as Raycaster;
    var timer as Timer.Timer?;

    // Held-input state, set by DoomDelegate.
    var forward as Number = 0;
    var turn as Number = 0;

    var frames as Number = 0;
    var fps as Number = 0;
    var fpsStart as Number = 0;

    function initialize() {
        View.initialize();
        caster = new Raycaster();
    }

    function onShow() as Void {
        fpsStart = System.getTimer();
        timer = new Timer.Timer();
        timer.start(method(:tick), TICK_MS, true);
    }

    function onHide() as Void {
        if (timer != null) {
            timer.stop();
            timer = null;
        }
    }

    function tick() as Void {
        if (turn != 0) {
            caster.rotate(TURN_STEP * turn);
        }
        if (forward != 0) {
            caster.move(MOVE_STEP * forward);
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        caster.render(dc, COLS);

        frames++;
        var now = System.getTimer();
        if (now - fpsStart >= 1000) {
            fps = frames * 1000 / (now - fpsStart);
            frames = 0;
            fpsStart = now;
        }
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, 30, Graphics.FONT_XTINY, fps + " fps",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}
