// p_setup.c
//
// Do all the WAD I/O, get map description,
//  set up initial state and misc. LUTs.
//
// Structs from r_defs.h are stored one array per field (vertexes_x[i] is
// vertexes[i].x) and pointers are indexes into those arrays, -1 for NULL.
//
// The watchdog won't let a single callback walk a whole lump, so
// P_SetupLevel only resets state and P_SetupLevelStep does the loading a
// slice at a time. The P_Load* functions take the range of records to
// process and do the same work per record as the C versions.

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
    // (line_t's bbox isn't stored, see P_LineBBox)
    var lines_slopetype as Array<Number> = [] as Array<Number>;
    var lines_frontsector as Array<Number> = [] as Array<Number>;
    var lines_backsector as Array<Number> = [] as Array<Number>;
    var lines_validcount as Array<Number> = [] as Array<Number>;
    // thinker_t for reversable actions, -1 for none
    var lines_specialdata as Array<Number> = [] as Array<Number>;

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
    var lumps as Array<ResourceId?>? = null;
    var setupstep as Number = 0;
    var setupindex as Number = 0;
    // current lump's data while it's being converted
    var data as Array<Number> = [] as Array<Number>;

    // Records handled per P_SetupLevelStep call, chosen to stay well under
    // the watchdog limit.
    const CHUNK = 128;
    const GROUPCHUNK = 4;
    // P_SpawnMapThing searches mobjinfo (up to NUMMOBJTYPES) and
    // P_SpawnMobj walks the BSP for every thing, so fewer per slice.
    const THINGCHUNK = 8;

    function W_LumpData(ml as Number) as Array<Number> {
        return WatchUi.loadResource(lumps[ml - 1] as ResourceId) as Array<Number>;
    }

    function newArray(n as Number) as Array<Number> {
        return new [n] as Array<Number>;
    }

    //
    // P_LoadVertexes
    //
    function P_LoadVertexes(first as Number, last as Number) as Void {
        var ml = data;
        var lx = vertexes_x;
        var ly = vertexes_y;

        // Copy and convert vertex coordinates,
        // internal representation as fixed.
        for (var i = first; i < last; i++) {
            lx[i] = ml[i * 2] << MFixed.FRACBITS;
            ly[i] = ml[i * 2 + 1] << MFixed.FRACBITS;
        }
    }

    //
    // P_LoadSegs
    //
    function P_LoadSegs(first as Number, last as Number) as Void {
        var ml = data;
        var sidenum = lines_sidenum;
        var flags = lines_flags;
        var sidesector = sides_sector;

        for (var i = first; i < last; i++) {
            var m = i * 6;
            segs_v1[i] = ml[m];
            segs_v2[i] = ml[m + 1];
            segs_angle[i] = ml[m + 2] << 16;
            segs_offset[i] = ml[m + 5] << 16;
            var linedef = ml[m + 3];
            segs_linedef[i] = linedef;
            var side = ml[m + 4];
            var sidedef = sidenum[linedef * 2 + side];
            segs_sidedef[i] = sidedef;
            segs_frontsector[i] = sidesector[sidedef];
            if ((flags[linedef] & DoomData.ML_TWOSIDED) != 0) {
                segs_backsector[i] = sidesector[sidenum[linedef * 2 + (side ^ 1)]];
            } else {
                segs_backsector[i] = -1;
            }
        }
    }

    //
    // P_LoadSubsectors
    //
    function P_LoadSubsectors(first as Number, last as Number) as Void {
        var ms = data;
        for (var i = first; i < last; i++) {
            subsectors_numlines[i] = ms[i * 2];
            subsectors_firstline[i] = ms[i * 2 + 1];
        }
    }

    //
    // P_LoadSectors
    //
    function P_LoadSectors(first as Number, last as Number) as Void {
        var ms = data;
        for (var i = first; i < last; i++) {
            var m = i * 7;
            sectors_floorheight[i] = ms[m] << MFixed.FRACBITS;
            sectors_ceilingheight[i] = ms[m + 1] << MFixed.FRACBITS;
            // R_FlatNumForName was resolved by tools/wad2ciq.py
            sectors_floorpic[i] = ms[m + 2];
            sectors_ceilingpic[i] = ms[m + 3];
            sectors_lightlevel[i] = ms[m + 4];
            sectors_special[i] = ms[m + 5];
            sectors_tag[i] = ms[m + 6];
            sectors_validcount[i] = 0;
            sectors_linecount[i] = 0;
            sectors_thinglist[i] = -1;
            sectors_specialdata[i] = -1;
            sectors_soundtraversed[i] = 0;
            sectors_soundtarget[i] = -1;
        }
    }

    //
    // P_LoadNodes
    //
    function P_LoadNodes(first as Number, last as Number) as Void {
        var mn = data;
        var bbox = nodes_bbox;
        for (var i = first; i < last; i++) {
            var m = i * 14;
            nodes_x[i] = mn[m] << MFixed.FRACBITS;
            nodes_y[i] = mn[m + 1] << MFixed.FRACBITS;
            nodes_dx[i] = mn[m + 2] << MFixed.FRACBITS;
            nodes_dy[i] = mn[m + 3] << MFixed.FRACBITS;
            for (var j = 0; j < 2; j++) {
                nodes_children[i * 2 + j] = mn[m + 12 + j];
                for (var k = 0; k < 4; k++) {
                    bbox[i * 8 + j * 4 + k] = mn[m + 4 + j * 4 + k] << MFixed.FRACBITS;
                }
            }
        }
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

    //
    // P_LoadLineDefs
    // Also counts secret lines for intermissions.
    //
    function P_LoadLineDefs(first as Number, last as Number) as Void {
        var mld = data;
        var vx = vertexes_x;
        var vy = vertexes_y;
        var sidesector = sides_sector;

        for (var i = first; i < last; i++) {
            var m = i * 7;
            lines_flags[i] = mld[m + 2];
            lines_special[i] = mld[m + 3];
            lines_tag[i] = mld[m + 4];
            var v1 = mld[m];
            var v2 = mld[m + 1];
            lines_v1[i] = v1;
            lines_v2[i] = v2;
            var dx = vx[v2] - vx[v1];
            var dy = vy[v2] - vy[v1];
            lines_dx[i] = dx;
            lines_dy[i] = dy;

            if (dx == 0) {
                lines_slopetype[i] = RDefs.ST_VERTICAL;
            } else if (dy == 0) {
                lines_slopetype[i] = RDefs.ST_HORIZONTAL;
            } else {
                if (MFixed.FixedDiv(dy, dx) > 0) {
                    lines_slopetype[i] = RDefs.ST_POSITIVE;
                } else {
                    lines_slopetype[i] = RDefs.ST_NEGATIVE;
                }
            }

            // bbox is worked out on demand by P_LineBBox to save RAM.

            var side0 = mld[m + 5];
            var side1 = mld[m + 6];
            lines_sidenum[i * 2] = side0;
            lines_sidenum[i * 2 + 1] = side1;

            if (side0 != -1) {
                lines_frontsector[i] = sidesector[side0];
            } else {
                lines_frontsector[i] = -1;
            }

            if (side1 != -1) {
                lines_backsector[i] = sidesector[side1];
            } else {
                lines_backsector[i] = -1;
            }
            lines_validcount[i] = 0;
            lines_specialdata[i] = -1;
        }
    }

    //
    // P_LoadSideDefs
    //
    function P_LoadSideDefs(first as Number, last as Number) as Void {
        var msd = data;
        for (var i = first; i < last; i++) {
            var m = i * 6;
            sides_textureoffset[i] = msd[m] << MFixed.FRACBITS;
            sides_rowoffset[i] = msd[m + 1] << MFixed.FRACBITS;
            // R_TextureNumForName was resolved by tools/wad2ciq.py
            sides_toptexture[i] = msd[m + 2];
            sides_bottomtexture[i] = msd[m + 3];
            sides_midtexture[i] = msd[m + 4];
            sides_sector[i] = msd[m + 5];
        }
    }

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
        blockmaplump = W_LumpData(DoomData.ML_BLOCKMAP);

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

    //
    // P_GroupLines
    // Builds sector line lists and subsector sector numbers.
    // Finds block bounding boxes for sectors.
    //
    // Split into its three loops so each can be run in slices.
    //
    function P_GroupLines_Subsectors() as Void {
        // look up sector number for each subsector
        for (var i = 0; i < numsubsectors; i++) {
            var seg = subsectors_firstline[i];
            subsectors_sector[i] = sides_sector[segs_sidedef[seg]];
        }
    }

    // count number of lines in each sector
    function P_GroupLines_Count() as Number {
        var linecount = sectors_linecount;
        var front = lines_frontsector;
        var back = lines_backsector;
        var total = 0;
        for (var i = 0; i < numlines; i++) {
            total++;
            linecount[front[i]]++;
            if (back[i] != -1 && back[i] != front[i]) {
                linecount[back[i]]++;
                total++;
            }
        }
        return total;
    }

    var linebufferfill as Number = 0;

    // build line tables for each sector
    function P_GroupLines_Sectors(first as Number, last as Number) as Void {
        var bbox = [0, 0, 0, 0] as Array<Number>;
        var front = lines_frontsector;
        var back = lines_backsector;
        var lv1 = lines_v1;
        var lv2 = lines_v2;
        var vx = vertexes_x;
        var vy = vertexes_y;
        var buffer = linebuffer;
        var n = numlines;
        var fill = linebufferfill;

        for (var i = first; i < last; i++) {
            MBBox.M_ClearBox(bbox);
            sectors_lines[i] = fill;
            for (var j = 0; j < n; j++) {
                if (front[j] == i || back[j] == i) {
                    buffer[fill] = j;
                    fill++;
                    MBBox.M_AddToBox(bbox, vx[lv1[j]], vy[lv1[j]]);
                    MBBox.M_AddToBox(bbox, vx[lv2[j]], vy[lv2[j]]);
                }
            }
            if (fill - sectors_lines[i] != sectors_linecount[i]) {
                ISystem.I_Error("P_GroupLines: miscounted");
            }

            // set the degenmobj_t to the middle of the bounding box
            sectors_soundorg_x[i] = (bbox[MBBox.BOXRIGHT] + bbox[MBBox.BOXLEFT]) / 2;
            sectors_soundorg_y[i] = (bbox[MBBox.BOXTOP] + bbox[MBBox.BOXBOTTOM]) / 2;

            // adjust bounding box to map blocks
            var b = i * 4;
            var block = (bbox[MBBox.BOXTOP] - bmaporgy + PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
            block = block >= bmapheight ? bmapheight - 1 : block;
            sectors_blockbox[b + MBBox.BOXTOP] = block;

            block = (bbox[MBBox.BOXBOTTOM] - bmaporgy - PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
            block = block < 0 ? 0 : block;
            sectors_blockbox[b + MBBox.BOXBOTTOM] = block;

            block = (bbox[MBBox.BOXRIGHT] - bmaporgx + PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
            block = block >= bmapwidth ? bmapwidth - 1 : block;
            sectors_blockbox[b + MBBox.BOXRIGHT] = block;

            block = (bbox[MBBox.BOXLEFT] - bmaporgx - PLocal.MAXRADIUS) >> PLocal.MAPBLOCKSHIFT;
            block = block < 0 ? 0 : block;
            sectors_blockbox[b + MBBox.BOXLEFT] = block;
        }
        linebufferfill = fill;
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
        lumps = MapLumps.W_MapLumps(lumpname);
        if (lumps == null) {
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

        // Size the thinker pool for the things that will actually spawn.
        PTick.P_InitThinkers(P_CountSpawnedThings(W_LumpData(DoomData.ML_THINGS)));
        PTick.leveltime = 0;
        setupstep = 0;
        setupindex = 0;
    }

    // Runs one slice of the loading P_SetupLevel does in the C code.
    // Returns true once the level is fully set up.
    //
    // note: most of this ordering is important
    function P_SetupLevelStep() as Boolean {
        var first = setupindex;
        switch (setupstep) {
            case 0:
                P_LoadBlockMap();
                return nextStep();

            case 1:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_VERTEXES);
                    numvertexes = data.size() / 2;
                    vertexes_x = newArray(numvertexes);
                    vertexes_y = newArray(numvertexes);
                }
                return slice(numvertexes, CHUNK, new Lang.Method(PSetup, :P_LoadVertexes));

            case 2:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_SECTORS);
                    numsectors = data.size() / 7;
                    sectors_floorheight = newArray(numsectors);
                    sectors_ceilingheight = newArray(numsectors);
                    sectors_floorpic = newArray(numsectors);
                    sectors_ceilingpic = newArray(numsectors);
                    sectors_lightlevel = newArray(numsectors);
                    sectors_special = newArray(numsectors);
                    sectors_tag = newArray(numsectors);
                    sectors_validcount = newArray(numsectors);
                    sectors_blockbox = newArray(numsectors * 4);
                    sectors_soundorg_x = newArray(numsectors);
                    sectors_soundorg_y = newArray(numsectors);
                    sectors_linecount = newArray(numsectors);
                    sectors_thinglist = newArray(numsectors);
                    sectors_specialdata = newArray(numsectors);
                    sectors_soundtraversed = newArray(numsectors);
                    sectors_soundtarget = newArray(numsectors);
                    sectors_lines = newArray(numsectors);
                }
                return slice(numsectors, CHUNK, new Lang.Method(PSetup, :P_LoadSectors));

            case 3:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_SIDEDEFS);
                    numsides = data.size() / 6;
                    sides_textureoffset = newArray(numsides);
                    sides_rowoffset = newArray(numsides);
                    sides_toptexture = newArray(numsides);
                    sides_bottomtexture = newArray(numsides);
                    sides_midtexture = newArray(numsides);
                    sides_sector = newArray(numsides);
                }
                return slice(numsides, CHUNK, new Lang.Method(PSetup, :P_LoadSideDefs));

            case 4:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_LINEDEFS);
                    numlines = data.size() / 7;
                    lines_v1 = newArray(numlines);
                    lines_v2 = newArray(numlines);
                    lines_dx = newArray(numlines);
                    lines_dy = newArray(numlines);
                    lines_flags = newArray(numlines);
                    lines_special = newArray(numlines);
                    // one spare slot past the last line: the "line_t junk"
                    // p_enemy passes to EV_DoDoor / EV_DoFloor
                    lines_tag = newArray(numlines + 1);
                    lines_sidenum = newArray(numlines * 2);
                    lines_slopetype = newArray(numlines);
                    lines_frontsector = newArray(numlines);
                    lines_backsector = newArray(numlines);
                    lines_validcount = newArray(numlines);
                    lines_specialdata = newArray(numlines);
                }
                return slice(numlines, CHUNK, new Lang.Method(PSetup, :P_LoadLineDefs));

            case 5:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_SSECTORS);
                    numsubsectors = data.size() / 2;
                    subsectors_sector = newArray(numsubsectors);
                    subsectors_numlines = newArray(numsubsectors);
                    subsectors_firstline = newArray(numsubsectors);
                }
                return slice(numsubsectors, CHUNK, new Lang.Method(PSetup, :P_LoadSubsectors));

            case 6:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_NODES);
                    numnodes = data.size() / 14;
                    nodes_x = newArray(numnodes);
                    nodes_y = newArray(numnodes);
                    nodes_dx = newArray(numnodes);
                    nodes_dy = newArray(numnodes);
                    nodes_bbox = newArray(numnodes * 8);
                    nodes_children = newArray(numnodes * 2);
                }
                return slice(numnodes, CHUNK, new Lang.Method(PSetup, :P_LoadNodes));

            case 7:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_SEGS);
                    numsegs = data.size() / 6;
                    segs_v1 = newArray(numsegs);
                    segs_v2 = newArray(numsegs);
                    segs_offset = newArray(numsegs);
                    segs_angle = newArray(numsegs);
                    segs_sidedef = newArray(numsegs);
                    segs_linedef = newArray(numsegs);
                    segs_frontsector = newArray(numsegs);
                    segs_backsector = newArray(numsegs);
                }
                return slice(numsegs, CHUNK, new Lang.Method(PSetup, :P_LoadSegs));

            case 8:
                data = [] as Array<Number>;
                P_GroupLines_Subsectors();
                linebuffer = newArray(P_GroupLines_Count());
                linebufferfill = 0;
                return nextStep();

            case 9:
                return slice(numsectors, GROUPCHUNK, new Lang.Method(PSetup, :P_GroupLines_Sectors));

            case 10:
                rejectmatrix = W_LumpData(DoomData.ML_REJECT);
                return nextStep();

            case 11:
                if (first == 0) {
                    data = W_LumpData(DoomData.ML_THINGS);
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
