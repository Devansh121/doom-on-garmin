// r_draw.c
//
// The actual span/column drawing functions.
// Here find the main potential for optimization,
//  e.g. inline assembly, different algorithms.
//
// There's no byte framebuffer to poke pixels into. The view is a
// BufferedBitmap and a "column" is a filled rectangle: each of the
// viewwidth columns covers a few screen pixels, and rows are scaled from
// viewheight to the bitmap height so the 4:3 aspect of the original
// (320x200 shown on a 4:3 monitor) is kept.

import Toybox.Graphics;
import Toybox.Lang;

module RDraw {

    // Size of the view bitmap on the watch, in screen pixels. A full
    // 320x200 view is 400x300 (4:3), so rows are 1.5 pixels and a
    // smaller viewheight (with the status bar) gets a shorter bitmap.
    const VIEW_W = 400;
    var VIEW_H as Number = 300;

    var viewbitmap as Graphics.BufferedBitmap? = null;
    var dc as Graphics.Dc? = null;

    // Screen pixel where column x / row y starts. One extra entry so
    // colx[x + 1] - colx[x] is the column's width.
    var colx as Array<Number> = [] as Array<Number>;
    var rowy as Array<Number> = [] as Array<Number>;

    var lastcolor as Number = -1;

    //
    // R_InitBuffer
    // Creats lookup tables that avoid
    //  multiplies and other hazzles
    //  for getting the framebuffer address
    //  of a pixel to draw.
    //
    function R_InitBuffer(width as Number, height as Number) as Void {
        colx = new [width + 1] as Array<Number>;
        for (var x = 0; x <= width; x++) {
            colx[x] = x * VIEW_W / width;
        }
        VIEW_H = height * 3 / 2;
        rowy = new [height + 1] as Array<Number>;
        for (var y = 0; y <= height; y++) {
            rowy[y] = y * VIEW_H / height;
        }

        if (viewbitmap == null || (viewbitmap as Graphics.BufferedBitmap).getHeight() != VIEW_H) {
            viewbitmap = null;
            dc = null;
            var ref = Graphics.createBufferedBitmap({:width => VIEW_W, :height => VIEW_H});
            viewbitmap = ref.get() as Graphics.BufferedBitmap;
            dc = (viewbitmap as Graphics.BufferedBitmap).getDc();
        }
        lastcolor = -1;
    }

    //
    // R_DrawColumn
    // Fills column x from row yl to yh (inclusive) with color.
    //
    function R_DrawColumn(x as Number, yl as Number, yh as Number, color as Number) as Void {
        var d = dc as Graphics.Dc;
        if (color != lastcolor) {
            d.setColor(color, color);
            lastcolor = color;
        }
        var px = colx[x];
        var py = rowy[yl];
        d.fillRectangle(px, py, colx[x + 1] - px, rowy[yh + 1] - py);
    }
}
