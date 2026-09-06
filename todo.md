# Noble Stars — TODO

Running list of the major fixes and gaps in the Godot 3D game (`godot/`). Roughly
priority-ordered inside each section. v1 SpriteKit (`NobleStars/`) is maintenance
only and is not tracked here.

## From play on a phone — 5 Sep 2026

Ryder's list off a real session, verbatim in intent and grouped here by where the
fix actually lands. Everything in this section is unstarted unless it says
otherwise; the older sections below are still the reference for anything that
overlaps.

### The lineup — done, this pass

- [x] **Nobody appears twice on a team, and the bots have names.** Three of the
      list at once, because all three lived in the same twenty lines of match
      setup:
      - **`Kits.all().pick_random()` per slot** meant Nobles Cup routinely
        fielded two of the same character on one side (a 1-in-3 chance per pair
        at nine kits), and Showdown's ten slots could deal the same fighter four
        times. `main.gd:lineup_kits(count, first)` deals a shuffled pool without
        replacement instead: Cup's three-a-side never repeats within a team,
        and Showdown fills nine of its ten slots with nine different characters
        and only the tenth can echo one. The two Cup sides are dealt
        independently, so a character can still line up opposite themselves —
        Brawl Ball's own rule, and Ryder's call.
      - **The player always spawned on the left of the Cup kickoff row.**
        `build_match` read `team_spawns[team][i]` by index and the player is
        always team 0, slot 0 — so it was the same tile every match. The three
        spots are now shuffled once into `CupMode._lineup` and **both**
        `build_match` and `kickoff` read that, which is the constraint the old
        comment was protecting: when the two disagreed, fighters spawned on top
        of each other and the depenetration fired them off the pitch.
      - **Bots were called "Kovacs 3".** They now draw a username from a pool of
        56 in `game.json` (`opponents`, read through `MenuData.opponent_names`),
        dealt without repeats per match. That name was already printed in three
        places — the versus cards, the elimination feed and the results table —
        so this shows up everywhere for free, and the nameplate below adds the
        fourth. `NS3_SIM` deliberately keeps the old kit-based naming, because
        `[sim] match 12/60: Kovacs 4 wins` is the line that has to stay readable.
- [x] **Health bars sit above the head instead of across the face.** The stack
      hung DOWN from an anchor 3.4 m up, so bar + gap + pips + Hammy's heat pips
      reached back into the model. It now hangs UP from a 2.75 m anchor — the
      bottom of the ammo pips lands on the anchor and everything else stacks
      above it, so no amount of extra rows can ever reach the face again. The
      username rides on top of that stack in the same outlined numerals the HP
      already uses.

### Feel and controls

- [ ] **Everything still moves too fast for the tile size.** The recurring note,
      and the same decision as **Camera framing** and **Model scale** below —
      all three are the one ratio between how big a fighter is, how much map is
      on screen and how far it crosses per second. Do not tune one alone. The
      numbers to start from are in those two entries.
- [x] **Haptics.** `scripts/haptics.gd` — a static `Haptics.fire(name)` over a
      fourteen-entry table of duration + amplitude, gated on
      `SaveGame.haptics_on` (Settings, beside Music and SFX) and on
      `OS.has_feature("mobile")`. What the pass turned on:
      - **Godot routes `vibrate_handheld` through Core Haptics on iOS 13+**, so
        both the duration and the amplitude are real. Older devices ignore both
        and fire the same ~0.4s buzz, which is why the table is short and hard
        throttled — every entry has to survive arriving as a fixed buzz.
      - **Damage is watched in `_update_status`, not hooked into `deal_damage`.**
        A wifi client never runs `deal_damage` and takes its health off the
        snapshot stream, so reading the number frame to frame is the one hook
        that covers both — and a nine-pellet shotgun arrives as one exchange
        rather than nine taps.
      - **`HEAVY_FRACTION` was measured with `NS3_HAPTIC_LOG=1`, not picked.** A
        bot's shot landing is 29% of max health and a gas tick 17%, so 0.22 is
        the only threshold that separates them; the first pass at 0.12 made
        every hit heavy, gas included, which is the same as having one entry.
      - **`REPEAT_GAP` on top of `MIN_GAP`** for the taps that arrive as a
        stream. Gas ticks about twice a second for as long as you stand in it,
        and at the global 0.09s floor it rattles.
      - **`NS3_HAPTIC_LOG=1` is the whole verification story**, since nothing can
        be felt on a desktop. Confirmed firing on real runs: `count_go`,
        `hit_taken`, `hit_heavy`, `super_ready`, `super_fire`, `elimination`,
        `death`, `goal_for`, `goal_against`, and `ui_tap` off a real menu button
        press. **Not yet seen fire: `cube`, `ball_get`, `ui_reward`** — each is a
        one-line hook beside an already-working sound in the same closure, but
        the situation did not arise in the runs that were made.
      - Still open: nothing is tuned against an actual phone. The amplitudes are
        first guesses and want a pass on the device.
- [ ] **The Super is hard to aim.** Aiming a Super costs the same drag as a shot
      but the miss is far more expensive, and the button and stick are separate
      controls (`super_button.gd` + `virtual_joystick.gd`), so the aim starts
      only once the finger is already on the button. Worth trying the Brawl
      Stars arrangement: the Super button is itself a stick you drag off.
- [ ] **The Super's auto-aim picks badly.** A tapped Super takes
      `nearest_visible_enemy(player, range * 1.1, ...)` and nothing else
      (`main.gd:_auto_aim_fire`) — no lead beyond `_aim_lead`, no preference for
      a target that is actually worth a charge, and no memory of what you were
      already shooting at. Nearest is the wrong metric for the one shot that
      costs something: the right target is usually the one you have been
      fighting, or the low one, not whoever happens to be a metre closer. Note
      the deliberate exceptions already in there (Pop Off runs the way you are
      running, Downhill sets off with nobody in reach, and any other Super with
      no target keeps its charge rather than firing at nothing) — those are not
      the bug and should survive whatever replaces the picker.
- [ ] **Nobles Cup aiming is weird.** `CupMode.kick_aim` shoots inside
      `SHOT_RANGE` and passes otherwise, and the indicator is the ball's own
      bounce path — so a tap does one of two quite different things depending on
      a distance the player cannot see. Reproduce and decide whether the tell is
      missing or the rule is wrong.

### Fit on a phone

- [ ] **The match does not reach the edges of the screen.** `project.godot` is
      `stretch/mode="canvas_items"`, `aspect="expand"` at 1280x720, which should
      fill — so this is either the safe-area inset or the HUD's own anchors.
      Shoot it on the device before changing anything.
- [ ] **The menu does not reach the edges either**, which is a different bug:
      `MenuShell._fit_stage` deliberately widens the 1920x1080 stage past 1920 on
      anything taller than 16:9 so a phone gains stage width rather than bars.
      Either that path is not running on device or the safe-area honouring is
      eating the gain.
- [ ] **Buttons and text are too small.** On the menu this is the type scale
      being authored against a 1920 stage and read at arm's length on a 6-inch
      screen; in the match it is the HUD. Measure the real device pixels per
      point before picking new numbers — the stage scale makes guessing useless.

### Menu and progression

- [ ] **Redesign the menu around Jackson's idea.** Needs the idea written down
      here before anything is built. The current programme-page design and the
      reasoning behind every token in it is in CLAUDE.md's **Menu** section —
      read that first so the redesign is a decision and not a drift.
- [ ] **The roster should be tiles, not a grid.** `roster_screen.gd` is a plain
      picker of rows; Ryder wants character tiles.
- [x] **Every character has a card now.** The old entry was half stale: **Ayaan
      has had a `brawlers.json` entry all along** (title, role, description,
      attack and Super copy) and so do Anders and Hammy — what those three lack
      is only the loadout names, and that block currently has no reader at all
      (`BrawlerDetailScreen._build_loadout` went with the roster's detail card
      in the menu overhaul; `MenuData._merge` still emits `loadout` and nothing
      consumes it). **Nova** was the one genuinely missing entry, and it showed
      the most because she is the sole starter and the first fighter anyone
      sees: `_merge`'s fallbacks titled her "Shotgunner" under a role tag
      already reading SHOTGUNNER, named her attack "SHOTGUNNER" and her Super
      "SUPER", and printed her kit description twice. She now has a full entry
      in the shape of Leon's, and home reads SCATTERSHOT / MEGA BLAST with real
      copy under the title FIRST DAY.
      - The JSON is copy, never balance: her numbers were read out of
        `kits.gd` (5000 HP, 250 x 5 pellets, 22° fan, 4.3 tiles; Super 333 x 9,
        34°, 5.0 tiles, breaks walls) and the write-ups quote them. `_merge`
        does not read the JSON `stats` block at all — every figure on screen
        comes from `kits.gd` — so it is there for shape parity and nothing else.
      - No `model` or `portrait` key: Nova has neither file on disk, and unlike
        Ayaan's entry (which names a portrait that does not exist and is never
        resolved anyway — `MenuData.portrait` derives the path from the id) this
        one does not pretend otherwise. She still renders as the capsule.
      - The copy is deliberately descriptive rather than a character concept —
        Nova is the placeholder reference kit and has none written down
        anywhere. Replace the title and the four loadout names freely.
      - **Left alone, worth a look:** Leon's entry is still `"rarity":
        "starting"` and `"unlocked": true` from the web build, so the roster
        labels him Starting Brawler alongside Nova, who is the only id in
        `game.json`'s `startingBrawlers`. Changing it moves him between rarity
        buckets, which the rarity-weighted `brawler_drop` reads — a content
        decision, not a typo fix.
- [ ] **A real progression system.** `SaveGame` already banks trophies, coins,
      gems, Power Points and pass tokens per match, and Trophy Road and the pass
      spend them — but power levels, Star Powers and gadgets are displayed and
      do nothing. Decide what a level actually changes before wiring it.
- [ ] **Activate a third game mode.** Two are live (Showdown, Nobles Cup); every
      other card on the modes screen is a locked dummy. `Session.mode` plus the
      branch at the top of `main.gd:start_match` is the whole hook, and
      `cup_mode.gd` is the worked example of what a mode file looks like.
- [ ] **Name the dog park?** Open question from Ryder — the maps have no names in
      the game at all (`game.json`'s `gameLog` invents "Castle Courtyard" and
      friends for its fake history, and nothing reads them). If maps get names,
      the loading screen and the versus screen are where they belong.

### Boot

- [x] **The app boots on the loading screen.** Not a second design — the splash
      *is* `loading_screen.gd`'s own first frame, rendered to a PNG by
      `tools/make_boot_splash.gd` because the engine paints it before any of our
      code is running and a still image is all it can paint. The screen builds
      itself through a static `LoadingScreen.compose()` that both the live
      transition and the renderer call, so the two cannot drift; re-run the tool
      after changing the screen:

          /Applications/Godot.app/Contents/MacOS/Godot --path godot \
              --script res://tools/make_boot_splash.gd     # NOT --headless

      Copy is `BOOT_TITLE` / `BOOT_SUBTITLE` on the screen itself ("Starting up"
      — "returning to the lobby" is the one line that cannot carry over to a
      cold start). `bg_color` is the screen's own `BASE_INK` (`#05070f`) by
      hand, and it is load-bearing: 4.7's `boot_splash/stretch_mode` defaults to
      **Keep**, which FITS the image, so on anything wider than 16:9 that colour
      is the columns either side. Fit rather than Cover deliberately — the title
      and the bar are anchored to the bottom of the frame, and Cover crops 11%
      off the bottom of a 19.5:9 phone, which is exactly where they live.
      Three more things it learned: the render is composed at the screen's
      authored 1280x720 and shot at 1920 via `size_2d_override`, which
      rasterizes the type at the larger size the way the game's own
      `canvas_items` stretch does (scaling the Control tree instead upscales the
      glyph bitmaps); 1920 and not more because that is the keyart's own
      resolution and the same frame at 2560 is a 4 MB PNG against a 500 KB
      source; and the PNG is imported `keep` with an `exclude_filter` entry in
      `export_presets.cfg`, because the exporter adds the boot splash to the
      pack by path *on top of* the resource sweep and it shipped twice
      (measured: 40.0 MB → 37.2 MB). `minimum_display_time=750` is `MIN_SHOW`'s
      rule — a splash that flashes for three frames reads as a glitch.
      **iOS gets it free on the next export**: the launch storyboard falls back
      to `boot_splash/image` and `boot_splash/bg_color` when the preset names no
      `storyboard/custom_image@2x`, which is why the last export's storyboard
      carries the engine's own `0.14, 0.14, 0.14`. Only the app icon is left in
      **Ship**.

### Balance, from play

- [ ] **Sanjit's range feels too long.** `kits.gd:305` — the melee reaches
      1.4 tiles (2.8 m) and the boomerang Super 5.0. Measure which one the
      complaint is about with `NS3_KIT=sanjit` before touching the tier tables;
      `CHARACTER_BUILDING.md` derives damage from range, so a range change is a
      damage change.
- [ ] **Kovacs knocks the ball out of play.** His clap and jump-smash deal
      knockback well above `CupMode.KNOCK_DROP_SPEED`, so he strips the carrier
      — intended — but the ball then travels further than a kick. Clamp what a
      knock does to the ball, or drop it at the carrier's feet.

## Generating assets ourselves

Most of what is still missing does **not** need Meshy or hand-drawn art. Three
pipelines already exist in this repo and between them cover nearly everything
below; the handful of exceptions are called out at the end.

**1. Synthesized audio — zero files.** `scripts/menu/menu_audio.gd` (`MenuAudio`)
is a complete runtime synth: sine/triangle/square/saw/noise oscillators,
envelopes and an 8-voice pool rendered into `AudioStreamWAV` buffers on first
play. That is why the menu ships with no SFX files at all. `main.gd` does not
use it. Every combat sound in the Sound section can be a new entry in that same
table rather than a recording — shot, impact, melee whoosh, reload tick, empty
click, Super charge, elimination, cube pickup, gas tick, goal horn, whistle.

**2. Headless render — portraits, cards, map thumbnails. `tools/render_portraits.gd`
exists now.** It shoots portraits (512, transparent) and full-body cards (768)
straight off the GLBs on `menu_stage.gd`'s own rig — same 22° lens, same warm
key / cool fill / gold rim — so a portrait and the live stage fighter are lit
identically, and the art regenerates for free whenever a model changes. All
seven modelled portraits were re-rendered through it. Run it **without**
`--headless` (the dummy driver renders nothing and every PNG comes out empty):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path godot \
    --script res://tools/render_portraits.gd
# NS3_PORTRAIT_KITS=tony,henry  NS3_PORTRAIT_KIND=portrait|card|both
# NS3_PORTRAIT_OUT=<dir>        (default: the menu art dirs)
```

Framing is sized to the **head**, not to a fixed number of metres: our rigs are
not proportioned alike — Tony's head is 41% of his body height against Henry's
25% — so the span that framed Henry's head and shoulders cut Tony off at the
chin. It reads the head off the skeleton (`Head` sits at the chin, `head_end`
at the crown on every Meshy rig here) and hangs the frame off the crown. The
same rig still needs pointing at the arena camera for map thumbnails.

**3. Script-drawn 2D — icons and badges.** v1 did exactly this: every 2D sprite
in the SpriteKit game comes out of `Tools/generate_sprites.swift`. Pins,
gadget/gear/Star Power/Hypercharge badges, currency and mode icons, the club
badge and the app icon are all flat vector shapes, and are better generated
deterministically than drawn once and lost.

**What genuinely cannot be self-generated:** the Nova and Ayaan character models
(Meshy, or a modeller), skin variants of existing characters, real music, and
the voicelines — which need the actual people the characters are based on and
therefore have the longest lead time of anything in this file. Start booking
those before anything else on the list.

## Character models & animation

- [x] **Feet sinking through the floor.** Meshy's run/attack clips drop the hips
      6–11 cm below the rest pose, pushing the feet under the floor plane.
      `fighter.gd` now calibrates the idle foot height at spawn and lifts the
      model each frame by however far the lowest foot bone has sunk below it
      (`_calibrate_feet` / `_ground_feet`). Measure any model with
      `Godot --path godot --headless --script res://tools/foot_probe.gd`.
- [x] **Run cycle no longer bobs — per-clip constant lift.** The old lift was
      recomputed every frame, so it tracked the stride and peaked at its trough:
      the fighter rose exactly where it used to sink. `_calibrate_feet` now
      samples each clip `kits.gd` actually names at `LIFT_SAMPLES` poses and
      stores one constant per clip (`max(0, rest − min foot y)`, model space);
      `_ground_feet` looks that up instead of measuring, easing over
      `LIFT_EASE_TAU` so a clip change does not pop against the 0.15s animation
      blend. Shifting the whole cycle by its own worst frame leaves the stride's
      natural rise and fall intact, which is what actually removes the bob.
      - Cached in a `static var` keyed by `kit.model` — it is a property of the
        model and its clips, not of the fighter, so six fighters of three kits
        pay for the sampling three times and a respawn pays nothing. It also
        drops a `force_update_all_bone_transforms()` per modelled fighter per
        frame.
      - **Swapping the run clip was the wrong fix and this is why it was not
        taken**: the zero-lift `run_fast_*` variants exist for henry, kovacs,
        leon and anders only — sanjit's `RunFast` still needs 0.087, and tony
        and hammy have only `Run_03` at 0.023 / 0.043. The swap fixes four kits
        and leaves three bobbing.
      - Measured values match `foot_probe.gd` to three decimals: tony 0.063,
        henry 0.074, sanjit 0.099, kovacs 0.111, leon 0.094, anders 0.019,
        hammy 0.108. The failure mode watched for was an **empty** table — the
        clip-name filter has to skip `kit.clips`' tuning floats
        (`attack_speed`, `super_seek`) and could have skipped everything, which
        would zero every lift and sink the feet again with no error.
- [ ] **Nova and Ayaan still render as capsules.** They have no `model` key in
      `kits.gd`, so they fall back to `_setup_capsule` in the match *and* on the
      menu stage. Nova is the sole starter, so a capsule is the first thing a
      new player ever sees. Anders and Hammy are wired now (`kits.gd:481`,
      `:559`) — this line used to name them. The two that remain need a Meshy
      pass through `Tools/fix_meshy_glb.py`; they are the only entries in this
      file that cannot be produced by one of the three pipelines above.
- [x] **Death and spawn animate now — in code, because there is no clip to
      play.** `fighter.gd:die` used to scale the fighter to nothing over 0.35s
      and `respawn()` snapped `scale` straight back, so a fighter popped out of
      existence and popped back in with nothing around either.
      - **Death is a pop**: `_pop_out` swells the body for a beat and bursts it,
        throwing a ground ring and an all-round spark. A first pass TOPPLED the
        body onto the floor and it was worse — at a 60 degree camera a body
        lying down is a shape you have to read, and the whole point of the
        moment is that it is instant.
      - **A Nobles Cup death also washes the screen red and counts you back in.**
        Two things that cost a pass each: a FLAT red pane at an alpha low enough
        to keep the pitch readable does not read as red at all (over green it
        composites to olive and the screen just looks dirty), so it is a
        vignette — saturated at the edges, nearly clear in the middle; and the
        counter sits in the lower third, because `center_label` owns the centre
        and a kickoff's "GO!" printed straight through it. Cup only: a Showdown
        death has nothing to count to and raises the results card instead.
      - **Spawn is a bubble**: the shell grows, the fighter scales up out of
        nothing inside it a beat behind, it holds, then bursts. Additive and
        never writing depth, so it cannot hide what is growing inside it, and
        its fresnel is far thicker than a real one — at 55 px/m a shell a few
        degrees wide is a couple of pixels, and the first version was invisible
        against the pale end zone a Cup respawn happens in.
      - Still confirmed: **no GLB ships a death or hit clip**, so none of this
        is a `kits.gd` `clips` entry waiting to be written. Kovacs'
        `Backflip_and_Rise` and Anders' `Backflip` remain if a per-kit arrival
        is ever wanted.
      - Both act on `_model` (or the capsule), **never on the fighter**:
        `rotation.y` on the fighter is its FACING, and aim, bars and the ball's
        carry point all read it.
      - A Cup knock-out hides the body at the **end** of the pop rather than on
        the frame of the hit. `fighter_bars.gd:77` already skips a dead fighter,
        so no full health bar hangs over it.
      - **`NS3_KILL=<sec>` was added to test it**, the sibling of `NS3_END`: a
        Cup match produces two or three deaths in two and a half minutes and
        none of them where the camera is, so the pop, the wash and the bubble
        were all effectively unshootable.
- [ ] **Model scale and collision don't match — and it is every model, not just
      Kovacs. Needs a decision, not a fix.** `godot/tools/size_probe.gd`
      measures each rig from its **bone** extents (a skinned mesh's own AABB is
      authored in bind space and comes back at ~0.02 m, i.e. meaningless). At
      `MODEL_SCALE` 1.44, against a capsule 1.30 m wide and 1.60 m tall:

          tony    w 0.82  d 0.41  h 2.34      leon    w 0.52  d 0.32  h 2.39
          henry   w 0.50  d 0.31  h 2.29      anders  w 0.46  d 0.31  h 2.38
          sanjit  w 0.64  d 0.41  h 2.38      hammy   w 0.46  d 0.29  h 2.40
          kovacs  w 0.61  d 0.30  h 2.40

      Every model is roughly **half** the capsule's width and **1.5x** its
      height. Widening the models to match puts them over 3 m tall; narrowing
      the capsule to match makes everyone about half as easy to hit. So this is
      a look-and-balance call — and the same one as **Camera framing** below,
      which should be decided with it.
- [x] **Hit flash and bush fade work on modelled fighters.** Both were the same
      missing mechanism: the two effects keyed off `_material`, which only the
      capsule fallback has. `_setup_model` now **duplicates** each surface
      material per fighter and installs it as a surface override — the GLB's own
      materials live on a Mesh *resource* that every fighter wearing that model
      shares, so tinting one there would have flashed all of them at once. On
      top of that: the flash is **emission**, because `albedo_color` multiplies
      the texture and setting it white is a no-op on a textured character; and
      **concealment is a tint rather than a fade** — see below.
      `set_concealed` runs every physics frame for every fighter, so
      `_conceal_applied` gates it to actual transitions.
- [x] **A concealed fighter no longer renders as a smear.** Reported from play:
      Sanjit "still kinda goes weirdly" in a bush. He does, and so does everyone
      else — reproduced by forcing concealment on and shooting Sanjit and Henry
      side by side, and Henry was every bit as broken.
      - A character is a closed solid, so any per-fragment transparency mode
        shows you its own far side: the inside of a skull through a face,
        Sanjit's staff through his chest, shoes through shins.
      - `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS` is the textbook fix and is what this
        used. **The prepass does nothing under the Forward Mobile renderer this
        project runs on.** It shipped that way because a fighter was never
        actually shot standing in a bush — the reveal shader was, the fighter
        inside it was not.
      - `TRANSPARENCY_ALPHA_HASH` genuinely fixes the sort (opaque pass,
        stochastic discard, real depth) and was tried and rejected: at 0.55 the
        dither sparkles, and any alpha low enough to read as hidden is noisier
        than the bug it replaces.
      - Shipped: stay **opaque** and multiply the albedo by `CONCEAL_TINT`. No
        sorting, no dithering, and the tell still reads, because the foliage
        around you opens up at the same time. `_model_albedo` remembers each
        material's own colour so the tint multiplies it and reveal puts it back
        — both had been assuming white.

## Menu

- [x] **The menu is native Godot** (`godot/scripts/menu/`). The HTML build it was
      rebuilt from is gone — it could not ship inside the iOS app — and all of its
      art moved to `godot/assets/menu/` (cards, treats, decor, pass hero, skins,
      mode/currency icons, logo, key art). Copy and config live in
      `godot/data/{brawlers,game}.json`; stats come from `kits.gd`.
- [ ] **v0.5 content: what is still unwired is now a short list.**
      Gadget/gear/Star Power/Hypercharge are **no longer displayed anywhere**,
      and this entry used to claim otherwise. `MenuData._merge` still carries
      them as a `loadout` dict, but `BrawlerDetailScreen._build_loadout` — the
      two-column block that drew them — went with the roster's detail card when
      home became the detail view, so the dict has zero readers. Five kits name
      a full set in `brawlers.json` (Nova, Leon, Sanjit, Tony, Kovacs, Henry;
      Anders, Hammy and Ayaan name none) and none of it reaches a screen.
      `trophyRoad` is wired — the screen reads the nested
      `{trophies, reward}` shape and renders all six reward kinds.
      **Still unwired:** the whole `loadout` dict, and game.json's `quests`,
      `leaderboard`, `gameLog` and `upcoming` are read by nothing, and
      `MenuData.card_art` still has zero callers. `passRewards` was deliberately
      left at the 15 tiers the pass screen parses rather than the web build's 40.
- [ ] **Leon, Anders, Hammy and Ayaan have no named unlock.** The v0.5 trophy
      road unlocks Sanjit, Tony, Kovacs and Henry only, so those four are
      reachable only through a shop Star Drop. Decide whether they get road
      milestones, pass tiers, or stay Star-Drop-only.
- [x] **Dead asset bytes are gone.** Deleted the 13 duplicate `icons/*.webp`
      (coin, gem, trophy, gear, lock, …), which were unreachable because
      `MenuUI.icon_texture` tries `svg/<name>.svg` first and only falls through
      to WebP when no SVG exists; and `assets/Fox.glb` + its texture, referenced
      by nothing at all. 456 KB off every export.
- [ ] **Two portrait holes left, and the cards are a different medium.**
      Portraits now come out of `tools/render_portraits.gd` (pipeline 2) and all
      seven modelled kits were re-rendered through it — the roster grid reads as
      one set for the first time. **Nova and Ayaan are still missing** and the
      tool cannot help: they have no GLB to shoot. That is the whole remaining
      hole, and it is the same Meshy dependency as the capsule item above.

      The cards are a separate problem from what this entry used to claim. The
      five that exist (`assets/menu/cards/*.webp`) are **stylised 2D
      illustrations** — cel shading, black outlines — not GLB renders, so
      rendering Anders and Hammy off their models would drop two 3D renders into
      a set of five drawings. Worth knowing before spending anything on it:
      `MenuData.card_art` currently has **zero callers**, so no screen shows a
      card either way. Decide whether cards stay an illustrated set (then they
      need an illustrator, not the renderer) or become renders (then re-shoot
      all seven with `NS3_PORTRAIT_KIND=card` and the set is consistent again).
- [ ] **The menu does not look good enough yet.** It is structurally right — the
      screens, the stack, the stage fighter, the layout offsets all match the
      reference — but it reads flat and unfinished next to what it is imitating.
      Worth being specific about what "ugly" is before touching anything, since
      the layout is not the problem:
      - **Everything is the same flat plate.** `MenuUI.plate_colors` gives every
        surface the same three-stop vertical gradient, so cards, buttons, top
        bar and rows all sit on one visual plane. Brawl Stars separates them
        with depth — thick bottom bevels, hard drop shadows under anything
        pressable, and a lip that makes a button look struck rather than
        painted.
      - **Nothing animates.** Screens appear rather than sliding, cards do not
        stagger in, buttons do not squash on press, and currency counters snap
        to their new value. The menu's whole sense of quality lives here.
      - **Dead space.** The roster grid, Trophy Road and the pass all sit in the
        top half against an empty auditorium; the stage backdrop is doing no
        work behind them.
      - **Type is uniform.** One display font at a handful of sizes, no weight
        or colour hierarchy inside a card, so nothing draws the eye first.
      All of it is `menu_ui.gd` plus per-screen tweening — no new art.
- [ ] **Menu art that the JSON already describes but nothing draws.** The two
      skins that **have** art now draw it: `shop_screen.gd:_skin_card` calls
      `MenuData.skin_art(skin)`, resolved from an explicit `art` key on s1/s2 in
      game.json (`skin_leon_homecoming`, `skin_tony_fieldday`); the other three
      fall back to the portrait as before. Explicit key rather than deriving a
      filename from the skin's name, so the next drawing only needs the key.
      **Still undrawn:** the three skins with no art; the gadget/gear/Star
      Power/Hypercharge **badges** (the names display now, the art does not);
      pins (`brawlers.json` carries a `pins` count and there is no pin art at
      all); player avatars for the profile popup and friends rows; map
      thumbnails for the events screen; and the club badge. All pipeline 2 or 3.

## Arena & visuals

- [x] **Arena visual pass.** Floor, walls, water and the world past the map
      edge are three fragment shaders over flat colour plus a slab and a
      surround plane — no art files, the same reasoning as the synthesized
      sounds. `tools/render_map.gd` was written to do it and is the thing to
      reach for next time: an overview of the whole map, or the real match lens
      pointed anywhere, both on `Arena.make_sun()`, without playing seven
      seconds of pre-match to reach a screenshot.
      - **Shadows had never rendered.** `sun.shadow_enabled` was true and had
        been for the life of the project, but the camera sits 105.5 m back
        behind a 7 degree lens and a directional light's default
        `directional_shadow_max_distance` is **100 m** — the entire arena was
        outside the volume shadows get drawn in. One constant (145 m, one
        orthogonal split) is most of what this pass actually looks like.
      - Walls and water borrowed the bushes' merge-aware outline. The per-tile
        edge mask rides an **`instance uniform`**, so ~400 walls share one
        material and still each get their own rim, and `open_at` re-masks the
        four neighbours of a hole — a wall shot out re-outlines what is left.
      - **Water is opaque now.** Translucent slabs blended against the floor
        *and* against each other, so a pond showed a grid of seams where its
        tiles overlapped. Foam is the constant to watch: a one-tile pond is 2 m
        across, and 24% of a tile per side left almost no water in the middle.
      - **A tile-scale checker cannot carry the floor.** At a 10% step it read
        as a chessboard and pulled the eye off the fighters; at 2% under two
        octaves of value noise (18 m and 6 m) it reads as ground.
      - Nobles Cup got real pitch markings — touchlines, halfway line, centre
        circle and spot, a box at each end — painted by the floor shader from
        `_playable_rect()` rather than laid down as geometry, so a line costs
        nothing and cannot z-fight the grass. That is the *lines* half of the
        pitch dressing below; goal frames and a better ball are still open.
      - **`Arena.WALL_HEIGHT` is a free knob and was left alone.** Verified
        purely visual: `Lob` is a `Node3D` with no collision, `begin_leap`
        sweeps terrain itself, and the LOS ray and every projectile both sit at
        y = 1 inside a box that starts at 0. 2.05 m was shot and looks
        chunkier and more like the reference; 1.5 m keeps more floor out of
        shadow. Taste, one constant, no balance consequence either way.
- [x] **The gas ring eases, and it looks like gas.** It used to move `inset` by
      `TILES_PER_SHRINK` in one assignment every `SHRINK_INTERVAL`, so the wall
      teleported two tiles with no motion at all, reseeded the whole cloud bank
      off `rng.seed = 7 + inset` in the same frame, and painted the danger zone
      as four flat translucent `BoxMesh`es rebuilt from scratch. The cadence is
      untouched — `FIRST_SHRINK_DELAY`, `SHRINK_INTERVAL`, `TILES_PER_SHRINK`
      and `TICKS_TO_KILL` are all exactly what they were, verified by stepping
      the ring in a probe: it starts at t=18, settles two tiles at t=21, steps
      again at t=30 and t=42, and stops at inset 20 on a 39-tile map.
      - **`inset` is a float everywhere, rules included** — the choice the old
        entry said to make. Easing only the visuals is a lie the player cannot
        see through: for the whole three seconds you would burn while standing
        on ground that plainly reads as safe. Every caller outside the file goes
        through `contains()` / `depth_inside()` / `safe_min()` / `safe_max()` /
        `safe_center()`, all of which were floats already, so the bots'
        `gas_depth` steering gets a continuously moving edge for free and
        `main.gd:gas_closing()`'s `inset > 0` still flips on the same frame.
      - **The rate is the number to check, not the duration.** A smoothstep
        peaks at 1.5x its average: two tiles (4 m) over `SHRINK_EASE` = 3 s tops
        out at **2.00 m/s**, against `Kits.SPEED_VERY_SLOW` = 4.48 m/s. The wall
        has to stay walkable-out-of or the ease becomes an execution.
      - **One net line changed**: `main.gd:_net_snapshot`'s `inset` parameter is
        `float`. The send site is untouched (`gas.inset`). Left as int the
        client's wall would land back on whole tiles and keep the jump the host
        no longer has. `GasRing` also gained a `_running` flag set only by
        `start()`, so a client — which never calls it — no longer runs the
        shrink schedule and the gas damage loop locally underneath the snapshot
        it is being sent.
      - **The bank is parametric now.** Each cloud stores its edge, its position
        along it, and its own jitter/scale/yaw, generated ONCE at a constant
        seed; world transforms are recomputed every frame from the eased edge.
        The count per edge is fixed at what the map's full width needs and the
        clouds bunch as the ring closes rather than being culled — culling
        reintroduces the pop, and dropping instances from a fixed buffer breaks
        the only thing that sorts a MultiMesh of transparent instances, which is
        the order they were written in. Buffer order is far edge, flanks, near
        edge, which is back-to-front under a camera at +Z.
      - **The fill is a shader over two quads**, a mat at ankle height and a
        haze at 2.6 m drifting faster, so the pair separates under the camera's
        pitch instead of reading as one decal. The front is the safe rectangle's
        box SDF pushed about by a noise octave, which is what stops it reading
        as a rectangle; a bright lip sits on the front and the interior billows.
      - **Two passes went into picking the colour in sRGB and wondering where
        the purple went.** Godot blends in LINEAR space, where grass's green
        channel is 0.45 against a dark violet's 0.003 — so a plausible violet at
        60% composites to a dead grey-green and the fill looks *dirty* rather
        than dangerous, which is exactly what the old flat slab did. The fix is
        a nearly-opaque, nearly-zero-green purple: at 0.93 alpha ALBEDO is more
        or less the answer, and the mat can afford it because it sits under a
        fighter's feet and never occludes anyone. Only the thin haze is ever
        between the camera and a body.
      - Two smaller things each cost a look: a quad's own straight edge is
        visible wherever the map's isn't (the haze is 2.6 m up, so its rectangle
        projects clear of the slab lip), hence the `rim_fade` that takes both
        quads out before their geometry ends; and scaling a whole 78 m edge of
        clouds up from zero on the first shrink puts a line of ten-pixel specks
        along the border that reads as confetti, hence the 0.55 floor under the
        bank's appear ramp.
      - `gas_cloud.glb` is now in `Loading.to_match`'s preload list (Showdown
        only). The bank is built on the match's first frame rather than on the
        first shrink, so without it a 6.6 MB GLB would come off disk during the
        pre-match beat — the same trap as `power_cube.glb`.
      - Fixed in passing: the MultiMesh was driving instance transforms from
        `_process` with physics interpolation on, which logged a warning every
        frame. `PHYSICS_INTERPOLATION_MODE_OFF` — the bank drifts on render
        time by design.
      - **Still open:** the gas makes no sound of its own and nothing announces
        a step. `MenuAudio` already has `gas_tick` for your own burn; a low
        rolling swell timed to the ease is the obvious next thing, and a haptic
        for "the ring is moving" would suit the table in **Haptics**.
- [ ] **Camera framing — measured, and the lens is the wrong lever.** The
      numbers, so this is not re-derived: the camera is 105.5 m out at a 60
      degree pitch behind a 7 degree vertical FOV, which is **22.9 x 12.9 m** at
      16:9, or 55.8 px/m on a 1280-wide frame. Henry renders about **65 x 85 px
      there — 5% of the screen width**, against roughly 8-10% for a Brawl Stars
      brawler. So the complaint is real.
      - But **zooming in is blocked by the range cap.** The vertical half-span
        is 6.45 m and the weapon range cap is 5.5 tiles = **11 m**: a target at
        max range straight up or down the screen is already 4.5 m off-camera,
        and the horizontal half-span (11.5 m) only just covers it. Any zoom
        makes you shoot at what you cannot see, which is a balance change
        wearing a camera change's clothes.
      - The lever is therefore **`Kits.MODEL_SCALE` (1.44)**, i.e. the item
        below — or the range cap itself. Decide the two together as that entry
        already says; the camera on its own has nothing left to give.
- [x] **Power cubes are the Meshy token again.** Re-landed from `72d806f`:
      `_spawn_cube` instances the token model, spinning about Y on a 2.6s loop
      with a soft sine bob (looped tweens) and the runtime metallic clamp the
      character models get, instead of a purple emissive box. The net-aware
      pickup path is untouched.
- [x] **Loot boxes are aimable and wear health bars.** Tap-to-fire falls back to
      the nearest visible box when no enemy is in range (Supers never do), and
      `fighter_bars.gd` draws each box a half-scale health bar; box damage
      replicates so the bars stay honest in wifi play.
- [x] **Impact VFX.** `scripts/hit_spark.gd` (`HitSpark`) — a burst where a hit
      lands and a flash at the barrel when one is fired. Built the way
      `shockwave.gd` is (an ImmediateMesh rebuilt per frame, unshaded from
      vertex colours, freeing itself), not with GPUParticles3D: the camera is a
      fixed steep top-down, so a spray drawn flat in XZ reads correctly from the
      only angle anyone sees, costs one draw call and ships no art file. One
      class covers both jobs — a hit is a wide spray, a muzzle flash is narrow,
      short and coreless (`main.gd:_hit_spark` / `:_muzzle_flash`).
      - **Sparks share the impact sound's `IMPACT_GAP` throttle**, so a
        nine-pellet shotgun spawns one burst rather than nine stacked on a
        frame.
      - Only projectile styles get a muzzle flash (`MUZZLE_STYLES`) — a melee
        lunge already has its `MeleeSwipe`, and a flash on one reads as a gun.
      - Two things cost a debugging pass each, both worth remembering: the
        material needs **`no_depth_test`** (a burst sits at chest height *on*
        the fighter it belongs to, so at a 60° camera pitch the body hides its
        own hit), and the first pass was **far too small to see** — the camera
        shows ~23 m across 1280 px, about 55 px/m, so sub-metre geometry is a
        handful of pixels. It rendered perfectly and was invisible.
- [x] **Bushes read as tiles, not scattered clumps.** Brawl Stars bushes
      fill their tile and merge into one dark contiguous mass with a crisp
      outline, and the darkness *is* the affordance that says "you can hide
      here". Ours currently does the opposite on purpose: `_build_bushes`
      jitters every `tall_grass.glb` instance by a random yaw and a 0.92–1.12
      scale specifically so a field of them does not read as a tiled texture.
      Shipped as two instanced layers per bush tile:
      - A flat **skirt** quad sized exactly to `Kits.TILE`, so a patch of them
        meets edge to edge with no seam and becomes one contiguous dark shape.
        This is what actually makes a bush read as a tile; the clump on top is
        only volume.
      - The skirt's outline is **merge-aware**: `_open_edges` packs "this side
        has no bush neighbour" into the MultiMesh's `INSTANCE_CUSTOM`, and
        `SKIRT_SHADER` draws the rim only on those sides, so a 3x3 patch is one
        shape rather than nine squares in a grid.
      - The **canopy** lost its yaw and scale jitter (which existed precisely to
        stop a field reading as tiled) and is scaled to overhang its tile by 8%
        so neighbouring clumps interlock. `CANOPY_TINT` and `SKIRT_FILL` put it
        well below the floor green, which is what makes a patch read as cover.
- [x] **The bush reveal radius is visible.** The *logic* was already exactly
      Brawl Stars': `main.gd:can_see` hides anyone standing on a `b` tile beyond
      `Kits.TILE * 2.0`, and `_update_concealment` fades the player while
      hiding distant enemies outright. Nothing shows the player where that
      radius ends, though — in Brawl Stars the foliage around you goes
      translucent and cuts a visible window in the bush field, which is what
      makes "a certain number of tiles around you" legible. Both bush layers now
      run a shader that fades any instance within `reveal_center`, which
      `_update_concealment` points at the player every physics frame — so what
      you can see through is exactly what you can be seen through. The 2-tile
      constant that used to be duplicated at `main.gd:1301` and `main.gd:2069`
      is now `Kits.BUSH_REVEAL`, and the shader reads the same one.
- [x] **A modelled fighter in a bush now fades.** Done with the hit flash — see
      the Character models section; the two shared one missing mechanism. Both
      halves of the concealment tell are in place: the bush around you opens up
      *and* you go translucent inside it. (Water is still a flat translucent
      slab, and that is the only piece of the old entry left.)

## Game systems

- [ ] **Two modes exist.** Showdown, and Nobles Cup (`cup_mode.gd` + `ball.gd`).
      `Session.mode` and the mode branch at the top of `main.gd:start_match` are
      where the next one goes; every other event card is still a locked dummy.
      **Cup's pitch dressing is done**: markings came with the arena pass and
      the goal is now a net on the mouth floor plus posts and a crossbar on the
      goal line (`Arena._build_goal`). The third of this entry about the ball
      was stale — `ball.gd` has loaded `assets/soccer_ball.glb` since it
      shipped, and the sphere at `:53` is only the fallback for a build without
      the asset.
- [x] **The blue screen is gone; both scene changes run behind a loading
      screen.** `menu.gd`'s PLAY and every way back to the lobby now call
      `Loading.to_match` / `Loading.to_menu` (`scripts/loading_screen.gd`,
      autoload `Loading`) instead of `change_scene_to_file`. It is an autoload
      because a loading screen owned by the scene being replaced dies halfway
      through the job it is covering.
      - It threaded-loads the target scene **and all seven character GLBs**, and
        holds a reference to each for the session — which is what turns
        `fighter.gd`'s `load(kit.model)` into a cache hit rather than a disk
        read on the frame a fighter spawns.
      - The screen is `assets/menu/background/loading_keyart.jpg`, which was
        imported and referenced by nothing, under a `GradientTexture2D` scrim:
        mode name, map, the fighter you picked, and a real progress bar.
      - It lifts on `Loading.done()`, called at the **end of `start_match()`**
        rather than in `_ready` — `start_match` awaits a frame partway through,
        so `_ready` returns before the arena exists. `SAFETY_SECONDS` lifts it
        anyway if some path forgets to call it, and `MIN_SHOW` stops it flashing.
      - Gotcha worth keeping: `ResourceLoader.load_threaded_get` **consumes** the
        request, so re-polling a path after collecting it reports
        `THREAD_LOAD_INVALID_RESOURCE` and every finished load looks failed.
      - Shoot it with `NS3_MENU_SCREEN=loading NS3_MENU_SHOT=<abs.png>`.
      - The `NS3_*` menu-skipping hooks still change scene directly on purpose,
        so the sim and screenshot harnesses are unchanged.
- [x] **The match introduction already animates** — this entry was stale. The
      cards slide and stagger in, the VS punches in on `TRANS_BACK`, the
      countdown digits scale on every tick, and the mode title scales up as the
      rows fade at `PREMATCH_INTRO_AT`. It landed with the pre-match rework in
      `d4e6678`; `versus_screen.gd:_slide_in`, `:95-98` and `:_show_intro` are
      the tweens. Nothing to do.
- [x] **The end-of-battle screen is a real results card.** `_show_results` is
      now the single entry point for all three endings (Showdown placement, a
      Cup scoreline, and a net client whose fighter went down while the host's
      match ran on), so they cannot drift apart. It builds a `MenuUI` card —
      your fighter's portrait on a tinted backdrop, the headline, a stat table,
      reward chips that count up from zero with a chime, and styled buttons —
      fresh into `results_body` each time.
      - **Per-match stats are real now**: `Fighter.stats` (damage, kills, cubes,
        goals, saves, survived) is always on and per fighter, distinct from
        `sim_stats`, which stays a per-KIT aggregate behind `sim_active`.
        Showdown shows damage / eliminations / cubes / survived, Nobles Cup
        goals / saves / damage / eliminations.
      - `survived` measures from `match_start`, set when the phase turns
        PLAYING — `now` runs for the life of the scene, so after PLAY AGAIN it
        would otherwise report the sum of both matches.
      - **Nobles Cup shows a full scoreboard, not your own stats.** Both teams,
        all six players, portrait chip on the team colour, G / K / DMG, sorted
        goals-then-damage so whoever decided the match is top of their column,
        your own row on a brighter plate. `_show_results` grew an optional
        `board` argument for it; Showdown and the net client pass nothing and
        are unchanged. This works in Cup and could not in Showdown: `fighters`
        never shrinks there, because a death parks a fighter rather than freeing
        it, so everyone is still present at the whistle with their stats intact.
      - **The SAVES row was dropped**, measured rather than guessed: with
        `NS3_SAVE_LOG=1` over a full match the ball changes hands about seven
        times and nearly all of those are a team collecting its own forward
        pass, so the row read 0 nearly always. `CupMode._is_save` and
        `Fighter.stats.saves` are still maintained for whenever there is
        somewhere worth showing them.
      - Two things keep the card on top, and both are load-bearing:
        `hud.move_child(results, -1)` for the fighter health bars, which are
        added to the HUD after the overlay is built in `_ready`; and **hiding
        `CupMode.HUD_GROUP`**, because Cup's scoreboard sits on its own layer
        *above* the card where `move_child` cannot reach it — without it the
        scoreline printed twice. Hidden rather than freed; `_build_hud` sweeps
        it on PLAY AGAIN.
      - Shoot it with `NS3_END=<sec>` alongside `NS3_SHOTS`.
- [ ] **PLAY AGAIN still only exists for the host.** Both buttons are `MenuUI`
      plates now and LOBBY goes through the loading screen, so what is left here
      is purely the multiplayer question: PLAY AGAIN is not built at all for
      anyone who is not `authoritative`, so a wifi client gets no rematch
      control and just waits. See the Multiplayer item on the rematch flow.
- [x] **A Nobles Cup goal resets the pitch properly.** `kickoff()` now calls
      `Fighter.kickoff_restore` on everyone still standing — health, ammo and
      every debuff timer, but deliberately **not** `super_charge`, since losing
      a charged Super would punish the team that just scored and a fighter who
      died for one already loses it in `respawn()`. It also clears anything in
      flight through the new `main.gd:clear_in_flight()`, shared with
      `start_match` so the two lists cannot drift; that sweep picked up
      `MeleeSwipe`, `Shockwave` and `DisconnectZone`, which `start_match` was
      not freeing either. The Ball is excluded on purpose — kickoff re-places
      it. As a bonus this stops a burn lit before the whistle ticking through a
      freeze that holds its victim still.
- [x] **The camera pans to the goal when someone scores.** `main.gd` grew a
      `focus_camera(at, seconds)` that sends the view somewhere other than the
      player for a beat, on a slower `CAM_PAN` lerp than the `CAM_FOLLOW` it
      chases the player with, so it reads as a move rather than a cut.
      `CupMode._goal_check` calls it with the conceded goal for
      `GOAL_CAMERA_HOLD` (1.35s) — deliberately shorter than the 2.0s
      `KICKOFF_FREEZE`, so the view is home again before input is handed back.
      The focus point is pulled `GOAL_CAMERA_INSET` back toward the centre spot:
      a goal is at the very edge of the map, and framing it dead centre fills
      the top half of the screen with sky past the end of the arena.
- [ ] **Shop and Trophy Road are placeholder screens** — dummy cards, nothing
      purchasable. **Settings are not** — that half of this entry was stale and
      has been struck: Music, SFX and Hints all write through `SaveGame` and are
      honoured (`menu_audio.gd:41` and `:59` gate every sound, match SFX
      included, since `main.gd`'s `sfx_at`/`sfx_ui` both go through
      `MenuAudio.play_at`; `menu.gd:113` and `main.gd:_start_battle_music` check
      `music_on`; `home_screen.gd:308` reads `hints_on`). Player name and the
      developer-mode unlock persist too.
- [ ] **Balance pass.** Run `NS3_SIM=<n>` (headless) across the seven kits and
      tune against `CHARACTER_BUILDING.md`; damage is derived from the tier
      tables, never picked by taste. Nova is a placeholder — don't tune her.
- [x] **Bots use walls as cover and bushes to ambush.** Both are expressed the
      way every other decision in `bot_brain.gd` is — a point to walk toward —
      so they drop into the `_pick_move` ladder without disturbing the
      priorities around them. Verify either one with `NS3_BOT_LOG=1`.
      - **Cover** triggers on the two moments a bot has nothing to trade: below
        30% health (which already fled, and now flees *somewhere*), or holding
        an empty magazine within 1.2x weapon range of someone who can actually
        see it. `_find_cover` scores every tile in a 4-tile window that has a
        wall on the line to the enemy, preferring the shortest trip — the walk
        is the part that gets you shot — with a smaller term that stops a bot
        backing so far out that returning means re-crossing the same ground.
        Arriving, it stands still and reloads rather than jittering on the tile.
      - **Ambush** is the bush half. Idle bots (ranked below loot — a cube in
        hand beats a hiding place) walk to the nearest reachable bush and wait
        there, and a bot already in one holds still instead of breaking cover to
        meet a target it can see. That asymmetry is real and was previously
        never sought: `main.gd:can_see` tests the *target's* tile, so a bot in a
        bush sees out while staying unseen past `Kits.BUSH_REVEAL`.
      - **Both are time-boxed, and that is load-bearing.** Lurking runs
        `AMBUSH_HOLD` then rests for 4-8s of wandering before another bush is
        considered; without the rest a bot that spawns beside one never leaves
        it and the match stops converging. A hidden bot also gives a target
        `AMBUSH_PATIENCE` to walk into range before closing itself, or an
        ambusher whose target never approaches simply stops playing.
      - **Every terrain query is sampled against the ASCII map**
        (`Arena.tile_at`), not raycast: it costs no physics, agrees exactly with
        `blocks_movement` and with a wall `Arena.open_at` has shot out, and is
        cheap enough to score a whole window on one think tick. Only `#` blocks
        sight — water and bushes do not.
      - Two costs found by measuring rather than reasoning, both now guarded:
        a bot at point-blank rescanned the window every `COVER_HOLD` and could
        never find anything (there is no line to break with someone on top of
        you — `COVER_MIN_ENEMY`), and caching only *successful* searches left a
        bot with nothing to hide behind rescanning every think tick for as long
        as it stayed in trouble. Failed searches are cached too.
      - A/B'd at 20 headless matches a side. Damage per spawn is up slightly
        across the board — cover makes fights last longer — average placement is
        flat, and no kit's `hits/atk` collapsed toward zero, which was the
        failure mode being watched for. Win% moved by up to 10pp in both
        directions, which at ~20 spawns per kit is noise, not a balance finding;
        the balance pass above is still open and unaffected.
- [x] **Bots use terrain offensively too.** The three things this entry named
      all landed, in the same idiom as the defensive half: a scored window of
      candidate tiles sampled against the ASCII map, held for a beat so it
      cannot oscillate, and cached on FAILURE as well as success.
      - **Flank.** A bot losing the health race by `FLANK_DEFICIT` (20% of max,
        about one exchange) breaks the target's sight and comes back on a
        different bearing. `_find_flank` is `_find_cover` with the sign
        reversed: cover wants the NEAREST wall, which is often the one you are
        already behind, so this scores the TURN around the target
        (`FLANK_MIN_TURN`, 55 degrees) and stays inside weapon range, because a
        flank that ends out of range is a retreat with extra steps.
      - **Covered approach.** Beyond ideal range a bot now looks for a step that
        is hidden from the target and at least a tile nearer, instead of walking
        the straight line. The straight run is still the fallback — most of an
        open map has no covered step and should not pay to look for one.
      - **Gas pressure.** At fighting distance near a closing ring, stand on the
        safe side of the target at ideal range, so every step they give up is a
        step nearer the gas. The only one of the three that needs no search: the
        inside line is a bearing, not a tile. Gated on `main.gd:gas_closing()`
        rather than `gas_depth` alone — before the first shrink `depth_inside`
        measures to the MAP edge, so without it bots would spend the opening of
        every match pressing opponents against an arena wall.
      - **The interaction that had to be found: a reposition that makes a bot
        forget its target is a reposition that fails.** `_update_target` drops
        an unseen target after 1.5s, and both new behaviours deliberately break
        that sight for longer than the walk takes. `_target_memory` raises the
        grace to 4s while a flank or approach is committed, bounded by the holds
        themselves so a stale point can never extend it.
      - **Showdown only**, and structurally so: all three sit below the
        `game.cup` branch in `_pick_move`, because in Nobles Cup the ball owns a
        bot's movement and a bot that peels off to flank has stopped playing the
        mode. Verified at runtime, not just by reading — a Cup match logs 21
        cover takes and exactly **zero** flanks, covered approaches or inside
        lines.
      - **A/B at 60 headless matches a side (~65 spawns per kit).** Damage per
        spawn 9626 → 9583, attacks per spawn 10.29 → 10.21, hits per attack
        1.151 → 1.147 — flat inside 1% on all three, and nothing collapsed
        toward zero `hits/atk`, which is the delivery bug being watched for.
      - **The same A/B at 20 matches a side said damage was down 11%.** It was
        noise. That is worth keeping: this file already warned that ~20 spawns
        per kit is too few, and this is the measurement that proves it. Run the
        sim at 60+ before believing anything.
      - **Win% moved up to ~10pp per kit, and the direction is not random.** It
        tracks attack rate, because the cost of all this is time spent walking
        instead of shooting: Leon (16.4 attacks/spawn, the highest) went
        19.2% → 9.0% with attacks per spawn down 18%, Nova (12.6) 20.3% → 11.1%
        on the same 18% drop, while Anders (the lowest rate) went 1.4% → 4.8%
        with damage per spawn UP 32%. Net effect is a mild flattening — win%
        spread across the roster tightened from sd 6.1 to 4.6.
      - **This moves the baseline the balance pass measures against**, so do the
        balance pass after this, not before. Verify any of it with
        `NS3_BOT_LOG=1`, which now prints flanks, covered approaches and inside
        lines alongside cover and bushes.

## Multiplayer

- [ ] **Clients have no prediction.** Client fighters are pure puppets rendering
      30 Hz snapshots — fine on LAN, visibly laggy on anything worse.
- [ ] **iOS can't receive UDP broadcast discovery replies** without Apple's
      multicast entitlement, so iPhone players must use join-by-IP. Either
      request the entitlement or make join-by-IP the primary flow on iOS.
- [ ] **Only the host gets PLAY AGAIN**, and a host that dies keeps simulating
      while showing results — the rematch flow needs a real design.
- [ ] **A client's results card has one stat row.** `deal_damage` returns early
      when `not authoritative`, so a client's `Fighter.stats` are all zeros and
      `main.gd:_net_rows` shows only the survival clock it measures itself
      rather than a column of noughts. Fixing it means the host sending each
      player their damage / eliminations / cubes with the match-over RPC.

## Ship

- [ ] **The app icon is a placeholder.** `godot/icon.png` is a flat gold star on
      navy at 1024x1024. Script-drawable (pipeline 3), and needed before a build
      on a phone looks like a real game. The launch art beside it is done — the
      iOS storyboard inherits the boot splash, see **Boot** above.
- [x] **Character and prop textures are capped; the bundle is less than half
      what it was.** The seven `assets/*_texture_0.png.import` files carried
      `process/size_limit=0` against 4096x4096 sources. Characters are now
      capped at **1024** and props (loot crate, gas cloud, tall grass) at
      **512**, the cap `power_cube` already proved. `.godot/imported` — which is
      what actually ships — went **120 MB → 48 MB**: the characters 62.5 MB →
      9.6 MB (leon 16.2 → 1.65, kovacs 13.8 → 1.47, henry 13.4 → 1.43) and the
      props 24 MB → 1.6 MB. 1024 rather than 512 on the characters because they
      are the menu's hero art, rendered ~540 px tall on the detail screen; a
      before/after of Leon at that size is pixel-for-pixel indistinguishable,
      shirt lettering included, and 1024 still leaves ~2.5x the on-screen texel
      density. Re-cap any new character import the same way.
- [x] **The export runs end to end, and the blocker was never the account.**
      `Tools/export_ios.sh` stopped for months on:

          error: No Account for Team "KJDG3J6ZYY"
          error: No profiles for 'com.ryder.noblestars3d' were found

      Both of those point at the Apple ID, and the Apple ID was fine the whole
      time. **The preset named the wrong team.** `KJDG3J6ZYY` is the free
      personal team of the signing account; it develops under the paid team
      `S7AT3UP8R4` ("ANDREW DWIGHT CARLSON"), so Godot wrote an id into
      `DEVELOPMENT_TEAM` that genuinely had no account behind it. One line in
      `application/app_store_team_id` and the script now prints
      `** EXPORT SUCCEEDED **` with no errors and leaves a 66 MB `.ipa` beside
      the `.xcodeproj`.
      - **What hid it was the previous fix.** The note in CLAUDE.md said this
        error "usually means a signing-identity CONFLICT, not a missing
        account… the account is fine", which was true of the earlier
        `Apple Distribution` vs `Automatic` conflict and sent every later look
        away from the team id. Read the team off the artefact instead of
        trusting the error or the preset:
        `security cms -D -i <app>/embedded.mobileprovision` prints
        `TeamIdentifier` and `TeamName`.
      - **It is a paid account**, so the profile is good for a year
        (`TimeToLive 365`) — the 7-day expiry that forces weekly reinstalls is
        a free personal team and does not apply.
      - `xcodebuild -allowProvisioningUpdates` builds and signs the written
        project with no GUI step: BUILD SUCCEEDED, `Apple Development`.
      - Simulator builds stay blocked upstream (godotengine/godot#118161 —
        simulator `libgodot.a` is x86_64-only), so the arm64 device slice is
        the only path regardless.
      - **Still open, and only Ryder can do it:** installing needs Developer
        Mode on the handset (Settings → Privacy & Security → Developer Mode,
        then a restart), or `devicectl` stops with
        `Developer Mode is disabled`. `devicectl` also needs `DEVELOPER_DIR`
        set, exactly like the export.
- [x] **The pbxproj placeholder lines are gone, and the export is scripted.**
      Re-measured against the 4.7.2.stable templates: the generated
      `project.pbxproj` contains **no** `$additional_pbx_*` /
      `$pbx_embeded_frameworks` lines — no `$` placeholders at all — and
      `plutil -lint` parses it. `Tools/export_ios.sh` keeps the strip as a
      regression guard and says so when there is nothing to strip. Two things
      the script encodes: `xcode-select` points at CommandLineTools so the
      export needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
      and the CLI exporter **ignores `export_project_only=true`** — it writes
      the Xcode project and then tries to archive anyway, so a nonzero exit does
      **not** mean the project is missing.
- [x] **The match has sound.** 28 combat sounds synthesized through `MenuAudio`
      (pipeline 1), so the game still ships zero audio files. Covered: a shot
      per weapon class, projectile impact and a separate melee connect, melee
      whoosh, reload tick, empty-mag click, Super charged and Super fired,
      elimination, loot-box break, wall break, power-cube pickup, gas tick,
      low-health pulse, countdown and go, victory and defeat stings, and Nobles
      Cup's kick, goal horn and whistle.
      - `main.gd:sfx_at` attenuates by distance from the listener (full level
        inside 6 m, gone by 30 m — the camera shows ~23 m) and jitters the pitch
        ±6%, without which a burst of identical samples reads as one looping
        tone rather than as gunfire. `sfx_ui` is the unattenuated path for the
        countdown, the stings and the whistle.
      - Sounds are keyed off `weapon.style` in `_attack_sound`, not off the kit,
        so a new character inherits one from the style it picks.
      - `MenuAudio.VOICES` went 8 → 16: a nine-pellet shotgun, its impacts and a
        bot firing across the map can all land in one frame, and the round-robin
        was cutting sounds off part-way through.
      - **`_render` falls through to "click" for a name it does not know**, so a
        typo plays a menu click mid-firefight instead of failing. `Godot --path
        godot --headless --script res://tools/sfx_probe.gd` renders the whole
        table and flags any name with no entry of its own, plus anything silent
        or clipping. Add a name to its list whenever you add one to the table.
      - `NS3_SFX_LOG=1` prints every sound as it fires, which is how you tell
        "the hook never ran" from "it is too quiet to notice".
      - The results screen chimes per reward now (`_count_up` fires "reward" as
        each of the three chips starts counting). Still open: nothing
        distinguishes one kit's shotgun from another's, and there is no
        positional stereo (everything is mono, attenuated only by distance).
- [ ] **Drop Brawl Stars SFX in as placeholders first.** Synthesising the table
      above is the ship path, but it is slow to tune blind, and the match is
      silent *today*. Standing in ripped Brawl Stars clips for shot / hit /
      elimination / Super / goal gets the timing and the mix roughed in
      immediately, and makes it obvious which sounds actually matter before
      anything is synthesised for them. Strictly internal — they are Supercell's
      audio and cannot ship — so keep them out of the export from the start:
      a `godot/assets/sfx_placeholder/` in `.gitignore`, loaded only when
      present, so a build with the directory missing simply runs silent rather
      than failing. Every one of them is a placeholder for a `MenuAudio` entry
      or a voiceline, not a substitute for one.
- [ ] **Voicelines.** Nine fighters x spawn / attack / Super / defeat / victory,
      recorded by the people the characters are based on. Cannot be generated —
      it needs real people in a room, so it is the longest lead time in this
      file and should be booked before the code hook exists.
- [ ] **More music.** Two tracks ship (`lobby_vibes`, `clash_carnival`). Wants at
      least a results/victory sting, and a second battle track so Cup and
      Showdown do not sound identical.

## Tooling & workflow

The answer to "which Godot plugins should we install" turned out to be **none**,
and that is worth recording so it is not re-litigated. `gdtoolkit` (`gdlint` /
`gdformat`) was measured against all 44 files: 145 findings, of which two were
real (`ball.gd:135` and `menu_popups.gd:54`, both unused arguments). The rest
were 81 `class-definitions-order`, 26 `mixed-tabs-and-spaces` that are every one
of them intentional continuation alignment, and 26 `max-line-length` at its
default 100. `gdformat` would additionally rewrite the deliberate paren
alignment in `kits.gd`'s tier tables and the shader strings in `arena.gd`.
**Both real findings are now fixed**: `ball.gd:135`'s unused `now` is renamed
`_now` (renamed rather than deleted — every caller is in `cup_mode.gd`, and
`_`-prefixing is the GDScript idiom that satisfies the lint with no signature
change), and `menu_popups.gd:54`'s unused `shell` argument is dropped from that
private static helper.
Editor addons have nothing to attach to when the `.tscn` files are empty shells
and everything is built in code, and the Godot MCP servers bridge a *live
editor* — the workflow the `NS3_*` env hooks exist to avoid. What the project
wanted was configuration, not packages.

- [x] **The reimport footgun is handled automatically — but the hook is not a
      compile check.** A `PostToolUse` hook in `.claude/settings.json` runs
      `Godot --headless --import` after any edit to a `godot/**/*.gd`. Skipping
      that import makes class members silently vanish at runtime, which is the
      single nastiest failure mode in this project because it produces no error
      at edit time. The hook derives the project directory from the edited file
      rather than hardcoding a path, and costs 1.2s. **A new `.claude/` is not
      picked up until `/hooks` is opened once or the session restarts** — the
      settings watcher only watches directories that had a settings file at
      session start.
      - **`--import` does NOT report GDScript parse errors.** A `main.gd` that
        could not load at all imported clean and silent; the
        `SCRIPT ERROR: Parse Error` only appeared on running the game. Hit
        independently in two sessions. The hook makes the import *feel* like a
        compile step, which is exactly what makes this sharp — to know a script
        parses, run the game.
- [ ] **Concurrent Godot runs need a real guard, and the repo has none.** Two
      processes contend on the import lock hard enough to look like a hang: an
      import that takes 1.2s alone sat for six minutes beside a second instance.
      Everything about detecting and clearing that has gone wrong at least once
      and is written up in CLAUDE.md — detect with `pgrep -x Godot` (a
      `ps | grep` matches the shell running your own script and reports a held
      lock forever), kill the job rather than the binary (`pkill` leaves the
      launching shell to start the next one), and **never kill an unidentified
      Godot** — a person playing the game is distinguishable from a stale agent
      process only by an interactive `-zsh` parent and the absolute `--path`
      form. A small wrapper that takes a real lockfile and refuses rather than
      clearing would remove the whole class of problem.
- [x] **Permission allowlist for the Godot binary** and read-only git, also in
      `.claude/settings.json`. One limitation worth knowing: prefix rules match
      from the start of the command, so the `NS3_KIT=nova … Godot …` form does
      not match — the env var comes first. Only the bare `Godot …` form is
      covered.
- [x] **Debug screenshots no longer write into the project.** `NS3_SHOTS` and
      `NS3_MENU_SHOT` handed an environment-supplied path straight to
      `save_png`, and a relative path resolves against `res://` — so
      `NS3_SHOTS=shot:1` wrote `shot_1.png` into the project, where the next
      `--import` swept it up as a game asset that then had to be found and
      removed before committing. `Session.shot_path` now sends anything not
      absolute to `user://`, and both hooks print where they actually wrote.
- [x] **`godot/.godot/` is gitignored** and its 422 files untracked. It was 52 MB
      of import and shader cache that churns on every reimport, and it made up
      most of the volume of recent commits — `aee0066` was 101 files, nearly all
      of it cache. Verified regenerable rather than assumed: a copy of the
      project with no `.godot` cold-imports in 5.3s with no errors and runs a
      full `NS3_SIM` match. **A fresh clone must import once** before the project
      will open or run.
- [ ] **No GDScript language server is wired into Claude Code.** `.gd` files get
      no go-to-definition, no find-references, no diagnostics. Godot ships a
      language server but only serves it while the editor is open, so this would
      mean keeping the editor running alongside. Marginal at 13k lines where
      grep works, but it is the one piece of real tooling still missing.
