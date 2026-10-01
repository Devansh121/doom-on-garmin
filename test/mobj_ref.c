// Reference values for test/PMobjTest.mc. The functions between the
// "copied" markers are verbatim from linuxdoom-1.10 p_maputl.c and
// p_mobj.c; the structs below keep just the fields they use, so no
// struct access had to change. Map things are spawned with the skill
// rules of P_SpawnMapThing (copied below as SpawnThings) and linked into
// the blockmap with the blockmap half of P_SetThingPosition, numbered
// from 1 like the Monkey C thinker pool hands them out. P_TryMove is a
// stub that always succeeds. From the repo root:
//
//   python3 -c "import json;[print(len(d),*d) for d in [json.load(open(f'generated/resources/e1m1_{n}.json')) for n in ['vertexes','linedefs','sidedefs','sectors','blockmap','things']]+[json.load(open('resources/info/mobjinfo.json'))]]" > mobj.txt
//   gcc test/mobj_ref.c -o mobj_ref && ./mobj_ref < mobj.txt
#include <stdio.h>
#include <stdlib.h>

typedef int fixed_t;
typedef int boolean;
enum { false, true };
#define FRACBITS 16
#define FRACUNIT (1 << FRACBITS)
#define MAXINT 0x7fffffff
#define MININT ((int)0x80000000)

#define MAPBLOCKUNITS	128
#define MAPBLOCKSIZE	(MAPBLOCKUNITS*FRACUNIT)
#define MAPBLOCKSHIFT	(FRACBITS+7)
#define MAPBTOFRAC		(MAPBLOCKSHIFT-FRACBITS)
#define MAXMOVE		(30*FRACUNIT)
#define MAXINTERCEPTS	128
#define PT_ADDLINES		1
#define PT_ADDTHINGS	2
#define PT_EARLYOUT		4

#define MF_SOLID 2
#define MF_NOBLOCKMAP 16
#define MF_MISSILE 0x10000
#define MF_CORPSE 0x100000
#define MF_SKULLFLY 0x1000000
#define MF_COUNTKILL 0x400000
#define CF_NOMOMENTUM 4
#define S_PLAY 149
#define S_PLAY_RUN1 150

typedef enum { ST_HORIZONTAL, ST_VERTICAL, ST_POSITIVE, ST_NEGATIVE } slopetype_t;

typedef struct { fixed_t x, y; } vertex_t;
typedef struct { fixed_t floorheight, ceilingheight; int ceilingpic; } sector_t;
typedef struct { sector_t* sector; } side_t;
typedef struct { sector_t* sector; } subsector_t;
typedef struct {
    vertex_t* v1; vertex_t* v2;
    fixed_t dx, dy;
    short sidenum[2];
    slopetype_t slopetype;
    sector_t* frontsector; sector_t* backsector;
    int validcount;
} line_t;
typedef struct { fixed_t x, y, dx, dy; } divline_t;

typedef struct { int sidemove, forwardmove; } ticcmd_t;
struct player_s;
typedef struct mobj_s {
    fixed_t x, y, z;
    struct mobj_s* bnext; struct mobj_s* bprev;
    subsector_t* subsector;
    fixed_t floorz;
    fixed_t radius;
    fixed_t momx, momy, momz;
    int flags;
    int state;
    struct player_s* player;
    struct { int spawnstate; } *info;
} mobj_t;
typedef struct player_s { mobj_t* mo; ticcmd_t cmd; int cheats; } player_t;

typedef struct {
    fixed_t frac;
    boolean isaline;
    union { mobj_t* thing; line_t* line; } d;
} intercept_t;
typedef boolean (*traverser_t) (intercept_t *in);

vertex_t vertexes[2048]; int numvertexes;
line_t lines[2048]; int numlines;
side_t sides[2048]; int numsides;
sector_t sectors[512]; int numsectors;
short blockmaplump[65536]; short* blockmap;
int bmapwidth, bmapheight;
fixed_t bmaporgx, bmaporgy;
mobj_t** blocklinks;
int validcount = 1;
int skyflatnum = -1;
line_t* ceilingline;
int states = 0;  // mobj->state is a state number
mobj_t mobjs[1024]; int nummobjs = 1;  // mobj numbers start at 1

fixed_t FixedMul(fixed_t a, fixed_t b) { return ((long long) a * (long long) b) >> FRACBITS; }
fixed_t FixedDiv2(fixed_t a, fixed_t b) { long long c = ((long long)a<<16) / ((long long)b); return (fixed_t) c; }
fixed_t FixedDiv(fixed_t a, fixed_t b) { if ((abs(a)>>14) >= abs(b)) return (a^b)<0 ? MININT : MAXINT; return FixedDiv2(a,b); }

// stubs for what P_XYMovement calls
boolean P_TryMove(mobj_t* thing, fixed_t x, fixed_t y) { thing->x = x; thing->y = y; return true; }
void P_SlideMove(mobj_t* mo) {}
void P_ExplodeMissile(mobj_t* mo) {}
void P_RemoveMobj(mobj_t* mo) {}
boolean P_SetMobjState(mobj_t* mo, int state) { mo->state = state; return true; }
// ---- copied from p_maputl.c ----
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
#endif
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

//
// P_BlockThingsIterator
//
boolean
P_BlockThingsIterator
( int			x,
  int			y,
  boolean(*func)(mobj_t*) )
{
    mobj_t*		mobj;
	
    if ( x<0
	 || y<0
	 || x>=bmapwidth
	 || y>=bmapheight)
    {
	return true;
    }
    

    for (mobj = blocklinks[y*bmapwidth+x] ;
	 mobj ;
	 mobj = mobj->bnext)
    {
	if (!func( mobj ) )
	    return false;
    }
    return true;
}

//
// INTERCEPT ROUTINES
//
intercept_t	intercepts[MAXINTERCEPTS];
intercept_t*	intercept_p;

divline_t 	trace;
boolean 	earlyout;
int		ptflags;

//
// PIT_AddLineIntercepts.
// Looks for lines in the given block
// that intercept the given trace
// to add to the intercepts list.
//
// A line is crossed if its endpoints
// are on opposite sides of the trace.
// Returns true if earlyout and a solid line hit.
//
boolean
PIT_AddLineIntercepts (line_t* ld)
{
    int			s1;
    int			s2;
    fixed_t		frac;
    divline_t		dl;
	
    // avoid precision problems with two routines
    if ( trace.dx > FRACUNIT*16
	 || trace.dy > FRACUNIT*16
	 || trace.dx < -FRACUNIT*16
	 || trace.dy < -FRACUNIT*16)
    {
	s1 = P_PointOnDivlineSide (ld->v1->x, ld->v1->y, &trace);
	s2 = P_PointOnDivlineSide (ld->v2->x, ld->v2->y, &trace);
    }
    else
    {
	s1 = P_PointOnLineSide (trace.x, trace.y, ld);
	s2 = P_PointOnLineSide (trace.x+trace.dx, trace.y+trace.dy, ld);
    }
    
    if (s1 == s2)
	return true;	// line isn't crossed
    
    // hit the line
    P_MakeDivline (ld, &dl);
    frac = P_InterceptVector (&trace, &dl);

    if (frac < 0)
	return true;	// behind source
	
    // try to early out the check
    if (earlyout
	&& frac < FRACUNIT
	&& !ld->backsector)
    {
	return false;	// stop checking
    }
    
	
    intercept_p->frac = frac;
    intercept_p->isaline = true;
    intercept_p->d.line = ld;
    intercept_p++;

    return true;	// continue
}



//
// PIT_AddThingIntercepts
//
boolean PIT_AddThingIntercepts (mobj_t* thing)
{
    fixed_t		x1;
    fixed_t		y1;
    fixed_t		x2;
    fixed_t		y2;
    
    int			s1;
    int			s2;
    
    boolean		tracepositive;

    divline_t		dl;
    
    fixed_t		frac;
	
    tracepositive = (trace.dx ^ trace.dy)>0;
		
    // check a corner to corner crossection for hit
    if (tracepositive)
    {
	x1 = thing->x - thing->radius;
	y1 = thing->y + thing->radius;
		
	x2 = thing->x + thing->radius;
	y2 = thing->y - thing->radius;			
    }
    else
    {
	x1 = thing->x - thing->radius;
	y1 = thing->y - thing->radius;
		
	x2 = thing->x + thing->radius;
	y2 = thing->y + thing->radius;			
    }
    
    s1 = P_PointOnDivlineSide (x1, y1, &trace);
    s2 = P_PointOnDivlineSide (x2, y2, &trace);

    if (s1 == s2)
	return true;		// line isn't crossed
	
    dl.x = x1;
    dl.y = y1;
    dl.dx = x2-x1;
    dl.dy = y2-y1;
    
    frac = P_InterceptVector (&trace, &dl);

    if (frac < 0)
	return true;		// behind source

    intercept_p->frac = frac;
    intercept_p->isaline = false;
    intercept_p->d.thing = thing;
    intercept_p++;

    return true;		// keep going
}


//
// P_TraverseIntercepts
// Returns true if the traverser function returns true
// for all lines.
// 
boolean
P_TraverseIntercepts
( traverser_t	func,
  fixed_t	maxfrac )
{
    int			count;
    fixed_t		dist;
    intercept_t*	scan;
    intercept_t*	in;
	
    count = intercept_p - intercepts;
    
    in = 0;			// shut up compiler warning
	
    while (count--)
    {
	dist = MAXINT;
	for (scan = intercepts ; scan<intercept_p ; scan++)
	{
	    if (scan->frac < dist)
	    {
		dist = scan->frac;
		in = scan;
	    }
	}
	
	if (dist > maxfrac)
	    return true;	// checked everything in range		

#if 0  // UNUSED
    {
	// don't check these yet, there may be others inserted
	in = scan = intercepts;
	for ( scan = intercepts ; scan<intercept_p ; scan++)
	    if (scan->frac > maxfrac)
		*in++ = *scan;
	intercept_p = in;
	return false;
    }
#endif

        if ( !func (in) )
	    return false;	// don't bother going farther

	in->frac = MAXINT;
    }
	
    return true;		// everything was traversed
}




//
// P_PathTraverse
// Traces a line from x1,y1 to x2,y2,
// calling the traverser function for each.
// Returns true if the traverser function returns true
// for all lines.
//
boolean
P_PathTraverse
( fixed_t		x1,
  fixed_t		y1,
  fixed_t		x2,
  fixed_t		y2,
  int			flags,
  boolean (*trav) (intercept_t *))
{
    fixed_t	xt1;
    fixed_t	yt1;
    fixed_t	xt2;
    fixed_t	yt2;
    
    fixed_t	xstep;
    fixed_t	ystep;
    
    fixed_t	partial;
    
    fixed_t	xintercept;
    fixed_t	yintercept;
    
    int		mapx;
    int		mapy;
    
    int		mapxstep;
    int		mapystep;

    int		count;
		
    earlyout = flags & PT_EARLYOUT;
		
    validcount++;
    intercept_p = intercepts;
	
    if ( ((x1-bmaporgx)&(MAPBLOCKSIZE-1)) == 0)
	x1 += FRACUNIT;	// don't side exactly on a line
    
    if ( ((y1-bmaporgy)&(MAPBLOCKSIZE-1)) == 0)
	y1 += FRACUNIT;	// don't side exactly on a line

    trace.x = x1;
    trace.y = y1;
    trace.dx = x2 - x1;
    trace.dy = y2 - y1;

    x1 -= bmaporgx;
    y1 -= bmaporgy;
    xt1 = x1>>MAPBLOCKSHIFT;
    yt1 = y1>>MAPBLOCKSHIFT;

    x2 -= bmaporgx;
    y2 -= bmaporgy;
    xt2 = x2>>MAPBLOCKSHIFT;
    yt2 = y2>>MAPBLOCKSHIFT;

    if (xt2 > xt1)
    {
	mapxstep = 1;
	partial = FRACUNIT - ((x1>>MAPBTOFRAC)&(FRACUNIT-1));
	ystep = FixedDiv (y2-y1,abs(x2-x1));
    }
    else if (xt2 < xt1)
    {
	mapxstep = -1;
	partial = (x1>>MAPBTOFRAC)&(FRACUNIT-1);
	ystep = FixedDiv (y2-y1,abs(x2-x1));
    }
    else
    {
	mapxstep = 0;
	partial = FRACUNIT;
	ystep = 256*FRACUNIT;
    }	

    yintercept = (y1>>MAPBTOFRAC) + FixedMul (partial, ystep);

	
    if (yt2 > yt1)
    {
	mapystep = 1;
	partial = FRACUNIT - ((y1>>MAPBTOFRAC)&(FRACUNIT-1));
	xstep = FixedDiv (x2-x1,abs(y2-y1));
    }
    else if (yt2 < yt1)
    {
	mapystep = -1;
	partial = (y1>>MAPBTOFRAC)&(FRACUNIT-1);
	xstep = FixedDiv (x2-x1,abs(y2-y1));
    }
    else
    {
	mapystep = 0;
	partial = FRACUNIT;
	xstep = 256*FRACUNIT;
    }	
    xintercept = (x1>>MAPBTOFRAC) + FixedMul (partial, xstep);
    
    // Step through map blocks.
    // Count is present to prevent a round off error
    // from skipping the break.
    mapx = xt1;
    mapy = yt1;
	
    for (count = 0 ; count < 64 ; count++)
    {
	if (flags & PT_ADDLINES)
	{
	    if (!P_BlockLinesIterator (mapx, mapy,PIT_AddLineIntercepts))
		return false;	// early out
	}
	
	if (flags & PT_ADDTHINGS)
	{
	    if (!P_BlockThingsIterator (mapx, mapy,PIT_AddThingIntercepts))
		return false;	// early out
	}
		
	if (mapx == xt2
	    && mapy == yt2)
	{
	    break;
	}
	
	if ( (yintercept >> FRACBITS) == mapy)
	{
	    yintercept += ystep;
	    mapx += mapxstep;
	}
	else if ( (xintercept >> FRACBITS) == mapx)
	{
	    xintercept += xstep;
	    mapy += mapystep;
	}
		
    }
    // go through the sorted list
    return P_TraverseIntercepts ( trav, FRACUNIT );
}

// ---- copied from p_mobj.c ----
//
// P_XYMovement  
//
#define STOPSPEED		0x1000
#define FRICTION		0xe800

void P_XYMovement (mobj_t* mo) 
{ 	
    fixed_t 	ptryx;
    fixed_t	ptryy;
    player_t*	player;
    fixed_t	xmove;
    fixed_t	ymove;
			
    if (!mo->momx && !mo->momy)
    {
	if (mo->flags & MF_SKULLFLY)
	{
	    // the skull slammed into something
	    mo->flags &= ~MF_SKULLFLY;
	    mo->momx = mo->momy = mo->momz = 0;

	    P_SetMobjState (mo, mo->info->spawnstate);
	}
	return;
    }
	
    player = mo->player;
		
    if (mo->momx > MAXMOVE)
	mo->momx = MAXMOVE;
    else if (mo->momx < -MAXMOVE)
	mo->momx = -MAXMOVE;

    if (mo->momy > MAXMOVE)
	mo->momy = MAXMOVE;
    else if (mo->momy < -MAXMOVE)
	mo->momy = -MAXMOVE;
		
    xmove = mo->momx;
    ymove = mo->momy;
	
    do
    {
	if (xmove > MAXMOVE/2 || ymove > MAXMOVE/2)
	{
	    ptryx = mo->x + xmove/2;
	    ptryy = mo->y + ymove/2;
	    xmove >>= 1;
	    ymove >>= 1;
	}
	else
	{
	    ptryx = mo->x + xmove;
	    ptryy = mo->y + ymove;
	    xmove = ymove = 0;
	}
		
	if (!P_TryMove (mo, ptryx, ptryy))
	{
	    // blocked move
	    if (mo->player)
	    {	// try to slide along it
		P_SlideMove (mo);
	    }
	    else if (mo->flags & MF_MISSILE)
	    {
		// explode a missile
		if (ceilingline &&
		    ceilingline->backsector &&
		    ceilingline->backsector->ceilingpic == skyflatnum)
		{
		    // Hack to prevent missiles exploding
		    // against the sky.
		    // Does not handle sky floors.
		    P_RemoveMobj (mo);
		    return;
		}
		P_ExplodeMissile (mo);
	    }
	    else
		mo->momx = mo->momy = 0;
	}
    } while (xmove || ymove);
    
    // slow down
    if (player && player->cheats & CF_NOMOMENTUM)
    {
	// debug option for no sliding at all
	mo->momx = mo->momy = 0;
	return;
    }

    if (mo->flags & (MF_MISSILE | MF_SKULLFLY) )
	return; 	// no friction for missiles ever
		
    if (mo->z > mo->floorz)
	return;		// no friction when airborne

    if (mo->flags & MF_CORPSE)
    {
	// do not stop sliding
	//  if halfway off a step with some momentum
	if (mo->momx > FRACUNIT/4
	    || mo->momx < -FRACUNIT/4
	    || mo->momy > FRACUNIT/4
	    || mo->momy < -FRACUNIT/4)
	{
	    if (mo->floorz != mo->subsector->sector->floorheight)
		return;
	}
    }

    if (mo->momx > -STOPSPEED
	&& mo->momx < STOPSPEED
	&& mo->momy > -STOPSPEED
	&& mo->momy < STOPSPEED
	&& (!player
	    || (player->cmd.forwardmove== 0
		&& player->cmd.sidemove == 0 ) ) )
    {
	// if in a walking frame, stop moving
	if ( player&&(unsigned)((player->mo->state - states)- S_PLAY_RUN1) < 4)
	    P_SetMobjState (player->mo, S_PLAY);
	
	mo->momx = 0;
	mo->momy = 0;
    }
    else
    {
	mo->momx = FixedMul (mo->momx, FRICTION);
	mo->momy = FixedMul (mo->momy, FRICTION);
    }
}

// ---- end of copied code ----

int rd(void) { int v; if (scanf("%d", &v) != 1) { fprintf(stderr, "short input\n"); exit(1); } return v; }

int things[4096]; int numthings;
int mobjinfo[200 * 23]; int nummobjinfo;
#define MI_DOOMEDNUM 0
#define MI_RADIUS 16
#define MI_FLAGS 21

void load(void) {
    int i, n, v[7];
    numvertexes = rd() / 2;
    for (i = 0; i < numvertexes; i++) { vertexes[i].x = rd() << FRACBITS; vertexes[i].y = rd() << FRACBITS; }
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
    blocklinks = calloc(bmapwidth * bmapheight, sizeof(*blocklinks));
    n = rd();
    for (i = 0; i < n; i++) things[i] = rd();
    numthings = n / 5;
    n = rd();
    for (i = 0; i < n; i++) mobjinfo[i] = rd();
    nummobjinfo = n / 23;
}

// The single player, sk_medium filtering of P_SpawnMapThing (player 1
// only, deathmatch starts, multiplayer things and other skills
// skipped), then the blockmap half of P_SetThingPosition.
void SpawnThings(void) {
    int t, i, bit = 1 << (2 - 1);
    for (t = 0; t < numthings; t++) {
        int* mthing = &things[t * 5];
        int type = mthing[3], options = mthing[4];
        if (type == 11) continue;
        if (type <= 4) {
            if (type != 1) continue;
            i = 0;  // MT_PLAYER
        } else {
            if (options & 16) continue;
            if (!(options & bit)) continue;
            for (i = 0; i < nummobjinfo; i++)
                if (type == mobjinfo[i * 23 + MI_DOOMEDNUM]) break;
        }
        mobj_t* thing = &mobjs[nummobjs++];
        thing->x = mthing[0] << FRACBITS;
        thing->y = mthing[1] << FRACBITS;
        thing->radius = mobjinfo[i * 23 + MI_RADIUS];
        thing->flags = mobjinfo[i * 23 + MI_FLAGS];
        // ---- copied from P_SetThingPosition ----
    // link into blockmap
    if ( ! (thing->flags & MF_NOBLOCKMAP) )
    {
	// inert things don't need to be in blockmap		
	int blockx = (thing->x - bmaporgx)>>MAPBLOCKSHIFT;
	int blocky = (thing->y - bmaporgy)>>MAPBLOCKSHIFT;
	mobj_t** link;

	if (blockx>=0
	    && blockx < bmapwidth
	    && blocky>=0
	    && blocky < bmapheight)
	{
	    link = &blocklinks[blocky*bmapwidth+blockx];
	    thing->bprev = NULL;
	    thing->bnext = *link;
	    if (*link)
		(*link)->bprev = thing;

	    *link = thing;
	}
	else
	{
	    // thing is off the map
	    thing->bnext = thing->bprev = NULL;
	}
    }
        // ---- end of copied code ----
    }
}

// PIT_* stand-in for P_BlockThingsIterator, like the line one in
// maputl_ref.c
int visits, stopafter;
long long visitsum;
boolean PIT_Count(mobj_t* thing) {
    visits++;
    visitsum += (long long)visits * (thing - mobjs);
    return visits != stopafter;
}

// traverser: checksums what it is handed, stops after stopafter
int travcount;
long long travsum;
boolean PTR_Count(intercept_t* in) {
    travcount++;
    int d = in->isaline ? in->d.line - lines : in->d.thing - mobjs;
    travsum += (long long)travcount * ((long long)in->frac + (in->isaline ? 1000003LL : 0) + 7919LL * d);
    return travcount != stopafter;
}

int main(void) {
    int i, j;
    load();
    SpawnThings();
    printf("    // %d mobjs spawned\n", nummobjs - 1);

    // P_BlockThingsIterator
    int bestx = 0, besty = 0, best = 0;
    for (j = 0; j < bmapheight; j++)
        for (i = 0; i < bmapwidth; i++) {
            int n = 0;
            for (mobj_t* m = blocklinks[j * bmapwidth + i]; m; m = m->bnext) n++;
            if (n > best) { best = n; bestx = i; besty = j; }
        }
    int px = (mobjs[1].x - bmaporgx) >> MAPBLOCKSHIFT, py = (mobjs[1].y - bmaporgy) >> MAPBLOCKSHIFT;
    printf("    // busiest thing block %d,%d with %d things\n", bestx, besty, best);
    int blk[][3] = {{bestx, besty, 0}, {bestx, besty, 2}, {px, py, 0}, {0, 0, 0},
                    {-1, 0, 0}, {0, -1, 0}, {bmapwidth, 0, 0}, {0, bmapheight, 0}};
    printf("    var blocks = [\n        // x, y, stopafter, result, visits, visitsum\n");
    for (i = 0; i < (int)(sizeof blk / sizeof blk[0]); i++) {
        visits = 0; visitsum = 0; stopafter = blk[i][2];
        boolean r = P_BlockThingsIterator(blk[i][0], blk[i][1], PIT_Count);
        printf("        [%d, %d, %d, %d, %d, %lld],\n", blk[i][0], blk[i][1], blk[i][2], r, visits, visitsum);
    }
    printf("    ];\n");
    visits = 0; visitsum = 0; stopafter = 0;
    for (j = 0; j < bmapheight; j++)
        for (i = 0; i < bmapwidth; i++)
            P_BlockThingsIterator(i, j, PIT_Count);
    printf("    // whole map: visits %d visitsum %lld\n", visits, visitsum);

    // P_PathTraverse from the player start and from the busiest block
    fixed_t sx = mobjs[1].x, sy = mobjs[1].y;
    fixed_t bx = bmaporgx + bestx * MAPBLOCKSIZE + 40 * FRACUNIT, by = bmaporgy + besty * MAPBLOCKSIZE + 70 * FRACUNIT;
    int tr[][7] = {
        // x1, y1, dx, dy (map units), flags, stopafter
        {0, 0, 2048, 0, PT_ADDLINES | PT_ADDTHINGS, 0},
        {0, 0, 0, 2048, PT_ADDLINES | PT_ADDTHINGS, 0},
        {0, 0, -1500, 1300, PT_ADDLINES | PT_ADDTHINGS, 0},
        {0, 0, 2000, -700, PT_ADDLINES | PT_ADDTHINGS, 0},
        {0, 0, 2000, -700, PT_ADDLINES | PT_ADDTHINGS | PT_EARLYOUT, 0},
        {0, 0, 2048, 0, PT_ADDLINES, 3},
        {0, 0, 10, 6, PT_ADDLINES | PT_ADDTHINGS, 0},
        {0, 0, -12, -15, PT_ADDLINES, 0},
        {1, 0, 1800, 900, PT_ADDLINES | PT_ADDTHINGS, 0},
        {1, 0, -1024, -2048, PT_ADDTHINGS, 0},
        {1, 0, 300, -2048, PT_ADDLINES | PT_ADDTHINGS | PT_EARLYOUT, 0},
        {2, 0, 1024, 512, PT_ADDLINES | PT_ADDTHINGS, 0},
    };
    printf("    var traces = [\n        // x1, y1, x2, y2, flags, stopafter, result, intercepts, calls, checksum\n");
    for (i = 0; i < (int)(sizeof tr / sizeof tr[0]); i++) {
        fixed_t x1 = tr[i][0] == 0 ? sx : tr[i][0] == 1 ? bx : bmaporgx + 5 * MAPBLOCKSIZE;
        fixed_t y1 = tr[i][0] == 0 ? sy : tr[i][0] == 1 ? by : bmaporgy + 9 * MAPBLOCKSIZE;
        fixed_t x2 = x1 + tr[i][2] * FRACUNIT, y2 = y1 + tr[i][3] * FRACUNIT;
        travcount = 0; travsum = 0; stopafter = tr[i][5];
        boolean r = P_PathTraverse(x1, y1, x2, y2, tr[i][4], PTR_Count);
        int n = intercept_p - intercepts;
        if (n >= MAXINTERCEPTS) { fprintf(stderr, "intercepts overflow\n"); return 1; }
        printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %lldl],\n", x1, y1, x2, y2, tr[i][4], stopafter, r, n, travcount, travsum);
    }
    printf("    ];\n");

    // P_XYMovement on its own: P_TryMove always succeeds
    sector_t sec = {0, 128 * FRACUNIT, 0};
    subsector_t ss = {&sec};
    int mv[][6] = {
        // momx, momy, z, flags, tics
        {8 * FRACUNIT, 3 * FRACUNIT, 0, 0, 60},
        {-5 * FRACUNIT, 7 * FRACUNIT + 1234, 0, 0, 60},
        {50 * FRACUNIT, -45 * FRACUNIT, 0, 0, 60},
        {20 * FRACUNIT, 20 * FRACUNIT, 0, 0, 3},
        {0x1001, -0xfff, 0, 0, 3},
        {6 * FRACUNIT, 0, 8 * FRACUNIT, 0, 3},
        {6 * FRACUNIT, 2 * FRACUNIT, 0, MF_MISSILE, 3},
        {FRACUNIT, FRACUNIT / 2, 0, MF_CORPSE, 60},
    };
    printf("    var moves = [\n        // momx, momy, z, flags, tics, x, y, momx, momy, tics until stopped\n");
    for (i = 0; i < (int)(sizeof mv / sizeof mv[0]); i++) {
        mobj_t mo = {0};
        mo.x = sx; mo.y = sy; mo.z = mv[i][2]; mo.floorz = 0;
        mo.subsector = &ss;
        mo.momx = mv[i][0]; mo.momy = mv[i][1]; mo.flags = mv[i][3];
        int stopped = -1;
        for (j = 0; j < mv[i][4]; j++) {
            P_XYMovement(&mo);
            if (stopped < 0 && !mo.momx && !mo.momy) stopped = j + 1;
        }
        printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d],\n", mv[i][0], mv[i][1], mv[i][2], mv[i][3], mv[i][4],
               mo.x, mo.y, mo.momx, mo.momy, stopped);
    }
    printf("    ];\n");
    return 0;
}
