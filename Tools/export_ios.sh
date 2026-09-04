#!/bin/bash
# Exports the Godot 3D game as an Xcode project, with the environment the
# export needs and the post-export repair it used to need done by hand.
#
# The "iOS" preset has export_project_only=true, so what you want out of this
# is build/ios/noblestars3d.xcodeproj. (The CLI exporter ignores that flag and
# tries to archive anyway — see EXPORT_STATUS below.)
#
#   Tools/export_ios.sh              # debug export
#   Tools/export_ios.sh --release    # release export
#
# Two things this exists to handle, and one it cannot:
#
# 1. The generated project.pbxproj used to contain six unreplaced template
#    placeholders — bare `$additional_pbx_*` and `$pbx_embeded_frameworks`
#    lines that are not valid pbxproj syntax — which had to be deleted by hand
#    before xcodebuild would parse the file. Measured against the 4.7.2.stable
#    templates on 2026-09-03 there are now NONE: the strip below finds nothing
#    and says so. It stays as a guard in case a template regresses.
# 2. xcode-select points at CommandLineTools here, which the export needs
#    overridden — see DEVELOPER_DIR below.
#
# 3. What it cannot fix: the archive step fails with
#      No Account for Team "KJDG3J6ZYY"
#      No profiles for 'com.ryder.noblestars3d' were found
#    That is not scriptable — sign into Xcode > Settings > Accounts with the
#    Apple ID on that team once, and let it create the development profile.
#    The Xcode project is written either way, so this is only in the way of a
#    one-command signed build, not of opening the project and hitting Run.
#
# Note that SIMULATOR builds are blocked upstream (godotengine/godot#118161:
# the 4.6.2+ templates ship a simulator libgodot.a that is x86_64-only and
# Xcode 26 has no Rosetta simulators) — use a real device.

set -euo pipefail

# xcode-select points at CommandLineTools on this machine, and Godot shells out
# to xcodebuild for the archive step at the end of an iOS export. Without this
# the export dies with "tool 'xcodebuild' requires Xcode" after it has already
# written the project — the same DEVELOPER_DIR the v1 SpriteKit builds need.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/ios/noblestars3d.ipa"
PBXPROJ="$ROOT/build/ios/noblestars3d.xcodeproj/project.pbxproj"

MODE="--export-debug"
if [[ "${1:-}" == "--release" ]]; then
    MODE="--export-release"
fi

if [[ ! -x "$GODOT" ]]; then
    echo "error: no Godot binary at $GODOT (set GODOT=<path>)" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"

# --headless, and the import first: exporting without an up-to-date .godot
# cache silently ships stale resources, and a fresh clone has no cache at all.
"$GODOT" --path "$ROOT/godot" --headless --import

# The exporter writes the Xcode project and THEN tries to archive it, so a
# failure in that last step still leaves a usable project behind. The project
# on disk is the thing we actually want, so it — not the exit code — is the
# test for whether this worked.
EXPORT_STATUS=0
"$GODOT" --path "$ROOT/godot" --headless "$MODE" "iOS" "$OUT" || EXPORT_STATUS=$?

if [[ ! -f "$PBXPROJ" ]]; then
    echo "error: export produced no $PBXPROJ (godot exited $EXPORT_STATUS)" >&2
    exit 1
fi
if [[ "$EXPORT_STATUS" -ne 0 ]]; then
    echo "note: godot exited $EXPORT_STATUS (its archive step), but the Xcode project was written"
fi

# The placeholders are whole lines. Matched on the literal `$`-prefixed names
# rather than on a line number, because the count and their positions move
# between template versions.
LEFTOVER=$(grep -c -e '\$additional_pbx_' -e '\$pbx_embeded_frameworks' "$PBXPROJ" || true)
if [[ "$LEFTOVER" -gt 0 ]]; then
    sed -i '' -e '/\$additional_pbx_/d' -e '/\$pbx_embeded_frameworks/d' "$PBXPROJ"
    echo "stripped $LEFTOVER unreplaced pbxproj placeholder line(s)"
else
    echo "no pbxproj placeholders to strip (template may be fixed upstream)"
fi

# Cheap proof the file now parses, so a broken export fails here rather than
# inside Xcode twenty minutes later.
if command -v plutil >/dev/null 2>&1; then
    if plutil -lint "$PBXPROJ" >/dev/null 2>&1; then
        echo "project.pbxproj parses"
    else
        echo "warning: project.pbxproj still does not parse — check it by hand" >&2
    fi
fi

echo "wrote $ROOT/build/ios/noblestars3d.xcodeproj"
