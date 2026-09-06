# Noble Stars — TODO

Open work on the Godot 3D game (`godot/`). **Finished work moved to
[`done.md`](done.md)** — 49 entries recording what was measured, what was tried
and rejected, and why things are the shape they are. Read it before reopening
anything here; several items on this list have a rejected first attempt on
record.

Reference material that is *not* a task — the three asset pipelines and the
"which Godot plugins" finding — is at the bottom under **Reference**.

## How to read this

**Priority** is about the player, not about how interesting the work is.

| | |
|---|---|
| **P0** | Stands between this project and a good build in Ryder's hand. Do these first. |
| **P1** | The game is measurably worse without it and somebody would notice in one session. |
| **P2** | Real work, wanted, not urgent. |
| **P3** | Nice to have, an open question, or deliberately deferred. |

**Effort** is calendar-feel, not lines of code.

| | |
|---|---|
| **XS** | One constant, one line, or a decision someone just has to make. |
| **S** | An afternoon in one or two files. |
| **M** | Several files, or needs measuring before it can be started. |
| **L** | A new subsystem. |
| **XL** | A new pipeline, native code, or other people's time. |

**[blocked]** means it cannot start until something outside the code happens —
a device, a decision, or a person. Those are the ones to unblock early even when
they are not urgent, and `Voicelines` is the extreme case.

## The list at a glance

| # | Item | Area | Pri | Effort | Blocked on |
|---|---|---|---|---|---|
| 1.1 | Match does not reach the screen edges | Phone fit | P0 | S | — |
| 1.2 | Menu does not reach the screen edges | Phone fit | P0 | S | — |
| 1.3 | Buttons and text are too small | Phone fit | P0 | M | — |
| 1.4 | Developer Mode on the handset | Ship | P0 | XS | Ryder + the phone |
| 2.1 | Speed / camera / model scale — one decision | Feel | P1 | M | a taste call |
| 3.1 | A shot cannot be called off after aiming | Controls | P1 | S | — |
| 3.2 | Judge the haptics on a real phone | Feel | P1 | XS | a device install |
| 4.1 | Nova and Ayaan are still capsules | Characters | P1 | L | Meshy pass |
| 8.1 | A client's death is silent and its HUD lies | Multiplayer | P1 | S | — |
| 10.1 | The app icon is a placeholder | Ship | P1 | S | — |
| 5.1 | The menu's second look | Menu | P2 | M | — |
| 5.2 | The roster should be tiles, not rows | Menu | P2 | S | — |
| 5.3 | Jackson's menu idea | Menu | P2 | ? | the idea, written down |
| 5.4 | A real progression system | Progression | P2 | L | what a level changes |
| 5.5 | Four fighters have no named unlock | Progression | P2 | XS | a content call |
| 6.1 | A third game mode | Modes | P2 | L | which mode |
| 7.1 | The balance pass | Balance | P2 | M | — |
| 7.2 | Sanjit's range feels too long | Balance | P2 | S | — |
| 3.4 | Hammy's heat pips should be one draining bar | Feel | P2 | S | — |
| 8.2 | Clients do not predict their own attacks | Multiplayer | P2 | M | — |
| 9.1 | Voicelines | Audio | P2 | XL | nine real people |
| 9.2 | The gas ring makes no sound | Audio | P2 | S | — |
| 11.2 | No GDScript language server | Tooling | P2 | M | — |
| 11.3 | A `.gdlintrc`, now there are two devs | Tooling | P2 | XS | — |
| 3.3 | An iOS haptics plugin | Feel | P3 | XL | 3.2 answering "texture" |
| 4.2 | Character cards — drawings or renders | Art | P3 | M | a medium call |
| 5.6 | JSON the menu carries and nothing reads | Menu | P3 | M | — |
| 5.7 | Menu art the JSON describes and nothing draws | Art | P3 | M | — |
| 6.2 | Do the maps get names? | Modes | P3 | XS | Ryder |
| 8.4 | No interest management | Multiplayer | P3 | M | a bigger roster |
| 9.3 | Per-kit weapon sounds, positional audio | Audio | P3 | S | — |
| 9.4 | More music | Audio | P3 | L | — |
| 11.1 | Nothing forces `Tools/godot.sh` | Tooling | P3 | XS | — |

---

# 1. Phone fit — the P0 block

Four items, and together they are the whole reason the game is not yet good in
the hand. Everything else on this list is worth less than these until a build on
the phone fills the screen at a readable size. **All device testing is Ryder's** —
the phone is his and `devicectl` installs from his machine, so anything Jackson
changes in the menu is a loop through him, not a handoff.

- [ ] **1.1 — The match does not reach the edges of the screen.** `P0` `S`
      `project.godot` is `stretch/mode="canvas_items"`, `aspect="expand"` at
      1280x720, which should fill — so this is either the safe-area inset or the
      HUD's own anchors. **Shoot it on the device before changing anything**; a
      desktop window cannot reproduce it.

- [ ] **1.2 — The menu does not reach the edges either**, and it is a different
      bug from 1.1. `P0` `S`
      `MenuShell._fit_stage` deliberately *widens* the 1920x1080 stage past 1920
      on anything taller than 16:9, so a phone is supposed to gain stage width
      rather than bars. Either that path is not running on device, or honouring
      the safe area is eating the gain back.

- [ ] **1.3 — Buttons and text are too small.** `P0` `M`
      On the menu this is a type scale authored against a 1920 stage and read at
      arm's length on a 6-inch screen; in the match it is the HUD. **Measure the
      real device pixels per point first** — the stage scale makes guessing
      useless, and the type scale has a deliberate hole in it (utility at 17-22,
      display at 44+) that a blind bump would fill in and flatten. See CLAUDE.md's
      **Menu** section before picking numbers.

- [ ] **1.4 — Developer Mode is off on the handset.** `P0` `XS` `[blocked: Ryder]`
      The export runs end to end and leaves a signed `.ipa`, but `devicectl`
      stops with `Developer Mode is disabled` until Settings → Privacy &
      Security → Developer Mode is switched on and the phone restarted. It
      cannot be done from here, and it gates every other P0 on this list, since
      all three need shooting on the device. `devicectl` also needs
      `DEVELOPER_DIR` set, exactly like the export.

---

# 2. The one scale decision

- [ ] **2.1 — Movement speed, camera framing and model scale are a single
      decision. Do not tune one alone.** `P1` `M`
      Three separate complaints that are one ratio: how big a fighter is, how
      much map is on screen, and how far a fighter crosses per second. The
      numbers are all measured already, so this is a taste call and a retune, not
      an investigation.
      - **The camera is 105.5 m out at 60° behind a 7° vertical FOV** = 22.9 x
        12.9 m at 16:9, or 55.8 px/m on a 1280 frame. Henry renders about
        **65 x 85 px, 5% of screen width**, against roughly 8-10% for a Brawl
        Stars brawler. The complaint is real.
      - **Zooming in is blocked by the range cap.** The vertical half-span is
        6.45 m against a weapon range cap of 5.5 tiles = 11 m, so a target at max
        range up or down the screen is already 4.5 m off-camera. Any zoom makes
        you shoot at what you cannot see — a balance change wearing a camera
        change's clothes. **The camera on its own has nothing left to give.**
      - **The lever is `Kits.MODEL_SCALE` (1.44), or the range cap itself.**
      - **And the models do not match their capsules.** `tools/size_probe.gd`
        measures each rig from its *bone* extents (a skinned mesh's own AABB is
        authored in bind space and comes back at ~0.02 m, i.e. meaningless).
        Against a capsule 1.30 m wide and 1.60 m tall:

            tony    w 0.82  d 0.41  h 2.34      leon    w 0.52  d 0.32  h 2.39
            henry   w 0.50  d 0.31  h 2.29      anders  w 0.46  d 0.31  h 2.38
            sanjit  w 0.64  d 0.41  h 2.38      hammy   w 0.46  d 0.29  h 2.40
            kovacs  w 0.61  d 0.30  h 2.40

        Every model is roughly **half** the capsule's width and **1.5x** its
        height. Widening the models puts them over 3 m tall; narrowing the
        capsules makes everyone half as easy to hit. That is a balance change,
        which is why it belongs in this decision and not beside it.

---

# 3. Controls and feel

- [ ] **3.1 — One cannot decide *not* to attack after aiming.** `P1` `S`
      Drag the aim stick out, change your mind, drag it back to the centre — the
      shot still fires on release. It should not. The stick already knows: `value`
      is what crosses `TAP_THRESHOLD` for the detent in `main.gd:_update_aim_detent`,
      so a release below that threshold *after* the stick has been out is
      distinguishable from a tap that never left home. Careful with the
      interaction: a release at zero deflection that was never dragged is a
      **tap**, and a tap must keep firing at the nearest target.

- [ ] **3.2 — Nothing in the haptics layer has been judged on an actual
      phone.** `P1` `XS` `[blocked: a device install]`
      The score vocabulary is written, measured and instrumented, and the
      amplitudes are reasoned from a measured damage curve — but they have not
      been **felt**, and that is the only test that settles them. This also
      decides 3.3: if the verdict is "the rhythm is right, the texture is wrong",
      the native plugin is the answer; if it is still the rhythm, the plugin will
      not fix it. `NS3_HAPTIC_DEMO=<name>` loops one entry for tuning on the
      handset itself.

- [ ] **3.3 — An iOS haptics plugin, for transient events and sharpness.**
      `P3` `XL` `[blocked: 3.2]`
      The ceiling on how good the haptics can feel, and the one thing the
      GDScript rewrite could not reach. `AppleEmbedded::vibrate_haptic_engine`
      (`drivers/apple_embedded/apple_embedded.mm:73-132`, identical on 4.6 and
      4.7) builds a pattern holding a single `CHHapticEventTypeHapticContinuous`
      with only `HapticIntensity` set — never `Transient`, never `HapticSharpness`.
      Every tap the game can currently make is the same soft continuous buzz at a
      different length and strength.
      - **What it buys:** a real transient (what a UI press and a landed shot
        actually want); sharpness, so a body hit is a dull thud and a wall break a
        sharp crack rather than the two differing only in volume;
        `CHHapticAdvancedPatternPlayer` curves instead of stepped segments; and
        sub-millisecond timing instead of the ~16 ms frame quantisation the queue
        in `haptics.gd` is stuck with.
      - **Shape:** a `.gdip` plus an arm64 `.a` in `godot/ios/plugins/` — the
        exporter picks it up with no preset change. Expose transient/continuous,
        intensity and sharpness, ideally an AHAP loader, then make `Haptics._emit`
        prefer it and keep `Input.vibrate_handheld` as the fallback. **The score
        vocabulary gets richer; it is not thrown away.**
      - **Why it is deferred:** first native code in the project, a build against
        Godot headers, and something new between `Tools/export_ios.sh` and the
        stock templates that currently run end to end. It cannot be tested in the
        simulator (godotengine/godot#118161), so every iteration is a device
        install.

- [ ] **3.4 — Hammy's three heat pips should merge into one bar that drains,
      like Ayaan's Downhill clock.** `P2` `S`
      Ryder's call, and the file already argues for it. Today
      `fighter_bars.gd:157-165` draws **three discrete pips** below the ammo row,
      lit when `i < f.heat_hits` — and then, once On Fire, **all three light
      solid and stay solid** for the whole four seconds. So the row says two
      different things with the same picture: while building it is a *count* out
      of three, and while burning it is a *duration* with no indication of how
      much is left. The second is the half that matters, because On Fire changes
      how the next shot should be played and you cannot see it running out.
      - **The precedent is Ayaan's** (`fighter_bars.gd:70-76`, `RIDE_H` /
        `RIDE_GAP` / `RIDE_COLOR`, driven by `Fighter.ride_fraction()` at
        `fighter.gd:167`): one continuous bar draining left to right. Everything
        needed for Hammy's is already on the fighter — `on_fire_until`
        (`fighter.gd:105`, a flat 4.0 s window set in `fighter.gd:647`) and
        `heat_hits` — so this is a `fire_fraction()` mirroring `ride_fraction()`
        plus one draw call replacing a loop.
      - **It should move ABOVE the health bar too**, and the reason is written in
        the file already: Ayaan's clock "sits ABOVE the health bar rather than
        joining the stack below it, because it is a temporary state and not
        another permanent stat." Hammy's On Fire is exactly a temporary state,
        and it is currently filed with the permanent ones. Moving it also drops
        the `below += HEAT_GAP + HEAT_H` correction in the upward stack
        (`:108-109`), which exists only because the pips sit under the ammo row.
      - **Keep the build-up legible.** Two thirds of a bar is a weaker "2 of 3"
        than two lit pips, so the merged bar probably wants segment ticks while
        charging and a clean drain once lit — one bar, two modes, rather than
        one bar that quietly means different things.
      - **Check the wifi case before shipping it.** `ride_fraction()` is
        deliberately empty on a client, because only the host simulates a ride
        and the snapshot carries positions rather than ride state. The snapshot
        does pack two burn clocks — confirm whether `on_fire_until` is one of
        them, or Hammy's new bar is blank in wifi play for the same reason.

---

# 4. Characters and art

- [ ] **4.1 — Nova and Ayaan still render as capsules.** `P1` `L`
      `[blocked: a Meshy pass]`
      No `model` key in `kits.gd`, so they fall back to `_setup_capsule` in the
      match **and** on the menu stage. **Nova is the sole starter**, so a capsule
      is the first thing a new player ever sees, on the first screen they see it
      on. Anders and Hammy are wired now (`kits.gd:481`, `:559`).
      - The two need a Meshy export through `python3 Tools/fix_meshy_glb.py`,
        then `Assets/3D/` → `godot/assets/` → `kits.gd` `model`/`clips`.
      - **This is the same blocker as their portraits.** `tools/render_portraits.gd`
        re-shot all seven modelled kits so the roster reads as one set for the
        first time; these two are the whole remaining hole and the tool cannot
        help, because there is no GLB to shoot.
      - They are the only items in this file that **cannot** be produced by one
        of the three pipelines in **Reference**.

- [ ] **4.2 — The character cards are a different medium from the portraits, and
      the medium has to be chosen.** `P3` `M` `[blocked: a medium call]`
      The five that exist (`assets/menu/cards/*.webp`) are **stylised 2D
      illustrations** — cel shading, black outlines — not GLB renders. Rendering
      Anders and Hammy off their models would drop two 3D renders into a set of
      five drawings. Worth knowing before spending anything: **`MenuData.card_art`
      has zero callers**, so no screen shows a card either way. Either cards stay
      an illustrated set (then they need an illustrator, not the renderer) or they
      become renders (then re-shoot all seven with `NS3_PORTRAIT_KIND=card` and
      the set is consistent again).

---

# 5. Menu and progression

- [ ] **5.1 — The menu's second look.** `P2` `M`
      *Rewritten 6 Sep 2026 — the old entry described the pre-overhaul menu and
      following it would have undone the overhaul.* It asked for thick bevels,
      hard drop shadows and a lip on every pressable, against an auditorium
      backdrop. That backdrop is deleted, the screens animate, and the current
      design's whole thesis is the opposite: **radius zero everywhere, hairline
      rules only, no bevel or shadow or gradient**, because adding one means
      adding it everywhere and then it is the old system again. Read CLAUDE.md's
      **Menu** section before touching a token.
      What is actually worth looking at now, on the design's own terms:
      - **Does the type scale's deliberate hole survive on a phone**, or does
        1.3's fix quietly fill it in? They are the same pass.
      - **Gold is the only colour with a job** (earned / active / yours). Audit
        that it has not leaked onto anything decorative.
      - **`MenuUI.plate_colors` still hands every surface the same three-stop
        vertical gradient**, which is a leftover from the flat-plate system the
        overhaul replaced. Either it earns its place or it goes.
      - The stage fighter is the only moving thing on Home. Whether the flank
        columns want any motion at all is a real question, not an obvious yes.

- [ ] **5.2 — The roster should be tiles, not rows.** `P2` `S`
      `roster_screen.gd` is a plain picker of rows. Ryder wants character tiles.
      Cheap now that Home is the detail screen and the roster only has to select
      and return.

- [ ] **5.3 — Redesign the menu around Jackson's idea.** `P2` `?`
      `[blocked: the idea, written down here]`
      Nothing can be estimated or built until the idea is in this file. The
      current programme-page design and the reasoning behind every token in it is
      in CLAUDE.md's **Menu** section — read that first, so the redesign is a
      decision and not a drift.

- [ ] **5.4 — A real progression system.** `P2` `L`
      `[blocked: deciding what a level changes]`
      `SaveGame` already banks trophies, coins, gems, Power Points and pass
      tokens per match, and Trophy Road and the pass spend them. Power levels,
      Star Powers and gadgets are the hole: they are named in `brawlers.json` and
      **do nothing**. Decide what a level actually changes before wiring
      anything — a stat bump touches `kits.gd`, which `CHARACTER_BUILDING.md`
      derives damage from, so it is a balance change too.

- [ ] **5.5 — Leon, Anders, Hammy and Ayaan have no named unlock.** `P2` `XS`
      `[blocked: a content call]`
      Trophy Road unlocks Sanjit, Tony, Kovacs and Henry by name, so those four
      are reachable only through a random Dawg Treat. Decide whether they get
      road milestones, pass tiers, or stay Treat-only. Related and left alone
      deliberately: Leon's `brawlers.json` entry is still `"rarity": "starting"`
      and `"unlocked": true` from the web build, so the roster labels him a
      Starting Brawler alongside Nova, who is the only id in `startingBrawlers`.
      Changing it moves him between rarity buckets, which the rarity-weighted
      `brawler_drop` reads — a content decision, not a typo fix.

- [ ] **5.6 — JSON the menu carries that nothing reads.** `P3` `M`
      Either wire it or delete it; carrying it costs export bytes and reads as
      a feature that exists.
      - **The `loadout` dict has zero readers.** `MenuData._merge` still emits
        gadget/gear/Star Power/Hypercharge, but `BrawlerDetailScreen._build_loadout`
        went with the roster's detail card when Home became the detail view. Six
        kits name a full set in `brawlers.json`; none of it reaches a screen. Tied
        to 5.4 — a loadout that displays and does nothing is worse than no
        loadout.
      - `game.json`'s **`quests`, `leaderboard`, `gameLog` and `upcoming`** are
        read by nothing.
      - **`MenuData.card_art` has zero callers** (see 4.2).
      - `passRewards` was deliberately left at the 15 tiers the pass screen
        parses rather than the web build's 40. That one is fine.

- [ ] **5.7 — Menu art the JSON describes and nothing draws.** `P3` `M`
      All of it is pipeline 2 or 3 in **Reference** — no illustrator needed.
      The two skins that *have* art now draw it (`shop_screen.gd:_skin_card` →
      `MenuData.skin_art`, resolved from an explicit `art` key on s1/s2). Still
      undrawn: the three skins with no art; the gadget/gear/Star Power/Hypercharge
      **badges** (names display, art does not); **pins** (`brawlers.json` carries
      a count and there is no pin art at all); player avatars for the profile
      popup; map thumbnails; the club badge.

---

# 6. Modes and systems

- [ ] **6.1 — Activate a third game mode.** `P2` `L` `[blocked: which mode]`
      Two are live — Showdown and Nobles Cup — and every other card on the modes
      screen is a locked dummy. `Session.mode` plus the branch at the top of
      `main.gd:start_match` is the whole hook, and **`cup_mode.gd` is the worked
      example of what a mode file looks like**: everything mode-specific in one
      file, called at four points (`build_match`, `tick`, `on_death`, `frozen`),
      with `cup == null` as the guard on every branch. Copy that shape.

- [ ] **6.2 — Do the maps get names?** `P3` `XS` `[blocked: Ryder]`
      Open question. The maps have no names in the game at all — `game.json`'s
      `gameLog` invents "Castle Courtyard" and friends for its fake history and
      nothing reads them. If they get names, the loading screen and the versus
      screen are where they belong.

---

# 7. Balance

- [ ] **7.1 — The balance pass.** `P2` `M`
      Run `NS3_SIM=<n>` headless across the nine kits and tune against
      `CHARACTER_BUILDING.md`; damage is **derived** from the tier tables, never
      picked by taste. Nova is a placeholder — do not tune her.
      - **Run 60+ matches a side, not 20.** This is measured, not a rule of
        thumb: the same A/B said damage was down 11% at 20 matches a side and
        flat inside 1% at 60. Twenty spawns per kit is noise.
      - **The bot terrain work moved the baseline**, so this pass measures
        against the new one. Win% spread across the roster already tightened from
        sd 6.1 to 4.6 as a side effect, and win% tracks attack rate now, because
        the cost of cover and flanking is time spent walking instead of shooting.
      - Sanity check the `hits/atk` column against each kit's projectile count.
        Anything near zero is a delivery bug, not a balance finding.

- [ ] **7.2 — Sanjit's range feels too long.** `P2` `S`
      `kits.gd:305` — the melee reaches 1.4 tiles (2.8 m) and the boomerang Super
      5.0. **Measure which one the complaint is about** with `NS3_KIT=sanjit`
      before touching the tier tables: `CHARACTER_BUILDING.md` derives damage from
      range, so a range change is a damage change.

---

# 8. Multiplayer

- [ ] **8.1 — A client's own death is silent, and its HUD lies about it.**
      `P1` `S`
      Found with `NS3_NET_KILL=6` + `NS3_HAPTIC_LOG=1`: the results card comes up
      correctly (DEFEATED, #10 of 10, the real stat table) while the HUD behind it
      still reads `HP 5000/5000`, and **not one haptic fires**.
      - The health line explains both. A client is put down by the
        `_net_eliminate` **event**, not by its health being walked to zero, so
        `_update_status`'s frame-to-frame damage watch — the one hook that is
        supposed to cover both single-player and net — never sees a decrease.
      - `death`, `elimination`, `cube`, `super_ready`, `super_fire` and
        `count_go` are all hooked into host-side paths a client never runs, so
        **the whole haptic layer is effectively off in wifi play.**
      - Fix: zero the local health on a net elimination, and fire the taps from
        the client's own event handlers.

- [ ] **8.2 — Clients do not predict their own attacks.** `P2` `M`
      The next thing anyone will feel after the prediction work. A client's shot
      goes up as `_net_fire` and appears only when `_net_attack` echoes back, so
      pressing fire on a 160 ms link is a 160 ms wait for the muzzle flash.
      Doing it means the client predicting its own ammo and cooldown well enough
      not to draw a shot the host refuses — the snapshot already carries both,
      one interpolation delay late.

- [ ] **8.4 — No interest management.** `P3` `M` `[deferred by design]`
      Every client is sent every fighter every snapshot, including the ones
      across the map its camera cannot show. At ten fighters that is 150 bytes
      and not worth the complexity. **This is the next lever if a mode ever wants
      a bigger roster**, and not before.

---

# 9. Audio

- [ ] **9.1 — Voicelines.** `P2` `XL` `[blocked: nine real people]`
      Nine fighters x spawn / attack / Super / defeat / victory, recorded by the
      people the characters are based on. **This cannot be generated and has the
      longest lead time of anything in this file — start booking it before the
      code hook exists.** Its priority here is P2 only because nothing else waits
      on it; its *scheduling* is the most urgent thing on the list.

- [ ] **9.2 — The gas ring makes no sound, and nothing announces a step.**
      `P2` `S`
      `MenuAudio` already has `gas_tick` for your own burn. What is missing is
      the ring itself: a low rolling swell timed to the ease (`SHRINK_EASE`, 3 s)
      so the wall moving is something you hear before you are standing in it. A
      haptic for "the ring is moving" belongs with it — `Haptics` is a tier and a
      score away, and this is exactly the MATCH-tier event the table has room for.

- [ ] **9.3 — Nothing distinguishes one kit's shotgun from another's, and there
      is no positional stereo.** `P3` `S`
      Sounds are keyed off `weapon.style` in `_attack_sound`, which is what makes
      a new character inherit one for free — so per-kit voices are an override
      layer on top, not a rewrite. Everything is mono, attenuated by distance
      only (full inside 6 m, gone by 30 m against a camera showing ~23 m).
      Add a name to `tools/sfx_probe.gd`'s list whenever one is added to the
      table: **`MenuAudio._render` falls through to "click" for an unknown name**,
      so a typo plays a menu click mid-firefight instead of failing.

- [ ] **9.4 — More music.** `P3` `L`
      Two tracks ship (`lobby_vibes`, `clash_carnival`). Wants at least a
      results/victory sting, and a second battle track so Cup and Showdown do not
      sound identical.

---

# 10. Ship

- [ ] **10.1 — The app icon is a placeholder.** `P1` `S`
      `godot/icon.png` is a flat gold star on navy at 1024x1024, and **the
      generator that draws it already exists** — `godot/tools/make_icon.gd`, run
      with `Godot --path godot --headless --script res://tools/make_icon.gd`. So
      this is not "build a pipeline", it is **design a better icon and edit that
      script**, which makes it the cheapest P1 on the list. Needed before a build
      on a phone looks like a real game. The launch art beside it is done: the
      iOS storyboard inherits the boot splash.

---

# 11. Tooling

- [ ] **11.1 — Nothing forces the use of `Tools/godot.sh`.** `P3` `XS`
      The lock wrapper only helps a caller who reaches for it, and every `NS3_*`
      line in this file and in CLAUDE.md still shows the bare binary. Either
      sweep those to the wrapper or add a hook that refuses the raw path.
      Remember the allowlist limitation: prefix rules match from the start of the
      command, so `NS3_KIT=nova Tools/godot.sh …` does not match — the env var
      comes first.

- [ ] **11.2 — No GDScript language server, and Jackson makes that matter.**
      `P2` `M`
      `.gd` files get no go-to-definition, no find-references, no diagnostics.
      Godot ships a language server but only serves it while the editor is open,
      so this means keeping the editor running alongside — which is the workflow
      the `NS3_*` hooks exist to avoid.
      - **Raised from P3.** The old note called it "marginal at 13k lines where
        grep works", which was true of the person who *wrote* those 13k lines and
        is not true of a second developer reading them cold. Go-to-definition
        across `kits.gd` → `fighter.gd` → `main.gd` is most of what onboarding
        actually is, and Jackson's Phase 0 is the moment it pays.
      - Pairs with the `.gdlintrc` in **Reference** — same reassessment, same
        cause.

- [ ] **11.3 — A `.gdlintrc`, now that two people write GDScript.** `P2` `XS`
      `gdlint` was measured and rejected at 145 findings for 2 real ones, which
      is the right call for one author with one style. It is the wrong call for
      two, and the boundary is sharp — Jackson owns `scripts/menu/` outright, so
      style drift there is invisible to Ryder until a file is unreadable.
      - The whole job is a `.gdlintrc` disabling exactly the three noisy rules:
        `class-definitions-order` (81 findings), `mixed-tabs-and-spaces` (26,
        every one intentional continuation alignment) and `max-line-length` (26,
        at a default of 100). What is left is the real findings.
      - **`gdformat` stays rejected** — it rewrites the deliberate paren
        alignment in `kits.gd`'s tier tables and the shader strings in
        `arena.gd`, both of which are readable *because* of that alignment.
      - Still configuration rather than a package, which was the original
        conclusion and survives. See **Reference** for the full reassessment.

---

# Reference

Not tasks. Kept here because both get re-litigated otherwise.

## Generating assets ourselves

Most of what is still missing does **not** need Meshy or hand-drawn art. Three
pipelines already exist in this repo and between them cover nearly everything
above.

**1. Synthesized audio — zero files.** `scripts/menu/menu_audio.gd` (`MenuAudio`)
is a complete runtime synth: sine/triangle/square/saw/noise oscillators,
envelopes and a 16-voice pool rendered into `AudioStreamWAV` buffers on first
play. That is why the game ships with no audio files at all — 28 combat sounds
included. A new sound is a new entry in that table, not a recording. Verify it
with `Godot --path godot --headless --script res://tools/sfx_probe.gd`, which
flags any name with no entry of its own plus anything silent or clipping.

**2. Headless render — portraits, cards, map thumbnails.**
`tools/render_portraits.gd` shoots portraits (512, transparent) and full-body
cards (768) straight off the GLBs on `menu_stage.gd`'s own rig — same 22° lens,
same warm key / cool fill / gold rim — so a portrait and the live stage fighter
are lit identically and the art regenerates for free whenever a model changes.
Run it **without** `--headless`; the dummy driver renders nothing and every PNG
comes out empty:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path godot \
    --script res://tools/render_portraits.gd
# NS3_PORTRAIT_KITS=tony,henry  NS3_PORTRAIT_KIND=portrait|card|both
# NS3_PORTRAIT_OUT=<dir>        (default: the menu art dirs)
```

Framing is sized to the **head**, not to a fixed number of metres: the rigs are
not proportioned alike — Tony's head is 41% of his body height against Henry's
25% — so the span that framed Henry's head and shoulders cut Tony off at the
chin. It reads the head off the skeleton (`Head` at the chin, `head_end` at the
crown on every Meshy rig here) and hangs the frame off the crown. The same rig
still needs pointing at the arena camera for map thumbnails.
`tools/render_map.gd` is the arena half — an overview of the whole map, or the
real match lens pointed anywhere, without playing seven seconds of pre-match to
reach a screenshot.

**3. Script-drawn 2D — icons and badges.** v1 did exactly this: every 2D sprite
in the SpriteKit game came out of `Tools/generate_sprites.swift`. Pins,
gadget/gear/Star Power/Hypercharge badges, currency and mode icons, the club
badge and the app icon are all flat vector shapes, and are better generated
deterministically than drawn once and lost.

**What genuinely cannot be self-generated:** the Nova and Ayaan character models
(4.1), skin variants of existing characters, real music, and the voicelines
(9.1) — which need the actual people the characters are based on and therefore
have the longest lead time of anything in this file.

## Godot plugins: the answer was none, and a second developer partly changes that

Recorded so it is not re-litigated from scratch — but **the measurement behind
"none" was taken on a one-person project, and Jackson joining expires part of
it.** What changed and what did not:

**The original finding, unchanged.** `gdtoolkit` (`gdlint` / `gdformat`) was
measured against all 44 files: 145 findings, of which **two** were real
(`ball.gd:135` and `menu_popups.gd:54`, both unused arguments, both now fixed).
The rest were 81 `class-definitions-order`, 26 `mixed-tabs-and-spaces` that are
every one of them intentional continuation alignment, and 26 `max-line-length`
at its default 100.

**`gdformat` is still a no.** It would rewrite the deliberate paren alignment in
`kits.gd`'s tier tables and the shader strings in `arena.gd` — both of which are
readable *because* of that alignment. A formatter that has to be fought is worse
than no formatter.

**`gdlint` is now worth a second look**, and it is the one thing on this page
whose answer moved. A 143-to-2 noise ratio is a reason to skip a linter when one
person writes everything in one style; with two developers it becomes the thing
that stops two styles diverging silently across a boundary — and the boundary is
sharp here, since Jackson owns `scripts/menu/` outright. The move is a
`.gdlintrc` disabling exactly the three noisy rules
(`class-definitions-order`, `mixed-tabs-and-spaces`, `max-line-length`), which
leaves the real findings and nothing else. That is still **configuration rather
than a package**, which was the original conclusion and survives intact.

**A language server matters much more than it did** — see `11.2`. Its "marginal
at 13k lines where grep works" was true of someone who wrote all 13k. It is not
true of a second developer reading them for the first time, and go-to-definition
across `kits.gd` → `fighter.gd` → `main.gd` is most of what onboarding is.

**Editor addons are still a no, for a structural reason that has not changed:**
the `.tscn` files are empty shells and everything is built in code, so an addon
has nothing to attach to. The Godot MCP servers bridge a *live editor*, which is
the workflow the `NS3_*` env hooks exist to avoid.

**The one plugin actually on the roadmap is native, not an addon** — the iOS
haptics plugin (`3.3`), a `.gdip` plus an arm64 `.a`. Different question, already
tracked, still deferred behind `3.2`.

---

# Struck this pass (6 Sep 2026)

Four entries were removed rather than carried forward, because acting on them
would have been wrong. Recorded here so they are not re-added from memory.

- **"The Super is hard to aim."** Its own proposed fix shipped — the Super *is*
  a stick you drag off now, `super_button.gd` is deleted and folded into
  `TouchStick`. Written up in `done.md`.
- **"Shop and Trophy Road are placeholder screens."** Both are real:
  `shop_screen.gd` has `_affordable_deals` and the Dawg Treat loop over
  `TREAT_TIERS`, and `season_screen.gd` claims through `SaveGame.is_claimed`
  across all six reward kinds. The settings half of that entry had already been
  struck for the same reason.
- **"The menu does not look good enough yet."** Rewritten as 5.1 — it described
  the pre-overhaul menu, and three of its four bullets asked for exactly what
  the overhaul deliberately removed.
- **"Drop Brawl Stars SFX in as placeholders first."** Its premise was "the match
  is silent *today*". It is not — 28 sounds are synthesized through `MenuAudio`,
  which was the ship path this was a shortcut to. Standing in Supercell's audio
  now would be a step backwards and cannot ship.

One half-typed line (`- []  **The`) was dropped from **Arena & visuals**. It was
uncommitted, carried no text, and git has no earlier version of it.

## Automatic joining: Bonjour, MultipeerConnectivity, GameKit

The join code plus the unicast sweep is as far as pure GDScript reaches. All
three of the "it just finds your friends" options need a **native iOS plugin**,
because Godot binds none of them — a static lib plus a `.gdip`, built in Xcode
and dropped in `ios/plugins/`. Ranked by what they cost against what they buy:

- **Bonjour / mDNS — the one worth doing.** It replaces only the DISCOVERY step,
  so ENet stays and every line of snapshot, prediction and RPC code is
  untouched; it fills the same `Net.games` dictionary `room_screen.gd` already
  reads. Apple **exempts Bonjour from the multicast entitlement** as long as you
  go through the system API (`NWBrowser`/`NWListener`, or `NSNetService`) and
  declare `NSBonjourServices` beside the `NSLocalNetworkUsageDescription` the
  preset already has. It also crosses subnets that the /24 sweep cannot, which
  is the school-network case. **Do not try this in GDScript over
  `PacketPeerUDP.join_multicast_group`**: the exemption is granted to the API,
  not to port 5353, so a hand-rolled mDNS on a raw socket needs the entitlement
  after all and will simply find nothing on a phone.
- **MultipeerConnectivity — the most magical, and the only one that beats client
  isolation.** `MCNearbyServiceBrowser`/`Advertiser` discover and connect over
  wifi, Bluetooth and peer-to-peer AWDL, so two phones find each other with no
  router involved at all — which is the one thing that would work on school wifi
  that blocks device-to-device traffic. But it is a TRANSPORT, not a directory:
  taking it would mean a `MultiplayerPeerExtension` so the existing RPCs keep
  working, and it is iOS-only, so the desktop build (where all the testing
  happens) would need ENet kept alongside it.
- **GameKit / `GKMatch` — probably not.** Real matchmaking with no addresses at
  all, and over the internet rather than the LAN. But it wants a Game Center
  capability and an App Store Connect record with a matching bundle id, and this
  game is side-loaded and deliberately never shipped to the App Store. It is
  also a transport like Multipeer, so it needs the same `MultiplayerPeer` work,
  and it is iOS/macOS-only.

Verify first, before writing any plugin: whether the unicast sweep actually
returns hosts on a real iPhone. If it does, discovery is already solved for home
wifi and Bonjour is only buying the cross-subnet case.
