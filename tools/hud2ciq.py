#!/usr/bin/env python3
"""Convert the status bar graphics from a Doom IWAD into Connect IQ bitmaps.

st_stuff.c loads its patches with W_CacheLumpName and draws them with
V_DrawPatch. Here each patch becomes a PNG (palette colors from PLAYPAL,
transparent where the patch has no posts) at its native resolution; the
status bar is drawn at 320x32 and scaled to the watch as a whole.

The patch offsets and sizes go into a generated HudLumps.mc, together with
the resource ids in the order st_stuff.c's arrays use (tallnum, shortnum,
faces, ...), since Monkey C can't look up Rez ids by name. It also bakes
each PLAYPAL palette into a translucent tint color, which is how the red /
gold / green palette shifts of ST_doPaletteStuff are shown.

Output goes to generated/ (WAD-derived, gitignored).
"""

import argparse
import os
import struct
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad2ciq import Wad, gamma_palette  # noqa: E402


def face_names():
    # ST_loadGraphics' face order.
    names = []
    for i in range(5):  # ST_NUMPAINFACES
        for j in range(3):  # ST_NUMSTRAIGHTFACES
            names.append(f"STFST{i}{j}")
        names.append(f"STFTR{i}0")  # turn right
        names.append(f"STFTL{i}0")  # turn left
        names.append(f"STFOUCH{i}")  # ouch!
        names.append(f"STFEVL{i}")  # evil grin ;)
        names.append(f"STFKILL{i}")  # pissed off
    names += ["STFGOD0", "STFDEAD0"]
    return names


# Groups in the order HudLumps.* indexes them.
GROUPS = [
    ("TALLNUM", [f"STTNUM{i}" for i in range(10)]),
    ("SHORTNUM", [f"STYSNUM{i}" for i in range(10)]),
    ("GREYNUM", [f"STGNUM{i}" for i in range(10)]),
    ("KEYS", [f"STKEYS{i}" for i in range(6)]),
    ("FACES", face_names()),
    ("TALLPERCENT", ["STTPRCNT"]),
    ("MINUS", ["STTMINUS"]),
    ("ARMSBG", ["STARMS"]),
    ("SBAR", ["STBAR"]),
]


def patch_image(data, playpal):
    """V_DrawPatch into an RGBA image."""
    w, h, left, top = struct.unpack_from("<hhhh", data, 0)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for col in range(w):
        (ofs,) = struct.unpack_from("<i", data, 8 + col * 4)
        # column_t posts: topdelta, length, unused, pixels..., unused
        while data[ofs] != 0xFF:
            topdelta, length = data[ofs], data[ofs + 1]
            for k in range(length):
                c = data[ofs + 3 + k] * 3
                px[col, topdelta + k] = (playpal[c], playpal[c + 1], playpal[c + 2], 255)
            ofs += length + 4
    return img, w, h, left, top


def palette_tints(pals):
    """Fit each PLAYPAL palette as palette 0 blended toward one color:
    pal[p] = (1 - a) * pal[0] + a * color. Returns 0xAARRGGBB per palette."""
    base = pals[0]
    out = []
    for p in pals:
        slopes, inters = [], []
        for ch in range(3):
            xs = [base[i * 3 + ch] for i in range(256)]
            ys = [p[i * 3 + ch] for i in range(256)]
            mx, my = sum(xs) / 256, sum(ys) / 256
            sxx = sum((x - mx) ** 2 for x in xs)
            sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
            slope = sxy / sxx
            slopes.append(slope)
            inters.append(my - slope * mx)
        a = max(0.0, min(1.0, 1 - sum(slopes) / 3))
        if a < 0.01:
            out.append(0)
            continue
        rgb = [max(0, min(255, round(i / a))) for i in inters]
        out.append(round(a * 255) << 24 | rgb[0] << 16 | rgb[1] << 8 | rgb[2])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("wad", help="path to doom1.wad")
    ap.add_argument("--gamma", type=int, default=2, choices=range(5),
                    help="gamma correction level, same as wad2ciq.py's")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "generated"))
    args = ap.parse_args()

    wad = Wad(args.wad)
    playpal_lump = wad.lump(wad.num_for_name("PLAYPAL"))
    # I_SetPalette applies the gamma table to whichever palette is set.
    pals = [gamma_palette(playpal_lump[i * 768:(i + 1) * 768], args.gamma)
            for i in range(len(playpal_lump) // 768)]

    resdir = os.path.join(args.out, "resources")
    imgdir = os.path.join(resdir, "hud")
    srcdir = os.path.join(args.out, "source")
    os.makedirs(imgdir, exist_ok=True)
    os.makedirs(srcdir, exist_ok=True)

    entries, ids, consts, sizes = [], [], [], []
    for group, names in GROUPS:
        consts.append(f"    const {group} = {len(ids)};")
        for name in names:
            i = wad.num_for_name(name)
            if i < 0:
                sys.exit(f"{name} not in WAD")
            img, w, h, left, top = patch_image(wad.lump(i), pals[0])
            img.save(os.path.join(imgdir, f"{name.lower()}.png"))
            entries.append(f'    <bitmap id="{name}" filename="hud/{name.lower()}.png" dithering="none" />')
            ids.append(f"Rez.Drawables.{name}")
            sizes += [w, h, left, top]
    consts.append(f"    const NUMLUMPS = {len(ids)};")

    with open(os.path.join(resdir, "hud.xml"), "w") as f:
        f.write("<drawables>\n" + "\n".join(entries) + "\n</drawables>\n")

    tints = palette_tints(pals)
    with open(os.path.join(srcdir, "HudLumps.mc"), "w") as f:
        f.write("// Generated by tools/hud2ciq.py, do not edit.\n\n"
                "import Toybox.Lang;\n\n"
                "(:extendedCode)\n"
                "module HudLumps {\n\n"
                "    // First lump of each group, in st_stuff.c's array order.\n"
                + "\n".join(consts) + "\n\n"
                "    // Resource id of each lump.\n"
                "    function ids() as Array<ResourceId> {\n"
                "        return [" + ", ".join(ids) + "] as Array<ResourceId>;\n"
                "    }\n\n"
                "    // width, height, leftoffset, topoffset of each patch_t, 4 per lump.\n"
                "    function sizes() as Array<Number> {\n"
                "        return [" + ", ".join(map(str, sizes)) + "] as Array<Number>;\n"
                "    }\n\n"
                "    // PLAYPAL palette n as a 0xAARRGGBB tint over palette 0 (0 for none).\n"
                "    function tints() as Array<Number> {\n"
                "        return [" + ", ".join(f"0x{t:08x}" for t in tints) + "] as Array<Number>;\n"
                "    }\n}\n")
    print(f"hud: {len(ids)} patches, {len(tints)} palette tints")


if __name__ == "__main__":
    main()
