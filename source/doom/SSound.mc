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
