// r_defs.h
//
// Refresh/rendering module, shared data struct definitions.
//
// The structs (vertex_t, sector_t, line_t, ...) live in PSetup as one
// array per field, indexed by what used to be the pointer's offset into
// the C array. NULL pointers become -1.

import Toybox.Lang;

module RDefs {

    // Move clipping aid for LineDefs.
    const ST_HORIZONTAL = 0;
    const ST_VERTICAL = 1;
    const ST_POSITIVE = 2;
    const ST_NEGATIVE = 3;
}
