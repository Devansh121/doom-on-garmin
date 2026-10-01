// r_plane.c
//
// Here is a core component: drawing the floors and ceilings,
//  while maintaining a per column clipping list only.
// Moreover, the sky areas have to be determined.
//
// Floors and ceilings are drawn in a single flat color, so the
// per-column top/bottom lists of visplane_t aren't needed: r_segs fills
// each column's floor and ceiling span with its plane's color right when
// it marks it, which covers the same pixels R_DrawPlanes would. What's
// left here is the plane bookkeeping (R_FindPlane) and the clip arrays.

import Toybox.Lang;

module RPlane {

    const MAXVISPLANES = 128;

    // visplane_t, one array per field
    var visplanes_height as Array<Number> = new [MAXVISPLANES] as Array<Number>;
    var visplanes_picnum as Array<Number> = new [MAXVISPLANES] as Array<Number>;
    var visplanes_lightlevel as Array<Number> = new [MAXVISPLANES] as Array<Number>;
    var lastvisplane as Number = 0;

    // -1 (NULL) when the plane isn't visible from this subsector
    var floorplane as Number = -1;
    var ceilingplane as Number = -1;

    //
    // Clip values are the solid pixel bounding the range.
    //  floorclip starts out SCREENHEIGHT
    //  ceilingclip starts out -1
    //
    var floorclip as Array<Number> = new [RMain.SCREENWIDTH] as Array<Number>;
    var ceilingclip as Array<Number> = new [RMain.SCREENWIDTH] as Array<Number>;

    //
    // R_ClearPlanes
    // At begining of frame.
    //
    function R_ClearPlanes() as Void {
        var fc = floorclip;
        var cc = ceilingclip;
        var vh = RMain.viewheight;

        // opening / clipping determination
        for (var i = 0; i < RMain.viewwidth; i++) {
            fc[i] = vh;
            cc[i] = -1;
        }

        lastvisplane = 0;
    }

    //
    // R_FindPlane
    //
    function R_FindPlane(height as Number, picnum as Number, lightlevel as Number) as Number {
        if (picnum == RData.skyflatnum) {
            height = 0;  // all skys map together
            lightlevel = 0;
        }

        var check;
        for (check = 0; check < lastvisplane; check++) {
            if (height == visplanes_height[check]
                && picnum == visplanes_picnum[check]
                && lightlevel == visplanes_lightlevel[check]) {
                break;
            }
        }

        if (check < lastvisplane) {
            return check;
        }

        if (lastvisplane == MAXVISPLANES) {
            ISystem.I_Error("R_FindPlane: no more visplanes");
        }

        lastvisplane++;

        visplanes_height[check] = height;
        visplanes_picnum[check] = picnum;
        visplanes_lightlevel[check] = lightlevel;

        return check;
    }
}
