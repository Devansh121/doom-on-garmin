// p_inter.c
//
// DESCRIPTION:
//	Handling interactions (i.e., collisions).
//
// player is a player number, mobjs are mobj numbers (-1 for NULL).
// The pickup messages from d_englsh.h (via dstrings.h) are below.

import Toybox.Lang;

(:extendedCode)
module PInter {

    //
    // ---- shared tables ----
    // a weapon is found with two clip loads,
    // a big item has five clip loads
    // (g_game.c's G_PlayerReborn reads maxammo)
    //
    var maxammo as Array<Number> = [200, 50, 300, 50] as Array<Number>;
    var clipammo as Array<Number> = [10, 4, 20, 1] as Array<Number>;
    // ---- end of shared tables ----

    const BONUSADD = 6;

    // d_englsh.h: P_inter.C
    const GOTARMOR = "Picked up the armor.";
    const GOTMEGA = "Picked up the MegaArmor!";
    const GOTHTHBONUS = "Picked up a health bonus.";
    const GOTARMBONUS = "Picked up an armor bonus.";
    const GOTSTIM = "Picked up a stimpack.";
    const GOTMEDINEED = "Picked up a medikit that you REALLY need!";
    const GOTMEDIKIT = "Picked up a medikit.";
    const GOTSUPER = "Supercharge!";

    const GOTBLUECARD = "Picked up a blue keycard.";
    const GOTYELWCARD = "Picked up a yellow keycard.";
    const GOTREDCARD = "Picked up a red keycard.";
    const GOTBLUESKUL = "Picked up a blue skull key.";
    const GOTYELWSKUL = "Picked up a yellow skull key.";
    const GOTREDSKULL = "Picked up a red skull key.";

    const GOTINVUL = "Invulnerability!";
    const GOTBERSERK = "Berserk!";
    const GOTINVIS = "Partial Invisibility";
    const GOTSUIT = "Radiation Shielding Suit";
    const GOTMAP = "Computer Area Map";
    const GOTVISOR = "Light Amplification Visor";
    const GOTMSPHERE = "MegaSphere!";

    const GOTCLIP = "Picked up a clip.";
    const GOTCLIPBOX = "Picked up a box of bullets.";
    const GOTROCKET = "Picked up a rocket.";
    const GOTROCKBOX = "Picked up a box of rockets.";
    const GOTCELL = "Picked up an energy cell.";
    const GOTCELLBOX = "Picked up an energy cell pack.";
    const GOTSHELLS = "Picked up 4 shotgun shells.";
    const GOTSHELLBOX = "Picked up a box of shotgun shells.";
    const GOTBACKPACK = "Picked up a backpack full of ammo!";

    const GOTBFG9000 = "You got the BFG9000!  Oh, yes.";
    const GOTCHAINGUN = "You got the chaingun!";
    const GOTCHAINSAW = "A chainsaw!  Find some meat!";
    const GOTLAUNCHER = "You got the rocket launcher!";
    const GOTPLASMA = "You got the plasma gun!";
    const GOTSHOTGUN = "You got the shotgun!";
    const GOTSHOTGUN2 = "You got the super shotgun!";

    //
    // GET STUFF
    //

    //
    // P_GiveAmmo
    // Num is the number of clip loads,
    // not the individual count (0= 1/2 clip).
    // Returns false if the ammo can't be picked up at all
    //
    function P_GiveAmmo(player as Number, ammo as Number, num as Number) as Boolean {
        var oldammo;

        if (ammo == DoomDef.am_noammo) {
            return false;
        }

        if (ammo < 0 || ammo > DoomDef.NUMAMMO) {
            ISystem.I_Error("P_GiveAmmo: bad type " + ammo);
        }

        var a = player * DoomDef.NUMAMMO + ammo;
        var pammo = DPlayer.players_ammo;
        var pmaxammo = DPlayer.players_maxammo;

        if (pammo[a] == pmaxammo[a]) {
            return false;
        }

        if (num != 0) {
            num *= clipammo[ammo];
        } else {
            num = clipammo[ammo] / 2;
        }

        if (DoomStat.gameskill == DoomDef.sk_baby
            || DoomStat.gameskill == DoomDef.sk_nightmare) {
            // give double ammo in trainer mode,
            // you'll need in nightmare
            num <<= 1;
        }

        oldammo = pammo[a];
        pammo[a] += num;

        if (pammo[a] > pmaxammo[a]) {
            pammo[a] = pmaxammo[a];
        }

        // If non zero ammo,
        // don't change up weapons,
        // player was lower on purpose.
        if (oldammo != 0) {
            return true;
        }

        // We were down to zero,
        // so select a new weapon.
        // Preferences are not user selectable.
        var readyweapon = DPlayer.players_readyweapon[player];
        var owned = DPlayer.players_weaponowned;
        var wo = player * DoomDef.NUMWEAPONS;
        switch (ammo) {
            case DoomDef.am_clip:
                if (readyweapon == DoomDef.wp_fist) {
                    if (owned[wo + DoomDef.wp_chaingun] != 0) {
                        DPlayer.players_pendingweapon[player] = DoomDef.wp_chaingun;
                    } else {
                        DPlayer.players_pendingweapon[player] = DoomDef.wp_pistol;
                    }
                }
                break;

            case DoomDef.am_shell:
                if (readyweapon == DoomDef.wp_fist
                    || readyweapon == DoomDef.wp_pistol) {
                    if (owned[wo + DoomDef.wp_shotgun] != 0) {
                        DPlayer.players_pendingweapon[player] = DoomDef.wp_shotgun;
                    }
                }
                break;

            case DoomDef.am_cell:
                if (readyweapon == DoomDef.wp_fist
                    || readyweapon == DoomDef.wp_pistol) {
                    if (owned[wo + DoomDef.wp_plasma] != 0) {
                        DPlayer.players_pendingweapon[player] = DoomDef.wp_plasma;
                    }
                }
                break;

            case DoomDef.am_misl:
                if (readyweapon == DoomDef.wp_fist) {
                    if (owned[wo + DoomDef.wp_missile] != 0) {
                        DPlayer.players_pendingweapon[player] = DoomDef.wp_missile;
                    }
                }
                break;
            default:
                break;
        }

        return true;
    }

    //
    // P_GiveWeapon
    // The weapon name may have a MF_DROPPED flag ored in.
    //
    function P_GiveWeapon(player as Number, weapon as Number, dropped as Boolean) as Boolean {
        var gaveammo;
        var gaveweapon;
        var owned = DPlayer.players_weaponowned;
        var w = player * DoomDef.NUMWEAPONS + weapon;
        var ammo = DItems.weaponinfo[weapon * DItems.WI_SIZE + DItems.WI_AMMO];

        // deathmatch is a Boolean here, so the C's (deathmatch!=2)
        // (altdeath) is always true.
        if (DoomStat.netgame
            && !dropped) {
            // leave placed weapons forever on net games
            if (owned[w] != 0) {
                return false;
            }

            DPlayer.players_bonuscount[player] += BONUSADD;
            owned[w] = 1;

            if (DoomStat.deathmatch) {
                P_GiveAmmo(player, ammo, 5);
            } else {
                P_GiveAmmo(player, ammo, 2);
            }
            DPlayer.players_pendingweapon[player] = weapon;

            if (player == DPlayer.consoleplayer) {
                SSound.S_StartSound(-1, SSound.sfx_wpnup);
            }
            return false;
        }

        if (ammo != DoomDef.am_noammo) {
            // give one clip with a dropped weapon,
            // two clips with a found weapon
            if (dropped) {
                gaveammo = P_GiveAmmo(player, ammo, 1);
            } else {
                gaveammo = P_GiveAmmo(player, ammo, 2);
            }
        } else {
            gaveammo = false;
        }

        if (owned[w] != 0) {
            gaveweapon = false;
        } else {
            gaveweapon = true;
            owned[w] = 1;
            DPlayer.players_pendingweapon[player] = weapon;
        }

        return (gaveweapon || gaveammo);
    }

    //
    // P_GiveBody
    // Returns false if the body isn't needed at all
    //
    function P_GiveBody(player as Number, num as Number) as Boolean {
        if (DPlayer.players_health[player] >= PLocal.MAXHEALTH) {
            return false;
        }

        DPlayer.players_health[player] += num;
        if (DPlayer.players_health[player] > PLocal.MAXHEALTH) {
            DPlayer.players_health[player] = PLocal.MAXHEALTH;
        }
        PMobj.mobjs_health[DPlayer.players_mo[player]] = DPlayer.players_health[player];

        return true;
    }

    //
    // P_GiveArmor
    // Returns false if the armor is worse
    // than the current armor.
    //
    function P_GiveArmor(player as Number, armortype as Number) as Boolean {
        var hits;

        hits = armortype * 100;
        if (DPlayer.players_armorpoints[player] >= hits) {
            return false; // don't pick up
        }

        DPlayer.players_armortype[player] = armortype;
        DPlayer.players_armorpoints[player] = hits;

        return true;
    }

    //
    // P_GiveCard
    //
    function P_GiveCard(player as Number, card as Number) as Void {
        var c = player * DoomDef.NUMCARDS + card;
        if (DPlayer.players_cards[c] != 0) {
            return;
        }

        DPlayer.players_bonuscount[player] = BONUSADD;
        DPlayer.players_cards[c] = 1;
    }

    //
    // P_GivePower
    //
    function P_GivePower(player as Number, power as Number) as Boolean {
        var powers = DPlayer.players_powers;
        var p = player * DoomDef.NUMPOWERS + power;

        if (power == DoomDef.pw_invulnerability) {
            powers[p] = DoomDef.INVULNTICS;
            return true;
        }

        if (power == DoomDef.pw_invisibility) {
            powers[p] = DoomDef.INVISTICS;
            PMobj.mobjs_flags[DPlayer.players_mo[player]] |= PMobj.MF_SHADOW;
            return true;
        }

        if (power == DoomDef.pw_infrared) {
            powers[p] = DoomDef.INFRATICS;
            return true;
        }

        if (power == DoomDef.pw_ironfeet) {
            powers[p] = DoomDef.IRONTICS;
            return true;
        }

        if (power == DoomDef.pw_strength) {
            P_GiveBody(player, 100);
            powers[p] = 1;
            return true;
        }

        if (powers[p] != 0) {
            return false; // already got it
        }

        powers[p] = 1;
        return true;
    }

    //
    // P_TouchSpecialThing
    //
    function P_TouchSpecialThing(special as Number, toucher as Number) as Void {
        var player;
        var delta;
        var sound;

        delta = PMobj.mobjs_z[special] - PMobj.mobjs_z[toucher];

        if (delta > PMobj.mobjs_height[toucher]
            || delta < -8 * MFixed.FRACUNIT) {
            // out of reach
            return;
        }

        sound = SSound.sfx_itemup;
        player = PMobj.mobjs_player[toucher];

        // Dead thing touching.
        // Can happen with a sliding player corpse.
        if (PMobj.mobjs_health[toucher] <= 0) {
            return;
        }

        var dropped = (PMobj.mobjs_flags[special] & PMobj.MF_DROPPED) != 0;
        var cards = DPlayer.players_cards;
        var c = player * DoomDef.NUMCARDS;

        // Identify by sprite.
        switch (PMobj.mobjs_sprite[special]) {
            // armor
            case Info.SPR_ARM1:
                if (!P_GiveArmor(player, 1)) {
                    return;
                }
                DPlayer.players_message[player] = GOTARMOR;
                break;

            case Info.SPR_ARM2:
                if (!P_GiveArmor(player, 2)) {
                    return;
                }
                DPlayer.players_message[player] = GOTMEGA;
                break;

            // bonus items
            case Info.SPR_BON1:
                DPlayer.players_health[player]++; // can go over 100%
                if (DPlayer.players_health[player] > 200) {
                    DPlayer.players_health[player] = 200;
                }
                PMobj.mobjs_health[DPlayer.players_mo[player]] = DPlayer.players_health[player];
                DPlayer.players_message[player] = GOTHTHBONUS;
                break;

            case Info.SPR_BON2:
                DPlayer.players_armorpoints[player]++; // can go over 100%
                if (DPlayer.players_armorpoints[player] > 200) {
                    DPlayer.players_armorpoints[player] = 200;
                }
                if (DPlayer.players_armortype[player] == 0) {
                    DPlayer.players_armortype[player] = 1;
                }
                DPlayer.players_message[player] = GOTARMBONUS;
                break;

            case Info.SPR_SOUL:
                DPlayer.players_health[player] += 100;
                if (DPlayer.players_health[player] > 200) {
                    DPlayer.players_health[player] = 200;
                }
                PMobj.mobjs_health[DPlayer.players_mo[player]] = DPlayer.players_health[player];
                DPlayer.players_message[player] = GOTSUPER;
                sound = SSound.sfx_getpow;
                break;

            case Info.SPR_MEGA:
                if (DoomStat.gamemode != DoomDef.commercial) {
                    return;
                }
                DPlayer.players_health[player] = 200;
                PMobj.mobjs_health[DPlayer.players_mo[player]] = DPlayer.players_health[player];
                P_GiveArmor(player, 2);
                DPlayer.players_message[player] = GOTMSPHERE;
                sound = SSound.sfx_getpow;
                break;

            // cards
            // leave cards for everyone
            case Info.SPR_BKEY:
                if (cards[c + DoomDef.it_bluecard] == 0) {
                    DPlayer.players_message[player] = GOTBLUECARD;
                }
                P_GiveCard(player, DoomDef.it_bluecard);
                if (!DoomStat.netgame) {
                    break;
                }
                return;

            case Info.SPR_YKEY:
                if (cards[c + DoomDef.it_yellowcard] == 0) {
                    DPlayer.players_message[player] = GOTYELWCARD;
                }
                P_GiveCard(player, DoomDef.it_yellowcard);
                if (!DoomStat.netgame) {
                    break;
                }
                return;

            case Info.SPR_RKEY:
                if (cards[c + DoomDef.it_redcard] == 0) {
                    DPlayer.players_message[player] = GOTREDCARD;
                }
                P_GiveCard(player, DoomDef.it_redcard);
                if (!DoomStat.netgame) {
                    break;
                }
                return;

            case Info.SPR_BSKU:
                if (cards[c + DoomDef.it_blueskull] == 0) {
                    DPlayer.players_message[player] = GOTBLUESKUL;
                }
                P_GiveCard(player, DoomDef.it_blueskull);
                if (!DoomStat.netgame) {
                    break;
                }
                return;

            case Info.SPR_YSKU:
                if (cards[c + DoomDef.it_yellowskull] == 0) {
                    DPlayer.players_message[player] = GOTYELWSKUL;
                }
                P_GiveCard(player, DoomDef.it_yellowskull);
                if (!DoomStat.netgame) {
                    break;
                }
                return;

            case Info.SPR_RSKU:
                if (cards[c + DoomDef.it_redskull] == 0) {
                    DPlayer.players_message[player] = GOTREDSKULL;
                }
                P_GiveCard(player, DoomDef.it_redskull);
                if (!DoomStat.netgame) {
                    break;
                }
                return;

            // medikits, heals
            case Info.SPR_STIM:
                if (!P_GiveBody(player, 10)) {
                    return;
                }
                DPlayer.players_message[player] = GOTSTIM;
                break;

            case Info.SPR_MEDI:
                if (!P_GiveBody(player, 25)) {
                    return;
                }

                if (DPlayer.players_health[player] < 25) {
                    DPlayer.players_message[player] = GOTMEDINEED;
                } else {
                    DPlayer.players_message[player] = GOTMEDIKIT;
                }
                break;

            // power ups
            case Info.SPR_PINV:
                if (!P_GivePower(player, DoomDef.pw_invulnerability)) {
                    return;
                }
                DPlayer.players_message[player] = GOTINVUL;
                sound = SSound.sfx_getpow;
                break;

            case Info.SPR_PSTR:
                if (!P_GivePower(player, DoomDef.pw_strength)) {
                    return;
                }
                DPlayer.players_message[player] = GOTBERSERK;
                if (DPlayer.players_readyweapon[player] != DoomDef.wp_fist) {
                    DPlayer.players_pendingweapon[player] = DoomDef.wp_fist;
                }
                sound = SSound.sfx_getpow;
                break;

            case Info.SPR_PINS:
                if (!P_GivePower(player, DoomDef.pw_invisibility)) {
                    return;
                }
                DPlayer.players_message[player] = GOTINVIS;
                sound = SSound.sfx_getpow;
                break;

            case Info.SPR_SUIT:
                if (!P_GivePower(player, DoomDef.pw_ironfeet)) {
                    return;
                }
                DPlayer.players_message[player] = GOTSUIT;
                sound = SSound.sfx_getpow;
                break;

            case Info.SPR_PMAP:
                if (!P_GivePower(player, DoomDef.pw_allmap)) {
                    return;
                }
                DPlayer.players_message[player] = GOTMAP;
                sound = SSound.sfx_getpow;
                break;

            case Info.SPR_PVIS:
                if (!P_GivePower(player, DoomDef.pw_infrared)) {
                    return;
                }
                DPlayer.players_message[player] = GOTVISOR;
                sound = SSound.sfx_getpow;
                break;

            // ammo
            case Info.SPR_CLIP:
                if (dropped) {
                    if (!P_GiveAmmo(player, DoomDef.am_clip, 0)) {
                        return;
                    }
                } else {
                    if (!P_GiveAmmo(player, DoomDef.am_clip, 1)) {
                        return;
                    }
                }
                DPlayer.players_message[player] = GOTCLIP;
                break;

            case Info.SPR_AMMO:
                if (!P_GiveAmmo(player, DoomDef.am_clip, 5)) {
                    return;
                }
                DPlayer.players_message[player] = GOTCLIPBOX;
                break;

            case Info.SPR_ROCK:
                if (!P_GiveAmmo(player, DoomDef.am_misl, 1)) {
                    return;
                }
                DPlayer.players_message[player] = GOTROCKET;
                break;

            case Info.SPR_BROK:
                if (!P_GiveAmmo(player, DoomDef.am_misl, 5)) {
                    return;
                }
                DPlayer.players_message[player] = GOTROCKBOX;
                break;

            case Info.SPR_CELL:
                if (!P_GiveAmmo(player, DoomDef.am_cell, 1)) {
                    return;
                }
                DPlayer.players_message[player] = GOTCELL;
                break;

            case Info.SPR_CELP:
                if (!P_GiveAmmo(player, DoomDef.am_cell, 5)) {
                    return;
                }
                DPlayer.players_message[player] = GOTCELLBOX;
                break;

            case Info.SPR_SHEL:
                if (!P_GiveAmmo(player, DoomDef.am_shell, 1)) {
                    return;
                }
                DPlayer.players_message[player] = GOTSHELLS;
                break;

            case Info.SPR_SBOX:
                if (!P_GiveAmmo(player, DoomDef.am_shell, 5)) {
                    return;
                }
                DPlayer.players_message[player] = GOTSHELLBOX;
                break;

            case Info.SPR_BPAK:
                if (!DPlayer.players_backpack[player]) {
                    for (var i = 0; i < DoomDef.NUMAMMO; i++) {
                        DPlayer.players_maxammo[player * DoomDef.NUMAMMO + i] *= 2;
                    }
                    DPlayer.players_backpack[player] = true;
                }
                for (var i = 0; i < DoomDef.NUMAMMO; i++) {
                    P_GiveAmmo(player, i, 1);
                }
                DPlayer.players_message[player] = GOTBACKPACK;
                break;

            // weapons
            case Info.SPR_BFUG:
                if (!P_GiveWeapon(player, DoomDef.wp_bfg, false)) {
                    return;
                }
                DPlayer.players_message[player] = GOTBFG9000;
                sound = SSound.sfx_wpnup;
                break;

            case Info.SPR_MGUN:
                if (!P_GiveWeapon(player, DoomDef.wp_chaingun, dropped)) {
                    return;
                }
                DPlayer.players_message[player] = GOTCHAINGUN;
                sound = SSound.sfx_wpnup;
                break;

            case Info.SPR_CSAW:
                if (!P_GiveWeapon(player, DoomDef.wp_chainsaw, false)) {
                    return;
                }
                DPlayer.players_message[player] = GOTCHAINSAW;
                sound = SSound.sfx_wpnup;
                break;

            case Info.SPR_LAUN:
                if (!P_GiveWeapon(player, DoomDef.wp_missile, false)) {
                    return;
                }
                DPlayer.players_message[player] = GOTLAUNCHER;
                sound = SSound.sfx_wpnup;
                break;

            case Info.SPR_PLAS:
                if (!P_GiveWeapon(player, DoomDef.wp_plasma, false)) {
                    return;
                }
                DPlayer.players_message[player] = GOTPLASMA;
                sound = SSound.sfx_wpnup;
                break;

            case Info.SPR_SHOT:
                if (!P_GiveWeapon(player, DoomDef.wp_shotgun, dropped)) {
                    return;
                }
                DPlayer.players_message[player] = GOTSHOTGUN;
                sound = SSound.sfx_wpnup;
                break;

            case Info.SPR_SGN2:
                if (!P_GiveWeapon(player, DoomDef.wp_supershotgun, dropped)) {
                    return;
                }
                DPlayer.players_message[player] = GOTSHOTGUN2;
                sound = SSound.sfx_wpnup;
                break;

            default:
                ISystem.I_Error("P_SpecialThing: Unknown gettable thing");
        }

        if ((PMobj.mobjs_flags[special] & PMobj.MF_COUNTITEM) != 0) {
            DPlayer.players_itemcount[player]++;
        }
        PMobj.P_RemoveMobj(special);
        DPlayer.players_bonuscount[player] += BONUSADD;
        if (player == DPlayer.consoleplayer) {
            SSound.S_StartSound(-1, sound);
        }
    }

    //
    // KillMobj
    //
    function P_KillMobj(source as Number, target as Number) as Void {
        var item;
        var mo;
        var tplayer = PMobj.mobjs_player[target];

        PMobj.mobjs_flags[target] &= ~(PMobj.MF_SHOOTABLE | PMobj.MF_FLOAT | PMobj.MF_SKULLFLY);

        if (PMobj.mobjs_type[target] != Info.MT_SKULL) {
            PMobj.mobjs_flags[target] &= ~PMobj.MF_NOGRAVITY;
        }

        PMobj.mobjs_flags[target] |= PMobj.MF_CORPSE | PMobj.MF_DROPOFF;
        PMobj.mobjs_height[target] >>= 2;

        if (source != -1 && PMobj.mobjs_player[source] != -1) {
            var splayer = PMobj.mobjs_player[source];
            // count for intermission
            if ((PMobj.mobjs_flags[target] & PMobj.MF_COUNTKILL) != 0) {
                DPlayer.players_killcount[splayer]++;
            }

            if (tplayer != -1) {
                DPlayer.players_frags[splayer * DPlayer.MAXPLAYERS + tplayer]++;
            }
        } else if (!DoomStat.netgame && (PMobj.mobjs_flags[target] & PMobj.MF_COUNTKILL) != 0) {
            // count all monster deaths,
            // even those caused by other monsters
            DPlayer.players_killcount[0]++;
        }

        if (tplayer != -1) {
            // count environment kills against you
            if (source == -1) {
                DPlayer.players_frags[tplayer * DPlayer.MAXPLAYERS + tplayer]++;
            }

            PMobj.mobjs_flags[target] &= ~PMobj.MF_SOLID;
            DPlayer.players_playerstate[tplayer] = DPlayer.PST_DEAD;
            PPspr.P_DropWeapon(tplayer);

            // (no automap on the watch, so no AM_Stop here)
        }

        if (PMobj.mobjs_health[target] < -PMobj.info(target, Info.MI_SPAWNHEALTH)
            && PMobj.info(target, Info.MI_XDEATHSTATE) != 0) {
            PMobj.P_SetMobjState(target, PMobj.info(target, Info.MI_XDEATHSTATE));
        } else {
            PMobj.P_SetMobjState(target, PMobj.info(target, Info.MI_DEATHSTATE));
        }
        PMobj.mobjs_tics[target] -= MRandom.P_Random() & 3;

        if (PMobj.mobjs_tics[target] < 1) {
            PMobj.mobjs_tics[target] = 1;
        }

        //	I_StartSound (&actor->r, actor->info->deathsound);

        // Drop stuff.
        // This determines the kind of object spawned
        // during the death frame of a thing.
        switch (PMobj.mobjs_type[target]) {
            case Info.MT_WOLFSS:
            case Info.MT_POSSESSED:
                item = Info.MT_CLIP;
                break;

            case Info.MT_SHOTGUY:
                item = Info.MT_SHOTGUN;
                break;

            case Info.MT_CHAINGUY:
                item = Info.MT_CHAINGUN;
                break;

            default:
                return;
        }

        mo = PMobj.P_SpawnMobj(PMobj.mobjs_x[target], PMobj.mobjs_y[target], PMobj.ONFLOORZ, item);
        PMobj.mobjs_flags[mo] |= PMobj.MF_DROPPED; // special versions of items
    }

    //
    // P_DamageMobj
    // Damages both enemies and players
    // "inflictor" is the thing that caused the damage
    //  creature or missile, can be NULL (slime, etc)
    // "source" is the thing to target after taking damage
    //  creature or NULL
    // Source and inflictor are the same for melee attacks.
    // Source can be NULL for slime, barrel explosions
    // and other environmental stuff.
    //
    function P_DamageMobj(target as Number, inflictor as Number, source as Number, damage as Number) as Void {
        var ang;
        var saved;
        var player;
        var thrust;

        if ((PMobj.mobjs_flags[target] & PMobj.MF_SHOOTABLE) == 0) {
            return; // shouldn't happen...
        }

        if (PMobj.mobjs_health[target] <= 0) {
            return;
        }

        if ((PMobj.mobjs_flags[target] & PMobj.MF_SKULLFLY) != 0) {
            PMobj.mobjs_momx[target] = 0;
            PMobj.mobjs_momy[target] = 0;
            PMobj.mobjs_momz[target] = 0;
        }

        player = PMobj.mobjs_player[target];
        if (player != -1 && DoomStat.gameskill == DoomDef.sk_baby) {
            damage >>= 1; // take half damage in trainer mode
        }

        // Some close combat weapons should not
        // inflict thrust and push the victim out of reach,
        // thus kick away unless using the chainsaw.
        if (inflictor != -1
            && (PMobj.mobjs_flags[target] & PMobj.MF_NOCLIP) == 0
            && (source == -1
                || PMobj.mobjs_player[source] == -1
                || DPlayer.players_readyweapon[PMobj.mobjs_player[source]] != DoomDef.wp_chainsaw)) {
            ang = RMain.R_PointToAngle2(PMobj.mobjs_x[inflictor],
                                        PMobj.mobjs_y[inflictor],
                                        PMobj.mobjs_x[target],
                                        PMobj.mobjs_y[target]);

            thrust = damage * (MFixed.FRACUNIT >> 3) * 100 / PMobj.info(target, Info.MI_MASS);

            // make fall forwards sometimes
            if (damage < 40
                && damage > PMobj.mobjs_health[target]
                && PMobj.mobjs_z[target] - PMobj.mobjs_z[inflictor] > 64 * MFixed.FRACUNIT
                && (MRandom.P_Random() & 1) != 0) {
                ang += Tables.ANG180;
                thrust *= 4;
            }

            // ang is unsigned
            ang = DoomType.USHR(ang, Tables.ANGLETOFINESHIFT);
            PMobj.mobjs_momx[target] += MFixed.FixedMul(thrust, Tables.finesine[Tables.FINECOSINE + ang]);
            PMobj.mobjs_momy[target] += MFixed.FixedMul(thrust, Tables.finesine[ang]);
        }

        // player specific
        if (player != -1) {
            // end of game hell hack
            if (PSetup.sectors_special[PSetup.subsectors_sector[PMobj.mobjs_subsector[target]]] == 11
                && damage >= PMobj.mobjs_health[target]) {
                damage = PMobj.mobjs_health[target] - 1;
            }

            // Below certain threshold,
            // ignore damage in GOD mode, or with INVUL power.
            if (damage < 1000
                && ((DPlayer.players_cheats[player] & DPlayer.CF_GODMODE) != 0
                    || DPlayer.players_powers[player * DoomDef.NUMPOWERS + DoomDef.pw_invulnerability] != 0)) {
                return;
            }

            if (DPlayer.players_armortype[player] != 0) {
                if (DPlayer.players_armortype[player] == 1) {
                    saved = damage / 3;
                } else {
                    saved = damage / 2;
                }

                if (DPlayer.players_armorpoints[player] <= saved) {
                    // armor is used up
                    saved = DPlayer.players_armorpoints[player];
                    DPlayer.players_armortype[player] = 0;
                }
                DPlayer.players_armorpoints[player] -= saved;
                damage -= saved;
            }
            DPlayer.players_health[player] -= damage; // mirror mobj health here for Dave
            if (DPlayer.players_health[player] < 0) {
                DPlayer.players_health[player] = 0;
            }

            DPlayer.players_attacker[player] = source;
            DPlayer.players_damagecount[player] += damage; // add damage after armor / invuln

            if (DPlayer.players_damagecount[player] > 100) {
                DPlayer.players_damagecount[player] = 100; // teleport stomp does 10k points...
            }

            // (I_Tactile, the force feedback call, is a no-op and left out)
        }

        // do the damage
        PMobj.mobjs_health[target] -= damage;
        if (PMobj.mobjs_health[target] <= 0) {
            P_KillMobj(source, target);
            return;
        }

        if ((MRandom.P_Random() < PMobj.info(target, Info.MI_PAINCHANCE))
            && (PMobj.mobjs_flags[target] & PMobj.MF_SKULLFLY) == 0) {
            PMobj.mobjs_flags[target] |= PMobj.MF_JUSTHIT; // fight back!

            PMobj.P_SetMobjState(target, PMobj.info(target, Info.MI_PAINSTATE));
        }

        PMobj.mobjs_reactiontime[target] = 0; // we're awake now...

        if ((PMobj.mobjs_threshold[target] == 0 || PMobj.mobjs_type[target] == Info.MT_VILE)
            && source != -1 && source != target
            && PMobj.mobjs_type[source] != Info.MT_VILE) {
            // if not intent on another player,
            // chase after this one
            PMobj.mobjs_target[target] = source;
            PMobj.mobjs_threshold[target] = PLocal.BASETHRESHOLD;
            if (PMobj.mobjs_state[target] == PMobj.info(target, Info.MI_SPAWNSTATE)
                && PMobj.info(target, Info.MI_SEESTATE) != Info.S_NULL) {
                PMobj.P_SetMobjState(target, PMobj.info(target, Info.MI_SEESTATE));
            }
        }
    }
}
