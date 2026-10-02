// p_setup.c
//
// Do all the WAD I/O, get map description,
//  set up initial state and misc. LUTs.
//
// Structs from r_defs.h are stored one array per field (sectors_tag[i] is
// sectors[i].tag) and pointers are indexes into those arrays, -1 for NULL.
//
// Every element of a Monkey C array costs the same whatever it holds, so
// fields that fit in 16 bits are kept two per number (see pack16 in
// tools/wad2ciq.py), named after both: vertexes_xy[i] is x | y << 16.
// Fields whose values always fit in 0..255 are ByteArrays, 1 byte per
// value. The halves of a packed number are read back with shifts and
// masks on the spot, not with helper functions, because on the watch a
// call costs about 100 times a local operation:
//   x << FRACBITS (low half)   w << 16
//   y << FRACBITS (high half)  w & ~0xffff
//   unsigned low half          w & 0xffff
//   signed high half           w >> 16
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
import Toybox.StringUtil;
import Toybox.WatchUi;

(:extendedCode)
module PSetup {

    //
    // MAP related Lookup tables.
    // Store VERTEXES, LINEDEFS, SIDEDEFS, etc.
    //
    var numvertexes as Number = 0;
    // x | y << 16, in map units
    var vertexes_xy as Array<Number> = [] as Array<Number>;

    var numsegs as Number = 0;
    // v1 | v2 << 16
    var segs_v1v2 as Array<Number> = [] as Array<Number>;
    // offset | angle << 16 (both are shorts << 16 in seg_t, so offset is
    // w << 16 and angle w & ~0xffff)
    var segs_offsetangle as Array<Number> = [] as Array<Number>;
    // sidedef | linedef << 16
    var segs_sidedeflinedef as Array<Number> = [] as Array<Number>;
    // frontsector | backsector << 16, backsector -1 for none
    var segs_sectors as Array<Number> = [] as Array<Number>;

    var numsectors as Number = 0;
    var sectors_floorheight as Array<Number> = [] as Array<Number>;
    var sectors_ceilingheight as Array<Number> = [] as Array<Number>;
    var sectors_floorpic as ByteArray = []b;
    var sectors_ceilingpic as ByteArray = []b;
    var sectors_lightlevel as Array<Number> = [] as Array<Number>;
    var sectors_special as ByteArray = []b;
    var sectors_tag as Array<Number> = [] as Array<Number>;
    // if == validcount, already checked
    var sectors_validcount as Array<Number> = [] as Array<Number>;
    // mapblock bounding box for height changes, one byte each:
    // blockbox[k] is (w >> (k << 3)) & 0xff
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
    var sectors_soundtraversed as ByteArray = []b;
    // thing that made a sound (or null)
    var sectors_soundtarget as Array<Number> = [] as Array<Number>;
    // index of the sector's first entry in linebuffer
    var sectors_lines as Array<Number> = [] as Array<Number>;

    var numsubsectors as Number = 0;
    var subsectors_sector as Array<Number> = [] as Array<Number>;
    // firstline | numlines << 16
    var subsectors_lines as Array<Number> = [] as Array<Number>;

    var numnodes as Number = 0;
    // x | y << 16 and dx | dy << 16, in map units
    var nodes_xy as Array<Number> = [] as Array<Number>;
    var nodes_dxdy as Array<Number> = [] as Array<Number>;
    // bbox[2][4] per node, top | bottom << 16 then left | right << 16 for
    // each side, in map units: bbox[side][k] is in nodes_bbox[i*4 +
    // side*2 + (k >> 1)]
    var nodes_bbox as Array<Number> = [] as Array<Number>;
    // children[0] | children[1] << 16, both unsigned: children[side] is
    // (w >> (side << 4)) & 0xffff
    var nodes_children as Array<Number> = [] as Array<Number>;

    var numlines as Number = 0;
    // v1 | v2 << 16
    var lines_v1v2 as Array<Number> = [] as Array<Number>;
    // dx | dy << 16, in map units
    var lines_dxdy as Array<Number> = [] as Array<Number>;
    var lines_flags as Array<Number> = [] as Array<Number>;
    var lines_special as ByteArray = []b;
    var lines_tag as Array<Number> = [] as Array<Number>;
    // sidenum[0] | sidenum[1] << 16, sidenum[1] is -1 for one sided
    // lines. sidenum[side] is (w << ((side ^ 1) << 4)) >> 16.
    var lines_sidenums as Array<Number> = [] as Array<Number>;
    // (line_t's bbox isn't stored, PMap works it out)
    var lines_slopetype as ByteArray = []b;
    // frontsector | backsector << 16, backsector -1 for none
    var lines_sectors as Array<Number> = [] as Array<Number>;
    var lines_validcount as Array<Number> = [] as Array<Number>;
    // (line_t's specialdata isn't kept: nothing in the C code uses it)

    var numsides as Number = 0;
    var sides_textureoffset as Array<Number> = [] as Array<Number>;
    // (rowoffset isn't kept: walls are drawn without texturemid, so
    // nothing reads it)
    // toptexture | bottomtexture << 10 | midtexture << 20: top is
    // w & 0x3ff, bottom (w >> 10) & 0x3ff and mid w >> 20
    var sides_textures as Array<Number> = [] as Array<Number>;
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

    // One of the current map's arrays, by its MapLumps index. Byte arrays
    // are stored as base64 strings (see wad2ciq.py), which the system
    // decodes in one call.
    function W_LevelData(k as Number) as Array<Number> or ByteArray {
        var r = WatchUi.loadResource((lumps as Array<ResourceId>)[k]);
        if (r instanceof String) {
            return StringUtil.convertEncodedString(r, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            }) as ByteArray;
        }
        return r as Array<Number>;
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
        blockmaplump = W_LevelData(MapLumps.BLOCKMAP) as Array<Number>;

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
        PTick.P_InitThinkers(P_CountSpawnedThings(W_LevelData(MapLumps.THINGS) as Array<Number>));
        PTick.leveltime = 0;
        setupstep = 0;
        setupindex = 0;
    }

    // Runs one step of the loading P_SetupLevel does in the C code.
    // Returns true once the level is fully set up.
    function P_SetupLevelStep() as Boolean {
        var step = setupstep;
        // P_LoadBlockMap .. P_GroupLines: one array per step
        if (step < MapLumps.NUMARRAYS) {
            if (step == MapLumps.BLOCKMAP) {
                P_LoadBlockMap();
            } else if (step != MapLumps.THINGS) {
                P_LoadArray(step, W_LevelData(step));
            }
            return nextStep();
        }

        switch (step - MapLumps.NUMARRAYS) {
            case 0:
                // the fields play changes
                sectors_validcount = filledArray(numsectors, 0);
                sectors_thinglist = filledArray(numsectors, -1);
                sectors_specialdata = filledArray(numsectors, -1);
                sectors_soundtraversed = new [numsectors]b;
                sectors_soundtarget = filledArray(numsectors, -1);
                lines_validcount = filledArray(numlines, 0);
                return nextStep();

            case 1:
                if (setupindex == 0) {
                    data = W_LevelData(MapLumps.THINGS) as Array<Number>;
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
    }

    // Keeps array a as the current level's MapLumps array k.
    function P_LoadArray(k as Number, a as Array<Number> or ByteArray) as Void {
        switch (k) {
            case MapLumps.VERTEXES_XY:
                vertexes_xy = a as Array<Number>;
                numvertexes = a.size();
                break;
            case MapLumps.SECTORS_FLOORHEIGHT:
                sectors_floorheight = a as Array<Number>;
                numsectors = a.size();
                break;
            case MapLumps.SECTORS_CEILINGHEIGHT:
                sectors_ceilingheight = a as Array<Number>;
                break;
            case MapLumps.SECTORS_FLOORPIC:
                // R_FlatNumForName was resolved by tools/wad2ciq.py
                sectors_floorpic = a as ByteArray;
                break;
            case MapLumps.SECTORS_CEILINGPIC:
                sectors_ceilingpic = a as ByteArray;
                break;
            case MapLumps.SECTORS_LIGHTLEVEL:
                sectors_lightlevel = a as Array<Number>;
                break;
            case MapLumps.SECTORS_SPECIAL:
                sectors_special = a as ByteArray;
                break;
            case MapLumps.SECTORS_TAG:
                sectors_tag = a as Array<Number>;
                break;
            case MapLumps.SIDES_TEXTUREOFFSET:
                sides_textureoffset = a as Array<Number>;
                numsides = a.size();
                break;
            case MapLumps.SIDES_TEXTURES:
                // R_TextureNumForName was resolved by tools/wad2ciq.py
                sides_textures = a as Array<Number>;
                break;
            case MapLumps.SIDES_SECTOR:
                sides_sector = a as Array<Number>;
                break;
            case MapLumps.LINES_V1V2:
                lines_v1v2 = a as Array<Number>;
                numlines = a.size();
                break;
            case MapLumps.LINES_DXDY:
                lines_dxdy = a as Array<Number>;
                break;
            case MapLumps.LINES_FLAGS:
                lines_flags = a as Array<Number>;
                break;
            case MapLumps.LINES_SPECIAL:
                lines_special = a as ByteArray;
                break;
            case MapLumps.LINES_TAG:
                // one spare slot past the last line: the "line_t junk"
                // p_enemy passes to EV_DoDoor / EV_DoFloor
                lines_tag = a as Array<Number>;
                break;
            case MapLumps.LINES_SIDENUMS:
                lines_sidenums = a as Array<Number>;
                break;
            case MapLumps.LINES_SLOPETYPE:
                // (line_t's bbox isn't stored, PMap works it out)
                lines_slopetype = a as ByteArray;
                break;
            case MapLumps.LINES_SECTORS:
                lines_sectors = a as Array<Number>;
                break;
            case MapLumps.SUBSECTORS_LINES:
                subsectors_lines = a as Array<Number>;
                numsubsectors = a.size();
                break;
            case MapLumps.NODES_XY:
                nodes_xy = a as Array<Number>;
                numnodes = a.size();
                break;
            case MapLumps.NODES_DXDY:
                nodes_dxdy = a as Array<Number>;
                break;
            case MapLumps.NODES_BBOX:
                nodes_bbox = a as Array<Number>;
                break;
            case MapLumps.NODES_CHILDREN:
                nodes_children = a as Array<Number>;
                break;
            case MapLumps.SEGS_V1V2:
                segs_v1v2 = a as Array<Number>;
                numsegs = a.size();
                break;
            case MapLumps.SEGS_OFFSETANGLE:
                segs_offsetangle = a as Array<Number>;
                break;
            case MapLumps.SEGS_SIDEDEFLINEDEF:
                segs_sidedeflinedef = a as Array<Number>;
                break;
            case MapLumps.SEGS_SECTORS:
                segs_sectors = a as Array<Number>;
                break;
            case MapLumps.REJECT:
                rejectmatrix = a as Array<Number>;
                break;
            case MapLumps.SUBSECTORS_SECTOR:
                subsectors_sector = a as Array<Number>;
                break;
            case MapLumps.LINEBUFFER:
                linebuffer = a as Array<Number>;
                break;
            case MapLumps.SECTORS_LINES:
                sectors_lines = a as Array<Number>;
                break;
            case MapLumps.SECTORS_LINECOUNT:
                sectors_linecount = a as Array<Number>;
                break;
            case MapLumps.SECTORS_BLOCKBOX:
                sectors_blockbox = a as Array<Number>;
                break;
            case MapLumps.SECTORS_SOUNDORG_X:
                sectors_soundorg_x = a as Array<Number>;
                break;
            case MapLumps.SECTORS_SOUNDORG_Y:
                sectors_soundorg_y = a as Array<Number>;
                break;
        }
    }

    // Z_FreeTags for the level's arrays.
    function P_FreeLevel() as Void {
        var none = [] as Array<Number>;
        vertexes_xy = none;
        segs_v1v2 = none;
        segs_offsetangle = none;
        segs_sidedeflinedef = none;
        segs_sectors = none;
        sectors_floorheight = none;
        sectors_ceilingheight = none;
        sectors_floorpic = []b;
        sectors_ceilingpic = []b;
        sectors_lightlevel = none;
        sectors_special = []b;
        sectors_tag = none;
        sectors_validcount = none;
        sectors_blockbox = none;
        sectors_soundorg_x = none;
        sectors_soundorg_y = none;
        sectors_linecount = none;
        sectors_thinglist = none;
        sectors_specialdata = none;
        sectors_soundtraversed = []b;
        sectors_soundtarget = none;
        sectors_lines = none;
        subsectors_sector = none;
        subsectors_lines = none;
        nodes_xy = none;
        nodes_dxdy = none;
        nodes_bbox = none;
        nodes_children = none;
        lines_v1v2 = none;
        lines_dxdy = none;
        lines_flags = none;
        lines_special = []b;
        lines_tag = none;
        lines_sidenums = none;
        lines_slopetype = []b;
        lines_sectors = none;
        lines_validcount = none;
        sides_textureoffset = none;
        sides_textures = none;
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
