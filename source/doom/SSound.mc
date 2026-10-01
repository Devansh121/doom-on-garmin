// s_sound.c
//
// The not so system specific sound interface.
//
// Not ported yet: every function is a stub with the signature the rest
// of the code calls, returning a harmless default.

import Toybox.Lang;

module SSound {

    // sfxenum_t values from sounds.h, used by p_mobj.c.
    const sfx_oof = 34;
    const sfx_telept = 35;
    const sfx_itmbk = 90;

    // sounds.h sfxenum_t, the ones p_pspr / p_inter use.
    const sfx_pistol = 1;
    const sfx_shotgn = 2;
    const sfx_dshtgn = 4;
    const sfx_dbopn = 5;
    const sfx_dbcls = 6;
    const sfx_dbload = 7;
    const sfx_bfg = 9;
    const sfx_sawup = 10;
    const sfx_sawidl = 11;
    const sfx_sawful = 12;
    const sfx_sawhit = 13;
    const sfx_itemup = 32;
    const sfx_wpnup = 33;
    const sfx_punch = 83;
    const sfx_getpow = 93;
    // end of p_pspr / p_inter sounds
    // sfx_* numbers from sounds.h used by p_map.c
    const sfx_noway = 81;
    // sounds.h sfxenum_t, the ones p_enemy uses (sfx_telept is above)
    const sfx_slop = 31;
    const sfx_posit1 = 36;
    const sfx_posit2 = 37;
    const sfx_posit3 = 38;
    const sfx_bgsit1 = 39;
    const sfx_bgsit2 = 40;
    const sfx_skepch = 53;
    const sfx_vilatk = 54;
    const sfx_claw = 55;
    const sfx_skeswg = 56;
    const sfx_pldeth = 57;
    const sfx_pdiehi = 58;
    const sfx_podth1 = 59;
    const sfx_podth2 = 60;
    const sfx_podth3 = 61;
    const sfx_bgdth1 = 62;
    const sfx_bgdth2 = 63;
    const sfx_bspwlk = 79;
    const sfx_barexp = 82;
    const sfx_hoof = 84;
    const sfx_metal = 85;
    const sfx_flame = 91;
    const sfx_flamst = 92;
    const sfx_bospit = 94;
    const sfx_boscub = 95;
    const sfx_bossit = 96;
    const sfx_bospn = 97;
    const sfx_bosdth = 98;
    const sfx_manatk = 99;
    // end of p_enemy sounds
    //
    // sounds.h sfx numbers used by the p_spec family (p_doors, p_plats,
    // p_floor, p_ceilng, p_switch; sfx_oof and sfx_telept are above).
    //
    const sfx_pstart = 18;
    const sfx_pstop = 19;
    const sfx_doropn = 20;
    const sfx_dorcls = 21;
    const sfx_stnmov = 22;
    const sfx_swtchn = 23;
    const sfx_swtchx = 24;
    const sfx_bdopn = 88;
    const sfx_bdcls = 89;

    // Sectors play sounds from their soundorg (a degenmobj_t the C code
    // casts to mobj_t*). There's no mobj number for that, so a sector's
    // origin is passed as -2 - sector; -1 stays NULL.
    function S_SectorOrigin(sector as Number) as Number {
        return -2 - sector;
    }
    // end of the p_spec block

    function S_Start() as Void {
    }

    function S_StartSound(origin as Number, sound_id as Number) as Void {
    }

    function S_StopSound(origin as Number) as Void {
    }

    function S_StartMusic(music_id as Number) as Void {
    }

    function S_ChangeMusic(music_id as Number, looping as Number) as Void {
    }

    function S_UpdateSounds(listener as Number) as Void {
    }
}
