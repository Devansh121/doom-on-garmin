#!/usr/bin/env python3
"""Extract sprnames, states and mobjinfo from Doom's info.c into jsonData.

info.c is one big table of structs that refer to each other through the
enums in info.h (S_*, MT_*, SPR_*), plus sound numbers from sounds.h,
MF_* flags from p_mobj.h and FRACUNIT multiples. All of those are
resolved to plain numbers here, so the tables load as flat number arrays:

  states    7 numbers per state, in state_t order
            (sprite, frame, tics, action, nextstate, misc1, misc2)
  mobjinfo  23 numbers per type, in mobjinfo_t order
  sprnames  array of 4-letter strings

Monkey C has no function pointers, so a state's action becomes a number:
1 + the index of the action in the list of distinct action names in order
of first appearance in states[], 0 for NULL. The list is written as a
comment in Info.mc for the code that dispatches on it.

It also writes source/doom/Info.mc with the enums as consts, so code can
say Info.S_PLAY instead of 149.

The output is derived from GPL code, so it's committed (resources/info/
and source/doom/Info.mc) and the build doesn't need a Doom checkout.
"""

import argparse
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

STATE_FIELDS = ["sprite", "frame", "tics", "action", "nextstate", "misc1", "misc2"]

MOBJINFO_FIELDS = [
    "doomednum", "spawnstate", "spawnhealth", "seestate", "seesound",
    "reactiontime", "attacksound", "painstate", "painchance", "painsound",
    "meleestate", "missilestate", "deathstate", "xdeathstate", "deathsound",
    "speed", "radius", "height", "mass", "damage", "activesound", "flags",
    "raisestate",
]

FRACUNIT = 1 << 16


def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def parse_enum(src, name):
    """Members of `typedef enum { ... } name;` as an ordered dict name -> value."""
    m = re.search(r"typedef\s+enum\s*\{([^}]*)\}\s*%s\s*;" % name, strip_comments(src))
    if not m:
        sys.exit(f"enum {name} not found")
    members = {}
    value = 0
    for item in m.group(1).split(","):
        item = item.strip()
        if not item:
            continue
        if "=" in item:
            key, expr = (s.strip() for s in item.split("=", 1))
            value = int(expr, 0)
        else:
            key = item
        members[key] = value
        value += 1
    return members


def to_int32(v):
    v &= 0xffffffff
    return v - (1 << 32) if v & 0x80000000 else v


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("info_c", help="path to linuxdoom-1.10/info.c (info.h, sounds.h and p_mobj.h are read from the same directory)")
    ap.add_argument("--out", default=os.path.join(ROOT, "resources", "info"))
    ap.add_argument("--mc", default=os.path.join(ROOT, "source", "doom", "Info.mc"))
    args = ap.parse_args()

    srcdir = os.path.dirname(os.path.abspath(args.info_c))

    def read(name):
        with open(os.path.join(srcdir, name)) as f:
            return f.read()

    info_c = strip_comments(open(args.info_c).read())
    info_h = read("info.h")

    sprites = parse_enum(info_h, "spritenum_t")
    statenums = parse_enum(info_h, "statenum_t")
    mobjtypes = parse_enum(info_h, "mobjtype_t")
    sfx = parse_enum(read("sounds.h"), "sfxenum_t")
    mobjflags = parse_enum(read("p_mobj.h"), "mobjflag_t")

    numsprites = sprites.pop("NUMSPRITES")
    numstates = statenums.pop("NUMSTATES")
    nummobjtypes = mobjtypes.pop("NUMMOBJTYPES")

    symbols = {}
    for table in (sprites, statenums, mobjtypes, sfx, mobjflags):
        for k, v in table.items():
            if k in symbols and symbols[k] != v:
                sys.exit(f"{k} defined twice")
            symbols[k] = v
    symbols["FRACUNIT"] = FRACUNIT

    def value(expr):
        # Only ints, symbols, * and | show up in info.c.
        expr = expr.strip()
        if "|" in expr:
            r = 0
            for part in expr.split("|"):
                r |= value(part)
            return r
        if "*" in expr:
            r = 1
            for part in expr.split("*"):
                r *= value(part)
            return to_int32(r)
        if re.fullmatch(r"-?(0x[0-9a-fA-F]+|\d+)", expr):
            return to_int32(int(expr, 0))
        if expr in symbols:
            return symbols[expr]
        sys.exit(f"can't resolve {expr!r}")

    def body(decl):
        m = re.search(r"\b%s\s*=\s*\{(.*?)\n\};" % re.escape(decl), info_c, re.S)
        if not m:
            sys.exit(f"{decl} not found in {args.info_c}")
        return m.group(1)

    # sprnames
    sprnames = re.findall(r'"([^"]*)"', body("sprnames[NUMSPRITES]"))
    if len(sprnames) != numsprites:
        sys.exit(f"sprnames: expected {numsprites}, got {len(sprnames)}")
    for name, i in sprites.items():
        if "SPR_" + sprnames[i] != name:
            sys.exit(f"sprnames[{i}] is {sprnames[i]}, enum says {name}")

    # states
    actions = []
    states = []
    rows = re.findall(r"\{([^{}]*)\{([^{}]*)\}([^{}]*)\}", body("states[NUMSTATES]"))
    for pre, action, post in rows:
        pre = [s for s in pre.split(",") if s.strip()]
        post = [s for s in post.split(",") if s.strip()]
        action = action.strip()
        if len(pre) != 3 or len(post) != 3:
            sys.exit(f"bad state row {pre} {action} {post}")
        if action == "NULL":
            anum = 0
        else:
            if action not in actions:
                actions.append(action)
            anum = actions.index(action) + 1
        states += [value(v) for v in pre] + [anum] + [value(v) for v in post]
    if len(rows) != numstates:
        sys.exit(f"states: expected {numstates}, got {len(rows)}")

    # mobjinfo
    mobjinfo = []
    rows = re.findall(r"\{([^{}]*)\}", body("mobjinfo[NUMMOBJTYPES]"))
    for row in rows:
        fields = [s for s in row.split(",") if s.strip()]
        if len(fields) != len(MOBJINFO_FIELDS):
            sys.exit(f"mobjinfo row has {len(fields)} fields: {row}")
        mobjinfo += [value(v) for v in fields]
    if len(rows) != nummobjtypes:
        sys.exit(f"mobjinfo: expected {nummobjtypes}, got {len(rows)}")

    os.makedirs(args.out, exist_ok=True)
    resources = {"sprnames": sprnames, "states": states, "mobjinfo": mobjinfo}
    for name, data in resources.items():
        with open(os.path.join(args.out, f"{name}.json"), "w") as f:
            json.dump(data, f, separators=(",", ":"))
    with open(os.path.join(args.out, "info.xml"), "w") as f:
        f.write("<jsonDataResources>\n")
        for name in resources:
            f.write(f'    <jsonData id="{name}" filename="{name}.json" />\n')
        f.write("</jsonDataResources>\n")

    with open(args.mc, "w") as f:
        f.write(info_mc(sprites, numsprites, statenums, numstates, mobjtypes, nummobjtypes, actions))

    print(f"sprnames: {len(sprnames)}, states: {numstates}, mobjinfo: {nummobjtypes}, actions: {len(actions)}")


def info_mc(sprites, numsprites, statenums, numstates, mobjtypes, nummobjtypes, actions):
    out = []
    w = out.append
    w("""\
// info.c / info.h
//
// Thing frame/state LUT,
// generated by multigen utilitiy.
// This one is the original DOOM version, preserved.
//
// Generated by tools/info2ciq.py from info.c / info.h, don't edit by hand.
// The tables themselves are jsonData (resources/info/) loaded by
// Info_Init, stored flat: states[n * ST_SIZE + ST_TICS] is
// states[n].tics, mobjinfo[t * MI_SIZE + MI_RADIUS] is
// mobjinfo[t].radius. Sounds are sfxenum_t numbers (sounds.h), flags are
// MF_* bits (p_mobj.h) and lengths are fixed_t.

import Toybox.Lang;
import Toybox.WatchUi;

module Info {
""")

    def enum(title, members, numname, num):
        w(f"    // {title}")
        for k, v in members.items():
            w(f"    const {k} = {v};")
        w(f"    const {numname} = {num};")
        w("")

    enum("spritenum_t", sprites, "NUMSPRITES", numsprites)
    enum("statenum_t", statenums, "NUMSTATES", numstates)

    w("    // state_t field offsets.")
    for i, name in enumerate(STATE_FIELDS):
        w(f"    const ST_{name.upper()} = {i};")
    w(f"    const ST_SIZE = {len(STATE_FIELDS)};")
    w("")
    w("    // Action numbers stored in states[n * ST_SIZE + ST_ACTION]; 0 is NULL.")
    for i, name in enumerate(actions):
        w(f"    //  {i + 1:3d} {name}")
    w(f"    const NUMACTIONS = {len(actions) + 1};")
    w("")

    enum("mobjtype_t", mobjtypes, "NUMMOBJTYPES", nummobjtypes)

    w("    // mobjinfo_t field offsets.")
    for i, name in enumerate(MOBJINFO_FIELDS):
        w(f"    const MI_{name.upper()} = {i};")
    w(f"    const MI_SIZE = {len(MOBJINFO_FIELDS)};")
    w("")

    w("""\
    // NUMSPRITES 4-letter sprite names, e.g. sprnames[SPR_TROO] is "TROO".
    var sprnames as Array<String> = [] as Array<String>;

    // NUMSTATES * ST_SIZE numbers.
    var states as Array<Number> = [] as Array<Number>;

    // NUMMOBJTYPES * MI_SIZE numbers.
    var mobjinfo as Array<Number> = [] as Array<Number>;

    function Info_Init() as Void {
        sprnames = WatchUi.loadResource(Rez.JsonData.sprnames) as Array<String>;
        states = WatchUi.loadResource(Rez.JsonData.states) as Array<Number>;
        mobjinfo = WatchUi.loadResource(Rez.JsonData.mobjinfo) as Array<Number>;
    }
}
""")
    return "\n".join(out)


if __name__ == "__main__":
    main()
