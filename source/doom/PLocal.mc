// p_local.h
//
// Play functions, animation, global header.

import Toybox.Lang;

module PLocal {

    // Bounding box coordinate storage.
    const VIEWHEIGHT = 41 * MFixed.FRACUNIT;

    const MAPBLOCKUNITS = 128;
    const MAPBLOCKSIZE = MAPBLOCKUNITS * MFixed.FRACUNIT;
    const MAPBLOCKSHIFT = MFixed.FRACBITS + 7;
    const MAPBMASK = MAPBLOCKSIZE - 1;
    const MAPBTOFRAC = MAPBLOCKSHIFT - MFixed.FRACBITS;

    // MAXRADIUS is for precalculated sector block boxes
    // the spider demon is larger,
    // but we do not have any moving sectors nearby
    const MAXRADIUS = 32 * MFixed.FRACUNIT;
}
