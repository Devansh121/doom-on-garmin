// Reference values for test/PEnemyTest.mc. The functions between the
// "copied" markers are verbatim from linuxdoom-1.10 p_enemy.c (and
// P_AproxDistance from p_maputl.c, R_PointToAngle from r_main.c); the
// structs below keep just the fields they use, so no struct access had
// to change. P_TryMove and P_CheckSight are stubs with the same fixed
// rule the Monkey C test installs. Build against the original tables.c
// and m_random.c:
//
//   gcc -I ~/src/DOOM/linuxdoom-1.10 test/enemy_ref.c ~/src/DOOM/linuxdoom-1.10/tables.c ~/src/DOOM/linuxdoom-1.10/m_random.c -o enemy_ref && ./enemy_ref
#include <stdio.h>
#include <stdlib.h>
#include "tables.h"
#include "m_random.h"

// boolean comes from doomtype.h, via m_random.h
extern int prndindex;
#define MAXINT 0x7fffffff
#define MININT ((int)0x80000000)
#define FLOATSPEED (FRACUNIT*4)
#define MELEERANGE (64*FRACUNIT)
#define MF_SHADOW 0x40000
#define MF_FLOAT 0x4000
#define MF_INFLOAT 0x200000
#define MF_AMBUSH 32

typedef enum
{
    DI_EAST,
    DI_NORTHEAST,
    DI_NORTH,
    DI_NORTHWEST,
    DI_WEST,
    DI_SOUTHWEST,
    DI_SOUTH,
    DI_SOUTHEAST,
    DI_NODIR,
    NUMDIRS

} dirtype_t;

dirtype_t opposite[] =
{
  DI_WEST, DI_SOUTHWEST, DI_SOUTH, DI_SOUTHEAST,
  DI_EAST, DI_NORTHEAST, DI_NORTH, DI_NORTHWEST, DI_NODIR
};

dirtype_t diags[] =
{
    DI_NORTHWEST, DI_NORTHEAST, DI_SOUTHWEST, DI_SOUTHEAST
};

// info.c: MT_TROOP speed 8, radius 20; MT_PLAYER radius 16
typedef struct { int speed; fixed_t radius; } mobjinfo_t;
mobjinfo_t troopinfo = { 8, 20*FRACUNIT };
mobjinfo_t playerinfo = { 0, 16*FRACUNIT };

typedef struct mobj_s {
    fixed_t x, y, z;
    angle_t angle;
    int flags;
    int movedir, movecount;
    fixed_t floorz;
    struct mobj_s* target;
    mobjinfo_t* info;
} mobj_t;

typedef struct line_s line_t;
line_t* spechit[8];
int numspechit = 0;
boolean floatok = false;
fixed_t tmfloorz = 0;
boolean P_UseSpecialLine(mobj_t* thing, line_t* line, int side) { return false; }
void I_Error(char* s, ...) { fprintf(stderr, "%s\n", s); exit(1); }

// The fixed rule, same as PEnemyTest.mc's testTryMove: accept a move
// when a hash of the destination's map units is < 3 (of 8), and then
// move there like P_TryMove would.
boolean P_TryMove(mobj_t* thing, fixed_t x, fixed_t y)
{
    if ((((x >> 16) * 7 + (y >> 16) * 13) & 7) < 3) {
        thing->x = x;
        thing->y = y;
        return true;
    }
    return false;
}

boolean P_CheckSight(mobj_t* t1, mobj_t* t2) { return true; }

fixed_t viewx, viewy;

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

angle_t R_PointToAngle2(fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2) {
    viewx = x1; viewy = y1;
    return R_PointToAngle(x2, y2);
}

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

// ---- copied from p_enemy.c ----
//
// P_CheckMeleeRange
//
boolean P_CheckMeleeRange (mobj_t*	actor)
{
    mobj_t*	pl;
    fixed_t	dist;

    if (!actor->target)
	return false;

    pl = actor->target;
    dist = P_AproxDistance (pl->x-actor->x, pl->y-actor->y);

    if (dist >= MELEERANGE-20*FRACUNIT+pl->info->radius)
	return false;

    if (! P_CheckSight (actor, actor->target) )
	return false;

    return true;
}

fixed_t	xspeed[8] = {FRACUNIT,47000,0,-47000,-FRACUNIT,-47000,0,47000};
fixed_t yspeed[8] = {0,47000,FRACUNIT,47000,0,-47000,-FRACUNIT,-47000};

boolean P_Move (mobj_t*	actor)
{
    fixed_t	tryx;
    fixed_t	tryy;

    line_t*	ld;

    // warning: 'catch', 'throw', and 'try'
    // are all C++ reserved words
    boolean	try_ok;
    boolean	good;

    if (actor->movedir == DI_NODIR)
	return false;

    if ((unsigned)actor->movedir >= 8)
	I_Error ("Weird actor->movedir!");

    tryx = actor->x + actor->info->speed*xspeed[actor->movedir];
    tryy = actor->y + actor->info->speed*yspeed[actor->movedir];

    try_ok = P_TryMove (actor, tryx, tryy);

    if (!try_ok)
    {
	// open any specials
	if (actor->flags & MF_FLOAT && floatok)
	{
	    // must adjust height
	    if (actor->z < tmfloorz)
		actor->z += FLOATSPEED;
	    else
		actor->z -= FLOATSPEED;

	    actor->flags |= MF_INFLOAT;
	    return true;
	}

	if (!numspechit)
	    return false;

	actor->movedir = DI_NODIR;
	good = false;
	while (numspechit--)
	{
	    ld = spechit[numspechit];
	    // if the special is not a door
	    // that can be opened,
	    // return false
	    if (P_UseSpecialLine (actor, ld,0))
		good = true;
	}
	return good;
    }
    else
    {
	actor->flags &= ~MF_INFLOAT;
    }


    if (! (actor->flags & MF_FLOAT) )
	actor->z = actor->floorz;
    return true;
}

boolean P_TryWalk (mobj_t* actor)
{
    if (!P_Move (actor))
    {
	return false;
    }

    actor->movecount = P_Random()&15;
    return true;
}

void P_NewChaseDir (mobj_t*	actor)
{
    fixed_t	deltax;
    fixed_t	deltay;

    dirtype_t	d[3];

    int		tdir;
    dirtype_t	olddir;

    dirtype_t	turnaround;

    if (!actor->target)
	I_Error ("P_NewChaseDir: called with no target");

    olddir = actor->movedir;
    turnaround=opposite[olddir];

    deltax = actor->target->x - actor->x;
    deltay = actor->target->y - actor->y;

    if (deltax>10*FRACUNIT)
	d[1]= DI_EAST;
    else if (deltax<-10*FRACUNIT)
	d[1]= DI_WEST;
    else
	d[1]=DI_NODIR;

    if (deltay<-10*FRACUNIT)
	d[2]= DI_SOUTH;
    else if (deltay>10*FRACUNIT)
	d[2]= DI_NORTH;
    else
	d[2]=DI_NODIR;

    // try direct route
    if (d[1] != DI_NODIR
	&& d[2] != DI_NODIR)
    {
	actor->movedir = diags[((deltay<0)<<1)+(deltax>0)];
	if (actor->movedir != turnaround && P_TryWalk(actor))
	    return;
    }

    // try other directions
    if (P_Random() > 200
	||  abs(deltay)>abs(deltax))
    {
	tdir=d[1];
	d[1]=d[2];
	d[2]=tdir;
    }

    if (d[1]==turnaround)
	d[1]=DI_NODIR;
    if (d[2]==turnaround)
	d[2]=DI_NODIR;

    if (d[1]!=DI_NODIR)
    {
	actor->movedir = d[1];
	if (P_TryWalk(actor))
	{
	    // either moved forward or attacked
	    return;
	}
    }

    if (d[2]!=DI_NODIR)
    {
	actor->movedir =d[2];

	if (P_TryWalk(actor))
	    return;
    }

    // there is no direct path to the player,
    // so pick another direction.
    if (olddir!=DI_NODIR)
    {
	actor->movedir =olddir;

	if (P_TryWalk(actor))
	    return;
    }

    // randomly determine direction of search
    if (P_Random()&1)
    {
	for ( tdir=DI_EAST;
	      tdir<=DI_SOUTHEAST;
	      tdir++ )
	{
	    if (tdir!=turnaround)
	    {
		actor->movedir =tdir;

		if ( P_TryWalk(actor) )
		    return;
	    }
	}
    }
    else
    {
	for ( tdir=DI_SOUTHEAST;
	      tdir != (DI_EAST-1);
	      tdir-- )
	{
	    if (tdir!=turnaround)
	    {
		actor->movedir =tdir;

		if ( P_TryWalk(actor) )
		    return;
	    }
	}
    }

    if (turnaround !=  DI_NODIR)
    {
	actor->movedir =turnaround;
	if ( P_TryWalk(actor) )
	    return;
    }

    actor->movedir = DI_NODIR;	// can not move
}

void A_FaceTarget (mobj_t* actor)
{
    if (!actor->target)
	return;

    actor->flags &= ~MF_AMBUSH;

    actor->angle = R_PointToAngle2 (actor->x,
				    actor->y,
				    actor->target->x,
				    actor->target->y);

    if (actor->target->flags & MF_SHADOW)
	actor->angle += (P_Random()-P_Random())<<21;
}
// ---- end of copied code ----

int main(void)
{
    mobj_t actor = { 0 }, target = { 0 };
    int i, t;

    // P_NewChaseDir sequence: a troop chasing a target that jumps between
    // these spots every 12 calls, starting at movedir 0 like P_SpawnMobj
    // leaves it, with P_Random from index 0.
    static const int spots[][2] = {
        { 1200, -3400 }, { 900, -3700 }, { 1056, -3616 }, { 1300, -3610 },
        { 1060, -3200 }, { 700, -3000 }
    };
    actor.x = 1056 << FRACBITS;
    actor.y = -3616 << FRACBITS;
    actor.floorz = 7 << FRACBITS;
    actor.info = &troopinfo;
    actor.target = &target;
    target.info = &playerinfo;
    prndindex = 0;

    printf("    // movedir, movecount, x, y, prndindex after each P_NewChaseDir\n");
    printf("    var chase = [\n");
    for (i = 0; i < 72; i++) {
        if (i % 12 == 0) {
            t = i / 12;
            target.x = spots[t][0] << FRACBITS;
            target.y = spots[t][1] << FRACBITS;
        }
        P_NewChaseDir(&actor);
        printf("        [%d, %d, %d, %d, %d]%s\n", actor.movedir, actor.movecount,
               actor.x, actor.y, prndindex, i < 71 ? "," : "");
    }
    printf("    ];\n");

    // P_CheckMeleeRange and A_FaceTarget: actor at the origin of each
    // case, target at an offset; the last ones are a shadow target.
    static const int faces[][5] = {
        // ax, ay, tx, ty (map units), shadow
        { 1056, -3616, 1056, -3616, 0 },
        { 1056, -3616, 1100, -3616, 0 },
        { 1056, -3616, 1115, -3616, 0 },
        { 1056, -3616, 1116, -3616, 0 },
        { 1056, -3616, 1000, -3580, 0 },
        { 1056, -3616, 1030, -3660, 0 },
        { 1056, -3616, 1090, -3650, 0 },
        { 1056, -3616, 1056, -3500, 0 },
        { 1056, -3616, 1056, -3700, 0 },
        { 1056, -3616, 900, -3616, 0 },
        { 0, 0, -3, 1, 0 },
        { -2000, 1500, 2500, -1700, 0 },
        { 1056, -3616, 1080, -3600, 1 },
        { 1056, -3616, 1300, -3000, 1 },
        { 1056, -3616, 800, -3900, 1 },
    };
    prndindex = 0;
    printf("    // ax, ay, tx, ty, shadow, P_CheckMeleeRange, angle after A_FaceTarget\n");
    printf("    var faces = [\n");
    for (i = 0; i < (int)(sizeof(faces) / sizeof(faces[0])); i++) {
        boolean melee;
        actor.x = faces[i][0] << FRACBITS;
        actor.y = faces[i][1] << FRACBITS;
        target.x = faces[i][2] << FRACBITS;
        target.y = faces[i][3] << FRACBITS;
        target.flags = faces[i][4] ? MF_SHADOW : 0;
        melee = P_CheckMeleeRange(&actor);
        A_FaceTarget(&actor);
        printf("        [%d, %d, %d, %d, %d, %s, %d]%s\n", actor.x, actor.y, target.x, target.y,
               faces[i][4], melee ? "true" : "false", (int)actor.angle,
               i < (int)(sizeof(faces) / sizeof(faces[0])) - 1 ? "," : "");
    }
    printf("    ];\n");
    return 0;
}
