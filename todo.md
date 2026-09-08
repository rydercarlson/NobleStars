# Noble Stars — TODO

Open work on the Godot 3D game (`godot/`). **Finished work moved to
[`done.md`](done.md)** — 73 entries recording what was measured, what was tried
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
| 1.3 | Menu text is half the readable size | Phone fit | P0 | M | a type-scale redesign |
| 1.5 | Loading title sits under the Dynamic Island | Phone fit | P1 | S | what the splash handoff should do |
| 2.1 | Speed / camera / model scale — one decision | Feel | P1 | M | a taste call |
| 3.2 | Judge the haptics on a real phone | Feel | P1 | XS | — |
| 4.1 | Nova is still a capsule | Characters | P1 | M | Meshy pass |
| 5.1 | The menu's second look | Menu | P2 | M | — |
| 5.3 | Jackson's menu idea — layout built, previews and a phone look left | Menu | P2 | M | — |
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

**Three of the four are done** (6 Sep 2026) and are in `done.md`: 1.1 the match
reaching the edges, 1.2 the menu reaching them, and 1.4 Developer Mode, which
turned out to be on already. What made them finishable in one pass is that the
device round trip **stopped needing Ryder's eyes** — `Tools/device_shot.sh`
drives the handset with the `NS3_*` hooks and brings the PNG back, so every
claim below is now measured on an iPhone 15 rather than reasoned about from a
desktop window. That changes the note this section used to carry: device
*testing* is still Ryder's hardware, but a screenshot is no longer a handoff.

What is left is the half that is a design decision rather than a bug.

- [ ] **1.3 — Buttons and text are too small.** `P0` `M`
      *Measured on the device 6 Sep 2026; the numbers below replace the "measure
      it first" instruction this entry used to lead with.* On an iPhone 15 in
      landscape (2556x1179 at 3x, so 852x393 pt):

      | | stage/viewport px → pt | utility tier | display tier |
      |---|---|---|---|
      | **Menu** (1080-tall stage) | x0.364 | 17-22 → **6.2-8.0 pt** | 44 → 16.0 pt |
      | **Match** (720-tall viewport) | x0.546 | 22 → 12.0 pt | 72 → 39.3 pt |

      Apple's floor for body text is **11 pt**. So:
      - **The match HUD is fine now.** Its four labels were bumped with the 1.1
        layout fix (status 20→22, feed 18→24, players 26→30) and all three clear
        11 pt. Nothing further is wanted here.
      - **The menu's utility tier moved to 26–30 stage px on 6 Sep** with the
        layout pass (done.md, Menu) — 9.5–10.9 pt, at the floor rather than
        half of it. Still to do: shoot it on the handset and judge whether the
        display tier (which moved with it where the two met) still reads as a
        separate tier there.
      - **Counted 7 Sep, every screen: 39 of 39 utility labels are under 11 pt.**
        Not most of them — all of them, because the floor needs **30.2 stage px**
        and the tier's own ceiling is 30. So "at the floor" was generous; the
        top of the tier misses by 1% and the bottom by a third. Screens that now
        hold the system's own 26 floor: **roster, shop, modes** (conformed 7 Sep,
        and it cost nothing but one measurement — seven rarity chips could not
        hold "LEGENDARY" at 26 until the copy beside them gave up 80 px).
        Screens that do not: **season** (10 labels) and **home** (7), plus five
        in the shell and popups.
      - **Season is the case that proves this is a redesign, not a multiply.**
        Its page does not scroll: header + Trophy Road + Nobles Pass + gaps have
        to total 816 stage px, and every one of those heights was solved against
        Anton's 1.64x line box and Barlow's 1.2x. A pass cell's name at 26
        instead of 20 adds ~10 px, twice per tier column, and there is nothing
        left to take it from — the last pass already cut the block padding and
        the head type to make it fit at all. Getting that grid to 30 px means
        **fewer tiers visible at once**, which is a design decision about what
        the Pass is for, not a number to bump.
      - *Kept for the record — the analysis this was done against:* the menu's
        utility tier was the whole remaining problem, at roughly
        *half* the readable floor. Clearing 11 pt means about 30 stage px, which
        lands on the bottom of the display tier — so this cannot be done as a
        blind multiply. **It is the deliberate hole in the type scale that has to
        be redesigned, not the sizes.** That is a design call on Jackson's own
        system (CLAUDE.md's **Menu** section explains why the hole exists), and
        it is the one part of the P0 block that is not a bug fix.
      - Fixing 1.2 did *not* help enough to matter: filling the display moved the
        stage scale from 0.631 to 0.667, worth 5.7%.
      - Note it is only the **type**. Tap targets are fine — PLAY is 168x64 pt
        and the smallest nav link is over 44 pt tall.

- [ ] **1.5 — The loading screen's title sits under the Dynamic Island.**
      `P1` `S` *(found 6 Sep 2026, the same pass that fixed 1.1 and 1.2)*
      `loading_screen.gd:277` insets `strip` by 46 px on a 1280-authored
      viewport = 75 device px, inside the phone's **177 px** landscape safe
      inset — so "NOBLES CUP" and the progress bar are behind the island. It is
      the first screen a tester ever sees.
      **It was deliberately not fixed with 1.1 and 1.2**, because it is not the
      same mechanical change: `LoadingScreen.compose()` is shared with
      `tools/make_boot_splash.gd`, which renders it at 1280x720 as the engine's
      boot splash, and CLAUDE.md records that the splash-to-live handoff being
      seamless is a tuned property. Insetting the live one moves it relative to
      the splash. Decide what the handoff should do first — the splash is
      already `scaleAspectFit`, so it is letterboxed to 2096 px of a 2556 px
      screen and the two do not line up edge to edge today either.

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

- [ ] **3.2 — Nothing in the haptics layer has been judged on an actual
      phone.** `P1` `XS`
      *No longer blocked on a device install: `Tools/device_install.sh` puts a
      build on the handset in one command and `Tools/device_shot.sh` drives it
      with any `NS3_*` hook, `NS3_HAPTIC_DEMO` included. What is still needed is
      a person holding it, because feeling it is the entire test.*
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

- [ ] **4.1 — Nova still renders as a capsule.** `P1` `M`
      `[blocked: a Meshy pass]`
      *Rewritten 6 Sep 2026: this entry covered Nova and Ayaan; Ayaan landed
      that day (Jackson's Meshy export through the pipeline, skis worn through
      his Super, a portrait off the model) and his half is in `done.md`.*
      No `model` key in `kits.gd`, so Nova falls back to `_setup_capsule` in the
      match **and** on the menu stage. **She is the sole starter**, so a
      capsule is the first thing a new player ever sees, on the first screen
      they see it on. Anders, Hammy and Ayaan are wired (`kits.gd` `anders()`,
      `hammy()`, `ayaan()`).
      - She needs a Meshy export through `python3 Tools/fix_meshy_glb.py`,
        then `Assets/3D/` → `godot/assets/` → `kits.gd` `model`/`clips`; give
        the Idle a stance with `--idle-from`/`--idle-aim` (CLAUDE.md, character
        model pipeline) rather than shipping the rest pose.
      - **This is the same blocker as her portrait.** `tools/render_portraits.gd`
        re-shot the modelled kits so the roster reads as one set; she is the
        whole remaining hole and the tool cannot help, because there is no GLB
        to shoot.
      - The only item in this file that **cannot** be produced by one of the
        three pipelines in **Reference**.

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
      - ~~`MenuUI.plate_colors` still hands every surface a three-stop
        gradient~~ — **answered 7 Sep: it goes.** It had already been flattened
        to three copies of one fill by the overhaul, and it had no caller.
        Removed along with `stat_row`/`stat_line`, `body_font_700`,
        `disabled_button`, `art_button` and `chip`, which had none either.
      - The stage fighter is the only moving thing on Home. Whether the flank
        columns want any motion at all is a real question, not an obvious yes.

- [ ] **5.3 — Redesign the menu around Jackson's idea.** `P2` `M`
      *The idea is written down (ROADMAP **D1**, 6 Sep 2026) and the layout is
      built: five zones, a shell-owned bottom nav with the active tab lit, the
      square back and menu buttons, compact currencies, the icon pack, no
      rules, utility type at 26–30 px.* What is still open:
      - Ability art: the medallions carry a glyph per weapon kind
        (`svg/style_*.svg`); an illustration per ability, as in the mockup, is
        eighteen drawings and a medium call like 4.2.
      - Per-fighter stage paintings: today one painting is lit in each kit's
        colour; a kit's `stage` key takes a real one whenever there is one.
      - The ability-preview buttons under the two cards on home (the previews
        themselves are content).
      - *Done 7-8 Sep: Season, the roster, Shop, Events and Settings were all
        relaid out, and the menu was split into a lobby, a fighter's page and a
        Trophy Road page on Jackson's notes (see done.md). Every pushed screen
        has its own layout rather than the overhaul's at a larger size.* What
        is left of this item is the phone look below and the ability art above.
      - Shoot it on the phone (`Tools/device_shot.sh`) — everything above was
        judged on the desktop stage at 1920x1080 and 2017 px of chrome width
        was not seen.

- [ ] **5.8 — Model and texture defects Jackson listed on 8 Sep.** `P2` `M`
      All of these need a Meshy re-export or a texture edit; none of them is a
      script change, which is why the 8 Sep notes pass left them.
      - **Tony**: idle arms and the tennis ball intersect his body; the UA logo
        on his back sits in the wrong place; the shirt reads "RMAT" where it
        should read "NBVT"; the racket strings are wrong.
      - **The UA logo has to come off entirely** — Tony and Leon both wear one.
        It is a real trademark on a shipped character.
      - **Hammy**: elbows bend backwards; the attack is a baseball pitcher's
        wind-up, too fast to read, and Jackson wants it redone rather than
        retimed.
      - Tied to `todo 4.3` and ROADMAP **D9** (who owns real attack clips).

- [ ] **5.9 — Fighter descriptions read like a second role tag.** `P2` `S`
      Jackson's 8 Sep note, and he is right about the cause: six of the nine
      describe the ATTACK — "Lobs explosive shells clean over walls", "The
      hardest single hit in the game off a wide paddle arc" — and on the
      fighter's page that copy now sits a few centimetres from an ATTACK card
      saying the same thing with the damage attached. So the description reads
      as a redundant label rather than as who they are.
      - What the page does today: prints the description as written and adds
        the two facts that WERE nowhere — rarity, and either "in your roster"
        or how to unlock them.
      - What is left is the copy itself: one or two sentences per fighter about
        who they are and how they are played, distinct from what their weapon
        does. That is Jackson's pen (and ROADMAP **D2** puts character design
        with Ryder), not a layout change, which is why the 8 Sep pass stopped
        at the layout.

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
      a feature that exists. *Half done 7 Sep — what is left is the two items
      that are waiting on someone else's decision, not on this cleanup.*
      - **The `loadout` dict has zero readers.** `MenuData._merge` still emits
        gadget/gear/Star Power/Hypercharge, but `BrawlerDetailScreen._build_loadout`
        went with the roster's detail card when Home became the detail view. Six
        kits name a full set in `brawlers.json`; none of it reaches a screen. Tied
        to 5.4 — a loadout that displays and does nothing is worse than no
        loadout.
      - ~~`game.json`'s `quests`, `leaderboard`, `gameLog` and `upcoming` are
        read by nothing~~ — **deleted 7 Sep**, along with `news`, `friends`,
        `club` and `inbox`, whose screens went in the overhaul. A third of the
        file, and with it `SaveGame.read_mail`, `club_chat` and `unread_mail()`,
        which had no callers left either.
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

*Empty. `10.1` (the app icon) is done and in [`done.md`](done.md).*

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

**VERIFIED 2026-09-06: the unicast sweep DOES work on a real iPhone**, and finds
a desktop host quickly once it has widened to the network's actual prefix. So
discovery is solved for home wifi and Bonjour drops a long way down this list —
it now buys only the case where the network is wider than the /22 the sweep
widens to, and MultipeerConnectivity buys that *and* client isolation. If any of
these gets built, build that one.
