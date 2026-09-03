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
- [ ] **A blue screen sits between the menu and the match.** `menu.gd:406`
      `start_match` calls `change_scene_to_file("res://game.tscn")`, which is a
      *blocking* load: the menu is torn down, then the process sits there
      loading the character GLBs and the 21 MB `power_cube.glb` `preload` at
      `main.gd:15` before `main.gd` builds anything. What you look at meanwhile
      is the bare 3D clear colour — `main.gd:135`'s
      `background_color = Color(0.5, 0.75, 0.9)`, the arena's pale sky — with no
      arena, HUD or fighters in it yet. It reads as a hang, not a transition.
      Wants `ResourceLoader.load_threaded_request` behind a real loading screen
      (mode name, map, the fighter you picked, a progress bar), which is also
      the natural home for a "loading" beat before the versus cards. Note the
      same blocking call is on the way back out (`main.gd:263`, `:2299`) and on
      the LOBBY button.
- [ ] **The match introduction is static.** `versus_screen.gd` lays out the
      right things — enemy cards on red across the top, yours on blue at the
      bottom, VS between, mode/map top-left, countdown bottom-right, then the
      mode title takes over at `PREMATCH_INTRO_AT` — but nothing *moves*. The
      cards do not fly in or stagger, the VS does not hit, the countdown digits
      do not punch, and the handoff to the mode title is a swap rather than a
      transition. Brawl Stars sells this entirely on timing and easing, and it
      is 7 seconds (`main.gd:PREMATCH`) the player spends staring at it every
      single match. All tween work in `versus_screen.gd`; no new art.
- [ ] **The end-of-battle screen is two labels and two buttons.**
      `main.gd:_build_results_overlay` is a 55%-black `ColorRect`, a
      default-font `Label` for "VICTORY!/You placed #N of 10", a second for
      "TROPHIES +8  COINS +12  PASS +140", and two bare `Button`s — no `MenuUI`
      anywhere, in a game that has a whole design system one directory over. It
      should be a real results card: your fighter, placement, and **per-match
      stats**, which are currently tracked nowhere. The counters half-exist —
      `deal_damage` accumulates damage / hits / kills into `sim_stats`
      (`main.gd:514-519`) — but only `if sim_active`, and keyed by kit name for
      `NS3_SIM`'s table rather than per fighter. Making them always-on and
      per-fighter is most of the work; then show damage dealt, eliminations,
      cubes collected, survival time, and for Nobles Cup goals and saves.
- [ ] **PLAY AGAIN and LOBBY need a real pass.** Both are unstyled `Button`s in
      the overlay above. PLAY AGAIN is hidden outright for anyone who is not
      `authoritative` (`main.gd:249`), so a wifi client gets no rematch control
      at all and just waits — see the Multiplayer item on the rematch flow.
      LOBBY calls `Net.leave()` and then the same blocking
      `change_scene_to_file` as the blue-screen item above, so leaving a match
      stalls the same way entering one does.
- [ ] **A Nobles Cup goal does not reset the pitch.** `CupMode._goal_check` →
      `kickoff()` moves everyone back to their spawns and re-places the ball,
      but it leaves two things behind. Health is whatever each fighter had when
      the goal went in, so a team that just conceded can be handed the restart
      at a sliver of health and lose the next one immediately — a kickoff should
      put **everyone back to full**, the way a respawn already does. And
      **projectiles in flight survive the whistle**: a lob or a boomerang thrown
      a moment before the goal is still travelling through the reset and lands
      on someone standing on the centre spot. Both are in `kickoff()` — heal
      every fighter, and free the `Projectile` / `Lob` / `Boomerang` /
      `HackySack` children the way `main.gd:start_match` already does.
- [ ] **No camera move when someone scores.** A Nobles Cup goal resolves in
      `cup_mode.gd` with the score label ticking over and a kickoff freeze, but
      the camera stays locked on the player the whole time. It should pan to the
      goal that was scored on and hold there through the celebration before
      returning for the kickoff — the freeze window (`CupMode.frozen`) already
      exists and already holds input, so there is a ready-made slot for it.
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
- [ ] **Get a build onto a real iPhone.** Simulator builds are blocked upstream
      (godotengine/godot#118161 — simulator `libgodot.a` is x86_64-only), so the
      arm64 device slice is the only path until fixed templates ship.
- [ ] **The generated pbxproj needs six placeholder lines deleted by hand**
      (`$additional_pbx_*`, `$pbx_embeded_frameworks`) before `xcodebuild` will
      parse it — script this into the export step.
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
      - Still open: nothing distinguishes one kit's shotgun from another's, the
        results screen has no per-reward chime, and there is no positional
        stereo (everything is mono, attenuated only by distance).
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
