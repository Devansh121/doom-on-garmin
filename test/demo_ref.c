// Ground truth for test/DemoTest.mc: plays DEMO1..3 from doom1.wad
// through the original game code and prints the state after every tic.
//
// Like test/player_ref.c, nothing from the game is copied here: this
// links every original linuxdoom-1.10 p_*.c file but p_saveg.c, plus
// d_items.c, info.c, tables.c, m_random.c and m_bbox.c, as they are.
// This file only supplies what they call into:
//  - a small WAD reader, with the texture and flat numbering r_data.c
//    does (TEXTURE1 order, flats counted from F_START + 1), so switches,
//    animations, the sky flat and textureheight work like in the game,
//  - R_PointInSubsector / R_PointToAngle2 from r_main.c, and
//    G_PlayerReborn, G_InitNew, G_DoLoadLevel, G_ReadDemoTiccmd and the
//    demo part of G_DoPlayDemo / G_Ticker from g_game.c, copied,
//  - stubs for sound, the status bar, the automap and the HUD.
//
// The flow is G_DeferedPlayDemo's: G_DoPlayDemo reads the header and
// calls G_InitNew (M_ClearRandom, then G_DoLoadLevel / P_SetupLevel),
// then every tic G_Ticker does reborns, reads the demo's ticcmd into
// players[0].cmd and runs P_Ticker. The tic where G_ReadDemoTiccmd hits
// DEMOMARKER isn't run: the demo's over (G_CheckDemoStatus).
//
// One line per tic, after P_Ticker, see print_tic. From the repo root:
//
//   D=~/src/DOOM/linuxdoom-1.10
//   gcc -w -I $D test/demo_ref.c $(ls $D/p_*.c | grep -v p_saveg) \
//       $D/d_items.c $D/info.c $D/tables.c $D/m_random.c $D/m_bbox.c \
//       -o demo_ref && ./demo_ref doom1.wad DEMO1
//
// test/gen_demo_expect.py turns that output into DemoExpect.mc.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>
#include <stdint.h>

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
skill_t gameskill;
GameMode_t gamemode = shareware;
boolean netgame;
boolean deathmatch;
boolean automapactive;
boolean respawnmonsters;
boolean respawnparm;
boolean nomonsters;
boolean paused;
boolean menuactive;
boolean demoplayback;
boolean precache;
boolean viewactive;
boolean usergame;
int gametic;
int gamemap = 1;
int gameepisode = 1;
boolean fastparm;
int totalkills, totalitems, totalsecret;
wbstartstruct_t wminfo;
int skyflatnum;
int skytexture;
int bodyqueslot;
fixed_t viewx, viewy;
fixed_t* finecosine = &finesine[FINEANGLES / 4];
int validcount = 1;
gamestate_t gamestate;
gameaction_t gameaction;
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

// ---- z_zone.c: plain heap ----
// Twice the size asked for: P_GroupLines allocates total*4 bytes for
// line pointers, which is short on 64-bit.
void* Z_Malloc(int size, int tag, void* user) { void* p = calloc(2, size); if (user) *(void**)user = p; return p; }
void Z_Free(void* ptr) {}
void Z_FreeTags(int lowtag, int hightag) {}
void Z_ChangeTag2(void* ptr, int tag) {}

// ---- w_wad.c: one IWAD ----
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
int W_CheckNumForName(char* name)
{
    int i;
    for (i = numwadlumps - 1; i >= 0; i--)
        if (!strncasecmp(wadlumps[i].name, name, 8)) return i;
    return -1;
}
int W_GetNumForName(char* name)
{
    int i = W_CheckNumForName(name);
    if (i == -1) I_Error("W_GetNumForName: %s not found!", name);
    return i;
}
int W_LumpLength(int lump) { return wadlumps[lump].size; }
void* W_CacheLumpNum(int lump, int tag)
{
    void* p = malloc(wadlumps[lump].size + 1);
    fseek(wadfile, wadlumps[lump].filepos, SEEK_SET);
    fread(p, 1, wadlumps[lump].size, wadfile);
    return p;
}
void* W_CacheLumpName(char* name, int tag) { return W_CacheLumpNum(W_GetNumForName(name), tag); }

// ---- r_data.c: names, heights and translations only ----
static int numtextures;
static char (*texturenames)[8];
fixed_t* textureheight;
int* texturetranslation;
int* flattranslation;
int firstflat;

// R_InitTextures, as far as names and heights go
void R_InitData(void)
{
    char* lump[2] = {"TEXTURE1", "TEXTURE2"};
    int k, i, n = 0, numflats;
    for (k = 0; k < 2; k++)
        if (W_CheckNumForName(lump[k]) >= 0)
            numtextures += *(int*)W_CacheLumpName(lump[k], PU_STATIC);
    texturenames = calloc(numtextures, 8);
    textureheight = calloc(numtextures, sizeof(fixed_t));
    texturetranslation = calloc(numtextures + 1, sizeof(int));
    for (k = 0; k < 2; k++) {
        byte* data;
        int count;
        if (W_CheckNumForName(lump[k]) < 0) continue;
        data = W_CacheLumpName(lump[k], PU_STATIC);
        count = *(int*)data;
        for (i = 0; i < count; i++, n++) {
            byte* tex = data + ((int*)data)[1 + i];
            memcpy(texturenames[n], tex, 8);
            textureheight[n] = (*(short*)(tex + 14)) << FRACBITS;
        }
    }
    for (i = 0; i < numtextures; i++) texturetranslation[i] = i;
    firstflat = W_GetNumForName("F_START") + 1;
    numflats = W_GetNumForName("F_END") - 1 - firstflat + 1;
    flattranslation = calloc(numflats + 1, sizeof(int));
    for (i = 0; i < numflats; i++) flattranslation[i] = i;
}
int R_CheckTextureNumForName(char* name)
{
    int i;
    if (name[0] == '-') return 0;
    for (i = 0; i < numtextures; i++)
        if (!strncasecmp(texturenames[i], name, 8)) return i;
    return -1;
}
int R_TextureNumForName(char* name)
{
    int i = R_CheckTextureNumForName(name);
    if (i == -1) I_Error("R_TextureNumForName: %.8s not found", name);
    return i;
}
int R_FlatNumForName(char* name) { return W_GetNumForName(name) - firstflat; }

// ---- stubs ----
int M_CheckParm(char* check) { return 0; }
char** myargv;
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

// level exits: G_Ticker does G_DoCompleted on the next tic
int exits;
void G_ExitLevel(void) { gameaction = ga_completed; exits++; }
void G_SecretExitLevel(void) { gameaction = ga_completed; exits++; }

void G_DoLoadLevel(void)
{
    int i;

    // Set the sky map.
    skyflatnum = R_FlatNumForName(SKYFLATNAME);

    gamestate = GS_LEVEL;

    for (i = 0; i < MAXPLAYERS; i++) {
        if (playeringame[i] && players[i].playerstate == PST_DEAD)
            players[i].playerstate = PST_REBORN;
        memset(players[i].frags, 0, sizeof(players[i].frags));
    }

    P_SetupLevel(gameepisode, gamemap, 0, gameskill);
    displayplayer = consoleplayer;		// view the guy you are playing
    gameaction = ga_nothing;
}

void G_InitNew(skill_t skill, int episode, int map)
{
    int i;

    paused = false;

    if (skill > sk_nightmare)
        skill = sk_nightmare;
    if (episode < 1)
        episode = 1;
    if (gamemode == shareware && episode > 1)
        episode = 1;	// only start episode 1 on shareware
    if (map < 1)
        map = 1;
    if (map > 9)
        map = 9;

    M_ClearRandom();

    if (skill == sk_nightmare || respawnparm)
        respawnmonsters = true;
    else
        respawnmonsters = false;

    if (fastparm || (skill == sk_nightmare && gameskill != sk_nightmare)) {
        for (i = S_SARG_RUN1; i <= S_SARG_PAIN2; i++)
            states[i].tics >>= 1;
        mobjinfo[MT_BRUISERSHOT].speed = 20 * FRACUNIT;
        mobjinfo[MT_HEADSHOT].speed = 20 * FRACUNIT;
        mobjinfo[MT_TROOPSHOT].speed = 20 * FRACUNIT;
    } else if (skill != sk_nightmare && gameskill == sk_nightmare) {
        for (i = S_SARG_RUN1; i <= S_SARG_PAIN2; i++)
            states[i].tics <<= 1;
        mobjinfo[MT_BRUISERSHOT].speed = 15 * FRACUNIT;
        mobjinfo[MT_HEADSHOT].speed = 10 * FRACUNIT;
        mobjinfo[MT_TROOPSHOT].speed = 10 * FRACUNIT;
    }

    // force players to be initialized upon first level load
    for (i = 0; i < MAXPLAYERS; i++)
        players[i].playerstate = PST_REBORN;

    usergame = true;                // will be set false if a demo
    paused = false;
    demoplayback = false;
    automapactive = false;
    viewactive = true;
    gameepisode = episode;
    gamemap = map;
    gameskill = skill;

    skytexture = R_TextureNumForName("SKY1");

    G_DoLoadLevel();
}

#define DEMOMARKER 0x80 // g_game.c

static byte* demobuffer;
static byte* demo_p;

// returns false at DEMOMARKER (G_CheckDemoStatus)
boolean G_ReadDemoTiccmd(ticcmd_t* cmd)
{
    if (*demo_p == DEMOMARKER) {
        // end of demo data stream
        demoplayback = false;
        return false;
    }
    cmd->forwardmove = ((signed char)*demo_p++);
    cmd->sidemove = ((signed char)*demo_p++);
    cmd->angleturn = ((unsigned char)*demo_p++) << 8;
    cmd->buttons = (unsigned char)*demo_p++;
    return true;
}

void G_DoPlayDemo(char* name)
{
    skill_t skill;
    int i, episode, map;

    gameaction = ga_nothing;
    demobuffer = demo_p = W_CacheLumpName(name, PU_STATIC);
    // The 1.10 source release checks for VERSION (110), but its game
    // code is 1.9's and the shareware IWAD's demos are 1.9 ones.
    if (*demo_p++ != 109)
        I_Error("Demo is from a different game version!");

    skill = *demo_p++;
    episode = *demo_p++;
    map = *demo_p++;
    deathmatch = *demo_p++;
    respawnparm = *demo_p++;
    fastparm = *demo_p++;
    nomonsters = *demo_p++;
    consoleplayer = *demo_p++;

    for (i = 0; i < MAXPLAYERS; i++)
        playeringame[i] = *demo_p++;
    if (playeringame[1])
        I_Error("net demos aren't supported");

    precache = false;
    G_InitNew(skill, episode, map);
    precache = true;

    usergame = false;
    demoplayback = true;
}

// ---- the test ----

// A cheap order-sensitive checksum: rotate left 5, xor in the value.
// DemoTest.mc does the same with Monkey C's 32-bit Numbers.
static uint32_t mix(uint32_t h, int v) { return ((h << 5) | (h >> 27)) ^ (uint32_t)v; }

int st(state_t* s) { return s ? (int)(s - states) : -1; }

// tic, player mo x, y, z, angle, momx, momy, player health, armor,
// readyweapon, clip, prndindex, leveltime, thinkers, mobjs, kills,
// items, secrets, mobj hash (every mobj's x, y, z, angle, type, state,
// tics, health, flags and target, in thinker order), sector hash (every
// sector's floor and ceiling height, light, special and floorpic)
void print_tic(int tic)
{
    player_t* p = &players[0];
    mobj_t* mo = p->mo;
    thinker_t* th;
    int nthinkers = 0, nmobjs = 0, i;
    uint32_t mh = 0, sh = 0;

    for (th = thinkercap.next; th != &thinkercap; th = th->next) {
        nthinkers++;
        if (th->function.acp1 == (actionf_p1)P_MobjThinker) {
            mobj_t* m = (mobj_t*)th;
            nmobjs++;
            mh = mix(mh, m->x);
            mh = mix(mh, m->y);
            mh = mix(mh, m->z);
            mh = mix(mh, (int)m->angle);
            mh = mix(mh, m->type);
            mh = mix(mh, st(m->state));
            mh = mix(mh, m->tics);
            mh = mix(mh, m->health);
            mh = mix(mh, m->flags);
            mh = mix(mh, m->target ? m->target->type : -1);
        }
    }
    for (i = 0; i < numsectors; i++) {
        sector_t* s = &sectors[i];
        sh = mix(sh, s->floorheight);
        sh = mix(sh, s->ceilingheight);
        sh = mix(sh, s->lightlevel);
        sh = mix(sh, s->special);
        sh = mix(sh, s->floorpic);
    }
    printf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", tic,
           mo->x, mo->y, mo->z, (int)mo->angle, mo->momx, mo->momy, p->health, p->armorpoints,
           p->readyweapon, p->ammo[am_clip], prndindex, leveltime, nthinkers, nmobjs,
           p->killcount, p->itemcount, p->secretcount, (int)mh, (int)sh);
}

int main(int argc, char** argv)
{
    int tic;

    W_Open(argc > 1 ? argv[1] : "doom1.wad");
    R_InitData();
    // P_Init, but R_InitSprites
    P_InitSwitchList();
    P_InitPicAnims();

    // G_DeferedPlayDemo, then the next G_Ticker's G_DoPlayDemo
    G_DoPlayDemo(argc > 2 ? argv[2] : "DEMO1");
    fprintf(stderr, "%s: E%dM%d skill %d\n", argc > 2 ? argv[2] : "DEMO1", gameepisode, gamemap, gameskill);

    for (tic = 0;; tic++) {
        // G_Ticker: do player reborns if needed (G_DoReborn: single
        // player reloads the level, G_DoLoadLevel on ga_loadlevel)
        if (players[0].playerstate == PST_REBORN) {
            fprintf(stderr, "tic %d: reborn, level reloaded\n", tic);
            G_DoLoadLevel();
        }
        if (gameaction == ga_completed) {
            // G_DoCompleted and the intermission would run here.
            fprintf(stderr, "tic %d: level exit, not followed\n", tic);
            break;
        }

        // get commands
        memset(&players[0].cmd, 0, sizeof(ticcmd_t));
        if (!G_ReadDemoTiccmd(&players[0].cmd))
            break;

        // do main actions: GS_LEVEL
        P_Ticker();
        gametic++;
        print_tic(tic);
    }
    fprintf(stderr, "%d tics, %d exits\n", tic, exits);
    return 0;
}
