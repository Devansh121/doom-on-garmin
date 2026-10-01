// The function pointers in state_t (info.c's actionf_t) as a dispatch.
//
// Monkey C has no function pointers, so states[].action holds a number
// (see the list in Info.mc) and these switches call the matching A_*
// function. Weapon states call theirs with (player, psp) like
// P_SetPsprite does, everything else with the mobj like P_SetMobjState.

import Toybox.Lang;

module Actions {

    // st->action.acp1(mobj)
    function P_MobjAction(action as Number, mo as Number) as Void {
        switch (action) {
            case 23:
                PPspr.A_BFGSpray(mo);
                break;
            case 24:
                PEnemy.A_Explode(mo);
                break;
            case 25:
                PEnemy.A_Pain(mo);
                break;
            case 26:
                PEnemy.A_PlayerScream(mo);
                break;
            case 27:
                PEnemy.A_Fall(mo);
                break;
            case 28:
                PEnemy.A_XScream(mo);
                break;
            case 29:
                PEnemy.A_Look(mo);
                break;
            case 30:
                PEnemy.A_Chase(mo);
                break;
            case 31:
                PEnemy.A_FaceTarget(mo);
                break;
            case 32:
                PEnemy.A_PosAttack(mo);
                break;
            case 33:
                PEnemy.A_Scream(mo);
                break;
            case 34:
                PEnemy.A_SPosAttack(mo);
                break;
            case 35:
                PEnemy.A_VileChase(mo);
                break;
            case 36:
                PEnemy.A_VileStart(mo);
                break;
            case 37:
                PEnemy.A_VileTarget(mo);
                break;
            case 38:
                PEnemy.A_VileAttack(mo);
                break;
            case 39:
                PEnemy.A_StartFire(mo);
                break;
            case 40:
                PEnemy.A_Fire(mo);
                break;
            case 41:
                PEnemy.A_FireCrackle(mo);
                break;
            case 42:
                PEnemy.A_Tracer(mo);
                break;
            case 43:
                PEnemy.A_SkelWhoosh(mo);
                break;
            case 44:
                PEnemy.A_SkelFist(mo);
                break;
            case 45:
                PEnemy.A_SkelMissile(mo);
                break;
            case 46:
                PEnemy.A_FatRaise(mo);
                break;
            case 47:
                PEnemy.A_FatAttack1(mo);
                break;
            case 48:
                PEnemy.A_FatAttack2(mo);
                break;
            case 49:
                PEnemy.A_FatAttack3(mo);
                break;
            case 50:
                PEnemy.A_BossDeath(mo);
                break;
            case 51:
                PEnemy.A_CPosAttack(mo);
                break;
            case 52:
                PEnemy.A_CPosRefire(mo);
                break;
            case 53:
                PEnemy.A_TroopAttack(mo);
                break;
            case 54:
                PEnemy.A_SargAttack(mo);
                break;
            case 55:
                PEnemy.A_HeadAttack(mo);
                break;
            case 56:
                PEnemy.A_BruisAttack(mo);
                break;
            case 57:
                PEnemy.A_SkullAttack(mo);
                break;
            case 58:
                PEnemy.A_Metal(mo);
                break;
            case 59:
                PEnemy.A_SpidRefire(mo);
                break;
            case 60:
                PEnemy.A_BabyMetal(mo);
                break;
            case 61:
                PEnemy.A_BspiAttack(mo);
                break;
            case 62:
                PEnemy.A_Hoof(mo);
                break;
            case 63:
                PEnemy.A_CyberAttack(mo);
                break;
            case 64:
                PEnemy.A_PainAttack(mo);
                break;
            case 65:
                PEnemy.A_PainDie(mo);
                break;
            case 66:
                PEnemy.A_KeenDie(mo);
                break;
            case 67:
                PEnemy.A_BrainPain(mo);
                break;
            case 68:
                PEnemy.A_BrainScream(mo);
                break;
            case 69:
                PEnemy.A_BrainDie(mo);
                break;
            case 70:
                PEnemy.A_BrainAwake(mo);
                break;
            case 71:
                PEnemy.A_BrainSpit(mo);
                break;
            case 72:
                PEnemy.A_SpawnSound(mo);
                break;
            case 73:
                PEnemy.A_SpawnFly(mo);
                break;
            case 74:
                PEnemy.A_BrainExplode(mo);
                break;
        }
    }

    // state->action.acp2(player, psp)
    function P_PspriteAction(action as Number, player as Number, psp as Number) as Void {
        switch (action) {
            case 1:
                PPspr.A_Light0(player, psp);
                break;
            case 2:
                PPspr.A_WeaponReady(player, psp);
                break;
            case 3:
                PPspr.A_Lower(player, psp);
                break;
            case 4:
                PPspr.A_Raise(player, psp);
                break;
            case 5:
                PPspr.A_Punch(player, psp);
                break;
            case 6:
                PPspr.A_ReFire(player, psp);
                break;
            case 7:
                PPspr.A_FirePistol(player, psp);
                break;
            case 8:
                PPspr.A_Light1(player, psp);
                break;
            case 9:
                PPspr.A_FireShotgun(player, psp);
                break;
            case 10:
                PPspr.A_Light2(player, psp);
                break;
            case 11:
                PPspr.A_FireShotgun2(player, psp);
                break;
            case 12:
                PPspr.A_CheckReload(player, psp);
                break;
            case 13:
                PPspr.A_OpenShotgun2(player, psp);
                break;
            case 14:
                PPspr.A_LoadShotgun2(player, psp);
                break;
            case 15:
                PPspr.A_CloseShotgun2(player, psp);
                break;
            case 16:
                PPspr.A_FireCGun(player, psp);
                break;
            case 17:
                PPspr.A_GunFlash(player, psp);
                break;
            case 18:
                PPspr.A_FireMissile(player, psp);
                break;
            case 19:
                PPspr.A_Saw(player, psp);
                break;
            case 20:
                PPspr.A_FirePlasma(player, psp);
                break;
            case 21:
                PPspr.A_BFGsound(player, psp);
                break;
            case 22:
                PPspr.A_FireBFG(player, psp);
                break;
        }
    }
}
