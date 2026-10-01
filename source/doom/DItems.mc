// d_items.c / d_items.h
//
// DESCRIPTION:
//	(none in d_items.c; it holds the weapon table, d_items.h says
//	"Items: key cards, artifacts, weapon, ammunition.")
//
// weaponinfo_t is flattened like the Info tables:
// weaponinfo[w * WI_SIZE + WI_AMMO] is weaponinfo[w].ammo.

import Toybox.Lang;

(:extendedCode)
module DItems {

    // weaponinfo_t field offsets.
    const WI_AMMO = 0;
    const WI_UPSTATE = 1;
    const WI_DOWNSTATE = 2;
    const WI_READYSTATE = 3;
    const WI_ATKSTATE = 4;
    const WI_FLASHSTATE = 5;
    const WI_SIZE = 6;

    //
    // PSPRITE ACTIONS for waepons.
    // This struct controls the weapon animations.
    //
    // Each entry is:
    //   ammo/amunition type
    //  upstate
    //  downstate
    // readystate
    // atkstate, i.e. attack/fire/hit frame
    // flashstate, muzzle flash
    //
    const weaponinfo = [
        // fist
        DoomDef.am_noammo,
        Info.S_PUNCHUP,
        Info.S_PUNCHDOWN,
        Info.S_PUNCH,
        Info.S_PUNCH1,
        Info.S_NULL,

        // pistol
        DoomDef.am_clip,
        Info.S_PISTOLUP,
        Info.S_PISTOLDOWN,
        Info.S_PISTOL,
        Info.S_PISTOL1,
        Info.S_PISTOLFLASH,

        // shotgun
        DoomDef.am_shell,
        Info.S_SGUNUP,
        Info.S_SGUNDOWN,
        Info.S_SGUN,
        Info.S_SGUN1,
        Info.S_SGUNFLASH1,

        // chaingun
        DoomDef.am_clip,
        Info.S_CHAINUP,
        Info.S_CHAINDOWN,
        Info.S_CHAIN,
        Info.S_CHAIN1,
        Info.S_CHAINFLASH1,

        // missile launcher
        DoomDef.am_misl,
        Info.S_MISSILEUP,
        Info.S_MISSILEDOWN,
        Info.S_MISSILE,
        Info.S_MISSILE1,
        Info.S_MISSILEFLASH1,

        // plasma rifle
        DoomDef.am_cell,
        Info.S_PLASMAUP,
        Info.S_PLASMADOWN,
        Info.S_PLASMA,
        Info.S_PLASMA1,
        Info.S_PLASMAFLASH1,

        // bfg 9000
        DoomDef.am_cell,
        Info.S_BFGUP,
        Info.S_BFGDOWN,
        Info.S_BFG,
        Info.S_BFG1,
        Info.S_BFGFLASH1,

        // chainsaw
        DoomDef.am_noammo,
        Info.S_SAWUP,
        Info.S_SAWDOWN,
        Info.S_SAW,
        Info.S_SAW1,
        Info.S_NULL,

        // super shotgun
        DoomDef.am_shell,
        Info.S_DSGUNUP,
        Info.S_DSGUNDOWN,
        Info.S_DSGUN,
        Info.S_DSGUN1,
        Info.S_DSGUNFLASH1
    ] as Array<Number>;
}
