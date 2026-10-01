// doomdata.h
//
// All external data is defined here, most of the data is loaded into
// different structures at run time. Only the constants survive the move
// to Monkey C; the map structs are unpacked by tools/wad2ciq.py.

import Toybox.Lang;

module DoomData {

    // Lump order in a map WAD: each map needs a couple of lumps
    // to provide a complete scene geometry description.
    const ML_LABEL = 0;     // A separator, name, ExMx or MAPxx
    const ML_THINGS = 1;    // Monsters, items..
    const ML_LINEDEFS = 2;  // LineDefs, from editing
    const ML_SIDEDEFS = 3;  // SideDefs, from editing
    const ML_VERTEXES = 4;  // Vertices, edited and BSP splits generated
    const ML_SEGS = 5;      // LineSegs, from LineDefs split by BSP
    const ML_SSECTORS = 6;  // SubSectors, list of LineSegs
    const ML_NODES = 7;     // BSP nodes
    const ML_SECTORS = 8;   // Sectors, from editing
    const ML_REJECT = 9;    // LUT, sector-sector visibility
    const ML_BLOCKMAP = 10; // LUT, motion clipping, walls/grid element

    // LineDef attributes.

    // Solid, is an obstacle.
    const ML_BLOCKING = 1;
    // Blocks monsters only.
    const ML_BLOCKMONSTERS = 2;
    // Backside will not be present at all
    //  if not two sided.
    const ML_TWOSIDED = 4;
    // upper texture unpegged
    const ML_DONTPEGTOP = 8;
    // lower texture unpegged
    const ML_DONTPEGBOTTOM = 16;
    // In AutoMap: don't map as two sided: IT'S A SECRET!
    const ML_SECRET = 32;
    // Sound rendering: don't let sound cross two of these.
    const ML_SOUNDBLOCK = 64;
    // Don't draw on the automap at all.
    const ML_DONTDRAW = 128;
    // Set if already seen, thus drawn in automap.
    const ML_MAPPED = 256;

    // Indicate a leaf.
    const NF_SUBSECTOR = 0x8000;
}
