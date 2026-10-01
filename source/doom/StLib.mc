// st_lib.c / st_lib.h
//
// DESCRIPTION:
//	The status bar widget code.
//
// Patches are HudLumps numbers (see tools/hud2ciq.py) instead of
// patch_t pointers, and a patch list (patch_t**) is an array of them.
// The widgets' int and boolean pointers become num / on fields that
// st_stuff keeps current before drawing, since Monkey C has no pointers
// to ints.
//
// The status bar is drawn into its own 320x32 BufferedBitmap (screens[4]
// in the C code is the BG copy, here the STBAR bitmap itself), so FG
// y coordinates are offset by ST_Y. The view scales that bitmap onto the
// watch every frame, so widgets only have to redraw when they change.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Number widget
class st_number_t {
    // upper right-hand corner
    //  of the number (right-justified)
    var x as Number = 0;
    var y as Number = 0;

    // max # of digits in number
    var width as Number = 0;

    // last number value
    var oldnum as Number = 0;

    // pointer to current value (here: the value itself)
    var num as Number = 0;

    // pointer to boolean stating
    //  whether to update number (here: the value itself)
    var on as Boolean = false;

    // list of patches for 0-9
    var p as Array<Number> = [] as Array<Number>;

    // user data
    var data as Number = 0;

    function initialize() {
    }
}

// Percent widget ("child" of number widget,
//  or, more precisely, contains a number widget.)
class st_percent_t {
    // number information
    var n as st_number_t = new st_number_t();

    // percent sign graphic
    var p as Number = 0;

    function initialize() {
    }
}

// Multiple Icon widget
class st_multicon_t {
    // center-justified location of icons
    var x as Number = 0;
    var y as Number = 0;

    // last icon number
    var oldinum as Number = 0;

    // pointer to current icon (here: the value itself)
    var inum as Number = 0;

    // pointer to boolean stating
    //  whether to update icon (here: the value itself)
    var on as Boolean = false;

    // list of icons
    var p as Array<Number> = [] as Array<Number>;

    // user data
    var data as Number = 0;

    function initialize() {
    }
}

// Binary Icon widget
class st_binicon_t {
    // center-justified location of icon
    var x as Number = 0;
    var y as Number = 0;

    // last icon value
    var oldval as Boolean = false;

    // pointer to current icon status (here: the value itself)
    var val as Boolean = false;

    // pointer to boolean
    //  stating whether to update icon (here: the value itself)
    var on as Boolean = false;

    // icon
    var p as Number = 0;

    // user data
    var data as Number = 0;

    function initialize() {
    }
}

(:extendedCode)
module StLib {

    // st_stuff.h: size of statusbar.
    const ST_HEIGHT = 32;
    const ST_WIDTH = RMain.SCREENWIDTH;
    const ST_Y = RMain.SCREENHEIGHT - ST_HEIGHT;

    // The FG status bar bitmap being drawn to; null in tests, which
    // only record the draw calls.
    var dc as Graphics.Dc? = null;

    // When not null, every V_DrawPatch appends lump, x, y and every
    // V_CopyRect appends -1, x, y, w, h (screen coordinates), for tests.
    var drawtrace as Array<Number>? = null;

    // W_CacheLumpName: patches stay loaded once used (PU_STATIC), except
    // the faces, of which only the last one drawn is kept, to save heap.
    var patches as Array<WatchUi.BitmapResource?> = new [HudLumps.NUMLUMPS] as Array<WatchUi.BitmapResource?>;
    var lumpsizes as Array<Number> = HudLumps.sizes();
    var lastface as Number = -1;

    function W_CachePatch(lump as Number) as WatchUi.BitmapResource {
        var p = patches[lump];
        if (p == null) {
            if (lump >= HudLumps.FACES && lump < HudLumps.FACES + StStuff.ST_NUMFACES) {
                if (lastface != -1) {
                    patches[lastface] = null;
                }
                lastface = lump;
            }
            p = WatchUi.loadResource(HudLumps.ids()[lump]) as WatchUi.BitmapResource;
            patches[lump] = p;
        }
        return p;
    }

    // SHORT(patch->width) and friends.
    function P_Width(lump as Number) as Number {
        return lumpsizes[lump * 4];
    }

    function P_Height(lump as Number) as Number {
        return lumpsizes[lump * 4 + 1];
    }

    function P_LeftOffset(lump as Number) as Number {
        return lumpsizes[lump * 4 + 2];
    }

    function P_TopOffset(lump as Number) as Number {
        return lumpsizes[lump * 4 + 3];
    }

    //
    // V_DrawPatch
    // Masks a column based masked pic to the screen.
    // (v_video.c; only FG, the status bar, is drawn to here)
    //
    function V_DrawPatch(x as Number, y as Number, lump as Number) as Void {
        if (drawtrace != null) {
            (drawtrace as Array<Number>).addAll([lump, x, y]);
        }
        if (dc != null) {
            y -= P_TopOffset(lump);
            x -= P_LeftOffset(lump);
            (dc as Graphics.Dc).drawBitmap(x, y - ST_Y, W_CachePatch(lump));
        }
    }

    //
    // V_CopyRect from BG to FG at the same place.
    //
    function V_CopyRect(x as Number, y as Number, width as Number, height as Number) as Void {
        if (drawtrace != null) {
            (drawtrace as Array<Number>).addAll([-1, x, y, width, height]);
        }
        if (dc != null) {
            (dc as Graphics.Dc).drawOffsetBitmap(x, y - ST_Y, x, y - ST_Y, width, height,
                W_CachePatch(HudLumps.SBAR));
        }
    }

    //
    // Hack display negative frags.
    //  Loads and store the stminus lump.
    //
    var sttminus as Number = HudLumps.MINUS;

    function STlib_init() as Void {
        sttminus = HudLumps.MINUS;
    }

    // ?
    function STlib_initNum(n as st_number_t, x as Number, y as Number, pl as Array<Number>,
                           num as Number, on as Boolean, width as Number) as Void {
        n.x = x;
        n.y = y;
        n.oldnum = 0;
        n.width = width;
        n.num = num;
        n.on = on;
        n.p = pl;
    }

    //
    // A fairly efficient way to draw a number
    //  based on differences from the old number.
    // Note: worth the trouble?
    //
    function STlib_drawNum(n as st_number_t, refresh as Boolean) as Void {
        var numdigits = n.width;
        var num = n.num;

        var w = P_Width(n.p[0]);
        var h = P_Height(n.p[0]);
        var x = n.x;

        var neg;

        n.oldnum = n.num;

        neg = num < 0;

        if (neg) {
            if (numdigits == 2 && num < -9) {
                num = -9;
            } else if (numdigits == 3 && num < -99) {
                num = -99;
            }

            num = -num;
        }

        // clear the area
        x = n.x - numdigits * w;

        if (n.y - ST_Y < 0) {
            ISystem.I_Error("drawNum: n->y - ST_Y < 0");
        }

        V_CopyRect(x, n.y, w * numdigits, h);

        // if non-number, do not draw it
        if (num == 1994) {
            return;
        }

        x = n.x;

        // in the special case of 0, you draw 0
        if (num == 0) {
            V_DrawPatch(x - w, n.y, n.p[0]);
        }

        // draw the new number
        while (num != 0 && numdigits != 0) {
            numdigits--;
            x -= w;
            V_DrawPatch(x, n.y, n.p[num % 10]);
            num /= 10;
        }

        // draw a minus sign if necessary
        if (neg) {
            V_DrawPatch(x - 8, n.y, sttminus);
        }
    }

    //
    // The C code redraws every number every frame (into the frame
    // buffer, which is rebuilt each frame anyway). The status bar bitmap
    // here keeps its contents, so a number is only redrawn when it
    // changed, as oldnum was meant for.
    //
    function STlib_updateNum(n as st_number_t, refresh as Boolean) as Void {
        if (n.on && (refresh || n.oldnum != n.num)) {
            STlib_drawNum(n, refresh);
        }
    }

    //
    function STlib_initPercent(p as st_percent_t, x as Number, y as Number, pl as Array<Number>,
                               num as Number, on as Boolean, percent as Number) as Void {
        STlib_initNum(p.n, x, y, pl, num, on, 3);
        p.p = percent;
    }

    function STlib_updatePercent(per as st_percent_t, refresh as Boolean) as Void {
        if (refresh && per.n.on) {
            V_DrawPatch(per.n.x, per.n.y, per.p);
        }

        STlib_updateNum(per.n, refresh);
    }

    function STlib_initMultIcon(i as st_multicon_t, x as Number, y as Number, il as Array<Number>,
                                inum as Number, on as Boolean) as Void {
        i.x = x;
        i.y = y;
        i.oldinum = -1;
        i.inum = inum;
        i.on = on;
        i.p = il;
    }

    function STlib_updateMultIcon(mi as st_multicon_t, refresh as Boolean) as Void {
        var w;
        var h;
        var x;
        var y;

        if (mi.on
            && (mi.oldinum != mi.inum || refresh)
            && (mi.inum != -1)) {
            if (mi.oldinum != -1) {
                x = mi.x - P_LeftOffset(mi.p[mi.oldinum]);
                y = mi.y - P_TopOffset(mi.p[mi.oldinum]);
                w = P_Width(mi.p[mi.oldinum]);
                h = P_Height(mi.p[mi.oldinum]);

                if (y - ST_Y < 0) {
                    ISystem.I_Error("updateMultIcon: y - ST_Y < 0");
                }

                V_CopyRect(x, y, w, h);
            }
            V_DrawPatch(mi.x, mi.y, mi.p[mi.inum]);
            mi.oldinum = mi.inum;
        }
    }

    function STlib_initBinIcon(b as st_binicon_t, x as Number, y as Number, i as Number,
                               val as Boolean, on as Boolean) as Void {
        b.x = x;
        b.y = y;
        b.oldval = false;
        b.val = val;
        b.on = on;
        b.p = i;
    }

    function STlib_updateBinIcon(bi as st_binicon_t, refresh as Boolean) as Void {
        var x;
        var y;
        var w;
        var h;

        if (bi.on
            && (bi.oldval != bi.val || refresh)) {
            x = bi.x - P_LeftOffset(bi.p);
            y = bi.y - P_TopOffset(bi.p);
            w = P_Width(bi.p);
            h = P_Height(bi.p);

            if (y - ST_Y < 0) {
                ISystem.I_Error("updateBinIcon: y - ST_Y < 0");
            }

            if (bi.val) {
                V_DrawPatch(bi.x, bi.y, bi.p);
            } else {
                V_CopyRect(x, y, w, h);
            }

            bi.oldval = bi.val;
        }
    }
}
