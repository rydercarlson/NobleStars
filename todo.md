# Noble Stars — TODO

Running list of the major fixes and gaps in the Godot 3D game (`godot/`). Roughly
priority-ordered inside each section. v1 SpriteKit (`NobleStars/`) is maintenance
only and is not tracked here.

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
- [ ] **No death or spawn animation.** `fighter.gd:die` scales the fighter to
      nothing over 0.35s and `respawn()` snaps `scale` straight back to
      `Vector3.ONE` — a fighter pops out of existence and pops back in. Both
      want a real clip now that the models have skeletons: a fall/collapse on
      death, and something on arrival (drop-in, rise, or at minimum a scale-up
      with a landing puff). This is felt hardest in Nobles Cup, where death is a
      three-second setback rather than an exit, so you watch it happen over and
      over in a single match. Note that **no GLB ships a death or hit clip** —
      the seven carry only Idle / Walking / Running / a run_fast variant / their
      attack — so death needs a new Meshy generation or hand animation, not just
      a `kits.gd` `clips` entry. Spawn is luckier: Kovacs has
      `Backflip_and_Rise` and Anders has `Backflip`, either of which already
      reads as an arrival.
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
      `set_concealed` fades with `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS`, since
      without the prepass you see a character's own far side through its front.
      `set_concealed` runs every physics frame for every fighter and changing a
      transparency mode recompiles a shader, so `_conceal_applied` gates it to
      actual transitions.

## Menu

- [x] **The menu is native Godot** (`godot/scripts/menu/`). The HTML build it was
      rebuilt from is gone — it could not ship inside the iOS app — and all of its
      art moved to `godot/assets/menu/` (cards, treats, decor, pass hero, skins,
      mode/currency icons, logo, key art). Copy and config live in
      `godot/data/{brawlers,game}.json`; stats come from `kits.gd`.
- [ ] **v0.5 content: what is still unwired is now a short list.**
      Gadget/gear/Star Power/Hypercharge **are** displayed — `MenuData._merge`
      carries them as a `loadout` dict and `BrawlerDetailScreen._build_loadout`
      draws a two-column block under the attack/super write-ups, returning null
      rather than four empty slots for a kit with no JSON entry (Nova, Ayaan).
      `trophyRoad` is wired too — the screen reads the nested
      `{trophies, reward}` shape and renders all six reward kinds.
      **Still unwired:** game.json's `quests`, `leaderboard`, `gameLog` and
      `upcoming` are read by nothing, and `MenuData.card_art` still has zero
      callers. `passRewards` was deliberately left at the 15 tiers the pass
      screen parses rather than the web build's 40.
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

- [ ] **Arena visual pass.** The floor is one flat green plane
      (`arena.gd:_build`), walls are plain boxes, water is a translucent blue
      slab. Needs real materials, tile variation, and readable wall silhouettes
      at the top-down camera angle. Bushes are done — see below. All shader and
      mesh work; no art files needed.
- [ ] **Camera framing.** Fighters read very small at the current height —
      revisit the zoom/tilt so character models are actually legible.
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
      Nobles Cup also wants real pitch dressing — goal frames, pitch lines, and
      a ball that is something better than the white sphere in `ball.gd:53`.
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
- [ ] **Bots ignore terrain.** `bot_brain.gd` handles targeting, lead aiming, and
      unsticking well, but it never uses walls as cover or bushes to ambush —
      the two things that make Showdown read as a real fight.

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
      navy at 1024x1024, and there is no iOS launch art. Script-drawable
      (pipeline 3), and needed before a build on a phone looks like a real game.
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
- [ ] **Get a build onto a real iPhone — and the blocker is now named, and it
      is Ryder's to clear.** `Tools/export_ios.sh` gets as far as the archive
      step and stops on:

          error: No Account for Team "KJDG3J6ZYY"
          error: No profiles for 'com.ryder.noblestars3d' were found

      That is not scriptable. It needs signing into Xcode → Settings → Accounts
      once with the Apple ID on that team and letting Xcode create the
      development profile; everything after that is automated. Simulator builds
      stay blocked upstream (godotengine/godot#118161 — simulator `libgodot.a`
      is x86_64-only), so the arm64 device slice is the only path regardless.
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
