// r_data.c
//
// Preparation of data for rendering,
// generation of lookups, caching, retrieval by name.
//
// Walls, floors and ceilings are drawn as flat colors, so instead of
// textures, flats and the COLORMAP lump this only loads each texture's
// and flat's average color under every light level, baked by
// tools/wad2ciq.py. colors[num * NUMCOLORMAPS + level] is 0xRRGGBB.

import Toybox.Lang;
import Toybox.WatchUi;

module RData {

    var numtextures as Number = 0;
    var texturecolors as Array<Number> = [] as Array<Number>;

    var numflats as Number = 0;
    var flatcolors as Array<Number> = [] as Array<Number>;

    // r_sky.c
    var skyflatnum as Number = 0;
    var skytexture as Number = 0;

    //
    // R_InitData
    // Locates all the lumps
    //  that will be used by all views
    // Must be called after W_Init.
    //
    function R_InitData() as Void {
        texturecolors = WatchUi.loadResource(Rez.JsonData.texturecolors) as Array<Number>;
        numtextures = texturecolors.size() / RMain.NUMCOLORMAPS;
        flatcolors = WatchUi.loadResource(Rez.JsonData.flatcolors) as Array<Number>;
        numflats = flatcolors.size() / RMain.NUMCOLORMAPS;

        skyflatnum = (WatchUi.loadResource(Rez.JsonData.skyflatnum) as Array<Number>)[0];
        skytexture = (WatchUi.loadResource(Rez.JsonData.skytexture) as Array<Number>)[0];
    }
}
