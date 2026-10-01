#!/usr/bin/env python3
"""Print E1M1 lumps from generated/ for the C reference programs.

Usage: python3 test/lump.py vertexes linedefs ... > e1m1.txt

Each lump goes on one line as its length followed by its values. The
blockmap and reject lumps are packed in generated/ to save RAM on the
watch (see tools/wad2ciq.py); they're unpacked here to the shorts and
bytes the C code expects.
"""
import json
import os
import sys

BASE = os.path.join(os.path.dirname(__file__), "..")


def load(name, mapname="e1m1"):
    if name.endswith(".json"):
        return json.load(open(os.path.join(BASE, name)))
    d = json.load(open(os.path.join(BASE, "generated", "resources", f"{mapname}_{name}.json")))
    if name == "blockmap":
        out = []
        for w in d:
            w &= 0xFFFFFFFF
            for half in (w & 0xFFFF, w >> 16):
                out.append(half - 0x10000 if half >= 0x8000 else half)
        return out
    if name == "reject":
        return [(w >> (8 * i)) & 0xFF for w in d for i in range(4)]
    return d


if __name__ == "__main__":
    for n in sys.argv[1:]:
        d = load(n)
        print(len(d), *d)
