// Reference values for testRecursiveSound in test/PEnemyTest.mc.
// P_RecursiveSound is verbatim from linuxdoom-1.10 p_enemy.c and
// P_LineOpening from p_maputl.c; the structs keep just the fields they
// use. Lines are loaded like P_LoadLineDefs and grouped into sectors like
// P_GroupLines. Same input as test/maputl_ref.c, from the repo root:
//
//   python3 -c "import json;[print(len(d),*d) for n in ['vertexes','linedefs','sidedefs','sectors','blockmap'] for d in [json.load(open(f'generated/resources/e1m1_{n}.json'))]]" > e1m1.txt
//   gcc test/sound_ref.c -o sound_ref && ./sound_ref < e1m1.txt
#include <stdio.h>
#include <stdlib.h>

typedef int fixed_t;
#define FRACBITS 16
#define ML_TWOSIDED 4
#define ML_SOUNDBLOCK 64

typedef struct line_s line_t;
typedef struct {
    fixed_t floorheight, ceilingheight;
    int validcount;
    int soundtraversed;
    void* soundtarget;
    int linecount;
    line_t** lines;
} sector_t;
typedef struct { sector_t* sector; } side_t;
struct line_s {
    int flags;
    short sidenum[2];
    sector_t* frontsector; sector_t* backsector;
};

line_t lines[2048]; int numlines;
side_t sides[4096]; int numsides;
sector_t sectors[512]; int numsectors;
line_t* linebuffer[4096];
int validcount = 1;
fixed_t opentop, openbottom, openrange, lowfloor;

// ---- copied from p_maputl.c ----
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
// ---- end of copied code ----

// ---- copied from p_enemy.c ----
void*		soundtarget;

void
P_RecursiveSound
( sector_t*	sec,
  int		soundblocks )
{
    int		i;
    line_t*	check;
    sector_t*	other;
	
    // wake up all monsters in this sector
    if (sec->validcount == validcount
	&& sec->soundtraversed <= soundblocks+1)
    {
	return;		// already flooded
    }
    
    sec->validcount = validcount;
    sec->soundtraversed = soundblocks+1;
    sec->soundtarget = soundtarget;
	
    for (i=0 ;i<sec->linecount ; i++)
    {
	check = sec->lines[i];
	if (! (check->flags & ML_TWOSIDED) )
	    continue;
	
	P_LineOpening (check);

	if (openrange <= 0)
	    continue;	// closed door
	
	if ( sides[ check->sidenum[0] ].sector == sec)
	    other = sides[ check->sidenum[1] ] .sector;
	else
	    other = sides[ check->sidenum[0] ].sector;
	
	if (check->flags & ML_SOUNDBLOCK)
	{
	    if (!soundblocks)
		P_RecursiveSound (other, 1);
	}
	else
	    P_RecursiveSound (other, soundblocks);
    }
}
// ---- end of copied code ----

int rd(void) { int v; if (scanf("%d", &v) != 1) { fprintf(stderr, "short input\n"); exit(1); } return v; }

int main(void) {
    int i, j, n, v[7];
    static int mld[2048 * 7], msd[4096 * 6];
    n = rd();
    for (i = 0; i < n; i++) rd();   // vertexes aren't needed
    n = rd();
    for (i = 0; i < n; i++) mld[i] = rd();
    numlines = n / 7;
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
        ld->flags = m[2];
        ld->sidenum[0] = m[5];
        ld->sidenum[1] = m[6];
        ld->frontsector = ld->sidenum[0] != -1 ? sides[ld->sidenum[0]].sector : 0;
        ld->backsector = ld->sidenum[1] != -1 ? sides[ld->sidenum[1]].sector : 0;
    }
    // P_GroupLines
    line_t** buf = linebuffer;
    for (i = 0; i < numsectors; i++) {
        sectors[i].lines = buf;
        for (j = 0; j < numlines; j++) {
            if (lines[j].frontsector == &sectors[i] || lines[j].backsector == &sectors[i]) {
                *buf++ = &lines[j];
                sectors[i].linecount++;
            }
        }
    }

    // P_NoiseAlert from a few sectors: soundtraversed of every sector
    // flooded by that noise, 0 for the rest
    // E1M1 has no sound blocking lines, so the second half of the runs
    // marks every fifth line as one
    static const int starts[] = { 0, 20, 37, 60, 84 };
    printf("    // start sector, soundblock every fifth line, soundtraversed per sector\n");
    printf("    var sound = [\n");
    for (i = 0; i < 10; i++) {
        if (i == 5)
            for (j = 0; j < numlines; j += 5)
                lines[j].flags |= ML_SOUNDBLOCK;
        soundtarget = &i;
        validcount++;
        P_RecursiveSound(&sectors[starts[i % 5]], 0);
        printf("        [%d, %s, \"", starts[i % 5], i >= 5 ? "true" : "false");
        for (j = 0; j < numsectors; j++)
            printf("%d", sectors[j].validcount == validcount ? sectors[j].soundtraversed : 0);
        printf("\"]%s\n", i < 9 ? "," : "");
    }
    printf("    ];\n");
    return 0;
}
