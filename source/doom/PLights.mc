// p_lights.c
//
// Handle Sector base lighting effects.
// Muzzle flash?
//
// fireflicker_t (TF_FIRELIGHT), lightflash_t (TF_LIGHTFLASH), strobe_t
// (TF_STROBEFLASH) and glow_t (TF_GLOW) are PTick thinkers whose fields
// are PTick.thinkers_data[t], indexed with the constants below in the
// structs' order. Light thinkers don't set sector->specialdata.

import Toybox.Lang;

module PLights {

    // fireflicker_t fields
    const FF_SECTOR = 0;
    const FF_COUNT = 1;
    const FF_MAXLIGHT = 2;
    const FF_MINLIGHT = 3;
    const FF_SIZE = 4;

    // lightflash_t fields
    const LF_SECTOR = 0;
    const LF_COUNT = 1;
    const LF_MAXLIGHT = 2;
    const LF_MINLIGHT = 3;
    const LF_MAXTIME = 4;
    const LF_MINTIME = 5;
    const LF_SIZE = 6;

    // strobe_t fields
    const SB_SECTOR = 0;
    const SB_COUNT = 1;
    const SB_MINLIGHT = 2;
    const SB_MAXLIGHT = 3;
    const SB_DARKTIME = 4;
    const SB_BRIGHTTIME = 5;
    const SB_SIZE = 6;

    // glow_t fields
    const GL_SECTOR = 0;
    const GL_MINLIGHT = 1;
    const GL_MAXLIGHT = 2;
    const GL_DIRECTION = 3;
    const GL_SIZE = 4;

    // Z_Malloc (size, PU_LEVSPEC, 0) and P_AddThinker for a light. The
    // fields start at 0 rather than whatever the zone had in it.
    function newLight(size as Number) as Number {
        var t = PTick.P_AllocThinker();
        var d = new [size] as Array<Number>;
        for (var i = 0; i < size; i++) {
            d[i] = 0;
        }
        PTick.thinkers_data[t] = d;
        PTick.P_AddThinker(t);
        return t;
    }

    //
    // FIRELIGHT FLICKER
    //

    //
    // T_FireFlicker
    //
    function T_FireFlicker(flick as Number) as Void {
        var f = PTick.thinkers_data[flick] as Array<Number>;
        var lightlevel = PSetup.sectors_lightlevel;
        var sector = f[FF_SECTOR];

        f[FF_COUNT]--;
        if (f[FF_COUNT] != 0) {
            return;
        }

        var amount = (MRandom.P_Random() & 3) * 16;

        if (lightlevel[sector] - amount < f[FF_MINLIGHT]) {
            lightlevel[sector] = f[FF_MINLIGHT];
        } else {
            lightlevel[sector] = f[FF_MAXLIGHT] - amount;
        }

        f[FF_COUNT] = 4;
    }

    //
    // P_SpawnFireFlicker
    //
    function P_SpawnFireFlicker(sector as Number) as Void {
        // Note that we are resetting sector attributes.
        // Nothing special about it during gameplay.
        PSetup.sectors_special[sector] = 0;

        var flick = newLight(FF_SIZE);
        var f = PTick.thinkers_data[flick] as Array<Number>;

        PTick.thinkers_function[flick] = PTick.TF_FIRELIGHT;
        f[FF_SECTOR] = sector;
        f[FF_MAXLIGHT] = PSetup.sectors_lightlevel[sector];
        f[FF_MINLIGHT] = PSpec.P_FindMinSurroundingLight(sector, PSetup.sectors_lightlevel[sector]) + 16;
        f[FF_COUNT] = 4;
    }

    //
    // BROKEN LIGHT FLASHING
    //

    //
    // T_LightFlash
    // Do flashing lights.
    //
    function T_LightFlash(flash as Number) as Void {
        var f = PTick.thinkers_data[flash] as Array<Number>;
        var lightlevel = PSetup.sectors_lightlevel;
        var sector = f[LF_SECTOR];

        f[LF_COUNT]--;
        if (f[LF_COUNT] != 0) {
            return;
        }

        if (lightlevel[sector] == f[LF_MAXLIGHT]) {
            lightlevel[sector] = f[LF_MINLIGHT];
            f[LF_COUNT] = (MRandom.P_Random() & f[LF_MINTIME]) + 1;
        } else {
            lightlevel[sector] = f[LF_MAXLIGHT];
            f[LF_COUNT] = (MRandom.P_Random() & f[LF_MAXTIME]) + 1;
        }
    }

    //
    // P_SpawnLightFlash
    // After the map has been loaded, scan each sector
    // for specials that spawn thinkers
    //
    function P_SpawnLightFlash(sector as Number) as Void {
        // nothing special about it during gameplay
        PSetup.sectors_special[sector] = 0;

        var flash = newLight(LF_SIZE);
        var f = PTick.thinkers_data[flash] as Array<Number>;

        PTick.thinkers_function[flash] = PTick.TF_LIGHTFLASH;
        f[LF_SECTOR] = sector;
        f[LF_MAXLIGHT] = PSetup.sectors_lightlevel[sector];

        f[LF_MINLIGHT] = PSpec.P_FindMinSurroundingLight(sector, PSetup.sectors_lightlevel[sector]);
        f[LF_MAXTIME] = 64;
        f[LF_MINTIME] = 7;
        f[LF_COUNT] = (MRandom.P_Random() & f[LF_MAXTIME]) + 1;
    }

    //
    // STROBE LIGHT FLASHING
    //

    //
    // T_StrobeFlash
    //
    function T_StrobeFlash(flash as Number) as Void {
        var f = PTick.thinkers_data[flash] as Array<Number>;
        var lightlevel = PSetup.sectors_lightlevel;
        var sector = f[SB_SECTOR];

        f[SB_COUNT]--;
        if (f[SB_COUNT] != 0) {
            return;
        }

        if (lightlevel[sector] == f[SB_MINLIGHT]) {
            lightlevel[sector] = f[SB_MAXLIGHT];
            f[SB_COUNT] = f[SB_BRIGHTTIME];
        } else {
            lightlevel[sector] = f[SB_MINLIGHT];
            f[SB_COUNT] = f[SB_DARKTIME];
        }
    }

    //
    // P_SpawnStrobeFlash
    // After the map has been loaded, scan each sector
    // for specials that spawn thinkers
    //
    function P_SpawnStrobeFlash(sector as Number, fastOrSlow as Number, inSync as Number) as Void {
        var flash = newLight(SB_SIZE);
        var f = PTick.thinkers_data[flash] as Array<Number>;

        f[SB_SECTOR] = sector;
        f[SB_DARKTIME] = fastOrSlow;
        f[SB_BRIGHTTIME] = PSpec.STROBEBRIGHT;
        PTick.thinkers_function[flash] = PTick.TF_STROBEFLASH;
        f[SB_MAXLIGHT] = PSetup.sectors_lightlevel[sector];
        f[SB_MINLIGHT] = PSpec.P_FindMinSurroundingLight(sector, PSetup.sectors_lightlevel[sector]);

        if (f[SB_MINLIGHT] == f[SB_MAXLIGHT]) {
            f[SB_MINLIGHT] = 0;
        }

        // nothing special about it during gameplay
        PSetup.sectors_special[sector] = 0;

        if (inSync == 0) {
            f[SB_COUNT] = (MRandom.P_Random() & 7) + 1;
        } else {
            f[SB_COUNT] = 1;
        }
    }

    //
    // Start strobing lights (usually from a trigger)
    //
    function EV_StartLightStrobing(line as Number) as Void {
        // while ((secnum = P_FindSectorFromLineTag(line,secnum)) >= 0):
        // Monkey C has no assignment in expressions.
        for (var secnum = PSpec.P_FindSectorFromLineTag(line, -1); secnum >= 0;
             secnum = PSpec.P_FindSectorFromLineTag(line, secnum)) {
            var sec = secnum;
            if (PSetup.sectors_specialdata[sec] != -1) {
                continue;
            }

            P_SpawnStrobeFlash(sec, PSpec.SLOWDARK, 0);
        }
    }

    //
    // TURN LINE'S TAG LIGHTS OFF
    //
    // Walks every sector; fine for the shareware maps.
    //
    function EV_TurnTagLightsOff(line as Number) as Void {
        var tags = PSetup.sectors_tag;
        var lightlevel = PSetup.sectors_lightlevel;
        var buffer = PSetup.linebuffer;
        var tag = PSetup.lines_tag[line];

        for (var j = 0; j < PSetup.numsectors; j++) {
            var sector = j;
            if (tags[sector] == tag) {
                var min = lightlevel[sector];
                var first = PSetup.sectors_lines[sector];
                for (var i = 0; i < PSetup.sectors_linecount[sector]; i++) {
                    var templine = buffer[first + i];
                    var tsec = PSpec.getNextSector(templine, sector);
                    if (tsec == -1) {
                        continue;
                    }
                    if (lightlevel[tsec] < min) {
                        min = lightlevel[tsec];
                    }
                }
                lightlevel[sector] = min;
            }
        }
    }

    //
    // TURN LINE'S TAG LIGHTS ON
    //
    // Walks every sector; fine for the shareware maps.
    //
    function EV_LightTurnOn(line as Number, bright as Number) as Void {
        var tags = PSetup.sectors_tag;
        var lightlevel = PSetup.sectors_lightlevel;
        var buffer = PSetup.linebuffer;
        var tag = PSetup.lines_tag[line];

        for (var i = 0; i < PSetup.numsectors; i++) {
            var sector = i;
            if (tags[sector] == tag) {
                // bright = 0 means to search
                // for highest light level
                // surrounding sector
                if (bright == 0) {
                    var first = PSetup.sectors_lines[sector];
                    for (var j = 0; j < PSetup.sectors_linecount[sector]; j++) {
                        var templine = buffer[first + j];
                        var temp = PSpec.getNextSector(templine, sector);

                        if (temp == -1) {
                            continue;
                        }

                        if (lightlevel[temp] > bright) {
                            bright = lightlevel[temp];
                        }
                    }
                }
                lightlevel[sector] = bright;
            }
        }
    }

    //
    // Spawn glowing light
    //

    function T_Glow(g as Number) as Void {
        var d = PTick.thinkers_data[g] as Array<Number>;
        var lightlevel = PSetup.sectors_lightlevel;
        var sector = d[GL_SECTOR];

        switch (d[GL_DIRECTION]) {
            case -1:
                // DOWN
                lightlevel[sector] -= PSpec.GLOWSPEED;
                if (lightlevel[sector] <= d[GL_MINLIGHT]) {
                    lightlevel[sector] += PSpec.GLOWSPEED;
                    d[GL_DIRECTION] = 1;
                }
                break;

            case 1:
                // UP
                lightlevel[sector] += PSpec.GLOWSPEED;
                if (lightlevel[sector] >= d[GL_MAXLIGHT]) {
                    lightlevel[sector] -= PSpec.GLOWSPEED;
                    d[GL_DIRECTION] = -1;
                }
                break;
        }
    }

    function P_SpawnGlowingLight(sector as Number) as Void {
        var g = newLight(GL_SIZE);
        var d = PTick.thinkers_data[g] as Array<Number>;

        d[GL_SECTOR] = sector;
        d[GL_MINLIGHT] = PSpec.P_FindMinSurroundingLight(sector, PSetup.sectors_lightlevel[sector]);
        d[GL_MAXLIGHT] = PSetup.sectors_lightlevel[sector];
        PTick.thinkers_function[g] = PTick.TF_GLOW;
        d[GL_DIRECTION] = -1;

        PSetup.sectors_special[sector] = 0;
    }
}
