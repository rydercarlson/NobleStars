# Noble Stars — done

Everything that was finished, moved out of `todo.md` so that file is only open
work. **This is not a changelog** — the entries are kept because most of them
record *why* something is the shape it is, what was measured, and what was tried
and rejected. Deleting one throws that away and invites the rejected version
back. CLAUDE.md carries the short form of the same facts; this is the long one.

Entries are verbatim as they were written, grouped by the section they were
filed under. Where the code has since moved on, a **superseded** note is added
under the entry rather than editing it — a stale entry with a correction on it
is more useful than a rewritten one, because the reasoning it records is what
was true at the time.

Newest work is roughly at the top of each section.

---

## The P1 sweep (6 Sep 2026) — controls, wifi feedback, and the icon

- [x] **3.1 — A drawn shot can be called off.** Drag the aim stick out, change
      your mind, drag it back to the centre, release: nothing fires. `TouchStick`
      keeps a `peak` — the furthest it went during THIS touch, reset by `begin`
      — because `value` alone cannot tell the two zero-deflection releases
      apart. Three gestures now end at `_release_fire`: out and released is the
      lane you drew, never left home is a tap that auto-aims, out and brought
      back is called off.
      - **This is not a hole in the "every tap fires" rule, and it took some
        care not to make it one.** That rule killed the Super's old `hold` case
        on the grounds that a button which declines to go off reads as broken
        rather than as restraint, and it still holds: a tap is a gesture you did
        not aim, and it fires. Drawing a lane and pulling it back is a *second*
        gesture, performed deliberately, and it already has feedback in both
        directions — the aim indicator vanishes as the stick crosses back under
        `TAP_THRESHOLD`, and `_update_aim_detent` fires `aim_off` at the same
        crossing. The shot not going off is the answer to something you did.
      - **It is checked ahead of `_kick_instead`** so a Nobles Cup carrier who
        draws a kick and thinks better of it keeps the ball instead of passing
        it anyway.
      - Same `TAP_THRESHOLD` the detent already watches, so there is one
        definition of where the stick stops meaning "tap" — a second constant
        here would let the tell and the behaviour drift apart.
      - **The gesture itself still wants a thumb.** The three branches are
        exhaustive over the input and the game runs, but nothing in the harness
        can draw a stick out and back. Pair it with `3.2` on the next device
        session — both want a hand rather than a screenshot.

- [x] **8.1 — A client's death is felt, and its HUD stops lying.** Found and
      fixed with the harness the entry names: `NS3_HOST=2 NS3_NET_KILL=6` on one
      instance, `NS3_JOIN=127.0.0.1 NS3_HAPTIC_LOG=1` on the other.
      - **The root cause is one sentence and it generalises**: a client learns
        some things as NUMBERS in the snapshot and others as EVENTS in an RPC,
        and every haptic was hooked to a host-side code path that is neither.
        So the fix has a rule: **anything a client learns as a number is
        watched frame to frame; anything it learns as an event is fired from the
        RPC handler.** That is why `hit` and `ammo_ready` already worked (health
        and ammo are numbers, watched in `_update_status`) and nothing else did.
      - **`_net_eliminate` now zeroes health before `die()`**, which
        `_net_cup_down` was already doing for Nobles Cup with the reason written
        beside it: `die()` does not touch health and `fighter_bars` skips only a
        fighter that `is_dead()`, so a full health bar otherwise hangs over the
        body for the whole pop-out. Showdown's half had simply never been done.
      - **The HUD lie is `status_label`**, which reads off `player` — about to
        be set to null — so left alone it freezes at whatever it last said,
        which is full health, printed behind a card that says DEFEATED. Blanked.
      - **`super_ready` moved OUT of `deal_damage` and into the frame watch.**
        The charge rides the snapshot, so watching the number covers the host
        and the client with one hook, exactly like the damage watch. The sound
        moved with it — a client had no `super_ready` sound either, which nobody
        had noticed because nobody had listened to a client.
      - **`count_go` was missing its sound as well as its tap.** The host fires
        both where it makes the COUNTDOWN → PLAYING transition itself, in the
        branch of `_run_playing` a client never reaches; a client makes the same
        transition in `_apply_snapshot_state`. The match was starting silently
        on every machine but the host's.
      - **`elimination` is matched on the killer's ROSTER INDEX, not their
        name.** `_net_eliminate` carries an extra `killer_idx` and `_eliminate`
        an optional one to feed it. A name comparison would have been one line
        and wrong twice over — every machine calls its own fighter "You", and
        two players may share a name. Same trap the Cup results board hit.
      - **There is deliberately no `defeat` tap on the client.** Losing a net
        Showdown is always losing by dying, so `death` fired a beat earlier and
        outlasts it — the rule `_end_match` already states. Nobles Cup, where
        you can lose on your feet, keeps its own in `end_cup_match`.
      - **Measured after, on the client:** `count_beep`, `count_go`, `hit` (990
        damage, 17% of max) and `death` all fire, against "not one haptic" in
        the entry. `super_fired` turned out to have worked all along — it lives
        in `perform_attack`, which a client runs off the `_net_attack` echo —
        so the entry overstated its list by one.
      - **Still missing, and left:** `landed`, the tap for damage you DEALT. A
        client is never told it hit anyone; there is no number and no event to
        hang it on, so it would need a new RPC. Not worth one.

- [x] **10.1 — A new app icon, in the game's own design language.** The old one
      was a gold star on a mid-navy VERTICAL GRADIENT with the lower half of the
      star darkened — a gradient, a shading pass and the pre-overhaul navy, three
      things the menu removed everywhere else. The new one takes `INK` and `GOLD`
      from `MenuUI` so there is one definition of each, and is flat, hard-edged
      and unshaded like everything else the game draws.
      - **Ink, not gold, for the field**, and the reason is continuity rather
        than taste: the boot splash, the launch storyboard and the menu are all
        ink, so tapping the icon and arriving at the lobby is one surface.
      - **The generator is supersampled now.** The old one tested a single point
        per pixel against the star polygon, so every edge was hard-aliased, and
        a jagged 1024 master is exactly what turns to mush at the sizes iOS
        downscales to. `SS x SS` samples per pixel, coverage lerped between the
        two colours, is the whole difference.
      - **First attempt was rejected**: inner radius 0.52 and a 0.20 rad tilt,
        reasoned as "chunky and off-axis reads as a mark rather than clip-art".
        Rendered, it read as a badly drawn star falling off a shelf — the fat
        inner radius destroys the silhouette and the tilt looks like a mistake
        rather than a choice. 0.42 and 0.07 rad keeps both the star and the
        life. **Render it and look at it at 120 px before believing any of these
        numbers**; the mark is legible there and that is the size that matters.
      - Nothing runs to the tile edge on purpose: iOS masks the icon into a
        superellipse, so a design that bleeds is cropped in a way you do not
        control and does not match across sizes.

---

## Phone fit (6 Sep 2026) — the P0 block, and the loop that made it cheap

- [x] **The device round trip no longer needs anyone's eyes.**
      `Tools/device_shot.sh` + `Tools/device_install.sh`. ROADMAP.md called the
      handset loop "the slowest feedback loop in the project" and put it on the
      critical path for three of the four P0s, on the reasoning that the phone
      is Ryder's and a desktop window cannot reproduce a notch. The first half
      of that is true and the second half turned out not to matter, because
      three `devicectl` facts compose into a complete loop:
      - **`process launch -e '{...}'` passes environment variables into the
        app**, so every `NS3_*` hook this project already has works on the
        handset exactly as it does on a desktop.
      - **`NS3_SHOTS` / `NS3_MENU_SHOT` resolve a relative path against
        `user://`**, which on iOS is the app's own `Documents/`. That was
        already true and was written for a different reason entirely — to stop
        debug screenshots landing in the project where the importer swept them
        up — and it is what makes the file reachable.
      - **`copy from --domain-type appDataContainer` reads that directory** for
        a development-signed app.
      So: launch with hooks, poll for the file, pull it. A screenshot of the
      real phone is now one command and about forty seconds, and **every claim
      in the entries below is measured on an iPhone 15 rather than reasoned
      about**. Three things learned building it, all in the script's own header:
      `--console` attaches and never returns even after the app has exited;
      `--destination` must be a file path, not a directory; and the device must
      be picked out of `--json-output`'s `connectionProperties`, because the
      printed State column is prose that changes under you ("connected" one
      minute, "available (paired)" the next) and CLAUDE.md's own warning applies
      — `unavailable` contains `available`.
      - **The install had a trap that reads like a signing failure and is not.**
        Xcode keeps a *second* `Debug-iphoneos` tree under
        `<derived>/Index.noindex/Build/Products` for the indexer, one level
        deeper than the real one, and its `.app` is a stub whose `Info.plist`
        carries no `CFBundleIdentifier`. `devicectl` then refuses with "Failed
        to get the identifier for the app to be installed". CLAUDE.md's
        documented `find -maxdepth 6 … -print -quit` can match either, whichever
        it reaches first. `-maxdepth 5` plus `-not -path '*Index.noindex*'` is
        exact.

- [x] **1.4 — Developer Mode was already on.** Nothing to do: the export builds,
      `devicectl` installs and launches, and the entry was written before the
      phone testing that produced `cf5a466` had happened. Verified rather than
      assumed — an install ran end to end this pass.

- [x] **1.1 — The match reaches the screen edges. Half of this entry was stale
      and the other half was real, and they had different causes.**
      - **The rendering half no longer reproduces.** Shot on the phone before
        changing anything, as the entry instructed: the match fills all
        2556x1179. What that symptom almost certainly was is recorded in
        `cf5a466` under a different heading — the launch storyboard defaulted to
        `contentMode="center"`, so at @3x iOS drew a 1920x1080 splash at 640x360
        points on an 852x393 screen and **a fresh install came up small and sat
        there**. That was fixed; the todo entry describing it was not.
      - **The HUD's own anchors were real, and were the entry's other guess.**
        `main.gd` placed four labels at coordinates authored for a 1280-wide
        viewport — a size **no shipping device has**, because
        `stretch/aspect="expand"` hands a 19.5:9 phone 1561x720. The sharpest
        case: `players_label` sat at x=1130 inside a 430-wide box, putting its
        right edge at 1560, so **the "N LEFT" counter has never once been
        visible in a desktop run** at the project's own 1280x720 base
        resolution, and on the phone it landed flush against the display edge
        with the last glyph under the rounded corner. `status_label` at x=20 was
        33 device px in, inside a **177 px** safe inset — under the Dynamic
        Island. And `center_label` was never centred at any width: with a zero
        minimum size, CENTER alignment centres text inside nothing and
        `position` is only its left edge.
      - **The fix is `_layout_hud`, run on every viewport change**, placing all
        four labels and all three sticks from `Session.safe_rect`. Two details
        worth keeping: every label now spans the full safe width and aligns
        inside it rather than sitting in a fixed-width box at a computed x,
        **because a Label grows rightward past its minimum size to fit its
        text** and a right-aligned one in a 430-wide box walks off the edge the
        moment an elimination line is long; and the sticks inset from the safe
        rect while **touch input deliberately still uses the whole glass** —
        `_unhandled_input`'s left/right split is on the raw viewport, since a
        thumb in the notch strip should still walk.
      - **The picture is deliberately NOT inset.** The arena runs under the
        island and the home indicator, which is right; it is only chrome that
        cannot be read or reached there. That distinction is the whole of the
        next entry.

- [x] **1.2 — The menu reaches the screen edges: the stage fills the display and
      only the chrome is inset.** `MenuShell._fit_stage` fitted the *whole
      stage* into the safe rect, and on the iPhone 15 that threw away **177
      device px on each side and 63 at the bottom — 13.9% of the screen width**,
      which is exactly "the menu does not reach the edges".
      - **It was invisible in development for two compounding reasons**, and
        both are worth remembering: the letterbox and the menu's own background
        are the same colour (`MenuUI.INK`), so it does not read as bars, it
        reads as a small menu; and a desktop window has no safe area at all, so
        no amount of resizing on a Mac reproduces it.
      - **The file's own comment already said this was wrong.** `_fit_stage` is
        documented as widening the stage past 1920 "so a phone gains stage width
        instead of black bars" — and then the safe-area inset ate the gain back
        and produced the bars anyway. Treating it as a bug rather than a design
        change is on that basis.
      - **The fix is one new node**, `chrome`, a Control inside the stage that
        `_fit_stage` insets by the safe rect. `home`, `screens_root` and
        `toast_column` hang off it; `bg` and `brawler_view` stay on the stage and
        fill the display. **No screen file changed** — every screen anchors
        FULL_RECT to its parent and so is inset for free, which is what kept this
        out of Jackson's surface as anything more than a reparent.
      - **`fx` deliberately stays on the stage, not in the chrome.** Particle
        bursts should be free to cross the whole picture, and both
        `MenuScreen.center_of` and `MenuShell.fly_to` compute destinations in
        stage space off `stage.global_position` — reparenting it would silently
        offset every burst by the safe inset with nothing to show for it.
      - Measured after: the stage fills all 2556x1179, and the chrome still gets
        **2017 stage px** of width to lay out in, more than the 1920 it is
        authored against. The design intent survives; the bars are gone.

- [x] **`Session.safe_rect` is the one copy of this.** The menu had a private
      `_safe_rect` and the match needed the identical numbers, which is the
      setup CLAUDE.md already warns about for `Arena.make_sun` — "a second copy
      of those numbers is how the tool and the game drift apart". It lives on
      `Session` because that class already exists to hold the things both scenes
      need. It keeps the original's guard: some platforms report the whole
      display instead of the window's safe area, so anything implausibly small
      is ignored rather than obeyed.

**Not done this pass, on purpose:**

- **The menu type scale (1.3).** Now measured — the utility tier renders at
  6.2-8.0 pt against Apple's 11 pt floor, about half — but clearing that floor
  needs about 30 stage px, which lands on the bottom of the display tier at 44.
  So the fix is a redesign of the deliberate hole in the scale, not a multiply,
  and that is a decision on Jackson's own system rather than a bug. The match
  HUD's half *was* done, because its labels sit at 12-39 pt with no such
  doctrine attached. Numbers are in `todo.md` 1.3.
- **The loading screen's title under the island.** Same class of bug, one line
  from being fixed, and left alone because `LoadingScreen.compose()` is shared
  with the boot-splash renderer and the seamlessness of that handoff is a tuned
  property. Filed as `todo.md` 1.5 with the reasoning rather than fixed in
  passing.

## Phone pass (5 Sep 2026) — The lineup — done, this pass

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


## Phone pass (5 Sep 2026) — Feel and controls

- [x] **The Super is a stick you drag off, and there are three of them on
      screen.** Closes "the Super is hard to aim", which asked for exactly the
      Brawl Stars arrangement: the button and the stick were separate controls,
      so aiming only began once the finger was already on the button and the
      most expensive shot in the game had the least aim time. `super_button.gd`
      is deleted and folded into `TouchStick`; `charge >= 0` is what turns the
      dial and the star on, so one circle does the job two overlapping ones used
      to.
      - **All three sticks are visible when nobody is touching them**,
        translucent and colour-coded — blue walks, red shoots, gold is the
        Super. They used to be invisible until touched, which is only readable
        once you already know they exist: nothing said the left half walks and
        the right half shoots, and the Super button was the one control you
        could see.
      - **They still float to the finger**, which is also what keeps a tap
        unambiguous: `value` is zero at the instant of the press however far
        from home it landed, so a press-and-release is always a tap and never a
        full-deflection drag. The old Super button anchored its stick at the
        button and then fed it the touch position, so a thumb landing on the
        edge released a manually aimed Super it never asked for.
      - **The grab radius is 118 px against a 70 px ring** (~2.3x the old
        button's area), affordable because an uncharged Super now falls THROUGH
        to the aim stick instead of swallowing the press — a thumb landing in
        the half-second before it filled used to fire nothing at all, which is
        indistinguishable from a control that does not work.
      - The hide check sits **before** `_update_status`'s validity guard, so a
        Showdown elimination cannot leave three parked joysticks under the
        results card.

- [x] **Haptics, second pass — scores instead of a table.** The first pass was
      `Haptics.fire(name)` over fourteen duration/amplitude pairs. The rewrite
      keeps every call site and replaces what is underneath.
      - **The diagnosis, and the reason the first table felt flat.** Godot's iOS
        backend emits exactly one event type and one parameter:
        `AppleEmbedded::vibrate_haptic_engine`
        (`drivers/apple_embedded/apple_embedded.mm:73-132`) builds a pattern
        holding a single `CHHapticEventTypeHapticContinuous` with only
        `HapticIntensity` set — no `CHHapticEventTypeHapticTransient`, no
        `HapticSharpness`. Fourteen pairs were therefore fourteen lengths of ONE
        sensation. It was never the contents of the table.
      - **Rhythm is the axis that was left.** Core Haptics mixes concurrent
        players and GDScript can schedule calls, so a tap is now a SCORE of
        timed segments, head fired on the frame and tail queued. Measured over a
        Cup match, the 36 tail segments landed 0-8 ms late (median 4); a 60 fps
        phone tops out near a frame, which is why nothing places two segments
        closer than ~40 ms.
      - **The fallback device was being designed for and does not exist here.**
        `OS.has_feature("mobile")` is true on an iPad too, so the probe is now
        `AppleEmbedded.supports_haptic_engine()`. TAPTIC gets the scores; BUZZ
        collapses to one segment and drops anything quiet, since that path
        answers every request with the same ~0.4 s buzz.
      - **Tiers fixed a real defect.** The old throttle was purely temporal, so
        a menu tap could swallow a death — `hit` and `death` land in the same
        frame and the winner was whichever ran first. A higher tier now preempts
        a lower one. Firing your Super is an EVENT and the elimination it caused
        is a CEREMONY, which the log proved matters: ranked the other way the
        kill was eaten, because a Super that kills lands both inside 160 ms.
      - **New coverage, biggest first.** `landed` — your shot arriving on
        somebody, which had no entry at all and is the one thing in a firefight
        you cannot read off the screen; `empty` (you pressed fire and nothing
        came out); `ammo_ready`; Cup's plain `kick` and `super_shot`, neither of
        which ever reached `perform_attack` so neither had any haptic; the
        countdown beeps; `victory`/`defeat`.
      - **Two numbers were measured rather than picked.** The damage curve was
        re-measured after the first attempt at 0.05-0.45 put every real hit
        between 0.36 and 0.61 of a scale running to 0.98 — real damage lives
        between 6% and a third of max health, so the curve is 0.06-0.34.
        `LANDED_WINDOW` exists because a shotgun's pellets land across three or
        four frames, so per-frame banking reported a third of the blow.
      - **`NS3_HAPTIC_AUDIO=1` is the new instrument that matters.** Rhythm is
        what is being designed and it survives being heard, so scores can be
        compared on a desktop instead of one device install per change. The log
        also prints DROPS with their reason now, which separates a throttle
        eating a tap from a hook that never ran.
      - **The aim stick's detent** — `aim_on`/`aim_off` across `TAP_THRESHOLD`,
        the invisible line where a tap-to-auto-aim becomes a manual lane.
        Watched per frame rather than off the drag event (a thumb that crosses
        and holds still stops generating those), and debounced with a dwell
        rather than hysteresis, because a hysteresis band would have the tap
        claim a state the game is not in. Verified by driving the stick with a
        sine across the threshold: the taps tracked it to within a frame — 1.68 s
        above and 0.40 s below, against 1.69 and 0.41 computed.
      - Confirmed firing on real runs: `count_beep`, `count_go`, `hit`,
        `landed`, `empty`, `ammo_ready`, `cube`, `super_ready`, `super_fire`,
        `elimination`, `death`, `kick`, `ball_get`, `goal_for`, `goal_against`,
        `victory`, `defeat`, `ui_tap`. Not yet seen: `super_shot` (needs a
        charged Super while carrying) and `ui_reward`.
      - Still open: nothing is tuned against an actual phone. The amplitudes are
        reasoned and measured but not FELT, and that is the only test that
        settles them.
- [x] **A tapped Super is scored now, not nearest.** `main.gd:_super_target`
      ranks every candidate in the same set the old rule used (`range * 1.1`,
      the same wall and bush checks) as an expected value: what the target is
      WORTH — would this Super finish them, are you already trading with them,
      are they wounded, are they close — multiplied by `_connect_odds`, roughly
      how likely the shot is to arrive given `_aim_lead` assumes the target
      holds its heading. Weights are a ranking, not a measurement: a kill beats
      the fight you are in, which beats a wounded bystander, which beats
      nearest.
      - **The regular tap is deliberately still nearest**, and the asymmetry is
        the point. An attack repeats two to five times a second, so a wrong pick
        costs one shot and the next tap corrects it — while a picker that
        re-ranks every tap sends consecutive shots at different people, which
        reads as the game arguing with you. Nearest is also the only rule a
        player can predict without reading a marker. A Super is the one shot
        that costs something, so it is the one that can afford the machinery.
      - **All three deliberate exceptions survived**, which was the thing to
        watch: Pop Off still leaps the way you are running, Downhill still sets
        off with nobody in reach, and any other Super with no target still keeps
        its charge. They live in the new `_tap_plan`, which returns
        `{kind, dir, target}` and is shared by the firing path AND the aim
        indicator — that sharing is what makes the Cup tell below possible.
      - `Fighter.engaged_with` / `engaged_at` record the exchange on **both**
        sides of every hit, so "the fighter you have been trading with" is true
        whether you have been shooting them or they have been shooting you.
      - **Superseded 6 Sep 2026 — the scoring was removed and must not come
        back.** `_super_target` is nearest again and `_connect_odds` is gone. The
        reasoning in this entry is sound and was still the wrong call: a Super is
        aimed under pressure at the fighter you are *looking at*, so any rule
        that quietly prefers a different one is wrong at the moment it matters,
        however good its arithmetic. What survived is the useful half —
        `_tap_plan` (now two cases, `target` and `free`), the three deliberate
        exceptions, and `Fighter.engaged_with`.
- [x] **A Cup tap now says which of the two things it will do.** The rule was
      not wrong — a tap shoots inside `SHOT_RANGE` and passes otherwise, which
      is right — the tell was missing, so the tap silently did one of two very
      different things depending on a distance the player cannot see.
      `CupMode.kick_plan` now returns `{kind, at, dir}` where kind is
      `shot` / `pass` / `clear`, and `main.gd` draws a ring on `at` — the goal,
      or the team-mate — so you can see what a tap is aimed at before you take
      it. `kick_aim` is kept as the direction-only half for the callers that
      just kick. The bots read the same plan, so what the ring promises and what
      a tap does cannot drift.


## Phone pass (5 Sep 2026) — Menu and progression

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

## Phone pass (5 Sep 2026) — Boot

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


## Phone pass (5 Sep 2026) — Balance, from play

- [x] **Kovacs stripped the carrier with a BASIC ATTACK, and that was the bug.**
      The entry above assumed the fix was a clamp on distance. Measured over a
      full match with the new `NS3_BALL_LOG=1`, the real fault was upstream:
      `_carrier_check` tested a bare speed threshold on `knockback_vel`, and
      Kovacs' clap shoves at 4.0 — over `KNOCK_DROP_SPEED` (3.0) — so it took
      the ball off the carrier **every time it landed**, on a normal reload,
      across a 2.4-tile 78-degree cone. Nothing else in the roster strips with
      its regular attack and nothing should.
      - **No threshold can fix it**, which is why the rule changed shape rather
        than its number: his clap shoves at 4.0 and *Sanjit's Super* shoves at
        exactly 4.0 too. What separates them is where the shove came from, so
        `deal_damage` now records the attacker on the target and
        `_knock_was_super` asks whether the impulse was harder than that
        attacker's OWN weapon. Every kit gives its Super more knockback than its
        attack (Kovacs 10 vs 4, Leon 5 vs 1.5, Anders 14 vs 3, and the other six
        put none on the weapon at all), so "harder than their own attack" IS
        "their Super" — and it stays true for a kit added later with nothing
        here retuned.
      - **The ball keeps some of the shove** (`Ball.knock_loose`) so a strip
        reads as knocked away rather than put down, capped at `KNOCK_BALL_MAX`
        — the hardest Super in the roster coasts it about 6 m against a kick's
        15, so a strip can never be a shot from anywhere a kick could not
        already have been taken. `last_touch` is deliberately NOT changed:
        whoever landed the Super never touched the ball, and leaving the carrier
        on it keeps goal credit and the own-goal test honest.
      - **A knock outlives the ball's pickup hold**, which cost a pass to find:
        a 10 m/s shove decays over ~0.58s against `KNOCK_BALL_HOLD` of 0.35s, so
        the carrier re-collected while still wearing a live knock record and was
        stripped again on the next frame — three strips off one Kovacs Super,
        measured. `Fighter.forget_knock()` spends the shove the moment it takes
        the ball.
      - Verified after the fix: every `knock` line in a full match is a Super
        (Kovacs 10.0, Nova 12.0) and the ball runs 1.6–2.0 m, against kicks of
        3–13 m.


## Character models & animation

- [x] **Ayaan is modelled, wears skis through his Super, and stands like a
      skier.** Jackson's Meshy export (`Assets/3D/Animation/carver_brawler_animated.glb`
      → `assets/ayaan.glb`, 6 Sep 2026) through `fix_meshy_glb.py`, textures
      capped at 1024 on import like the other characters; `Jump_Over_Obstacle`
      is the Super clip and `Punch_Combo_3` the attack. The skis are a second
      GLB (`assets/skis.glb`) split into `left`/`right` by `--split-halves` and
      bolted to `LeftFoot`/`RightFoot` for the life of the Super — worn from
      the cast, through the flip, to the landing, gone with the run.
      - **Skis solved in skeleton space vanished at the apex.** On the ground
        they looked right; at the top of the jump they were a hundred metres
        away, because a Meshy armature carries a 0.01 scale that a child of
        the skeleton inherits. The solve is in world space now
        (`skeleton.global_transform * get_bone_global_rest`), which folds that
        scale into the inverse. Written up in CLAUDE.md under **Worn gear**.
      - **The first Idle was a frame of the punch combo's guard**, and on the
        home screen it read as hands-up surrender. The rest pose was worse (a
        T-pose with relaxed arms is a mannequin). What shipped is the guard
        frame's symmetric feet with both arms re-aimed to hip height and an
        8° forward lean — a skier gripping poles — built with the tool's new
        `--idle-from` / `--idle-aim` / `--idle-spin` flags rather than by
        hand-editing quaternions. Rejected on the way: forearms level at chest
        height (zombie arms), the jump's crouch frames (every one is an
        asymmetric lunge), and the walk frame (straight legs, no stance).
      - **The stance flags did nothing for four candidates in a row** and the
        renders of "different" poses were the raw clip frames. zsh does not
        word-split an unquoted `$FLAGS`, so the whole flag string arrived as
        one argument that matched neither parser — the same zsh trap CLAUDE.md
        already records for the wifi harness. `${=FLAGS}`.

- [x] **Anders' hacky sack is the pink "N" ball, on his foot and in the air.**
      The ball Jackson supplied as `Meshy_AI_Soccer_Ball_8k_…` was taken for the
      Cup ball and wired as one; it is the hacky sack. The Cup ball went back to
      the drawn twelve-pentagon shader (`ball.gd`), and the model is
      `assets/hacky_sack.glb`: worn on `RightFoot` from the cast until the kick
      lands (`kits.gd` `gear`, `"on": "attack"`), then thrown as the same model
      (`weapon.model`, `hacky_sack.gd`), fitted to `weapon.radius` by
      `Fighter.fit_ball`. Landings and hits still resolve by radius.
      - **At the projectile's radius (0.44) the ball on his foot was a beach
        ball** strapped to his ankle. It is half that on the foot and
        `main.gd:_launch_sack` swells the throw from that size to its own over
        its first 0.15 s, so the hand-off reads as one object rather than a
        small ball popping into a big one.
      - **The atlas had pink speckle over every white panel** — the bake's
        noise, recoloured with the panels. Cleaned by classifying each texel
        (white / pink / navy / seam) and replacing any pink-in-white or
        white-in-pink fleck with the local mean of the majority class, and the
        metal/roughness map was dropped (its dot pattern read as a grid on the
        navy panels; the material is metallic 0, roughness 0.8 now).

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

- [x] **Season rebuilt to the mockup: reward cards, a drawn track, and a Pass
      grid** (7 Sep 2026). Jackson sent a mockup of the Season page and asked
      for its format. Three changes, and the third is the one that cost the
      time:
      - **A reward is a picture of itself.** The rails set every reward as
        words, on the reasoning that a word reads faster down a rail than a
        108px illustration and ships no file. That reasoning was wrong about
        what is being scanned for: not *how much*, but *which kind*, which a
        glyph answers first and a word answers second. Twenty columns of
        display type is also just a wall of text. The word stays under the
        glyph as the amount. Four glyphs were drawn to fill the set
        (`svg/dawg_treat.svg` — the bone — plus `crown`, `ticket`, `pin`); a
        fighter, skin or pin shows the roster's own portrait render in a tile
        of the kit's colour, so a reward is never a second illustration of
        somebody the roster already draws.
      - **The track is drawn.** A row of thresholds with nothing between them
        is a list of numbers; the line with a dot per milestone, lit as far as
        you have got and dark after, is what makes it a road. One of the few
        places a line IS the content — which is what `MenuUI.rule()` survived
        the 6 Sep no-rules pass for. Each track cell draws its own half-spans
        and its dot with anchored `ColorRect`s, so the line is continuous
        across adjacent columns and needs no custom `_draw`.
      - **The heights have to add up, and estimating them does not work.**
        Nothing on this screen scrolls vertically, so the header, the two
        blocks and the gaps between them have to fit 816 stage pixels between
        the top bar and `MenuUI.NAV_H`. Every hand-computed budget came out
        short, and the reason is type metrics: Anton's line box is ~1.64x its
        font size and Barlow's ~1.2x, so a "24px" name is 39 tall and a "20px"
        gold CLAIM button, with `MenuUI.button`'s 16px content margin, cannot
        be shorter than 65 — half a tile. Three things came out of that:
        - **A claimable card is the button.** Nesting a CLAIM button in the
          card made every claimable column ~20px taller than its neighbours
          and pushed the rail out of its block. `_reward_card` returns a
          `Button` in that state and a `PanelContainer` otherwise, the state
          line reads CLAIM in gold, and the whole tile is the tap target —
          which is the bigger target on a phone anyway, and is what the mockup
          draws.
        - **`MenuUI.button` takes a `pad` now**, for the one chip that still
          has to be small (UPGRADE in the premium lane head). Default 16, so
          every existing caller is unchanged.
        - **Measure it, do not add it up.** `print(get_global_rect())` for the
          two blocks and the nav bar settled in one run what four rounds of
          arithmetic had got wrong. A `Control` whose minimum exceeds its
          anchors silently grows its parent — `body` was 1136 tall inside a
          1080 stage — so the overflow is invisible until something lands
          under the nav.
      - Smaller things that were wrong and are worth not redoing: a
        `ScrollContainer` gives its child the full height on the disabled axis
        **only if the child carries `SIZE_EXPAND`**, so the Pass rail laid out
        forty tiers correctly inside a zero-width box and drew nothing; and a
        `PanelContainer`'s stylebox content margin is added to its child's
        width, so a 3px ring around the current tier made every column
        `TIER_W + 6` and walked the scroll-to-tier offset off by a column and
        a half.
      - On a stage taller than 16:9 the blocks and the cards take the slack
        (`_grow`) rather than leaving a band of nothing above the nav.
        Verified at 1920x1080, 1920x1200 and 1560x720, in both the
        pass-bought and pass-not-bought states, with `NS3_MENU_PROGRESS`.

- [x] **Shop opens on the Dawg Treat, and the menu grew a shared block**
      (7 Sep 2026). Shop was the last screen still wearing the overhaul's
      layout at a larger size: three lists, of which the first was nine
      near-identical POWER UP rows with an UPGRADE button each, filling the
      screen top to bottom, with the Dawg Treat — the one thing on the page
      with any occasion to it — below the fold underneath them.
      - **The Treat is the first block now**, with the bone at 96px, the copy,
        the OPEN button, and the odds beside it as a row of seven rarity
        chips: a colour band over the chance over the name. The old table was
        seven lines with a 14px swatch each; the chips take a third of the
        height and put the seven colours in a row where they read as a scale.
      - **A fighter is a card with their own face on it**, the same square the
        roster tiles use, with POWER n and the cost. **The card is not the
        button** — everywhere else in this menu a whole tile is pressable, and
        here it deliberately is not: claiming a Trophy Road reward is free, and
        this spends 200 coins a tap. A cost earns an explicit control.
      - **Three pieces moved into `MenuUI` so two screens cannot drift.**
        `block(icon, title, rule)` is the bordered card with a head that Season
        and Shop are both made of; `reward_glyph(kind)` and
        `reward_name(kind, amount)` are the one place a reward is named and
        drawn. That last one was already broken in the small way these things
        break: Shop said "50 POWER POINTS" where Season said "50 POWER PTS".
      - **`GridContainer` only splits its width between columns whose children
        ask to expand.** Without `SIZE_EXPAND_FILL` on the cards, the columns
        sit at their natural widths and the last row stops halfway across the
        block. The sibling of the same trap: a label with `clip_text` has a
        minimum width of zero, so a name column that does not expand gets only
        what "POWER 1" needs and KOVACS comes out "KOVAC".

- [x] **Events got the icons it already had, and a button you can see**
      (7 Sep 2026). Two bugs and a relayout:
      - **The SELECT button was invisible.** It was built `"navy"`, and
        `MenuUI.fill_for` resolves that to `PANEL` — the fill of the card it
        sits on — so on the one mode you had not already picked, the action was
        a word floating in the dark with a hairline somewhere behind it. It is
        `"grey"` now, and it is the same size and position as PLAY on the other
        card, because they are the same control in two states.
      - **Every mode names an `icon` in game.json and nothing drew them.**
        `bulldog`, `gem`, `coin`, `power_point`, `star_drop` were all already
        in the art; only the Cup's `brawl_ball` was missing, so `svg/ball.svg`
        was drawn for it. First pass at that glyph had a pentagon and seams
        heavy enough to read as a spider at 66px — the second is a smaller
        centre panel and five short seams.
      - A hairline rule was still separating each card's blurb from its head,
        which the 6 Sep no-rules pass had removed everywhere else, and a glyph
        beside the map name was tried and dropped: there is no map icon in the
        set and `stage_ring` at 22px is a smudge. Gold already says "this is
        the place".
      - The five unbuilt modes were dim rows with a 7px colour block each;
        they are small dim cards now, so the section reads as a plan rather
        than as a list of things that do not work.

- [x] **Seven dead helpers left the design system** (7 Sep 2026, `todo 5.1`).
      `plate_colors` was the one the todo asked about — "either it earns its
      place or it goes" — and the answer was that the overhaul had already
      flattened it to three copies of one fill and nothing had called it since.
      `stat_row`/`stat_line`, `body_font_700`, `disabled_button`, `art_button`
      and `chip` had no callers either. Checked with
      `grep -rn "\.name(" godot --include="*.gd"` and verified by running every
      menu screen plus a full Nobles Cup match with its results card, since
      `main.gd` builds its match chrome out of `MenuUI` too — zero errors. Git
      history has them if one is ever wanted back.

- [x] **5.2 — The roster is a wall of faces, not a table** (7 Sep 2026).
      Ryder wanted tiles; the screen was nine numbered rows. The argument the
      table was built on is worth recording because it was *true* and still
      wrong: nine rows fit one screen with no scrolling and put trophies and
      power in columns you can compare down, which a grid cannot do. Neither
      fact is why anyone opens this screen. **You do not pick a fighter by
      comparing trophy counts** — you pick the one you want to play, and you
      recognise them by face. The table made the two figures the loudest thing
      on a screen whose entire job is recognition, and it set nine names in the
      display face while nine portrait renders sat unused in
      `assets/menu/portraits/`. The numbers are still there, small, in each
      tile's footer, which is the weight they deserve.
      - One tile each: the portrait on a ground of the kit's own colour (the
        only solid block of a fighter's colour in the menu outside the home
        flanks, and what makes nine tiles read as nine people rather than nine
        dark rectangles), the roster number top-left, a padlock or SELECTED
        top-right, then name, role, and a trophy figure and power level.
      - **Two rows at any roster size.** `_columns()` is `ceil(n / 2)`, so nine
        lay out 5+4 and the twelve the beta bar asks for lay out 6+6, both on
        one fixed-height screen. Past twelve this wants a scroll or a third row
        rather than thinner tiles.
      - A locked fighter is **dimmed, not hidden** — which fighter it is is the
        reason to go and unlock them — and spends the footer on the unlock hint
        instead of on two zeroes. Nova has no render yet (`todo 4.1`) and gets
        her initial in the display face, which reads as "not shot yet" where a
        broken-image box reads as a bug.
      - **The ground is a `Panel`, not a `PanelContainer`.** A container lays
        its children out to fill it and ignores their anchors, so `MenuUI.pin`
        did nothing and the roster number and the SELECTED mark rendered on top
        of each other in the corner. Verified at 1920x1080 and 1560x720, with
        the roster fully unlocked and back at first-run.

- [x] **`NS3_MENU_PROGRESS` seeds progress for a harness run** (7 Sep 2026).
      A fresh save has nothing reached and nothing claimed, so a screenshot of
      Season or Shop only ever showed the locked state — and claimed,
      claimable and current-tier are most of what those screens are.
      `NS3_MENU_PROGRESS=trophies:2000,tier:11,tokens:300,premium:1,claimed:1`
      sets the `SaveGame` statics in memory and **never calls `save()`**, so
      the machine's own progress is untouched. `claimed:1` backfills every
      milestone and tier already passed, which is what puts the three states
      side by side, and `starters:1` puts the roster back to a first-run one,
      which is the only way to shoot a locked tile on a save with developer
      mode turned on.

- [x] **The stage covers a 16:10 display** (6 Sep 2026). In fullscreen on the
      MacBook the menu came up "cropped weirdly": `_fit_stage` kept the stage
      1080 tall on any display, so on a 16:10 screen the picture was a 16:9
      band with ink bars, and the chrome — anchored to the display through the
      safe rect, not to the band — sat in the bars. The stage now grows in
      whichever direction the display exceeds 16:9, so it covers it either way;
      the ring, pool and hint under the fighter are placed by proportion of the
      stage height (`HomeScreen.FEET_FRAC`) because he is framed to it.
      Verified at 1280x832, 1280x720 and 1560x720.

- [x] **The mockup pass: cards, bars, medallions, and a stage lit in the
      fighter's colour** (6 Sep 2026, after the five-zone layout below).
      Jackson's mockup set the material: rounded cards with a hairline edge,
      coloured stat bars in glyph boxes, ability cards with a round medallion,
      a record card, coins and gems with their names under the figures, three
      bars over the word MENU, text nav tabs, and the fighter on a painted stage
      under a spotlight with a ring at his feet.
      - **One radius.** `MenuUI.RADIUS` = 12 on every box and button, 6 on
        chips. The old system's thesis was zero; the mockup's is one number,
        and the point survives — a second radius would still read as a second
        system.
      - **Nine stages from one painting.** "The backdrop should change
        depending on character" arrived with one painting in hand, so the
        stage is recoloured by its own luminance (`STAGE_TINT_SHADER`): the
        hall keeps its navy where it is dark and the floor takes the kit colour
        where it is lit, with the pool and rings following. A kit that names
        `stage` art gets that file untinted, so real per-fighter paintings can
        replace the tint one at a time.
      - **The fighter renders on a transparent viewport** over the painting,
        with no ground plane and no fog — the arena-floor set and the fog
        constants that framed it are inert. `FILL` went 0.52 → 0.64 so he is the
        size the mockup draws him; his feet land at `HomeScreen.FEET_Y` (900).
      - **Ability medallions carry a glyph per kits.gd Style**, thirteen
        script-drawn svgs (`svg/style_*.svg`) chosen through the `style` the
        merge now carries, rather than one illustration per ability: nine kits
        would need eighteen drawings, and a glyph per weapon *kind* is what the
        match's own vocabulary already is. Real ability art can replace them
        card by card.
      - **Rejected:** the mockup's mountains (not in the painting, and a second
        painted layer behind a painting is where the JPEG-era framing chain
        came from); lighting ROSTER as the active tab on home the way the
        mockup does (home is not the roster, and the tab would then do
        nothing); a nav tab that is a label in a button (zero minimum width —
        all four tabs collapsed onto one spot; a tab is now a text button that
        sizes to its word, like `link`).

- [x] **The five-zone layout, a nav that stays, and no lines** (6 Sep 2026,
      Jackson's redesign — ROADMAP **D1**, `todo 5.3`). Same material as the
      programme page (Anton and Barlow, ink and gold, square corners); what
      changed is what goes where. Top-left is who you are (avatar, name, record
      on home; the back arrow in a square on every pushed screen, the room
      screen included). Top-right is coins and gems as icon-and-figure and the
      menu as three bars in a square. Bottom-left is ROSTER / SEASON / SHOP /
      WIFI as picture-over-word tabs owned by `MenuShell`, on every screen, the
      current one lit gold. Bottom-right is the mode plate and PLAY one gap
      apart on one baseline. One hint under the fighter's feet, nothing else
      around him. The icon pack does the pictures; its painted backdrop stays
      unused because the live 3D ground is the game's own look.
      - **Every hairline rule is gone.** Section heads, stat rows, the home
        screen's top and bottom caps, the roster's row separators, the rails'
        column rules. On a phone they read as stray lines, not structure;
        spacing does the job. Kept: the Season thresholds' underline (it turns
        gold as you reach them — that is content) and the mode cards' flag.
      - **The utility type moved up a tier, 17–22 → 26–30** (`todo 1.3`): on
        the phone the stage converts at x0.364 px→pt, so 19 px was 6.9 pt. Moved
        as a tier, with the display sizes it met moved with it, so the deliberate
        hole in the scale is intact one step up. Not verified on the handset yet.
      - **What overflowed and how it was settled.** The home screen's right flank
        ran under PLAY once its copy was 28 px: ability body went to 26 with
        tighter line spacing, the record became one row of three figures
        instead of three stat lines, and both flanks widened to 460. Season's
        two rails ran into the nav: header, gaps and rail heights came down
        (rails 176 and 276) rather than the nav moving, and the rail's
        scroll-to-progress stopped adding the 1 px per column that the deleted
        column rule used to take, which had been clipping the current tier.
      - **Rejected:** the pack's stage backdrop behind the fighter (fights the
        3D ground and the depth fog that takes it to ink); keeping a CLOSE link
        beside the back square (two exits doing one thing); a nav inside the
        home screen (then no pushed screen can show which tab it is).
      - **The earlier `wifi_screen.gd` re-skin was retired** in favour of
        Ryder's phone-tested `room_screen.gd` (the two-column join-code pad):
        function over chrome until the party surface replaces it.

- [x] **The menu is native Godot** (`godot/scripts/menu/`). The HTML build it was
      rebuilt from is gone — it could not ship inside the iOS app — and all of its
      art moved to `godot/assets/menu/` (cards, treats, decor, pass hero, skins,
      mode/currency icons, logo, key art). Copy and config live in
      `godot/data/{brawlers,game}.json`; stats come from `kits.gd`.
- [x] **Dead asset bytes are gone.** Deleted the 13 duplicate `icons/*.webp`
      (coin, gem, trophy, gear, lock, …), which were unreachable because
      `MenuUI.icon_texture` tries `svg/<name>.svg` first and only falls through
      to WebP when no SVG exists; and `assets/Fox.glb` + its texture, referenced
      by nothing at all. 456 KB off every export.

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
- [x] **PLAY AGAIN exists for everyone now.** Both buttons are `MenuUI` plates
      and LOBBY goes through the loading screen; the multiplayer half is done
      too — a wifi client gets REMATCH in place of PLAY AGAIN, which asks the
      host, and a line saying what it is waiting on. See the Multiplayer
      section for the flow and for the `VBoxContainer` bug the four-row client
      card turned up in this card's own stagger.
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

- [x] **8.3 — Nobles Cup can be hosted.** *Found built and uncommitted, and
      verified 6 Sep 2026 rather than taken on trust.* This entry used to say
      `net_play.gd` and the net section of `main.gd` were Showdown-only and that
      `_rpc_start_game` hard-coded `Session.mode = "showdown"`. None of that is
      true of the working tree.
      - `host_game` takes a `room_mode`; `room_capacity()` returns 6 for Cup
        against 10 for Showdown; `main.gd` carries `_net_cup_roster`,
        `_net_cup_down`, `_net_cup_goal`, `_net_cup_kickoff`, `_net_cup_over`,
        `cup.adopt_net_match` / `cup.apply_net_state`, and the ball's carrier
        index in the snapshot.
      - Verified in the two-instance harness (`NS3_HOST=2 NS3_MODE=cup` against
        `NS3_JOIN=127.0.0.1`): the client connected, applied a 6-fighter roster,
        and rendered a live **0-1** scoreline with the clock at 2:24 and the
        elimination feed naming the scorer. Zero script errors on either side.
      - The room screen offers `NOBLES CUP · 3v3 · up to 6` beside Showdown.
      - CLAUDE.md documents it in the same changeset (`**Nobles Cup over wifi**`,
        and the `CupMode.authoritative` split), so working tree and notes agree.

- [x] **Join codes replaced join-by-IP.** *Also found built and uncommitted.*
      A four-character code a friend reads out across the room:
      `192.168.1.24` → `6PBA`. There is no server to look a code up in, so the
      code cannot *refer* to the address — it **is** the address, compressed and
      scrambled across the code space so that adjacent addresses do not produce
      adjacent codes.
      - `tools/code_probe.gd` verifies the codec **in the engine that ships it**,
        because the seven-character form multiplies a 35-bit number by a 35-bit
        constant and that is the one place GDScript's 64-bit ints could silently
        wrap. Result: 65,536 exhaustive checks on 192.168.*, ~20,000 random each
        on 10.*, 172.16-31.* and public, **zero bad**.
      - A mistyped four-character code decodes to **nothing** 94% of the time
        rather than to somebody else's machine.
      - CLAUDE.md documents it too: `Net.broadcast_works()` replaced
        `discovery_works()`, and discovery is now broadcast **plus** a unicast
        /24 sweep, because unicast to a LAN neighbour needs only the Local
        Network permission that `export_presets.cfg` already declares.

- [x] **Clients interpolate, and predict their own fighter.** They used to be
      pure puppets chasing the newest 30 Hz snapshot on an exponential lerp,
      which is invisible on a LAN and both laggy and steppy on anything worse.
      - **Everyone else is drawn at a fixed delay behind the host**
        (`NET_INTERP_DELAY`, 85 ms — two and a half snapshots), by
        interpolating between the two buffered snapshots that bracket that
        instant. The host stamps its own `now` into every snapshot and the
        client keeps a **min-filtered** `local now − host now` in
        `_host_offset`, so the delay is measured against the host's clock
        rather than against arrival times and jitter stops moving bodies. A
        starved buffer extrapolates from the last two samples for at most
        `NET_EXTRAP_MAX` (120 ms) and then holds — past that, extrapolation
        reads as a fighter skating through a wall, which is worse than a
        fighter standing still.
      - **The discrete half of a snapshot** (health, ammo, Super, the gas ring,
        the fighters-left count) **is applied at that same delayed instant**,
        not off the newest packet, so a hit flash lands on the frame the body
        is drawn where it was hit. Your OWN fighter is the deliberate
        exception: it is drawn at `now`, so its numbers are applied the moment
        they arrive.
      - **Your own fighter moves on your own stick** (`_net_predict`), through
        the same `Fighter.apply_movement` the host runs, so walls, water and
        the kit's speed all resolve identically. The host acknowledges the last
        input seq it applied in each snapshot; `_reconcile` compares that
        against the position the client's own copy of that input produced and,
        past `NET_PRED_TOLERANCE` (5 cm), puts the body where the host says it
        was and **replays** every unacknowledged input from there — so a
        correction resolves against walls instead of teleporting through them.
        Past `NET_PRED_HARD_SNAP` (2.5 m) it snaps: a knockback or a dash is
        not something to swim to.
      - **`_pred_pos` and `_pred_error` are kept apart, and that is
        load-bearing.** The correction goes into the SIMULATION at once and
        into the PICTURE over the next fraction of a second. Feed the visual
        offset back into the simulation and the next frame's prediction
        measures its own correction, double-counts it, and the client twitches
        on every packet. Ask for a `git log -p` on the first draft before
        rewriting this: the bookkeeping needed to make the naive version
        correct is longer than the replay.
      - **The host buffers inputs and consumes one per physics tick**
        (`_consume_input`) instead of applying whatever arrived last. Two
        inputs landing inside one frame used to mean one was thrown away and
        the client had predicted a step the host never took.
      - **Measured** with `NS3_NET_STATS=1` under `NS3_NET_LAG=80
        NS3_NET_JITTER=20 NS3_NET_LOSS=0.03` (a 160 ms round trip with 3%
        loss): reconcile error **avg 0 cm, max 15 cm** across the settling
        frames and **0 cm** for the rest of the match, buffer 3-4 snapshots
        deep, 0 extrapolated frames. Untouched, the same link leaves the local
        body about 0.9 m behind the stick.
      - Gotcha the pass turned up, and it is worth knowing before tuning the
        buffer: **`unreliable_ordered` DISCARDS a packet that has been
        overtaken**, so a client whose frame rate drops below the snapshot rate
        gets one snapshot per FRAME and the ordered channel collapses the rest.
        Measured at 12-18 received against 30 sent through the first seconds of
        a match while the models are still landing — which is exactly what the
        buffer and the extrapolation window are covering.
      - Gotcha 2: **`Kits.Style.JUMP_SMASH` was starting a leap on clients**,
        where `_update_leaps` never runs, so `is_leaping()` stayed true for the
        rest of the match — and `apply_movement` returns early while it is.
        Free while the local fighter was a puppet the snapshot stream moved; it
        freezes a predicting one solid. Now gated on `authoritative` like the
        DASH and DOWNHILL cases beside it.
      - Still open, and the next thing anyone will feel: **attacks are not
        predicted.** A client's shot goes up as `_net_fire` and only appears
        when `_net_attack` echoes back, so pressing fire on a 160 ms link is a
        160 ms wait for the muzzle flash. Doing it means the client predicting
        its own ammo and cooldown well enough not to draw a shot the host
        refuses; the snapshot already carries both, one interpolation delay
        late.
- [x] **The snapshot is packed and quantised — 6.2x smaller, measured.** It was
      a Variant `Array` of `Array`s, which costs about twelve bytes a field
      once Godot has tagged every number as a double: **29-30 KB/s** at 30 Hz
      for ten fighters, which a LAN swallows and a phone on a busy access point
      does not. It is now a ten-byte header plus fifteen bytes per LIVING
      fighter — **4.7-4.8 KB/s**, and down to 3.1 KB/s late in a match as the
      roster thins, because dead fighters are left out of the alive mask
      instead of costing an empty array each.
      - Quantisation, and why each is enough: position to a centimetre (the
        capsule is 0.65 m across and the map is 78 m, so u16 covers it),
        facing to 1/256 of a turn (1.4°, on a body 70 px wide on screen), ammo
        to 1/32 of a pip, Super to 1/255 of the bar, the two burn clocks to a
        sixteenth of a second. The reconcile tolerance is 5 cm, five times the
        position quantum, so packing cannot itself provoke a correction.
      - **Nothing is delta-encoded, on purpose.** The stream is unreliable: a
        field only sent when it changes is a field lost for good when that one
        packet drops, and the ack scheme that fixes it costs more — in state on
        both sides, and in bugs — than the bytes it saves at this size.
      - `NS3_NET_STATS=1` prints both figures every two seconds (the host
        builds the old form alongside the new one and `var_to_bytes` it), so
        the ratio stays checkable rather than remembered.
- [x] **A client's results card has its real stat table.** `deal_damage`
      returns early when `not authoritative`, so a client's own `Fighter.stats`
      are all zeros and the card fell back to the one row it could fill in
      honestly. The host now sends the fighter's damage / eliminations / cubes
      / survival with `_net_push_stats` immediately before the `_net_eliminate`
      that raises the card, and again to the last survivor before
      `_net_match_over`; `_net_rows` prints them. The single-row fallback is
      kept for the case where they somehow have not arrived — one true row
      still beats four invented ones.
      - `multiplayer.get_peers().has(peer)` guards the send. The commonest
        reason a player's fighter is eliminated is that the player LEFT, and
        `_on_net_peer_left` eliminates it from inside the disconnect handler,
        by which point `rpc_id` to them is an engine error. That error was
        printing on every clean exit of the wifi harness.
      - **It also turned up a real rendering bug in the results card**, which
        had been invisible because Showdown's four rows had never been built on
        the losing side of the race: `MenuUI.stagger` goes through `pop_in`,
        which tweens `position:y` — and the rows live in a `VBoxContainer`,
        which OWNS its children's positions. `pop_in` reads `home` off a child
        the container has not laid out yet, records 0 for every row, and walks
        all four back to the top of the table stacked, where only the last one
        drawn is visible. The card looked like it had one row and the log said
        it had four. `main.gd:_fade_in_rows` replaces it and fades only —
        alpha is the half of that effect a container cannot fight.
- [x] **A client can ask for a rematch, and is told what it is waiting on.**
      Only the host can deal a roster, so the flow is: the client's card gets a
      REMATCH button in place of PLAY AGAIN, which sends `_net_rematch_request`
      and turns into "WAITING FOR THE HOST…"; the host's card carries "N of M
      ready for a rematch"; the host's PLAY AGAIN pulls the whole room into the
      next match through the `_net_start` it already broadcast, and
      `_start_from_roster` hides the results card at the far end. LOBBY works
      on both, and a host that leaves gets its clients "THE HOST LEFT — BACK TO
      THE LOBBY" written onto the same line, because the results card covers
      the `center_label` the old "HOST LEFT" was printed on.
      - Verified end to end in the two-instance harness with the two hooks
        added for it (`NS3_NET_KILL`, `NS3_NET_REMATCH`): client dies, card
        with four real rows and a REMATCH button, request goes up, host's card
        counts it, host deals, both instances come up in a new match's versus
        screen.
- [x] **iOS leads with join-by-IP.** An iPhone cannot receive the broadcast
      half of discovery without Apple's multicast entitlement — neither the
      replies a browsing phone needs nor the probes a HOSTING phone needs — so
      the games list there is permanently empty, and an empty list where the
      answer should be reads as a broken feature rather than an unavailable
      one. `Net.discovery_works()` is false on iOS and `room_screen.gd` swaps
      the two halves on it: JOIN BY IP first, in gold, with a green button,
      prefilled with the last address used and on a numeric keypad
      (`KEYBOARD_TYPE_NUMBER_DECIMAL` — the default layout hides the dot behind
      a shift); the list below it, carrying the one line that says why. Desktop
      keeps discovery first, because there it works.
      - The last address joined by hand is remembered across launches in its
        own `user://lan.cfg` (`Net.last_ip` / `remember_ip`). Typing an IPv4
        address on a phone keyboard is the entire cost of this flow and it is
        the same address every time in one house. Its own file rather than the
        save: the save is the player's progress and has no business carrying a
        LAN address.
      - The host's room screen now prints its own IP at 34 pt in gold under
        "Friends join by typing this address:", instead of as a clause in a
        muted hint line. On iOS that number is the only way anyone joins.
      - Shoot the iOS layout from a desktop with `NS3_FAKE_IOS=1
        NS3_MENU_SCREEN=wifi NS3_MENU_SHOT=<abs.png>`. Without it the one
        screen that only exists on a phone is the one screen this project
        cannot photograph.

## Ship

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

## Tooling & workflow

- [x] **Frozen-frame probes for stances and worn gear, and screenshots that
      survive an occluded window.** `tools/pose_probe.gd` freezes a kit at
      `CLIP:SECONDS` frames (plus the menu stage's straight-on view, plus the
      match ball from four sides) and `tools/gear_probe.gd` runs
      `Fighter._setup_gear`'s exact solve on a frozen frame — the live wind-up
      the sack sits on the foot for is 0.12 s, which no `NS3_SHOTS` burst could
      reliably catch before `prefix_7.06.png` names existed.
      - **Nine identical screenshots from one run.** The engine skips drawing
        while its window cannot draw (occluded by another app, on another
        Space, the display asleep), and `get_image()` then hands back the last
        frame it did draw. Both probes, `NS3_SHOTS` and `NS3_MENU_SHOT` now call
        `RenderingServer.force_draw(false)` when `DisplayServer.window_can_draw()`
        is false, and the probes ask for an always-on-top window; the harness
        runs pass `--always-on-top`. Verified with the window covered:
        thirteen shots, thirteen different pictures.
      - **`NS3_SHOTS` named every shot `prefix_<int>.png`**, so a burst inside
        one second overwrote itself. Whole seconds keep the old names; a
        fractional time keeps its decimals.

- [x] **The stalled match-feel branch is committed and pushed.** 1,982 lines
      across nine gameplay scripts, landed as `94f26b5` on 2026-09-06. They had
      sat uncommitted on top of `a68f3fd`, whose message is
      `WIP: match feel (stalled agent, unverified)`. **They were verified** —
      a headless Showdown sim, a headless Cup match, the wifi room screen, the
      join-code probe and a two-instance LAN Cup match all run with zero script
      errors, which is what made it safe to land. Until it was committed a second
      person cloning the repo got none of it, and **two finished features existed only on one machine** —
      Nobles Cup over wifi, and join codes. Both are written up in `done.md`
      under **Multiplayer**.
      - Modified: `cup_mode.gd`, `fighter.gd`, `haptics.gd`, `main.gd`,
        `menu.gd`, `net_play.gd`, `room_screen.gd`, `virtual_joystick.gd`,
        `tools/aim_probe.gd`. Staged deletion: `super_button.gd`. Untracked:
        `tools/code_probe.gd`.
      - **CLAUDE.md already documents both** — the same changeset updated it, so
        the working tree is self-consistent. It is only the *committed* CLAUDE.md
        that still describes join-by-IP and an unhostable Cup, which is one more
        reason to commit.

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
- [x] **Concurrent Godot runs have a real guard now: `Tools/godot.sh`.** It
      takes a lockfile keyed on the RESOLVED project directory and **refuses**
      (exit 75) rather than clearing, and it never kills anything. `mkdir` is the
      atomic primitive — a lockfile written with `>` has a window between the
      test and the write. A stale lock whose owner is provably dead is the one
      case where clearing is correct, and it is reclaimed silently.
      - **Per project, not per machine**, which is the whole point: three agents
        working in `.claude/worktrees/*` each have their own `.godot` cache and
        their own real lock, so they no longer block each other or the main
        checkout. Verified live against an agent's running Godot while the main
        project correctly reported free — the exact case CLAUDE.md warns costs
        "several minutes of dead waiting" with a naive `pgrep` wait-loop.
      - **A running Godot has already `chdir`'d into its own project
        directory**, and that is the fact the detection turns on. The first
        version resolved `--path godot` against the process cwd and got
        `<project>/godot/godot`, which does not exist — so every foreign Godot
        came back unresolvable and the wrapper cheerfully started a second one
        beside it. The cwd IS the answer; only an absolute `--path` is trusted
        ahead of it, for the moment before the chdir lands.
      - **The "is a person playing?" tell cannot be matched against the whole
        command line.** CLAUDE.md names a `-zsh` parent as the signal, but the
        Claude bash wrapper's own `shell-snapshots/snapshot-zsh-….sh` argument
        contains that literal string, so every agent job was being reported as a
        human. It reads the parent's `argv[0]` instead: a leading dash is a login
        shell (a person — do not kill), a ` -c ` is a script/agent job (kill the
        JOB, not the binary), anything else is unidentified.
      - `--wait <seconds>` blocks instead of refusing; `--status` reports the
        holder; `--no-lock` is the deliberate escape hatch for the **wifi
        harness**, which is two instances of the same project on purpose. Import
        once normally, then start both halves with `--no-lock`.
      - Allowlisted in `.claude/settings.json` beside the raw binary. Same
        prefix-matching limitation as that entry: `NS3_KIT=nova Tools/godot.sh …`
        does not match, because the env var comes first.
      - Still open: nothing forces its use. The wrapper only helps a caller who
        reaches for it, and every `NS3_*` line in this file still shows the bare
        binary.
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
