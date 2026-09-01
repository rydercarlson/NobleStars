# Noble Stars — TODO

Running list of the major fixes and gaps in the Godot 3D game (`godot/`). Roughly
priority-ordered inside each section. v1 SpriteKit (`NobleStars/`) is maintenance
only and is not tracked here.

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
- [ ] **Nova and Anders still render as capsules.** They have no `model` key in
      `kits.gd`, so they fall back to `_setup_capsule`. Nova is a placeholder
      character; Anders needs a Meshy pass through `Tools/fix_meshy_glb.py`.
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
- [ ] **Leon, Anders and Hammy have no named unlock.** The v0.5 trophy road
      unlocks Sanjit, Tony, Kovacs and Henry only, so those three are reachable
      only through a shop Star Drop. Decide whether they get road milestones,
      pass tiers, or stay Star-Drop-only.
- [ ] **The 13 duplicate `icons/*.webp`** (coin, gem, trophy, gear, lock, …) are
      shadowed by same-named `svg/*.svg`, which `MenuUI.icon_texture` prefers.
      Harmless, but they are dead bytes in the export until one set is dropped.
- [ ] **Nova and Anders have no portrait or card art** — they fall back to a
      colour chip until they get models.

## Arena & visuals

- [ ] **Arena visual pass.** The floor is one flat green plane, walls are plain
      boxes, bushes are stacked spheres. Needs real materials, tile variation,
      and readable wall silhouettes at the top-down camera angle.
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
- [ ] **Water and bush tiles are untextured colour blocks**, and a modelled
      fighter standing in a bush gets no self-view tell at all —
      `fighter.gd:set_concealed` only fades the capsule fallback's material.

## Game systems

- [ ] **Only Showdown exists.** `Session.mode` and the `_mode` hook at the top of
      `main.gd:start_match` are the branch points; every other mode in
      `mode_select.gd` is a locked dummy.
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

- [ ] **Get a build onto a real iPhone.** Simulator builds are blocked upstream
      (godotengine/godot#118161 — simulator `libgodot.a` is x86_64-only), so the
      arm64 device slice is the only path until fixed templates ship.
- [ ] **The generated pbxproj needs six placeholder lines deleted by hand**
      (`$additional_pbx_*`, `$pbx_embeded_frameworks`) before `xcodebuild` will
      parse it — script this into the export step.
- [ ] **No sound at all.** SFX for shots, hits, eliminations, and the gas ring,
      plus voicelines recorded by the people the characters are based on.
