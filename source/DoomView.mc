import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// i_video.c's job: show the finished frame, here by copying the view
// bitmap to the middle of the watch screen.
class DoomView extends WatchUi.View {

    const TICK_MS = 50;

    // Status bar size on screen: 320x32 scaled by 1.125 x 1.35, the
    // view's 1:1.2 pixel aspect. At 360 wide its corners fit in the
    // 454 circle down to 138 rows below the center.
    const BAR_W = 360;
    const BAR_H = 43;
    const BAR_BOTTOM = 138;

    // PLAYPAL palette shifts as translucent colors
    var tints as Array<Number> = HudLumps.tints();

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

        // st_stuff draws the status bar into its own bitmap when the
        // view leaves room for it (setblocks 10 and below).
        StStuff.ST_Drawer(RMain.viewheight == RMain.SCREENHEIGHT, false);
        var sbar = StStuff.st_statusbaron ? StStuff.stbarbitmap : null;

        // The view and the status bar below it. The bar is scaled to
        // BAR_W, keeping Doom's 1:1.2 pixel aspect like the view, and its
        // bottom sits at the lowest row where it still fits in the round
        // screen; the view goes right above it.
        var viewx = (w - RDraw.VIEW_W) / 2;
        var viewy = (h - RDraw.VIEW_H) / 2;
        var bary = 0;
        if (sbar != null) {
            bary = h / 2 + BAR_BOTTOM - BAR_H;
            viewy = bary - RDraw.VIEW_H;
        }

        var bitmap = RDraw.viewbitmap;
        if (bitmap != null) {
            dc.drawBitmap(viewx, viewy, bitmap);
        }

        // ST_doPaletteStuff's palette shift, as a tint over the view
        var palette = StStuff.st_palette;
        if (palette > 0) {
            dc.setFill(tints[palette]);
            dc.fillRectangle(viewx, viewy, RDraw.VIEW_W, RDraw.VIEW_H);
        }

        if (sbar != null) {
            dc.drawScaledBitmap((w - BAR_W) / 2, bary, BAR_W, BAR_H, sbar);
        }

        // HU_Drawer: the message line at the top of the view
        HuStuff.HU_Drawer(dc, w / 2, viewy + 4);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sbar != null ? bary + BAR_H + 4 : 22, Graphics.FONT_XTINY, DMain.fps + " fps", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
