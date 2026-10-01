#!/usr/bin/env python3
"""Convert the sprite lumps of a Doom IWAD into Connect IQ bitmaps.

Every lump between S_START and S_END becomes a PNG at its native size,
with PLAYPAL colors under COLORMAP 0 (full bright) and transparency
where the patch has no posts. The renderer (source/doom/RThings.mc)
scales them on the watch with Dc.drawBitmap2.

Alongside the bitmaps this writes what r_data.c / r_things.c work out at
startup, so the watch doesn't have to:

  spritelumpinfo  R_InitSpriteLumps: per sprite lump,
                  width | (leftoffset + 256) << 8 | (topoffset + 256) << 17
                  in pixels. (The height is the PNG's.)
  spriteframes    R_InitSprites / R_InstallSpriteLump: the spritedef_t and
                  spriteframe_t tables, in one flat array (see
                  sprite_frames below).

and SpriteLumps.mc, which maps a sprite lump number (lump - firstspritelump)
to its Rez.Drawables id, since Monkey C can't look ids up by name.

Output goes to generated/, which is gitignored like the map data: it's
derived from the WAD.
"""

import argparse
import json
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(__file__))
from wad2ciq import Wad  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")


def write_png(path, width, height, rgba):
    """Minimal RGBA PNG writer, so the tool needs only the standard library."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter: none
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(kind, data):
        c = struct.pack(">I", len(data)) + kind + data
        return c + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def patch_rgba(patch, playpal, colormap):
    """Draw a patch_t's posts into an RGBA buffer (transparent elsewhere)."""
    width, height, leftoffset, topoffset = struct.unpack_from("<hhhh", patch, 0)
    rgba = bytearray(width * height * 4)
    for x in range(width):
        (colofs,) = struct.unpack_from("<i", patch, 8 + x * 4)
        # column_t posts: topdelta, length, unused, pixels..., unused
        while patch[colofs] != 0xFF:
            topdelta, length = patch[colofs], patch[colofs + 1]
            for k in range(length):
                y = topdelta + k
                if 0 <= y < height:
                    c = colormap[patch[colofs + 3 + k]] * 3
                    o = (y * width + x) * 4
                    rgba[o:o + 4] = bytes((playpal[c], playpal[c + 1], playpal[c + 2], 255))
            colofs += length + 4
    return width, height, leftoffset, topoffset, rgba


def sprite_frames(names, lumpnames):
    """R_InitSpriteDefs, with R_InstallSpriteLump's checks.

    Returns one flat array:
      [0 .. numsprites]   where each sprite's frames start (sprite i has
                          start[i + 1] - start[i] frames, 0 if absent)
      frame entry         not rotated: (lump << 1 | flip) << 1
                          rotated: 1 | pos << 1, with the 8 rotations at
                          pos .. pos + 2, three 10-bit lump << 1 | flip
                          fields per number (rotation r is field r % 3 of
                          entry pos + r / 3)
    Lumps are relative to firstspritelump.
    """

    def install(sprtemp, spritename, lump, frame, rotation, flipped):
        # R_InstallSpriteLump
        if frame >= 29 or rotation > 8:
            sys.exit(f"R_InstallSpriteLump: Bad frame characters in lump {lump}")
        st = sprtemp[frame]
        if rotation == 0:
            # the lump should be used for all rotations
            if st["rotate"] is False:
                sys.exit(f"R_InitSprites: Sprite {spritename} frame {chr(65 + frame)} has multip rot=0 lump")
            if st["rotate"] is True:
                sys.exit(f"R_InitSprites: Sprite {spritename} frame {chr(65 + frame)} has rotations and a rot=0 lump")
            st["rotate"] = False
            for r in range(8):
                st["lump"][r] = lump
                st["flip"][r] = flipped
            return
        # the lump is only used for one rotation
        if st["rotate"] is False:
            sys.exit(f"R_InitSprites: Sprite {spritename} frame {chr(65 + frame)} has rotations and a rot=0 lump")
        st["rotate"] = True
        # make 0 based
        rotation -= 1
        if st["lump"][rotation] != -1:
            sys.exit(f"R_InitSprites: Sprite {spritename} : {chr(65 + frame)} : {chr(49 + rotation)} has two lumps mapped to it")
        st["lump"][rotation] = lump
        st["flip"][rotation] = flipped

    defs = []
    for spritename in names:
        sprtemp = [{"rotate": None, "lump": [-1] * 8, "flip": [False] * 8} for _ in range(29)]
        for l, name in enumerate(lumpnames):
            if name[:4] != spritename:
                continue
            install(sprtemp, spritename, l, ord(name[4]) - 65, ord(name[5]) - 48, False)
            if len(name) > 6:
                install(sprtemp, spritename, l, ord(name[6]) - 65, ord(name[7]) - 48, True)
        frames = [i for i, st in enumerate(sprtemp) if st["rotate"] is not None]
        maxframe = max(frames) + 1 if frames else 0
        for frame in range(maxframe):
            st = sprtemp[frame]
            if st["rotate"] is None:
                # no rotations were found for that frame at all
                sys.exit(f"R_InitSprites: No patches found for {spritename} frame {chr(65 + frame)}")
            if st["rotate"] and -1 in st["lump"]:
                sys.exit(f"R_InitSprites: Sprite {spritename} frame {chr(65 + frame)} is missing rotations")
        defs.append(sprtemp[:maxframe])

    out = [0] * (len(names) + 1)
    frames = []
    for i, d in enumerate(defs):
        out[i] = len(names) + 1 + len(frames)
        frames += d
        out[i + 1] = len(names) + 1 + len(frames)
    base = len(out) + len(frames)
    entries = []
    rotations = []
    for st in frames:
        lumps = [st["lump"][r] << 1 | (1 if st["flip"][r] else 0) for r in range(8)]
        assert max(lumps) < 1 << 10
        if not st["rotate"]:
            entries.append(lumps[0] << 1)
            continue
        entries.append(1 | (base + len(rotations)) << 1)
        for r in range(0, 8, 3):
            rotations.append(sum(v << (10 * k) for k, v in enumerate(lumps[r:r + 3])))
    return out + entries + rotations


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("wad", help="path to doom1.wad")
    ap.add_argument("--out", default=os.path.join(ROOT, "generated"))
    args = ap.parse_args()

    wad = Wad(args.wad)
    playpal = wad.lump(wad.num_for_name("PLAYPAL"))[:768]
    colormap = wad.lump(wad.num_for_name("COLORMAP"))[:256]
    firstspritelump = wad.num_for_name("S_START") + 1
    lastspritelump = wad.num_for_name("S_END") - 1
    with open(os.path.join(ROOT, "resources", "info", "sprnames.json")) as f:
        sprnames = json.load(f)

    resdir = os.path.join(args.out, "resources")
    imgdir = os.path.join(resdir, "sprites")
    srcdir = os.path.join(args.out, "source")
    os.makedirs(imgdir, exist_ok=True)
    os.makedirs(srcdir, exist_ok=True)

    lumpnames = []
    info = []
    bitmaps = []
    ids = []
    for i in range(firstspritelump, lastspritelump + 1):
        name = wad.lumps[i][0]
        lumpnames.append(name)
        width, height, leftoffset, topoffset, rgba = patch_rgba(wad.lump(i), playpal, colormap)
        write_png(os.path.join(imgdir, f"{name}.png"), width, height, rgba)
        # One number per lump to keep the table small on the watch.
        assert 0 < width < 256 and -256 <= leftoffset < 256 and -256 <= topoffset < 256, name
        info.append(width | (leftoffset + 256) << 8 | (topoffset + 256) << 17)
        rid = f"spr_{name}"
        bitmaps.append(f'    <bitmap id="{rid}" filename="sprites/{name}.png" dithering="none" automaticPalette="false" />')
        ids.append(f"Rez.Drawables.{rid}")

    with open(os.path.join(resdir, "sprites.xml"), "w") as f:
        f.write("<resources>\n  <drawables>\n" + "\n".join(bitmaps) + "\n  </drawables>\n"
                "  <jsonDataResources>\n"
                '    <jsonData id="spritelumpinfo" filename="spritelumpinfo.json" />\n'
                '    <jsonData id="spriteframes" filename="spriteframes.json" />\n'
                "  </jsonDataResources>\n</resources>\n")
    with open(os.path.join(resdir, "spritelumpinfo.json"), "w") as f:
        json.dump(info, f, separators=(",", ":"))
    frames = sprite_frames(sprnames, lumpnames)
    with open(os.path.join(resdir, "spriteframes.json"), "w") as f:
        json.dump(frames, f, separators=(",", ":"))

    # The id list is split over several functions: one function holding
    # them all is too big for an extended code page.
    chunk = 48
    parts = [ids[i:i + chunk] for i in range(0, len(ids), chunk)]
    funcs = "".join(
        f"    function ids{n}() as Array<ResourceId> {{\n"
        "        return [\n            " + ",\n            ".join(part) + "\n        ] as Array<ResourceId>;\n    }\n\n"
        for n, part in enumerate(parts))
    with open(os.path.join(srcdir, "SpriteLumps.mc"), "w") as f:
        f.write("// Generated by tools/sprites2ciq.py, do not edit.\n\n"
                "import Toybox.Lang;\n\n"
                "(:extendedCode)\n"
                "module SpriteLumps {\n\n"
                f"    const NUMSPRITELUMPS = {len(ids)};\n\n"
                "    // Rez.Drawables id of a sprite lump (lump - firstspritelump).\n"
                "    // Looked up in chunks rather than kept in an array, which would\n"
                "    // cost heap for as long as the game runs.\n"
                "    function W_SpriteLumpId(lump as Number) as ResourceId {\n"
                f"        var part = lump / {chunk};\n"
                f"        var i = lump % {chunk};\n"
                + "".join(f"        if (part == {n}) {{\n            return ids{n}()[i];\n        }}\n" for n in range(len(parts) - 1))
                + f"        return ids{len(parts) - 1}()[i];\n    }}\n\n" + funcs + "}\n")
    print(f"sprites: {len(ids)} lumps, {len(frames)} frame values")


if __name__ == "__main__":
    main()
