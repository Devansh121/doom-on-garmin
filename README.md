# doom-on-garmin

An attempt to get Doom running on a Garmin Forerunner 965 (454×454 AMOLED) as a Connect IQ watch app.

Connect IQ only runs Monkey C bytecode, so no native C code and no custom firmware. That means Doom can't be recompiled for the watch. It has to be rewritten in Monkey C, with the game data shrunk to fit in app memory.

## Roadmap

1. **Raycaster (current).** A Wolfenstein-style DDA renderer that measures how many frames per second the watch can draw.
2. **Doom data.** A Python tool that converts shareware `doom1.wad` (E1) maps, palette and a few textures into compact Connect IQ resources.
3. **Doom renderer.** Draw Doom levels the way Doom does (BSP + sectors), within whatever frame rate stage 1 shows is possible.

## Build

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and the `fr965` device files. Install the device files via the SDK Manager, which needs a Garmin login.

```sh
SDK=~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0
# one-time developer key (keep it out of the repo)
openssl genrsa -out key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out ~/.Garmin/developer_key.der -nocrypt && rm key.pem

$SDK/bin/monkeyc -d fr965 -f monkey.jungle -o bin/DoomIQ.prg -y ~/.Garmin/developer_key.der
$SDK/bin/connectiq &                    # simulator
$SDK/bin/monkeydo bin/DoomIQ.prg fr965  # run in simulator
```

To sideload, copy `bin/DoomIQ.prg` to `GARMIN/APPS/` on the watch over USB (MTP).

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
