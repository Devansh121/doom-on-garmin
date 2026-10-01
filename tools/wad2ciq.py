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


def convert_colors(wad):
    """Flat stand-ins for R_InitTextures / R_InitFlats / R_InitColormaps:
    the renderer draws every texture and flat as its average color, so
    bake that color for each COLORMAP light level instead of shipping the
    graphics."""
    playpal = wad.lump(wad.num_for_name("PLAYPAL"))[:768]
    colormap = wad.lump(wad.num_for_name("COLORMAP"))

    pdata = wad.lump(wad.num_for_name("PNAMES"))
    (npatches,) = struct.unpack_from("<i", pdata, 0)
    pnames = [name8(pdata[4 + i * 8:12 + i * 8]) for i in range(npatches)]

    tex = []
    for lumpname in ("TEXTURE1", "TEXTURE2"):
        i = wad.num_for_name(lumpname)
        if i < 0:
            continue
        data = wad.lump(i)
        (count,) = struct.unpack_from("<i", data, 0)
        for t in range(count):
            (ofs,) = struct.unpack_from("<i", data, 4 + t * 4)
            tex += lit_colors(composite_texture(wad, data, ofs, pnames), playpal, colormap)

    firstflat = wad.num_for_name("F_START") + 1
    lastflat = wad.num_for_name("F_END") - 1
    flats = []
    for i in range(firstflat, lastflat + 1):
        data = wad.lump(i)
        # F1_START/F1_END style markers are empty but still count as flats.
        flats += lit_colors(list(data[:4096]), playpal, colormap) if len(data) >= 4096 else [0] * 32

    return {
        "texturecolors": tex,
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


def convert_map(wad, mapname, textures, firstflat):
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
    out["blockmap"] = unpack_records(lump["BLOCKMAP"], "<h")

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


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("wad", help="path to doom1.wad")
    ap.add_argument("--maps", nargs="+", default=["E1M1"])
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "generated"))
    args = ap.parse_args()

    wad = Wad(args.wad)
    textures = texture_names(wad)
    firstflat = wad.num_for_name("F_START") + 1
    resdir = os.path.join(args.out, "resources")
    srcdir = os.path.join(args.out, "source")
    os.makedirs(resdir, exist_ok=True)
    os.makedirs(srcdir, exist_ok=True)

    entries = []
    cases = []
    for mapname in args.maps:
        mapname = mapname.upper()
        converted = convert_map(wad, mapname, textures, firstflat)
        for lumpname, values in converted.items():
            rid = f"{mapname}_{lumpname}".lower()
            fname = f"{rid}.json"
            with open(os.path.join(resdir, fname), "w") as f:
                json.dump(values, f, separators=(",", ":"))
            entries.append(f'    <jsonData id="{rid}" filename="{fname}" />')
            print(f"{rid}: {len(values)} values")
        # Indexed by ML_* - 1 (ML_LABEL is the map marker itself).
        ids = ", ".join(f"Rez.JsonData.{mapname.lower()}_{l.lower()}" if l.lower() in converted else "null"
                        for l in MAP_LUMPS)
        cases.append(f'        if (name.equals("{mapname}")) {{\n            return [{ids}];\n        }}')

    for name, values in convert_colors(wad).items():
        with open(os.path.join(resdir, f"{name}.json"), "w") as f:
            json.dump(values, f, separators=(",", ":"))
        entries.append(f'    <jsonData id="{name}" filename="{name}.json" />')
        print(f"{name}: {len(values)} values")

    with open(os.path.join(resdir, "maps.xml"), "w") as f:
        f.write("<jsonDataResources>\n" + "\n".join(entries) + "\n</jsonDataResources>\n")

    with open(os.path.join(srcdir, "MapLumps.mc"), "w") as f:
        f.write("// Generated by tools/wad2ciq.py, do not edit.\n\n"
                "import Toybox.Lang;\n\n"
                "module MapLumps {\n\n"
                "    // Resource ids for a map's lumps, indexed by ML_* - 1, or null if\n"
                "    // the map isn't built into the app.\n"
                "    function W_MapLumps(name as String) as Array<ResourceId?>? {\n"
                + "\n".join(cases) + "\n        return null;\n    }\n}\n")


if __name__ == "__main__":
    main()
