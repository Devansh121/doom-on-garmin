// Reference vissprites and sprite clipping for test/RThingsTest.mc.
// Builds on rsegs_ref.c (walls, drawsegs and their sprite clip lists)
// and adds R_InitSpriteDefs / R_InstallSpriteLump, R_ProjectSprite,
// R_AddSprites, R_SortVisSprites and the clipping half of R_DrawSprite
// from linuxdoom-1.10 r_things.c, R_InitSpriteLumps from r_data.c and
// R_PointInSubsector / R_PointOnSegSide from r_main.c. Only the struct
// access is changed; things get spawned the way P_SpawnMapThing places
// them, sector links included.
//
//   python3 test/dump_e1m1.py > e1m1.txt
//   python3 test/dump_things.py doom1.wad > things.txt
//   gcc -I ~/src/DOOM/linuxdoom-1.10 rthings_ref.c ~/src/DOOM/linuxdoom-1.10/tables.c -o rthings_ref
//   cat e1m1.txt things.txt | ./rthings_ref
#define NO_MAIN
#define ADDSPRITES_HOOK R_AddSprites
#include "rsegs_ref.c"

#define MINZ (FRACUNIT*4)
#define BASEYCENTER 100
#define MAXVISSPRITES 128
#define FF_FULLBRIGHT 0x8000
#define FF_FRAMEMASK 0x7fff
#define MF_SHADOW 0x40000
#define MF_NOSECTOR 8
#define MF_SPAWNCEILING 256
typedef unsigned char byte;
fixed_t viewcos, viewsin;
#define I_Error(...) (printf(__VA_ARGS__), exit(1))

typedef struct mobj_s {
    fixed_t x, y, z; angle_t angle; int sprite, frame, flags;
    struct mobj_s* snext;
} mobj_t;
mobj_t mobjs[512]; int nummobjs;
// sector_t fields the dump doesn't have, by sector number
int sector_validcount[512];
mobj_t* sector_thinglist[512];
int validcount = 1;

typedef struct { boolean rotate; short lump[8]; unsigned char flip[8]; } spriteframe_t;
typedef struct { int numframes; spriteframe_t* spriteframes; } spritedef_t;

typedef struct vissprite_s {
    struct vissprite_s* prev; struct vissprite_s* next;
    int x1, x2; fixed_t gx, gy, gz, gzt, startfrac, scale, xiscale, texturemid;
    int patch; lighttable_t* colormap; int mobjflags;
} vissprite_t;

char lumpnames[1024][9]; int numlumps;
int firstspritelump = 0, lastspritelump, numspritelumps;
fixed_t spritewidth[1024], spriteoffset[1024], spritetopoffset[1024];
char* sprnames_[256];
int modifiedgame = 0;

// ---- r_main.c ----
int R_PointOnSegSide(fixed_t x, fixed_t y, seg_t* line) {
    fixed_t lx, ly, ldx, ldy, dx, dy, left, right;
    lx = line->v1->x; ly = line->v1->y;
    ldx = line->v2->x - lx; ldy = line->v2->y - ly;
    if (!ldx) { if (x <= lx) return ldy > 0; return ldy < 0; }
    if (!ldy) { if (y <= ly) return ldx < 0; return ldx > 0; }
    dx = (x - lx); dy = (y - ly);
    if ((ldy ^ ldx ^ dx ^ dy) & 0x80000000) { if ((ldy ^ dx) & 0x80000000) return 1; return 0; }
    left = FixedMul(ldy >> FRACBITS, dx);
    right = FixedMul(dy, ldx >> FRACBITS);
    if (right < left) return 0;
    return 1;
}

subsector_t* R_PointInSubsector(fixed_t x, fixed_t y) {
    node_t* node; int side; int nodenum;
    if (!numnodes) return subsectors;
    nodenum = numnodes - 1;
    while (!(nodenum & NF_SUBSECTOR)) {
        node = &nodes[nodenum];
        side = R_PointOnSide(x, y, node);
        nodenum = node->children[side];
    }
    return &subsectors[nodenum & ~NF_SUBSECTOR];
}

// ---- r_things.c ----
fixed_t pspritescale, pspriteiscale;
lighttable_t** spritelights;
spritedef_t* sprites;
int numsprites;
spriteframe_t sprtemp[29];
int maxframe;
char* spritename;

void R_InstallSpriteLump(int lump, unsigned frame, unsigned rotation, boolean flipped) {
    int r;
    if (frame >= 29 || rotation > 8) I_Error("R_InstallSpriteLump: Bad frame characters in lump %i", lump);
    if ((int)frame > maxframe) maxframe = frame;
    if (rotation == 0) {
        // the lump should be used for all rotations
        if (sprtemp[frame].rotate == false) I_Error("R_InitSprites: Sprite %s frame %c has multip rot=0 lump", spritename, 'A' + frame);
        if (sprtemp[frame].rotate == true) I_Error("R_InitSprites: Sprite %s frame %c has rotations and a rot=0 lump", spritename, 'A' + frame);
        sprtemp[frame].rotate = false;
        for (r = 0; r < 8; r++) { sprtemp[frame].lump[r] = lump - firstspritelump; sprtemp[frame].flip[r] = (byte)flipped; }
        return;
    }
    // the lump is only used for one rotation
    if (sprtemp[frame].rotate == false) I_Error("R_InitSprites: Sprite %s frame %c has rotations and a rot=0 lump", spritename, 'A' + frame);
    sprtemp[frame].rotate = true;
    // make 0 based
    rotation--;
    if (sprtemp[frame].lump[rotation] != -1) I_Error("R_InitSprites: Sprite %s : %c : %c has two lumps mapped to it", spritename, 'A' + frame, '1' + rotation);
    sprtemp[frame].lump[rotation] = lump - firstspritelump;
    sprtemp[frame].flip[rotation] = (byte)flipped;
}

void R_InitSpriteDefs(char** namelist) {
    char** check; int i, l, intname, frame, rotation, start, end, patched;
    check = namelist;
    while (*check != NULL) check++;
    numsprites = check - namelist;
    if (!numsprites) return;
    sprites = malloc(numsprites * sizeof(*sprites));
    start = firstspritelump - 1;
    end = lastspritelump + 1;
    for (i = 0; i < numsprites; i++) {
        spritename = namelist[i];
        memset(sprtemp, -1, sizeof(sprtemp));
        maxframe = -1;
        intname = *(int*)namelist[i];
        for (l = start + 1; l < end; l++) {
            if (*(int*)lumpnames[l] == intname) {
                frame = lumpnames[l][4] - 'A';
                rotation = lumpnames[l][5] - '0';
                patched = l;
                R_InstallSpriteLump(patched, frame, rotation, false);
                if (lumpnames[l][6]) {
                    frame = lumpnames[l][6] - 'A';
                    rotation = lumpnames[l][7] - '0';
                    R_InstallSpriteLump(l, frame, rotation, true);
                }
            }
        }
        if (maxframe == -1) { sprites[i].numframes = 0; continue; }
        maxframe++;
        for (frame = 0; frame < maxframe; frame++) {
            switch ((int)sprtemp[frame].rotate) {
            case -1: I_Error("R_InitSprites: No patches found for %s frame %c", namelist[i], frame + 'A'); break;
            case 0: break;
            case 1:
                for (rotation = 0; rotation < 8; rotation++)
                    if (sprtemp[frame].lump[rotation] == -1) I_Error("R_InitSprites: Sprite %s frame %c is missing rotations", namelist[i], frame + 'A');
                break;
            }
        }
        sprites[i].numframes = maxframe;
        sprites[i].spriteframes = malloc(maxframe * sizeof(spriteframe_t));
        memcpy(sprites[i].spriteframes, sprtemp, maxframe * sizeof(spriteframe_t));
    }
}

vissprite_t vissprites[MAXVISSPRITES];
vissprite_t* vissprite_p;
vissprite_t overflowsprite;

void R_ClearSprites(void) { vissprite_p = vissprites; }

vissprite_t* R_NewVisSprite(void) {
    if (vissprite_p == &vissprites[MAXVISSPRITES]) return &overflowsprite;
    vissprite_p++;
    return vissprite_p - 1;
}

void R_ProjectSprite(mobj_t* thing) {
    fixed_t tr_x, tr_y, gxt, gyt, tx, tz, xscale; int x1, x2;
    spritedef_t* sprdef; spriteframe_t* sprframe; int lump; unsigned rot; boolean flip;
    int index; vissprite_t* vis; angle_t ang; fixed_t iscale;

    tr_x = thing->x - viewx;
    tr_y = thing->y - viewy;
    gxt = FixedMul(tr_x, viewcos);
    gyt = -FixedMul(tr_y, viewsin);
    tz = gxt - gyt;
    // thing is behind view plane?
    if (tz < MINZ) return;
    xscale = FixedDiv(projection, tz);
    gxt = -FixedMul(tr_x, viewsin);
    gyt = FixedMul(tr_y, viewcos);
    tx = -(gyt + gxt);
    // too far off the side?
    if (abs(tx) > (tz << 2)) return;

    if ((unsigned)thing->sprite >= numsprites) I_Error("R_ProjectSprite: invalid sprite number %i ", thing->sprite);
    sprdef = &sprites[thing->sprite];
    if ((thing->frame & FF_FRAMEMASK) >= sprdef->numframes) I_Error("R_ProjectSprite: invalid sprite frame %i : %i ", thing->sprite, thing->frame);
    sprframe = &sprdef->spriteframes[thing->frame & FF_FRAMEMASK];

    if (sprframe->rotate) {
        // choose a different rotation based on player view
        ang = R_PointToAngle(thing->x, thing->y);
        rot = (ang - thing->angle + (unsigned)(ANG45 / 2) * 9) >> 29;
        lump = sprframe->lump[rot];
        flip = (boolean)sprframe->flip[rot];
    } else {
        // use single rotation for all views
        lump = sprframe->lump[0];
        flip = (boolean)sprframe->flip[0];
    }

    // calculate edges of the shape
    tx -= spriteoffset[lump];
    x1 = (centerxfrac + FixedMul(tx, xscale)) >> FRACBITS;
    // off the right side?
    if (x1 > viewwidth) return;
    tx += spritewidth[lump];
    x2 = ((centerxfrac + FixedMul(tx, xscale)) >> FRACBITS) - 1;
    // off the left side
    if (x2 < 0) return;

    // store information in a vissprite
    vis = R_NewVisSprite();
    vis->mobjflags = thing->flags;
    vis->scale = xscale << detailshift;
    vis->gx = thing->x;
    vis->gy = thing->y;
    vis->gz = thing->z;
    vis->gzt = thing->z + spritetopoffset[lump];
    vis->texturemid = vis->gzt - viewz;
    vis->x1 = x1 < 0 ? 0 : x1;
    vis->x2 = x2 >= viewwidth ? viewwidth - 1 : x2;
    iscale = FixedDiv(FRACUNIT, xscale);
    if (flip) { vis->startfrac = spritewidth[lump] - 1; vis->xiscale = -iscale; }
    else { vis->startfrac = 0; vis->xiscale = iscale; }
    if (vis->x1 > x1) vis->startfrac += vis->xiscale * (vis->x1 - x1);
    vis->patch = lump;

    // get light level
    if (thing->flags & MF_SHADOW) vis->colormap = NULL;
    else if (fixedcolormap) vis->colormap = colormaps + fixedcolormap * 256;
    else if (thing->frame & FF_FULLBRIGHT) vis->colormap = colormaps;
    else {
        // diminished light
        index = xscale >> (LIGHTSCALESHIFT - detailshift);
        if (index >= MAXLIGHTSCALE) index = MAXLIGHTSCALE - 1;
        vis->colormap = spritelights[index];
    }
}

void R_AddSprites(sector_t* sec) {
    mobj_t* thing; int lightnum;
    if (sector_validcount[sec - sectors] == validcount) return;
    sector_validcount[sec - sectors] = validcount;
    lightnum = (sec->lightlevel >> LIGHTSEGSHIFT) + extralight;
    if (lightnum < 0) spritelights = scalelight[0];
    else if (lightnum >= LIGHTLEVELS) spritelights = scalelight[LIGHTLEVELS - 1];
    else spritelights = scalelight[lightnum];
    // Handle all things in sector.
    for (thing = sector_thinglist[sec - sectors]; thing; thing = thing->snext) R_ProjectSprite(thing);
}

vissprite_t vsprsortedhead;

void R_SortVisSprites(void) {
    int i, count; vissprite_t* ds; vissprite_t* best = 0; vissprite_t unsorted; fixed_t bestscale;
    count = vissprite_p - vissprites;
    unsorted.next = unsorted.prev = &unsorted;
    if (!count) return;
    for (ds = vissprites; ds < vissprite_p; ds++) { ds->next = ds + 1; ds->prev = ds - 1; }
    vissprites[0].prev = &unsorted;
    unsorted.next = &vissprites[0];
    (vissprite_p - 1)->next = &unsorted;
    unsorted.prev = vissprite_p - 1;
    vsprsortedhead.next = vsprsortedhead.prev = &vsprsortedhead;
    for (i = 0; i < count; i++) {
        bestscale = MAXINT;
        for (ds = unsorted.next; ds != &unsorted; ds = ds->next) {
            if (ds->scale < bestscale) { bestscale = ds->scale; best = ds; }
        }
        best->next->prev = best->prev;
        best->prev->next = best->next;
        best->next = &vsprsortedhead;
        best->prev = vsprsortedhead.prev;
        vsprsortedhead.prev->next = best;
        vsprsortedhead.prev = best;
    }
}

// R_DrawSprite up to the R_DrawVisSprite call, which is left to the caller.
short clipbot[SCREENWIDTH];
short cliptop[SCREENWIDTH];
void R_DrawSprite(vissprite_t* spr) {
    drawseg_t* ds; int x, r1, r2; fixed_t scale, lowscale; int silhouette;
    for (x = spr->x1; x <= spr->x2; x++) clipbot[x] = cliptop[x] = -2;
    for (ds = ds_p - 1; ds >= drawsegs; ds--) {
        if (ds->x1 > spr->x2 || ds->x2 < spr->x1 || (!ds->silhouette && !ds->maskedtexturecol)) continue;
        r1 = ds->x1 < spr->x1 ? spr->x1 : ds->x1;
        r2 = ds->x2 > spr->x2 ? spr->x2 : ds->x2;
        if (ds->scale1 > ds->scale2) { lowscale = ds->scale2; scale = ds->scale1; }
        else { lowscale = ds->scale1; scale = ds->scale2; }
        if (scale < spr->scale || (lowscale < spr->scale && !R_PointOnSegSide(spr->gx, spr->gy, ds->curline))) {
            // (masked mid textures are not drawn here)
            continue;
        }
        silhouette = ds->silhouette;
        if (spr->gz >= ds->bsilheight) silhouette &= ~SIL_BOTTOM;
        if (spr->gzt <= ds->tsilheight) silhouette &= ~SIL_TOP;
        if (silhouette == 1) {
            for (x = r1; x <= r2; x++) if (clipbot[x] == -2) clipbot[x] = ds->sprbottomclip[x];
        } else if (silhouette == 2) {
            for (x = r1; x <= r2; x++) if (cliptop[x] == -2) cliptop[x] = ds->sprtopclip[x];
        } else if (silhouette == 3) {
            for (x = r1; x <= r2; x++) {
                if (clipbot[x] == -2) clipbot[x] = ds->sprbottomclip[x];
                if (cliptop[x] == -2) cliptop[x] = ds->sprtopclip[x];
            }
        }
    }
    for (x = spr->x1; x <= spr->x2; x++) {
        if (clipbot[x] == -2) clipbot[x] = viewheight;
        if (cliptop[x] == -2) cliptop[x] = -1;
    }
}

long long h;
void hv(long long v) { h = (h * 31 + ((v % 1000000007LL) + 1000000007LL)) % 1000000007LL; }

int main(int argc, char** argv) {
    load_e1m1();
    init_render();

    // lumps and R_InitSpriteLumps
    scanf("%d", &numlumps);
    for (int i = 0; i < numlumps; i++) {
        int w, l, t;
        memset(lumpnames[i], 0, 9);
        scanf("%8s %d %d %d", lumpnames[i], &w, &l, &t);
        spritewidth[i] = w << FRACBITS; spriteoffset[i] = l << FRACBITS; spritetopoffset[i] = t << FRACBITS;
    }
    lastspritelump = numlumps - 1;
    numspritelumps = numlumps;
    int n; scanf("%d", &n);
    for (int i = 0; i < n; i++) { sprnames_[i] = calloc(8, 1); scanf("%4s", sprnames_[i]); }
    sprnames_[n] = NULL;
    R_InitSpriteDefs(sprnames_);

    // P_SpawnMapThing / P_SpawnMobj / P_SetThingPosition
    scanf("%d", &nummobjs);
    for (int i = 0; i < nummobjs; i++) {
        int x, y, angle, sprite, frame, flags, ceil, height;
        scanf("%d %d %d %d %d %d %d %d", &x, &y, &angle, &sprite, &frame, &flags, &ceil, &height);
        mobj_t* mo = &mobjs[i];
        mo->x = x << FRACBITS; mo->y = y << FRACBITS;
        mo->angle = ANG45 * (angle / 45);
        mo->sprite = sprite; mo->frame = frame; mo->flags = flags;
        sector_t* sec = R_PointInSubsector(mo->x, mo->y)->sector;
        mo->z = ceil ? sec->ceilingheight - height : sec->floorheight;
        if (!(flags & MF_NOSECTOR)) { mo->snext = sector_thinglist[sec - sectors]; sector_thinglist[sec - sectors] = mo; }
    }

    int views[][4] = {
        {1056, -3616, 90, 41}, {1056, -3616, 0, 41}, {1500, -3200, 135, 41},
        {3000, -3000, 180, 41}, {2000, -2500, 270, 41}, {1056, -3400, 45, 41},
        {1200, -2600, 0, 41}, {2900, -3300, 120, 41}, {1500, -2200, 300, 41},
        {900, -3400, 90, 41}, {500, -3300, 0, 33}
    };
    int nviews = sizeof(views) / sizeof(views[0]);
    for (int v = 0; v < nviews; v++) {
        viewx = views[v][0] << FRACBITS; viewy = views[v][1] << FRACBITS; viewz = views[v][3] << FRACBITS;
        viewangle = (angle_t)(ANG45 / 45) * views[v][2];
        viewsin = finesine[viewangle >> ANGLETOFINESHIFT];
        viewcos = finesine[FINEANGLES / 4 + (viewangle >> ANGLETOFINESHIFT)];  // finecosine
        validcount++;
        clear_frame();
        R_ClearSprites();
        R_RenderBSPNode(numnodes - 1);
        int count = vissprite_p - vissprites;
        h = 0;
        for (vissprite_t* s = vissprites; s < vissprite_p; s++) {
            int cm = s->colormap ? (s->colormap - colormaps) / 256 : -1;
            long long f[] = { s->x1, s->x2, s->scale, s->texturemid, s->patch, s->xiscale, s->startfrac, s->gz, s->gzt, cm };
            for (int k = 0; k < 10; k++) hv(f[k]);
        }
        long long projhash = h;
        R_SortVisSprites();
        h = 0;
        long long cliph = 0; int partial = -1;
        for (vissprite_t* s = vsprsortedhead.next; count && s != &vsprsortedhead; s = s->next) {
            hv(s - vissprites);
            R_DrawSprite(s);
            long long hh = h; h = cliph;
            int closed = 0, open = 0;
            for (int x = s->x1; x <= s->x2; x++) {
                hv(cliptop[x]); hv(clipbot[x]);
                if (clipbot[x] <= cliptop[x] + 1) closed++;
                else if (cliptop[x] == -1 && clipbot[x] == viewheight) open++;
            }
            cliph = h; h = hh;
            // a sprite partly hidden behind a wall edge
            if (partial < 0 && closed > 0 && open > 0) partial = s - vissprites;
        }
        printf("        [%d, %d, %d, %d, %lldl, %lldl, %lldl, %d],\n", views[v][0], views[v][1], views[v][2],
               count, projhash, h, cliph, partial);
        if (partial >= 0) {
            vissprite_t* s = &vissprites[partial];
            R_DrawSprite(s);
            printf("        // vissprite %d, x %d..%d, cliptop / clipbot:\n        [", partial, s->x1, s->x2);
            for (int x = s->x1; x <= s->x2; x++) printf("%s%d, %d", x > s->x1 ? ", " : "", cliptop[x], clipbot[x]);
            printf("],\n");
        }
        if (argc > 1) {
            for (vissprite_t* s = vissprites; s < vissprite_p; s++)
                printf("   vis %d: x %d..%d scale %d mid %d patch %d xiscale %d cm %d\n", (int)(s - vissprites), s->x1, s->x2,
                       s->scale, s->texturemid, s->patch, s->xiscale, s->colormap ? (int)(s->colormap - colormaps) / 256 : -1);
        }
    }
}
