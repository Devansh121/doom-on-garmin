// p_pspr.c
//
// DESCRIPTION:
//	Weapon sprite animation, weapon objects.
//	Action functions for weapons.
//
// player is a player number. pspdef_t* psp becomes the psprite number
// (ps_weapon / ps_flash); its fields are DPlayer.players_psprites_*
// at [player * NUMPSPRITES + psp], and a state of -1 is NULL.

import Toybox.Lang;

(:extendedCode)
module PPspr {

    const LOWERSPEED = MFixed.FRACUNIT * 6;
    const RAISESPEED = MFixed.FRACUNIT * 6;

    const WEAPONBOTTOM = 128 * MFixed.FRACUNIT;
    const WEAPONTOP = 32 * MFixed.FRACUNIT;

    // plasma cells for a bfg attack
    const BFGCELLS = 40;

    // weaponinfo[player->readyweapon].field
    function readyinfo(player as Number, field as Number) as Number {
        return DItems.weaponinfo[DPlayer.players_readyweapon[player] * DItems.WI_SIZE + field];
    }

    //
    // P_SetPsprite
    //
    function P_SetPsprite(player as Number, position as Number, stnum as Number) as Void {
        var psp = player * DPlayer.NUMPSPRITES + position;
        var states = Info.states;
        var pstate = DPlayer.players_psprites_state;
        var ptics = DPlayer.players_psprites_tics;

        do {
            if (stnum == 0) {
                // object removed itself
                pstate[psp] = -1;
                break;
            }

            var st = stnum * Info.ST_SIZE;
            pstate[psp] = stnum;
            ptics[psp] = states[st + Info.ST_TICS]; // could be 0

            if (states[st + Info.ST_MISC1] != 0) {
                // coordinate set
                DPlayer.players_psprites_sx[psp] = states[st + Info.ST_MISC1] << MFixed.FRACBITS;
                DPlayer.players_psprites_sy[psp] = states[st + Info.ST_MISC2] << MFixed.FRACBITS;
            }

            // Call action routine.
            // Modified handling.
            var action = states[st + Info.ST_ACTION];
            if (action != 0) {
                Actions.P_PspriteAction(action, player, position);
                if (pstate[psp] == -1) {
                    break;
                }
            }

            stnum = states[pstate[psp] * Info.ST_SIZE + Info.ST_NEXTSTATE];

        } while (ptics[psp] == 0);
        // an initial state of 0 could cycle through
    }

    //
    // P_CalcSwing
    //
    var swingx as Number = 0;
    var swingy as Number = 0;

    function P_CalcSwing(player as Number) as Void {
        var swing;
        var angle;

        // OPTIMIZE: tablify this.
        // A LUT would allow for different modes,
        //  and add flexibility.

        swing = DPlayer.players_bob[player];

        angle = (Tables.FINEANGLES / 70 * PTick.leveltime) & Tables.FINEMASK;
        swingx = MFixed.FixedMul(swing, Tables.finesine[angle]);

        angle = (Tables.FINEANGLES / 70 * PTick.leveltime + Tables.FINEANGLES / 2) & Tables.FINEMASK;
        swingy = -MFixed.FixedMul(swingx, Tables.finesine[angle]);
    }

    //
    // P_BringUpWeapon
    // Starts bringing the pending weapon up
    // from the bottom of the screen.
    // Uses player
    //
    function P_BringUpWeapon(player as Number) as Void {
        var newstate;

        if (DPlayer.players_pendingweapon[player] == DoomDef.wp_nochange) {
            DPlayer.players_pendingweapon[player] = DPlayer.players_readyweapon[player];
        }

        if (DPlayer.players_pendingweapon[player] == DoomDef.wp_chainsaw) {
            SSound.S_StartSound(DPlayer.players_mo[player], SSound.sfx_sawup);
        }

        newstate = DItems.weaponinfo[DPlayer.players_pendingweapon[player] * DItems.WI_SIZE + DItems.WI_UPSTATE];

        DPlayer.players_pendingweapon[player] = DoomDef.wp_nochange;
        DPlayer.players_psprites_sy[player * DPlayer.NUMPSPRITES + DPlayer.ps_weapon] = WEAPONBOTTOM;

        P_SetPsprite(player, DPlayer.ps_weapon, newstate);
    }

    //
    // P_CheckAmmo
    // Returns true if there is enough ammo to shoot.
    // If not, selects the next weapon to use.
    //
    function P_CheckAmmo(player as Number) as Boolean {
        var ammo;
        var count;
        var readyweapon = DPlayer.players_readyweapon[player];
        var pammo = DPlayer.players_ammo;
        var am = player * DoomDef.NUMAMMO;
        var owned = DPlayer.players_weaponowned;
        var wo = player * DoomDef.NUMWEAPONS;
        var gamemode = DoomStat.gamemode;

        ammo = readyinfo(player, DItems.WI_AMMO);

        // Minimal amount for one shot varies.
        if (readyweapon == DoomDef.wp_bfg) {
            count = BFGCELLS;
        } else if (readyweapon == DoomDef.wp_supershotgun) {
            count = 2; // Double barrel.
        } else {
            count = 1; // Regular.
        }

        // Some do not need ammunition anyway.
        // Return if current ammunition sufficient.
        if (ammo == DoomDef.am_noammo || pammo[am + ammo] >= count) {
            return true;
        }

        // Out of ammo, pick a weapon to change to.
        // Preferences are set here.
        do {
            if (owned[wo + DoomDef.wp_plasma] != 0
                && pammo[am + DoomDef.am_cell] != 0
                && (gamemode != DoomDef.shareware)) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_plasma;
            } else if (owned[wo + DoomDef.wp_supershotgun] != 0
                       && pammo[am + DoomDef.am_shell] > 2
                       && (gamemode == DoomDef.commercial)) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_supershotgun;
            } else if (owned[wo + DoomDef.wp_chaingun] != 0
                       && pammo[am + DoomDef.am_clip] != 0) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_chaingun;
            } else if (owned[wo + DoomDef.wp_shotgun] != 0
                       && pammo[am + DoomDef.am_shell] != 0) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_shotgun;
            } else if (pammo[am + DoomDef.am_clip] != 0) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_pistol;
            } else if (owned[wo + DoomDef.wp_chainsaw] != 0) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_chainsaw;
            } else if (owned[wo + DoomDef.wp_missile] != 0
                       && pammo[am + DoomDef.am_misl] != 0) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_missile;
            } else if (owned[wo + DoomDef.wp_bfg] != 0
                       && pammo[am + DoomDef.am_cell] > 40
                       && (gamemode != DoomDef.shareware)) {
                DPlayer.players_pendingweapon[player] = DoomDef.wp_bfg;
            } else {
                // If everything fails.
                DPlayer.players_pendingweapon[player] = DoomDef.wp_fist;
            }

        } while (DPlayer.players_pendingweapon[player] == DoomDef.wp_nochange);

        // Now set appropriate weapon overlay.
        P_SetPsprite(player,
                     DPlayer.ps_weapon,
                     readyinfo(player, DItems.WI_DOWNSTATE));

        return false;
    }

    //
    // P_FireWeapon.
    //
    function P_FireWeapon(player as Number) as Void {
        var newstate;

        if (!P_CheckAmmo(player)) {
            return;
        }

        PMobj.P_SetMobjState(DPlayer.players_mo[player], Info.S_PLAY_ATK1);
        newstate = readyinfo(player, DItems.WI_ATKSTATE);
        P_SetPsprite(player, DPlayer.ps_weapon, newstate);
        PEnemy.P_NoiseAlert(DPlayer.players_mo[player], DPlayer.players_mo[player]);
    }

    //
    // P_DropWeapon
    // Player died, so put the weapon away.
    //
    function P_DropWeapon(player as Number) as Void {
        P_SetPsprite(player,
                     DPlayer.ps_weapon,
                     readyinfo(player, DItems.WI_DOWNSTATE));
    }

    //
    // A_WeaponReady
    // The player can fire the weapon
    // or change to another weapon at this time.
    // Follows after getting weapon up,
    // or after previous attack/fire sequence.
    //
    function A_WeaponReady(player as Number, psp as Number) as Void {
        var newstate;
        var angle;
        var mo = DPlayer.players_mo[player];
        var readyweapon = DPlayer.players_readyweapon[player];
        var p = player * DPlayer.NUMPSPRITES + psp;

        // get out of attack state
        if (PMobj.mobjs_state[mo] == Info.S_PLAY_ATK1
            || PMobj.mobjs_state[mo] == Info.S_PLAY_ATK2) {
            PMobj.P_SetMobjState(mo, Info.S_PLAY);
        }

        if (readyweapon == DoomDef.wp_chainsaw
            && DPlayer.players_psprites_state[p] == Info.S_SAW) {
            SSound.S_StartSound(mo, SSound.sfx_sawidl);
        }

        // check for change
        //  if player is dead, put the weapon away
        if (DPlayer.players_pendingweapon[player] != DoomDef.wp_nochange || DPlayer.players_health[player] == 0) {
            // change weapon
            //  (pending weapon should allready be validated)
            newstate = readyinfo(player, DItems.WI_DOWNSTATE);
            P_SetPsprite(player, DPlayer.ps_weapon, newstate);
            return;
        }

        // check for fire
        //  the missile launcher and bfg do not auto fire
        if ((DPlayer.players_cmd_buttons[player] & DPlayer.BT_ATTACK) != 0) {
            if (DPlayer.players_attackdown[player] == 0
                || (readyweapon != DoomDef.wp_missile
                    && readyweapon != DoomDef.wp_bfg)) {
                DPlayer.players_attackdown[player] = 1;
                P_FireWeapon(player);
                return;
            }
        } else {
            DPlayer.players_attackdown[player] = 0;
        }

        // bob the weapon based on movement speed
        var bob = DPlayer.players_bob[player];
        angle = (128 * PTick.leveltime) & Tables.FINEMASK;
        DPlayer.players_psprites_sx[p] = MFixed.FRACUNIT + MFixed.FixedMul(bob, Tables.finesine[Tables.FINECOSINE + angle]);
        angle &= Tables.FINEANGLES / 2 - 1;
        DPlayer.players_psprites_sy[p] = WEAPONTOP + MFixed.FixedMul(bob, Tables.finesine[angle]);
    }

    //
    // A_ReFire
    // The player can re-fire the weapon
    // without lowering it entirely.
    //
    function A_ReFire(player as Number, psp as Number) as Void {
        // check for fire
        //  (if a weaponchange is pending, let it go through instead)
        if ((DPlayer.players_cmd_buttons[player] & DPlayer.BT_ATTACK) != 0
            && DPlayer.players_pendingweapon[player] == DoomDef.wp_nochange
            && DPlayer.players_health[player] != 0) {
            DPlayer.players_refire[player]++;
            P_FireWeapon(player);
        } else {
            DPlayer.players_refire[player] = 0;
            P_CheckAmmo(player);
        }
    }

    function A_CheckReload(player as Number, psp as Number) as Void {
        P_CheckAmmo(player);
        // (an #if 0 block switching to S_DSNR1 is left out)
    }

    //
    // A_Lower
    // Lowers current weapon,
    //  and changes weapon at bottom.
    //
    function A_Lower(player as Number, psp as Number) as Void {
        var p = player * DPlayer.NUMPSPRITES + psp;
        DPlayer.players_psprites_sy[p] += LOWERSPEED;

        // Is already down.
        if (DPlayer.players_psprites_sy[p] < WEAPONBOTTOM) {
            return;
        }

        // Player is dead.
        if (DPlayer.players_playerstate[player] == DPlayer.PST_DEAD) {
            DPlayer.players_psprites_sy[p] = WEAPONBOTTOM;

            // don't bring weapon back up
            return;
        }

        // The old weapon has been lowered off the screen,
        // so change the weapon and start raising it
        if (DPlayer.players_health[player] == 0) {
            // Player is dead, so keep the weapon off screen.
            P_SetPsprite(player, DPlayer.ps_weapon, Info.S_NULL);
            return;
        }

        DPlayer.players_readyweapon[player] = DPlayer.players_pendingweapon[player];

        P_BringUpWeapon(player);
    }

    //
    // A_Raise
    //
    function A_Raise(player as Number, psp as Number) as Void {
        var newstate;
        var p = player * DPlayer.NUMPSPRITES + psp;

        DPlayer.players_psprites_sy[p] -= RAISESPEED;

        if (DPlayer.players_psprites_sy[p] > WEAPONTOP) {
            return;
        }

        DPlayer.players_psprites_sy[p] = WEAPONTOP;

        // The weapon has been raised all the way,
        //  so change to the ready state.
        newstate = readyinfo(player, DItems.WI_READYSTATE);

        P_SetPsprite(player, DPlayer.ps_weapon, newstate);
    }

    //
    // A_GunFlash
    //
    function A_GunFlash(player as Number, psp as Number) as Void {
        PMobj.P_SetMobjState(DPlayer.players_mo[player], Info.S_PLAY_ATK2);
        P_SetPsprite(player, DPlayer.ps_flash, readyinfo(player, DItems.WI_FLASHSTATE));
    }

    //
    // WEAPON ATTACKS
    //

    //
    // A_Punch
    //
    function A_Punch(player as Number, psp as Number) as Void {
        var angle;
        var damage;
        var slope;
        var mo = DPlayer.players_mo[player];

        damage = (MRandom.P_Random() % 10 + 1) << 1;

        if (DPlayer.players_powers[player * DoomDef.NUMPOWERS + DoomDef.pw_strength] != 0) {
            damage *= 10;
        }

        angle = PMobj.mobjs_angle[mo];
        angle += (MRandom.P_Random() - MRandom.P_Random()) << 18;
        slope = PMap.P_AimLineAttack(mo, angle, PLocal.MELEERANGE);
        PMap.P_LineAttack(mo, angle, PLocal.MELEERANGE, slope, damage);

        // turn to face target
        var linetarget = PMap.linetarget;
        if (linetarget != -1) {
            SSound.S_StartSound(mo, SSound.sfx_punch);
            PMobj.mobjs_angle[mo] = RMain.R_PointToAngle2(PMobj.mobjs_x[mo],
                                                          PMobj.mobjs_y[mo],
                                                          PMobj.mobjs_x[linetarget],
                                                          PMobj.mobjs_y[linetarget]);
        }
    }

    //
    // A_Saw
    //
    function A_Saw(player as Number, psp as Number) as Void {
        var angle;
        var damage;
        var slope;
        var mo = DPlayer.players_mo[player];

        damage = 2 * (MRandom.P_Random() % 10 + 1);
        angle = PMobj.mobjs_angle[mo];
        angle += (MRandom.P_Random() - MRandom.P_Random()) << 18;

        // use meleerange + 1 se the puff doesn't skip the flash
        slope = PMap.P_AimLineAttack(mo, angle, PLocal.MELEERANGE + 1);
        PMap.P_LineAttack(mo, angle, PLocal.MELEERANGE + 1, slope, damage);

        var linetarget = PMap.linetarget;
        if (linetarget == -1) {
            SSound.S_StartSound(mo, SSound.sfx_sawful);
            return;
        }
        SSound.S_StartSound(mo, SSound.sfx_sawhit);

        // turn to face target
        angle = RMain.R_PointToAngle2(PMobj.mobjs_x[mo], PMobj.mobjs_y[mo],
                                      PMobj.mobjs_x[linetarget], PMobj.mobjs_y[linetarget]);
        // angle_t differences, compared unsigned
        var d = angle - PMobj.mobjs_angle[mo];
        if (DoomType.UGT(d, Tables.ANG180)) {
            if (DoomType.ULT(d, -(Tables.ANG90 / 20))) {
                PMobj.mobjs_angle[mo] = angle + Tables.ANG90 / 21;
            } else {
                PMobj.mobjs_angle[mo] -= Tables.ANG90 / 20;
            }
        } else {
            if (DoomType.UGT(d, Tables.ANG90 / 20)) {
                PMobj.mobjs_angle[mo] = angle - Tables.ANG90 / 21;
            } else {
                PMobj.mobjs_angle[mo] += Tables.ANG90 / 20;
            }
        }
        PMobj.mobjs_flags[mo] |= PMobj.MF_JUSTATTACKED;
    }

    //
    // A_FireMissile
    //
    function A_FireMissile(player as Number, psp as Number) as Void {
        DPlayer.players_ammo[player * DoomDef.NUMAMMO + readyinfo(player, DItems.WI_AMMO)]--;
        PMobj.P_SpawnPlayerMissile(DPlayer.players_mo[player], Info.MT_ROCKET);
    }

    //
    // A_FireBFG
    //
    function A_FireBFG(player as Number, psp as Number) as Void {
        DPlayer.players_ammo[player * DoomDef.NUMAMMO + readyinfo(player, DItems.WI_AMMO)] -= BFGCELLS;
        PMobj.P_SpawnPlayerMissile(DPlayer.players_mo[player], Info.MT_BFG);
    }

    //
    // A_FirePlasma
    //
    function A_FirePlasma(player as Number, psp as Number) as Void {
        DPlayer.players_ammo[player * DoomDef.NUMAMMO + readyinfo(player, DItems.WI_AMMO)]--;

        P_SetPsprite(player,
                     DPlayer.ps_flash,
                     readyinfo(player, DItems.WI_FLASHSTATE) + (MRandom.P_Random() & 1));

        PMobj.P_SpawnPlayerMissile(DPlayer.players_mo[player], Info.MT_PLASMA);
    }

    //
    // P_BulletSlope
    // Sets a slope so a near miss is at aproximately
    // the height of the intended target
    //
    var bulletslope as Number = 0;

    function P_BulletSlope(mo as Number) as Void {
        var an;

        // see which target is to be aimed at
        an = PMobj.mobjs_angle[mo];
        bulletslope = PMap.P_AimLineAttack(mo, an, 16 * 64 * MFixed.FRACUNIT);

        if (PMap.linetarget == -1) {
            an += 1 << 26;
            bulletslope = PMap.P_AimLineAttack(mo, an, 16 * 64 * MFixed.FRACUNIT);
            if (PMap.linetarget == -1) {
                an -= 2 << 26;
                bulletslope = PMap.P_AimLineAttack(mo, an, 16 * 64 * MFixed.FRACUNIT);
            }
        }
    }

    //
    // P_GunShot
    //
    function P_GunShot(mo as Number, accurate as Boolean) as Void {
        var angle;
        var damage;

        damage = 5 * (MRandom.P_Random() % 3 + 1);
        angle = PMobj.mobjs_angle[mo];

        if (!accurate) {
            angle += (MRandom.P_Random() - MRandom.P_Random()) << 18;
        }

        PMap.P_LineAttack(mo, angle, PLocal.MISSILERANGE, bulletslope, damage);
    }

    //
    // A_FirePistol
    //
    function A_FirePistol(player as Number, psp as Number) as Void {
        var mo = DPlayer.players_mo[player];
        SSound.S_StartSound(mo, SSound.sfx_pistol);

        PMobj.P_SetMobjState(mo, Info.S_PLAY_ATK2);
        DPlayer.players_ammo[player * DoomDef.NUMAMMO + readyinfo(player, DItems.WI_AMMO)]--;

        P_SetPsprite(player,
                     DPlayer.ps_flash,
                     readyinfo(player, DItems.WI_FLASHSTATE));

        P_BulletSlope(mo);
        P_GunShot(mo, DPlayer.players_refire[player] == 0);
    }

    //
    // A_FireShotgun
    //
    function A_FireShotgun(player as Number, psp as Number) as Void {
        var mo = DPlayer.players_mo[player];

        SSound.S_StartSound(mo, SSound.sfx_shotgn);
        PMobj.P_SetMobjState(mo, Info.S_PLAY_ATK2);

        DPlayer.players_ammo[player * DoomDef.NUMAMMO + readyinfo(player, DItems.WI_AMMO)]--;

        P_SetPsprite(player,
                     DPlayer.ps_flash,
                     readyinfo(player, DItems.WI_FLASHSTATE));

        P_BulletSlope(mo);

        for (var i = 0; i < 7; i++) {
            P_GunShot(mo, false);
        }
    }

    //
    // A_FireShotgun2
    //
    function A_FireShotgun2(player as Number, psp as Number) as Void {
        var angle;
        var damage;
        var mo = DPlayer.players_mo[player];

        SSound.S_StartSound(mo, SSound.sfx_dshtgn);
        PMobj.P_SetMobjState(mo, Info.S_PLAY_ATK2);

        DPlayer.players_ammo[player * DoomDef.NUMAMMO + readyinfo(player, DItems.WI_AMMO)] -= 2;

        P_SetPsprite(player,
                     DPlayer.ps_flash,
                     readyinfo(player, DItems.WI_FLASHSTATE));

        P_BulletSlope(mo);

        for (var i = 0; i < 20; i++) {
            damage = 5 * (MRandom.P_Random() % 3 + 1);
            angle = PMobj.mobjs_angle[mo];
            angle += (MRandom.P_Random() - MRandom.P_Random()) << 19;
            PMap.P_LineAttack(mo,
                              angle,
                              PLocal.MISSILERANGE,
                              bulletslope + ((MRandom.P_Random() - MRandom.P_Random()) << 5), damage);
        }
    }

    //
    // A_OpenShotgun2, A_LoadShotgun2, A_CloseShotgun2
    // (these three live in p_enemy.c in the C source)
    //
    function A_OpenShotgun2(player as Number, psp as Number) as Void {
        SSound.S_StartSound(DPlayer.players_mo[player], SSound.sfx_dbopn);
    }

    function A_LoadShotgun2(player as Number, psp as Number) as Void {
        SSound.S_StartSound(DPlayer.players_mo[player], SSound.sfx_dbload);
    }

    function A_CloseShotgun2(player as Number, psp as Number) as Void {
        SSound.S_StartSound(DPlayer.players_mo[player], SSound.sfx_dbcls);
        A_ReFire(player, psp);
    }

    //
    // A_FireCGun
    //
    function A_FireCGun(player as Number, psp as Number) as Void {
        var mo = DPlayer.players_mo[player];
        var am = player * DoomDef.NUMAMMO + readyinfo(player, DItems.WI_AMMO);

        SSound.S_StartSound(mo, SSound.sfx_pistol);

        if (DPlayer.players_ammo[am] == 0) {
            return;
        }

        PMobj.P_SetMobjState(mo, Info.S_PLAY_ATK2);
        DPlayer.players_ammo[am]--;

        P_SetPsprite(player,
                     DPlayer.ps_flash,
                     readyinfo(player, DItems.WI_FLASHSTATE)
                     + DPlayer.players_psprites_state[player * DPlayer.NUMPSPRITES + psp]
                     - Info.S_CHAIN1);

        P_BulletSlope(mo);

        P_GunShot(mo, DPlayer.players_refire[player] == 0);
    }

    //
    // ?
    //
    function A_Light0(player as Number, psp as Number) as Void {
        DPlayer.players_extralight[player] = 0;
    }

    function A_Light1(player as Number, psp as Number) as Void {
        DPlayer.players_extralight[player] = 1;
    }

    function A_Light2(player as Number, psp as Number) as Void {
        DPlayer.players_extralight[player] = 2;
    }

    //
    // A_BFGSpray
    // Spawn a BFG explosion on every monster in view
    //
    function A_BFGSpray(mo as Number) as Void {
        var damage;
        var an;
        var target = PMobj.mobjs_target[mo];

        // offset angles from its attack angle
        for (var i = 0; i < 40; i++) {
            an = PMobj.mobjs_angle[mo] - Tables.ANG90 / 2 + Tables.ANG90 / 40 * i;

            // mo->target is the originator (player)
            //  of the missile
            PMap.P_AimLineAttack(target, an, 16 * 64 * MFixed.FRACUNIT);

            var linetarget = PMap.linetarget;
            if (linetarget == -1) {
                continue;
            }

            PMobj.P_SpawnMobj(PMobj.mobjs_x[linetarget],
                              PMobj.mobjs_y[linetarget],
                              PMobj.mobjs_z[linetarget] + (PMobj.mobjs_height[linetarget] >> 2),
                              Info.MT_EXTRABFG);

            damage = 0;
            for (var j = 0; j < 15; j++) {
                damage += (MRandom.P_Random() & 7) + 1;
            }

            PInter.P_DamageMobj(linetarget, target, target, damage);
        }
    }

    //
    // A_BFGsound
    //
    function A_BFGsound(player as Number, psp as Number) as Void {
        SSound.S_StartSound(DPlayer.players_mo[player], SSound.sfx_bfg);
    }

    //
    // P_SetupPsprites
    // Called at start of level for each player.
    //
    function P_SetupPsprites(player as Number) as Void {
        // remove all psprites
        for (var i = 0; i < DPlayer.NUMPSPRITES; i++) {
            DPlayer.players_psprites_state[player * DPlayer.NUMPSPRITES + i] = -1;
        }

        // spawn the gun
        DPlayer.players_pendingweapon[player] = DPlayer.players_readyweapon[player];
        P_BringUpWeapon(player);
    }

    //
    // P_MovePsprites
    // Called every tic by player thinking routine.
    //
    function P_MovePsprites(player as Number) as Void {
        var pstate = DPlayer.players_psprites_state;
        var ptics = DPlayer.players_psprites_tics;
        var base = player * DPlayer.NUMPSPRITES;

        for (var i = 0; i < DPlayer.NUMPSPRITES; i++) {
            var psp = base + i;
            // a null state means not active
            if (pstate[psp] != -1) {
                // drop tic count and possibly change state

                // a -1 tic count never changes
                if (ptics[psp] != -1) {
                    ptics[psp]--;
                    if (ptics[psp] == 0) {
                        P_SetPsprite(player, i, Info.states[pstate[psp] * Info.ST_SIZE + Info.ST_NEXTSTATE]);
                    }
                }
            }
        }

        DPlayer.players_psprites_sx[base + DPlayer.ps_flash] = DPlayer.players_psprites_sx[base + DPlayer.ps_weapon];
        DPlayer.players_psprites_sy[base + DPlayer.ps_flash] = DPlayer.players_psprites_sy[base + DPlayer.ps_weapon];
    }
}
