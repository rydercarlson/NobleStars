#!/bin/bash
# Shoot the game on the actual iPhone and bring the PNGs back to this machine.
#
#   Tools/device_shot.sh --out <dir> NS3_KIT=nova NS3_SHOTS=run:3,9
#   Tools/device_shot.sh --out <dir> NS3_MENU_SHOT=menu.png NS3_MENU_SCREEN=roster
#
# Why this exists: ROADMAP.md calls the device round trip "the slowest feedback
# loop in the project" and puts it on the critical path for three of the four
# P0s, because the phone is Ryder's and a desktop window cannot reproduce a
# notch, a safe area or a 19.5:9 aspect. It turns out not to need his eyes at
# all — three devicectl facts make the whole loop scriptable:
#
#   1. `devicectl device process launch -e '{...}'` passes environment
#      variables into the app, so every NS3_* debug hook works on the handset
#      exactly as it does on the desktop.
#   2. NS3_SHOTS / NS3_MENU_SHOT resolve a non-absolute path against `user://`,
#      which on iOS is the app's own Documents directory.
#   3. `devicectl device copy from --domain-type appDataContainer` reads that
#      directory for a development-signed app.
#
# So: launch with hooks, wait for the file to appear, pull it. No Xcode, no
# cable-watching, no asking anyone to look at a phone.
#
# Notes earned getting this working:
#   - `--console` HANGS. It attaches and never returns even after the app has
#     exited and written its file; this script polls the container instead.
#   - `--destination` must be a FILE path. Given a directory it fails with
#     "Cannot open destination file ...: Is a directory".
#   - devicectl needs DEVELOPER_DIR, exactly like the export does, because
#     xcode-select points at CommandLineTools on this machine.
#   - There is no "delete file" in devicectl, so old shots accumulate in the
#     container. Use a fresh prefix per run (the default is a timestamp) rather
#     than trusting that a name is free.
#   - The app must already be installed, and this does not build it. See
#     CLAUDE.md's "Install and launch from the command line".

set -euo pipefail

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

BUNDLE="${BUNDLE:-com.ryder.noblestars3d}"
OUTDIR=""
DEVICE="${NS3_DEVICE:-}"
TIMEOUT=90
ENV_ARGS=()

usage() {
    sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUTDIR="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        *=*) ENV_ARGS+=("$1"); shift ;;
        *) echo "error: unexpected argument '$1'" >&2; usage 1 ;;
    esac
done

if [[ -z "$OUTDIR" ]]; then
    echo "error: --out <dir> is required" >&2
    exit 1
fi
if [[ ${#ENV_ARGS[@]} -eq 0 ]]; then
    echo "error: give at least one KEY=VALUE hook (NS3_SHOTS or NS3_MENU_SHOT)" >&2
    exit 1
fi
mkdir -p "$OUTDIR"

# The first reachable device, unless one was named. This reads
# connectionProperties out of --json-output rather than the printed table, for
# the two reasons CLAUDE.md records: the State column is prose that changes
# under you ("connected" one minute, "available (paired)" the next), and
# `unavailable` contains `available`, so no grep for a word is safe. A device
# is reachable when it has a transportType at all and its tunnel is not
# `unavailable`; a disconnected tunnel reconnects on demand.
if [[ -z "$DEVICE" ]]; then
    _devjson=$(mktemp -t nsdev)
    xcrun devicectl list devices --json-output "$_devjson" >/dev/null 2>&1 || true
    DEVICE=$(python3 - "$_devjson" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for dev in devices:
    conn = dev.get("connectionProperties") or {}
    if conn.get("transportType", "None") == "None":
        continue
    if conn.get("tunnelState") == "unavailable":
        continue
    print(dev["identifier"])
    break
PY
)
    rm -f "$_devjson"
fi
if [[ -z "$DEVICE" ]]; then
    echo "error: no connected device. Check the cable and the Trust prompt:" >&2
    echo "       xcrun devicectl list devices" >&2
    exit 1
fi

# Build the JSON dict devicectl wants, and work out which files to wait for.
# NS3_SHOTS is "prefix:t1,t2,..." and writes <prefix>_<t>.png per time;
# NS3_MENU_SHOT is a single path. Both resolve against user:// unless absolute,
# and an absolute path on the phone is not somewhere this can read, so refuse.
JSON="{"
WANT=()
for kv in "${ENV_ARGS[@]}"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    [[ "$JSON" != "{" ]] && JSON+=","
    JSON+="\"$key\":\"$val\""
    case "$key" in
        NS3_SHOTS)
            prefix="${val%%:*}"
            times="${val#*:}"
            if [[ "$prefix" == /* ]]; then
                echo "error: NS3_SHOTS prefix must be relative so it lands in user://" >&2
                exit 1
            fi
            IFS=',' read -ra ts <<< "$times"
            for t in "${ts[@]}"; do
                WANT+=("${prefix}_${t}.png")
            done
            ;;
        NS3_MENU_SHOT)
            if [[ "$val" == /* ]]; then
                echo "error: NS3_MENU_SHOT must be relative so it lands in user://" >&2
                exit 1
            fi
            WANT+=("$val")
            ;;
    esac
done
JSON+="}"

if [[ ${#WANT[@]} -eq 0 ]]; then
    echo "error: no NS3_SHOTS or NS3_MENU_SHOT among the hooks — nothing to fetch" >&2
    exit 1
fi

echo "device  $DEVICE"
echo "hooks   $JSON"
echo "expect  ${WANT[*]}"

xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
    --environment-variables "$JSON" "$BUNDLE" >/dev/null 2>&1

# Poll the container rather than the process: NS3_SHOTS quits the game once it
# has written the last frame, so the file appearing is the real completion
# signal and the process list races against it.
listing="$OUTDIR/.listing"
deadline=$((SECONDS + TIMEOUT))
while true; do
    xcrun devicectl device info files --device "$DEVICE" \
        --domain-type appDataContainer --domain-identifier "$BUNDLE" \
        > "$listing" 2>/dev/null || true
    missing=0
    for f in "${WANT[@]}"; do
        grep -q "Documents/$f " "$listing" || missing=1
    done
    [[ $missing -eq 0 ]] && break
    if [[ $SECONDS -ge $deadline ]]; then
        echo "error: timed out after ${TIMEOUT}s waiting for: ${WANT[*]}" >&2
        echo "       (a shot time past the end of the match never fires; and a" >&2
        echo "        script parse error only shows when the game runs — check" >&2
        echo "        with 'devicectl device info processes')" >&2
        exit 1
    fi
    sleep 2
done
rm -f "$listing"

for f in "${WANT[@]}"; do
    xcrun devicectl device copy from --device "$DEVICE" \
        --domain-type appDataContainer --domain-identifier "$BUNDLE" \
        --source "Documents/$f" --destination "$OUTDIR/$(basename "$f")" >/dev/null 2>&1
    echo "wrote   $OUTDIR/$(basename "$f")  $(file -b "$OUTDIR/$(basename "$f")" | cut -d, -f2-)"
done
