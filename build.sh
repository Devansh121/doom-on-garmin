#!/usr/bin/env bash
# Build Doom IQ for the Forerunner 965.
#
#   ./build.sh            convert WAD data if needed, then compile bin/DoomIQ.prg
#   ./build.sh run        ... and run it in the simulator
#   ./build.sh install    ... and copy it to a watch connected over USB (MTP)
#   ./build.sh test       build with unit tests and run them in the simulator
#
# Env: CIQ_SDK (SDK dir), DOOM_WAD (path to doom1.wad), CIQ_KEY (developer key).
set -euo pipefail
cd "$(dirname "$0")"

DEVICE=fr965
SDK=${CIQ_SDK:-$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-* 2>/dev/null | sort -V | tail -1)}
WAD=${DOOM_WAD:-doom1.wad}
KEY=${CIQ_KEY:-$HOME/.Garmin/developer_key.der}
GEN=generated/resources

[ -x "$SDK/bin/monkeyc" ] || { echo "Connect IQ SDK not found, set CIQ_SDK" >&2; exit 1; }
[ -f "$KEY" ] || { echo "developer key $KEY not found, see README" >&2; exit 1; }

if [ ! -f "$GEN/maps.xml" ] || [ "$WAD" -nt "$GEN/maps.xml" ]; then
    [ -f "$WAD" ] || { echo "$WAD not found, set DOOM_WAD" >&2; exit 1; }
    python3 tools/wad2ciq.py "$WAD"
fi

mkdir -p bin
if [ "${1:-}" = test ]; then
    "$SDK/bin/monkeyc" -d "$DEVICE" -f monkey.jungle -o bin/DoomIQ-test.prg -y "$KEY" -t
    pgrep -f "$SDK/bin/simulator" >/dev/null || { "$SDK/bin/connectiq" & sleep 5; }
    exec "$SDK/bin/monkeydo" bin/DoomIQ-test.prg "$DEVICE" -t
fi
"$SDK/bin/monkeyc" -d "$DEVICE" -f monkey.jungle -o bin/DoomIQ.prg -y "$KEY" -w

case "${1:-}" in
    run)
        pgrep -f "$SDK/bin/simulator" >/dev/null || { "$SDK/bin/connectiq" & sleep 5; }
        "$SDK/bin/monkeydo" bin/DoomIQ.prg "$DEVICE"
        ;;
    install)
        apps=$(ls -d /run/user/"$(id -u)"/gvfs/mtp:host=091e_*/*/GARMIN/Apps 2>/dev/null | head -1 || true)
        [ -n "$apps" ] || { echo "no Garmin watch mounted over MTP" >&2; exit 1; }
        gio copy bin/DoomIQ.prg "$apps/DoomIQ.prg"
        echo "copied to $apps, unplug the watch to install"
        ;;
esac
