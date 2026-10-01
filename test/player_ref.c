// Reference values for test/PlayerTest.mc. Unlike the other refs this
// one doesn't copy anything: it links the original linuxdoom-1.10
// p_user.c, p_pspr.c, p_inter.c, d_items.c, info.c, tables.c and
// m_random.c as they are, and only supplies what they call into
// (P_SetMobjState, copied from p_mobj.c, R_PointToAngle2 and finecosine
// from r_main.c, and empty stubs).
//
// P_TryMove just moves, and each tic runs P_PlayerThink followed by the
// parts of P_MobjThinker a player in open space needs: P_XYMovement (from
// p_mobj.c) and the state tic countdown. The Monkey C test does the same.
//
//   D=~/src/DOOM/linuxdoom-1.10
//   gcc -w -I $D test/player_ref.c $D/p_user.c $D/p_pspr.c $D/p_inter.c \
//       $D/d_items.c $D/info.c $D/tables.c $D/m_random.c -o player_ref && ./player_ref
//
// The original headers are fine on 64-bit for this: no struct is
// read from WAD data.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "doomdef.h"
#include "d_event.h"
#include "doomstat.h"
#include "p_local.h"
#include "m_random.h"
#include "r_main.h"

// ---- globals the linked files expect ----
player_t players[MAXPLAYERS];
boolean playeringame[MAXPLAYERS];
int consoleplayer;
skill_t gameskill = sk_medium;
GameMode_t gamemode = shareware;
boolean netgame;
boolean deathmatch;
boolean automapactive;
int leveltime;
mobj_t* linetarget;
fixed_t viewx, viewy;
fixed_t* finecosine = &finesine[FINEANGLES / 4];

extern int prndindex; // m_random.c

fixed_t FixedMul(fixed_t a, fixed_t b) { return ((long long) a * (long long) b) >> FRACBITS; }
fixed_t FixedDiv(fixed_t a, fixed_t b) { return (fixed_t)(((long long)a << 16) / b); }

void I_Error(char* error, ...) { va_list ap; va_start(ap, error); vfprintf(stderr, error, ap); va_end(ap); exit(1); }
void I_Tactile(int on, int off, int total) {}
void AM_Stop(void) {}
void S_StartSound(void* origin, int sound_id) {}

// ---- r_main.c ----
angle_t R_PointToAngle(fixed_t x, fixed_t y)
{
    x -= viewx;
    y -= viewy;
    if ((!x) && (!y))
        return 0;
    if (x >= 0) {
        if (y >= 0) {
            if (x > y) return tantoangle[SlopeDiv(y, x)];
            else return ANG90 - 1 - tantoangle[SlopeDiv(x, y)];
        } else {
            y = -y;
            if (x > y) return -tantoangle[SlopeDiv(y, x)];
            else return ANG270 + tantoangle[SlopeDiv(x, y)];
        }
    } else {
        x = -x;
        if (y >= 0) {
            if (x > y) return ANG180 - 1 - tantoangle[SlopeDiv(y, x)];
            else return ANG90 + tantoangle[SlopeDiv(x, y)];
        } else {
            y = -y;
            if (x > y) return ANG180 + tantoangle[SlopeDiv(y, x)];
            else return ANG270 - 1 - tantoangle[SlopeDiv(x, y)];
        }
    }
    return 0;
}

angle_t R_PointToAngle2(fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2)
{
    viewx = x1;
    viewy = y1;
    return R_PointToAngle(x2, y2);
}

// ---- stubs for the modules other people port ----
int removed[16];
mobj_t mobjs[16];
int nummobjs;
int spawned;

void P_RemoveMobj(mobj_t* th) { removed[th - mobjs] = 1; }
mobj_t* P_SpawnMobj(fixed_t x, fixed_t y, fixed_t z, mobjtype_t type) { spawned++; return &mobjs[15]; }
fixed_t P_AimLineAttack(mobj_t* t1, angle_t angle, fixed_t distance) { linetarget = NULL; return 0; }
void P_LineAttack(mobj_t* t1, angle_t angle, fixed_t distance, fixed_t slope, int damage) {}
void P_UseLines(player_t* player) {}
void P_NoiseAlert(mobj_t* target, mobj_t* emmiter) {}
void P_SpawnPlayerMissile(mobj_t* source, mobjtype_t type) {}
void P_PlayerInSpecialSector(player_t* player) {}
boolean P_TryMove(mobj_t* thing, fixed_t x, fixed_t y) { thing->x = x; thing->y = y; return true; }
void P_SlideMove(mobj_t* mo) {}

// p_enemy.c / p_mobj.c actions named by info.c; the Monkey C side has
// them as empty stubs too.
#define STUB(n) void n() {}
STUB(A_Explode) STUB(A_Pain) STUB(A_PlayerScream) STUB(A_Fall) STUB(A_XScream)
STUB(A_Look) STUB(A_Chase) STUB(A_FaceTarget) STUB(A_PosAttack) STUB(A_Scream)
STUB(A_SPosAttack) STUB(A_VileChase) STUB(A_VileStart) STUB(A_VileTarget)
STUB(A_VileAttack) STUB(A_StartFire) STUB(A_Fire) STUB(A_FireCrackle)
STUB(A_Tracer) STUB(A_SkelWhoosh) STUB(A_SkelFist) STUB(A_SkelMissile)
STUB(A_FatRaise) STUB(A_FatAttack1) STUB(A_FatAttack2) STUB(A_FatAttack3)
STUB(A_BossDeath) STUB(A_CPosAttack) STUB(A_CPosRefire) STUB(A_TroopAttack)
STUB(A_SargAttack) STUB(A_HeadAttack) STUB(A_BruisAttack) STUB(A_SkullAttack)
STUB(A_Metal) STUB(A_SpidRefire) STUB(A_BabyMetal) STUB(A_BspiAttack)
STUB(A_Hoof) STUB(A_CyberAttack) STUB(A_PainAttack) STUB(A_PainDie)
STUB(A_KeenDie) STUB(A_BrainPain) STUB(A_BrainScream) STUB(A_BrainDie)
STUB(A_BrainAwake) STUB(A_BrainSpit) STUB(A_SpawnSound) STUB(A_SpawnFly)
STUB(A_BrainExplode)
// p_enemy.c weapon actions
void A_ReFire(player_t* player, pspdef_t* psp);
void A_OpenShotgun2(player_t* player, pspdef_t* psp) {}
void A_LoadShotgun2(player_t* player, pspdef_t* psp) {}
void A_CloseShotgun2(player_t* player, pspdef_t* psp) { A_ReFire(player, psp); }

// ---- p_mobj.c ----
boolean P_SetMobjState(mobj_t* mobj, statenum_t state)
{
    state_t* st;
    do {
        if (state == S_NULL) {
            mobj->state = (state_t*) S_NULL;
            P_RemoveMobj(mobj);
            return false;
        }
        st = &states[state];
        mobj->state = st;
        mobj->tics = st->tics;
        mobj->sprite = st->sprite;
        mobj->frame = st->frame;
        if (st->action.acp1)
            st->action.acp1(mobj);
        state = st->nextstate;
    } while (!mobj->tics);
    return true;
}

#define STOPSPEED 0x1000
#define FRICTION 0xe800

void P_XYMovement(mobj_t* mo)
{
    fixed_t ptryx, ptryy;
    player_t* player;
    fixed_t xmove, ymove;

    if (!mo->momx && !mo->momy)
        return;
    player = mo->player;
    if (mo->momx > MAXMOVE) mo->momx = MAXMOVE;
    else if (mo->momx < -MAXMOVE) mo->momx = -MAXMOVE;
    if (mo->momy > MAXMOVE) mo->momy = MAXMOVE;
    else if (mo->momy < -MAXMOVE) mo->momy = -MAXMOVE;
    xmove = mo->momx;
    ymove = mo->momy;
    do {
        if (xmove > MAXMOVE / 2 || ymove > MAXMOVE / 2) {
            ptryx = mo->x + xmove / 2;
            ptryy = mo->y + ymove / 2;
            xmove >>= 1;
            ymove >>= 1;
        } else {
            ptryx = mo->x + xmove;
            ptryy = mo->y + ymove;
            xmove = ymove = 0;
        }
        if (!P_TryMove(mo, ptryx, ptryy))
            P_SlideMove(mo);
    } while (xmove || ymove);

    if (player && player->cheats & CF_NOMOMENTUM) {
        mo->momx = mo->momy = 0;
        return;
    }
    if (mo->flags & (MF_MISSILE | MF_SKULLFLY))
        return;
    if (mo->z > mo->floorz)
        return;
    if (mo->momx > -STOPSPEED && mo->momx < STOPSPEED
        && mo->momy > -STOPSPEED && mo->momy < STOPSPEED
        && (!player || (player->cmd.forwardmove == 0 && player->cmd.sidemove == 0))) {
        if (player && (unsigned)((player->mo->state - states) - S_PLAY_RUN1) < 4)
            P_SetMobjState(player->mo, S_PLAY);
        mo->momx = 0;
        mo->momy = 0;
    } else {
        mo->momx = FixedMul(mo->momx, FRICTION);
        mo->momy = FixedMul(mo->momy, FRICTION);
    }
}

// one tic of P_Ticker for the player, as described at the top
void tic(player_t* p)
{
    mobj_t* mo = p->mo;
    P_PlayerThink(p);
    P_XYMovement(mo);
    if (mo->tics != -1) {
        mo->tics--;
        if (!mo->tics)
            P_SetMobjState(mo, mo->state->nextstate);
    }
    leveltime++;
}

// ---- test setup, mirrored in PlayerTest.mc ----
void setup_mobj(mobj_t* mo, mobjtype_t type, fixed_t x, fixed_t y)
{
    memset(mo, 0, sizeof(*mo));
    mo->type = type;
    mo->info = &mobjinfo[type];
    mo->x = x;
    mo->y = y;
    mo->z = 0;
    mo->floorz = 0;
    mo->ceilingz = 128 * FRACUNIT;
    mo->radius = mo->info->radius;
    mo->height = mo->info->height;
    mo->flags = mo->info->flags;
    mo->health = mo->info->spawnhealth;
    mo->reactiontime = mo->info->reactiontime;
    mo->state = &states[mo->info->spawnstate];
    mo->tics = mo->state->tics;
    mo->sprite = mo->state->sprite;
    mo->frame = mo->state->frame;
}

sector_t sector0;
subsector_t subsector0;

player_t* setup_player(void)
{
    player_t* p = &players[0];
    mobj_t* mo = &mobjs[0];
    int i;

    memset(p, 0, sizeof(*p));
    setup_mobj(mo, MT_PLAYER, 1056 * FRACUNIT, -3616 * FRACUNIT);
    subsector0.sector = &sector0;
    mo->subsector = &subsector0;
    mo->player = p;
    p->mo = mo;
    p->playerstate = PST_LIVE;
    p->health = 100;
    p->viewheight = VIEWHEIGHT;
    p->readyweapon = wp_pistol;
    p->pendingweapon = wp_nochange;
    p->weaponowned[wp_fist] = 1;
    p->weaponowned[wp_pistol] = 1;
    for (i = 0; i < NUMAMMO; i++)
        p->maxammo[i] = maxammo[i];
    p->ammo[am_clip] = 50;
    P_SetMobjState(mo, S_PLAY);
    P_SetupPsprites(p);
    M_ClearRandom();
    leveltime = 0;
    return p;
}

int st(state_t* s) { return s ? (int)(s - states) : -1; }

void print_player(player_t* p)
{
    mobj_t* mo = p->mo;
    printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d],\n",
           mo->x, mo->y, mo->momx, mo->momy, (int)mo->angle, p->viewz, p->viewheight, p->bob,
           st(mo->state), mo->tics,
           st(p->psprites[0].state), p->psprites[0].tics, p->psprites[0].sx, p->psprites[0].sy,
           st(p->psprites[1].state),
           p->readyweapon, p->pendingweapon, p->ammo[am_clip], p->ammo[am_shell], prndindex);
}

int main(void)
{
    player_t* p;
    int t;

    // 1. walking, turning, firing and switching weapons
    p = setup_player();
    p->weaponowned[wp_shotgun] = 1;
    p->ammo[am_shell] = 8;
    printf("    // x, y, momx, momy, angle, viewz, viewheight, bob, mo state, mo tics,\n"
           "    // weapon state, tics, sx, sy, flash state, readyweapon, pendingweapon,\n"
           "    // clip, shells, prndindex\n");
    printf("    var walk = [\n");
    for (t = 0; t < 90; t++) {
        ticcmd_t* cmd = &p->cmd;
        memset(cmd, 0, sizeof(*cmd));
        if (t < 15) cmd->forwardmove = 50;
        else if (t < 25) { cmd->forwardmove = 25; cmd->sidemove = 24; cmd->angleturn = 640; }
        else if (t < 30) ;
        else if (t < 38) { cmd->forwardmove = 50; cmd->buttons = BT_ATTACK; }
        else if (t == 38) cmd->buttons = BT_CHANGE | (wp_shotgun << BT_WEAPONSHIFT);
        else if (t < 51) { cmd->angleturn = -300; cmd->sidemove = -40; }
        else if (t < 60) cmd->buttons = BT_USE;
        else cmd->buttons = BT_ATTACK;
        // airborne for a few tics
        if (t >= 44 && t < 47) p->mo->z = 16 * FRACUNIT;
        else p->mo->z = 0;
        tic(p);
        print_player(p);
    }
    printf("    ];\n\n");

    // 2. damage with armor, then death
    p = setup_player();
    setup_mobj(&mobjs[1], MT_POSSESSED, 1256 * FRACUNIT, -3516 * FRACUNIT);
    {
        int dmg[][3] = {
            // damage, armortype, armorpoints (-1: keep)
            {10, 1, 20}, {25, -1, -1}, {7, -1, -1}, {30, -1, -1},
            {15, 2, 200}, {41, -1, -1}, {3, -1, -1}, {200, -1, -1}
        };
        int i;
        printf("    // health, player health, armorpoints, armortype, momx, momy, damagecount,\n"
               "    // mo state, mo tics, flags, playerstate, weapon state, attacker is source, prndindex\n");
        printf("    var damage = [\n");
        for (i = 0; i < 8; i++) {
            if (dmg[i][1] >= 0) { p->armortype = dmg[i][1]; p->armorpoints = dmg[i][2]; }
            P_DamageMobj(p->mo, &mobjs[1], &mobjs[1], dmg[i][0]);
            printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d],\n",
                   p->mo->health, p->health, p->armorpoints, p->armortype, p->mo->momx, p->mo->momy,
                   p->damagecount, st(p->mo->state), p->mo->tics, p->mo->flags, p->playerstate,
                   st(p->psprites[0].state), p->attacker == &mobjs[1], prndindex);
        }
        printf("    ];\n");
    }
    // dead: turn towards the killer, fall and lower the weapon
    printf("    // angle, viewz, viewheight, damagecount, weapon state, sy, playerstate\n");
    printf("    var death = [\n");
    for (t = 0; t < 30; t++) {
        memset(&p->cmd, 0, sizeof(p->cmd));
        if (t == 29) p->cmd.buttons = BT_USE;
        tic(p);
        printf("        [%d, %d, %d, %d, %d, %d, %d],\n", (int)p->mo->angle, p->viewz, p->viewheight,
               p->damagecount, st(p->psprites[0].state), p->psprites[0].sy, p->playerstate);
    }
    printf("    ];\n\n");

    // 3. item pickups
    p = setup_player();
    {
        // type, dropped, z
        int items[][3] = {
            {MT_MISC2, 0, 0},           // health bonus
            {MT_CLIP, 0, 0},            // clip
            {MT_CLIP, 1, 0},            // dropped clip: half a clip
            {MT_SHOTGUN, 0, 0},         // shotgun: weapon and 2 clips of shells
            {MT_SHOTGUN, 0, 0},         // again: just the shells
            {MT_SHOTGUN, 1, 0},         // dropped: one clip of shells
            {MT_MISC11, 0, 0},          // medikit at 101%: not needed
            {MT_MISC0, 0, 0},           // green armor
            {MT_MISC0, 0, 0},           // again: not picked up
            {MT_MISC2, 0, 9 * FRACUNIT},  // above, but still within reach
            {MT_MISC2, 0, -9 * FRACUNIT}, // out of reach below
        };
        int i;
        printf("    // health, armorpoints, armortype, clip, shells, has shotgun, pendingweapon,\n"
               "    // bonuscount, itemcount, removed, message\n");
        printf("    var touch = [\n");
        for (i = 0; i < 11; i++) {
            mobj_t* mo = &mobjs[2 + i];
            setup_mobj(mo, items[i][0], p->mo->x, p->mo->y);
            if (items[i][1]) mo->flags |= MF_DROPPED;
            mo->z = items[i][2];
            p->message = NULL;
            P_TouchSpecialThing(mo, p->mo);
            printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s%s%s],\n",
                   p->health, p->armorpoints, p->armortype, p->ammo[am_clip], p->ammo[am_shell],
                   p->weaponowned[wp_shotgun], p->pendingweapon, p->bonuscount, p->itemcount,
                   removed[2 + i], p->message ? "\"" : "", p->message ? p->message : "null",
                   p->message ? "\"" : "");
        }
        printf("    ];\n");
    }
    return 0;
}
