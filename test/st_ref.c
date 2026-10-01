// Reference values for test/StStuffTest.mc. STlib_drawNum (st_lib.c),
// ST_calcPainOffset and ST_updateFaceWidget (st_stuff.c) are copied
// from linuxdoom-1.10 with only the struct access changed: patches are
// numbers whose widths come from the WAD (STTNUM* 14x16, STYSNUM* 4x6),
// and V_DrawPatch / V_CopyRect print what they would draw.
// R_PointToAngle is from r_main.c. Build against the original tables.c:
//
//   gcc -I ~/src/DOOM/linuxdoom-1.10 test/st_ref.c ~/src/DOOM/linuxdoom-1.10/tables.c -o st_ref && ./st_ref
#include <stdio.h>
#include "tables.h"

typedef int boolean;
#define false 0
#define true 1
#define TICRATE 35
#define NUMWEAPONS 9
#define NUMPOWERS 6
#define pw_invulnerability 0
#define CF_GODMODE 2
#define ST_Y 168

//
// st_lib.c
//
typedef struct { int width, height; } patch_t;
patch_t tallpatch = {14, 16}, shortpatch = {4, 6}, minuspatch = {8, 6};
int lumpbase; // which list the patch_t* points into, for printing

void V_DrawPatch(int x, int y, int scrn, int lump) { printf("%d, %d, %d, ", lump, x, y); }
void V_CopyRect(int srcx, int srcy, int srcscrn, int width, int height, int destx, int desty, int destscrn) {
    printf("-1, %d, %d, %d, %d, ", destx, desty, width, height);
}
#define FG 0
#define BG 4
#define SHORT(x) (x)
#define I_Error(s) printf("error %s\n", s)

typedef struct {
    int x, y, width, oldnum;
    int *num;
    boolean *on;
    patch_t *p0; // n->p[0], the digit patches' size
    int plump;   // lump number of n->p[0]
    int data;
} st_number_t;

int sttminus = 79; // HudLumps.MINUS

void STlib_drawNum(st_number_t *n, boolean refresh)
{
    int numdigits = n->width;
    int num = *n->num;

    int w = SHORT(n->p0->width);
    int h = SHORT(n->p0->height);
    int x = n->x;

    int neg;

    n->oldnum = *n->num;

    neg = num < 0;

    if (neg)
    {
        if (numdigits == 2 && num < -9)
            num = -9;
        else if (numdigits == 3 && num < -99)
            num = -99;

        num = -num;
    }

    // clear the area
    x = n->x - numdigits*w;

    if (n->y - ST_Y < 0)
        I_Error("drawNum: n->y - ST_Y < 0");

    V_CopyRect(x, n->y - ST_Y, BG, w*numdigits, h, x, n->y, FG);

    // if non-number, do not draw it
    if (num == 1994)
        return;

    x = n->x;

    // in the special case of 0, you draw 0
    if (!num)
        V_DrawPatch(x - w, n->y, FG, n->plump + 0);

    // draw the new number
    while (num && numdigits--)
    {
        x -= w;
        V_DrawPatch(x, n->y, FG, n->plump + num % 10);
        num /= 10;
    }

    // draw a minus sign if necessary
    if (neg)
        V_DrawPatch(x - 8, n->y, FG, sttminus);
}

//
// st_stuff.c face logic
//
#define ST_NUMPAINFACES		5
#define ST_NUMSTRAIGHTFACES	3
#define ST_NUMTURNFACES		2
#define ST_NUMSPECIALFACES		3
#define ST_FACESTRIDE \
          (ST_NUMSTRAIGHTFACES+ST_NUMTURNFACES+ST_NUMSPECIALFACES)
#define ST_NUMEXTRAFACES		2
#define ST_NUMFACES \
          (ST_FACESTRIDE*ST_NUMPAINFACES+ST_NUMEXTRAFACES)
#define ST_TURNOFFSET		(ST_NUMSTRAIGHTFACES)
#define ST_OUCHOFFSET		(ST_TURNOFFSET + ST_NUMTURNFACES)
#define ST_EVILGRINOFFSET		(ST_OUCHOFFSET + 1)
#define ST_RAMPAGEOFFSET		(ST_EVILGRINOFFSET + 1)
#define ST_GODFACE			(ST_NUMPAINFACES*ST_FACESTRIDE)
#define ST_DEADFACE			(ST_GODFACE+1)
#define ST_EVILGRINCOUNT		(2*TICRATE)
#define ST_STRAIGHTFACECOUNT	(TICRATE/2)
#define ST_TURNCOUNT		(1*TICRATE)
#define ST_OUCHCOUNT		(1*TICRATE)
#define ST_RAMPAGEDELAY		(2*TICRATE)
#define ST_MUCHPAIN			20

typedef struct { fixed_t x, y; angle_t angle; } mobj_t;
typedef struct {
    mobj_t *mo;
    int health;
    int powers[NUMPOWERS];
    boolean weaponowned[NUMWEAPONS];
    int attackdown;
    int cheats;
    int damagecount;
    int bonuscount;
    mobj_t *attacker;
} player_t;

player_t player;
player_t *plyr = &player;
mobj_t playermo, badguy;

static int st_oldhealth = -1;
static boolean oldweaponsowned[NUMWEAPONS];
static int st_facecount = 0;
static int st_faceindex = 0;
static int st_randomnumber;

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
    viewx = x1;
    viewy = y1;
    return R_PointToAngle(x2, y2);
}

int ST_calcPainOffset(void)
{
    int		health;
    static int	lastcalc;
    static int	oldhealth = -1;

    health = plyr->health > 100 ? 100 : plyr->health;

    if (health != oldhealth)
    {
	lastcalc = ST_FACESTRIDE * (((100 - health) * ST_NUMPAINFACES) / 101);
	oldhealth = health;
    }
    return lastcalc;
}

void ST_updateFaceWidget(void)
{
    int		i;
    angle_t	badguyangle;
    angle_t	diffang;
    static int	lastattackdown = -1;
    static int	priority = 0;
    boolean	doevilgrin;

    if (priority < 10)
    {
	// dead
	if (!plyr->health)
	{
	    priority = 9;
	    st_faceindex = ST_DEADFACE;
	    st_facecount = 1;
	}
    }

    if (priority < 9)
    {
	if (plyr->bonuscount)
	{
	    // picking up bonus
	    doevilgrin = false;

	    for (i=0;i<NUMWEAPONS;i++)
	    {
		if (oldweaponsowned[i] != plyr->weaponowned[i])
		{
		    doevilgrin = true;
		    oldweaponsowned[i] = plyr->weaponowned[i];
		}
	    }
	    if (doevilgrin)
	    {
		// evil grin if just picked up weapon
		priority = 8;
		st_facecount = ST_EVILGRINCOUNT;
		st_faceindex = ST_calcPainOffset() + ST_EVILGRINOFFSET;
	    }
	}

    }

    if (priority < 8)
    {
	if (plyr->damagecount
	    && plyr->attacker
	    && plyr->attacker != plyr->mo)
	{
	    // being attacked
	    priority = 7;

	    if (plyr->health - st_oldhealth > ST_MUCHPAIN)
	    {
		st_facecount = ST_TURNCOUNT;
		st_faceindex = ST_calcPainOffset() + ST_OUCHOFFSET;
	    }
	    else
	    {
		badguyangle = R_PointToAngle2(plyr->mo->x,
					      plyr->mo->y,
					      plyr->attacker->x,
					      plyr->attacker->y);

		if (badguyangle > plyr->mo->angle)
		{
		    // whether right or left
		    diffang = badguyangle - plyr->mo->angle;
		    i = diffang > ANG180;
		}
		else
		{
		    // whether left or right
		    diffang = plyr->mo->angle - badguyangle;
		    i = diffang <= ANG180;
		} // confusing, aint it?


		st_facecount = ST_TURNCOUNT;
		st_faceindex = ST_calcPainOffset();

		if (diffang < ANG45)
		{
		    // head-on
		    st_faceindex += ST_RAMPAGEOFFSET;
		}
		else if (i)
		{
		    // turn face right
		    st_faceindex += ST_TURNOFFSET;
		}
		else
		{
		    // turn face left
		    st_faceindex += ST_TURNOFFSET+1;
		}
	    }
	}
    }

    if (priority < 7)
    {
	// getting hurt because of your own damn stupidity
	if (plyr->damagecount)
	{
	    if (plyr->health - st_oldhealth > ST_MUCHPAIN)
	    {
		priority = 7;
		st_facecount = ST_TURNCOUNT;
		st_faceindex = ST_calcPainOffset() + ST_OUCHOFFSET;
	    }
	    else
	    {
		priority = 6;
		st_facecount = ST_TURNCOUNT;
		st_faceindex = ST_calcPainOffset() + ST_RAMPAGEOFFSET;
	    }

	}

    }

    if (priority < 6)
    {
	// rapid firing
	if (plyr->attackdown)
	{
	    if (lastattackdown==-1)
		lastattackdown = ST_RAMPAGEDELAY;
	    else if (!--lastattackdown)
	    {
		priority = 5;
		st_faceindex = ST_calcPainOffset() + ST_RAMPAGEOFFSET;
		st_facecount = 1;
		lastattackdown = 1;
	    }
	}
	else
	    lastattackdown = -1;

    }

    if (priority < 5)
    {
	// invulnerability
	if ((plyr->cheats & CF_GODMODE)
	    || plyr->powers[pw_invulnerability])
	{
	    priority = 4;

	    st_faceindex = ST_GODFACE;
	    st_facecount = 1;

	}

    }

    // look left or look right if the facecount has timed out
    if (!st_facecount)
    {
	st_faceindex = ST_calcPainOffset() + (st_randomnumber % 3);
	st_facecount = ST_STRAIGHTFACECOUNT;
	priority = 0;
    }

    st_facecount--;

}

// Same table as StStuffTest.mc's FACE_SCRIPT: tics, health, damagecount,
// bonuscount, attacker spot (0 none), player angle (degrees),
// weaponowned bits, attackdown, cheats, invulnerability tics.
int script[][10] = {
    {40, 100, 0, 0, 0, 0, 3, 0, 0, 0},     // idle, looking around
    {1, 90, 10, 0, 1, 0, 3, 0, 0, 0},      // hit from the left
    {34, 90, 9, 0, 1, 0, 3, 0, 0, 0},
    {40, 90, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 80, 10, 0, 2, 0, 3, 0, 0, 0},      // hit from the right
    {40, 80, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 75, 8, 0, 3, 0, 3, 0, 0, 0},       // head-on
    {40, 75, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 72, 8, 0, 1, 90, 3, 0, 0, 0},      // left spot, facing it
    {40, 72, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 70, 8, 0, 4, 0, 3, 0, 0, 0},       // from behind
    {40, 70, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 68, 8, 0, 5, 0, 3, 0, 0, 0},       // front left diagonal
    {40, 68, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 66, 8, 0, 2, 270, 3, 0, 0, 0},     // right spot, facing it
    {40, 66, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 95, 5, 0, 1, 0, 3, 0, 0, 0},       // health up by 25 while hit: ouch
    {40, 95, 0, 0, 0, 0, 3, 0, 0, 0},
    {3, 60, 6, 0, 0, 0, 3, 0, 0, 0},       // hurt by the floor
    {1, 85, 3, 0, 0, 0, 3, 0, 0, 0},       // ... with the ouch bug
    {40, 85, 0, 0, 0, 0, 3, 0, 0, 0},
    {1, 85, 0, 6, 0, 0, 7, 0, 0, 0},       // picked up the shotgun
    {80, 85, 0, 5, 0, 0, 7, 0, 0, 0},
    {90, 85, 0, 0, 0, 0, 7, 1, 0, 0},      // holding fire
    {20, 85, 0, 0, 0, 0, 7, 0, 0, 0},
    {10, 85, 0, 0, 0, 0, 7, 0, 2, 0},      // iddqd
    {20, 85, 0, 0, 0, 0, 7, 0, 0, 0},
    {5, 85, 0, 0, 0, 0, 7, 0, 0, 30},      // invulnerability sphere
    {20, 85, 0, 0, 0, 0, 7, 0, 0, 0},
    {20, 15, 0, 0, 0, 0, 7, 0, 0, 0},      // nearly dead
    {5, 0, 0, 0, 0, 0, 7, 0, 0, 0},        // dead
};
fixed_t spots[][2] = {{0, 0}, {0, 100}, {0, -100}, {100, 10}, {-100, 5}, {70, 80}};

int main(void)
{
    int i, s, t, tic, nums[] = {0, 7, 50, 123, 999, 1000, 1994, -5, -42, -123};
    st_number_t n;
    boolean on = true;
    int num;

    // tall 3-digit number at ST_AMMOX, ST_AMMOY, then short 3-digit at
    // ST_AMMO0X, ST_AMMO0Y, then a 2-digit tall one (frags)
    n.on = &on;
    n.num = &num;
    for (i = 0; i < 10; i++) {
        num = nums[i];
        n.x = 44; n.y = 171; n.width = 3; n.p0 = &tallpatch; n.plump = 0;
        printf("tall %d: ", num); STlib_drawNum(&n, true); printf("\n");
        n.x = 288; n.y = 173; n.width = 3; n.p0 = &shortpatch; n.plump = 10;
        printf("short %d: ", num); STlib_drawNum(&n, true); printf("\n");
        n.x = 138; n.y = 171; n.width = 2; n.p0 = &tallpatch; n.plump = 0;
        printf("frags %d: ", num); STlib_drawNum(&n, true); printf("\n");
    }

    plyr->mo = &playermo;
    for (i = 0; i < NUMWEAPONS; i++)
        oldweaponsowned[i] = plyr->weaponowned[i] = (3 >> i) & 1;

    printf("faces: ");
    tic = 0;
    for (s = 0; s < sizeof(script) / sizeof(script[0]); s++) {
        int *c = script[s];
        for (t = 0; t < c[0]; t++) {
            plyr->health = c[1];
            plyr->damagecount = c[2];
            plyr->bonuscount = c[3];
            plyr->attacker = c[4] ? &badguy : NULL;
            badguy.x = spots[c[4]][0] << FRACBITS;
            badguy.y = spots[c[4]][1] << FRACBITS;
            playermo.angle = (ANG45 / 45) * c[5];
            for (i = 0; i < NUMWEAPONS; i++)
                plyr->weaponowned[i] = (c[6] >> i) & 1;
            plyr->attackdown = c[7];
            plyr->cheats = c[8];
            plyr->powers[pw_invulnerability] = c[9];

            // ST_Ticker with a fixed random number
            st_randomnumber = (tic * 37 + 11) & 255;
            ST_updateFaceWidget();
            st_oldhealth = plyr->health;
            printf("%d, ", st_faceindex);
            tic++;
        }
    }
    printf("\n%d tics\n", tic);
    return 0;
}
