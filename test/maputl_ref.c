// Reference values for test/MapUtlTest.mc. The functions between the
// "copied" markers are verbatim from linuxdoom-1.10 p_maputl.c; the
// structs below keep just the fields they use, so no struct access had
// to change. Lines are loaded the same way P_LoadLineDefs does it.
// No tables are needed, only FixedMul/FixedDiv. From the repo root:
//
//   python3 -c "import json;[print(len(d),*d) for n in ['vertexes','linedefs','sidedefs','sectors','blockmap'] for d in [json.load(open(f'generated/resources/e1m1_{n}.json'))]]" > e1m1.txt
//   gcc test/maputl_ref.c -o maputl_ref && ./maputl_ref < e1m1.txt
#include <stdio.h>
#include <stdlib.h>

typedef int fixed_t;
typedef int boolean;
enum { false, true };
#define FRACBITS 16
#define FRACUNIT (1 << FRACBITS)
#define MAXINT 0x7fffffff
#define MININT ((int)0x80000000)

enum { BOXTOP, BOXBOTTOM, BOXLEFT, BOXRIGHT };
typedef enum { ST_HORIZONTAL, ST_VERTICAL, ST_POSITIVE, ST_NEGATIVE } slopetype_t;

typedef struct { fixed_t x, y; } vertex_t;
typedef struct { fixed_t floorheight, ceilingheight; } sector_t;
typedef struct { sector_t* sector; } side_t;
typedef struct {
    vertex_t* v1; vertex_t* v2;
    fixed_t dx, dy;
    short sidenum[2];
    fixed_t bbox[4];
    slopetype_t slopetype;
    sector_t* frontsector; sector_t* backsector;
    int validcount;
} line_t;
typedef struct { fixed_t x, y, dx, dy; } divline_t;

vertex_t vertexes[2048]; int numvertexes;
line_t lines[2048]; int numlines;
side_t sides[2048]; int numsides;
sector_t sectors[512]; int numsectors;
short blockmaplump[65536]; short* blockmap;
int bmapwidth, bmapheight;
fixed_t bmaporgx, bmaporgy;
int validcount = 1;

fixed_t FixedMul(fixed_t a, fixed_t b) { return ((long long) a * (long long) b) >> FRACBITS; }
fixed_t FixedDiv2(fixed_t a, fixed_t b) { long long c = ((long long)a<<16) / ((long long)b); return (fixed_t) c; }
fixed_t FixedDiv(fixed_t a, fixed_t b) { if ((abs(a)>>14) >= abs(b)) return (a^b)<0 ? MININT : MAXINT; return FixedDiv2(a,b); }

// ---- copied from p_maputl.c ----
//
// P_AproxDistance
// Gives an estimation of distance (not exact)
//

fixed_t
P_AproxDistance
( fixed_t	dx,
  fixed_t	dy )
{
    dx = abs(dx);
    dy = abs(dy);
    if (dx < dy)
	return dx+dy-(dx>>1);
    return dx+dy-(dy>>1);
}


//
// P_PointOnLineSide
// Returns 0 or 1
//
int
P_PointOnLineSide
( fixed_t	x,
  fixed_t	y,
  line_t*	line )
{
    fixed_t	dx;
    fixed_t	dy;
    fixed_t	left;
    fixed_t	right;
	
    if (!line->dx)
    {
	if (x <= line->v1->x)
	    return line->dy > 0;
	
	return line->dy < 0;
    }
    if (!line->dy)
    {
	if (y <= line->v1->y)
	    return line->dx < 0;
	
	return line->dx > 0;
    }
	
    dx = (x - line->v1->x);
    dy = (y - line->v1->y);
	
    left = FixedMul ( line->dy>>FRACBITS , dx );
    right = FixedMul ( dy , line->dx>>FRACBITS );
	
    if (right < left)
	return 0;		// front side
    return 1;			// back side
}



//
// P_BoxOnLineSide
// Considers the line to be infinite
// Returns side 0 or 1, -1 if box crosses the line.
//
int
P_BoxOnLineSide
( fixed_t*	tmbox,
  line_t*	ld )
{
    int		p1;
    int		p2;
	
    switch (ld->slopetype)
    {
      case ST_HORIZONTAL:
	p1 = tmbox[BOXTOP] > ld->v1->y;
	p2 = tmbox[BOXBOTTOM] > ld->v1->y;
	if (ld->dx < 0)
	{
	    p1 ^= 1;
	    p2 ^= 1;
	}
	break;
	
      case ST_VERTICAL:
	p1 = tmbox[BOXRIGHT] < ld->v1->x;
	p2 = tmbox[BOXLEFT] < ld->v1->x;
	if (ld->dy < 0)
	{
	    p1 ^= 1;
	    p2 ^= 1;
	}
	break;
	
      case ST_POSITIVE:
	p1 = P_PointOnLineSide (tmbox[BOXLEFT], tmbox[BOXTOP], ld);
	p2 = P_PointOnLineSide (tmbox[BOXRIGHT], tmbox[BOXBOTTOM], ld);
	break;
	
      case ST_NEGATIVE:
	p1 = P_PointOnLineSide (tmbox[BOXRIGHT], tmbox[BOXTOP], ld);
	p2 = P_PointOnLineSide (tmbox[BOXLEFT], tmbox[BOXBOTTOM], ld);
	break;
    }

    if (p1 == p2)
	return p1;
    return -1;
}


//
// P_PointOnDivlineSide
// Returns 0 or 1.
//
int
P_PointOnDivlineSide
( fixed_t	x,
  fixed_t	y,
  divline_t*	line )
{
    fixed_t	dx;
    fixed_t	dy;
    fixed_t	left;
    fixed_t	right;
	
    if (!line->dx)
    {
	if (x <= line->x)
	    return line->dy > 0;
	
	return line->dy < 0;
    }
    if (!line->dy)
    {
	if (y <= line->y)
	    return line->dx < 0;

	return line->dx > 0;
    }
	
    dx = (x - line->x);
    dy = (y - line->y);
	
    // try to quickly decide by looking at sign bits
    if ( (line->dy ^ line->dx ^ dx ^ dy)&0x80000000 )
    {
	if ( (line->dy ^ dx) & 0x80000000 )
	    return 1;		// (left is negative)
	return 0;
    }
	
    left = FixedMul ( line->dy>>8, dx>>8 );
    right = FixedMul ( dy>>8 , line->dx>>8 );
	
    if (right < left)
	return 0;		// front side
    return 1;			// back side
}



//
// P_MakeDivline
//
void
P_MakeDivline
( line_t*	li,
  divline_t*	dl )
{
    dl->x = li->v1->x;
    dl->y = li->v1->y;
    dl->dx = li->dx;
    dl->dy = li->dy;
}



//
// P_InterceptVector
// Returns the fractional intercept point
// along the first divline.
// This is only called by the addthings
// and addlines traversers.
//
fixed_t
P_InterceptVector
( divline_t*	v2,
  divline_t*	v1 )
{
#if 1
    fixed_t	frac;
    fixed_t	num;
    fixed_t	den;
	
    den = FixedMul (v1->dy>>8,v2->dx) - FixedMul(v1->dx>>8,v2->dy);

    if (den == 0)
	return 0;
    //	I_Error ("P_InterceptVector: parallel");
    
    num =
	FixedMul ( (v1->x - v2->x)>>8 ,v1->dy )
	+FixedMul ( (v2->y - v1->y)>>8, v1->dx );

    frac = FixedDiv (num , den);

    return frac;
#else	// UNUSED, float debug.
    float	frac;
    float	num;
    float	den;
    float	v1x;
    float	v1y;
    float	v1dx;
    float	v1dy;
    float	v2x;
    float	v2y;
    float	v2dx;
    float	v2dy;

    v1x = (float)v1->x/FRACUNIT;
    v1y = (float)v1->y/FRACUNIT;
    v1dx = (float)v1->dx/FRACUNIT;
    v1dy = (float)v1->dy/FRACUNIT;
    v2x = (float)v2->x/FRACUNIT;
    v2y = (float)v2->y/FRACUNIT;
    v2dx = (float)v2->dx/FRACUNIT;
    v2dy = (float)v2->dy/FRACUNIT;
	
    den = v1dy*v2dx - v1dx*v2dy;

    if (den == 0)
	return 0;	// parallel
    
    num = (v1x - v2x)*v1dy + (v2y - v1y)*v1dx;
    frac = num / den;

    return frac*FRACUNIT;
#endif
}


//
// P_LineOpening
// Sets opentop and openbottom to the window
// through a two sided line.
// OPTIMIZE: keep this precalculated
//
fixed_t opentop;
fixed_t openbottom;
fixed_t openrange;
fixed_t	lowfloor;


void P_LineOpening (line_t* linedef)
{
    sector_t*	front;
    sector_t*	back;
	
    if (linedef->sidenum[1] == -1)
    {
	// single sided line
	openrange = 0;
	return;
    }
	 
    front = linedef->frontsector;
    back = linedef->backsector;
	
    if (front->ceilingheight < back->ceilingheight)
	opentop = front->ceilingheight;
    else
	opentop = back->ceilingheight;

    if (front->floorheight > back->floorheight)
    {
	openbottom = front->floorheight;
	lowfloor = back->floorheight;
    }
    else
    {
	openbottom = back->floorheight;
	lowfloor = front->floorheight;
    }
	
    openrange = opentop - openbottom;
}

//
// P_BlockLinesIterator
// The validcount flags are used to avoid checking lines
// that are marked in multiple mapblocks,
// so increment validcount before the first call
// to P_BlockLinesIterator, then make one or more calls
// to it.
//
boolean
P_BlockLinesIterator
( int			x,
  int			y,
  boolean(*func)(line_t*) )
{
    int			offset;
    short*		list;
    line_t*		ld;
	
    if (x<0
	|| y<0
	|| x>=bmapwidth
	|| y>=bmapheight)
    {
	return true;
    }
    
    offset = y*bmapwidth+x;
	
    offset = *(blockmap+offset);

    for ( list = blockmaplump+offset ; *list != -1 ; list++)
    {
	ld = &lines[*list];

	if (ld->validcount == validcount)
	    continue; 	// line has already been checked

	ld->validcount = validcount;
		
	if ( !func(ld) )
	    return false;
    }
    return true;	// everything was checked
}
// ---- end of copied code ----

int rd(void) { int v; if (scanf("%d", &v) != 1) { fprintf(stderr, "short input\n"); exit(1); } return v; }

void load(void) {
    int i, n, v[7];
    numvertexes = rd();
    numvertexes /= 2;
    for (i = 0; i < numvertexes; i++) { vertexes[i].x = rd() << FRACBITS; vertexes[i].y = rd() << FRACBITS; }
    // linedefs come before sidedefs in the dump, keep them for later
    static int mld[2048 * 7];
    n = rd();
    for (i = 0; i < n; i++) mld[i] = rd();
    numlines = n / 7;
    static int msd[4096 * 6];
    n = rd();
    for (i = 0; i < n; i++) msd[i] = rd();
    numsides = n / 6;
    n = rd();
    numsectors = n / 7;
    for (i = 0; i < numsectors; i++) {
        for (int k = 0; k < 7; k++) v[k] = rd();
        sectors[i].floorheight = v[0] << FRACBITS;
        sectors[i].ceilingheight = v[1] << FRACBITS;
    }
    for (i = 0; i < numsides; i++) sides[i].sector = &sectors[msd[i * 6 + 5]];
    for (i = 0; i < numlines; i++) {
        int* m = &mld[i * 7];
        line_t* ld = &lines[i];
        vertex_t* v1 = ld->v1 = &vertexes[m[0]];
        vertex_t* v2 = ld->v2 = &vertexes[m[1]];
        ld->dx = v2->x - v1->x;
        ld->dy = v2->y - v1->y;
        if (!ld->dx) ld->slopetype = ST_VERTICAL;
        else if (!ld->dy) ld->slopetype = ST_HORIZONTAL;
        else ld->slopetype = FixedDiv(ld->dy, ld->dx) > 0 ? ST_POSITIVE : ST_NEGATIVE;
        ld->sidenum[0] = m[5];
        ld->sidenum[1] = m[6];
        ld->frontsector = ld->sidenum[0] != -1 ? sides[ld->sidenum[0]].sector : 0;
        ld->backsector = ld->sidenum[1] != -1 ? sides[ld->sidenum[1]].sector : 0;
    }
    n = rd();
    for (i = 0; i < n; i++) blockmaplump[i] = rd();
    blockmap = blockmaplump + 4;
    bmaporgx = blockmaplump[0] << FRACBITS;
    bmaporgy = blockmaplump[1] << FRACBITS;
    bmapwidth = blockmaplump[2];
    bmapheight = blockmaplump[3];
}

// PIT_* stand-in for P_BlockLinesIterator: counts visits and sums the
// visited line numbers weighted by visit order; stops after stopafter.
int visits, stopafter;
long long visitsum;
boolean PIT_Count(line_t* ld) {
    visits++;
    visitsum += (long long)visits * (ld - lines);
    return visits != stopafter;
}

int pick[8];

int main(void) {
    int i, j;
    load();
    printf("// %d lines, blockmap %dx%d\n", numlines, bmapwidth, bmapheight);

    // P_AproxDistance edge cases
    int ad[][2] = {{0, 0}, {3 * FRACUNIT, 4 * FRACUNIT}, {-3 * FRACUNIT, 4 * FRACUNIT}, {4 * FRACUNIT, -3 * FRACUNIT},
                   {FRACUNIT, FRACUNIT}, {1, 0}, {0, -1}, {3, 3}, {-7, 5},
                   {MAXINT, 0}, {MAXINT, MAXINT}, {MININT, 0}, {MININT, 5 * FRACUNIT}, {0x40000000, 0x40000000}};
    printf("    var aprox = [\n");
    for (i = 0; i < (int)(sizeof ad / sizeof ad[0]); i++)
        printf("        [%d, %d, %d],\n", ad[i][0], ad[i][1], P_AproxDistance(ad[i][0], ad[i][1]));
    printf("    ];\n");

    // a line for every slopetype, one pointing each way
    for (i = 0; i < 8; i++) pick[i] = -1;
    for (i = 0; i < numlines; i++) {
        line_t* ld = &lines[i];
        int neg = ld->slopetype == ST_VERTICAL ? ld->dy < 0 : ld->dx < 0;
        int s = ld->slopetype * 2 + neg;
        if (pick[s] == -1) pick[s] = i;
    }

    printf("    var lineside = [\n        // line, slopetype, x, y, P_PointOnLineSide, P_PointOnDivlineSide\n");
    for (i = 0; i < 8; i++) {
        line_t* ld = &lines[pick[i]];
        fixed_t mx = ld->v1->x + ld->dx / 2, my = ld->v1->y + ld->dy / 2;
        fixed_t pts[][2] = {
            {ld->v1->x, ld->v1->y}, {ld->v2->x, ld->v2->y}, {mx, my},
            {mx + (ld->dy >> 4), my - (ld->dx >> 4)}, {mx - (ld->dy >> 4), my + (ld->dx >> 4)},
            {mx + 1, my}, {mx, my - 1}, {mx - FRACUNIT / 2, my + FRACUNIT / 3},
            {ld->v1->x + 3000 * FRACUNIT, ld->v1->y - 2000 * FRACUNIT}, {ld->v1->x - 5000 * FRACUNIT, ld->v1->y + 7 * FRACUNIT}
        };
        divline_t dl;
        P_MakeDivline(ld, &dl);
        for (j = 0; j < 10; j++)
            printf("        [%d, %d, %d, %d, %d, %d],\n", pick[i], ld->slopetype, pts[j][0], pts[j][1],
                   P_PointOnLineSide(pts[j][0], pts[j][1], ld), P_PointOnDivlineSide(pts[j][0], pts[j][1], &dl));
    }
    printf("    ];\n");

    printf("    var boxside = [\n        // line, top, bottom, left, right, P_BoxOnLineSide\n");
    for (i = 0; i < 8; i++) {
        line_t* ld = &lines[pick[i]];
        fixed_t mx = ld->v1->x + ld->dx / 2, my = ld->v1->y + ld->dy / 2;
        fixed_t r = 16 * FRACUNIT, off = 64 * FRACUNIT;
        fixed_t c[][2] = {{mx, my}, {mx + off, my + off}, {mx - off, my - off}, {mx + off, my - off}, {mx - off, my + off}};
        for (j = 0; j < 5; j++) {
            fixed_t box[4];
            box[BOXTOP] = c[j][1] + r; box[BOXBOTTOM] = c[j][1] - r;
            box[BOXLEFT] = c[j][0] - r; box[BOXRIGHT] = c[j][0] + r;
            printf("        [%d, %d, %d, %d, %d, %d],\n", pick[i], box[BOXTOP], box[BOXBOTTOM], box[BOXLEFT], box[BOXRIGHT],
                   P_BoxOnLineSide(box, ld));
        }
        // a box whose edge sits exactly on v1
        fixed_t box[4] = {ld->v1->y, ld->v1->y - r, ld->v1->x, ld->v1->x + r};
        printf("        [%d, %d, %d, %d, %d, %d],\n", pick[i], box[BOXTOP], box[BOXBOTTOM], box[BOXLEFT], box[BOXRIGHT],
               P_BoxOnLineSide(box, ld));
    }
    printf("    ];\n");

    // P_InterceptVector for every pair of picked lines (same and parallel
    // ones give den == 0), and a few traces from the player start
    printf("    var intercept = [\n        // v2 line, v1 line, frac\n");
    for (i = 0; i < 8; i++)
        for (j = 0; j < 8; j++) {
            divline_t a, b;
            P_MakeDivline(&lines[pick[i]], &a);
            P_MakeDivline(&lines[pick[j]], &b);
            printf("        [%d, %d, %d],\n", pick[i], pick[j], P_InterceptVector(&a, &b));
        }
    printf("    ];\n");
    printf("    var traces = [\n        // trace x, y, dx, dy, line, frac\n");
    int tr[][4] = {{1056, -3616, 1000, 0}, {1056, -3616, -300, 800}, {1056, -3616, 2047, -2047}, {0, 0, 1, 1}};
    for (i = 0; i < 4; i++)
        for (j = 0; j < 8; j += 3) {
            divline_t t = {tr[i][0] << FRACBITS, tr[i][1] << FRACBITS, tr[i][2] << FRACBITS, tr[i][3] << FRACBITS}, l;
            P_MakeDivline(&lines[pick[j]], &l);
            printf("        [%d, %d, %d, %d, %d, %d],\n", t.x, t.y, t.dx, t.dy, pick[j], P_InterceptVector(&t, &l));
        }
    printf("    ];\n");

    // P_LineOpening: a few two sided lines with the floor higher on
    // either side, one single sided line, and a running checksum over all
    // lines (single sided lines leave opentop & co from the last call)
    printf("    var opening = [\n        // line, openrange, opentop, openbottom, lowfloor (front floor higher?)\n");
    int shown = 0, ff = 0, bf = 0;
    for (i = 0; i < numlines && shown < 6; i++) {
        line_t* ld = &lines[i];
        if (ld->sidenum[1] == -1) continue;
        int fhigher = ld->frontsector->floorheight > ld->backsector->floorheight;
        int same = ld->frontsector->floorheight == ld->backsector->floorheight;
        if (same && shown) continue;
        if (fhigher && ff >= 3) continue;
        if (!fhigher && !same && bf >= 3) continue;
        if (fhigher) ff++; else if (!same) bf++;
        P_LineOpening(ld);
        printf("        [%d, %d, %d, %d, %d],  // %s\n", i, openrange, opentop, openbottom, lowfloor,
               same ? "same" : fhigher ? "front" : "back");
        shown++;
    }
    P_LineOpening(&lines[0]);
    printf("        [0, %d, %d, %d, %d],  // single sided\n", openrange, opentop, openbottom, lowfloor);
    printf("    ];\n");
    long long osum = 0;
    opentop = openbottom = openrange = lowfloor = 0;
    for (i = 0; i < numlines; i++) {
        P_LineOpening(&lines[i]);
        osum += (long long)(i + 1) * ((openrange >> 8) + 3 * (opentop >> 8) + 5 * (openbottom >> 8) + 7 * (lowfloor >> 8));
    }
    printf("    opening checksum %lld\n", osum);

    // P_BlockLinesIterator
    int bestx = 0, besty = 0, best = 0;
    for (j = 0; j < bmapheight; j++)
        for (i = 0; i < bmapwidth; i++) {
            int n = 0;
            for (short* l = blockmaplump + blockmap[j * bmapwidth + i]; *l != -1; l++) n++;
            if (n > best) { best = n; bestx = i; besty = j; }
        }
    printf("    // busiest block %d,%d with %d entries\n", bestx, besty, best);
    int blk[][3] = {{0, 0, 0}, {bestx, besty, 0}, {bestx, besty, 3}, {17, 18, 0}, {12, 13, 0}, {30, 2, 0},
                    {-1, 0, 0}, {0, -1, 0}, {bmapwidth, 0, 0}, {0, bmapheight, 0}, {bmapwidth - 1, bmapheight - 1, 0}};
    printf("    var blocks = [\n        // x, y, stopafter, result, visits, visitsum\n");
    for (i = 0; i < (int)(sizeof blk / sizeof blk[0]); i++) {
        validcount++;
        visits = 0; visitsum = 0; stopafter = blk[i][2];
        boolean r = P_BlockLinesIterator(blk[i][0], blk[i][1], PIT_Count);
        printf("        [%d, %d, %d, %d, %d, %lld],\n", blk[i][0], blk[i][1], blk[i][2], r, visits, visitsum);
    }
    printf("    ];\n");
    // one validcount over a 5x5 area: lines in several blocks count once
    validcount++;
    visits = 0; visitsum = 0; stopafter = 0;
    for (j = besty - 2; j <= besty + 2; j++)
        for (i = bestx - 2; i <= bestx + 2; i++)
            P_BlockLinesIterator(i, j, PIT_Count);
    printf("    5x5 around busiest: visits %d visitsum %lld\n", visits, visitsum);
    // whole map, one validcount
    validcount++;
    visits = 0; visitsum = 0;
    for (j = 0; j < bmapheight; j++)
        for (i = 0; i < bmapwidth; i++)
            P_BlockLinesIterator(i, j, PIT_Count);
    printf("    whole map: visits %d visitsum %lld\n", visits, visitsum);
    return 0;
}
