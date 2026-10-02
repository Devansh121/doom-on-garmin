// Reference values for test/SpecTest.mc. Unlike the other *_ref.c files
// this one doesn't copy anything: it links the original, unmodified
// p_spec.c, p_doors.c, p_plats.c, p_floor.c, p_ceilng.c, p_lights.c,
// p_switch.c, p_tick.c and m_random.c, and supplies just what they need
// from the rest of the engine. P_ChangeSector always returns false (no
// things get crushed), sounds are dropped, Z_Malloc zeroes (the port
// starts a special's fields at 0 where the C leaves them unset) and
// Z_Free leaks so P_RunThinkers can still read the freed thinker's
// next pointer.
//
// Map data is loaded the way P_LoadSectors, P_LoadSideDefs,
// P_LoadLineDefs and P_GroupLines do it. From the repo root:
//
//   python3 -c "import json;[print(len(d),*d) for n in ['lumps/e1m1_sectors','lumps/e1m1_sidedefs','lumps/e1m1_linedefs','resources/textureheights','resources/texturenames','resources/flatnames'] for d in [json.load(open(f'generated/{n}.json'))]]" > spec.txt
//   L=~/src/DOOM/linuxdoom-1.10
//   gcc -w -I $L test/spec_ref.c $L/p_spec.c $L/p_doors.c $L/p_plats.c $L/p_floor.c \
//       $L/p_ceilng.c $L/p_lights.c $L/p_switch.c $L/p_tick.c $L/m_random.c -o spec_ref
//   ./spec_ref < spec.txt
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>

#include "doomdef.h"
#include "doomstat.h"
#include "i_system.h"
#include "z_zone.h"
#include "m_argv.h"
#include "m_random.h"
#include "w_wad.h"
#include "r_local.h"
#include "p_local.h"
#include "g_game.h"
#include "s_sound.h"
#include "r_state.h"

// globals of the linked files that no header declares
extern int prndindex;
extern int numswitches;
extern short numlinespecials;
typedef struct { boolean istexture; int picnum; int basepic; int numpics; int speed; } anim_t;
extern anim_t anims[];
extern anim_t* lastanim;

// ---- what the p_spec family needs from elsewhere ----

sector_t* sectors; int numsectors;
side_t* sides; int numsides;
line_t* lines; int numlines;
line_t** linebuffer;

fixed_t* textureheight;
int* texturetranslation;
int* flattranslation;
int numtextures, numflats;
char texturenames[1024][9];
char flatnames[1024][9];
#define FIRSTFLAT 1000  // any lump number will do

GameMode_t gamemode = shareware;
boolean deathmatch, netgame, paused, menuactive, demoplayback;
int totalsecret;
int consoleplayer;
boolean playeringame[MAXPLAYERS];
player_t players[MAXPLAYERS];
int myargc; char** myargv;

// zeroed, like the Monkey C side starts every special's fields
void* Z_Malloc(int size, int tag, void* ptr) { return calloc(1, size); }
void Z_Free(void* ptr) { }
void I_Error(char* error, ...) {
    va_list ap; va_start(ap, error); vprintf(error, ap); va_end(ap);
    printf("\n"); exit(1);
}
void S_StartSound(void* origin, int sound_id) { }
boolean P_ChangeSector(sector_t* sector, boolean crunch) { return false; }
void P_DamageMobj(mobj_t* target, mobj_t* inflictor, mobj_t* source, int damage) { }
int EV_Teleport(line_t* line, int side, mobj_t* thing) { return 0; }
void G_ExitLevel(void) { }
void G_SecretExitLevel(void) { }
int M_CheckParm(char* check) { return 0; }
void P_PlayerThink(player_t* player) { }
void P_RespawnSpecials(void) { }

// The lump directory, as far as the specials look at it: the flats.
int W_CheckNumForName(char* name) {
    for (int i = numflats - 1; i >= 0; i--)
        if (!strncasecmp(flatnames[i], name, 8)) return FIRSTFLAT + i;
    return -1;
}

// ---- r_data.c, verbatim apart from the texture list ----
int R_FlatNumForName(char* name) {
    int i;
    char namet[9];
    i = W_CheckNumForName(name);
    if (i == -1) { namet[8] = 0; memcpy(namet, name, 8); I_Error("R_FlatNumForName: %s not found", namet); }
    return i - FIRSTFLAT;
}
int R_CheckTextureNumForName(char* name) {
    int i;
    // "NoTexture" marker.
    if (name[0] == '-') return 0;
    for (i = 0; i < numtextures; i++)
        if (!strncasecmp(texturenames[i], name, 8)) return i;
    return -1;
}
int R_TextureNumForName(char* name) {
    int i;
    i = R_CheckTextureNumForName(name);
    if (i == -1) I_Error("R_TextureNumForName: %s not found", name);
    return i;
}

// ---- loading ----
int nsec, nside, nline;
int* msec; int* mside; int* mline;

int* readints(int* n) {
    scanf("%d", n);
    int* v = malloc(sizeof(int) * (*n + 1));
    for (int i = 0; i < *n; i++) scanf("%d", &v[i]);
    return v;
}

void load(void) {
    numsectors = nsec / 7;
    sectors = calloc(numsectors, sizeof(sector_t));
    for (int i = 0; i < numsectors; i++) {
        int* ms = msec + i * 7;
        sector_t* ss = &sectors[i];
        ss->floorheight = ms[0] << FRACBITS;
        ss->ceilingheight = ms[1] << FRACBITS;
        ss->floorpic = ms[2];
        ss->ceilingpic = ms[3];
        ss->lightlevel = ms[4];
        ss->special = ms[5];
        ss->tag = ms[6];
        ss->thinglist = NULL;
    }
    numsides = nside / 6;
    sides = calloc(numsides, sizeof(side_t));
    for (int i = 0; i < numsides; i++) {
        int* msd = mside + i * 6;
        side_t* sd = &sides[i];
        sd->textureoffset = msd[0] << FRACBITS;
        sd->rowoffset = msd[1] << FRACBITS;
        sd->toptexture = msd[2];
        sd->bottomtexture = msd[3];
        sd->midtexture = msd[4];
        sd->sector = &sectors[msd[5]];
    }
    numlines = nline / 7;
    lines = calloc(numlines, sizeof(line_t));
    for (int i = 0; i < numlines; i++) {
        int* mld = mline + i * 7;
        line_t* ld = &lines[i];
        ld->flags = mld[2];
        ld->special = mld[3];
        ld->tag = mld[4];
        ld->sidenum[0] = mld[5];
        ld->sidenum[1] = mld[6];
        ld->frontsector = ld->sidenum[0] != -1 ? sides[ld->sidenum[0]].sector : 0;
        ld->backsector = ld->sidenum[1] != -1 ? sides[ld->sidenum[1]].sector : 0;
    }
    // P_GroupLines
    int total = 0;
    for (int i = 0; i < numlines; i++) {
        line_t* li = &lines[i];
        total++;
        li->frontsector->linecount++;
        if (li->backsector && li->backsector != li->frontsector) { li->backsector->linecount++; total++; }
    }
    linebuffer = malloc(total * sizeof(line_t*));
    line_t** fill = linebuffer;
    for (int i = 0; i < numsectors; i++) {
        sectors[i].lines = fill;
        for (int j = 0; j < numlines; j++)
            if (lines[j].frontsector == &sectors[i] || lines[j].backsector == &sectors[i]) *fill++ = &lines[j];
    }
    // R_InitTextures / R_InitFlats translation tables
    for (int i = 0; i < numtextures; i++) texturetranslation[i] = i;
    for (int i = 0; i < numflats; i++) flattranslation[i] = i;

    P_InitThinkers();
    leveltime = 0;
    prndindex = 0;
}

// one tic of P_Ticker without the player
void tic(void) {
    P_RunThinkers();
    P_UpdateSpecials();
    leveltime++;
}

int sec(sector_t* s) { return s ? s - sectors : -1; }

long long hashsector(int s, int tics, int* first) {
    long long h = 0;
    *first = -1;
    for (int t = 0; t < tics; t++) {
        tic();
        h += (long long)(t + 1) * ((sectors[s].floorheight >> 8) + 3LL * (sectors[s].ceilingheight >> 8));
        if (*first == -1 && !sectors[s].specialdata) *first = t + 1;
    }
    return h;
}

int main(void) {
    msec = readints(&nsec);
    mside = readints(&nside);
    mline = readints(&nline);
    int n;
    int* th = readints(&n);
    numtextures = n;
    textureheight = malloc(n * sizeof(fixed_t));
    for (int i = 0; i < n; i++) textureheight[i] = th[i] << FRACBITS;
    texturetranslation = malloc((n + 1) * sizeof(int));
    scanf("%d", &n);
    for (int i = 0; i < n; i++) scanf("%8s", texturenames[i]);
    scanf("%d", &numflats);
    for (int i = 0; i < numflats; i++) scanf("%8s", flatnames[i]);
    flattranslation = malloc((numflats + 1) * sizeof(int));

    P_InitSwitchList();
    P_InitPicAnims();
    load();

    printf("// numswitches %d, anims %d\n", numswitches, (int)(lastanim - anims));
    for (anim_t* a = anims; a < lastanim; a++)
        printf("//   anim istexture %d picnum %d basepic %d numpics %d speed %d\n",
               a->istexture, a->picnum, a->basepic, a->numpics, a->speed);

    // utilities on every sector
    long long usum = 0;
    printf("// sector, lowestfloor, highestfloor, nexthighestfloor, lowestceiling, highestceiling, minlight\n");
    for (int i = 0; i < numsectors; i++) {
        sector_t* s = &sectors[i];
        int v[6] = { P_FindLowestFloorSurrounding(s), P_FindHighestFloorSurrounding(s),
                     P_FindNextHighestFloor(s, s->floorheight), P_FindLowestCeilingSurrounding(s),
                     P_FindHighestCeilingSurrounding(s), P_FindMinSurroundingLight(s, s->lightlevel) };
        for (int k = 0; k < 6; k++) usum += (long long)(i + 1) * (k + 1) * (v[k] >> 8);
        if (i % 12 == 0 || i == 59 || i == 70 || i == 4)
            printf("[%d, %d, %d, %d, %d, %d, %d],\n", i, v[0], v[1], v[2], v[3], v[4], v[5]);
    }
    printf("// utility checksum %lldl\n", usum);
    printf("// FindSectorFromLineTag 195: %d, 308: %d, 308 after 59: %d\n",
           P_FindSectorFromLineTag(&lines[195], -1), P_FindSectorFromLineTag(&lines[308], -1),
           P_FindSectorFromLineTag(&lines[308], 59));

    // EV_VerticalDoor on line 151 (sector 4) used by a monster, then a
    // player closing it while it waits, then reopening it on the way down
    {
        mobj_t monster, player;
        memset(&monster, 0, sizeof(monster));
        memset(&player, 0, sizeof(player));
        player.player = &players[0];
        load();
        EV_VerticalDoor(&lines[151], &monster);
        printf("// door: tic, ceiling, direction\n");
        int s = 4;
        for (int t = 1; t <= 260; t++) {
            if (t == 20) EV_VerticalDoor(&lines[151], &monster);   // ignored, still going up
            if (t == 80) EV_VerticalDoor(&lines[151], &player);    // close it now
            if (t == 100) EV_VerticalDoor(&lines[151], &monster);  // going down: back up
            tic();
            vldoor_t* d = sectors[s].specialdata;
            if (t <= 3 || t % 20 == 0 || t == 99 || t == 101 || t == 255)
                printf("[%d, %d, %d],\n", t, sectors[s].ceilingheight, d ? d->direction : 99);
        }
    }

    // EV_DoDoor on line 195 (tag 2), every door type
    printf("// EV_DoDoor line 195: type, rtn, hash, tics till done, floor, ceiling\n");
    for (int type = 0; type <= 7; type++) {
        load();
        int rtn = EV_DoDoor(&lines[195], type);
        int first;
        long long h = hashsector(70, 400, &first);
        printf("[%d, %d, %lldl, %d, %d, %d],\n", type, rtn, h, first, sectors[70].floorheight, sectors[70].ceilingheight);
    }

    // EV_DoPlat on line 195 (tag 2, sector 70), every plat type
    printf("// EV_DoPlat line 195: type, amount, rtn, hash, tics till done, floor, ceiling, prndindex\n");
    for (int type = 0; type <= 4; type++) {
        load();
        int amount = type == raiseAndChange ? 24 : 0;
        int rtn = EV_DoPlat(&lines[195], type, amount);
        int first;
        long long h = hashsector(70, 400, &first);
        printf("[%d, %d, %d, %lldl, %d, %d, %d, %d, %d],\n", type, amount, rtn, h, first,
               sectors[70].floorheight, sectors[70].ceilingheight, sectors[70].floorpic, prndindex);
    }

    // a plat stopped and restarted
    {
        load();
        EV_DoPlat(&lines[195], perpetualRaise, 0);
        long long h = 0;
        for (int t = 1; t <= 300; t++) {
            if (t == 50) EV_StopPlat(&lines[195]);
            if (t == 120) EV_DoPlat(&lines[195], perpetualRaise, 0);
            tic();
            h += (long long)t * (sectors[70].floorheight >> 8);
        }
        printf("// perpetual plat stopped at 50, restarted at 120: hash %lldl, floor %d\n", h, sectors[70].floorheight);
    }

    // EV_DoFloor on line 308 (tag 1, sector 59), every floor type
    printf("// EV_DoFloor line 308: type, rtn, hash, tics till done, floor, ceiling, floorpic, special\n");
    for (int type = 0; type <= 12; type++) {
        if (type == donutRaise) continue;
        load();
        int rtn = EV_DoFloor(&lines[308], type);
        int first;
        long long h = hashsector(59, 700, &first);
        printf("[%d, %d, %lldl, %d, %d, %d, %d, %d],\n", type, rtn, h, first,
               sectors[59].floorheight, sectors[59].ceilingheight, sectors[59].floorpic, sectors[59].special);
    }

    // EV_BuildStairs on line 308
    for (int type = 0; type <= 1; type++) {
        load();
        int rtn = EV_BuildStairs(&lines[308], type);
        int first;
        long long h = hashsector(59, 300, &first);
        int moving = 0;
        for (int i = 0; i < numsectors; i++) if (sectors[i].specialdata) moving++;
        printf("// EV_BuildStairs %d: rtn %d hash %lldl done %d floor %d still moving %d\n", type, rtn, h, first, sectors[59].floorheight, moving);
    }

    // EV_DoCeiling on line 308, every ceiling type
    printf("// EV_DoCeiling line 308: type, rtn, hash, tics till done, floor, ceiling\n");
    for (int type = 0; type <= 5; type++) {
        load();
        int rtn = EV_DoCeiling(&lines[308], type);
        int first;
        long long h = hashsector(59, 600, &first);
        printf("[%d, %d, %lldl, %d, %d, %d],\n", type, rtn, h, first, sectors[59].floorheight, sectors[59].ceilingheight);
    }

    // a crusher stopped and restarted
    {
        load();
        EV_DoCeiling(&lines[308], crushAndRaise);
        long long h = 0;
        for (int t = 1; t <= 300; t++) {
            if (t == 40) EV_CeilingCrushStop(&lines[308]);
            if (t == 90) EV_DoCeiling(&lines[308], crushAndRaise);
            tic();
            h += (long long)t * (sectors[59].ceilingheight >> 8);
        }
        printf("// crusher stopped at 40, restarted at 90: hash %lldl, ceiling %d\n", h, sectors[59].ceilingheight);
    }

    // P_SpawnSpecials with the random index at 0, then 200 tics of lights,
    // flat/texture animation and the scrolling lines
    {
        load();
        totalsecret = 0;
        P_SpawnSpecials();
        printf("// spawnspecials: totalsecret %d numlinespecials %d prndindex %d\n", totalsecret, numlinespecials, prndindex);
        int ls[] = { 40, 44, 45, 72 };
        long long h = 0;
        printf("// lights: tic, sector 40, 44, 45, 72\n");
        for (int t = 1; t <= 200; t++) {
            tic();
            for (int k = 0; k < 4; k++) h += (long long)t * (k + 1) * sectors[ls[k]].lightlevel;
            if (t <= 2 || t % 25 == 0)
                printf("[%d, %d, %d, %d, %d],\n", t, sectors[40].lightlevel, sectors[44].lightlevel,
                       sectors[45].lightlevel, sectors[72].lightlevel);
        }
        int nuk = R_FlatNumForName("NUKAGE1"), sla = R_TextureNumForName("SLADRIP1");
        printf("// light hash %lldl prndindex %d; flattranslation[%d..] %d %d %d; texturetranslation[%d..] %d %d %d; side 486 offset %d\n",
               h, prndindex, nuk, flattranslation[nuk], flattranslation[nuk + 1], flattranslation[nuk + 2],
               sla, texturetranslation[sla], texturetranslation[sla + 1], texturetranslation[sla + 2],
               sides[lines[352].sidenum[0]].textureoffset);
    }

    // the light functions on their own, from the same random index
    {
        load();
        prndindex = 17;
        P_SpawnLightFlash(&sectors[40]);
        P_SpawnStrobeFlash(&sectors[72], FASTDARK, 0);
        P_SpawnFireFlicker(&sectors[59]);
        P_SpawnGlowingLight(&sectors[13]);
        long long h = 0;
        for (int t = 1; t <= 150; t++) {
            tic();
            h += (long long)t * (sectors[40].lightlevel + 2 * sectors[72].lightlevel + 3 * sectors[59].lightlevel + 4 * sectors[13].lightlevel);
        }
        printf("// lights from prndindex 17: hash %lldl prndindex %d levels %d %d %d %d\n", h, prndindex,
               sectors[40].lightlevel, sectors[72].lightlevel, sectors[59].lightlevel, sectors[13].lightlevel);
        EV_TurnTagLightsOff(&lines[308]);
        printf("// EV_TurnTagLightsOff 308: sector 59 %d\n", sectors[59].lightlevel);
        EV_LightTurnOn(&lines[308], 0);
        printf("// EV_LightTurnOn 308 0: sector 59 %d\n", sectors[59].lightlevel);
        EV_StartLightStrobing(&lines[195]);
        for (int t = 0; t < 40; t++) tic();
        printf("// EV_StartLightStrobing 195, 40 tics: sector 70 %d prndindex %d\n", sectors[70].lightlevel, prndindex);
    }

    // the exit switch on line 330 as a button, and back after BUTTONTIME
    {
        load();
        int s = lines[330].sidenum[0];
        printf("// switch side %d: top %d mid %d bottom %d\n", s, sides[s].toptexture, sides[s].midtexture, sides[s].bottomtexture);
        P_ChangeSwitchTexture(&lines[330], 1);
        printf("// pressed: top %d mid %d bottom %d special %d\n", sides[s].toptexture, sides[s].midtexture, sides[s].bottomtexture, lines[330].special);
        for (int t = 0; t < BUTTONTIME - 1; t++) P_UpdateSpecials();
        printf("// after %d: mid %d\n", BUTTONTIME - 1, sides[s].midtexture);
        P_UpdateSpecials();
        printf("// after %d: mid %d\n", BUTTONTIME, sides[s].midtexture);
        P_ChangeSwitchTexture(&lines[330], 0);
        printf("// used: mid %d special %d\n", sides[s].midtexture, lines[330].special);
    }
    return 0;
}
