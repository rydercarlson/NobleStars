# Noble Stars

Brawl Stars–inspired top-down arena battler (Showdown mode: last fighter standing, shrinking gas ring, loot-box power cubes). The whole project is the 3D Godot 4 game in `godot/`.

There was a v1: a SpriteKit/Swift 2D game in `NobleStars/`, complete and kept working alongside this one for a while. **It was deleted** — it had no users, it was not being extended, and having two iOS apps both called "Noble Stars" installed side by side was actively confusing. It is in git history if it is ever wanted back. Nothing outside that history should reference `NobleStars/`, `project.yml`, `xcodegen` or `Tools/generate_sprites.swift`.

## Two people work here

**Ryder owns gameplay** — kits, characters, balance, match feel, controls, modes, multiplayer, arena. Every character design is his call; nobody builds a fighter without him. **Jackson owns menus and assets end to end** — `godot/scripts/menu/` as a developer *and* the art: he designs it, makes it, and implements it. **All on-device testing is Ryder's**, whoever wrote the code — the phone is his and `devicectl` installs from his machine, so a menu change is a loop through him rather than a handoff. `ROADMAP.md` holds the split, the phases and the open decisions.

## Where the detail lives — READ THE PAGE BEFORE YOU TOUCH THE CODE

This file is the spine: what holds everywhere, and where everything else is. The subsystem
pages under `docs/` carry the constraints that were discovered the hard way — **a rule you
did not read is a rule you will re-break.** Open the page before editing its area.

| Page | Read it before touching | It carries |
|---|---|---|
| **`docs/menu.md`** | `menu.tscn`, `menu.gd`, `scripts/menu/`, `data/*.json` | The design system, the five screens, stage scaling, the type scale, popup ordering |
| **`docs/cup.md`** | `cup_mode.gd`, `ball.gd`, `Arena.PITCH_MAP` | Nobles Cup rules, the pitch, the ball, kicking, the camera lock |
| **`docs/net.md`** | `net_play.gd`, `room_screen.gd`, the net section of `main.gd` | The roster, the snapshot wire format, prediction, join codes, discovery |
| **`docs/feel.md`** | `haptics.gd`, `virtual_joystick.gd`, effects, aiming, results | Haptics, touch sticks, tap-vs-drag aiming, effects, match bookends, lineup |
| **`docs/arena.md`** | `arena.gd`, `gas_ring.gd` | Terrain shaders, bushes, the gas ring, power-cube preloading |
| **`docs/testing.md`** | Any test run at all | Every `NS3_*` hook, the probe tools, running Godot by hand |
| **`docs/ios.md`** | Export, signing, installing to the phone | `export_presets.cfg`, the signing traps, `devicectl`, the device loop |
| **`docs/models.md`** | A new or re-exported GLB, worn gear | The Meshy pipeline, `fix_meshy_glb.py`, bone attachment |
| **`docs/phone_fit.md`** | HUD layout, menu stage sizing | Safe area, stage pixels, what may and may not be inset |

Sibling docs at the root: `todo.md`, `done.md`, `ROADMAP.md`, `SHOT_FEEL.md` (weapon feel
and the tile rescale), `CHARACTER_BUILDING.md` (how a kit is statted).

## Update the docs before you finish — this is not optional

Four files carry this project's memory, and they are only worth anything if the session that changed something is the session that writes it down. **A task is not done until they are current.** Check all four at the end of every session, and say in your final message which you touched and which needed nothing.

| File | What it holds | When to touch it |
|---|---|---|
| **`CLAUDE.md`** + the `docs/` page for the area | How the code actually works, and every constraint discovered the hard way. | You changed behaviour, learned a non-obvious fact, or found a rule that a future session would otherwise re-break. Put it on the subsystem page; put it here only if it holds everywhere. |
| **`todo.md`** | Open work only, each item with a priority and an effort rating. | You finished an item, found a new one, or discovered an existing one was stale. |
| **`done.md`** | Finished work, and the reasoning behind it. | You completed a `todo.md` item — **move the entry, do not delete it.** |
| **`ROADMAP.md`** | The sequence to beta, ownership between Ryder and Jackson, and the numbered open decisions (D1-D11). | You changed what beta needs, finished a phase item, or a decision got answered. |

Rules that have already been earned:

- **Write down what you REJECTED and why, not only what you shipped.** Most of the value in `done.md` is the approach that looked obvious and was wrong. Several entries exist purely to stop a future session re-trying something measured and discarded — the toppling-over death animation, the alpha-hash concealment, the expected-value Super picker.
- **Never delete a completed entry to tidy up.** If the code moves on, add a `superseded` note under it and leave the reasoning in place. A stale entry with a correction attached is worth more than a clean file.
- **A stale entry is worse than a missing one**, because it gets acted on. Three entries in `todo.md` described work that had already shipped and one of them would have undone a deliberate redesign. If you find one, strike it and record why in the file's own "Struck this pass" block.
- **Verify before you claim.** Do not write "X is broken" or "Y is stale" from a file in your context — read the working tree. This exact mistake was made in this file's own history: a session reported CLAUDE.md stale on two counts that the working tree had already fixed.
- **`--headless --import` is not a compile check** (see below), so "it imported" is never evidence that anything works. Run the game.

## Godot 3D game (`godot/`)

Godot 4.7, everything built in code (the `.tscn` files are near-empty shells). Entry scene is `menu.tscn`; `game.tscn` is the match. Scripts live in `godot/scripts/`: `main.gd` is the match hub (mirrors v1's GameScene), plus `fighter.gd`, `arena.gd`, `bot_brain.gd`, `gas_ring.gd`, `kits.gd` (character data), `projectile.gd`/`lob.gd`, `virtual_joystick.gd` (`TouchStick`, all three sticks — `super_button.gd` was folded into it), `session.gd`, `loading_screen.gd` (autoload `Loading`), and for Nobles Cup `cup_mode.gd` (`CupMode`, the rules) + `ball.gd` (`Ball`). Menu system: `menu.gd` (`MenuShell` — stage scaling, screen stack, toasts/popups/particles), `menu_stage.gd` (`MenuStage` — the full-stage 3D view of the fighter), `scripts/menu/` (the screens), `ui_kit.gd` (the old navy/gold StyleBox helpers, now only `room_screen.gd` uses them), `save_game.gd` (`SaveGame` statics → JSON at `user://save.json`: per-fighter trophies, coins, gems, unlocks, pass progress, settings; Showdown ranks 1–10 award +8,+6,+5,+4,+3,+1,0,0,−1,−2 trophies, `max(2, 22−2·rank)` coins and `max(40, 180−12·rank)` Nobles Pass tokens via `SaveGame.award_match`, called from `main.gd:_end_match`). **Stats come from `kits.gd`, never from `brawlers.json`** — the JSON carries copy, art ids and shop/pass/news config only.

**Run it: `Tools/godot.sh --path godot`** (add `--headless --import` after adding files — REQUIRED after new scripts too, or class members silently vanish at runtime). The wrapper serialises runs under a per-project lockfile, which is what makes parallel agents and separate worktrees workable; **never kill a Godot you have not identified** — one of them is a human playing the game. Details, including how to tell them apart, are in `docs/testing.md`. `godot/.godot/` is gitignored, so a **fresh clone must import once** (~5s) before the project will open or run.

**`--headless --import` is NOT a compile check.** It does not report GDScript parse errors — a `main.gd` that could not load at all imported silently, and the `SCRIPT ERROR: Parse Error` only appeared on running the game. This is a sharp edge precisely because the PostToolUse hook makes the import feel like one. To know a script actually parses, run the game. A **PostToolUse hook in `.claude/settings.json` runs that reimport automatically** after any edit to a `godot/**/*.gd`, so the footgun is handled for Claude Code edits; you still need it by hand after adding assets outside the editor.

**Current state:** full Showdown match playable — nine kits (Nova shotgun, Tony lob, Henry melee/dash, Sanjit fast melee/boomerang, Kovacs tank clap/jump-smash, Leon controller buttons/disconnect, Anders hacky-sack control, Hammy heat-streak sniper/bank-shot Super, Ayaan slalom curveballs/steerable Downhill run), bots, gas ring, loot, three parked floating touch sticks, results overlay (awards trophies, coins, and Pass tokens into the save). Desktop fallbacks: WASD, Space auto-aim, E Super. Menu is a game-programme roster page (`docs/menu.md`): the selected fighter's GLB idling center-stage, their stat column and ability write-ups filling the flanks, the mode plate and PLAY bottom-right, ROSTER/SEASON/SHOP/WIFI bottom-left on every screen, the avatar and record top-left, coins/gems and the menu square top-right. Nova is the sole starter; Trophy Road runs 100→5000 trophies and unlocks Sanjit, Tony, Kovacs and Henry by name, alongside coins, gems, Power Points, Bling and Dawg Treats. Two modes launch — Showdown and Nobles Cup; every other event card is still a locked dummy. `Session.mode` + the mode branch at the top of `main.gd:start_match` are where the next one goes in.

## Rules that hold everywhere

**Scale: ONE TILE IS ONE FIGHTER.** `Kits.TILE` (1.30 m) is exactly `2 * Kits.FIGHTER_RADIUS`, so "tiles" and "body-widths" are the same unit, as they are in Brawl Stars ("a Brawler's hitbox is slightly larger than a single tile of cover... shown by the ring around their feet"). Every figure they publish — range 8.33, movement 2.40/s, projectile 12.0/s — is denominated in it, so ours compare by reading rather than converting. Rescaled 7 Sep 2026 from a 2.0 m tile; see `SHOT_FEEL.md` §10 for the full pass. Four things follow, and each has bitten already:

- **Changing `TILE` means changing every `X * TILE` in the project**, because such a value keeps its number and silently changes its meaning. It also means regenerating the Showdown map and re-authoring the Cup pitch.
- **A fighter is exactly as wide as a tile, so a one-tile corridor has ZERO clearance** and a fighter jams in it. `Arena.TILE_COLLISION_SHRINK` (0.75) insets terrain *collision* inside the tile it is *drawn* on, which is what makes those corridors passable — Brawl Stars does the same, its movement collider being smaller than its hitbox ring. **Inset the wall, never the fighter**: the fighter's capsule is also its hurtbox (`projectile.gd` sweeps against it), so narrowing it would shrink `hit_width`, silently retune every `lead/hit` figure, and make the feet ring a lie. **`NS3_SIM` cannot see this class of bug** — bots path on the ASCII grid and route around gaps they cannot fit through, so the balance table stays healthy while a player wedges. `tools/fit_probe.gd` is the check (`NS3_MAP=showdown Tools/godot.sh --path godot --headless --script res://tools/fit_probe.gd`); run it after touching `TILE`, `FIGHTER_RADIUS`, `TILE_COLLISION_SHRINK` or either map.
- **Speed sits just above Brawl Stars parity** — `SPEED_NORMAL` 3.60 m/s = 2.77 tiles/s against their 2.40, the other four tiers derived from it. Exact parity (3.12) was tried and played as "genuinely moving in slow motion" — though most of that turned out to be oversized models, so **judge speed and `MODEL_SCALE` together, never one alone**: perceived pace is body-LENGTHS per second. Tune that one constant; every projectile speed is a multiple of a tier, and `lead/hit` has no move-speed term so aiming difficulty does not move. The floor is the run clips: stride is `velocity / RUN_CLIP_SPEED` clamped at 0.35, and `SPEED_VERY_SLOW` already lands at 0.357.
- **Time constants stay, distance-per-second constants scale, tile-denominated distances multiply.** Knockback is the trap: `IMPULSE_TRAVEL` makes every `knockback` a displacement with a fixed ~0.109 s decay, so it is an impact and stays in metres. The ball is travel, so it time-dilated — speed, `STOP_SPEED` *and* `DRAG` all scaled, which preserves `kick_range()` exactly while stretching the clock.

**Every fighter wears a hitbox ring** (`fighter.gd:_setup_hitbox_ring`), in every mode, not just Nobles Cup. The torus straddles `FIGHTER_RADIUS`, so its mid-line is 1.40 m against a 1.30 m tile. It takes the team colour in Cup and the kit colour in Showdown — the same split `fighter_bars.gd` makes for health bars. It is the only thing that makes the tile-is-a-fighter unit legible while playing, because the models are roughly half the capsule's width.

**Phone fit: THE PICTURE FILLS THE DISPLAY; ONLY CHROME IS INSET.** The arena and the menu stage run edge to edge and under the notch and the home indicator; only a label that cannot be read there and a stick that cannot be reached get inset. Insetting the whole picture is what BOTH phone-fit P0s turned out to be. **`Session.safe_rect(viewport)` is the ONE copy of that rectangle** — the menu and the match both need exactly these numbers. **Nothing in the match HUD may be placed at a literal coordinate**; `main.gd:_layout_hud` re-places all four labels and all three sticks off the safe rect on every viewport change. Full write-up, and why the type-size complaint is two different problems: `docs/phone_fit.md`.

**Effects and sounds ship no asset files.** Every combat SFX is synthesized at runtime through `MenuAudio`, every VFX is an `ImmediateMesh` rebuilt per frame, every haptic is a scored rhythm, and the terrain, water and gas are shaders over flat colour. The camera is a fixed steep top-down, so this is cheaper *and* sufficient. Do not reach for an art or audio file without a reason that survives that.

**GDScript gotchas:** `:=` cannot infer types from ternaries or cross-script members — annotate; never `class_name` anything Godot ships natively (a native `VirtualJoystick` silently shadowed ours — members vanish with only runtime "invalid access" errors; ours is `TouchStick`).

**Godot gotchas beyond GDScript itself:** a **1-pixel-wide `ImageTexture`** in a `TextureRect` (`EXPAND_IGNORE_SIZE` + `STRETCH_SCALE`) drew nothing at all, with no error — `GradientTexture2D` is the working way to lay a gradient scrim over art, and it is less code. Driving a Control's own `size` from its `resized` signal **recurses** and trips a `_set_size` error, so a rotated banner cannot size itself off its parent that way. The menu's own layout gotchas (`PanelContainer` stretch, `PRESET_MODE_MINSIZE`, `ScrollContainer` minimum height) are in `docs/menu.md`.

## Where it's going

- Finish replacing the placeholder capsule fighters with rigged Meshy GLB characters. Eight of nine are wired through `kits.gd` `model`/`clips` keys → `fighter.gd` (Tony, Sanjit, Henry, Kovacs, Leon, Anders, Hammy, Ayaan); **only Nova is still on the capsule fallback**, and she is `todo.md` 4.1. This line used to name Anders, Hammy and Ayaan as capsules too — they have had GLBs for a while. Corrected 7 Sep 2026.
- Arena visual pass — done for the floor, walls, water and the surround (`docs/arena.md`). Still open: **camera framing and model scale**, which `todo.md` keeps together because they are one decision.
- Ship to a real iPhone via the iOS export (`docs/ios.md`).
- Voicelines recorded by the people the characters are based on. (Combat SFX are done — 28 sounds synthesized at runtime through `MenuAudio`; `main.gd:sfx_at` attenuates by distance and jitters pitch, `_attack_sound` keys them off `weapon.style` so a new kit inherits one. `MenuAudio._render` falls through to "click" for an unknown name, so verify the table with `Godot --path godot --headless --script res://tools/sfx_probe.gd` after adding a sound.)
- New characters are Ryder's designs — ideas live in `ROADMAP.md` (decision **D2**); ask before building one. Stat them with `CHARACTER_BUILDING.md` (tier tables for health/speed/reload/range, the damage formula that derives from them, and the 5.5-tile on-screen range cap — **set by the SHORTEST visible direction, up-screen, not the wide axis**: a weapon fires every way, and the camera shows 5.54 tiles up against 8.8 sideways, so capping on the wide axis put shots three tiles off the top of the frame) — damage is derived, never picked by taste.
