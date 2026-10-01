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
