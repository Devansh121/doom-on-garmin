// Reference draw calls for test/RSegsTest.mc. Builds on rbsp_ref.c and
// adds R_StoreWallRange / R_RenderSegLoop from linuxdoom-1.10 r_segs.c,
// R_FindPlane from r_plane.c and the scale/light setup from r_main.c.
//
// Textures are stubbed: R_GetColumn only remembers which texture was
// asked for, and colfunc records [0, x, yl, yh, texture, colormap level].
// Plane marks record [1 or 2, x, top, bottom, picnum, height] where the C
// code writes plane->top/bottom. The drawsegs and their sprite clip
// lists (openings) are kept for rthings_ref.c, which includes this file
// with NO_MAIN defined.
//
//   python3 test/dump_e1m1.py > e1m1.txt
//   gcc -I ~/src/DOOM/linuxdoom-1.10 rsegs_ref.c ~/src/DOOM/linuxdoom-1.10/tables.c -o rsegs_ref
//   ./rsegs_ref < e1m1.txt
#define HAVE_STOREWALLRANGE
void R_Subsector_planes(void);
#define SUBSECTOR_HOOK R_Subsector_planes
#include <string.h>
#include "rbsp_ref.c"

#define LIGHTLEVELS 16
#define LIGHTSEGSHIFT 4
#define MAXLIGHTSCALE 48
#define LIGHTSCALESHIFT 12
#define NUMCOLORMAPS 32
#define DISTMAP 2
#define SCREENWIDTH 320
#define HEIGHTBITS 12
#define HEIGHTUNIT (1<<HEIGHTBITS)
#define ML_DONTPEGTOP 8
#define ML_DONTPEGBOTTOM 16
#define ML_TWOSIDED 4

typedef unsigned char lighttable_t;
lighttable_t colormaps[34 * 256];
lighttable_t* scalelight[LIGHTLEVELS][MAXLIGHTSCALE];
lighttable_t** walllights;
lighttable_t* dc_colormap;
int fixedcolormap = 0, extralight = 0, detailshift = 1, viewheight = 200;
fixed_t projection, centeryfrac = 100 << FRACBITS;
fixed_t textureheight[256];
int texturetranslation[256];

typedef struct { fixed_t height; int picnum, lightlevel; } visplane_t;
visplane_t visplanes[128];
visplane_t* lastvisplane;
visplane_t* floorplane;
visplane_t* ceilingplane;
short floorclip[SCREENWIDTH], ceilingclip[SCREENWIDTH];

// r_defs.h / r_plane.c / r_things.c: drawsegs and sprite clip lists
#define SIL_NONE 0
#define SIL_BOTTOM 1
#define SIL_TOP 2
#define SIL_BOTH 3
#define MAXDRAWSEGS 256
#define MAXOPENINGS SCREENWIDTH*64
typedef struct {
    seg_t* curline; int x1, x2; fixed_t scale1, scale2, scalestep;
    int silhouette; fixed_t bsilheight, tsilheight;
    short* sprtopclip; short* sprbottomclip; short* maskedtexturecol;
} drawseg_t;
drawseg_t drawsegs[MAXDRAWSEGS];
drawseg_t* ds_p;
short openings[MAXOPENINGS];
short* lastopening;
short negonearray[SCREENWIDTH];
short screenheightarray[SCREENWIDTH];
short* maskedtexturecol;

// trace
long long tracehash; int tracen;
void rec(int kind, int x, int yl, int yh, int a, int b) {
    int v[6] = {kind, x, yl, yh, a, b};
    for (int i = 0; i < 6; i++) tracehash = (tracehash * 31 + ((v[i] % 1000000007LL) + 1000000007LL)) % 1000000007LL;
    tracen++;
}

int dc_x, dc_yl, dc_yh, lasttex;
fixed_t dc_iscale, dc_texturemid;
unsigned char* dc_source;
unsigned char* R_GetColumn(int tex, int col) { lasttex = tex; return 0; }
void colfunc(void) { if (dc_yh - dc_yl < 0) return; rec(0, dc_x, dc_yl, dc_yh, lasttex, (dc_colormap - colormaps) / 256); }

fixed_t R_PointToDist(fixed_t x, fixed_t y) {
    int angle; fixed_t dx, dy, temp;
    dx = abs(x - viewx); dy = abs(y - viewy);
    if (dy > dx) { temp = dx; dx = dy; dy = temp; }
    angle = (tantoangle[FixedDiv(dy, dx) >> DBITS] + ANG90) >> ANGLETOFINESHIFT;
    return FixedDiv(dx, finesine[angle]);
}

// ---- r_plane.c ----
visplane_t* R_FindPlane(fixed_t height, int picnum, int lightlevel) {
    visplane_t* check;
    if (picnum == skyflatnum) { height = 0; lightlevel = 0; }
    for (check = visplanes; check < lastvisplane; check++)
        if (height == check->height && picnum == check->picnum && lightlevel == check->lightlevel) break;
    if (check < lastvisplane) return check;
    lastvisplane++;
    check->height = height; check->picnum = picnum; check->lightlevel = lightlevel;
    return check;
}

#ifdef ADDSPRITES_HOOK
void ADDSPRITES_HOOK(sector_t* sec);
#endif

void R_Subsector_planes(void) {
    if (frontsector->floorheight < viewz)
        floorplane = R_FindPlane(frontsector->floorheight, frontsector->floorpic, frontsector->lightlevel);
    else floorplane = NULL;
    if (frontsector->ceilingheight > viewz || frontsector->ceilingpic == skyflatnum)
        ceilingplane = R_FindPlane(frontsector->ceilingheight, frontsector->ceilingpic, frontsector->lightlevel);
    else ceilingplane = NULL;
#ifdef ADDSPRITES_HOOK
    ADDSPRITES_HOOK(frontsector);
#endif
}

// ---- r_segs.c ----
boolean segtextured, markfloor, markceiling, maskedtexture;
int toptexture, bottomtexture, midtexture;
angle_t rw_normalangle;
int rw_x, rw_stopx;
angle_t rw_centerangle;
fixed_t rw_offset, rw_distance, rw_scale, rw_scalestep;
fixed_t rw_midtexturemid, rw_toptexturemid, rw_bottomtexturemid;
int worldtop, worldbottom, worldhigh, worldlow;
fixed_t pixhigh, pixlow, pixhighstep, pixlowstep, topfrac, topstep, bottomfrac, bottomstep;

fixed_t R_ScaleFromGlobalAngle(angle_t visangle) {
    fixed_t scale; int anglea, angleb, sinea, sineb; fixed_t num; int den;
    anglea = ANG90 + (visangle - viewangle);
    angleb = ANG90 + (visangle - rw_normalangle);
    sinea = finesine[anglea >> ANGLETOFINESHIFT];
    sineb = finesine[angleb >> ANGLETOFINESHIFT];
    num = FixedMul(projection, sineb) << detailshift;
    den = FixedMul(rw_distance, sinea);
    if (den > num >> 16) {
        scale = FixedDiv(num, den);
        if (scale > 64 * FRACUNIT) scale = 64 * FRACUNIT; else if (scale < 256) scale = 256;
    } else scale = 64 * FRACUNIT;
    return scale;
}

void R_RenderSegLoop(void) {
    angle_t angle; unsigned index; int yl, yh, mid; fixed_t texturecolumn; int top, bottom;
    for (; rw_x < rw_stopx; rw_x++) {
        yl = (topfrac + HEIGHTUNIT - 1) >> HEIGHTBITS;
        if (yl < ceilingclip[rw_x] + 1) yl = ceilingclip[rw_x] + 1;
        if (markceiling) {
            top = ceilingclip[rw_x] + 1; bottom = yl - 1;
            if (bottom >= floorclip[rw_x]) bottom = floorclip[rw_x] - 1;
            if (top <= bottom) rec(1, rw_x, top, bottom, ceilingplane->picnum, ceilingplane->height >> 16);
        }
        yh = bottomfrac >> HEIGHTBITS;
        if (yh >= floorclip[rw_x]) yh = floorclip[rw_x] - 1;
        if (markfloor) {
            top = yh + 1; bottom = floorclip[rw_x] - 1;
            if (top <= ceilingclip[rw_x]) top = ceilingclip[rw_x] + 1;
            if (top <= bottom) rec(2, rw_x, top, bottom, floorplane->picnum, floorplane->height >> 16);
        }
        if (segtextured) {
            angle = (rw_centerangle + xtoviewangle[rw_x]) >> ANGLETOFINESHIFT;
            texturecolumn = rw_offset - FixedMul(finetangent[angle], rw_distance);
            texturecolumn >>= FRACBITS;
            index = rw_scale >> LIGHTSCALESHIFT;
            if (index >= MAXLIGHTSCALE) index = MAXLIGHTSCALE - 1;
            dc_colormap = walllights[index];
            dc_x = rw_x;
            dc_iscale = 0xffffffffu / (unsigned)rw_scale;
        }
        if (midtexture) {
            dc_yl = yl; dc_yh = yh; dc_texturemid = rw_midtexturemid;
            dc_source = R_GetColumn(midtexture, texturecolumn);
            colfunc();
            ceilingclip[rw_x] = viewheight; floorclip[rw_x] = -1;
        } else {
            if (toptexture) {
                mid = pixhigh >> HEIGHTBITS; pixhigh += pixhighstep;
                if (mid >= floorclip[rw_x]) mid = floorclip[rw_x] - 1;
                if (mid >= yl) {
                    dc_yl = yl; dc_yh = mid; dc_texturemid = rw_toptexturemid;
                    dc_source = R_GetColumn(toptexture, texturecolumn);
                    colfunc();
                    ceilingclip[rw_x] = mid;
                } else ceilingclip[rw_x] = yl - 1;
            } else { if (markceiling) ceilingclip[rw_x] = yl - 1; }
            if (bottomtexture) {
                mid = (pixlow + HEIGHTUNIT - 1) >> HEIGHTBITS; pixlow += pixlowstep;
                if (mid <= ceilingclip[rw_x]) mid = ceilingclip[rw_x] + 1;
                if (mid <= yh) {
                    dc_yl = mid; dc_yh = yh; dc_texturemid = rw_bottomtexturemid;
                    dc_source = R_GetColumn(bottomtexture, texturecolumn);
                    colfunc();
                    floorclip[rw_x] = mid;
                } else floorclip[rw_x] = yh + 1;
            } else { if (markfloor) floorclip[rw_x] = yh + 1; }
        }
        rw_scale += rw_scalestep;
        topfrac += topstep;
        bottomfrac += bottomstep;
    }
}

void R_StoreWallRange(int start, int stop) {
    fixed_t hyp, sineval; angle_t distangle, offsetangle; fixed_t vtop; int lightnum;
    if (ds_p == &drawsegs[MAXDRAWSEGS]) return;
    // the dump keeps the seg's sidedef textures on the seg itself
    struct { int midtexture, toptexture, bottomtexture; } side = {
        segsides[curline - segs].midtexture, curline->toptexture, curline->bottomtexture }, *sidedef = &side;
    rw_normalangle = curline->angle + ANG90;
    offsetangle = abs(rw_normalangle - rw_angle1);
    if (offsetangle > ANG90) offsetangle = ANG90;
    distangle = ANG90 - offsetangle;
    hyp = R_PointToDist(curline->v1->x, curline->v1->y);
    sineval = finesine[distangle >> ANGLETOFINESHIFT];
    rw_distance = FixedMul(hyp, sineval);
    ds_p->x1 = rw_x = start;
    ds_p->x2 = stop;
    ds_p->curline = curline;
    rw_stopx = stop + 1;
    ds_p->scale1 = rw_scale = R_ScaleFromGlobalAngle(viewangle + xtoviewangle[start]);
    if (stop > start) {
        ds_p->scale2 = R_ScaleFromGlobalAngle(viewangle + xtoviewangle[stop]);
        ds_p->scalestep = rw_scalestep = (ds_p->scale2 - rw_scale) / (stop - start);
    } else ds_p->scale2 = ds_p->scale1;
    worldtop = frontsector->ceilingheight - viewz;
    worldbottom = frontsector->floorheight - viewz;
    midtexture = toptexture = bottomtexture = maskedtexture = 0;
    ds_p->maskedtexturecol = NULL;
    if (!backsector) {
        midtexture = texturetranslation[sidedef->midtexture];
        markfloor = markceiling = true;
        if (curline->flags & ML_DONTPEGBOTTOM) {
            vtop = frontsector->floorheight + textureheight[sidedef->midtexture];
            rw_midtexturemid = vtop - viewz;
        } else rw_midtexturemid = worldtop;
        ds_p->silhouette = SIL_BOTH;
        ds_p->sprtopclip = screenheightarray;
        ds_p->sprbottomclip = negonearray;
        ds_p->bsilheight = MAXINT;
        ds_p->tsilheight = MININT;
    } else {
        ds_p->sprtopclip = ds_p->sprbottomclip = NULL;
        ds_p->silhouette = 0;
        if (frontsector->floorheight > backsector->floorheight) { ds_p->silhouette = SIL_BOTTOM; ds_p->bsilheight = frontsector->floorheight; }
        else if (backsector->floorheight > viewz) { ds_p->silhouette = SIL_BOTTOM; ds_p->bsilheight = MAXINT; }
        if (frontsector->ceilingheight < backsector->ceilingheight) { ds_p->silhouette |= SIL_TOP; ds_p->tsilheight = frontsector->ceilingheight; }
        else if (backsector->ceilingheight < viewz) { ds_p->silhouette |= SIL_TOP; ds_p->tsilheight = MININT; }
        if (backsector->ceilingheight <= frontsector->floorheight) { ds_p->sprbottomclip = negonearray; ds_p->bsilheight = MAXINT; ds_p->silhouette |= SIL_BOTTOM; }
        if (backsector->floorheight >= frontsector->ceilingheight) { ds_p->sprtopclip = screenheightarray; ds_p->tsilheight = MININT; ds_p->silhouette |= SIL_TOP; }
        worldhigh = backsector->ceilingheight - viewz;
        worldlow = backsector->floorheight - viewz;
        if (frontsector->ceilingpic == skyflatnum && backsector->ceilingpic == skyflatnum) worldtop = worldhigh;
        if (worldlow != worldbottom || backsector->floorpic != frontsector->floorpic || backsector->lightlevel != frontsector->lightlevel)
            markfloor = true;
        else markfloor = false;
        if (worldhigh != worldtop || backsector->ceilingpic != frontsector->ceilingpic || backsector->lightlevel != frontsector->lightlevel)
            markceiling = true;
        else markceiling = false;
        if (backsector->ceilingheight <= frontsector->floorheight || backsector->floorheight >= frontsector->ceilingheight)
            markceiling = markfloor = true;
        if (worldhigh < worldtop) toptexture = texturetranslation[sidedef->toptexture];
        if (worldlow > worldbottom) bottomtexture = texturetranslation[sidedef->bottomtexture];
        if (sidedef->midtexture) {
            maskedtexture = true;
            ds_p->maskedtexturecol = maskedtexturecol = lastopening - rw_x;
            lastopening += rw_stopx - rw_x;
        }
    }
    segtextured = midtexture | toptexture | bottomtexture | maskedtexture;
    if (segtextured) {
        offsetangle = rw_normalangle - rw_angle1;
        if (offsetangle > ANG180) offsetangle = -offsetangle;
        if (offsetangle > ANG90) offsetangle = ANG90;
        sineval = finesine[offsetangle >> ANGLETOFINESHIFT];
        rw_offset = FixedMul(hyp, sineval);
        if (rw_normalangle - rw_angle1 < ANG180) rw_offset = -rw_offset;
        rw_offset += curline->offset;
        rw_centerangle = ANG90 + viewangle - rw_normalangle;
        if (!fixedcolormap) {
            lightnum = (frontsector->lightlevel >> LIGHTSEGSHIFT) + extralight;
            if (curline->v1->y == curline->v2->y) lightnum--;
            else if (curline->v1->x == curline->v2->x) lightnum++;
            if (lightnum < 0) walllights = scalelight[0];
            else if (lightnum >= LIGHTLEVELS) walllights = scalelight[LIGHTLEVELS - 1];
            else walllights = scalelight[lightnum];
        }
    }
    if (frontsector->floorheight >= viewz) markfloor = false;
    if (frontsector->ceilingheight <= viewz && frontsector->ceilingpic != skyflatnum) markceiling = false;
    worldtop >>= 4; worldbottom >>= 4;
    topstep = -FixedMul(rw_scalestep, worldtop);
    topfrac = (centeryfrac >> 4) - FixedMul(worldtop, rw_scale);
    bottomstep = -FixedMul(rw_scalestep, worldbottom);
    bottomfrac = (centeryfrac >> 4) - FixedMul(worldbottom, rw_scale);
    if (backsector) {
        worldhigh >>= 4; worldlow >>= 4;
        if (worldhigh < worldtop) { pixhigh = (centeryfrac >> 4) - FixedMul(worldhigh, rw_scale); pixhighstep = -FixedMul(rw_scalestep, worldhigh); }
        if (worldlow > worldbottom) { pixlow = (centeryfrac >> 4) - FixedMul(worldlow, rw_scale); pixlowstep = -FixedMul(rw_scalestep, worldlow); }
    }
    R_RenderSegLoop();
    if (((ds_p->silhouette & SIL_TOP) || maskedtexture) && !ds_p->sprtopclip) {
        memcpy(lastopening, ceilingclip + start, 2 * (rw_stopx - start));
        ds_p->sprtopclip = lastopening - start;
        lastopening += rw_stopx - start;
    }
    if (((ds_p->silhouette & SIL_BOTTOM) || maskedtexture) && !ds_p->sprbottomclip) {
        memcpy(lastopening, floorclip + start, 2 * (rw_stopx - start));
        ds_p->sprbottomclip = lastopening - start;
        lastopening += rw_stopx - start;
    }
    if (maskedtexture && !(ds_p->silhouette & SIL_TOP)) { ds_p->silhouette |= SIL_TOP; ds_p->tsilheight = MININT; }
    if (maskedtexture && !(ds_p->silhouette & SIL_BOTTOM)) { ds_p->silhouette |= SIL_BOTTOM; ds_p->bsilheight = MAXINT; }
    ds_p++;
}

void init_render(void) {
    projection = centerxfrac;
    for (int i = 0; i < 256; i++) texturetranslation[i] = i;
    for (int i = 0; i < LIGHTLEVELS; i++) {
        int startmap = ((LIGHTLEVELS - 1 - i) * 2) * NUMCOLORMAPS / LIGHTLEVELS;
        for (int j = 0; j < MAXLIGHTSCALE; j++) {
            int level = startmap - j * SCREENWIDTH / (viewwidth << detailshift) / DISTMAP;
            if (level < 0) level = 0;
            if (level >= NUMCOLORMAPS) level = NUMCOLORMAPS - 1;
            scalelight[i][j] = colormaps + level * 256;
        }
    }
    for (int i = 0; i < SCREENWIDTH; i++) { negonearray[i] = -1; screenheightarray[i] = viewheight; }
}

void clear_frame(void) {
    lastvisplane = visplanes;
    lastopening = openings;
    ds_p = drawsegs;
    for (int i = 0; i < viewwidth; i++) { floorclip[i] = viewheight; ceilingclip[i] = -1; }
    R_ClearClipSegs();
}

#ifndef NO_MAIN
int main(void) {
    load_e1m1();
    init_render();
    int views[][3] = { {1056, -3616, 90}, {1056, -3616, 0}, {1500, -3200, 135}, {3000, -3000, 180}, {2000, -2500, 270} };
    for (int v = 0; v < 5; v++) {
        viewx = views[v][0] << FRACBITS; viewy = views[v][1] << FRACBITS; viewz = 41 << FRACBITS;
        viewangle = (angle_t)(ANG45 / 45) * views[v][2];
        tracehash = 0; tracen = 0;
        clear_frame();
        R_RenderBSPNode(numnodes - 1);
        printf("        [%d, %d, %d, %d, %lldl],\n", views[v][0], views[v][1], views[v][2], tracen, tracehash);
    }
}
#endif
