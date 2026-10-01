#!/usr/bin/env python3
"""Extract finetangent, finesine and tantoangle from Doom's tables.c into jsonData.

Monkey C has no static array initialisers big enough for these, and
regenerating them with Math.sin would drift from the original values by
an ulp here and there. Pulling them straight out of tables.c keeps the
renderer bit-for-bit with the C code.

The output is derived from GPL code, so unlike the WAD data it's committed
(resources/tables/) and the build doesn't need a Doom checkout.
"""

import argparse
import json
import os
import re
import sys

TABLES = {"finetangent": 4096, "finesine": 10240, "tantoangle": 2049}

# v_video.c: the five gamma correction levels, gammatable[5][256] flattened.
# Only the build tools use it (when baking colors), so it isn't a resource.
GAMMA = ("v_video.c", "gammatable", 1280)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("tables_c", help="path to linuxdoom-1.10/tables.c")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "resources", "tables"))
    args = ap.parse_args()

    src = open(args.tables_c).read()
    os.makedirs(args.out, exist_ok=True)
    entries = []
    for name, count in TABLES.items():
        m = re.search(r"\b%s\[\d+\]\s*=\s*\{(.*?)\};" % name, src, re.S)
        if not m:
            sys.exit(f"{name} not found in {args.tables_c}")
        values = [int(v, 0) for v in re.findall(r"-?(?:0x[0-9a-fA-F]+|\d+)", m.group(1))]
        if len(values) != count:
            sys.exit(f"{name}: expected {count} values, got {len(values)}")
        with open(os.path.join(args.out, f"{name}.json"), "w") as f:
            json.dump(values, f, separators=(",", ":"))
        entries.append(f'    <jsonData id="{name}" filename="{name}.json" />')
        print(f"{name}: {count} values")

    vsrc = open(os.path.join(os.path.dirname(args.tables_c), GAMMA[0])).read()
    m = re.search(r"\b%s\[5\]\[256\]\s*=\s*\{(.*?)\};" % GAMMA[1], vsrc, re.S)
    values = [int(v) for v in re.findall(r"\d+", m.group(1))]
    if len(values) != GAMMA[2]:
        sys.exit(f"gammatable: expected {GAMMA[2]} values, got {len(values)}")
    with open(os.path.join(os.path.dirname(__file__), "gammatable.json"), "w") as f:
        json.dump(values, f, separators=(",", ":"))
    print(f"gammatable: {len(values)} values")

    with open(os.path.join(args.out, "tables.xml"), "w") as f:
        f.write("<jsonDataResources>\n" + "\n".join(entries) + "\n</jsonDataResources>\n")


if __name__ == "__main__":
    main()
