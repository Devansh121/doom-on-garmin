// Reference values for test/PlayerTest.mc. Nothing from the game is
// copied here: this links every original linuxdoom-1.10 p_*.c file but
// p_saveg.c (p_user, p_pspr, p_inter, p_map, p_maputl, p_sight, p_mobj,
// p_enemy, the p_spec family, p_setup, p_tick), plus d_items.c, info.c,
// tables.c, m_random.c and m_bbox.c, as they are. This file only
// supplies what they call into:
//  - a tiny WAD reader, so the real P_SetupLevel loads E1M1 from
//    doom1.wad, things and specials included, like PSetup does,
//  - R_PointInSubsector / R_PointToAngle2 / finecosine from r_main.c and
//    G_PlayerReborn from g_game.c, copied,
//  - stubs for sound, the status bar, level exits and the zone allocator.
// Textures and flats only matter here for the sky checks, so
// R_FlatNumForName gives F_SKY1 the number skyflatnum and every other
// flat and texture is 0.
//
// Each tic is P_PlayerThink plus P_MobjThinker for the player's mobj; the
// other thinkers aren't run. From the repo root:
//
//   D=~/src/DOOM/linuxdoom-1.10
//   gcc -w -I $D test/player_ref.c $(ls $D/p_*.c | grep -v p_saveg) \
//       $D/d_items.c $D/info.c $D/tables.c $D/m_random.c $D/m_bbox.c \
//       -o player_ref && ./player_ref doom1.wad
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>

#include "doomdef.h"
#include "d_event.h"
#include "doomstat.h"
#include "p_local.h"
#include "m_random.h"
#include "r_main.h"
#include "r_sky.h"
#include "w_wad.h"
#include "z_zone.h"
#include "g_game.h"

// ---- globals the linked files expect ----
player_t players[MAXPLAYERS];
boolean playeringame[MAXPLAYERS];
int consoleplayer;
int displayplayer;
skill_t gameskill = sk_medium;
GameMode_t gamemode = shareware;
boolean netgame;
boolean deathmatch;
boolean automapactive;
boolean respawnmonsters;
boolean nomonsters;
boolean paused;
boolean menuactive;
boolean demoplayback;
boolean precache;
boolean viewactive;
int gametic;
int gamemap = 1;
int gameepisode = 1;
boolean fastparm;
int totalkills, totalitems, totalsecret;
wbstartstruct_t wminfo;
int skyflatnum = 1;
int bodyqueslot;
fixed_t viewx, viewy;
fixed_t* finecosine = &finesine[FINEANGLES / 4];
int validcount = 1;
extern int prndindex; // m_random.c

fixed_t FixedMul(fixed_t a, fixed_t b) { return ((long long) a * (long long) b) >> FRACBITS; }
fixed_t FixedDiv2(fixed_t a, fixed_t b) { long long c = ((long long)a<<16) / ((long long)b); return (fixed_t) c; }
fixed_t FixedDiv(fixed_t a, fixed_t b) { if ((abs(a)>>14) >= abs(b)) return (a^b)<0 ? MININT : MAXINT; return FixedDiv2(a,b); }

void I_Error(char* error, ...) { va_list ap; va_start(ap, error); vfprintf(stderr, error, ap); va_end(ap); fprintf(stderr, "\n"); exit(1); }
void I_Tactile(int on, int off, int total) {}
void AM_Stop(void) {}
void S_StartSound(void* origin, int sound_id) {}
void S_StopSound(void* origin) {}
void S_Start(void) {}
void ST_Start(void) {}
void HU_Start(void) {}
void R_PrecacheLevel(void) {}
int R_TextureNumForName(char* name) { return 0; }
int R_FlatNumForName(char* name) { return strncasecmp(name, "F_SKY1", 8) == 0 ? skyflatnum : 0; }

// ---- z_zone.c: plain heap ----
// Twice the size asked for: P_GroupLines allocates total*4 bytes for
// line pointers, which is short on 64-bit.
void* Z_Malloc(int size, int tag, void* user) { void* p = calloc(2, size); if (user) *(void**)user = p; return p; }
void Z_Free(void* ptr) {}
void Z_FreeTags(int lowtag, int hightag) {}
void Z_ChangeTag2(void* ptr, int tag) {}

// ---- w_wad.c: just enough to read map lumps from one IWAD ----
typedef struct { int filepos, size; char name[8]; } wadlump_t;
static FILE* wadfile;
static wadlump_t* wadlumps;
static int numwadlumps;

void W_Open(const char* path)
{
    char id[4];
    int dir;
    wadfile = fopen(path, "rb");
    if (!wadfile) I_Error("can't open %s", path);
    fread(id, 1, 4, wadfile);
    fread(&numwadlumps, 4, 1, wadfile);
    fread(&dir, 4, 1, wadfile);
    wadlumps = malloc(numwadlumps * sizeof(wadlump_t));
    fseek(wadfile, dir, SEEK_SET);
    fread(wadlumps, sizeof(wadlump_t), numwadlumps, wadfile);
}
void W_Reload(void) {}
int W_GetNumForName(char* name)
{
    int i;
    for (i = numwadlumps - 1; i >= 0; i--)
        if (!strncasecmp(wadlumps[i].name, name, 8)) return i;
    I_Error("W_GetNumForName: %s not found!", name);
    return -1;
}
int W_LumpLength(int lump) { return wadlumps[lump].size; }
void* W_CacheLumpNum(int lump, int tag)
{
    void* p = malloc(wadlumps[lump].size + 1);
    fseek(wadfile, wadlumps[lump].filepos, SEEK_SET);
    fread(p, 1, wadlumps[lump].size, wadfile);
    return p;
}

// ---- stubs ----
// r_data.c tables: every texture and flat is number 0 here (see above)
fixed_t textureheight_[1] = {0};
fixed_t* textureheight = textureheight_;
int translation_[2] = {0, 1};
int* texturetranslation = translation_;
int* flattranslation = translation_;
int R_CheckTextureNumForName(char* name) { return -1; }
int W_CheckNumForName(char* name) { return -1; }
int M_CheckParm(char* check) { return 0; }
char** myargv;
// g_game.c; stubs in GGame.mc too
void G_ExitLevel(void) {}
void G_SecretExitLevel(void) {}
void G_DeathMatchSpawnPlayer(int playernum) {}
// P_Init in p_setup.c, never called
void R_InitSprites(char** namelist) {}

// ---- copied from r_main.c ----
int R_PointOnSide(fixed_t x, fixed_t y, node_t* node)
{
    fixed_t dx, dy, left, right;
    if (!node->dx) { if (x <= node->x) return node->dy > 0; return node->dy < 0; }
    if (!node->dy) { if (y <= node->y) return node->dx < 0; return node->dx > 0; }
    dx = (x - node->x);
    dy = (y - node->y);
    if ((node->dy ^ node->dx ^ dx ^ dy) & 0x80000000) {
        if ((node->dy ^ dx) & 0x80000000) return 1;
        return 0;
    }
    left = FixedMul(node->dy >> FRACBITS, dx);
    right = FixedMul(dy, node->dx >> FRACBITS);
    if (right < left) return 0;
    return 1;
}

subsector_t* R_PointInSubsector(fixed_t x, fixed_t y)
{
    node_t* node;
    int side, nodenum;
    if (!numnodes) return subsectors;
    nodenum = numnodes - 1;
    while (!(nodenum & NF_SUBSECTOR)) {
        node = &nodes[nodenum];
        side = R_PointOnSide(x, y, node);
        nodenum = node->children[side];
    }
    return &subsectors[nodenum & ~NF_SUBSECTOR];
}

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

// ---- copied from g_game.c ----
void G_PlayerReborn(int player)
{
    player_t* p;
    int i;
    int frags[MAXPLAYERS];
    int killcount;
    int itemcount;
    int secretcount;

    memcpy(frags, players[player].frags, sizeof(frags));
    killcount = players[player].killcount;
    itemcount = players[player].itemcount;
    secretcount = players[player].secretcount;

    p = &players[player];
    memset(p, 0, sizeof(*p));

    memcpy(players[player].frags, frags, sizeof(players[player].frags));
    players[player].killcount = killcount;
    players[player].itemcount = itemcount;
    players[player].secretcount = secretcount;

    p->usedown = p->attackdown = true;	// don't do anything immediately
    p->playerstate = PST_LIVE;
    p->health = MAXHEALTH;
    p->readyweapon = p->pendingweapon = wp_pistol;
    p->weaponowned[wp_fist] = true;
    p->weaponowned[wp_pistol] = true;
    p->ammo[am_clip] = 50;

    for (i = 0; i < NUMAMMO; i++)
        p->maxammo[i] = maxammo[i];
}

// ---- the test ----

// one tic of P_Ticker for the player, as described at the top
void tic(player_t* p)
{
    P_PlayerThink(p);
    P_MobjThinker(p->mo);
    leveltime++;
}

// A fresh E1M1 with player 0 reborn at its start, the random index back
// at 0 first. Mirrored by testSetupPlayer in PlayerTest.mc.
player_t* setup_player(void)
{
    M_ClearRandom();
    playeringame[0] = true;
    players[0].playerstate = PST_REBORN;
    P_SetupLevel(1, 1, 0, sk_medium);
    leveltime = 0;
    return &players[0];
}

int st(state_t* s) { return s ? (int)(s - states) : -1; }

boolean removed(mobj_t* mo) { return mo->thinker.function.acv == (actionf_v)(-1); }

// mobjs in the level, so the puffs, blood and dropped items that
// shooting leaves behind are compared too
int count_mobjs(void)
{
    thinker_t* th;
    int n = 0;
    for (th = thinkercap.next; th != &thinkercap; th = th->next)
        if (th->function.acp1 == (actionf_p1)P_MobjThinker) n++;
    return n;
}

void print_player(player_t* p)
{
    mobj_t* mo = p->mo;
    printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d],\n",
           mo->x, mo->y, mo->z, mo->momx, mo->momy, (int)mo->angle, p->viewz, p->viewheight, p->bob,
           st(mo->state), mo->tics,
           st(p->psprites[0].state), p->psprites[0].tics, p->psprites[0].sx, p->psprites[0].sy,
           st(p->psprites[1].state),
           p->readyweapon, p->pendingweapon, p->ammo[am_clip], p->ammo[am_shell], prndindex,
           count_mobjs());
}

int main(int argc, char** argv)
{
    player_t* p;
    int t;

    W_Open(argc > 1 ? argv[1] : "doom1.wad");

    // 1. walking, turning, firing and switching weapons from the E1M1
    // start, with real clipping against the walls and things
    p = setup_player();
    p->weaponowned[wp_shotgun] = 1;
    p->ammo[am_shell] = 8;
    printf("    // x, y, z, momx, momy, angle, viewz, viewheight, bob, mo state, mo tics,\n"
           "    // weapon state, tics, sx, sy, flash state, readyweapon, pendingweapon,\n"
           "    // clip, shells, prndindex, mobjs\n");
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
        // a little hop: P_ZMovement brings it back down
        if (t == 44) p->mo->z = p->mo->floorz + 16 * FRACUNIT;
        tic(p);
        print_player(p);
    }
    printf("    ];\n\n");

    // 2. damage with armor, then death
    p = setup_player();
    {
        mobj_t* source = P_SpawnMobj(p->mo->x + 200 * FRACUNIT, p->mo->y + 100 * FRACUNIT, ONFLOORZ, MT_POSSESSED);
        int dmg[][3] = {
            // damage, armortype, armorpoints (-1: keep)
            {10, 1, 20}, {25, -1, -1}, {7, -1, -1}, {30, -1, -1},
            {15, 2, 200}, {41, -1, -1}, {3, -1, -1}, {200, -1, -1}
        };
        int i;
        M_ClearRandom();
        printf("    // health, player health, armorpoints, armortype, momx, momy, damagecount,\n"
               "    // mo state, mo tics, flags, playerstate, weapon state, attacker is source, prndindex\n");
        printf("    var damage = [\n");
        for (i = 0; i < 8; i++) {
            if (dmg[i][1] >= 0) { p->armortype = dmg[i][1]; p->armorpoints = dmg[i][2]; }
            P_DamageMobj(p->mo, source, source, dmg[i][0]);
            printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d],\n",
                   p->mo->health, p->health, p->armorpoints, p->armortype, p->mo->momx, p->mo->momy,
                   p->damagecount, st(p->mo->state), p->mo->tics, p->mo->flags, p->playerstate,
                   st(p->psprites[0].state), p->attacker == source, prndindex);
        }
        printf("    ];\n");
    }
    // dead: slide back, turn towards the killer, fall and lower the weapon
    printf("    // x, y, angle, viewz, viewheight, damagecount, weapon state, sy, playerstate\n");
    printf("    var death = [\n");
    for (t = 0; t < 30; t++) {
        memset(&p->cmd, 0, sizeof(p->cmd));
        if (t == 29) p->cmd.buttons = BT_USE;
        tic(p);
        printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d],\n", p->mo->x, p->mo->y, (int)p->mo->angle,
               p->viewz, p->viewheight, p->damagecount, st(p->psprites[0].state), p->psprites[0].sy,
               p->playerstate);
    }
    printf("    ];\n\n");

    // 3. item pickups
    p = setup_player();
    {
        // type, dropped, z above the player
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
            mobj_t* mo = P_SpawnMobj(p->mo->x, p->mo->y, ONFLOORZ, items[i][0]);
            if (items[i][1]) mo->flags |= MF_DROPPED;
            mo->z = p->mo->z + items[i][2];
            p->message = NULL;
            P_TouchSpecialThing(mo, p->mo);
            printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s%s%s],\n",
                   p->health, p->armorpoints, p->armortype, p->ammo[am_clip], p->ammo[am_shell],
                   p->weaponowned[wp_shotgun], p->pendingweapon, p->bonuscount, p->itemcount,
                   removed(mo), p->message ? "\"" : "", p->message ? p->message : "null",
                   p->message ? "\"" : "");
        }
        printf("    ];\n");
    }
    return 0;
}
