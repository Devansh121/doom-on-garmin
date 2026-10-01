import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// i_video.c's job: show the finished frame, here by copying the view
// bitmap to the middle of the watch screen.
class DoomView extends WatchUi.View {

    const TICK_MS = 50;

    var timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
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
        if (DMain.D_Tick()) {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();

        if (!DMain.started) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - 30, Graphics.FONT_MEDIUM, "DOOM", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 + 20, Graphics.FONT_XTINY, DMain.D_StartupMessage(), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var bitmap = RDraw.viewbitmap;
        if (bitmap != null) {
            dc.drawBitmap((w - RDraw.VIEW_W) / 2, (h - RDraw.VIEW_H) / 2, bitmap);
        }
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 22, Graphics.FONT_XTINY, DMain.fps + " fps", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
