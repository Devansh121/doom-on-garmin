// r_segs.c
//
// All the clipping: columns, horizontal spans, sky columns.

import Toybox.Lang;

module RSegs {

    var rw_angle1 as Number = 0;
    var rw_normalangle as Number = 0;
    var rw_distance as Number = 0;

    // index of the next free drawseg (ds_p)
    var ds_p as Number = 0;

    // Rough count of work done this frame, so the BSP walk knows when to
    // hand control back before the watchdog trips.
    var work as Number = 0;

    // When set, R_StoreWallRange appends [curline, start, stop] for tests.
    var trace as Array<Number>? = null;

    //
    // R_StoreWallRange
    // A wall segment will be drawn
    //  between start and stop pixels (inclusive).
    //
    // Only records the range for now; the drawing comes next.
    function R_StoreWallRange(start as Number, stop as Number) as Void {
        work += stop - start + 1;
        if (trace != null) {
            trace.add(RBsp.curline);
            trace.add(start);
            trace.add(stop);
        }
    }
}
