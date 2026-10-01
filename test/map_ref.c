// Reference values for test/MapTest.mc and test/SightTest.mc. The code
// between the "copied" markers is verbatim from linuxdoom-1.10 (p_sight.c,
// the start of p_map.c up to P_TryMove, and the p_maputl.c / r_main.c
// helpers they call); the structs below keep just the fields it uses.
// Things aren't iterated (P_BlockThingsIterator is a stub returning true),
// and P_SetThingPosition / P_UnsetThingPosition / P_CrossSpecialLine are
// no-ops, so only the line clipping is compared. From the repo root:
//
//   python3 -c "import json;[print(len(d),*d) for n in ['vertexes','linedefs','sidedefs','sectors','segs','ssectors','nodes','blockmap','reject','things'] for d in [json.load(open(f'generated/resources/e1m1_{n}.json'))]]" > e1m1.txt
//   gcc test/map_ref.c -o map_ref && ./map_ref < e1m1.txt
#include <stdio.h>
#include <stdlib.h>

typedef int fixed_t;
typedef unsigned char byte;
typedef int boolean;
enum { false, true };
#define FRACBITS 16
#define FRACUNIT (1 << FRACBITS)
#define MAXINT 0x7fffffff
#define MININT ((int)0x80000000)
#define RANGECHECK

enum { BOXTOP, BOXBOTTOM, BOXLEFT, BOXRIGHT };
typedef enum { ST_HORIZONTAL, ST_VERTICAL, ST_POSITIVE, ST_NEGATIVE } slopetype_t;
#define ML_BLOCKING 1
#define ML_BLOCKMONSTERS 2
#define ML_TWOSIDED 4
#define NF_SUBSECTOR 0x8000
#define MF_DROPOFF 0x400
#define MF_NOCLIP 0x1000
#define MF_FLOAT 0x4000
#define MF_TELEPORT 0x8000
#define MF_MISSILE 0x10000
#define MAPBLOCKSHIFT (FRACBITS + 7)
#define MAXRADIUS (32 * FRACUNIT)

typedef struct { fixed_t x, y; } vertex_t;
typedef struct { fixed_t floorheight, ceilingheight; } sector_t;
typedef struct { sector_t* sector; } side_t;
typedef struct {
    vertex_t* v1; vertex_t* v2;
    fixed_t dx, dy;
    short flags, special;
    short sidenum[2];
    fixed_t bbox[4];
    slopetype_t slopetype;
    sector_t* frontsector; sector_t* backsector;
    int validcount;
} line_t;
typedef struct { line_t* linedef; sector_t* frontsector; sector_t* backsector; } seg_t;
typedef struct { sector_t* sector; short numlines, firstline; } subsector_t;
typedef struct { fixed_t x, y, dx, dy; fixed_t bbox[2][4]; unsigned short children[2]; } node_t;
typedef struct { fixed_t x, y, dx, dy; } divline_t;
typedef struct {
    fixed_t x, y, z;
    subsector_t* subsector;
    fixed_t floorz, ceilingz, radius, height;
    int flags;
    void* player;
} mobj_t;

vertex_t vertexes[2048]; int numvertexes;
line_t lines[2048]; int numlines;
side_t sides[2048]; int numsides;
sector_t sectors[512]; int numsectors;
seg_t segs[4096]; int numsegs;
subsector_t subsectors[2048]; int numsubsectors;
node_t nodes[2048]; int numnodes;
short blockmaplump[65536]; short* blockmap;
int bmapwidth, bmapheight;
fixed_t bmaporgx, bmaporgy;
byte rejectmatrix[65536];
int validcount = 1;

void I_Error(char* error, ...) { fprintf(stderr, "%s\n", error); exit(1); }
fixed_t FixedMul(fixed_t a, fixed_t b) { return ((long long) a * (long long) b) >> FRACBITS; }
fixed_t FixedDiv2(fixed_t a, fixed_t b) { long long c = ((long long)a<<16) / ((long long)b); return (fixed_t) c; }
fixed_t FixedDiv(fixed_t a, fixed_t b) { if ((abs(a)>>14) >= abs(b)) return (a^b)<0 ? MININT : MAXINT; return FixedDiv2(a,b); }

// stubs, see the header comment
boolean P_BlockThingsIterator(int x, int y, boolean(*func)(mobj_t*)) { return true; }
boolean PIT_CheckThing(mobj_t* thing) { return true; }
void P_UnsetThingPosition(mobj_t* thing) {}
void P_SetThingPosition(mobj_t* thing) {}
void P_CrossSpecialLine(int linenum, int side, mobj_t* thing) {}

// ---- copied from r_main.c ----
//
// R_PointOnSide
// Traverse BSP (sub) tree,
//  check point against partition plane.
// Returns side 0 (front) or 1 (back).
//
int
R_PointOnSide
( fixed_t	x,
  fixed_t	y,
  node_t*	node )
{
    fixed_t	dx;
    fixed_t	dy;
    fixed_t	left;
    fixed_t	right;
	
    if (!node->dx)
    {
	if (x <= node->x)
	    return node->dy > 0;
	
	return node->dy < 0;
    }
    if (!node->dy)
    {
	if (y <= node->y)
	    return node->dx < 0;
	
	return node->dx > 0;
    }
	
    dx = (x - node->x);
    dy = (y - node->y);
	
    // Try to quickly decide by looking at sign bits.
    if ( (node->dy ^ node->dx ^ dx ^ dy)&0x80000000 )
    {
	if  ( (node->dy ^ dx) & 0x80000000 )
	{
	    // (left is negative)
	    return 1;
	}
	return 0;
    }

    left = FixedMul ( node->dy>>FRACBITS , dx );
    right = FixedMul ( dy , node->dx>>FRACBITS );
	
    if (right < left)
    {
	// front side
	return 0;
    }
    // back side
    return 1;			
}
//
// R_PointInSubsector
//
subsector_t*
R_PointInSubsector
( fixed_t	x,
  fixed_t	y )
{
    node_t*	node;
    int		side;
    int		nodenum;

    // single subsector is a special case
    if (!numnodes)				
	return subsectors;
		
    nodenum = numnodes-1;

    while (! (nodenum & NF_SUBSECTOR) )
    {
	node = &nodes[nodenum];
	side = R_PointOnSide (x, y, node);
	nodenum = node->children[side];
    }
	
    return &subsectors[nodenum & ~NF_SUBSECTOR];
}
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
// ---- copied from p_sight.c ----

//
// P_CheckSight
//
fixed_t		sightzstart;		// eye z of looker
fixed_t		topslope;
fixed_t		bottomslope;		// slopes to top and bottom of target

divline_t	strace;			// from t1 to t2
fixed_t		t2x;
fixed_t		t2y;

int		sightcounts[2];


//
// P_DivlineSide
// Returns side 0 (front), 1 (back), or 2 (on).
//
int
P_DivlineSide
( fixed_t	x,
  fixed_t	y,
  divline_t*	node )
{
    fixed_t	dx;
    fixed_t	dy;
    fixed_t	left;
    fixed_t	right;

    if (!node->dx)
    {
	if (x==node->x)
	    return 2;
	
	if (x <= node->x)
	    return node->dy > 0;

	return node->dy < 0;
    }
    
    if (!node->dy)
    {
	if (x==node->y)
	    return 2;

	if (y <= node->y)
	    return node->dx < 0;

	return node->dx > 0;
    }
	
    dx = (x - node->x);
    dy = (y - node->y);

    left =  (node->dy>>FRACBITS) * (dx>>FRACBITS);
    right = (dy>>FRACBITS) * (node->dx>>FRACBITS);
	
    if (right < left)
	return 0;	// front side
    
    if (left == right)
	return 2;
    return 1;		// back side
}


//
// P_InterceptVector2
// Returns the fractional intercept point
// along the first divline.
// This is only called by the addthings and addlines traversers.
//
fixed_t
P_InterceptVector2
( divline_t*	v2,
  divline_t*	v1 )
{
    fixed_t	frac;
    fixed_t	num;
    fixed_t	den;
	
    den = FixedMul (v1->dy>>8,v2->dx) - FixedMul(v1->dx>>8,v2->dy);

    if (den == 0)
	return 0;
    //	I_Error ("P_InterceptVector: parallel");
    
    num = FixedMul ( (v1->x - v2->x)>>8 ,v1->dy) + 
	FixedMul ( (v2->y - v1->y)>>8 , v1->dx);
    frac = FixedDiv (num , den);

    return frac;
}

//
// P_CrossSubsector
// Returns true
//  if strace crosses the given subsector successfully.
//
boolean P_CrossSubsector (int num)
{
    seg_t*		seg;
    line_t*		line;
    int			s1;
    int			s2;
    int			count;
    subsector_t*	sub;
    sector_t*		front;
    sector_t*		back;
    fixed_t		opentop;
    fixed_t		openbottom;
    divline_t		divl;
    vertex_t*		v1;
    vertex_t*		v2;
    fixed_t		frac;
    fixed_t		slope;
	
#ifdef RANGECHECK
    if (num>=numsubsectors)
	I_Error ("P_CrossSubsector: ss %i with numss = %i",
		 num,
		 numsubsectors);
#endif

    sub = &subsectors[num];
    
    // check lines
    count = sub->numlines;
    seg = &segs[sub->firstline];

    for ( ; count ; seg++, count--)
    {
	line = seg->linedef;

	// allready checked other side?
	if (line->validcount == validcount)
	    continue;
	
	line->validcount = validcount;
		
	v1 = line->v1;
	v2 = line->v2;
	s1 = P_DivlineSide (v1->x,v1->y, &strace);
	s2 = P_DivlineSide (v2->x, v2->y, &strace);

	// line isn't crossed?
	if (s1 == s2)
	    continue;
	
	divl.x = v1->x;
	divl.y = v1->y;
	divl.dx = v2->x - v1->x;
	divl.dy = v2->y - v1->y;
	s1 = P_DivlineSide (strace.x, strace.y, &divl);
	s2 = P_DivlineSide (t2x, t2y, &divl);

	// line isn't crossed?
	if (s1 == s2)
	    continue;	

	// stop because it is not two sided anyway
	// might do this after updating validcount?
	if ( !(line->flags & ML_TWOSIDED) )
	    return false;
	
	// crosses a two sided line
	front = seg->frontsector;
	back = seg->backsector;

	// no wall to block sight with?
	if (front->floorheight == back->floorheight
	    && front->ceilingheight == back->ceilingheight)
	    continue;	

	// possible occluder
	// because of ceiling height differences
	if (front->ceilingheight < back->ceilingheight)
	    opentop = front->ceilingheight;
	else
	    opentop = back->ceilingheight;

	// because of ceiling height differences
	if (front->floorheight > back->floorheight)
	    openbottom = front->floorheight;
	else
	    openbottom = back->floorheight;
		
	// quick test for totally closed doors
	if (openbottom >= opentop)	
	    return false;		// stop
	
	frac = P_InterceptVector2 (&strace, &divl);
		
	if (front->floorheight != back->floorheight)
	{
	    slope = FixedDiv (openbottom - sightzstart , frac);
	    if (slope > bottomslope)
		bottomslope = slope;
	}
		
	if (front->ceilingheight != back->ceilingheight)
	{
	    slope = FixedDiv (opentop - sightzstart , frac);
	    if (slope < topslope)
		topslope = slope;
	}
		
	if (topslope <= bottomslope)
	    return false;		// stop				
    }
    // passed the subsector ok
    return true;		
}



//
// P_CrossBSPNode
// Returns true
//  if strace crosses the given node successfully.
//
boolean P_CrossBSPNode (int bspnum)
{
    node_t*	bsp;
    int		side;

    if (bspnum & NF_SUBSECTOR)
    {
	if (bspnum == -1)
	    return P_CrossSubsector (0);
	else
	    return P_CrossSubsector (bspnum&(~NF_SUBSECTOR));
    }
		
    bsp = &nodes[bspnum];
    
    // decide which side the start point is on
    side = P_DivlineSide (strace.x, strace.y, (divline_t *)bsp);
    if (side == 2)
	side = 0;	// an "on" should cross both sides

    // cross the starting side
    if (!P_CrossBSPNode (bsp->children[side]) )
	return false;
	
    // the partition plane is crossed here
    if (side == P_DivlineSide (t2x, t2y,(divline_t *)bsp))
    {
	// the line doesn't touch the other side
	return true;
    }
    
    // cross the ending side		
    return P_CrossBSPNode (bsp->children[side^1]);
}


//
// P_CheckSight
// Returns true
//  if a straight line between t1 and t2 is unobstructed.
// Uses REJECT.
//
boolean
P_CheckSight
( mobj_t*	t1,
  mobj_t*	t2 )
{
    int		s1;
    int		s2;
    int		pnum;
    int		bytenum;
    int		bitnum;
    
    // First check for trivial rejection.

    // Determine subsector entries in REJECT table.
    s1 = (t1->subsector->sector - sectors);
    s2 = (t2->subsector->sector - sectors);
    pnum = s1*numsectors + s2;
    bytenum = pnum>>3;
    bitnum = 1 << (pnum&7);

    // Check in REJECT table.
    if (rejectmatrix[bytenum]&bitnum)
    {
	sightcounts[0]++;

	// can't possibly be connected
	return false;	
    }

    // An unobstructed LOS is possible.
    // Now look from eyes of t1 to any part of t2.
    sightcounts[1]++;

    validcount++;
	
    sightzstart = t1->z + t1->height - (t1->height>>2);
    topslope = (t2->z+t2->height) - sightzstart;
    bottomslope = (t2->z) - sightzstart;
	
    strace.x = t1->x;
    strace.y = t1->y;
    t2x = t2->x;
    t2y = t2->y;
    strace.dx = t2->x - t1->x;
    strace.dy = t2->y - t1->y;

    // the head node is the last node output
    return P_CrossBSPNode (numnodes-1);	
}
// ---- copied from p_map.c ----
fixed_t		tmbbox[4];
mobj_t*		tmthing;
int		tmflags;
fixed_t		tmx;
fixed_t		tmy;


// If "floatok" true, move would be ok
// if within "tmfloorz - tmceilingz".
boolean		floatok;

fixed_t		tmfloorz;
fixed_t		tmceilingz;
fixed_t		tmdropoffz;

// keep track of the line that lowers the ceiling,
// so missiles don't explode against sky hack walls
line_t*		ceilingline;

// keep track of special lines as they are hit,
// but don't process them until the move is proven valid
#define MAXSPECIALCROSS		8

line_t*		spechit[MAXSPECIALCROSS];
int		numspechit;



//
// MOVEMENT ITERATOR FUNCTIONS
//


//
// PIT_CheckLine
// Adjusts tmfloorz and tmceilingz as lines are contacted
//
boolean PIT_CheckLine (line_t* ld)
{
    if (tmbbox[BOXRIGHT] <= ld->bbox[BOXLEFT]
	|| tmbbox[BOXLEFT] >= ld->bbox[BOXRIGHT]
	|| tmbbox[BOXTOP] <= ld->bbox[BOXBOTTOM]
	|| tmbbox[BOXBOTTOM] >= ld->bbox[BOXTOP] )
	return true;

    if (P_BoxOnLineSide (tmbbox, ld) != -1)
	return true;
		
    // A line has been hit
    
    // The moving thing's destination position will cross
    // the given line.
    // If this should not be allowed, return false.
    // If the line is special, keep track of it
    // to process later if the move is proven ok.
    // NOTE: specials are NOT sorted by order,
    // so two special lines that are only 8 pixels apart
    // could be crossed in either order.
    
    if (!ld->backsector)
	return false;		// one sided line
		
    if (!(tmthing->flags & MF_MISSILE) )
    {
	if ( ld->flags & ML_BLOCKING )
	    return false;	// explicitly blocking everything

	if ( !tmthing->player && ld->flags & ML_BLOCKMONSTERS )
	    return false;	// block monsters only
    }

    // set openrange, opentop, openbottom
    P_LineOpening (ld);	
	
    // adjust floor / ceiling heights
    if (opentop < tmceilingz)
    {
	tmceilingz = opentop;
	ceilingline = ld;
    }

    if (openbottom > tmfloorz)
	tmfloorz = openbottom;	

    if (lowfloor < tmdropoffz)
	tmdropoffz = lowfloor;
		
    // if contacted a special line, add it to the list
    if (ld->special)
    {
	spechit[numspechit] = ld;
	numspechit++;
    }

    return true;
}


//
// MOVEMENT CLIPPING
//

//
// P_CheckPosition
// This is purely informative, nothing is modified
// (except things picked up).
// 
// in:
//  a mobj_t (can be valid or invalid)
//  a position to be checked
//   (doesn't need to be related to the mobj_t->x,y)
//
// during:
//  special things are touched if MF_PICKUP
//  early out on solid lines?
//
// out:
//  newsubsec
//  floorz
//  ceilingz
//  tmdropoffz
//   the lowest point contacted
//   (monsters won't move to a dropoff)
//  speciallines[]
//  numspeciallines
//
boolean
P_CheckPosition
( mobj_t*	thing,
  fixed_t	x,
  fixed_t	y )
{
    int			xl;
    int			xh;
    int			yl;
    int			yh;
    int			bx;
    int			by;
    subsector_t*	newsubsec;

    tmthing = thing;
    tmflags = thing->flags;
	
    tmx = x;
    tmy = y;
	
    tmbbox[BOXTOP] = y + tmthing->radius;
    tmbbox[BOXBOTTOM] = y - tmthing->radius;
    tmbbox[BOXRIGHT] = x + tmthing->radius;
    tmbbox[BOXLEFT] = x - tmthing->radius;

    newsubsec = R_PointInSubsector (x,y);
    ceilingline = NULL;
    
    // The base floor / ceiling is from the subsector
    // that contains the point.
    // Any contacted lines the step closer together
    // will adjust them.
    tmfloorz = tmdropoffz = newsubsec->sector->floorheight;
    tmceilingz = newsubsec->sector->ceilingheight;
			
    validcount++;
    numspechit = 0;

    if ( tmflags & MF_NOCLIP )
	return true;
    
    // Check things first, possibly picking things up.
    // The bounding box is extended by MAXRADIUS
    // because mobj_ts are grouped into mapblocks
    // based on their origin point, and can overlap
    // into adjacent blocks by up to MAXRADIUS units.
    xl = (tmbbox[BOXLEFT] - bmaporgx - MAXRADIUS)>>MAPBLOCKSHIFT;
    xh = (tmbbox[BOXRIGHT] - bmaporgx + MAXRADIUS)>>MAPBLOCKSHIFT;
    yl = (tmbbox[BOXBOTTOM] - bmaporgy - MAXRADIUS)>>MAPBLOCKSHIFT;
    yh = (tmbbox[BOXTOP] - bmaporgy + MAXRADIUS)>>MAPBLOCKSHIFT;

    for (bx=xl ; bx<=xh ; bx++)
	for (by=yl ; by<=yh ; by++)
	    if (!P_BlockThingsIterator(bx,by,PIT_CheckThing))
		return false;
    
    // check lines
    xl = (tmbbox[BOXLEFT] - bmaporgx)>>MAPBLOCKSHIFT;
    xh = (tmbbox[BOXRIGHT] - bmaporgx)>>MAPBLOCKSHIFT;
    yl = (tmbbox[BOXBOTTOM] - bmaporgy)>>MAPBLOCKSHIFT;
    yh = (tmbbox[BOXTOP] - bmaporgy)>>MAPBLOCKSHIFT;

    for (bx=xl ; bx<=xh ; bx++)
	for (by=yl ; by<=yh ; by++)
	    if (!P_BlockLinesIterator (bx,by,PIT_CheckLine))
		return false;

    return true;
}


//
// P_TryMove
// Attempt to move to a new position,
// crossing special lines unless MF_TELEPORT is set.
//
boolean
P_TryMove
( mobj_t*	thing,
  fixed_t	x,
  fixed_t	y )
{
    fixed_t	oldx;
    fixed_t	oldy;
    int		side;
    int		oldside;
    line_t*	ld;

    floatok = false;
    if (!P_CheckPosition (thing, x, y))
	return false;		// solid wall or thing
    
    if ( !(thing->flags & MF_NOCLIP) )
    {
	if (tmceilingz - tmfloorz < thing->height)
	    return false;	// doesn't fit

	floatok = true;
	
	if ( !(thing->flags&MF_TELEPORT) 
	     &&tmceilingz - thing->z < thing->height)
	    return false;	// mobj must lower itself to fit

	if ( !(thing->flags&MF_TELEPORT)
	     && tmfloorz - thing->z > 24*FRACUNIT )
	    return false;	// too big a step up

	if ( !(thing->flags&(MF_DROPOFF|MF_FLOAT))
	     && tmfloorz - tmdropoffz > 24*FRACUNIT )
	    return false;	// don't stand over a dropoff
    }
    
    // the move is ok,
    // so link the thing into its new position
    P_UnsetThingPosition (thing);

    oldx = thing->x;
    oldy = thing->y;
    thing->floorz = tmfloorz;
    thing->ceilingz = tmceilingz;	
    thing->x = x;
    thing->y = y;

    P_SetThingPosition (thing);
    
    // if any special lines were hit, do the effect
    if (! (thing->flags&(MF_TELEPORT|MF_NOCLIP)) )
    {
	while (numspechit--)
	{
	    // see if the line was crossed
	    ld = spechit[numspechit];
	    side = P_PointOnLineSide (thing->x, thing->y, ld);
	    oldside = P_PointOnLineSide (oldx, oldy, ld);
	    if (side != oldside)
	    {
		if (ld->special)
		    P_CrossSpecialLine (ld-lines, oldside, thing);
	    }
	}
    }

    return true;
}
// ---- end of copied code ----

int rd(void) { int v; if (scanf("%d", &v) != 1) { fprintf(stderr, "short input\n"); exit(1); } return v; }

int things[4096]; int numthings;

void load(void) {
    int i, n;
    static int mld[2048 * 7], msd[4096 * 6], mseg[4096 * 6];
    numvertexes = rd() / 2;
    for (i = 0; i < numvertexes; i++) { vertexes[i].x = rd() << FRACBITS; vertexes[i].y = rd() << FRACBITS; }
    n = rd(); for (i = 0; i < n; i++) mld[i] = rd(); numlines = n / 7;
    n = rd(); for (i = 0; i < n; i++) msd[i] = rd(); numsides = n / 6;
    numsectors = rd() / 7;
    for (i = 0; i < numsectors; i++) {
        int v[7];
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
        ld->flags = m[2]; ld->special = m[3];
        ld->dx = v2->x - v1->x;
        ld->dy = v2->y - v1->y;
        if (!ld->dx) ld->slopetype = ST_VERTICAL;
        else if (!ld->dy) ld->slopetype = ST_HORIZONTAL;
        else ld->slopetype = FixedDiv(ld->dy, ld->dx) > 0 ? ST_POSITIVE : ST_NEGATIVE;
        if (v1->x < v2->x) { ld->bbox[BOXLEFT] = v1->x; ld->bbox[BOXRIGHT] = v2->x; }
        else { ld->bbox[BOXLEFT] = v2->x; ld->bbox[BOXRIGHT] = v1->x; }
        if (v1->y < v2->y) { ld->bbox[BOXBOTTOM] = v1->y; ld->bbox[BOXTOP] = v2->y; }
        else { ld->bbox[BOXBOTTOM] = v2->y; ld->bbox[BOXTOP] = v1->y; }
        ld->sidenum[0] = m[5];
        ld->sidenum[1] = m[6];
        ld->frontsector = ld->sidenum[0] != -1 ? sides[ld->sidenum[0]].sector : 0;
        ld->backsector = ld->sidenum[1] != -1 ? sides[ld->sidenum[1]].sector : 0;
    }
    // segs as P_LoadSegs
    n = rd(); for (i = 0; i < n; i++) mseg[i] = rd(); numsegs = n / 6;
    for (i = 0; i < numsegs; i++) {
        int* m = &mseg[i * 6];
        line_t* ldef = &lines[m[3]];
        int side = m[4];
        segs[i].linedef = ldef;
        segs[i].frontsector = sides[ldef->sidenum[side]].sector;
        segs[i].backsector = (ldef->flags & ML_TWOSIDED) ? sides[ldef->sidenum[side ^ 1]].sector : 0;
    }
    numsubsectors = rd() / 2;
    for (i = 0; i < numsubsectors; i++) { subsectors[i].numlines = rd(); subsectors[i].firstline = rd(); }
    numnodes = rd() / 14;
    for (i = 0; i < numnodes; i++) {
        nodes[i].x = rd() << FRACBITS; nodes[i].y = rd() << FRACBITS;
        nodes[i].dx = rd() << FRACBITS; nodes[i].dy = rd() << FRACBITS;
        for (int j = 0; j < 2; j++) for (int k = 0; k < 4; k++) nodes[i].bbox[j][k] = rd() << FRACBITS;
        nodes[i].children[0] = rd(); nodes[i].children[1] = rd();
    }
    n = rd(); for (i = 0; i < n; i++) blockmaplump[i] = rd();
    blockmap = blockmaplump + 4;
    bmaporgx = blockmaplump[0] << FRACBITS;
    bmaporgy = blockmaplump[1] << FRACBITS;
    bmapwidth = blockmaplump[2];
    bmapheight = blockmaplump[3];
    n = rd(); for (i = 0; i < n; i++) rejectmatrix[i] = rd();
    n = rd(); for (i = 0; i < n; i++) things[i] = rd(); numthings = n / 5;
    // P_GroupLines: subsector sectors
    for (i = 0; i < numsubsectors; i++)
        subsectors[i].sector = segs[subsectors[i].firstline].frontsector;
}

// a mobj standing on the floor at x, y
void place(mobj_t* mo, fixed_t x, fixed_t y) {
    mo->x = x; mo->y = y;
    mo->subsector = R_PointInSubsector(x, y);
    mo->z = mo->floorz = mo->subsector->sector->floorheight;
    mo->ceilingz = mo->subsector->sector->ceilingheight;
}

#define NSIGHT 20

int main(void) {
    int i, j;
    load();
    printf("// %d lines, %d nodes, %d things\n", numlines, numnodes, numthings);

    // P_CheckSight between every pair of the first NSIGHT things, both
    // ways round, each standing on the floor and 56 units tall.
    static mobj_t sm[NSIGHT];
    for (i = 0; i < NSIGHT; i++) {
        place(&sm[i], things[i * 5] << FRACBITS, things[i * 5 + 1] << FRACBITS);
        sm[i].height = 56 * FRACUNIT;
    }
    int seen = 0;
    printf("    var sight = [\n        // t1, t2, P_CheckSight, topslope, bottomslope\n");
    for (i = 0; i < NSIGHT; i++)
        for (j = 0; j < NSIGHT; j++) {
            if (i == j) continue;
            boolean r = P_CheckSight(&sm[i], &sm[j]);
            seen += r;
            printf("        [%d, %d, %d, %d, %d],\n", i, j, r, topslope, bottomslope);
        }
    printf("    ];\n    // %d visible, sightcounts %d %d\n", seen, sightcounts[0], sightcounts[1]);

    // P_CheckPosition / P_TryMove from the thing spots in 8 directions.
    // Cases are picked so every outcome shows up for a player (radius
    // 16, MF_DROPOFF) and a monster (radius 20, blocked by
    // ML_BLOCKMONSTERS, no dropoffs).
    enum { BLOCKED, NOFIT, LOWER, STEPUP, DROPOFF, UP_OK, DOWN_OK, FLAT_OK, NCAT };
    static const char* catname[] = {"blocked", "doesn't fit", "too low", "step too big", "dropoff",
                                    "step up", "step down", "flat"};
    int count[2][NCAT] = {{0}};
    int dirs[8][2] = {{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}};
    int dists[] = {16, 32, 64, 128};
    int dummy;
    printf("    var moves = [\n        // monster?, x, y, newx, newy, P_CheckPosition, P_TryMove, floatok,\n"
           "        // tmfloorz, tmceilingz, tmdropoffz, numspechit, ceilingline\n");
    for (int type = 0; type < 2; type++)
        for (i = 0; i < numthings; i++)
            for (int d = 0; d < 4; d++)
                for (int k = 0; k < 8; k++) {
                    mobj_t mo = {0};
                    fixed_t x = things[i * 5] << FRACBITS, y = things[i * 5 + 1] << FRACBITS;
                    fixed_t nx = x + dirs[k][0] * dists[d] * FRACUNIT, ny = y + dirs[k][1] * dists[d] * FRACUNIT;
                    mo.radius = (type ? 20 : 16) * FRACUNIT;
                    mo.height = 56 * FRACUNIT;
                    mo.flags = type ? 0 : MF_DROPOFF;
                    mo.player = type ? NULL : &dummy;
                    place(&mo, x, y);
                    fixed_t place_z = mo.z;
                    boolean cp = P_CheckPosition(&mo, nx, ny);
                    int nsh = numspechit;
                    int cl = ceilingline ? ceilingline - lines : -1;
                    boolean tm = P_TryMove(&mo, nx, ny);
                    int cat;
                    if (tm) cat = tmfloorz > place_z ? UP_OK : tmfloorz < place_z ? DOWN_OK : FLAT_OK;
                    else if (!cp) cat = BLOCKED;
                    else if (tmceilingz - tmfloorz < mo.height) cat = NOFIT;
                    else if (tmceilingz - mo.z < mo.height) cat = LOWER;
                    else if (tmfloorz - mo.z > 24 * FRACUNIT) cat = STEPUP;
                    else cat = DROPOFF;
                    if (count[type][cat]++ >= 6) continue;
                    printf("        [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d],  // %s\n", type, x, y, nx, ny,
                           cp, tm, floatok, tmfloorz, tmceilingz, tmdropoffz, nsh, cl, catname[cat]);
                }
    printf("    ];\n");
    for (int type = 0; type < 2; type++) {
        printf("    // %s:", type ? "monster" : "player");
        for (i = 0; i < NCAT; i++) printf(" %s %d,", catname[i], count[type][i]);
        printf("\n");
    }
    return 0;
}
