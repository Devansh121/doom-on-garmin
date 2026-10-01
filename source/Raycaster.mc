import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Wolfenstein-style DDA raycaster. One ray per screen column strip.
class Raycaster {

    const MAP_W = 16;
    const MAP_H = 16;

    // 0 = empty, 1..4 = wall types. Border must be solid so rays always hit.
    var map as Array<Number> = [
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,0,0,2,2,0,0,0,0,0,3,3,3,0,0,1,
        1,0,0,2,0,0,0,0,0,0,0,0,3,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,3,0,0,1,
        1,0,0,0,0,0,4,4,4,0,0,0,0,0,0,1,
        1,0,0,0,0,0,4,0,4,0,0,0,0,0,0,1,
        1,0,0,0,0,0,4,0,4,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,1,
        1,0,3,3,0,0,0,0,0,0,0,0,2,0,0,1,
        1,0,0,3,0,0,0,0,0,0,0,0,2,0,0,1,
        1,0,0,0,0,0,0,2,2,2,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    ];

    // [lit side, shaded side] per wall type
    var wallColors as Array<Array<Number>> = [
        [0x000000, 0x000000],
        [0xAA5500, 0x552A00],
        [0x888888, 0x444444],
        [0x0055AA, 0x002A55],
        [0xAA0000, 0x550000]
    ];

    var posX as Float = 2.5;
    var posY as Float = 2.5;
    var dirX as Float = 1.0;
    var dirY as Float = 0.0;
    var planeX as Float = 0.0;
    var planeY as Float = 0.66;

    function initialize() {
    }

    function move(dist as Float) as Void {
        var nx = posX + dirX * dist;
        var ny = posY + dirY * dist;
        if (map[posY.toNumber() * MAP_W + nx.toNumber()] == 0) {
            posX = nx;
        }
        if (map[ny.toNumber() * MAP_W + posX.toNumber()] == 0) {
            posY = ny;
        }
    }

    function rotate(angle as Float) as Void {
        var c = Math.cos(angle);
        var s = Math.sin(angle);
        var odx = dirX;
        dirX = dirX * c - dirY * s;
        dirY = odx * s + dirY * c;
        var opx = planeX;
        planeX = planeX * c - planeY * s;
        planeY = opx * s + planeY * c;
    }

    function render(dc as Graphics.Dc, cols as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var half = h / 2;
        var colW = (w + cols - 1) / cols;

        dc.setColor(0x333333, 0x333333);
        dc.fillRectangle(0, 0, w, half);
        dc.setColor(0x555533, 0x555533);
        dc.fillRectangle(0, half, w, h - half);

        for (var x = 0; x < cols; x++) {
            var camX = 2.0 * x / cols - 1.0;
            var rdx = dirX + planeX * camX;
            var rdy = dirY + planeY * camX;
            var mx = posX.toNumber();
            var my = posY.toNumber();
            var ddx = rdx == 0.0 ? 1000000.0 : (1.0 / rdx).abs();
            var ddy = rdy == 0.0 ? 1000000.0 : (1.0 / rdy).abs();
            var sx;
            var sy;
            var sdx;
            var sdy;
            if (rdx < 0) {
                sx = -1;
                sdx = (posX - mx) * ddx;
            } else {
                sx = 1;
                sdx = (mx + 1.0 - posX) * ddx;
            }
            if (rdy < 0) {
                sy = -1;
                sdy = (posY - my) * ddy;
            } else {
                sy = 1;
                sdy = (my + 1.0 - posY) * ddy;
            }

            var side = 0;
            var hit = 0;
            while (hit == 0) {
                if (sdx < sdy) {
                    sdx += ddx;
                    mx += sx;
                    side = 0;
                } else {
                    sdy += ddy;
                    my += sy;
                    side = 1;
                }
                hit = map[my * MAP_W + mx];
            }

            // Perpendicular distance avoids fisheye.
            var dist = side == 0 ? sdx - ddx : sdy - ddy;
            if (dist < 0.05) {
                dist = 0.05;
            }
            var lineH = (h / dist).toNumber();
            if (lineH > h) {
                lineH = h;
            }

            var color = wallColors[hit][side];
            dc.setColor(color, color);
            dc.fillRectangle(x * colW, half - lineH / 2, colW, lineH);
        }
    }
}
