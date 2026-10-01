// m_bbox.c / m_bbox.h
//
// Main loop menu stuff.
// Random number LUT.
// Default Config File.
// PCX Screenshots.

import Toybox.Lang;

module MBBox {

    // bbox coordinates
    const BOXTOP = 0;
    const BOXBOTTOM = 1;
    const BOXLEFT = 2;
    const BOXRIGHT = 3;

    function M_ClearBox(box as Array<Number>) as Void {
        box[BOXTOP] = DoomType.MININT;
        box[BOXRIGHT] = DoomType.MININT;
        box[BOXBOTTOM] = DoomType.MAXINT;
        box[BOXLEFT] = DoomType.MAXINT;
    }

    function M_AddToBox(box as Array<Number>, x as Number, y as Number) as Void {
        if (x < box[BOXLEFT]) {
            box[BOXLEFT] = x;
        } else if (x > box[BOXRIGHT]) {
            box[BOXRIGHT] = x;
        }
        if (y < box[BOXBOTTOM]) {
            box[BOXBOTTOM] = y;
        } else if (y > box[BOXTOP]) {
            box[BOXTOP] = y;
        }
    }
}
