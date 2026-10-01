#!/usr/bin/env python3
"""Dump E1M1 from generated/ as plain numbers for the C reference programs.

Derives the same fields p_setup.c does (seg front/back sectors, subsector
sectors) so the C side doesn't need a WAD loader.
"""
import json
import os

base = os.path.join(os.path.dirname(__file__), "..", "generated", "resources")
L = lambda n: json.load(open(os.path.join(base, f"e1m1_{n}.json")))
v, ld, sd, sec, seg, ss, nodes = (L(n) for n in
    ("vertexes", "linedefs", "sidedefs", "sectors", "segs", "ssectors", "nodes"))

side_sector = sd[5::6]
side_mid = sd[4::6]
side_top = sd[2::6]
side_bottom = sd[3::6]
out = []
out.append(f"{len(v)//2} " + " ".join(map(str, v)))
out.append(f"{len(sec)//7} " + " ".join(map(str, sec)))
segrows = []
for i in range(len(seg) // 6):
    v1, v2, angle, linedef, side, offset = seg[i * 6:i * 6 + 6]
    flags = ld[linedef * 7 + 2]
    sidenum = ld[linedef * 7 + 5 + side]
    front = side_sector[sidenum]
    back = side_sector[ld[linedef * 7 + 5 + (side ^ 1)]] if flags & 4 else -1
    # v1 v2 front back midtexture angle offset linedef flags toptexture bottomtexture
    segrows += [v1, v2, front, back, side_mid[sidenum], angle, offset, linedef, flags,
                side_top[sidenum], side_bottom[sidenum]]
out.append(f"{len(seg)//6} " + " ".join(map(str, segrows)))
ssrows = []
for i in range(len(ss) // 2):
    numsegs, firstseg = ss[i * 2:i * 2 + 2]
    ssrows += [segrows[firstseg * 11 + 2], numsegs, firstseg]
out.append(f"{len(ss)//2} " + " ".join(map(str, ssrows)))
out.append(f"{len(nodes)//14} " + " ".join(map(str, nodes)))
print("\n".join(out))
