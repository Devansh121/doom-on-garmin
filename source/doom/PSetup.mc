// p_setup.c
//
// Do all the WAD I/O, get map description,
//  set up initial state and misc. LUTs.
//
// Structs from r_defs.h are stored one array per field (vertexes_x[i] is
// vertexes[i].x) and pointers are indexes into those arrays, -1 for NULL.
//
// What P_LoadVertexes .. P_LoadSegs and P_GroupLines work out from the
// lumps never changes, so tools/wad2ciq.py does it at build time (the same
// steps and arithmetic) and writes each of the arrays below as its own
// jsonData resource. Loading a level is then one loadResource per array,
// with no raw lump and converted copy alive at the same time. Only the
// fields play changes start out here (validcount, thinglist, ...).
//
// The watchdog won't let a single callback load a whole level, so
// P_SetupLevel only resets state and P_SetupLevelStep does the loading
// one array (or a slice of the things) at a time.

import Toybox.Lang;
import Toybox.WatchUi;

(:extendedCode)
module PSetup {

    //
    // MAP related Lookup tables.
    // Store VERTEXES, LINEDEFS, SIDEDEFS, etc.
    //
    var numvertexes as Number = 0;
    var vertexes_x as Array<Number> = [] as Array<Number>;
    var vertexes_y as Array<Number> = [] as Array<Number>;

    var numsegs as Number = 0;
    var segs_v1 as Array<Number> = [] as Array<Number>;
    var segs_v2 as Array<Number> = [] as Array<Number>;
    var segs_offset as Array<Number> = [] as Array<Number>;
    var segs_angle as Array<Number> = [] as Array<Number>;
    var segs_sidedef as Array<Number> = [] as Array<Number>;
    var segs_linedef as Array<Number> = [] as Array<Number>;
    var segs_frontsector as Array<Number> = [] as Array<Number>;
    var segs_backsector as Array<Number> = [] as Array<Number>;

    var numsectors as Number = 0;
    var sectors_floorheight as Array<Number> = [] as Array<Number>;
    var sectors_ceilingheight as Array<Number> = [] as Array<Number>;
    var sectors_floorpic as Array<Number> = [] as Array<Number>;
    var sectors_ceilingpic as Array<Number> = [] as Array<Number>;
    var sectors_lightlevel as Array<Number> = [] as Array<Number>;
    var sectors_special as Array<Number> = [] as Array<Number>;
    var sectors_tag as Array<Number> = [] as Array<Number>;
    // if == validcount, already checked
    var sectors_validcount as Array<Number> = [] as Array<Number>;
    // mapblock bounding box for height changes, 4 per sector
    var sectors_blockbox as Array<Number> = [] as Array<Number>;
    // origin for any sounds played by the sector
    var sectors_soundorg_x as Array<Number> = [] as Array<Number>;
    var sectors_soundorg_y as Array<Number> = [] as Array<Number>;
    var sectors_linecount as Array<Number> = [] as Array<Number>;
    // list of mobjs in sector, -1 for none
    var sectors_thinglist as Array<Number> = [] as Array<Number>;
    // thinker_t for reversable actions, -1 for none
    var sectors_specialdata as Array<Number> = [] as Array<Number>;
    // 0 = untraversed, 1,2 = sndlines -1
    var sectors_soundtraversed as Array<Number> = [] as Array<Number>;
    // thing that made a sound (or null)
    var sectors_soundtarget as Array<Number> = [] as Array<Number>;
    // index of the sector's first entry in linebuffer
    var sectors_lines as Array<Number> = [] as Array<Number>;

    var numsubsectors as Number = 0;
    var subsectors_sector as Array<Number> = [] as Array<Number>;
    var subsectors_numlines as Array<Number> = [] as Array<Number>;
    var subsectors_firstline as Array<Number> = [] as Array<Number>;

    var numnodes as Number = 0;
    var nodes_x as Array<Number> = [] as Array<Number>;
    var nodes_y as Array<Number> = [] as Array<Number>;
    var nodes_dx as Array<Number> = [] as Array<Number>;
    var nodes_dy as Array<Number> = [] as Array<Number>;
    // bbox[2][4] per node, flattened: nodes_bbox[i*8 + side*4 + k]
    var nodes_bbox as Array<Number> = [] as Array<Number>;
    // children[2] per node: nodes_children[i*2 + side]
    var nodes_children as Array<Number> = [] as Array<Number>;

    var numlines as Number = 0;
    var lines_v1 as Array<Number> = [] as Array<Number>;
    var lines_v2 as Array<Number> = [] as Array<Number>;
    var lines_dx as Array<Number> = [] as Array<Number>;
    var lines_dy as Array<Number> = [] as Array<Number>;
    var lines_flags as Array<Number> = [] as Array<Number>;
    var lines_special as Array<Number> = [] as Array<Number>;
    var lines_tag as Array<Number> = [] as Array<Number>;
    // sidenum[2] per line: lines_sidenum[i*2 + side]
    var lines_sidenum as Array<Number> = [] as Array<Number>;
    // (line_t's bbox isn't stored, PMap works it out)
    var lines_slopetype as Array<Number> = [] as Array<Number>;
    var lines_frontsector as Array<Number> = [] as Array<Number>;
    var lines_backsector as Array<Number> = [] as Array<Number>;
    var lines_validcount as Array<Number> = [] as Array<Number>;
    // (line_t's specialdata isn't kept: nothing in the C code uses it)

    var numsides as Number = 0;
    var sides_textureoffset as Array<Number> = [] as Array<Number>;
    var sides_rowoffset as Array<Number> = [] as Array<Number>;
    var sides_toptexture as Array<Number> = [] as Array<Number>;
    var sides_bottomtexture as Array<Number> = [] as Array<Number>;
    var sides_midtexture as Array<Number> = [] as Array<Number>;
    var sides_sector as Array<Number> = [] as Array<Number>;

    // BLOCKMAP
    // Created from axis aligned bounding box
    // of the map, a rectangular array of
    // blocks of size ...
    // Used to speed up collision detection
    // by spatial subdivision in 2D.
    //
    // Blockmap size.
    var bmapwidth as Number = 0;
    var bmapheight as Number = 0;  // size in mapblocks
    // the whole lump, packed two entries per number: read it with
    // P_BlockmapLump. blockmap offsets start at entry 4
    var blockmaplump as Array<Number> = [] as Array<Number>;
    // origin of block map
    var bmaporgx as Number = 0;
    var bmaporgy as Number = 0;
    // for thing chains: first mobj in each block, -1 for none
    var blocklinks as Array<Number> = [] as Array<Number>;

    // REJECT
    // For fast sight rejection.
    // Speeds up enemy AI by skipping detailed
    //  LineOf Sight calculation.
    // Without special effect, this could be
    //  used as a PVS lookup as well.
    //
    // one number per byte of the lump
    var rejectmatrix as Array<Number> = [] as Array<Number>;

    // sectors[i].lines for every sector, back to back
    var linebuffer as Array<Number> = [] as Array<Number>;

    //
    // Loading state for P_SetupLevelStep.
    //
    var lumps as Array<ResourceId>? = null;
    var setupstep as Number = 0;
    var setupindex as Number = 0;
    // the THINGS lump while P_LoadThings runs
    var data as Array<Number> = [] as Array<Number>;

    // Things handled per P_SetupLevelStep call, chosen to stay well under
    // the watchdog limit. P_SpawnMapThing searches mobjinfo (up to
    // NUMMOBJTYPES) and P_SpawnMobj walks the BSP for every thing.
    const THINGCHUNK = 8;

    // One of the current map's arrays, by its MapLumps index.
    function W_LevelData(k as Number) as Array<Number> {
        return WatchUi.loadResource((lumps as Array<ResourceId>)[k]) as Array<Number>;
    }

    function newArray(n as Number) as Array<Number> {
        return new [n] as Array<Number>;
    }

    // n copies of v
    function filledArray(n as Number, v as Number) as Array<Number> {
        var a = new [n] as Array<Number>;
        for (var i = 0; i < n; i++) {
            a[i] = v;
        }
        return a;
    }

    //
    // P_LoadThings
    //
    function P_LoadThings(first as Number, last as Number) as Void {
        var mt = data;
        for (var i = first; i < last; i++) {
            var m = i * 5;
            var type = mt[m + 3];
            var spawn = true;

            // Do not spawn cool, new monsters if !commercial
            // (always true here, the shareware IWAD is all we load)
            switch (type) {
                case 68:  // Arachnotron
                case 64:  // Archvile
                case 88:  // Boss Brain
                case 89:  // Boss Shooter
                case 69:  // Hell Knight
                case 67:  // Mancubus
                case 71:  // Pain Elemental
                case 65:  // Former Human Commando
                case 66:  // Revenant
                case 84:  // Wolf SS
                    spawn = false;
                    break;
            }
            if (spawn == false) {
                // The C code breaks out of the loop here too, which
                // skips every remaining thing in the map.
                setupindex = numthings;
                return;
            }

            // Do spawn all other stuff.
            PMobj.P_SpawnMapThing([mt[m], mt[m + 1], mt[m + 2], type, mt[m + 4]]);
        }
    }

    var numthings as Number = 0;

    // blockmaplump[k]. The lump is packed two shorts per number (see
    // wad2ciq.py): even k is the low half, odd k the high half.
    function P_BlockmapLump(k as Number) as Number {
        var w = blockmaplump[k >> 1];
        return (k & 1) != 0 ? w >> 16 : (w << 16) >> 16;
    }

    //
    // P_LoadBlockMap
    //
    function P_LoadBlockMap() as Void {
        // SHORT() byte swapping isn't needed, wad2ciq.py already
        // unpacked the lump as little-endian shorts.
        blockmaplump = W_LevelData(MapLumps.BLOCKMAP);

        bmaporgx = P_BlockmapLump(0) << MFixed.FRACBITS;
        bmaporgy = P_BlockmapLump(1) << MFixed.FRACBITS;
        bmapwidth = P_BlockmapLump(2);
        bmapheight = P_BlockmapLump(3);

        // clear out mobj chains
        var count = bmapwidth * bmapheight;
        blocklinks = newArray(count);
        for (var i = 0; i < count; i++) {
            blocklinks[i] = -1;
        }
    }

    // How many mobjs P_LoadThings will spawn: the same tests P_SpawnMapThing
    // makes before spawning (single player, the current skill), so the
    // thinker pool isn't sized for things that never appear. E1M6 has 463
    // things in its lump but far fewer at any one skill, and every pool
    // slot costs about 40 array entries.
    function P_CountSpawnedThings(mt as Array<Number>) as Number {
        var bit;
        if (DoomStat.gameskill == DoomDef.sk_baby) {
            bit = 1;
        } else if (DoomStat.gameskill == DoomDef.sk_nightmare) {
            bit = 4;
        } else {
            bit = 1 << (DoomStat.gameskill - 1);
        }
        var count = 1;  // the player
        for (var i = 0; i < mt.size(); i += 5) {
            var type = mt[i + 3];
            var options = mt[i + 4];
            if (type == 11 || type <= 4) {
                continue;  // deathmatch and player starts
            }
            if (!DoomStat.netgame && (options & 16) != 0) {
                continue;
            }
            if ((options & bit) != 0) {
                count++;
            }
        }
        return count;
    }

    //
    // P_SetupLevel
    //
    function P_SetupLevel(episode as Number, map as Number) as Void {
        // find map name
        var lumpname = "E" + episode + "M" + map;
        var maplumps = MapLumps.W_MapLumps(lumpname);
        if (maplumps == null) {
            ISystem.I_Error("W_GetNumForName: " + lumpname + " not found!");
        }

        DoomStat.totalkills = 0;
        DoomStat.totalitems = 0;
        DoomStat.totalsecret = 0;
        for (var i = 0; i < DoomStat.MAXPLAYERS; i++) {
            DPlayer.players_killcount[i] = 0;
            DPlayer.players_secretcount[i] = 0;
            DPlayer.players_itemcount[i] = 0;
            DoomStat.playerstarts[i] = null;
        }

        // Z_FreeTags (PU_LEVEL, PU_PURGELEVEL-1): let go of the last
        // level before loading this one, so the two are never in memory
        // together.
        P_FreeLevel();
        lumps = maplumps;

        // Size the thinker pool for the things that will actually spawn.
        PTick.P_InitThinkers(P_CountSpawnedThings(W_LevelData(MapLumps.THINGS)));
        PTick.leveltime = 0;
        setupstep = 0;
        setupindex = 0;
    }

    // Runs one step of the loading P_SetupLevel does in the C code.
    // Returns true once the level is fully set up.
    //
    // note: most of this ordering is important
    function P_SetupLevelStep() as Boolean {
        switch (setupstep) {
            case 0:
                P_LoadBlockMap();
                break;

            // P_LoadVertexes
            case 1:
                vertexes_x = W_LevelData(MapLumps.VERTEXES_X);
                numvertexes = vertexes_x.size();
                break;
            case 2:
                vertexes_y = W_LevelData(MapLumps.VERTEXES_Y);
                break;

            // P_LoadSectors
            case 3:
                sectors_floorheight = W_LevelData(MapLumps.SECTORS_FLOORHEIGHT);
                numsectors = sectors_floorheight.size();
                break;
            case 4:
                sectors_ceilingheight = W_LevelData(MapLumps.SECTORS_CEILINGHEIGHT);
                break;
            case 5:
                // R_FlatNumForName was resolved by tools/wad2ciq.py
                sectors_floorpic = W_LevelData(MapLumps.SECTORS_FLOORPIC);
                break;
            case 6:
                sectors_ceilingpic = W_LevelData(MapLumps.SECTORS_CEILINGPIC);
                break;
            case 7:
                sectors_lightlevel = W_LevelData(MapLumps.SECTORS_LIGHTLEVEL);
                break;
            case 8:
                sectors_special = W_LevelData(MapLumps.SECTORS_SPECIAL);
                break;
            case 9:
                sectors_tag = W_LevelData(MapLumps.SECTORS_TAG);
                break;
            case 10:
                sectors_validcount = filledArray(numsectors, 0);
                sectors_thinglist = filledArray(numsectors, -1);
                sectors_specialdata = filledArray(numsectors, -1);
                sectors_soundtraversed = filledArray(numsectors, 0);
                sectors_soundtarget = filledArray(numsectors, -1);
                break;

            // P_LoadSideDefs
            case 11:
                sides_textureoffset = W_LevelData(MapLumps.SIDES_TEXTUREOFFSET);
                numsides = sides_textureoffset.size();
                break;
            case 12:
                sides_rowoffset = W_LevelData(MapLumps.SIDES_ROWOFFSET);
                break;
            case 13:
                // R_TextureNumForName was resolved by tools/wad2ciq.py
                sides_toptexture = W_LevelData(MapLumps.SIDES_TOPTEXTURE);
                break;
            case 14:
                sides_bottomtexture = W_LevelData(MapLumps.SIDES_BOTTOMTEXTURE);
                break;
            case 15:
                sides_midtexture = W_LevelData(MapLumps.SIDES_MIDTEXTURE);
                break;
            case 16:
                sides_sector = W_LevelData(MapLumps.SIDES_SECTOR);
                break;

            // P_LoadLineDefs
            case 17:
                lines_v1 = W_LevelData(MapLumps.LINES_V1);
                numlines = lines_v1.size();
                break;
            case 18:
                lines_v2 = W_LevelData(MapLumps.LINES_V2);
                break;
            case 19:
                lines_dx = W_LevelData(MapLumps.LINES_DX);
                break;
            case 20:
                lines_dy = W_LevelData(MapLumps.LINES_DY);
                break;
            case 21:
                lines_flags = W_LevelData(MapLumps.LINES_FLAGS);
                break;
            case 22:
                lines_special = W_LevelData(MapLumps.LINES_SPECIAL);
                break;
            case 23:
                // one spare slot past the last line: the "line_t junk"
                // p_enemy passes to EV_DoDoor / EV_DoFloor
                lines_tag = W_LevelData(MapLumps.LINES_TAG);
                break;
            case 24:
                lines_sidenum = W_LevelData(MapLumps.LINES_SIDENUM);
                break;
            case 25:
                // (line_t's bbox isn't stored, PMap works it out)
                lines_slopetype = W_LevelData(MapLumps.LINES_SLOPETYPE);
                break;
            case 26:
                lines_frontsector = W_LevelData(MapLumps.LINES_FRONTSECTOR);
                break;
            case 27:
                lines_backsector = W_LevelData(MapLumps.LINES_BACKSECTOR);
                break;
            case 28:
                lines_validcount = filledArray(numlines, 0);
                break;

            // P_LoadSubsectors
            case 29:
                subsectors_numlines = W_LevelData(MapLumps.SUBSECTORS_NUMLINES);
                numsubsectors = subsectors_numlines.size();
                break;
            case 30:
                subsectors_firstline = W_LevelData(MapLumps.SUBSECTORS_FIRSTLINE);
                break;

            // P_LoadNodes
            case 31:
                nodes_x = W_LevelData(MapLumps.NODES_X);
                numnodes = nodes_x.size();
                break;
            case 32:
                nodes_y = W_LevelData(MapLumps.NODES_Y);
                break;
            case 33:
                nodes_dx = W_LevelData(MapLumps.NODES_DX);
                break;
            case 34:
                nodes_dy = W_LevelData(MapLumps.NODES_DY);
                break;
            case 35:
                nodes_bbox = W_LevelData(MapLumps.NODES_BBOX);
                break;
            case 36:
                nodes_children = W_LevelData(MapLumps.NODES_CHILDREN);
                break;

            // P_LoadSegs
            case 37:
                segs_v1 = W_LevelData(MapLumps.SEGS_V1);
                numsegs = segs_v1.size();
                break;
            case 38:
                segs_v2 = W_LevelData(MapLumps.SEGS_V2);
                break;
            case 39:
                segs_offset = W_LevelData(MapLumps.SEGS_OFFSET);
                break;
            case 40:
                segs_angle = W_LevelData(MapLumps.SEGS_ANGLE);
                break;
            case 41:
                segs_sidedef = W_LevelData(MapLumps.SEGS_SIDEDEF);
                break;
            case 42:
                segs_linedef = W_LevelData(MapLumps.SEGS_LINEDEF);
                break;
            case 43:
                segs_frontsector = W_LevelData(MapLumps.SEGS_FRONTSECTOR);
                break;
            case 44:
                segs_backsector = W_LevelData(MapLumps.SEGS_BACKSECTOR);
                break;

            case 45:
                rejectmatrix = W_LevelData(MapLumps.REJECT);
                break;

            // P_GroupLines
            case 46:
                subsectors_sector = W_LevelData(MapLumps.SUBSECTORS_SECTOR);
                break;
            case 47:
                linebuffer = W_LevelData(MapLumps.LINEBUFFER);
                break;
            case 48:
                sectors_lines = W_LevelData(MapLumps.SECTORS_LINES);
                break;
            case 49:
                sectors_linecount = W_LevelData(MapLumps.SECTORS_LINECOUNT);
                break;
            case 50:
                sectors_blockbox = W_LevelData(MapLumps.SECTORS_BLOCKBOX);
                break;
            case 51:
                sectors_soundorg_x = W_LevelData(MapLumps.SECTORS_SOUNDORG_X);
                break;
            case 52:
                sectors_soundorg_y = W_LevelData(MapLumps.SECTORS_SOUNDORG_Y);
                break;

            case 53:
                if (setupindex == 0) {
                    data = W_LevelData(MapLumps.THINGS);
                    numthings = data.size() / 5;
                }
                return slice(numthings, THINGCHUNK, new Lang.Method(PSetup, :P_LoadThings));

            default:
                data = [] as Array<Number>;
                // clear special respawning que
                PMobj.iquehead = 0;
                PMobj.iquetail = 0;

                // set up world state
                PSpec.P_SpawnSpecials();
                return true;
        }
        return nextStep();
    }

    // Z_FreeTags for the level's arrays.
    function P_FreeLevel() as Void {
        var none = [] as Array<Number>;
        vertexes_x = none;
        vertexes_y = none;
        segs_v1 = none;
        segs_v2 = none;
        segs_offset = none;
        segs_angle = none;
        segs_sidedef = none;
        segs_linedef = none;
        segs_frontsector = none;
        segs_backsector = none;
        sectors_floorheight = none;
        sectors_ceilingheight = none;
        sectors_floorpic = none;
        sectors_ceilingpic = none;
        sectors_lightlevel = none;
        sectors_special = none;
        sectors_tag = none;
        sectors_validcount = none;
        sectors_blockbox = none;
        sectors_soundorg_x = none;
        sectors_soundorg_y = none;
        sectors_linecount = none;
        sectors_thinglist = none;
        sectors_specialdata = none;
        sectors_soundtraversed = none;
        sectors_soundtarget = none;
        sectors_lines = none;
        subsectors_sector = none;
        subsectors_numlines = none;
        subsectors_firstline = none;
        nodes_x = none;
        nodes_y = none;
        nodes_dx = none;
        nodes_dy = none;
        nodes_bbox = none;
        nodes_children = none;
        lines_v1 = none;
        lines_v2 = none;
        lines_dx = none;
        lines_dy = none;
        lines_flags = none;
        lines_special = none;
        lines_tag = none;
        lines_sidenum = none;
        lines_slopetype = none;
        lines_frontsector = none;
        lines_backsector = none;
        lines_validcount = none;
        sides_textureoffset = none;
        sides_rowoffset = none;
        sides_toptexture = none;
        sides_bottomtexture = none;
        sides_midtexture = none;
        sides_sector = none;
        blockmaplump = none;
        blocklinks = none;
        rejectmatrix = none;
        linebuffer = none;
        data = none;
    }

    //
    // P_Init
    //
    function P_Init() as Void {
        PSwitch.P_InitSwitchList();
        PSpec.P_InitPicAnims();
        RThings.R_InitSprites(Info.sprnames);
    }

    // Runs fn over the next count records of the current step, moving on
    // to the next step when the lump is done.
    function slice(total as Number, count as Number, fn as Method) as Boolean {
        var first = setupindex;
        var last = first + count < total ? first + count : total;
        fn.invoke(first, last);
        // P_LoadThings can jump setupindex to the end on its own.
        setupindex = setupindex > last ? setupindex : last;
        if (setupindex >= total) {
            return nextStep();
        }
        return false;
    }

    function nextStep() as Boolean {
        setupstep++;
        setupindex = 0;
        return false;
    }
}
