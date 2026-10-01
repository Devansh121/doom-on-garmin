// Reference values for test/RMainTest.mc. The functions below are copied
// from linuxdoom-1.10 r_main.c / m_fixed.c with only the struct access
// changed; build against the original tables.c:
//
//   gcc -I ~/src/DOOM/linuxdoom-1.10 rmain_ref.c ~/src/DOOM/linuxdoom-1.10/tables.c -o rmain_ref
//   ./rmain_ref < nodes.txt   (nodes.txt: count, then 14 shorts per node)
#include <stdio.h>
#include <stdlib.h>
#include "tables.h"

#define MAXINT 0x7fffffff
#define MININT ((int)0x80000000)
#define FIELDOFVIEW 2048
#define NF_SUBSECTOR 0x8000

typedef struct { fixed_t x, y, dx, dy; fixed_t bbox[2][4]; unsigned short children[2]; } node_t;
node_t nodes[1024];
int numnodes;

fixed_t viewx, viewy;
int viewwidth = 160, centerx = 80;
fixed_t centerxfrac = 80 << FRACBITS;
int viewangletox[FINEANGLES / 2];
angle_t xtoviewangle[161];
angle_t clipangle;

fixed_t FixedMul(fixed_t a, fixed_t b) { return ((long long) a * (long long) b) >> FRACBITS; }
fixed_t FixedDiv2(fixed_t a, fixed_t b) { long long c = ((long long)a<<16) / ((long long)b); return (fixed_t) c; }
fixed_t FixedDiv(fixed_t a, fixed_t b) { if ((abs(a)>>14) >= abs(b)) return (a^b)<0 ? MININT : MAXINT; return FixedDiv2(a,b); }

int R_PointOnSide(fixed_t x, fixed_t y, node_t* node) {
    fixed_t dx, dy, left, right;
    if (!node->dx) { if (x <= node->x) return node->dy > 0; return node->dy < 0; }
    if (!node->dy) { if (y <= node->y) return node->dx < 0; return node->dx > 0; }
    dx = (x - node->x); dy = (y - node->y);
    if ((node->dy ^ node->dx ^ dx ^ dy) & 0x80000000) { if ((node->dy ^ dx) & 0x80000000) return 1; return 0; }
    left = FixedMul(node->dy >> FRACBITS, dx);
    right = FixedMul(dy, node->dx >> FRACBITS);
    if (right < left) return 0;
    return 1;
}

angle_t R_PointToAngle(fixed_t x, fixed_t y) {
    x -= viewx; y -= viewy;
    if ((!x) && (!y)) return 0;
    if (x >= 0) {
        if (y >= 0) { if (x > y) return tantoangle[SlopeDiv(y, x)]; else return ANG90 - 1 - tantoangle[SlopeDiv(x, y)]; }
        else { y = -y; if (x > y) return -tantoangle[SlopeDiv(y, x)]; else return ANG270 + tantoangle[SlopeDiv(x, y)]; }
    } else {
        x = -x;
        if (y >= 0) { if (x > y) return ANG180 - 1 - tantoangle[SlopeDiv(y, x)]; else return ANG90 + tantoangle[SlopeDiv(x, y)]; }
        else { y = -y; if (x > y) return ANG180 + tantoangle[SlopeDiv(y, x)]; else return ANG270 - 1 - tantoangle[SlopeDiv(x, y)]; }
    }
    return 0;
}

fixed_t R_PointToDist(fixed_t x, fixed_t y) {
    int angle; fixed_t dx, dy, temp;
    dx = abs(x - viewx); dy = abs(y - viewy);
    if (dy > dx) { temp = dx; dx = dy; dy = temp; }
    angle = (tantoangle[FixedDiv(dy, dx) >> DBITS] + ANG90) >> ANGLETOFINESHIFT;
    return FixedDiv(dx, finesine[angle]);
}

void R_InitTextureMapping(void) {
    int i, x, t; fixed_t focallength;
    focallength = FixedDiv(centerxfrac, finetangent[FINEANGLES / 4 + FIELDOFVIEW / 2]);
    for (i = 0; i < FINEANGLES / 2; i++) {
        if (finetangent[i] > FRACUNIT * 2) t = -1;
        else if (finetangent[i] < -FRACUNIT * 2) t = viewwidth + 1;
        else {
            t = FixedMul(finetangent[i], focallength);
            t = (centerxfrac - t + FRACUNIT - 1) >> FRACBITS;
            if (t < -1) t = -1; else if (t > viewwidth + 1) t = viewwidth + 1;
        }
        viewangletox[i] = t;
    }
    for (x = 0; x <= viewwidth; x++) { i = 0; while (viewangletox[i] > x) i++; xtoviewangle[x] = (i << ANGLETOFINESHIFT) - ANG90; }
    for (i = 0; i < FINEANGLES / 2; i++) {
        if (viewangletox[i] == -1) viewangletox[i] = 0;
        else if (viewangletox[i] == viewwidth + 1) viewangletox[i] = viewwidth;
    }
    clipangle = xtoviewangle[0];
}

int R_PointInSubsector(fixed_t x, fixed_t y) {
    int nodenum = numnodes - 1;
    while (!(nodenum & NF_SUBSECTOR)) nodenum = nodes[nodenum].children[R_PointOnSide(x, y, &nodes[nodenum])];
    return nodenum & ~NF_SUBSECTOR;
}

int main(void) {
    scanf("%d", &numnodes);
    for (int i = 0; i < numnodes; i++) {
        int v[14];
        for (int k = 0; k < 14; k++) scanf("%d", &v[k]);
        nodes[i].x = v[0] << FRACBITS; nodes[i].y = v[1] << FRACBITS;
        nodes[i].dx = v[2] << FRACBITS; nodes[i].dy = v[3] << FRACBITS;
        nodes[i].children[0] = v[12]; nodes[i].children[1] = v[13];
    }
    R_InitTextureMapping();
    long long sum = 0;
    for (int i = 0; i < FINEANGLES / 2; i++) sum += viewangletox[i] * (long long)(i + 1);
    printf("viewangletox weighted sum %lld\n", sum);
    printf("viewangletox[1000] %d [2048] %d [3000] %d\n", viewangletox[1000], viewangletox[2048], viewangletox[3000]);
    printf("xtoviewangle[0] %d [40] %d [80] %d [120] %d [160] %d\n", (int)xtoviewangle[0], (int)xtoviewangle[40],
           (int)xtoviewangle[80], (int)xtoviewangle[120], (int)xtoviewangle[160]);

    int pts[][4] = {
        {1056, -3616, 1200, -3500}, {1056, -3616, 900, -3700}, {0, 0, -5, 300}, {0, 0, -300, -2},
        {100, 100, 100, 100}, {-2000, 500, 3000, -1500}, {1056, -3616, 1056, -3000}, {1000, 1000, 999, -2000}
    };
    for (int i = 0; i < 8; i++) {
        viewx = pts[i][0] << FRACBITS; viewy = pts[i][1] << FRACBITS;
        fixed_t x = pts[i][2] << FRACBITS, y = pts[i][3] << FRACBITS;
        printf("        [%d, %d, %d, %d, %d, %d],\n", pts[i][0], pts[i][1], pts[i][2], pts[i][3],
               (int)R_PointToAngle(x, y), (x == viewx && y == viewy) ? 0 : R_PointToDist(x, y));
    }
    int ss[][2] = {{1056, -3616}, {1500, -3200}, {3000, -3000}, {2000, -2500}, {-200, 200}};
    for (int i = 0; i < 5; i++)
        printf("        [%d, %d, %d],\n", ss[i][0], ss[i][1], R_PointInSubsector(ss[i][0] << FRACBITS, ss[i][1] << FRACBITS));
}
