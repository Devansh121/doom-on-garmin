#!/usr/bin/env python3
"""Convert map lumps from a Doom IWAD into Connect IQ jsonData resources.

Connect IQ apps can't open files, so the WAD can't be read at runtime the
way w_wad.c does. Instead each map lump is unpacked here into a flat array
of numbers, one jsonData resource per lump, which p_setup loads with
WatchUi.loadResource().

Fields are kept in the same order as the structs in doomdata.h so the
P_Load* functions can index them the same way the C code walks the lump.
Texture and flat names are resolved to numbers here (what
R_TextureNumForName / R_FlatNumForName do at load time in the C code).

Output goes to generated/ (resources plus a MapLumps.mc that maps a map
name to its resource ids, since Monkey C can't look up Rez ids by
string). It's gitignored: the shareware WAD is freely distributable but
it isn't GPL, so we don't commit data derived from it.
"""

import argparse
import json
import os
import struct
import sys

# Lump order inside a map, from doomdata.h (ML_LABEL .. ML_BLOCKMAP).
MAP_LUMPS = [
    "THINGS", "LINEDEFS", "SIDEDEFS", "VERTEXES", "SEGS",
    "SSECTORS", "NODES", "SECTORS", "REJECT", "BLOCKMAP",
]


class Wad:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.data = f.read()
        ident, numlumps, infotableofs = struct.unpack_from("<4sii", self.data, 0)
        if ident not in (b"IWAD", b"PWAD"):
            sys.exit(f"{path}: not a WAD file")
        self.lumps = []
        for i in range(numlumps):
            filepos, size, name = struct.unpack_from("<ii8s", self.data, infotableofs + i * 16)
            self.lumps.append((name.rstrip(b"\0").decode("ascii").upper(), filepos, size))

    def num_for_name(self, name):
        # W_CheckNumForName scans backwards so later lumps override earlier ones.
        for i in range(len(self.lumps) - 1, -1, -1):
            if self.lumps[i][0] == name:
                return i
        return -1

    def lump(self, i):
        _, filepos, size = self.lumps[i]
        return self.data[filepos:filepos + size]


def name8(raw):
    return raw.split(b"\0", 1)[0].decode("ascii").upper()


def texture_names(wad):
    """Texture numbers in TEXTURE1 (then TEXTURE2) order, as R_InitTextures assigns them."""
    names = []
    for lumpname in ("TEXTURE1", "TEXTURE2"):
        i = wad.num_for_name(lumpname)
        if i < 0:
            continue
        data = wad.lump(i)
        (count,) = struct.unpack_from("<i", data, 0)
        for t in range(count):
            (ofs,) = struct.unpack_from("<i", data, 4 + t * 4)
            names.append(name8(data[ofs:ofs + 8]))
    return names


def texture_num(textures, name):
    # R_TextureNumForName: "-" means no texture, which is number 0.
    if name.startswith("-"):
        return 0
    try:
        return textures.index(name)
    except ValueError:
        sys.exit(f"texture {name} not found")


def flat_num(wad, firstflat, name):
    # R_FlatNumForName: lump number relative to the first flat (markers included).
    i = wad.num_for_name(name)
    if i < 0:
        sys.exit(f"flat {name} not found")
    return i - firstflat


def composite_texture(wad, data, ofs, pnames):
    """Build a texture's texels from its patches the way R_GenerateComposite
    does. Returns a list of palette indexes, None where nothing is drawn."""
    width, height = struct.unpack_from("<hh", data, ofs + 12)
    (patchcount,) = struct.unpack_from("<h", data, ofs + 20)
    texels = [None] * (width * height)
    for p in range(patchcount):
        originx, originy, patchnum = struct.unpack_from("<hhh", data, ofs + 22 + p * 10)
        patch = wad.lump(wad.num_for_name(pnames[patchnum]))
        pw, ph = struct.unpack_from("<hh", patch, 0)
        for col in range(pw):
            x = originx + col
            if x < 0 or x >= width:
                continue
            (colofs,) = struct.unpack_from("<i", patch, 8 + col * 4)
            # column_t posts: topdelta, length, unused, pixels..., unused
            while patch[colofs] != 0xFF:
                topdelta, length = patch[colofs], patch[colofs + 1]
                for k in range(length):
                    y = originy + topdelta + k
                    if 0 <= y < height:
                        texels[y * width + x] = patch[colofs + 3 + k]
                colofs += length + 4
    return texels


def gamma_palette(playpal, usegamma):
    """PLAYPAL through v_video.c's gammatable, like I_SetPalette does with
    usegamma. Level 0 is the original, 4 the brightest."""
    table = json.load(open(os.path.join(os.path.dirname(__file__), "gammatable.json")))
    g = table[usegamma * 256:(usegamma + 1) * 256]
    return bytes(g[c] for c in playpal)


def lit_colors(texels, playpal, colormap):
    """Average 0xRRGGBB of the texels under each of the 32 light levels."""
    texels = [t for t in texels if t is not None]
    out = []
    for level in range(32):
        cmap = colormap[level * 256:(level + 1) * 256]
        r = g = b = 0
        for t in texels:
            c = cmap[t] * 3
            r += playpal[c]
            g += playpal[c + 1]
            b += playpal[c + 2]
        n = max(len(texels), 1)
        out.append((r // n) << 16 | (g // n) << 8 | (b // n))
    return out


TEXBANDS = 16


def texture_bands(wad, data, ofs, pnames, playpal):
    """For the optional textured walls: a texture squeezed to TEXBANDS
    vertical bands, each the palette index nearest its average color.
    Returns (widthmask, bands) with widthmask as R_InitTextures makes
    texturewidthmask."""
    width, height = struct.unpack_from("<hh", data, ofs + 12)
    texels = composite_texture(wad, data, ofs, pnames)
    pal = [tuple(playpal[i * 3:i * 3 + 3]) for i in range(256)]
    bands = []
    for b in range(TEXBANDS):
        x0 = b * width // TEXBANDS
        x1 = max((b + 1) * width // TEXBANDS, x0 + 1)
        cols = [texels[y * width + x] for y in range(height) for x in range(x0, min(x1, width))]
        cols = [c for c in cols if c is not None]
        if not cols:
            bands.append(0)
            continue
        r = sum(pal[c][0] for c in cols) / len(cols)
        g = sum(pal[c][1] for c in cols) / len(cols)
        bl = sum(pal[c][2] for c in cols) / len(cols)
        bands.append(min(range(256), key=lambda i: (pal[i][0] - r) ** 2 + (pal[i][1] - g) ** 2 + (pal[i][2] - bl) ** 2))
    j = 1
    while j * 2 <= width:
        j <<= 1
    return j - 1, bands


def pack_bytes(values):
    """Four bytes per number, little end first, as signed 32-bit."""
    values = list(values) + [0] * ((-len(values)) % 4)
    out = []
    for k in range(0, len(values), 4):
        w = values[k] | values[k + 1] << 8 | values[k + 2] << 16 | values[k + 3] << 24
        out.append(w - (1 << 32) if w >= (1 << 31) else w)
    return out


def convert_colors(wad, usegamma):
    """Flat stand-ins for R_InitTextures / R_InitFlats / R_InitColormaps:
    the renderer draws every texture and flat as its average color, so
    bake that color for each COLORMAP light level instead of shipping the
    graphics."""
    playpal = gamma_palette(wad.lump(wad.num_for_name("PLAYPAL"))[:768], usegamma)
    colormap = wad.lump(wad.num_for_name("COLORMAP"))

    pdata = wad.lump(wad.num_for_name("PNAMES"))
    (npatches,) = struct.unpack_from("<i", pdata, 0)
    pnames = [name8(pdata[4 + i * 8:12 + i * 8]) for i in range(npatches)]

    tex = []
    widthmasks = []
    bands = []
    for lumpname in ("TEXTURE1", "TEXTURE2"):
        i = wad.num_for_name(lumpname)
        if i < 0:
            continue
        data = wad.lump(i)
        (count,) = struct.unpack_from("<i", data, 0)
        for t in range(count):
            (ofs,) = struct.unpack_from("<i", data, 4 + t * 4)
            tex += lit_colors(composite_texture(wad, data, ofs, pnames), playpal, colormap)
            mask, b = texture_bands(wad, data, ofs, pnames, playpal)
            widthmasks.append(mask)
            bands += b

    firstflat = wad.num_for_name("F_START") + 1
    lastflat = wad.num_for_name("F_END") - 1
    flats = []
    for i in range(firstflat, lastflat + 1):
        data = wad.lump(i)
        # F1_START/F1_END style markers are empty but still count as flats.
        flats += lit_colors(list(data[:4096]), playpal, colormap) if len(data) >= 4096 else [0] * 32

    # Names, so p_spec/p_switch can find texture and flat numbers by name
    # (R_TextureNumForName, R_FlatNumForName) for switches and animations,
    # and texture heights for raiseToTexture floors.
    flatnames = [wad.lumps[i][0] for i in range(firstflat, lastflat + 1)]
    heights = []
    for lumpname in ("TEXTURE1", "TEXTURE2"):
        i = wad.num_for_name(lumpname)
        if i < 0:
            continue
        data = wad.lump(i)
        (count,) = struct.unpack_from("<i", data, 0)
        for t in range(count):
            (ofs,) = struct.unpack_from("<i", data, 4 + t * 4)
            heights.append(struct.unpack_from("<h", data, ofs + 14)[0])

    return {
        "texturenames": texture_names(wad),
        "textureheights": heights,
        "flatnames": flatnames,
        "texturecolors": tex,
        # Textured walls (optional): per texture its width mask and
        # TEXBANDS palette indexes packed four per number, plus COLORMAP
        # packed the same way and the palette as 0xRRGGBB.
        "texturewidthmask": widthmasks,
        "texturebands": pack_bytes(bands),
        "colormaps": pack_bytes(colormap[:34 * 256]),
        "palette": [playpal[i * 3] << 16 | playpal[i * 3 + 1] << 8 | playpal[i * 3 + 2] for i in range(256)],
        "flatcolors": flats,
        # G_DoLoadLevel: SKYFLATNAME is F_SKY1, and episode 1 uses SKY1.
        "skyflatnum": [wad.num_for_name("F_SKY1") - firstflat],
        "skytexture": [texture_names(wad).index("SKY1")],
    }


def unpack_records(data, fmt):
    size = struct.calcsize(fmt)
    out = []
    for ofs in range(0, len(data) - size + 1, size):
        out.extend(struct.unpack_from(fmt, data, ofs))
    return out


MININT = -(1 << 31)
MAXINT = (1 << 31) - 1
FRACBITS = 16
NF_SUBSECTOR = 0x8000
ML_TWOSIDED = 4
# r_defs.h slopetype_t
ST_HORIZONTAL, ST_VERTICAL, ST_POSITIVE, ST_NEGATIVE = range(4)
# m_bbox.h
BOXTOP, BOXBOTTOM, BOXLEFT, BOXRIGHT = range(4)
# p_local.h
MAPBLOCKSHIFT = FRACBITS + 7
MAXRADIUS = 32 << FRACBITS


def s32(v):
    """v as a C int (two's complement wrap to 32 bits)."""
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v >= (1 << 31) else v


def cdiv(a, b):
    """C integer division, truncating toward zero."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def c_abs(a):
    # abs(MININT) stays MININT
    return s32(-a) if a < 0 else a


def fixed_div(a, b):
    """m_fixed.c FixedDiv, as MFixed.FixedDiv computes it."""
    if (c_abs(a) >> 14) >= c_abs(b):
        return MININT if (a ^ b) < 0 else MAXINT
    return s32(cdiv(a << 16, b))


def m_clear_box():
    box = [0] * 4
    box[BOXTOP] = box[BOXRIGHT] = MININT
    box[BOXBOTTOM] = box[BOXLEFT] = MAXINT
    return box


def m_add_to_box(box, x, y):
    # The else ifs are m_bbox.c's: the first point only sets left and
    # bottom, so a box can end up with right/top still at MININT.
    if x < box[BOXLEFT]:
        box[BOXLEFT] = x
    elif x > box[BOXRIGHT]:
        box[BOXRIGHT] = x
    if y < box[BOXBOTTOM]:
        box[BOXBOTTOM] = y
    elif y > box[BOXTOP]:
        box[BOXTOP] = y


def raw_lumps(wad, mapname, textures, firstflat):
    """The map lumps as flat lists of numbers in doomdata.h field order,
    texture and flat names resolved to numbers. These are what p_setup.c
    reads; the test tools' C reference programs read them too."""
    base = wad.num_for_name(mapname)
    if base < 0:
        sys.exit(f"map {mapname} not in WAD")
    lump = {name: wad.lump(base + 1 + n) for n, name in enumerate(MAP_LUMPS)}

    out = {}
    out["vertexes"] = unpack_records(lump["VERTEXES"], "<hh")
    out["linedefs"] = unpack_records(lump["LINEDEFS"], "<7h")
    out["segs"] = unpack_records(lump["SEGS"], "<6h")
    out["ssectors"] = unpack_records(lump["SSECTORS"], "<hh")
    # x, y, dx, dy, bbox[2][4], then children as unsigned (NF_SUBSECTOR is 0x8000).
    out["nodes"] = unpack_records(lump["NODES"], "<12h2H")
    out["things"] = unpack_records(lump["THINGS"], "<5h")
    # Two shorts per number to halve the RAM it takes: entry k is the low
    # half of [k >> 1] for even k, the high half for odd k.
    bm = unpack_records(lump["BLOCKMAP"], "<h")
    if len(bm) % 2:
        bm.append(0)
    out["blockmap"] = [s32((bm[k] & 0xFFFF) | ((bm[k + 1] & 0xFFFF) << 16)) for k in range(0, len(bm), 2)]
    # 32 bits per number: bit pnum of the lump (bit pnum & 7 of byte
    # pnum >> 3, as p_sight.c reads it) is bit pnum & 31 of [pnum >> 5].
    rej = lump["REJECT"] + bytes((-len(lump["REJECT"])) % 4)
    out["reject"] = [s32(struct.unpack_from("<I", rej, o)[0]) for o in range(0, len(rej), 4)]

    sides = []
    data = lump["SIDEDEFS"]
    for ofs in range(0, len(data), 30):
        xo, yo = struct.unpack_from("<hh", data, ofs)
        top, bottom, mid = (name8(data[ofs + 4 + k * 8:ofs + 12 + k * 8]) for k in range(3))
        (sector,) = struct.unpack_from("<h", data, ofs + 28)
        sides += [xo, yo, texture_num(textures, top), texture_num(textures, bottom),
                  texture_num(textures, mid), sector]
    out["sidedefs"] = sides

    sectors = []
    data = lump["SECTORS"]
    for ofs in range(0, len(data), 26):
        floorh, ceilh = struct.unpack_from("<hh", data, ofs)
        floorpic, ceilpic = name8(data[ofs + 4:ofs + 12]), name8(data[ofs + 12:ofs + 20])
        light, special, tag = struct.unpack_from("<3h", data, ofs + 20)
        sectors += [floorh, ceilh, flat_num(wad, firstflat, floorpic),
                    flat_num(wad, firstflat, ceilpic), light, special, tag]
    out["sectors"] = sectors
    return out


def level_arrays(raw):
    """Everything p_setup.c's P_LoadVertexes .. P_GroupLines work out from
    the lumps, as the arrays PSetup keeps at runtime, so P_SetupLevelStep
    only has to load them. The steps and the arithmetic (32-bit, C
    rounding) are p_setup.c's."""
    out = {}

    # P_LoadVertexes
    v = raw["vertexes"]
    vx = [s32(x << FRACBITS) for x in v[0::2]]
    vy = [s32(y << FRACBITS) for y in v[1::2]]
    out["vertexes_x"] = vx
    out["vertexes_y"] = vy

    # P_LoadSectors
    ms = raw["sectors"]
    numsectors = len(ms) // 7
    out["sectors_floorheight"] = [s32(h << FRACBITS) for h in ms[0::7]]
    out["sectors_ceilingheight"] = [s32(h << FRACBITS) for h in ms[1::7]]
    out["sectors_floorpic"] = ms[2::7]
    out["sectors_ceilingpic"] = ms[3::7]
    out["sectors_lightlevel"] = ms[4::7]
    out["sectors_special"] = ms[5::7]
    out["sectors_tag"] = ms[6::7]

    # P_LoadSideDefs
    msd = raw["sidedefs"]
    side_sector = msd[5::6]
    out["sides_textureoffset"] = [s32(o << FRACBITS) for o in msd[0::6]]
    out["sides_rowoffset"] = [s32(o << FRACBITS) for o in msd[1::6]]
    out["sides_toptexture"] = msd[2::6]
    out["sides_bottomtexture"] = msd[3::6]
    out["sides_midtexture"] = msd[4::6]
    out["sides_sector"] = side_sector

    # P_LoadLineDefs
    mld = raw["linedefs"]
    numlines = len(mld) // 7
    lv1, lv2, ldx, ldy, slope, sidenum, front, back = [], [], [], [], [], [], [], []
    for i in range(numlines):
        a, b, flags, special, tag, side0, side1 = mld[i * 7:i * 7 + 7]
        dx = s32(vx[b] - vx[a])
        dy = s32(vy[b] - vy[a])
        lv1.append(a)
        lv2.append(b)
        ldx.append(dx)
        ldy.append(dy)
        if dx == 0:
            slope.append(ST_VERTICAL)
        elif dy == 0:
            slope.append(ST_HORIZONTAL)
        elif fixed_div(dy, dx) > 0:
            slope.append(ST_POSITIVE)
        else:
            slope.append(ST_NEGATIVE)
        sidenum += [side0, side1]
        front.append(side_sector[side0] if side0 != -1 else -1)
        back.append(side_sector[side1] if side1 != -1 else -1)
    out["lines_v1"] = lv1
    out["lines_v2"] = lv2
    out["lines_dx"] = ldx
    out["lines_dy"] = ldy
    out["lines_flags"] = mld[2::7]
    out["lines_special"] = mld[3::7]
    # one spare slot past the last line: the "line_t junk" p_enemy passes
    # to EV_DoDoor / EV_DoFloor
    out["lines_tag"] = mld[4::7] + [0]
    out["lines_sidenum"] = sidenum
    out["lines_slopetype"] = slope
    out["lines_frontsector"] = front
    out["lines_backsector"] = back

    # P_LoadSubsectors
    mss = raw["ssectors"]
    out["subsectors_numlines"] = mss[0::2]
    out["subsectors_firstline"] = mss[1::2]

    # P_LoadNodes
    mn = raw["nodes"]
    numnodes = len(mn) // 14
    out["nodes_x"] = [s32(x << FRACBITS) for x in mn[0::14]]
    out["nodes_y"] = [s32(x << FRACBITS) for x in mn[1::14]]
    out["nodes_dx"] = [s32(x << FRACBITS) for x in mn[2::14]]
    out["nodes_dy"] = [s32(x << FRACBITS) for x in mn[3::14]]
    out["nodes_bbox"] = [s32(mn[i * 14 + 4 + k] << FRACBITS) for i in range(numnodes) for k in range(8)]
    out["nodes_children"] = [mn[i * 14 + 12 + j] for i in range(numnodes) for j in range(2)]

    # P_LoadSegs
    ml = raw["segs"]
    numsegs = len(ml) // 6
    seg_sidedef = []
    seg_front = []
    seg_back = []
    for i in range(numsegs):
        linedef, side = ml[i * 6 + 3], ml[i * 6 + 4]
        sd = sidenum[linedef * 2 + side]
        seg_sidedef.append(sd)
        seg_front.append(side_sector[sd])
        if mld[linedef * 7 + 2] & ML_TWOSIDED:
            seg_back.append(side_sector[sidenum[linedef * 2 + (side ^ 1)]])
        else:
            seg_back.append(-1)
    out["segs_v1"] = ml[0::6]
    out["segs_v2"] = ml[1::6]
    out["segs_offset"] = [s32(o << 16) for o in ml[5::6]]
    out["segs_angle"] = [s32(a << 16) for a in ml[2::6]]
    out["segs_sidedef"] = seg_sidedef
    out["segs_linedef"] = ml[3::6]
    out["segs_frontsector"] = seg_front
    out["segs_backsector"] = seg_back

    # P_GroupLines
    # look up sector number for each subsector
    out["subsectors_sector"] = [side_sector[seg_sidedef[first]] for first in out["subsectors_firstline"]]

    # count number of lines in each sector
    linecount = [0] * numsectors
    for i in range(numlines):
        linecount[front[i]] += 1
        if back[i] != -1 and back[i] != front[i]:
            linecount[back[i]] += 1

    # build line tables for each sector
    bm = raw["blockmap"]
    bmaporgx = s32((bm[0] << 16) & 0xFFFF0000)  # (short) blockmaplump[0] << FRACBITS
    bmaporgy = s32(bm[0] & 0xFFFF0000)            # (short) blockmaplump[1] << FRACBITS
    bmapwidth = s32(bm[1] << 16) >> 16
    bmapheight = bm[1] >> 16
    linebuffer = []
    sectors_lines = []
    blockbox = []
    soundorg_x = []
    soundorg_y = []
    for i in range(numsectors):
        bbox = m_clear_box()
        sectors_lines.append(len(linebuffer))
        for j in range(numlines):
            if front[j] == i or back[j] == i:
                linebuffer.append(j)
                m_add_to_box(bbox, vx[lv1[j]], vy[lv1[j]])
                m_add_to_box(bbox, vx[lv2[j]], vy[lv2[j]])
        if len(linebuffer) - sectors_lines[i] != linecount[i]:
            sys.exit("P_GroupLines: miscounted")

        # set the degenmobj_t to the middle of the bounding box
        soundorg_x.append(cdiv(s32(bbox[BOXRIGHT] + bbox[BOXLEFT]), 2))
        soundorg_y.append(cdiv(s32(bbox[BOXTOP] + bbox[BOXBOTTOM]), 2))

        # adjust bounding box to map blocks
        box = [0] * 4
        block = s32(bbox[BOXTOP] - bmaporgy + MAXRADIUS) >> MAPBLOCKSHIFT
        box[BOXTOP] = bmapheight - 1 if block >= bmapheight else block
        block = s32(bbox[BOXBOTTOM] - bmaporgy - MAXRADIUS) >> MAPBLOCKSHIFT
        box[BOXBOTTOM] = 0 if block < 0 else block
        block = s32(bbox[BOXRIGHT] - bmaporgx + MAXRADIUS) >> MAPBLOCKSHIFT
        box[BOXRIGHT] = bmapwidth - 1 if block >= bmapwidth else block
        block = s32(bbox[BOXLEFT] - bmaporgx - MAXRADIUS) >> MAPBLOCKSHIFT
        box[BOXLEFT] = 0 if block < 0 else block
        blockbox += box
    out["sectors_blockbox"] = blockbox
    out["sectors_soundorg_x"] = soundorg_x
    out["sectors_soundorg_y"] = soundorg_y
    out["sectors_linecount"] = linecount
    out["sectors_lines"] = sectors_lines
    out["linebuffer"] = linebuffer

    # loaded as they are
    for name in ("things", "blockmap", "reject"):
        out[name] = raw[name]
    return out


def convert_demos(wad):
    """DEMO1..DEMO3 for g_game.c's demo playback. Each becomes the 13
    header bytes (version, skill, episode, map, deathmatch, respawnparm,
    fastparm, nomonsters, consoleplayer, playeringame[4]), one number
    each, then one number per ticcmd: its 4 bytes (forwardmove,
    sidemove, angleturn >> 8, buttons) packed little endian, a quarter of
    the RAM one number per byte would take. The DEMOMARKER byte (0x80)
    that ends the stream becomes a last number of 0x80, so its low byte
    is checked the way G_ReadDemoTiccmd checks *demo_p."""
    out = {}
    for n in range(1, 4):
        i = wad.num_for_name(f"DEMO{n}")
        if i < 0:
            continue
        data = wad.lump(i)
        values = list(data[:13])
        p = 13
        while data[p] != 0x80:
            (v,) = struct.unpack_from("<i", data, p)
            values.append(v)
            p += 4
        values.append(0x80)
        out[f"demo{n}"] = values
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("wad", help="path to doom1.wad")
    ap.add_argument("--gamma", type=int, default=2, choices=range(5),
                    help="gamma correction level (v_video.c usegamma); the AMOLED looks dull at 0")
    ap.add_argument("--maps", nargs="+", default=[f"E1M{m}" for m in range(1, 10)])
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "generated"))
    args = ap.parse_args()

    wad = Wad(args.wad)
    textures = texture_names(wad)
    firstflat = wad.num_for_name("F_START") + 1
    resdir = os.path.join(args.out, "resources")
    srcdir = os.path.join(args.out, "source")
    os.makedirs(resdir, exist_ok=True)
    os.makedirs(srcdir, exist_ok=True)

    lumpdir = os.path.join(args.out, "lumps")
    os.makedirs(lumpdir, exist_ok=True)
    for fname in os.listdir(resdir):
        if fname.startswith("e1m") and fname.endswith(".json"):
            os.remove(os.path.join(resdir, fname))

    entries = []
    cases = []
    fields = None
    for mapname in args.maps:
        mapname = mapname.upper()
        raw = raw_lumps(wad, mapname, textures, firstflat)
        # The plain lumps, for test/lump.py and the C reference programs.
        # They aren't built into the app.
        for lumpname, values in raw.items():
            with open(os.path.join(lumpdir, f"{mapname}_{lumpname}.json".lower()), "w") as f:
                json.dump(values, f, separators=(",", ":"))
        level = level_arrays(raw)
        fields = fields or list(level)
        assert list(level) == fields
        for name in fields:
            rid = f"{mapname}_{name}".lower()
            fname = f"{rid}.json"
            with open(os.path.join(resdir, fname), "w") as f:
                json.dump(level[name], f, separators=(",", ":"))
            entries.append(f'    <jsonData id="{rid}" filename="{fname}" />')
            print(f"{rid}: {len(level[name])} values")
        ids = ", ".join(f"Rez.JsonData.{mapname.lower()}_{name}" for name in fields)
        cases.append(f'        if (name.equals("{mapname}")) {{\n            return [{ids}];\n        }}')

    for name, values in convert_colors(wad, args.gamma).items():
        with open(os.path.join(resdir, f"{name}.json"), "w") as f:
            json.dump(values, f, separators=(",", ":"))
        entries.append(f'    <jsonData id="{name}" filename="{name}.json" />')
        print(f"{name}: {len(values)} values")

    for name, values in convert_demos(wad).items():
        with open(os.path.join(resdir, f"{name}.json"), "w") as f:
            json.dump(values, f, separators=(",", ":"))
        entries.append(f'    <jsonData id="{name}" filename="{name}.json" />')
        print(f"{name}: {len(values)} values")

    with open(os.path.join(resdir, "maps.xml"), "w") as f:
        f.write("<jsonDataResources>\n" + "\n".join(entries) + "\n</jsonDataResources>\n")

    consts = "".join(f"    const {name.upper()} = {i};\n" for i, name in enumerate(fields))
    with open(os.path.join(srcdir, "MapLumps.mc"), "w") as f:
        f.write("// Generated by tools/wad2ciq.py, do not edit.\n\n"
                "import Toybox.Lang;\n\n"
                "module MapLumps {\n\n"
                "    // Where each array is in W_MapLumps' list.\n"
                + consts + "\n"
                "    // Resource ids for a map's arrays, or null if the map isn't\n"
                "    // built into the app.\n"
                "    function W_MapLumps(name as String) as Array<ResourceId>? {\n"
                + "\n".join(cases) + "\n        return null;\n    }\n}\n")


if __name__ == "__main__":
    main()
