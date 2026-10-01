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

    // Texture and flat numbers by name, for the *NumForName lookups
    // p_spec and p_switch do. Built from the name lists wad2ciq.py
    // writes; a linear search per lookup would be too slow for the
    // watchdog at P_Init. Flat numbers count the F1_START style markers.
    var texturenums as Dictionary<String, Number> = {} as Dictionary<String, Number>;
    var flatnums as Dictionary<String, Number> = {} as Dictionary<String, Number>;

    // needed for texture pegging
    var textureheight as Array<Number> = [] as Array<Number>;

    // for global animation
    var flattranslation as Array<Number> = [] as Array<Number>;
    var texturetranslation as Array<Number> = [] as Array<Number>;

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

        // R_CheckTextureNumForName takes the first match, so fill from
        // the end; W_CheckNumForName takes the last, so fill from the start.
        var names = WatchUi.loadResource(Rez.JsonData.texturenames) as Array<String>;
        texturenums = {} as Dictionary<String, Number>;
        for (var i = names.size() - 1; i >= 0; i--) {
            texturenums.put(names[i], i);
        }
        names = WatchUi.loadResource(Rez.JsonData.flatnames) as Array<String>;
        flatnums = {} as Dictionary<String, Number>;
        for (var i = 0; i < names.size(); i++) {
            flatnums.put(names[i], i);
        }

        // R_InitTextures: textureheight[i] = texture->height<<FRACBITS
        textureheight = WatchUi.loadResource(Rez.JsonData.textureheights) as Array<Number>;
        for (var i = 0; i < numtextures; i++) {
            textureheight[i] = textureheight[i] << MFixed.FRACBITS;
        }

        // Create translation table for global animation.
        texturetranslation = new [numtextures + 1] as Array<Number>;
        for (var i = 0; i < numtextures; i++) {
            texturetranslation[i] = i;
        }

        // R_InitFlats: Create translation table for global animation.
        flattranslation = new [numflats + 1] as Array<Number>;
        for (var i = 0; i < numflats; i++) {
            flattranslation[i] = i;
        }

        skyflatnum = (WatchUi.loadResource(Rez.JsonData.skyflatnum) as Array<Number>)[0];
        skytexture = (WatchUi.loadResource(Rez.JsonData.skytexture) as Array<Number>)[0];
    }

    //
    // R_FlatNumForName
    // Retrieval, get a flat number for a flat name.
    //
    function R_FlatNumForName(name as String) as Number {
        var i = W_CheckFlatNumForName(name);

        if (i == -1) {
            ISystem.I_Error("R_FlatNumForName: " + name + " not found");
        }
        return i;
    }

    // Stand-in for W_CheckNumForName(name) - firstflat: there's no lump
    // directory on the watch, only the flat names. -1 if not found.
    function W_CheckFlatNumForName(name as String) as Number {
        var i = flatnums.get(name.toUpper());
        return i != null ? i : -1;
    }

    //
    // R_CheckTextureNumForName
    // Check whether texture is available.
    // Filter out NoTexture indicator.
    //
    function R_CheckTextureNumForName(name as String) as Number {
        // "NoTexture" marker.
        if (name.substring(0, 1).equals("-")) {
            return 0;
        }

        // for (i=0 ; i<numtextures ; i++)
        //     if (!strncasecmp (textures[i]->name, name, 8) )
        //         return i;
        var i = texturenums.get(name.toUpper());
        if (i != null) {
            return i;
        }

        return -1;
    }

    //
    // R_TextureNumForName
    // Calls R_CheckTextureNumForName,
    //  aborts with error message.
    //
    function R_TextureNumForName(name as String) as Number {
        var i = R_CheckTextureNumForName(name);

        if (i == -1) {
            ISystem.I_Error("R_TextureNumForName: " + name + " not found");
        }
        return i;
    }
}
