# iOS: export, signing and the device loop

Split out of `CLAUDE.md`. Read this before exporting, signing or installing to the phone.

## Export

**iOS export** — use `Tools/export_ios.sh`, which already sets the environment the export needs. Templates live at `~/Library/Application Support/Godot/export_templates/4.7.2.stable/ios.zip`; the preset has `export_project_only=true`, so what you want out of it is `build/ios/noblestars3d.xcodeproj`.

- **`export_presets.cfg` has NO comment syntax that survives — `#` lines silently eat the key that follows.** It is parsed by Godot's ConfigFile, which knows `;` and not `#`, and the failure is quiet: a `#` block written between two options had the first one read and the second one dropped, so a setting that is plainly there in the file has no effect. The editor also rewrites this file and would strip comments anyway. **Keep the preset bare and put the reasoning here.**
- **The launch storyboard defaulted to `contentMode="center"`, which is why a fresh install came up SMALL.** Godot writes the same 1920x1080 splash to both `@2x` and `@3x`, so at @3x iOS reads it as 640x360 points on an 852x393 point screen and draws it smaller than the display with a border all round — and because iOS holds the storyboard until Godot's first frame, a cold first launch sits on it for several seconds and it is very visible. `storyboard/image_scale_mode=2` (Scale to Fit, `scaleAspectFit`) matches what the engine boot splash does a moment later, so the handoff is seamless; Scale to Fill would crop ~9% off the bottom of a 19.5:9 screen, which is where the title and loading bar are anchored. **Verify by grepping `contentMode` in `build/ios/noblestars3d/Launch Screen.storyboard` after an export** — the enum is `Same as Logo,Center,Scale to Fit,Scale to Fill,Scale`, readable out of the Godot binary with `strings`.
- **The export REQUIRES `rendering/textures/vram_compression/import_etc2_astc=true`** in project.godot. Without it validation fails with an EMPTY error message.
- **Godot's `targeted_device_family` enum is 0=iPhone 1=iPad 2=both**, which is not Apple's numbering.
- **Set `DEVELOPER_DIR` when exporting.** `xcode-select` points at CommandLineTools, and Godot shells out to `xcodebuild` internally, so the export dies at "Making .xcarchive" with `tool 'xcodebuild' requires Xcode`. The `.xcodeproj` is already written by that point, so the failure is cosmetic — but the exporter reports the whole export as failed, which reads like a real problem.
- **The pbxproj placeholder repair is no longer needed.** Older templates left six unreplaced `$additional_pbx_*`/`$pbx_embeded_frameworks` lines that had to be deleted before `xcodebuild` would parse the project. 4.7.2 emits zero. `export_ios.sh` still checks and reports.
- **Simulator builds are blocked upstream**: godotengine/godot#118161 — 4.6.2+ templates ship simulator `libgodot.a` as x86_64-only and Xcode 26 has no Rosetta simulators; test on a real device until fixed templates ship.

## Getting it onto a phone

**Getting it onto a phone.** `xcrun devicectl` is the tool, and `connectionProperties` from `xcrun devicectl list devices --json-output <path>` is the only signal that tracks reality: `transportType` (`None` = not connected), `pairingState` (`pairingInProgress` = a Trust prompt is waiting on the phone) and `tunnelState`. **`system_profiler SPUSBDataType` does NOT enumerate iPhones on this Mac** — it reported zero the entire time a wired transport was live, and reading it as ground truth led to a long, wrong hunt for a bad cable. Also do not grep device state for `available`: `unavailable` contains it.

## Signing

**Signing: `No Account for Team` has had TWO causes here, and the second one hid behind the first.** The one to check now is the **team id in the preset**: `application/app_store_team_id` named `KJDG3J6ZYY`, which is a.carlson14@gmail.com's free personal team, while the account actually develops under the paid team `S7AT3UP8R4` ("ANDREW DWIGHT CARLSON"). Godot wrote the wrong id into `DEVELOPMENT_TEAM`, so the archive step really did have no account for the team it was naming. Corrected in the preset on 2026-09-05, and `Tools/export_ios.sh` now runs end to end — `** EXPORT SUCCEEDED **`, no errors, an `.ipa` on disk. Tell the two apart by reading the profile rather than the error: `security cms -D -i <app>/embedded.mobileprovision` prints `TeamIdentifier` and `TeamName`, and that is the team the preset has to name.

**A successful export still PRINTS `KJDG3J6ZYY`, and it is not the bug above.** `xcodebuild`'s log names the signing certificate — `Signing Identity: "Apple Development: a.carlson14@gmail.com (KJDG3J6ZYY)"` — and that parenthetical is the CERTIFICATE's identifier, not the team the build is signed for. Read against the paragraph above it looks exactly like the preset regressing to the free personal team, which is a false alarm that has already cost one session a detour. The profile is what settles it, and on the 2026-09-06 export it said `TeamName ANDREW DWIGHT CARLSON`, `TeamIdentifier S7AT3UP8R4`, `TimeToLive 365`, expiring 2027-09-05 — the paid team, the year-long profile. Check it out of the `.ipa` rather than hunting for an `.app`, which the project-only export does not leave in `build/ios/`:

```sh
cd $(mktemp -d) && unzip -q -o <repo>/build/ios/noblestars3d.ipa 'Payload/*/embedded.mobileprovision'
security cms -D -i Payload/*/embedded.mobileprovision > prov.plist
/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier' -c 'Print :TimeToLive' prov.plist
```

The older cause, which is the one the rest of this section is about: **a signing-identity CONFLICT, not a missing account.** Godot writes `CODE_SIGN_IDENTITY = "Apple Distribution"` into the Release configuration while also setting `CODE_SIGN_STYLE = Automatic`. Xcode will not reconcile those, and the conflict poisons provisioning for the whole target — including Debug — which surfaces from the command line as `No Account for Team "<id>"` and `No profiles for '<bundle>' were found`. Both point at the account, and the account is fine. An evening went into that misdirection; what identified it was the Signing & Capabilities pane in the Xcode GUI, which says plainly `noblestars3d has conflicting provisioning settings`. **When signing fails, open the project and read that pane before touching accounts.**

The fix is in the preset, so re-exports stay correct. Development signing on **both** configurations is right for the side-load workflow this has used until now:

```
application/app_store_team_id="S7AT3UP8R4"   # the PAID team, not KJDG3J6ZYY
application/code_sign_identity_debug="Apple Development"
application/code_sign_identity_release="Apple Development"
application/export_method_release=1     # development, not App Store (0)
```

With that, `xcodebuild -allowProvisioningUpdates` signs and builds with no GUI step at all.

## Beta changes the signing

**⚠ Beta changes this, and the change walks back toward the trap above.** `ROADMAP.md` commits to a **TestFlight closed beta**, which cannot be fed a development-signed build: it needs `export_method_release=0` and `Apple Distribution` on Release — which is exactly the identity whose conflict with `CODE_SIGN_STYLE = Automatic` cost the evening described two paragraphs up. So the sentence "Development signing is right for both configurations" is true of side-loading and **false of TestFlight**, and whoever makes that switch should expect the `No Account for Team` symptom to reappear pointing, once again, at the wrong thing. Do it in this order: change Release only, leave Debug on `Apple Development` so device installs keep working, then open the generated project and read the **Signing & Capabilities** pane before believing any command-line error. The side-load path must keep working throughout — it is how the phone-fit P0s get tested. Note that `~/Library/MobileDevice/Provisioning Profiles/` can be EMPTY and `defaults read com.apple.dt.Xcode IDEProvisioningTeams` absent even on a build that then succeeds — they look like the signing health check and are not one.

## The device loop

**Use `Tools/device_install.sh` and `Tools/device_shot.sh`.** Between them the
whole handset loop — export, build, install, run with debug hooks, screenshot,
pull the PNG back — is two commands and needs no Xcode and **nobody looking at
the phone**:

```sh
Tools/device_install.sh                                     # export + xcodebuild + install
Tools/device_shot.sh --out shots NS3_KIT=nova NS3_SHOTS=run:3,9
Tools/device_shot.sh --out shots NS3_MENU_SHOT=m.png NS3_MENU_SCREEN=roster
```

**This is the single most useful thing to know about testing here**, because
ROADMAP.md is written around the assumption that a device screenshot is a round
trip through Ryder and is therefore the slowest loop in the project. It is not,
and it works because three facts compose: `devicectl device process launch -e
'{"K":"V"}'` passes environment variables in, so **every `NS3_*` hook works on
the phone**; `NS3_SHOTS`/`NS3_MENU_SHOT` resolve a relative path against
`user://`, which on iOS is the app's `Documents/`; and `devicectl device copy
from --domain-type appDataContainer --domain-identifier com.ryder.noblestars3d`
reads that directory for a development-signed app. Four sharp edges, all
handled inside the scripts:

- **`--console` hangs.** It attaches and never returns even after the app has
  exited and written its file. Poll for the file instead — which is also the
  real completion signal, since `NS3_SHOTS` quits the game once it has written
  the last frame.
- **`copy from --destination` must be a FILE path.** A directory fails with
  `Cannot open destination file …: Is a directory`.
- **Pick the device out of `--json-output`, never the printed table.** The State
  column is prose that changes under you — `connected` one minute,
  `available (paired)` the next — and per the warning above, `unavailable`
  contains `available`. The test is `connectionProperties.transportType` being
  present and `tunnelState != "unavailable"`; a `disconnected` tunnel reconnects
  on demand and is fine.
- **There is no delete in `devicectl`**, so shots pile up in the container. Use
  a fresh name per run rather than assuming one is free.

**Xcode keeps TWO `Debug-iphoneos` trees and installing the wrong one looks like
a signing failure.** `<derived>/Index.noindex/Build/Products/Debug-iphoneos/`
holds the indexer's stub `.app`, whose `Info.plist` has no `CFBundleIdentifier`;
`devicectl` refuses it with `Failed to get the identifier for the app to be
installed`. It is one level deeper than the real bundle, so the `-maxdepth 6`
form below matches either, whichever `find` reaches first. Use `-maxdepth 5
-not -path '*Index.noindex*'`, as the script does.

By hand, if a script is not to hand:

```sh
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name 'noblestars3d.app' \
    -path '*Debug-iphoneos*' -not -path '*Index.noindex*' -print -quit)
xcrun devicectl device install app --device <udid> "$APP"
xcrun devicectl device process launch --device <udid> com.ryder.noblestars3d
xcrun devicectl device info processes --device <udid> | grep noblestars3d   # still alive?
```

That last line matters: a Godot iOS build can launch and die immediately on a texture or shader problem, and the launch command reports success either way. **This signs under a PAID developer account**, so the profile is good for a year (`TimeToLive 365`, read off `embedded.mobileprovision`) — the 7-day expiry that forces a weekly reinstall is a free personal team, and does not apply here. **`devicectl` needs `DEVELOPER_DIR` too**, exactly like the export: `xcode-select` points at CommandLineTools, so a bare `xcrun devicectl` fails with `unable to find utility "devicectl"`. And an install onto a phone that has never run a development build stops with `Developer Mode is disabled` — that is Settings > Privacy & Security > Developer Mode on the phone, followed by a restart, and it cannot be done from here.
