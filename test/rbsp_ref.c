// Reference wall ranges for test/RBspTest.mc. The r_bsp.c functions below
// are copied from linuxdoom-1.10 with only the struct definitions trimmed;
// R_StoreWallRange just records what it's given.
//
//   python3 test/dump_e1m1.py > e1m1.txt
//   gcc -I ~/src/DOOM/linuxdoom-1.10 rbsp_ref.c ~/src/DOOM/linuxdoom-1.10/tables.c -o rbsp_ref
//   ./rbsp_ref < e1m1.txt
#include <stdio.h>
#include <stdlib.h>
#include "tables.h"

#define MAXINT 0x7fffffff
#define MININT ((int)0x80000000)
#define FIELDOFVIEW 2048
#define NF_SUBSECTOR 0x8000
enum { BOXTOP, BOXBOTTOM, BOXLEFT, BOXRIGHT };
typedef int boolean;
#define true 1
#define false 0

typedef struct { fixed_t x, y; } vertex_t;
typedef struct { fixed_t floorheight, ceilingheight; short floorpic, ceilingpic, lightlevel; } sector_t;
typedef struct { short midtexture; } side_t;
typedef struct { vertex_t *v1, *v2; side_t *sidedef; sector_t *frontsector, *backsector; } seg_t;
typedef struct { sector_t *sector; short numlines, firstline; } subsector_t;
typedef struct { fixed_t x, y, dx, dy; fixed_t bbox[2][4]; unsigned short children[2]; } node_t;

vertex_t vertexes[2048]; sector_t sectors[512]; side_t segsides[4096]; seg_t segs[4096];
subsector_t subsectors[2048]; node_t nodes[2048];
int numvertexes, numsectors, numsegs, numsubsectors, numnodes;

fixed_t viewx, viewy, viewz; angle_t viewangle;
int viewwidth = 160, centerx = 80;
fixed_t centerxfrac = 80 << FRACBITS;
int viewangletox[FINEANGLES / 2];
angle_t xtoviewangle[161];
angle_t clipangle;
angle_t rw_angle1;
int skyflatnum = 54;

seg_t* curline; sector_t* frontsector; sector_t* backsector;
long long tracesum; int tracecount; int tracefirst[15];

void R_StoreWallRange(int start, int stop) {
    int line = curline - segs;
    if (tracecount < 5) { tracefirst[tracecount * 3] = line; tracefirst[tracecount * 3 + 1] = start; tracefirst[tracecount * 3 + 2] = stop; }
    tracecount++;
    tracesum += (long long)tracecount * (line * 100000LL + start * 1000 + stop);
}

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

// ---- r_bsp.c ----

typedef struct { int first; int last; } cliprange_t;
#define MAXSEGS 32
cliprange_t* newend;
cliprange_t solidsegs[MAXSEGS];

void R_ClipSolidWallSegment(int first, int last) {
    cliprange_t* next; cliprange_t* start;
    start = solidsegs;
    while (start->last < first - 1) start++;
    if (first < start->first) {
        if (last < start->first - 1) {
            R_StoreWallRange(first, last);
            next = newend; newend++;
            while (next != start) { *next = *(next - 1); next--; }
            next->first = first; next->last = last;
            return;
        }
        R_StoreWallRange(first, start->first - 1);
        start->first = first;
    }
    if (last <= start->last) return;
    next = start;
    while (last >= (next + 1)->first - 1) {
        R_StoreWallRange(next->last + 1, (next + 1)->first - 1);
        next++;
        if (last <= next->last) { start->last = next->last; goto crunch; }
    }
    R_StoreWallRange(next->last + 1, last);
    start->last = last;
  crunch:
    if (next == start) return;
    while (next++ != newend) *++start = *next;
    newend = start + 1;
}

void R_ClipPassWallSegment(int first, int last) {
    cliprange_t* start;
    start = solidsegs;
    while (start->last < first - 1) start++;
    if (first < start->first) {
        if (last < start->first - 1) { R_StoreWallRange(first, last); return; }
        R_StoreWallRange(first, start->first - 1);
    }
    if (last <= start->last) return;
    while (last >= (start + 1)->first - 1) {
        R_StoreWallRange(start->last + 1, (start + 1)->first - 1);
        start++;
        if (last <= start->last) return;
    }
    R_StoreWallRange(start->last + 1, last);
}

void R_ClearClipSegs(void) {
    solidsegs[0].first = -0x7fffffff; solidsegs[0].last = -1;
    solidsegs[1].first = viewwidth; solidsegs[1].last = 0x7fffffff;
    newend = solidsegs + 2;
}

void R_AddLine(seg_t* line) {
    int x1, x2; angle_t angle1, angle2, span, tspan;
    curline = line;
    angle1 = R_PointToAngle(line->v1->x, line->v1->y);
    angle2 = R_PointToAngle(line->v2->x, line->v2->y);
    span = angle1 - angle2;
    if (span >= ANG180) return;
    rw_angle1 = angle1;
    angle1 -= viewangle; angle2 -= viewangle;
    tspan = angle1 + clipangle;
    if (tspan > 2 * clipangle) { tspan -= 2 * clipangle; if (tspan >= span) return; angle1 = clipangle; }
    tspan = clipangle - angle2;
    if (tspan > 2 * clipangle) { tspan -= 2 * clipangle; if (tspan >= span) return; angle2 = -clipangle; }
    angle1 = (angle1 + ANG90) >> ANGLETOFINESHIFT;
    angle2 = (angle2 + ANG90) >> ANGLETOFINESHIFT;
    x1 = viewangletox[angle1]; x2 = viewangletox[angle2];
    if (x1 == x2) return;
    backsector = line->backsector;
    if (!backsector) goto clipsolid;
    if (backsector->ceilingheight <= frontsector->floorheight || backsector->floorheight >= frontsector->ceilingheight) goto clipsolid;
    if (backsector->ceilingheight != frontsector->ceilingheight || backsector->floorheight != frontsector->floorheight) goto clippass;
    if (backsector->ceilingpic == frontsector->ceilingpic && backsector->floorpic == frontsector->floorpic
        && backsector->lightlevel == frontsector->lightlevel && curline->sidedef->midtexture == 0) return;
  clippass:
    R_ClipPassWallSegment(x1, x2 - 1);
    return;
  clipsolid:
    R_ClipSolidWallSegment(x1, x2 - 1);
}

int checkcoord[12][4] = { {3,0,2,1}, {3,0,2,0}, {3,1,2,0}, {0}, {2,0,2,1}, {0,0,0,0}, {3,1,3,0}, {0}, {2,0,3,1}, {2,1,3,1}, {2,1,3,0} };

boolean R_CheckBBox(fixed_t* bspcoord) {
    int boxx, boxy, boxpos; fixed_t x1, y1, x2, y2; angle_t angle1, angle2, span, tspan;
    cliprange_t* start; int sx1, sx2;
    if (viewx <= bspcoord[BOXLEFT]) boxx = 0; else if (viewx < bspcoord[BOXRIGHT]) boxx = 1; else boxx = 2;
    if (viewy >= bspcoord[BOXTOP]) boxy = 0; else if (viewy > bspcoord[BOXBOTTOM]) boxy = 1; else boxy = 2;
    boxpos = (boxy << 2) + boxx;
    if (boxpos == 5) return true;
    x1 = bspcoord[checkcoord[boxpos][0]]; y1 = bspcoord[checkcoord[boxpos][1]];
    x2 = bspcoord[checkcoord[boxpos][2]]; y2 = bspcoord[checkcoord[boxpos][3]];
    angle1 = R_PointToAngle(x1, y1) - viewangle;
    angle2 = R_PointToAngle(x2, y2) - viewangle;
    span = angle1 - angle2;
    if (span >= ANG180) return true;
    tspan = angle1 + clipangle;
    if (tspan > 2 * clipangle) { tspan -= 2 * clipangle; if (tspan >= span) return false; angle1 = clipangle; }
    tspan = clipangle - angle2;
    if (tspan > 2 * clipangle) { tspan -= 2 * clipangle; if (tspan >= span) return false; angle2 = -clipangle; }
    angle1 = (angle1 + ANG90) >> ANGLETOFINESHIFT;
    angle2 = (angle2 + ANG90) >> ANGLETOFINESHIFT;
    sx1 = viewangletox[angle1]; sx2 = viewangletox[angle2];
    if (sx1 == sx2) return false;
    sx2--;
    start = solidsegs;
    while (start->last < sx2) start++;
    if (sx1 >= start->first && sx2 <= start->last) return false;
    return true;
}

int sscount;
void R_Subsector(int num) {
    int count; seg_t* line; subsector_t* sub;
    sscount++;
    sub = &subsectors[num];
    frontsector = sub->sector;
    count = sub->numlines;
    line = &segs[sub->firstline];
    while (count--) { R_AddLine(line); line++; }
}

void R_RenderBSPNode(int bspnum) {
    node_t* bsp; int side;
    if (bspnum & NF_SUBSECTOR) { if (bspnum == -1) R_Subsector(0); else R_Subsector(bspnum & (~NF_SUBSECTOR)); return; }
    bsp = &nodes[bspnum];
    side = R_PointOnSide(viewx, viewy, bsp);
    R_RenderBSPNode(bsp->children[side]);
    if (R_CheckBBox(bsp->bbox[side ^ 1])) R_RenderBSPNode(bsp->children[side ^ 1]);
}

int main(void) {
    int n, a, b, c, d, e;
    scanf("%d", &numvertexes);
    for (int i = 0; i < numvertexes; i++) { scanf("%d %d", &a, &b); vertexes[i].x = a << FRACBITS; vertexes[i].y = b << FRACBITS; }
    scanf("%d", &numsectors);
    for (int i = 0; i < numsectors; i++) {
        int f[7]; for (int k = 0; k < 7; k++) scanf("%d", &f[k]);
        sectors[i].floorheight = f[0] << FRACBITS; sectors[i].ceilingheight = f[1] << FRACBITS;
        sectors[i].floorpic = f[2]; sectors[i].ceilingpic = f[3]; sectors[i].lightlevel = f[4];
    }
    scanf("%d", &numsegs);
    for (int i = 0; i < numsegs; i++) {
        scanf("%d %d %d %d %d", &a, &b, &c, &d, &e);
        segs[i].v1 = &vertexes[a]; segs[i].v2 = &vertexes[b];
        segs[i].frontsector = &sectors[c]; segs[i].backsector = d < 0 ? NULL : &sectors[d];
        segsides[i].midtexture = e; segs[i].sidedef = &segsides[i];
    }
    scanf("%d", &numsubsectors);
    for (int i = 0; i < numsubsectors; i++) { scanf("%d %d %d", &a, &b, &c); subsectors[i].sector = &sectors[a]; subsectors[i].numlines = b; subsectors[i].firstline = c; }
    scanf("%d", &numnodes);
    for (int i = 0; i < numnodes; i++) {
        int v[14]; for (int k = 0; k < 14; k++) scanf("%d", &v[k]);
        nodes[i].x = v[0] << FRACBITS; nodes[i].y = v[1] << FRACBITS; nodes[i].dx = v[2] << FRACBITS; nodes[i].dy = v[3] << FRACBITS;
        for (int j = 0; j < 2; j++) { nodes[i].children[j] = v[12 + j]; for (int k = 0; k < 4; k++) nodes[i].bbox[j][k] = v[4 + j * 4 + k] << FRACBITS; }
    }
    R_InitTextureMapping();

    int views[][3] = { {1056, -3616, 90}, {1056, -3616, 0}, {1500, -3200, 135}, {3000, -3000, 180}, {2000, -2500, 270}, {-200, 200, 30} };
    for (int i = 0; i < 6; i++) {
        viewx = views[i][0] << FRACBITS; viewy = views[i][1] << FRACBITS; viewz = 41 << FRACBITS;
        viewangle = (angle_t)(ANG45 / 45) * views[i][2];
        tracesum = 0; tracecount = 0; sscount = 0;
        R_ClearClipSegs();
        R_RenderBSPNode(numnodes - 1);
        printf("        [%d, %d, %d, %d, %d, %lldl, [%d, %d, %d, %d, %d, %d]],\n", views[i][0], views[i][1], views[i][2],
               sscount, tracecount, tracesum, tracefirst[0], tracefirst[1], tracefirst[2], tracefirst[3], tracefirst[4], tracefirst[5]);
    }
}
