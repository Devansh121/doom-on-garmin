// Expected values come from the original p_user.c, p_pspr.c and
// p_inter.c built as they are, see test/player_ref.c. Both sides run the
// same scenarios: a player in open space (P_TryMove only moves it, the
// mobj thinker is cut down to P_XYMovement and the state countdown),
// P_DamageMobj on an armored player until it dies, and item pickups.

import Toybox.Lang;
import Toybox.Test;

// p_mobj.c's P_XYMovement with P_TryMove just moving, as in the C side.
function testXYMovement(mo as Number) as Void {
    var STOPSPEED = 0x1000;
    var FRICTION = 0xe800;
    var MAXMOVE = 30 * MFixed.FRACUNIT;
    var ptryx;
    var ptryy;
    var xmove;
    var ymove;

    if (PMobj.mobjs_momx[mo] == 0 && PMobj.mobjs_momy[mo] == 0) {
        return;
    }
    var player = PMobj.mobjs_player[mo];
    if (PMobj.mobjs_momx[mo] > MAXMOVE) {
        PMobj.mobjs_momx[mo] = MAXMOVE;
    } else if (PMobj.mobjs_momx[mo] < -MAXMOVE) {
        PMobj.mobjs_momx[mo] = -MAXMOVE;
    }
    if (PMobj.mobjs_momy[mo] > MAXMOVE) {
        PMobj.mobjs_momy[mo] = MAXMOVE;
    } else if (PMobj.mobjs_momy[mo] < -MAXMOVE) {
        PMobj.mobjs_momy[mo] = -MAXMOVE;
    }
    xmove = PMobj.mobjs_momx[mo];
    ymove = PMobj.mobjs_momy[mo];
    do {
        if (xmove > MAXMOVE / 2 || ymove > MAXMOVE / 2) {
            ptryx = PMobj.mobjs_x[mo] + xmove / 2;
            ptryy = PMobj.mobjs_y[mo] + ymove / 2;
            xmove >>= 1;
            ymove >>= 1;
        } else {
            ptryx = PMobj.mobjs_x[mo] + xmove;
            ptryy = PMobj.mobjs_y[mo] + ymove;
            xmove = 0;
            ymove = 0;
        }
        PMobj.mobjs_x[mo] = ptryx;
        PMobj.mobjs_y[mo] = ptryy;
    } while (xmove != 0 || ymove != 0);

    if (player != -1 && (DPlayer.players_cheats[player] & DPlayer.CF_NOMOMENTUM) != 0) {
        PMobj.mobjs_momx[mo] = 0;
        PMobj.mobjs_momy[mo] = 0;
        return;
    }
    if ((PMobj.mobjs_flags[mo] & (PMobj.MF_MISSILE | PMobj.MF_SKULLFLY)) != 0) {
        return;
    }
    if (PMobj.mobjs_z[mo] > PMobj.mobjs_floorz[mo]) {
        return;
    }
    var momx = PMobj.mobjs_momx[mo];
    var momy = PMobj.mobjs_momy[mo];
    if (momx > -STOPSPEED && momx < STOPSPEED
        && momy > -STOPSPEED && momy < STOPSPEED
        && (player == -1 || (DPlayer.players_cmd_forwardmove[player] == 0
                             && DPlayer.players_cmd_sidemove[player] == 0))) {
        var s = PMobj.mobjs_state[mo];
        if (player != -1 && s >= Info.S_PLAY_RUN1 && s < Info.S_PLAY_RUN1 + 4) {
            PMobj.P_SetMobjState(mo, Info.S_PLAY);
        }
        PMobj.mobjs_momx[mo] = 0;
        PMobj.mobjs_momy[mo] = 0;
    } else {
        PMobj.mobjs_momx[mo] = MFixed.FixedMul(momx, FRICTION);
        PMobj.mobjs_momy[mo] = MFixed.FixedMul(momy, FRICTION);
    }
}

// One tic of P_Ticker for player 0, like tic() in player_ref.c.
function testPlayerTic() as Void {
    var mo = DPlayer.players_mo[0];
    PUser.P_PlayerThink(0);
    testXYMovement(mo);
    if (PMobj.mobjs_tics[mo] != -1) {
        PMobj.mobjs_tics[mo]--;
        if (PMobj.mobjs_tics[mo] == 0) {
            PMobj.P_SetMobjState(mo, Info.states[PMobj.mobjs_state[mo] * Info.ST_SIZE + Info.ST_NEXTSTATE]);
        }
    }
    PTick.leveltime++;
}

// setup_mobj in player_ref.c
function testSpawn(type as Number, x as Number, y as Number) as Number {
    var mo = PMobj.P_SpawnMobj(x, y, PMobj.ONFLOORZ, type);
    PMobj.mobjs_z[mo] = 0;
    PMobj.mobjs_floorz[mo] = 0;
    PMobj.mobjs_ceilingz[mo] = 128 * MFixed.FRACUNIT;
    return mo;
}

function zeros(n as Number) as Array<Number> {
    var a = new [n] as Array<Number>;
    for (var i = 0; i < n; i++) {
        a[i] = 0;
    }
    return a;
}

// setup_player in player_ref.c: a fresh player 0 with a pistol and 50
// bullets, standing at the E1M1 start (sector special 0).
function testSetupPlayer() as Number {
    var x = 1056 << 16;
    var y = -3616 << 16;
    initRender();
    Info.Info_Init();
    loadE1M1();
    var mo = testSpawn(Info.MT_PLAYER, x, y);
    Test.assertEqual(PSetup.sectors_special[PSetup.subsectors_sector[PMobj.mobjs_subsector[mo]]], 0);

    PMobj.mobjs_player[mo] = 0;
    DPlayer.players_mo[0] = mo;
    DPlayer.players_playerstate[0] = DPlayer.PST_LIVE;
    DPlayer.players_cmd_forwardmove[0] = 0;
    DPlayer.players_cmd_sidemove[0] = 0;
    DPlayer.players_cmd_angleturn[0] = 0;
    DPlayer.players_cmd_buttons[0] = 0;
    DPlayer.players_viewz[0] = 0;
    DPlayer.players_viewheight[0] = PLocal.VIEWHEIGHT;
    DPlayer.players_deltaviewheight[0] = 0;
    DPlayer.players_bob[0] = 0;
    DPlayer.players_health[0] = 100;
    DPlayer.players_armorpoints[0] = 0;
    DPlayer.players_armortype[0] = 0;
    DPlayer.players_powers = zeros(DPlayer.MAXPLAYERS * DoomDef.NUMPOWERS);
    DPlayer.players_cards = zeros(DPlayer.MAXPLAYERS * DoomDef.NUMCARDS);
    DPlayer.players_backpack[0] = false;
    DPlayer.players_readyweapon[0] = DoomDef.wp_pistol;
    DPlayer.players_pendingweapon[0] = DoomDef.wp_nochange;
    DPlayer.players_weaponowned = zeros(DPlayer.MAXPLAYERS * DoomDef.NUMWEAPONS);
    DPlayer.players_weaponowned[DoomDef.wp_fist] = 1;
    DPlayer.players_weaponowned[DoomDef.wp_pistol] = 1;
    DPlayer.players_ammo = zeros(DPlayer.MAXPLAYERS * DoomDef.NUMAMMO);
    DPlayer.players_maxammo = zeros(DPlayer.MAXPLAYERS * DoomDef.NUMAMMO);
    for (var i = 0; i < DoomDef.NUMAMMO; i++) {
        DPlayer.players_maxammo[i] = PInter.maxammo[i];
    }
    DPlayer.players_ammo[DoomDef.am_clip] = 50;
    DPlayer.players_attackdown[0] = 0;
    DPlayer.players_usedown[0] = 0;
    DPlayer.players_cheats[0] = 0;
    DPlayer.players_refire[0] = 0;
    DPlayer.players_killcount[0] = 0;
    DPlayer.players_itemcount[0] = 0;
    DPlayer.players_message[0] = null;
    DPlayer.players_damagecount[0] = 0;
    DPlayer.players_bonuscount[0] = 0;
    DPlayer.players_attacker[0] = -1;
    DPlayer.players_extralight[0] = 0;
    DPlayer.players_fixedcolormap[0] = 0;
    for (var i = 0; i < DPlayer.NUMPSPRITES; i++) {
        DPlayer.players_psprites_state[i] = -1;
        DPlayer.players_psprites_tics[i] = 0;
        DPlayer.players_psprites_sx[i] = 0;
        DPlayer.players_psprites_sy[i] = 0;
    }

    PMobj.P_SetMobjState(mo, Info.S_PLAY);
    PPspr.P_SetupPsprites(0);
    MRandom.M_ClearRandom();
    PTick.leveltime = 0;
    return mo;
}

(:test)
function testPlayerWalkMatchesC(logger as Test.Logger) as Boolean {
    // x, y, momx, momy, angle, viewz, viewheight, bob, mo state, mo tics,
    // weapon state, tics, sx, sy, flash state, readyweapon, pendingweapon,
    // clip, shells, prndindex
    var walk = [
        [69308414, -236978137, 92798, 35, 0, 2686983, 2686976, 39998, 150, 3, 12, 1, 0, 7602176, -1, 1, 10, 50, 8, 0],
        [69503610, -236978063, 176896, 67, 0, 2709426, 2686976, 145345, 150, 2, 12, 1, 0, 7208960, -1, 1, 10, 50, 8, 0],
        [69782904, -236977957, 253110, 96, 0, 2774361, 2686976, 297565, 150, 1, 12, 1, 0, 6815744, -1, 1, 10, 50, 8, 0],
        [70138412, -236977822, 322179, 122, 0, 2881856, 2686976, 482124, 151, 4, 12, 1, 0, 6422528, -1, 1, 10, 50, 8, 0],
        [70562989, -236977661, 384772, 145, 0, 3013817, 2686976, 687658, 151, 3, 12, 1, 0, 6029312, -1, 1, 10, 50, 8, 0],
        [71050159, -236977477, 441497, 166, 0, 3139648, 2686976, 905359, 151, 2, 12, 1, 0, 5636096, -1, 1, 10, 50, 8, 0],
        [71594054, -236977272, 492904, 185, 0, 3185984, 2686976, 1048576, 151, 1, 12, 1, 0, 5242880, -1, 1, 10, 50, 8, 0],
        [72189356, -236977048, 539492, 203, 0, 3112000, 2686976, 1048576, 152, 4, 12, 1, 0, 4849664, -1, 1, 10, 50, 8, 0],
        [72831246, -236976806, 581712, 219, 0, 2996536, 2686976, 1048576, 152, 3, 12, 1, 0, 4456448, -1, 1, 10, 50, 8, 0],
        [73515356, -236976548, 619974, 233, 0, 2850856, 2686976, 1048576, 152, 2, 12, 1, 0, 4063232, -1, 1, 10, 50, 8, 0],
        [74237728, -236976276, 654649, 246, 0, 2689184, 2686976, 1048576, 152, 1, 12, 1, 0, 3670016, -1, 1, 10, 50, 8, 0],
        [74994775, -236975991, 686073, 258, 0, 2527304, 2686976, 1048576, 153, 4, 12, 1, 0, 3276800, -1, 1, 10, 50, 8, 0],
        [75783246, -236975694, 714551, 269, 0, 2380992, 2686976, 1048576, 153, 3, 12, 1, 0, 2883584, -1, 1, 10, 50, 8, 0],
        [76600195, -236975386, 740360, 279, 0, 2264552, 2686976, 1048576, 153, 2, 12, 1, 0, 2490368, -1, 1, 10, 50, 8, 0],
        [77442953, -236975068, 763749, 288, 0, 2189344, 2686976, 1048576, 153, 1, 10, 1, 269696, 3125648, -1, 1, 10, 50, 8, 0],
        [78260836, -237020681, 741206, -41337, 41943040, 2162704, 2686976, 1048576, 150, 4, 10, 1, 167904, 3140704, -1, 1, 10, 50, 8, 0],
        [79058889, -237104512, 723235, -75972, 83886080, 2187232, 2686976, 1048576, 150, 3, 10, 1, 65136, 3145712, -1, 1, 10, 50, 8, 0],
        [79841470, -237219412, 709214, -104129, 125829120, 2260544, 2686976, 1048576, 150, 2, 10, 1, -37632, 3140624, -1, 1, 10, 50, 8, 0],
        [80612305, -237358756, 698569, -126281, 167772160, 2375472, 2686976, 1048576, 150, 1, 10, 1, -139424, 3125488, -1, 1, 10, 50, 8, 0],
        [81374539, -237516407, 690774, -142872, 209715200, 2520800, 2686976, 1048576, 151, 4, 10, 1, -239232, 3100448, -1, 1, 10, 50, 8, 0],
        [82130780, -237686687, 685343, -154317, 251658240, 2682352, 2686976, 1048576, 151, 3, 10, 1, -336096, 3065744, -1, 1, 10, 50, 8, 0],
        [82883147, -237864345, 681832, -161003, 293601280, 2844352, 2686976, 1048576, 151, 2, 10, 1, -429104, 3021712, -1, 1, 10, 50, 8, 0],
        [83633309, -238044535, 679834, -163298, 335544320, 2990992, 2686976, 1048576, 151, 1, 10, 1, -517344, 2968784, -1, 1, 10, 50, 8, 0],
        [84382521, -238222794, 678973, -161548, 377487360, 3107968, 2686976, 1048576, 152, 4, 10, 1, -599984, 2907456, -1, 1, 10, 50, 8, 0],
        [85131659, -238395021, 678906, -156081, 419430400, 3183840, 2686976, 1048576, 152, 3, 10, 1, -676192, 2838320, -1, 1, 10, 50, 8, 0],
        [85810565, -238551102, 615258, -141449, 419430400, 3211224, 2686976, 1048576, 152, 2, 10, 1, -745264, 2762048, -1, 1, 10, 50, 8, 0],
        [86425823, -238692551, 557577, -128189, 419430400, 3187440, 2686976, 1048576, 152, 1, 10, 1, -806544, 2679360, -1, 1, 10, 50, 8, 0],
        [86983400, -238820740, 505304, -116172, 419430400, 3114808, 2686976, 1048576, 153, 4, 10, 1, -859408, 2591088, -1, 1, 10, 50, 8, 0],
        [87488704, -238936912, 457931, -105281, 419430400, 2993516, 2686976, 1025497, 153, 3, 10, 1, -882035, 2489224, -1, 1, 10, 50, 8, 0],
        [87946635, -239042193, 414999, -95411, 419430400, 2822281, 2686976, 842227, 153, 2, 10, 1, -740515, 2341327, -1, 1, 10, 50, 8, 0],
        [88445330, -239078611, 451942, -33004, 419430400, 2693372, 2686976, 953761, 154, 11, 13, 4, -740515, 2341327, -1, 1, 10, 50, 8, 0],
        [88980968, -239052622, 485421, 23552, 419430400, 2531904, 2686976, 1048576, 154, 10, 13, 3, -740515, 2341327, -1, 1, 10, 50, 8, 0],
        [89550085, -238970077, 515762, 74806, 419430400, 2384928, 2686976, 1048576, 154, 9, 13, 2, -740515, 2341327, -1, 1, 10, 50, 8, 0],
        [90149543, -238836278, 543258, 121255, 419430400, 2267432, 2686976, 1048576, 154, 8, 13, 1, -740515, 2341327, -1, 1, 10, 50, 8, 0],
        [90776497, -238656030, 568177, 163349, 419430400, 2190880, 2686976, 1048576, 155, 5, 14, 6, -740515, 2341327, 17, 1, 10, 49, 8, 1],
        [91428370, -238433688, 590759, 201497, 419430400, 2162760, 2686976, 1048576, 155, 4, 14, 5, -740515, 2341327, 17, 1, 10, 49, 8, 1],
        [92102825, -238173198, 611224, 236069, 419430400, 2185792, 2686976, 1048576, 155, 3, 14, 4, -740515, 2341327, 17, 1, 10, 49, 8, 1],
        [92797745, -237878136, 629771, 267399, 419430400, 2257752, 2686976, 1048576, 155, 2, 14, 3, -740515, 2341327, 17, 1, 10, 49, 8, 1],
        [93427516, -237610737, 570729, 242330, 419430400, 2371600, 2686976, 1048576, 155, 1, 14, 2, -740515, 2341327, 17, 1, 2, 49, 8, 1],
        [93953021, -237300102, 476238, 281512, 399769600, 2516232, 2686976, 1048576, 154, 12, 14, 1, -740515, 2341327, 17, 1, 2, 49, 8, 1],
        [94385991, -236949030, 392379, 318159, 380108800, 2677528, 2686976, 1048576, 154, 11, 15, 4, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [94737147, -236560080, 318235, 352485, 360448000, 2839585, 2686976, 1047487, 154, 10, 15, 3, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [95016185, -236135663, 252878, 384627, 340787200, 2968614, 2686976, 984161, 154, 9, 15, 2, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [95231979, -235677991, 195563, 414765, 321126400, 3076404, 2686976, 976679, 154, 8, 15, 1, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [95427542, -235263226, 195563, 414765, 301465600, 3735552, 2686976, 802134, 154, 7, 16, 5, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [95623105, -234848461, 195563, 414765, 281804800, 3735552, 2686976, 802134, 154, 6, 16, 4, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [95818668, -234433696, 195563, 414765, 262144000, 3735552, 2686976, 802134, 154, 5, 16, 3, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [95985777, -233942113, 151442, 445497, 242483200, 3109282, 2686976, 1028363, 154, 4, 16, 2, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [96110956, -233419021, 113443, 474052, 222822400, 3004272, 2686976, 1048576, 154, 3, 16, 1, -740515, 2341327, -1, 1, 2, 49, 8, 1],
        [96200409, -232866642, 81066, 500593, 203161600, 2860000, 2686976, 1048576, 149, -1, 11, 1, -740515, 2734543, -1, 1, 2, 49, 8, 1],
        [96259717, -232287072, 53747, 525235, 183500800, 2698832, 2686976, 1048576, 150, 3, 11, 1, -740515, 3127759, -1, 1, 2, 49, 8, 1],
        [96313464, -231761837, 48708, 475994, 183500800, 2536520, 2686976, 1048576, 150, 2, 11, 1, -740515, 3520975, -1, 1, 2, 49, 8, 1],
        [96362172, -231285843, 44141, 431369, 183500800, 2438695, 2686976, 873347, 150, 1, 11, 1, -740515, 3914191, -1, 1, 2, 49, 8, 1],
        [96406313, -230854474, 40002, 390928, 183500800, 2401983, 2686976, 717268, 151, 4, 11, 1, -740515, 4307407, -1, 1, 2, 49, 8, 1],
        [96446315, -230463546, 36251, 354278, 183500800, 2409162, 2686976, 589083, 151, 3, 11, 1, -740515, 4700623, -1, 1, 2, 49, 8, 1],
        [96482566, -230109268, 32852, 321064, 183500800, 2445150, 2686976, 483806, 151, 2, 11, 1, -740515, 5093839, -1, 1, 2, 49, 8, 1],
        [96515418, -229788204, 29772, 290964, 183500800, 2496532, 2686976, 397343, 151, 1, 11, 1, -740515, 5487055, -1, 1, 2, 49, 8, 1],
        [96545190, -229497240, 26980, 263686, 183500800, 2552538, 2686976, 326333, 152, 4, 11, 1, -740515, 5880271, -1, 1, 2, 49, 8, 1],
        [96572170, -229233554, 24450, 238965, 183500800, 2605385, 2686976, 268013, 152, 3, 11, 1, -740515, 6273487, -1, 1, 2, 49, 8, 1],
        [96596620, -228994589, 22157, 216562, 183500800, 2650178, 2686976, 220115, 152, 2, 11, 1, -740515, 6666703, -1, 1, 2, 49, 8, 1],
        [96618777, -228778027, 20079, 196259, 183500800, 2684515, 2686976, 180778, 152, 1, 11, 1, -740515, 7059919, -1, 1, 2, 49, 8, 1],
        [96638856, -228581768, 18196, 177859, 183500800, 2707952, 2686976, 148470, 153, 4, 11, 1, -740515, 7453135, -1, 1, 2, 49, 8, 1],
        [96657052, -228403909, 16490, 161184, 183500800, 2721409, 2686976, 121936, 153, 3, 11, 1, -740515, 7846351, -1, 1, 2, 49, 8, 1],
        [96673542, -228242725, 14944, 146073, 183500800, 2726626, 2686976, 100144, 153, 2, 11, 1, -740515, 8239567, -1, 1, 2, 49, 8, 1],
        [96688486, -228096652, 13543, 132378, 183500800, 2725700, 2686976, 82247, 153, 1, 20, 1, -740515, 7995392, -1, 2, 10, 49, 8, 1],
        [96702029, -227964274, 12273, 119967, 183500800, 2720735, 2686976, 67548, 150, 4, 20, 1, -740515, 7602176, -1, 2, 10, 49, 8, 1],
        [96714302, -227844307, 11122, 108720, 183500800, 2713600, 2686976, 55475, 150, 3, 20, 1, -740515, 7208960, -1, 2, 10, 49, 8, 1],
        [96725424, -227735587, 10079, 98527, 183500800, 2705804, 2686976, 45561, 150, 2, 20, 1, -740515, 6815744, -1, 2, 10, 49, 8, 1],
        [96735503, -227637060, 9134, 89290, 183500800, 2698435, 2686976, 37418, 150, 1, 20, 1, -740515, 6422528, -1, 2, 10, 49, 8, 1],
        [96744637, -227547770, 8277, 80919, 183500800, 2692179, 2686976, 30731, 151, 4, 20, 1, -740515, 6029312, -1, 2, 10, 49, 8, 1],
        [96752914, -227466851, 7501, 73332, 183500800, 2687377, 2686976, 25239, 151, 3, 20, 1, -740515, 5636096, -1, 2, 10, 49, 8, 1],
        [96760415, -227393519, 6797, 66457, 183500800, 2684093, 2686976, 20728, 151, 2, 20, 1, -740515, 5242880, -1, 2, 10, 49, 8, 1],
        [96767212, -227327062, 6159, 60226, 183500800, 2682201, 2686976, 17023, 151, 1, 20, 1, -740515, 4849664, -1, 2, 10, 49, 8, 1],
        [96773371, -227266836, 5581, 54579, 183500800, 2681460, 2686976, 13981, 152, 4, 20, 1, -740515, 4456448, -1, 2, 10, 49, 8, 1],
        [96778952, -227212257, 5057, 49462, 183500800, 2681578, 2686976, 11482, 152, 3, 20, 1, -740515, 4063232, -1, 2, 10, 49, 8, 1],
        [96784009, -227162795, 4582, 44824, 183500800, 2682263, 2686976, 9430, 152, 2, 20, 1, -740515, 3670016, -1, 2, 10, 49, 8, 1],
        [96788591, -227117971, 4152, 40621, 183500800, 2683254, 2686976, 7744, 152, 1, 20, 1, -740515, 3276800, -1, 2, 10, 49, 8, 1],
        [96792743, -227077350, 3762, 36812, 183500800, 2684339, 2686976, 6360, 153, 4, 20, 1, -740515, 2883584, -1, 2, 10, 49, 8, 1],
        [96796505, -227040538, 3409, 33360, 183500800, 2685367, 2686976, 5223, 153, 3, 20, 1, -740515, 2490368, -1, 2, 10, 49, 8, 1],
        [96799914, -227007178, 3089, 30232, 183500800, 2686240, 2686976, 4289, 154, 11, 21, 3, -740515, 2097152, -1, 2, 10, 49, 8, 1],
        [96803003, -226976946, 2799, 27397, 183500800, 2686911, 2686976, 3522, 154, 10, 21, 2, -740515, 2097152, -1, 2, 10, 49, 8, 1],
        [96805802, -226949549, 2536, 24828, 183500800, 2687371, 2686976, 2893, 154, 9, 21, 1, -740515, 2097152, -1, 2, 10, 49, 8, 1],
        [96808338, -226924721, 2298, 22500, 183500800, 2687637, 2686976, 2375, 155, 5, 22, 7, -740515, 2097152, 30, 2, 10, 49, 7, 22],
        [96810636, -226902221, 2082, 20390, 183500800, 2687742, 2686976, 1951, 155, 4, 22, 6, -740515, 2097152, 30, 2, 10, 49, 7, 22],
        [96812718, -226881831, 1886, 18478, 183500800, 2687727, 2686976, 1602, 155, 3, 22, 5, -740515, 2097152, 30, 2, 10, 49, 7, 22],
        [96814604, -226863353, 1709, 16745, 183500800, 2687632, 2686976, 1315, 155, 2, 22, 4, -740515, 2097152, 31, 2, 10, 49, 7, 22],
        [96816313, -226846608, 1548, 15175, 183500800, 2687495, 2686976, 1080, 155, 1, 22, 3, -740515, 2097152, 31, 2, 10, 49, 7, 22],
        [96817861, -226831433, 1402, 13752, 183500800, 2687344, 2686976, 887, 154, 12, 22, 2, -740515, 2097152, 31, 2, 10, 49, 7, 22],
        [96819263, -226817681, 1270, 12462, 183500800, 2687201, 2686976, 728, 154, 11, 22, 1, -740515, 2097152, -1, 2, 10, 49, 7, 22],
        [96820533, -226805219, 1150, 11293, 183500800, 2687079, 2686976, 598, 154, 10, 23, 5, -740515, 2097152, -1, 2, 10, 49, 7, 22]
    ];

    var mo = testSetupPlayer();
    DPlayer.players_weaponowned[DoomDef.wp_shotgun] = 1;
    DPlayer.players_ammo[DoomDef.am_shell] = 8;

    for (var t = 0; t < walk.size(); t++) {
        // the cmds from player_ref.c
        var forwardmove = 0;
        var sidemove = 0;
        var angleturn = 0;
        var buttons = 0;
        if (t < 15) {
            forwardmove = 50;
        } else if (t < 25) {
            forwardmove = 25;
            sidemove = 24;
            angleturn = 640;
        } else if (t < 30) {
        } else if (t < 38) {
            forwardmove = 50;
            buttons = DPlayer.BT_ATTACK;
        } else if (t == 38) {
            buttons = DPlayer.BT_CHANGE | (DoomDef.wp_shotgun << DPlayer.BT_WEAPONSHIFT);
        } else if (t < 51) {
            angleturn = -300;
            sidemove = -40;
        } else if (t < 60) {
            buttons = DPlayer.BT_USE;
        } else {
            buttons = DPlayer.BT_ATTACK;
        }
        DPlayer.players_cmd_forwardmove[0] = forwardmove;
        DPlayer.players_cmd_sidemove[0] = sidemove;
        DPlayer.players_cmd_angleturn[0] = angleturn;
        DPlayer.players_cmd_buttons[0] = buttons;
        // airborne for a few tics
        PMobj.mobjs_z[mo] = (t >= 44 && t < 47) ? 16 * MFixed.FRACUNIT : 0;

        testPlayerTic();

        var e = walk[t];
        var got = [
            PMobj.mobjs_x[mo], PMobj.mobjs_y[mo], PMobj.mobjs_momx[mo], PMobj.mobjs_momy[mo],
            PMobj.mobjs_angle[mo], DPlayer.players_viewz[0], DPlayer.players_viewheight[0],
            DPlayer.players_bob[0], PMobj.mobjs_state[mo], PMobj.mobjs_tics[mo],
            DPlayer.players_psprites_state[0], DPlayer.players_psprites_tics[0],
            DPlayer.players_psprites_sx[0], DPlayer.players_psprites_sy[0],
            DPlayer.players_psprites_state[1],
            DPlayer.players_readyweapon[0], DPlayer.players_pendingweapon[0],
            DPlayer.players_ammo[DoomDef.am_clip], DPlayer.players_ammo[DoomDef.am_shell],
            MRandom.prndindex
        ];
        for (var i = 0; i < e.size(); i++) {
            Test.assertEqualMessage(got[i], e[i], "tic " + t + " field " + i);
        }
    }
    return true;
}

(:test)
function testDamagePlayerMatchesC(logger as Test.Logger) as Boolean {
    // health, player health, armorpoints, armortype, momx, momy, damagecount,
    // mo state, mo tics, flags, playerstate, weapon state, attacker is source, prndindex
    var damage = [
        [93, 93, 17, 1, -73272, -36635, 7, 156, 4, 33557574, 0, 12, 1, 1],
        [76, 76, 9, 1, -256451, -128223, 24, 156, 4, 33557574, 0, 12, 1, 2],
        [71, 71, 7, 1, -307741, -153868, 29, 156, 4, 33557574, 0, 12, 1, 3],
        [48, 48, 0, 0, -527555, -263773, 52, 156, 4, 33557574, 0, 12, 1, 4],
        [40, 40, 193, 2, -637462, -318726, 60, 156, 4, 33557574, 0, 12, 1, 5],
        [19, 19, 173, 2, -937875, -468930, 81, 156, 4, 33557574, 0, 12, 1, 6],
        [17, 17, 172, 2, -959857, -479921, 83, 156, 4, 33557574, 0, 12, 1, 7],
        [-83, 0, 72, 2, -2425282, -1212621, 100, 158, 7, 34606144, 1, 11, 1, 8]
    ];

    // angle, viewz, viewheight, damagecount, weapon state, sy, playerstate
    var death = [
        [59652323, 2621640, 2621440, 100, 11, 8388608, 1],
        [119304646, 2717872, 2555904, 100, 11, 8388608, 1],
        [178956969, 2798304, 2490368, 100, 11, 8388608, 1],
        [238609292, 2848680, 2424832, 100, 11, 8388608, 1],
        [298261615, 2857680, 2359296, 100, 11, 8388608, 1],
        [340797984, 2818040, 2293760, 99, 11, 8388608, 1],
        [342854272, 2727232, 2228224, 98, 11, 8388608, 1],
        [344648000, 2587712, 2162688, 97, 11, 8388608, 1],
        [345926048, 2406712, 2097152, 96, 11, 8388608, 1],
        [346946592, 2195496, 2031616, 95, 11, 8388608, 1],
        [347965440, 1968288, 1966080, 94, 11, 8388608, 1],
        [348728448, 1740872, 1900544, 93, 11, 8388608, 1],
        [349490528, 1529024, 1835008, 92, 11, 8388608, 1],
        [350251648, 1347048, 1769472, 91, 11, 8388608, 1],
        [350758528, 1206304, 1703936, 90, 11, 8388608, 1],
        [351264992, 1114128, 1638400, 89, 11, 8388608, 1],
        [351518048, 1157179, 1572864, 88, 11, 8388608, 1],
        [352023872, 1216012, 1507328, 87, 11, 8388608, 1],
        [352276640, 1267018, 1441792, 86, 11, 8388608, 1],
        [352529280, 1299682, 1376256, 85, 11, 8388608, 1],
        [352781824, 1308970, 1310720, 84, 11, 8388608, 1],
        [353034272, 1294098, 1245184, 83, 11, 8388608, 1],
        [353286592, 1257254, 1179648, 82, 11, 8388608, 1],
        [353286592, 1202373, 1114112, 81, 11, 8388608, 1],
        [353538816, 1134128, 1048576, 80, 11, 8388608, 1],
        [353790944, 1057177, 983040, 79, 11, 8388608, 1],
        [353790944, 975629, 917504, 78, 11, 8388608, 1],
        [354042944, 892777, 851968, 77, 11, 8388608, 1],
        [354042944, 810987, 786432, 76, 11, 8388608, 1],
        [354042944, 731734, 720896, 75, 11, 8388608, 2]
    ];

    var mo = testSetupPlayer();
    var source = testSpawn(Info.MT_POSSESSED, 1256 << 16, -3516 << 16);
    MRandom.M_ClearRandom();

    // damage, armortype, armorpoints (-1: keep)
    var dmg = [
        [10, 1, 20], [25, -1, -1], [7, -1, -1], [30, -1, -1],
        [15, 2, 200], [41, -1, -1], [3, -1, -1], [200, -1, -1]
    ];
    for (var t = 0; t < dmg.size(); t++) {
        if (dmg[t][1] >= 0) {
            DPlayer.players_armortype[0] = dmg[t][1];
            DPlayer.players_armorpoints[0] = dmg[t][2];
        }
        PInter.P_DamageMobj(mo, source, source, dmg[t][0]);

        var e = damage[t];
        var got = [
            PMobj.mobjs_health[mo], DPlayer.players_health[0], DPlayer.players_armorpoints[0],
            DPlayer.players_armortype[0], PMobj.mobjs_momx[mo], PMobj.mobjs_momy[mo],
            DPlayer.players_damagecount[0], PMobj.mobjs_state[mo], PMobj.mobjs_tics[mo],
            PMobj.mobjs_flags[mo], DPlayer.players_playerstate[0],
            DPlayer.players_psprites_state[0], DPlayer.players_attacker[0] == source ? 1 : 0,
            MRandom.prndindex
        ];
        for (var i = 0; i < e.size(); i++) {
            Test.assertEqualMessage(got[i], e[i], "damage " + t + " field " + i);
        }
    }

    // dead: turn towards the killer, fall and lower the weapon
    for (var t = 0; t < death.size(); t++) {
        DPlayer.players_cmd_forwardmove[0] = 0;
        DPlayer.players_cmd_sidemove[0] = 0;
        DPlayer.players_cmd_angleturn[0] = 0;
        DPlayer.players_cmd_buttons[0] = t == 29 ? DPlayer.BT_USE : 0;
        testPlayerTic();

        var e = death[t];
        var got = [
            PMobj.mobjs_angle[mo], DPlayer.players_viewz[0], DPlayer.players_viewheight[0],
            DPlayer.players_damagecount[0], DPlayer.players_psprites_state[0],
            DPlayer.players_psprites_sy[0], DPlayer.players_playerstate[0]
        ];
        for (var i = 0; i < e.size(); i++) {
            Test.assertEqualMessage(got[i], e[i], "death tic " + t + " field " + i);
        }
    }
    return true;
}

(:test)
function testTouchSpecialThingMatchesC(logger as Test.Logger) as Boolean {
    // health, armorpoints, armortype, clip, shells, has shotgun, pendingweapon,
    // bonuscount, itemcount, removed, message
    var touch = [
        [101, 0, 0, 50, 0, 0, 10, 6, 1, 1, "Picked up a health bonus."],
        [101, 0, 0, 60, 0, 0, 10, 12, 1, 1, "Picked up a clip."],
        [101, 0, 0, 65, 0, 0, 10, 18, 1, 1, "Picked up a clip."],
        [101, 0, 0, 65, 8, 1, 2, 24, 1, 1, "You got the shotgun!"],
        [101, 0, 0, 65, 16, 1, 2, 30, 1, 1, "You got the shotgun!"],
        [101, 0, 0, 65, 20, 1, 2, 36, 1, 1, "You got the shotgun!"],
        [101, 0, 0, 65, 20, 1, 2, 36, 1, 0, null],
        [101, 100, 1, 65, 20, 1, 2, 42, 1, 1, "Picked up the armor."],
        [101, 100, 1, 65, 20, 1, 2, 42, 1, 0, null],
        [102, 100, 1, 65, 20, 1, 2, 48, 2, 1, "Picked up a health bonus."],
        [102, 100, 1, 65, 20, 1, 2, 48, 2, 0, null]
    ];

    var mo = testSetupPlayer();

    // type, dropped, z
    var items = [
        [Info.MT_MISC2, 0, 0],                    // health bonus
        [Info.MT_CLIP, 0, 0],                     // clip
        [Info.MT_CLIP, 1, 0],                     // dropped clip: half a clip
        [Info.MT_SHOTGUN, 0, 0],                  // shotgun: weapon and 2 clips of shells
        [Info.MT_SHOTGUN, 0, 0],                  // again: just the shells
        [Info.MT_SHOTGUN, 1, 0],                  // dropped: one clip of shells
        [Info.MT_MISC11, 0, 0],                   // medikit at 101%: not needed
        [Info.MT_MISC0, 0, 0],                    // green armor
        [Info.MT_MISC0, 0, 0],                    // again: not picked up
        [Info.MT_MISC2, 0, 9 * MFixed.FRACUNIT],  // above, but still within reach
        [Info.MT_MISC2, 0, -9 * MFixed.FRACUNIT]  // out of reach below
    ];
    for (var t = 0; t < items.size(); t++) {
        var item = testSpawn(items[t][0], PMobj.mobjs_x[mo], PMobj.mobjs_y[mo]);
        if (items[t][1] != 0) {
            PMobj.mobjs_flags[item] |= PMobj.MF_DROPPED;
        }
        PMobj.mobjs_z[item] = items[t][2];
        DPlayer.players_message[0] = null;
        PInter.P_TouchSpecialThing(item, mo);

        var e = touch[t];
        var got = [
            DPlayer.players_health[0], DPlayer.players_armorpoints[0], DPlayer.players_armortype[0],
            DPlayer.players_ammo[DoomDef.am_clip], DPlayer.players_ammo[DoomDef.am_shell],
            DPlayer.players_weaponowned[DoomDef.wp_shotgun], DPlayer.players_pendingweapon[0],
            DPlayer.players_bonuscount[0], DPlayer.players_itemcount[0],
            PTick.thinkers_function[item] == PTick.TF_REMOVED ? 1 : 0
        ];
        for (var i = 0; i < got.size(); i++) {
            Test.assertEqualMessage(got[i], e[i], "item " + t + " field " + i);
        }
        var msg = DPlayer.players_message[0];
        if (e[10] == null) {
            Test.assertMessage(msg == null, "item " + t + " message");
        } else {
            Test.assertMessage(msg != null && msg.equals(e[10]), "item " + t + " message");
        }
    }
    return true;
}
