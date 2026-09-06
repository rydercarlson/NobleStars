#!/bin/bash
# Export, build and install the game onto the connected iPhone, end to end.
#
#   Tools/device_install.sh
#
# The three steps were already written down separately — Tools/export_ios.sh
# for the Xcode project, and CLAUDE.md's "Install and launch from the command
# line" for the devicectl half — with an unwritten xcodebuild in the middle.
# This is the whole chain, so that changing a script and seeing it on the phone
# is one command and cannot skip the export the way doing it by hand does.
#
# Pair it with Tools/device_shot.sh, which drives the installed build with the
# NS3_* hooks and brings the screenshots back.
#
# Things that bite here, all of them recorded in CLAUDE.md at more length:
#   - DEVELOPER_DIR must point at Xcode. xcode-select points at
#     CommandLineTools on this machine, and both the export's archive step and
#     devicectl itself fail without it.
#   - `-allowProvisioningUpdates` is what makes signing work with no GUI step,
#     given the preset names the PAID team (S7AT3UP8R4) and Apple Development
#     on both configurations.
#   - A Godot iOS build can launch and die immediately on a shader problem, and
#     the launch command reports success either way. Check it is still alive.

set -euo pipefail

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${BUNDLE:-com.ryder.noblestars3d}"
CONFIG="${CONFIG:-Debug}"
DEVICE="${NS3_DEVICE:-}"

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
    echo "error: no connected device (xcrun devicectl list devices)" >&2
    exit 1
fi

echo "==> exporting"
"$ROOT/Tools/export_ios.sh" | tail -3

echo "==> building ($CONFIG)"
xcodebuild -project "$ROOT/build/ios/noblestars3d.xcodeproj" \
    -scheme noblestars3d -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' -allowProvisioningUpdates \
    build 2>&1 | tail -5

# -maxdepth 5, and Index.noindex excluded, both deliberately. Xcode keeps a
# SECOND Debug-iphoneos tree under <derived>/Index.noindex/Build/Products for
# the indexer, one level deeper, and its .app is a stub whose Info.plist has no
# CFBundleIdentifier — devicectl then fails with "Failed to get the identifier
# for the app to be installed", which reads like a signing problem and is not.
# The -maxdepth 6 form in CLAUDE.md can match either, whichever find reaches
# first.
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name 'noblestars3d.app' \
    -path "*${CONFIG}-iphoneos*" -not -path '*Index.noindex*' -print -quit)
if [[ -z "$APP" ]]; then
    echo "error: no built .app under DerivedData for $CONFIG-iphoneos" >&2
    exit 1
fi
echo "==> installing $APP"
xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | tail -3
echo "==> installed on $DEVICE"
