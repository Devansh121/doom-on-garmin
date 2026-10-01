// p_local.h
//
// Play functions, animation, global header.

import Toybox.Lang;

module PLocal {

    const FLOATSPEED = MFixed.FRACUNIT * 4;

    const MAXHEALTH = 100;
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

    // player radius for movement checking
    const PLAYERRADIUS = 16 * MFixed.FRACUNIT;

    const GRAVITY = MFixed.FRACUNIT;
    const MAXMOVE = 30 * MFixed.FRACUNIT;

    const USERANGE = 64 * MFixed.FRACUNIT;
    const MELEERANGE = 64 * MFixed.FRACUNIT;
    const MISSILERANGE = 32 * 64 * MFixed.FRACUNIT;

    // follow a player exlusively for 3 seconds
    const BASETHRESHOLD = 100;

    //
    // P_MAPUTL
    //
    const MAXINTERCEPTS = 128;

    const PT_ADDLINES = 1;
    const PT_ADDTHINGS = 2;
    const PT_EARLYOUT = 4;
}
