// p_user.c
//
// DESCRIPTION:
//	Player related stuff.
//	Bobbing POV/weapon, movement.
//	Pending weapon.
//
// player is a player number (players[p]); its fields are the
// DPlayer.players_*[p] arrays and player->cmd is players_cmd_*[p].

import Toybox.Lang;

(:extendedCode)
module PUser {

    // Index of the special effects (INVUL inverse) map.
    const INVERSECOLORMAP = 32;

    //
    // Movement.
    //

    // 16 pixels of bob
    const MAXBOB = 0x100000;

    var onground as Boolean = false;

    //
    // P_Thrust
    // Moves the given origin along a given angle.
    //
    function P_Thrust(player as Number, angle as Number, move as Number) as Void {
        // angle_t is unsigned: mask off the sign bits >> drags in
        angle = (angle >> Tables.ANGLETOFINESHIFT) & Tables.FINEMASK;

        var mo = DPlayer.players_mo[player];
        PMobj.mobjs_momx[mo] += MFixed.FixedMul(move, Tables.finesine[Tables.FINECOSINE + angle]);
        PMobj.mobjs_momy[mo] += MFixed.FixedMul(move, Tables.finesine[angle]);
    }

    //
    // P_CalcHeight
    // Calculate the walking / running height adjustment
    //
    function P_CalcHeight(player as Number) as Void {
        // (arrays in locals, module variable reads are slow on the watch)
        var pviewz = DPlayer.players_viewz;
        var pviewheight = DPlayer.players_viewheight;
        var mz = PMobj.mobjs_z;
        var mceilingz = PMobj.mobjs_ceilingz;
        var angle;
        var bob;
        var mo = DPlayer.players_mo[player];
        var momx = PMobj.mobjs_momx[mo];
        var momy = PMobj.mobjs_momy[mo];

        // Regular movement bobbing
        // (needs to be calculated for gun swing
        // even if not on ground)
        // OPTIMIZE: tablify angle
        // Note: a LUT allows for effects
        //  like a ramp with low health.
        var pbob = MFixed.FixedMul(momx, momx) + MFixed.FixedMul(momy, momy);

        pbob >>= 2;

        if (pbob > MAXBOB) {
            pbob = MAXBOB;
        }
        DPlayer.players_bob[player] = pbob;

        if ((DPlayer.players_cheats[player] & DPlayer.CF_NOMOMENTUM) != 0 || !onground) {
            pviewz[player] = mz[mo] + PLocal.VIEWHEIGHT;

            if (pviewz[player] > mceilingz[mo] - 4 * MFixed.FRACUNIT) {
                pviewz[player] = mceilingz[mo] - 4 * MFixed.FRACUNIT;
            }

            pviewz[player] = mz[mo] + pviewheight[player];
            return;
        }

        angle = (Tables.FINEANGLES / 20 * PTick.leveltime) & Tables.FINEMASK;
        bob = MFixed.FixedMul(pbob / 2, Tables.finesine[angle]);

        // move viewheight
        if (DPlayer.players_playerstate[player] == DPlayer.PST_LIVE) {
            // (worked on in locals, stored back below)
            var deltaviewheight = DPlayer.players_deltaviewheight[player];
            var viewheight = pviewheight[player] + deltaviewheight;

            if (viewheight > PLocal.VIEWHEIGHT) {
                viewheight = PLocal.VIEWHEIGHT;
                deltaviewheight = 0;
            }

            if (viewheight < PLocal.VIEWHEIGHT / 2) {
                viewheight = PLocal.VIEWHEIGHT / 2;
                if (deltaviewheight <= 0) {
                    deltaviewheight = 1;
                }
            }

            if (deltaviewheight != 0) {
                deltaviewheight += MFixed.FRACUNIT / 4;
                if (deltaviewheight == 0) {
                    deltaviewheight = 1;
                }
            }
            pviewheight[player] = viewheight;
            DPlayer.players_deltaviewheight[player] = deltaviewheight;
        }
        pviewz[player] = mz[mo] + pviewheight[player] + bob;

        if (pviewz[player] > mceilingz[mo] - 4 * MFixed.FRACUNIT) {
            pviewz[player] = mceilingz[mo] - 4 * MFixed.FRACUNIT;
        }
    }

    //
    // P_MovePlayer
    //
    function P_MovePlayer(player as Number) as Void {
        var mo = DPlayer.players_mo[player];
        var forwardmove = DPlayer.players_cmd_forwardmove[player];
        var sidemove = DPlayer.players_cmd_sidemove[player];

        PMobj.mobjs_angle[mo] += (DPlayer.players_cmd_angleturn[player] << 16);

        // Do not let the player control movement
        //  if not onground.
        onground = (PMobj.mobjs_z[mo] <= PMobj.mobjs_floorz[mo]);

        if (forwardmove != 0 && onground) {
            P_Thrust(player, PMobj.mobjs_angle[mo], forwardmove * 2048);
        }

        if (sidemove != 0 && onground) {
            P_Thrust(player, PMobj.mobjs_angle[mo] - Tables.ANG90, sidemove * 2048);
        }

        if ((forwardmove != 0 || sidemove != 0)
            && PMobj.mobjs_state[mo] == Info.S_PLAY) {
            PMobj.P_SetMobjState(mo, Info.S_PLAY_RUN1);
        }
    }

    //
    // P_DeathThink
    // Fall on your face when dying.
    // Decrease POV height to floor height.
    //
    const ANG5 = Tables.ANG90 / 18;

    function P_DeathThink(player as Number) as Void {
        var angle;
        var delta;
        var mo = DPlayer.players_mo[player];

        PPspr.P_MovePsprites(player);

        // fall to the ground
        if (DPlayer.players_viewheight[player] > 6 * MFixed.FRACUNIT) {
            DPlayer.players_viewheight[player] -= MFixed.FRACUNIT;
        }

        if (DPlayer.players_viewheight[player] < 6 * MFixed.FRACUNIT) {
            DPlayer.players_viewheight[player] = 6 * MFixed.FRACUNIT;
        }

        DPlayer.players_deltaviewheight[player] = 0;
        onground = (PMobj.mobjs_z[mo] <= PMobj.mobjs_floorz[mo]);
        P_CalcHeight(player);

        var attacker = DPlayer.players_attacker[player];
        if (attacker != -1 && attacker != mo) {
            angle = RMain.R_PointToAngle2(PMobj.mobjs_x[mo],
                                          PMobj.mobjs_y[mo],
                                          PMobj.mobjs_x[attacker],
                                          PMobj.mobjs_y[attacker]);

            delta = angle - PMobj.mobjs_angle[mo];

            // angle_t compares are unsigned
            if (DoomType.ULT(delta, ANG5) || DoomType.UGT(delta, -ANG5)) {
                // Looking at killer,
                //  so fade damage flash down.
                PMobj.mobjs_angle[mo] = angle;

                if (DPlayer.players_damagecount[player] != 0) {
                    DPlayer.players_damagecount[player]--;
                }
            } else if (DoomType.ULT(delta, Tables.ANG180)) {
                PMobj.mobjs_angle[mo] += ANG5;
            } else {
                PMobj.mobjs_angle[mo] -= ANG5;
            }
        } else if (DPlayer.players_damagecount[player] != 0) {
            DPlayer.players_damagecount[player]--;
        }

        if ((DPlayer.players_cmd_buttons[player] & DPlayer.BT_USE) != 0) {
            DPlayer.players_playerstate[player] = DPlayer.PST_REBORN;
        }
    }

    //
    // P_PlayerThink
    //
    function P_PlayerThink(player as Number) as Void {
        var newweapon;
        var mo = DPlayer.players_mo[player];
        var powers = DPlayer.players_powers;
        var pw = player * DoomDef.NUMPOWERS;

        var mflags = PMobj.mobjs_flags;

        // fixme: do this in the cheat code
        if ((DPlayer.players_cheats[player] & DPlayer.CF_NOCLIP) != 0) {
            mflags[mo] |= PMobj.MF_NOCLIP;
        } else {
            mflags[mo] &= ~PMobj.MF_NOCLIP;
        }

        // chain saw run forward
        if ((mflags[mo] & PMobj.MF_JUSTATTACKED) != 0) {
            DPlayer.players_cmd_angleturn[player] = 0;
            DPlayer.players_cmd_forwardmove[player] = 0xc800 / 512;
            DPlayer.players_cmd_sidemove[player] = 0;
            mflags[mo] &= ~PMobj.MF_JUSTATTACKED;
        }

        if (DPlayer.players_playerstate[player] == DPlayer.PST_DEAD) {
            P_DeathThink(player);
            return;
        }

        // Move around.
        // Reactiontime is used to prevent movement
        //  for a bit after a teleport.
        if (PMobj.mobjs_reactiontime[mo] != 0) {
            PMobj.mobjs_reactiontime[mo]--;
        } else {
            P_MovePlayer(player);
        }

        P_CalcHeight(player);

        if (PSetup.sectors_special[PSetup.subsectors_sector[PMobj.mobjs_subsector[mo]]] != 0) {
            PSpec.P_PlayerInSpecialSector(player);
        }

        // Check for weapon change.

        // A special event has no other buttons.
        if ((DPlayer.players_cmd_buttons[player] & DPlayer.BT_SPECIAL) != 0) {
            DPlayer.players_cmd_buttons[player] = 0;
        }

        var buttons = DPlayer.players_cmd_buttons[player];
        if ((buttons & DPlayer.BT_CHANGE) != 0) {
            var owned = DPlayer.players_weaponowned;
            var wo = player * DoomDef.NUMWEAPONS;
            var readyweapon = DPlayer.players_readyweapon[player];

            // The actual changing of the weapon is done
            //  when the weapon psprite can do it
            //  (read: not in the middle of an attack).
            newweapon = (buttons & DPlayer.BT_WEAPONMASK) >> DPlayer.BT_WEAPONSHIFT;

            if (newweapon == DoomDef.wp_fist
                && owned[wo + DoomDef.wp_chainsaw] != 0
                && !(readyweapon == DoomDef.wp_chainsaw
                     && powers[pw + DoomDef.pw_strength] != 0)) {
                newweapon = DoomDef.wp_chainsaw;
            }

            if ((DoomStat.gamemode == DoomDef.commercial)
                && newweapon == DoomDef.wp_shotgun
                && owned[wo + DoomDef.wp_supershotgun] != 0
                && readyweapon != DoomDef.wp_supershotgun) {
                newweapon = DoomDef.wp_supershotgun;
            }

            if (owned[wo + newweapon] != 0
                && newweapon != readyweapon) {
                // Do not go to plasma or BFG in shareware,
                //  even if cheated.
                if ((newweapon != DoomDef.wp_plasma
                     && newweapon != DoomDef.wp_bfg)
                    || (DoomStat.gamemode != DoomDef.shareware)) {
                    DPlayer.players_pendingweapon[player] = newweapon;
                }
            }
        }

        // check for use
        if ((buttons & DPlayer.BT_USE) != 0) {
            if (DPlayer.players_usedown[player] == 0) {
                PMap.P_UseLines(player);
                DPlayer.players_usedown[player] = 1;
            }
        } else {
            DPlayer.players_usedown[player] = 0;
        }

        // cycle psprites
        PPspr.P_MovePsprites(player);

        // Counters, time dependend power ups.

        // Strength counts up to diminish fade.
        if (powers[pw + DoomDef.pw_strength] != 0) {
            powers[pw + DoomDef.pw_strength]++;
        }

        if (powers[pw + DoomDef.pw_invulnerability] != 0) {
            powers[pw + DoomDef.pw_invulnerability]--;
        }

        if (powers[pw + DoomDef.pw_invisibility] != 0) {
            powers[pw + DoomDef.pw_invisibility]--;
            if (powers[pw + DoomDef.pw_invisibility] == 0) {
                PMobj.mobjs_flags[mo] &= ~PMobj.MF_SHADOW;
            }
        }

        if (powers[pw + DoomDef.pw_infrared] != 0) {
            powers[pw + DoomDef.pw_infrared]--;
        }

        if (powers[pw + DoomDef.pw_ironfeet] != 0) {
            powers[pw + DoomDef.pw_ironfeet]--;
        }

        if (DPlayer.players_damagecount[player] != 0) {
            DPlayer.players_damagecount[player]--;
        }

        if (DPlayer.players_bonuscount[player] != 0) {
            DPlayer.players_bonuscount[player]--;
        }

        // Handling colormaps.
        var invul = powers[pw + DoomDef.pw_invulnerability];
        var infra = powers[pw + DoomDef.pw_infrared];
        if (invul != 0) {
            if (invul > 4 * 32
                || (invul & 8) != 0) {
                DPlayer.players_fixedcolormap[player] = INVERSECOLORMAP;
            } else {
                DPlayer.players_fixedcolormap[player] = 0;
            }
        } else if (infra != 0) {
            if (infra > 4 * 32
                || (infra & 8) != 0) {
                // almost full bright
                DPlayer.players_fixedcolormap[player] = 1;
            } else {
                DPlayer.players_fixedcolormap[player] = 0;
            }
        } else {
            DPlayer.players_fixedcolormap[player] = 0;
        }
    }
}
