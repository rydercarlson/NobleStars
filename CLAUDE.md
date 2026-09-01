# Noble Stars

Brawl Stars–inspired top-down arena battler (Showdown mode: last fighter standing, shrinking gas ring, loot-box power cubes). **Active development is the 3D Godot 4 game in `godot/`.** The original SpriteKit iOS game (`NobleStars/`) is v1 — complete, kept working, but not being extended.

## Godot 3D game (`godot/`) — main development

Godot 4.7, everything built in code (the `.tscn` files are near-empty shells). Entry scene is `menu.tscn` (Brawl Stars–style lobby, see below); `game.tscn` is the match.

**The menu is native Godot and is the only menu.** Screens live in `godot/scripts/menu/` (home, brawlers grid + detail, shop, pass, trophy road, modes, matchmaking, news, friends, club, inbox, popups) on top of `menu.gd` (`MenuShell`), with `menu_ui.gd` (widgets + `ICON_DIR`/`PNG_ICON_DIR`/font constants), `menu_data.gd` (`MenuData` — loads `godot/data/{brawlers,game}.json`, resolves art by id via `portrait()` / `card_art()`), `menu_audio.gd` (sounds synthesised at runtime, no audio files), `menu_stage.gd` (3D fighter showcase). Menu art is `godot/assets/menu/{background,buttons via btn_*.png,icons,svg,portraits,cards,treats,decor,fonts}`. **Stats come from `kits.gd`, never from `brawlers.json`** — the JSON carries copy, art ids and shop/pass/news config only. The HTML build this was ported from (`web-menu/`) has been deleted: a browser page cannot ship inside the iOS app, and its art now lives under `godot/assets/menu/`. Scripts live in `godot/scripts/`: `main.gd` is the match hub (mirrors v1's GameScene), plus `fighter.gd`, `arena.gd`, `bot_brain.gd`, `gas_ring.gd`, `kits.gd` (character data), `projectile.gd`/`lob.gd`, `virtual_joystick.gd`, `super_button.gd`, `session.gd`. `ui_kit.gd` holds the older navy/gold StyleBoxFlat helpers still used by `room_screen.gd`. `save_game.gd` (`SaveGame` statics → JSON at `user://save.json`: per-fighter trophies, coins, selections; Showdown ranks 1–10 award +8,+6,+5,+4,+3,+1,0,0,−1,−2 trophies and `max(2, 22−2·rank)` coins via `SaveGame.award_match`, called from `main.gd:_end_match`).

Run it: `/Applications/Godot.app/Contents/MacOS/Godot --path godot` (add `--headless --import` after adding files — REQUIRED after new scripts too, or class members silently vanish at runtime).

**Wifi multiplayer** (`net_play.gd` autoload `Net`, `room_screen.gd`, net section at the bottom of `main.gd`): host-authoritative LAN play over ENet (port 42537). The host runs the exact single-player sim (bots fill empty Showdown slots); clients send stick input + fire requests up as RPCs and render 30Hz snapshots (positions/health/ammo/super) plus reliable events (attacks, eliminations, loot boxes, cubes, wall breaks) — `authoritative` in main.gd gates every mutation so client-side projectiles stay visual-only. Rooms: lobby → WIFI MATCH → host or join (UDP broadcast discovery on 42538, join-by-IP fallback — iOS can't receive broadcast replies without Apple's multicast entitlement, so on iPhone use join-by-IP). The host's own death shows results but the match keeps simulating; only the host gets PLAY AGAIN. Client fighters are pure puppets (no prediction) — fine on LAN RTTs.

**Current state:** full Showdown match playable — seven kits (Nova shotgun, Tony lob, Henry melee/dash, Sanjit fast melee/boomerang, Kovacs tank clap/jump-smash, Leon controller buttons/disconnect, Anders hacky-sack control), bots, gas ring, loot, twin floating touch sticks (move left half, aim right half — release fires, tap auto-aims), drawn Super button, results overlay (awards trophies/coins into the save). Desktop fallbacks: WASD, Space auto-aim, E Super. Menu is a Brawl Stars–style lobby: selected fighter's GLB idling center-stage (capsule fallback), PLAY + mode button bottom-right, Shop/Fighters/news banner left, trophies+coins top bar; screens for fighter select (grid → stat-bar detail view), events (Showdown + locked dummy modes), shop/trophy-road/settings placeholders. Only "showdown" launches; `Session.mode` + the `_mode` hook at the top of `main.gd:start_match` are where real new modes branch in.

**Where it's going:**
- Replace the placeholder capsule fighters with rigged Meshy GLB characters. Tony is wired first (`kits.gd` `model`/`clips` keys → `fighter.gd` loads the GLB and drives idle/run/attack clips); Henry and the rest follow the same pattern. A kit without a `model` key falls back to the capsule.
- Arena visual pass — the floor is currently a single flat plane, walls are boxes.
- Ship to a real iPhone via the iOS export (see below).
- Sound effects, and voicelines recorded by the people the characters are based on.
- New characters are Ryder's designs — ideas live in `plans.md`; ask before building one. Stat them with `CHARACTER_BUILDING.md` (tier tables for health/speed/reload/range, the damage formula that derives from them, and the 5.5-tile on-screen range cap) — damage is derived, never picked by taste.

**Debug env hooks** (mirror the v1 ones): `NS3_KIT=nova|tony|henry|sanjit|kovacs|leon|anders`, `NS3_AUTOFIRE=<sec>`, `NS3_AUTOWALK="x,z"`, `NS3_GODMODE=1`, `NS3_SUPER=1` (start with Super charged), `NS3_SHOTS="prefix:t1,t2,..."` (match-time screenshots, then quits), `NS3_MENU_SHOT=<path.png>` (menu screenshot, then quits; combine with `NS3_MENU_SCREEN=lobby|fighters|modes|shop|road|settings` to shoot a specific screen, and `NS3_MENU_DETAIL=<kit>` with `NS3_MENU_SCREEN=fighters` for the fighter detail view), `NS3_RESET_SAVE=1` (delete the save, start fresh), `NS3_SIM=<n>` (balance sim: n all-bot matches at 10x speed, per-kit win/placement/damage table to stdout, then quits — run with `--headless`; the table's `hits/atk` column should sit near a kit's projectile count, and anything near zero means shots aren't landing, which is a delivery bug rather than a balance one — see `CHARACTER_BUILDING.md`), `NS3_SIM_SPEED=<n>` (override the sim's 10x time scale; re-run at 2 to tell physics artifacts from real balance). NS3_KIT/NS3_AUTOFIRE/NS3_SIM skip the menu. Net hooks (beat the single-player hooks): `NS3_HOST=<n>` hosts and auto-starts once n players are in the room, `NS3_JOIN=<ip>` joins — two windowed instances with `NS3_JOIN=127.0.0.1` + `NS3_SHOTS` on each is the wifi-play test harness. These are the testing strategy — there are no unit tests.

**GDScript gotchas:** `:=` cannot infer types from ternaries or cross-script members — annotate; never `class_name` anything Godot ships natively (a native `VirtualJoystick` silently shadowed ours — members vanish with only runtime "invalid access" errors; ours is `TouchStick`).

**Character model pipeline:** Meshy exports GLB — always run `python3 Tools/fix_meshy_glb.py <file.glb>` on a fresh export before committing (fixes broken material export, +Z facing, and adds the missing Idle clip); cleaned models live in `Assets/3D/` (see its README) and get copied into `godot/assets/` when wired into a kit. A model whose fighter throws what it holds (Sanjit's staff) is re-exported with `--split-held-item left|right`, which carves the item into a `held_item` node; `fighter.gd:set_held_item_visible` hides it while the thrown copy flies and `boomerang.gd:_exit_tree` puts it back. Meshy's run/attack clips drop the hips below the rest pose, so `fighter.gd` calibrates each model's idle foot height at spawn and lifts the model per-frame by however far the lowest foot bone sinks below it; `Godot --path godot --headless --script res://tools/foot_probe.gd` prints the per-clip sink and lift for every model.

**iOS export** (`godot/export_presets.cfg`, templates installed at `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`): `--export-debug "iOS" build/ios/noblestars3d.ipa` writes an Xcode project (export_project_only). Gotchas learned the hard way: iOS export REQUIRES `rendering/textures/vram_compression/import_etc2_astc=true` in project.godot — without it validation fails with an EMPTY error message; Godot's `targeted_device_family` enum is 0=iPhone 1=iPad 2=both (not Apple's); the generated pbxproj contains six unreplaced `$additional_pbx_*`/`$pbx_embeded_frameworks` placeholder lines that must be deleted before xcodebuild will parse it. **Simulator builds are blocked upstream**: godotengine/godot#118161 — 4.6.2+ templates ship simulator libgodot.a as x86_64-only and Xcode 26 has no Rosetta simulators; test on a real device (arm64 device slice is fine) until fixed templates ship.

## v1 SpriteKit game (`NobleStars/`) — complete, maintenance only

SpriteKit + SwiftUI shell, Swift, no external dependencies. Landscape-only, iPhone-only (iPadOS 26 has orientation-lock regressions). All 2D art is generated by `Tools/generate_sprites.swift`. Arena maps are ASCII grids in `ArenaMap.swift` (`#` wall, `b` bush, `~` water, `S` spawn, `X` loot box); 2.5D depth comes from y-sorted `zPosition` (`ZLayer` in `Constants.swift`, which also holds the `PhysicsCategory` bitmasks).

Build & run — full Xcode lives at /Applications/Xcode.app but `xcode-select` points at CommandLineTools, so always prefix builds with `DEVELOPER_DIR`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate          # only needed after adding/removing files or editing project.yml
xcodebuild -project NobleStars.xcodeproj -scheme NobleStars \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name "NobleStars.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl install <UDID> "$APP" && xcrun simctl launch <UDID> com.ryder.noblestars
```

The Xcode project is generated — never edit `NobleStars.xcodeproj` by hand; edit `project.yml` and re-run `xcodegen generate`.

Gotchas:
- **Simulator screenshots are captured in portrait framebuffer orientation.** The app runs landscape, so `xcrun simctl io <UDID> screenshot x.png` needs `sips --rotate 270 x.png --out x_r.png` before viewing. Don't mistake the raw portrait capture for a broken orientation lock.
- **Debug env hooks** (via `SIMCTL_CHILD_` prefix on `simctl launch`): `NS_KIT=nova|tony|henry`, `NS_AUTOFIRE=<sec>`, `NS_AUTOWALK="dx,dy"`, `NS_GODMODE=1`, `NS_DEBUG_HUD=1`. Any of NS_KIT/NS_AUTOFIRE/NS_AUTOWALK skips the menu. All in GameScene.swift / GameView.swift.
- The simulator can shut down between Bash invocations when Simulator.app isn't open — `open -a Simulator` keeps it alive, or re-boot with `xcrun simctl boot <UDID>`.
- zsh does not glob-expand unquoted variables — resolve the DerivedData app path with `find`, not a wildcard in a variable.
