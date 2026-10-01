# doom-on-garmin

An attempt to get Doom running on a Garmin Forerunner 965 (454×454 AMOLED) as a Connect IQ watch app.

Connect IQ only runs Monkey C bytecode, so no native C code and no custom firmware. That means Doom can't be recompiled for the watch. It has to be rewritten in Monkey C, with the game data shrunk to fit in app memory.

## Roadmap

1. **Raycaster (current).** A Wolfenstein-style DDA renderer that measures how many frames per second the watch can draw.
2. **Doom data.** A Python tool that converts shareware `doom1.wad` (E1) maps, palette and a few textures into compact Connect IQ resources.
3. **Doom renderer.** Draw Doom levels the way Doom does (BSP + sectors), within whatever frame rate stage 1 shows is possible.

## Build

You'll need the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) with the `fr965` device files (from the SDK Manager, which needs a Garmin login), Python 3, and the shareware `doom1.wad` (v1.9, md5 `f0cefca49926d00903cf57551d901abe`).

```sh
# one-time developer key, kept outside the repo
openssl genrsa -out key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out ~/.Garmin/developer_key.der -nocrypt && rm key.pem

DOOM_WAD=path/to/doom1.wad ./build.sh           # bin/DoomIQ.prg
DOOM_WAD=path/to/doom1.wad ./build.sh run       # run in the simulator
DOOM_WAD=path/to/doom1.wad ./build.sh install   # copy to a watch plugged in over USB
```

`build.sh` runs `tools/wad2ciq.py` first, which unpacks the map lumps into `resources/generated/`. Connect IQ apps can't read files, so the WAD data is built into the app. The trig tables in `resources/tables/` were extracted from the original `tables.c` with `tools/tables2ciq.py`.

## Controls

| Input | Action |
|---|---|
| UP / DOWN (hold) | turn left / right |
| START (hold) | walk forward |
| BACK | quit |
| Touch: left / right third | turn |
| Touch: middle | walk forward |
| Touch: bottom edge | walk back |

## License

GPL-2.0, the license of the [Doom source release](https://github.com/id-Software/DOOM), so Doom code can be reused later. This repo doesn't include any WAD files; supply your own `doom1.wad`.
