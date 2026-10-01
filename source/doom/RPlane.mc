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

(:extendedCode)
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
        RSegs.lastopening = RSegs.FIRSTOPENING;
    }

    // R_FindPlane for a sector's floor or ceiling, remembered per sector
    // for the rest of the frame: a sector's height, pic and light can't
    // change mid-frame, so R_FindPlane would return the same plane, and
    // its linear search runs twice per subsector otherwise.
    var cacheframe as Array<Number> = [] as Array<Number>;
    var cacheplane as Array<Number> = [] as Array<Number>;

    function R_FindSectorPlane(sec as Number, ceiling as Boolean) as Number {
        var n = PSetup.numsectors * 2;
        if (cacheframe.size() != n) {
            cacheframe = new [n] as Array<Number>;
            cacheplane = new [n] as Array<Number>;
            for (var i = 0; i < n; i++) {
                cacheframe[i] = -1;
            }
        }
        var k = sec * 2 + (ceiling ? 1 : 0);
        if (cacheframe[k] == RMain.framecount) {
            return cacheplane[k];
        }
        var plane = ceiling
            ? R_FindPlane(PSetup.sectors_ceilingheight[sec], PSetup.sectors_ceilingpic[sec], PSetup.sectors_lightlevel[sec])
            : R_FindPlane(PSetup.sectors_floorheight[sec], PSetup.sectors_floorpic[sec], PSetup.sectors_lightlevel[sec]);
        cacheframe[k] = RMain.framecount;
        cacheplane[k] = plane;
        return plane;
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
