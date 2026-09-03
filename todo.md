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

**2. Headless render — portraits, cards, map thumbnails.** `NS3_MENU_SHOT`
already proves the engine boots headless, poses a fighter and writes a PNG. A
`tools/render_portraits.gd` on the same rig as `menu_stage.gd` can shoot every
portrait and full-body card straight off the GLBs. That removes Meshy from the
portrait pipeline for the seven kits that already have a model, and means the
art regenerates for free whenever a model changes. The same trick shoots map
thumbnails from the arena camera.

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
- [ ] **Run cycle bobs after grounding.** The lift peaks at the trough of the run
      (11 cm on Kovacs), so the fighter now rises where it used to sink. The
      `run_fast_*` clips Meshy shipped (`run_fast_3`, `RunFast`, `run_fast_10`,
      `run_fast_3_inplace`) need no lift at all — try them as the `run` clip in
      `kits.gd` instead, or smooth the lift over a few frames.
- [ ] **Nova and Ayaan still render as capsules.** They have no `model` key in
      `kits.gd`, so they fall back to `_setup_capsule` in the match *and* on the
      menu stage. Nova is the sole starter, so a capsule is the first thing a
      new player ever sees. Anders and Hammy are wired now (`kits.gd:481`,
      `:559`) — this line used to name them. The two that remain need a Meshy
      pass through `Tools/fix_meshy_glb.py`; they are the only entries in this
      file that cannot be produced by one of the three pipelines above.
- [ ] **Death is a shrink tween.** `fighter.gd:die` scales the fighter to nothing
      over 0.35s — wire a real death clip (or a fall) now that the models have
      skeletons.
- [ ] **Model scale and collision don't match.** Every fighter uses the same
      0.45-radius / 1.6-tall capsule regardless of how wide the model is; Kovacs
      the tank in particular reads smaller than he collides.
- [ ] **Hit flash only works on the capsule fallback.** `fighter.gd` skips the
      damage flash for modelled fighters, so hits on Tony/Henry/etc. have no body
      feedback (only the damage popup).

## Menu

- [x] **The menu is native Godot** (`godot/scripts/menu/`). The HTML build it was
      rebuilt from is gone — it could not ship inside the iOS app — and all of its
      art moved to `godot/assets/menu/` (cards, treats, decor, pass hero, skins,
      mode/currency icons, logo, key art). Copy and config live in
      `godot/data/{brawlers,game}.json`; stats come from `kits.gd`.
- [ ] **v0.5 content is imported but not all wired.** `MenuData.card_art(id)`
      serves the new full-body cards, and brawlers.json now carries
      gadget/gear/starPower/hypercharge, but no screen displays them yet.
      game.json's `quests`, `leaderboard`, `gameLog` and `upcoming` sections are
      still read by nothing. `passRewards` was deliberately left at the 15 tiers
      the pass screen parses rather than the web build's 40.
      `trophyRoad` **is** wired now — the screen reads the nested
      `{trophies, reward}` shape and renders all six reward kinds.
- [ ] **Leon, Anders, Hammy and Ayaan have no named unlock.** The v0.5 trophy
      road unlocks Sanjit, Tony, Kovacs and Henry only, so those four are
      reachable only through a shop Star Drop. Decide whether they get road
      milestones, pass tiers, or stay Star-Drop-only.
- [ ] **Dead asset bytes.** The 13 duplicate `icons/*.webp` (coin, gem, trophy,
      gear, lock, …) are shadowed by same-named `svg/*.svg`, which
      `MenuUI.icon_texture` prefers; and `assets/Fox.glb` (162 KB) is referenced
      by nothing at all. Harmless, but they ride along in every export.
- [ ] **Portrait and card art has four holes.** Portraits are missing for Nova
      and Ayaan (7 of 9 exist); full-body cards are missing for Nova, Anders,
      Hammy and Ayaan (5 of 9). Missing art falls back to a flat colour chip on
      the roster grid, the detail screen, the shop's skin cards and the
      friends/leaderboard rows. **This does not need Meshy** — pipeline 2 above
      renders both straight off the GLBs for everyone who has one, which is
      seven of the nine today.
- [ ] **Menu art that the JSON already describes but nothing draws.** The shop
      lists five skins and only two have art (`decor/skin_leon_homecoming`,
      `skin_tony_fieldday`) — and `shop_screen.gd:_skin_card` draws the plain
      portrait anyway, so even those two never appear. Also unillustrated:
      per-brawler gadget/gear/Star Power/Hypercharge badges (the data is in
      `brawlers.json`, only generic icons exist), pins (`brawlers.json` carries
      a `pins` count and there is no pin art at all), player avatars for the
      profile popup and friends rows, map thumbnails for the events screen, and
      the club badge. All of it is pipeline 2 or 3.

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
- [ ] **No impact VFX.** Shots, melee arcs, and shockwaves have no hit particles
      or muzzle flash; only the damage popup sells a hit.
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
- [ ] **A modelled fighter in a bush has no self-view tell.**
      `fighter.gd:set_concealed` only fades the capsule fallback's material, so
      seven of the nine fighters get no feedback at all that they are concealed.
      The reveal shader above is half of this — the bush around you now opens
      up — but the fighter standing in it still does not fade. (Bushes
      themselves are no longer
      untextured blocks — `tall_grass.glb` landed in `08a6b5e` and the stacked
      spheres survive only as `_build_bushes_fallback`. Water is still a flat
      translucent slab.)

## Game systems

- [ ] **Two modes exist.** Showdown, and Nobles Cup (`cup_mode.gd` + `ball.gd`).
      `Session.mode` and the mode branch at the top of `main.gd:start_match` are
      where the next one goes; every other event card is still a locked dummy.
      Nobles Cup also wants real pitch dressing — goal frames, pitch lines, and
      a ball that is something better than the white sphere in `ball.gd:53`.
- [ ] **Shop, Trophy Road, and Settings are placeholder screens** — dummy cards,
      nothing purchasable, no settings actually persist.
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

## Ship

- [ ] **The app icon is a placeholder.** `godot/icon.png` is a flat gold star on
      navy at 1024x1024, and there is no iOS launch art. Script-drawable
      (pipeline 3), and needed before a build on a phone looks like a real game.
- [ ] **Character textures are uncapped and the bundle is enormous.** All seven
      `assets/*_texture_0.png.import` files carry `process/size_limit=0` against
      4096x4096 sources — henry 16.6 MB, leon 20 MB, kovacs 17 MB. `assets/` is
      254 MB and `.godot/imported` is 106 MB. `power_cube` already proves the
      fix (`process/size_limit=512` took it from 16.6 MB to 582 KB); apply the
      same cap to the characters and reimport before any device build.
- [ ] **Get a build onto a real iPhone.** Simulator builds are blocked upstream
      (godotengine/godot#118161 — simulator `libgodot.a` is x86_64-only), so the
      arm64 device slice is the only path until fixed templates ship.
- [ ] **The generated pbxproj needs six placeholder lines deleted by hand**
      (`$additional_pbx_*`, `$pbx_embeded_frameworks`) before `xcodebuild` will
      parse it — script this into the export step.
- [ ] **The match is completely silent.** `main.gd` loads `clash_carnival.mp3`
      and nothing else; there is no SFX path in the match at all. Nearly all of
      it is synthesizable through `MenuAudio` (pipeline 1) rather than recorded:
      - *Combat:* shot per weapon class (shotgun, lob, melee, sniper, boomerang,
        controller-button, hacky sack, curveball), projectile impact, melee
        whoosh and connect, reload tick, empty-mag click.
      - *Feedback:* Super charged, Super fired, elimination, loot-box break,
        power-cube pickup, gas-ring damage tick, low-health warning.
      - *Match flow:* countdown and go, victory and defeat stings, results-screen
        reward chimes for trophies, coins and Pass tokens.
      - *Nobles Cup:* kick, Super Shot, goal horn, whistle, kickoff, wall break.
- [ ] **Voicelines.** Nine fighters x spawn / attack / Super / defeat / victory,
      recorded by the people the characters are based on. Cannot be generated —
      it needs real people in a room, so it is the longest lead time in this
      file and should be booked before the code hook exists.
- [ ] **More music.** Two tracks ship (`lobby_vibes`, `clash_carnival`). Wants at
      least a results/victory sting, and a second battle track so Cup and
      Showdown do not sound identical.
