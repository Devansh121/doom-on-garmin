#!/usr/bin/env python3
"""Dump sprite lumps and E1M1's spawned things for test/rthings_ref.c.

Prints, after what dump_e1m1.py prints:
  the sprite lumps (S_START..S_END): count, then name width leftoffset
  topoffset per lump, for R_InitSpriteLumps / R_InitSpriteDefs;
  the sprite names (sprnames, info.c order);
  the things P_SpawnMapThing spawns on skill 3 single player, in THINGS
  order: x y angle sprite frame flags spawnceiling height. The C side
  finds each one's sector (and so its z) itself.

  python3 test/dump_things.py doom1.wad
"""
import json
import os
import struct
import sys

here = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(here, "..", "tools"))
from wad2ciq import Wad  # noqa: E402

wad = Wad(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "doom1.wad"))
first = wad.num_for_name("S_START") + 1
last = wad.num_for_name("S_END") - 1
rows = []
for i in range(first, last + 1):
    w, h, l, t = struct.unpack_from("<hhhh", wad.lump(i), 0)
    rows.append(f"{wad.lumps[i][0]} {w} {l} {t}")
out = [f"{len(rows)} " + " ".join(rows)]

info = os.path.join(here, "..", "resources", "info")
sprnames = json.load(open(os.path.join(info, "sprnames.json")))
out.append(f"{len(sprnames)} " + " ".join(sprnames))

MI_SIZE, MI_DOOMEDNUM, MI_SPAWNSTATE, MI_HEIGHT, MI_FLAGS = 23, 0, 1, 17, 21
ST_SIZE = 7
MF_AMBUSH, MF_SPAWNCEILING = 32, 256
mobjinfo = json.load(open(os.path.join(info, "mobjinfo.json")))
states = json.load(open(os.path.join(info, "states.json")))
things = json.load(open(os.path.join(here, "..", "generated", "resources", "e1m1_things.json")))
skillbit = 1 << (2 - 1)  # sk_medium
spawned = []
for i in range(0, len(things), 5):
    x, y, angle, typ, options = things[i:i + 5]
    if typ == 11 or typ in (2, 3, 4):
        continue  # deathmatch starts, other players' starts
    if typ != 1:
        if options & 16 or not options & skillbit:
            continue
    t = 0 if typ == 1 else next(n for n in range(len(mobjinfo) // MI_SIZE)
                                if mobjinfo[n * MI_SIZE + MI_DOOMEDNUM] == typ)
    mi = mobjinfo[t * MI_SIZE:(t + 1) * MI_SIZE]
    st = mi[MI_SPAWNSTATE]
    flags = mi[MI_FLAGS] | (MF_AMBUSH if typ != 1 and options & 8 else 0)
    spawned.append(f"{x} {y} {angle} {states[st * ST_SIZE]} {states[st * ST_SIZE + 1]} {flags} "
                   f"{1 if mi[MI_FLAGS] & MF_SPAWNCEILING else 0} {mi[MI_HEIGHT]}")
out.append(f"{len(spawned)} " + " ".join(spawned))
print("\n".join(out))
