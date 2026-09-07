# Noble Stars — Roadmap to Beta

**Beta means:** a TestFlight closed group, roughly 10-25 invited testers, on
their own phones. Not a side-load over USB, which is how it installs today — see
**Phase 5**, where that difference turns out to cost more than it sounds like.

**There are no dates in this file, on purpose.** The whole game is about six
days old. Anything phrased as "three weeks" would be fiction, and a roadmap full
of fiction gets ignored. What this file commits to is **order** — what unlocks
what, and who holds it. Sizes (`S` / `M` / `L` / `XL`) are relative to each
other and nothing else.

**Two people.**

| | |
|---|---|
| **Ryder** | Gameplay. Kits, characters, balance, match feel, controls, modes, multiplayer, arena. Every character design is his call — nobody builds a fighter without him. |
| **Jackson** | Menus and assets, end to end. Owns `godot/scripts/menu/` as a developer *and* owns the art: he designs it, makes it, and implements it. Ryder does not touch the menu surface. |

**On-device testing is Ryder's hardware — but a screenshot is no longer a
handoff.** *(Corrected 6 Sep 2026; this paragraph used to call the device round
trip "the slowest feedback loop in the project" and budget for it.)*
`Tools/device_install.sh` puts a build on the phone in one command and
`Tools/device_shot.sh` drives it with any `NS3_*` hook and brings the PNG back,
so anyone with the repo and the cable can shoot the handset without asking
anybody to look at it. What still needs Ryder in the room is anything that has
to be **felt or played** — the haptics verdict (`todo 3.2`), how the sticks sit
under a real thumb, whether the game is fun. Those are the round trips to budget
for; a screenshot is forty seconds.

Item detail lives in [`todo.md`](todo.md) — references below like `todo 1.1` point
at it. Finished work and the reasoning behind it is in [`done.md`](done.md).
Read [`CLAUDE.md`](CLAUDE.md) before starting anything; most of what looks like a
free choice in this codebase has a rejected first attempt on record.

---

## The beta bar

Ten things. Beta is when all ten are true — not when a date arrives.

1. **12 fighters, none of them capsules.** Nine kits exist today, eight of them
   modelled (Ayaan landed 6 Sep — Jackson's export, skis and all). That is
   **three new characters** plus a model for Nova = **four GLBs**, and three
   fresh kit designs.
2. **Every fighter has real attack animations.** All seven modelled kits name an
   `attack` clip today, but they are **borrowed Meshy stock** — Hammy attacks
   with `baseball_pitching`, Anders with `Kick_a_Soccer_Ball`, Leon with
   `mage_soell_cast_3`. Two kits have **no `super` clip at all** and fall back to
   their attack. Twelve fighters need purpose-made attack and Super animations.
   See **D9** for who owns this.
3. **A third game mode.** Showdown and Nobles Cup are live; every other card is
   a locked dummy.
4. **Three maps per mode.** There is exactly **one** of each today —
   `Arena.SHOWDOWN_MAP` and `Arena.PITCH_MAP`, two hardcoded ASCII constants. At
   three modes that is **nine maps**, plus everything a plural implies: a
   registry, selection, names, and thumbnails. See **D11**.
5. **A party system, and matches start from it.** Not in the game in any form
   today. This is a menu surface *and* a change to how a match is launched, so it
   is the one beta item that lands on both owners at once. See **D10** — its
   answer changes the size by an order of magnitude.
6. **Wifi multiplayer playable.** Showdown over LAN works today. See **D4** for
   whether Nobles Cup has to be hostable too.
7. **Menus that are not sucky.** Jackson's call what that means; his redesign
   idea is the input the roadmap is waiting on (**D1**).
8. **A real progression system.** Trophies, coins, gems and Power Points are
   already banked and spent. Power levels, Star Powers and gadgets are named and
   **do nothing**.
9. **Spectating after death in Showdown.** Today a Showdown elimination frees
   your fighter and raises the results card on the spot — the match you were in
   carries on without you and you never see who won. Watching it out is both the
   normal battle-royale expectation and the thing that makes a lobby of friends
   worth being in.
10. **Better assets and much more polish overall.** Deliberately vague here and
    made concrete in Phase 4.

**Not in beta:** voicelines. They need nine real people in a room and are the
longest lead time in the project — they move to **Beyond beta**, but see **D7**,
because "not in beta" and "don't start yet" are different answers.

---

## Phase 0 — Unblock

*Nothing else can be judged until the game is on a phone at a readable size.
Every P0 in `todo.md` is in here.* **Nearly done — one item left, and it is the
one that is a design decision rather than a bug.**

| Owner | Item | Size | |
|---|---|---|---|
| ~~Ryder~~ | ~~Commit and verify the working tree~~ — **done**, `94f26b5`+`cf5a466` | S | — |
| ~~Ryder~~ | ~~Turn on Developer Mode~~ — **it was already on** | XS | `todo 1.4` |
| ~~Ryder~~ | ~~The match reaches the screen edges~~ — **done** | S | `todo 1.1` |
| ~~Ryder~~ | ~~The menu reaches the screen edges~~ — **done** | S | `todo 1.2` |
| **Jackson** | Onboarding: repo, Godot 4.7.2, the reimport hook, `Tools/godot.sh` | S | — |
| **Jackson** | **Text readable at arm's length — the menu's type scale** | M | `todo 1.3` |

**The working tree is committed and the phone-fit bugs are fixed and verified on
an iPhone 15.** `done.md` carries the reasoning; the short version is that the
menu was fitting its *whole stage* into the safe area and losing 13.9% of the
screen width to bars the same colour as its own background, and the match HUD
was placed at coordinates authored for a 1280-wide viewport that no shipping
device has. Both now lay out from `Session.safe_rect`, with the **picture
filling the display and only the chrome inset**.

**The menu's type scale is the one thing left, and it moved from Ryder's column
to a real decision on Jackson's system.** It is now measured rather than
guessed: the utility tier rendered at **6.2-8.0 pt** on the handset against
Apple's 11 pt floor for body text, roughly half. It has since moved to 26-30
stage px, which is **9.5-10.9 pt** — under the floor everywhere, rather than at
half of it. Clearing the floor needs about
30 stage px, which lands on the bottom of the display tier at 44 — so this is
**a redesign of the deliberate hole in the scale, not a multiply**, and it is
exactly the change CLAUDE.md's **Menu** section warns will flatten the design if
done blind. The match HUD's half of the same item was fixed alongside 1.1, since
its labels sit at 12-39 pt with no such doctrine attached.

**1.3 is the only thing left in this phase, and as of 7 Sep it is a decision
with numbers under it rather than an open question.** Onboarding is done, D1 is
answered, and Phase 2 ran a long way on it (Season, the roster, Shop and Events
are all rebuilt — see `done.md`). What the count says: 11 pt is **30.2 stage
px** and the utility tier's own ceiling is 30, so **all 39 sized utility labels
in the menu are under the floor** — the top of the tier by 1%, the bottom by a
third. Roster, Shop and Events were brought up to the tier's own 26 floor at no
cost. **Season is the one that proves this is a redesign.** Its page does not
scroll, its three blocks must total 816 stage px, and those heights were already
solved with the padding and head type cut to fit — so raising its Pass grid to
30 means showing **fewer tiers at once**, which is a decision about what the
Pass is for. That decision is Jackson's, and it is the last thing between this
project and a clean Phase 0.

**Jackson's onboarding, specifically.** Clone, then `Tools/godot.sh --path godot
--headless --import` once (a fresh clone must import before the project will
open). Three things that will otherwise cost him a day each, all of them in
CLAUDE.md: `--headless --import` is **not** a compile check and will import a
file that cannot parse, silently; never `class_name` anything Godot ships
natively; and run one Godot at a time per project, which is what
`Tools/godot.sh` enforces. Then read CLAUDE.md's **Menu** section start to
finish before changing a single token — the current design's every rule looks
arbitrary in isolation and is not — and its **Phone fit** section, which is
where 1.3's numbers come from and which explains why the stage and the chrome
are two different rectangles.

**And learn `Tools/device_shot.sh` early.** A menu change can be shot on the
actual handset in one command without the phone leaving Ryder's desk drawer, so
the type scale can be iterated against real device pixels rather than against a
desktop window that is lying to you about every one of them.

---

## Phase 1 — The roster

*Five models is the longest lead item that is actually in beta scope. It starts
now and runs underneath everything else.*

| Owner | Item | Size | |
|---|---|---|---|
| **Ryder** | Design three new fighters | M | **D2** |
| **Ryder** | Stat them, then build the kits | M | `CHARACTER_BUILDING.md` |
| **Ryder** | Meshy pass for Nova *(Ayaan is done)* | S | `todo 4.1` |
| **Ryder** | Meshy passes for the three new fighters | L | — |
| **?** | Real attack animations for all 12 fighters | L | **D9** |
| **?** | Super animations for the kits that have none | M | **D9** |
| **Jackson** | Portraits for the remaining four, wired through the menu *(Ayaan's is in)* | S | `todo 4.1`, pipeline 2 |
| **Jackson** | Decide the card medium, then produce the set | M | `todo 4.2`, **D5** |

**Nova first, ahead of the other three.** She is the sole starter, so her capsule
is the first thing every new tester sees, on the first screen they see. A beta
tester's first impression is a placeholder cylinder.

**The three new fighters are Ryder's designs and nobody starts one without
him.** Stat them with `CHARACTER_BUILDING.md` — health, speed, reload and range
come off the tier tables and **damage is derived from them, never picked by
taste**. The 5.5-tile on-screen range cap is a hard ceiling and is tangled with
the camera (Phase 4).

**Every fresh Meshy export goes through `python3 Tools/fix_meshy_glb.py` before
it is committed** — it repairs the material export, faces the model +Z and adds
the missing Idle clip. A fighter that throws what it holds needs
`--split-held-item left|right`. Re-cap the texture import at 1024 for characters,
or the bundle grows by ~7 MB per fighter.

**The attack animations are borrowed, and it shows.** Every modelled kit names
an `attack` clip, so this is not a missing feature — it is stock Meshy library
animation standing in for character animation. Hammy attacks with
`baseball_pitching`, Anders with `Kick_a_Soccer_Ball`, Leon with
`mage_soell_cast_3`, Kovacs with `Angry_Ground_Stomp_2`. Two of the seven have
**no `super` clip at all** and play their attack clip for it. Twelve fighters x
attack + Super is 24 clips, and the tuning floats beside each one
(`attack_speed`, `attack_seek`, `attack_fast_at`, `attack_end`) exist because a
borrowed clip's timing never matches the weapon's — purpose-made clips should
make most of that go away, which is a small mercy hiding inside a large job.
Note what is *not* wanted here: **death and hit animations are done in code
deliberately** (`_pop_out` and `_play_arrival`), and a toppling-over death was
tried and rejected, so no GLB needs one.

**Jackson's portraits are a script, not a drawing job.** `tools/render_portraits.gd`
shoots them off the GLBs on the menu stage's own rig, so a portrait and the live
fighter are lit identically and the art regenerates whenever a model changes.
Run it **without** `--headless`. The cards are the real question — see **D5**.

---

## Phase 2 — The menu, properly

*Jackson's block. Runs in parallel with Phase 3; they touch different files and
should not block each other.*

| Owner | Item | Size | |
|---|---|---|---|
| ~~**Jackson**~~ | ~~Write the redesign idea down~~ — done 6 Sep | — | **D1** answered |
| **Jackson** | Build it — layout, Season, roster and Shop are in; ability art and a phone look remain | M | `todo 5.1`, `todo 5.3` |
| **Jackson** | The party surface — the menu half | L | **D10** |
| ~~**Jackson**~~ | ~~Roster as tiles, not rows~~ — **done** 7 Sep, portrait tiles on kit-colour grounds | S | — |
| **Jackson** | Map select and map thumbnails | M | pipeline 2 |
| **Jackson** | Wire or delete the dead JSON | M | `todo 5.6` |
| **Jackson** | Draw the art the JSON already describes | M | `todo 5.7`, pipeline 3 |
| ~~Jackson~~ | ~~The app icon~~ — **done**, flat gold-on-ink in the menu's own language | S | — |
| **Ryder** | Decide what a power level changes | M | **D3** |
| **Jackson** | Wire progression once **D3** lands | L | `todo 5.4` |

**Nothing in this phase starts before the idea is written down.** "Not sucky
menus" is not a specification, and the current design is internally consistent
enough that a partial redesign will read worse than either the old one or the
new one. Write the idea into this file first (**D1**).

**Progression is split down the middle and that is deliberate.** What a level
*changes* is a balance decision — it touches `kits.gd`, which
`CHARACTER_BUILDING.md` derives damage from — so it is Ryder's. What a level
*looks like* is Jackson's. The wiring cannot start before the decision, and the
decision has no dependencies, so Ryder should make it early even though the work
lands late.

**The app icon is here rather than in Phase 5** because it is a flat vector
shape, it is script-drawable (pipeline 3), and it is the cheapest thing on this
list that changes whether a build looks like a real game on a home screen.

---

## Phase 3 — Modes, maps and multiplayer

*Ryder's block. Parallel with Phase 2, except the party, which is a seam.*

| Owner | Item | Size | |
|---|---|---|---|
| **Ryder** | Pick the third mode | XS | **D6** — blocks the build |
| **Ryder** | Build it | L | `todo 6.1` |
| **Ryder** | A map registry: more than one per mode | M | **D11** |
| **Ryder** | Author nine maps (three per mode) | L | **D11** |
| **Ryder** | Spectate after death in Showdown | M | bar item 9 |
| **Ryder** | The party surface — the plumbing half | L | **D10** |
| ~~Ryder~~ | ~~A client's death is silent and its HUD lies~~ — **done**, and with it the haptic layer in wifi play | S | — |
| **Ryder** | Client-side attack prediction | M | `todo 8.2` |
| ~~Ryder~~ | ~~Nobles Cup over wifi~~ — **already built**, see below | — | **D4 answered** |

**`cup_mode.gd` is the worked example for the third mode** and the shape is worth
copying exactly: everything mode-specific in one file, called from `main.gd` at
four points, with `cup == null` as the guard on every branch. That is what kept
Showdown's match loop untouched when Cup landed.

**The client-death bug is fixed** (6 Sep 2026), and it was worth more than its
size exactly as this said: the same root cause had the whole haptic layer off in
wifi play, so anyone testing multiplayer was testing a version of the game with a
feature silently missing. The general rule it produced is in CLAUDE.md's wifi
section — a client learns some things as numbers and others as events, and each
piece of feedback has to hang off whichever one it is.

### Already built — in the working tree, uncommitted

Two finished features were found in the uncommitted changeset during the audit
that produced this file. Neither was in any document. Both were verified this
pass rather than taken on trust.

**Nobles Cup over wifi is done.** This was listed as the largest item in beta
scope and as open decision **D4** — both were wrong. `net_play.gd` takes a
`room_mode`, `room_capacity()` returns 6 for Cup, and `main.gd` carries
`_net_cup_roster`, `_net_cup_down`, `_net_cup_goal`, `_net_cup_kickoff`,
`_net_cup_over`, `cup.adopt_net_match` / `apply_net_state`, and the ball's
carrier in the snapshot. Verified in the two-instance harness: the client
connected, took a 6-fighter roster, and rendered a live 0-1 scoreline with the
clock at 2:24 and the goal feed naming the scorer, with zero script errors.
**D4 is answered: yes, Cup is hostable.** The room screen already offers
`NOBLES CUP · 3v3 · up to 6` beside Showdown.

**Join codes replaced join-by-IP.** A four-character code that a friend reads
out across the room — `192.168.1.24` is `6PBA`. There is no server to look a
code up in, so the code does not *refer* to the address, it **is** the address,
compressed and scrambled across the code space. `tools/code_probe.gd` verifies
the codec in the engine that ships it (the seven-character form multiplies a
35-bit number by a 35-bit constant, which is where GDScript's 64-bit ints could
silently wrap): 65,536 exhaustive checks on 192.168.*, ~20,000 random each on
the other families, **zero bad**, and a mistyped four-character code decodes to
nothing 94% of the time rather than to somebody else's machine.

**This matters for the party (D10) more than for anything else.** A join code is
already most of what a LAN party invite is, and it works on iOS, where broadcast
discovery cannot without Apple's multicast entitlement. Whoever answers **D10**
should read `room_screen.gd` first — the LAN-party answer may be closer than it
looks.

**CLAUDE.md already covers both**, updated in the same changeset — the working
tree is self-consistent. It is the *committed* CLAUDE.md that still describes
join-by-IP and an unhostable Cup, which is one more reason to land the commit.

**Maps are a subsystem before they are content.** There is one Showdown map and
one Cup pitch, both hardcoded ASCII constants in `arena.gd`, and `_build` picks
between them with a single ternary on `map_mode`. Nine maps needs a registry, a
selection path, names (**D8** stops being optional the moment there is more than
one), and a thumbnail per map — which `tools/render_map.gd` already shoots, on
the match's own light rig, with `NS3_MAP_KIND=overview`. Build the registry
before authoring the content, or nine maps get authored against a shape that
then changes.

**Two hard-won rules govern what a map may be.** A Cup pitch is **mirrored on
both axes — every row is a palindrome** — because neither end may be the better
end; and the solid five-tile wall two tiles off each goal is what makes the mode
work, since nothing can be shot at the mouth from beyond it and the attack has to
come round the outside. Showdown maps are freer, but the gas ring assumes a
roughly square playable area and the bots' bush and cover scans assume terrain
is *sampled from the ASCII map*, so anything freed from the scene without going
through `Arena.open_at` keeps blocking pathing and ball bounces.

**Spectating is smaller than it sounds in Cup and larger in Showdown**, and the
reason is structural: **a Showdown elimination frees the fighter**, which is
exactly why the results card can show a per-player table in Cup and cannot in
Showdown. A spectator camera needs something left to follow. The wifi half is
already most of the way there and worth copying — a host's own death shows its
results card **while its sim keeps running** for whoever is still alive. Decide
whether spectating replaces the immediate results card or sits in front of it
with a way through.

**The party is the one item that lands on both owners at once.** Jackson owns
the surface, Ryder owns what it does, and they have to agree on the seam before
either starts. It also displaces `room_screen.gd`, which is explicitly "the one
corner the menu overhaul did not touch" and still uses the old `ui_kit.gd`
styling — so the party is where that finally gets rewritten rather than
restyled. **Its size depends entirely on D10** and nothing else in this file
varies as much.

---

## Phase 4 — Polish and balance

*"Much more polish" from the beta bar, made concrete. Most of it needs the
roster finished first, which is why it is here and not earlier.*

| Owner | Item | Size | |
|---|---|---|---|
| **Ryder** | Speed / camera / model scale — one decision | M | `todo 2.1` |
| **Ryder** | The balance pass, now across 12 kits | M | `todo 7.1` |
| **Ryder** | Sanjit's range | S | `todo 7.2` |
| ~~Ryder~~ | ~~A shot cannot be called off after aiming~~ — **done** | S | — |
| **Ryder** | Hammy's heat pips become one draining bar | S | `todo 3.4` |
| **Ryder** | Judge the haptics on a real phone | XS | `todo 3.2` |
| **Ryder** | The gas ring makes no sound | S | `todo 9.2` |
| **Ryder** | Per-kit weapon sounds | S | `todo 9.3` |
| **Jackson** | Named unlocks for every fighter without one | XS | `todo 5.5` |
| **Jackson** | The asset quality pass | M | bar item 10 |
| **Both** | Name the nine maps | XS | **D8** |

**The balance pass runs last and it runs at 60+ matches a side.** Both halves
are measured, not preference: the same A/B said damage was down 11% at 20
matches a side and flat inside 1% at 60, so twenty spawns per kit is noise; and
three new kits plus a progression system plus the scale decision each move the
baseline it measures against. Running it before those land means running it
twice.

**~~Speed, camera framing and model scale are one decision, not three items.~~
ANSWERED 7 Sep 2026 — made together, from play.** The taste call this was
waiting on got made in one session against a real build, and all three moved:
`SPEED_NORMAL` to 3.60 m/s (2.77 tiles/s, 1.15x Brawl Stars), `MODEL_SCALE` to
1.40, and the camera per-mode with Nobles Cup locked horizontally. It was right
that they are one decision — **exact speed parity read as "slow motion" mostly
because the models were oversized**, and the two were reported in the same
breath. What made it decidable ahead of Phase 4, against the note below, was
that the tile rescale forced the question anyway. See `SHOT_FEEL.md` §10 and
`done.md`.

**The fourth axis, also settled: the camera became per-mode.**
`SHOT_FEEL.md` §9.6 measured the Nobles Cup pitch at 15 tiles against a view
11.5 tiles wide at 16:9 and 14.0 on the phone — **the pitch is wider than the
screen on every display**, so both touchlines are never visible, where Brawl
Ball always shows the full width. Fitting it is a 1.31x pull-back, which shrinks
a fighter from 5% of screen width to 3.8% and drops weapon range from 48% of the
view to 37%. So it pulls the *same two levers this decision is about*, in the
opposite direction, for one mode only — which is exactly why it belonged in
here. **Pulling back was not enough on its own**: the camera also had to lock to
the pitch centre, because a wider window that still follows the player sideways
loses a touchline just the same. Stadium stands are still open — the pull-back
spends its new width on flat green surround plane, and that is now visible.

**Unlocks grow with the roster.** Four fighters have no named unlock today; three
new ones make seven. Whether they arrive on Trophy Road, through the pass, or
only through a Dawg Treat is a content decision, and it is Jackson's because it
is a progression shape rather than a balance one.

**"Better assets" is a real line item and it belongs to Jackson.** Everything
the game draws today that is not a character model is generated — the terrain,
the walls, the water, the gas, the bushes and every effect are fragment shaders
and per-frame `ImmediateMesh`, and all 28 sounds are synthesized at runtime.
That was the right call and should stay: the camera is a fixed steep top-down,
so a spray drawn flat in XZ reads from the only angle anyone sees, and the game
ships zero audio files. The quality pass is therefore **tuning the generators and
filling the holes the JSON already names** — badges, pins, avatars, skins, the
club badge, map thumbnails — not replacing the approach with art files. Where a
new asset is genuinely wanted, pipelines 2 and 3 in `todo.md` make it a script.

---

## Phase 5 — TestFlight

*The phase that the "closed group" answer created. It is bigger than it looks.*

| Owner | Item | Size | |
|---|---|---|---|
| **Ryder** | Switch the preset to distribution signing | M | see below |
| **Ryder** | App Store Connect: app record, bundle id, agreements | S | — |
| **Jackson** | Icon set, screenshots, store copy | M | — |
| **Both** | Privacy declarations and the first review pass | M | — |
| **Both** | First-run experience for someone with no context | M | — |

**Signing is the trap, and it is a trap this project has already been caught in
once.** The preset is `Apple Development` with `export_method` 1 (development)
for **both** configurations, and CLAUDE.md says in as many words that this is
correct "because this game is side-loaded onto phones and never shipped to the
App Store". TestFlight makes that sentence false. It needs App Store
distribution, which is exactly the `Apple Distribution` setting whose conflict
with `CODE_SIGN_STYLE = Automatic` **cost an evening and produced an error
message pointing at the wrong thing entirely** (`No Account for Team` — the
account was fine both times). Before changing a line: open the generated project
in Xcode and read the Signing & Capabilities pane, which says
`conflicting provisioning settings` in plain English where the command line does
not. And read the team off the artefact rather than trusting the preset —
`security cms -D -i <app>/embedded.mobileprovision` prints the truth.

**Budget for review.** The first TestFlight build goes through App Review even
for a closed group, and a rejection costs a round trip measured in days rather
than hours. Everything else in this phase can be prepared while Phases 1-4 run;
only the build itself has to wait.

**First-run matters more with 25 people than with 2.** A tester who has never
seen the game gets no explanation of three floating sticks, a shrinking gas
ring, or what a Dawg Treat is. Whether that is a tutorial, a hints pass, or
better copy on the screens that already exist is an open question — it is not
currently anywhere in `todo.md`, and it is the one beta-only piece of work in
this file.

---

## Open decisions

Each one blocks something. Owner is who decides, not who implements.

| | Decision | Owner | Blocks |
|---|---|---|---|
| ~~**D1**~~ | ~~What is the menu redesign idea?~~ **Answered 6 Sep — see below.** | Jackson | nothing |
| **D2** | Who are the three new fighters and what are their kits? | Ryder | Phase 1, and the balance pass |
| **D3** | What does a power level actually change? | Ryder | Progression wiring, `todo 5.4` |
| ~~**D4**~~ | ~~Cup hostable for beta?~~ **Answered — it is already built and verified.** | — | nothing |
| **D5** | Character cards: illustrations or renders? | Jackson | `todo 4.2` |
| **D6** | Which third mode? | Ryder | The largest item in Phase 3 |
| **D7** | Do voiceline bookings start now even though they ship after beta? | Ryder | Nothing in beta — everything after it |
| **D8** | What are the nine maps called? | Both | Map select, loading and versus screens |
| **D9** | Who owns character animation — Ryder or Jackson? | Both | 24 clips in Phase 1 |
| **D10** | Is the party LAN-only, or online with accounts and invites? | Ryder | The size of two Phase-3 items |
| **D11** | Three maps per mode — new layouts, or variants of the two that exist? | Ryder | Nine maps in Phase 3 |

**D1 is answered — a layout, and then a material.** Jackson's idea, written
down the day it was built: keep the programme page's type (Anton and Barlow,
ink and gold), put it in rounded cards on a painted stage lit in the fighter's
own colour, and change what goes where.
**Five zones.** Top-left is who you are — on home the avatar badge, name and
trophies; on every pushed screen the back arrow in a small square, so the
corner always means "up". Top-right is coins and gems as a compact readout
(icon and figure, nothing else) and then the menu as three bars in a square,
never the word MENU. The flanks stay the fighter's numbers and abilities, with
room under each ability for the preview button that is coming. Bottom-left is
the nav — ROSTER, SEASON, SHOP, WIFI as picture-over-word tabs owned by the
shell, on every screen, the current one lit gold. Bottom-right is the mode
plate and PLAY, one gap apart, on the nav's baseline, PLAY the biggest thing on
the screen. Under the fighter's feet, one hint; nothing else near him.
**Cards, bars and a lit stage** (the 6 Sep mockup). The flanks became rounded
cards with a one-pixel edge: five stat bars filled against the roster's best,
two ability cards with a glyph medallion each, a record card. The stage is the
icon pack's painted hall, recoloured by its own light so every fighter stands
in a pool of their kit colour — nine stages from one painting, and a kit may
name its own. **No stray rules** — spacing separates blocks, and the only
lines left are content (a threshold that turns gold, the rows of the record).
**The utility type went up to 26–30 stage px**, which is `todo 1.3`. Not used
from the pack: any face it invents.
**Rewards are pictures of themselves** (the 7 Sep Season mockup, the third pass
and the one that reaches the pushed screens). Season's Trophy Road and Nobles
Pass are cards in the same material — a glyph, the amount under it, and a state
line that is a tick, a padlock or the word CLAIM — on a drawn track whose dots
light as far as you have got, with the Pass as a Free/Premium grid ringed at the
tier you are on. Setting a reward as a word was the earlier rule and it was
wrong about what a rail is scanned for: which KIND, not how much. Shop is the
last screen still wearing the overhaul's layout at a larger size.

**D7 is the one that is easy to answer wrongly by not answering.** Voicelines
need nine real people to physically show up, and that is a scheduling problem
rather than a work problem — it is the only thing in this project whose lead
time is not under anyone's control here. Deciding "after beta" is fine.
Deciding nothing means it starts after beta *and then takes months*.

**D2 has a standing rule attached:** every character is Ryder's design. Nobody —
including Claude — builds one without him.

**D9 exists because character animation sits exactly on the seam.** It is an
*asset*, which is Jackson's; it is *gameplay-facing* and lives in `kits.gd`
beside the timing floats that make a swing land when the projectile spawns,
which is Ryder's. Twenty-four clips is too much work to leave unowned, and the
worst outcome is each assuming the other has it. One of you takes the whole
column.

**D10 is the largest unknown in this file.** "A party" spans two wildly different
projects. **LAN party** is the existing ENet host/join reshaped into a party
surface — the plumbing exists, it is host-authoritative already, and this is a
Phase-3-sized job. **Online party** — friends, invites, presence, parties that
survive across matches — needs accounts, a server, and a backend that does not
exist in any form; the entire multiplayer stack today is `net_play.gd` doing
LAN broadcast discovery on port 42537, and on iOS even that half does not work
without Apple's multicast entitlement, which is why the phone leads with
join-by-IP. Answer this before anyone estimates the party, because the two
answers differ by an order of magnitude and one of them is bigger than
everything else in this file combined.

**D11 decides whether "nine maps" is content or a project.** Three genuinely new
layouts per mode is nine authored maps plus nine balance passes — the layout *is*
balance, especially in Cup, where the goal wall does the defending. Variants of
the two that exist (different bush and water placement, same skeleton) is a
fraction of that and still reads as three maps to a player. There is no wrong
answer, but the roadmap sizes very differently under each.

---

## Beyond beta

Not scoped, not sequenced, kept so it is not rediscovered as a surprise.

- **Voicelines** (`todo 9.1`). Nine fighters x spawn / attack / Super / defeat /
  victory, recorded by the people the characters are based on. See **D7**.
- **More music** (`todo 9.4`). Two tracks ship. Wants a victory sting and a
  second battle track so Cup and Showdown do not sound identical.
- **An iOS haptics plugin** (`todo 3.3`). The ceiling on how good the haptics can
  feel. Godot's iOS backend emits one event type and one parameter, so every tap
  the game can currently make is the same buzz at a different length. Only worth
  it if the verdict from `todo 3.2` on a real phone is "the rhythm is right, the
  texture is wrong".
- **Interest management** (`todo 8.4`). Deliberately deferred. The next lever if
  a mode ever wants a roster bigger than ten, and not before.
- **A GDScript language server** (`todo 11.2`). Marginal at 13k lines.
- **Modes four and beyond**, skins, and a public TestFlight or App Store release.
- **Fighters 13+**, which is the same pipeline as **D2** and gets cheaper every
  time it is run.

---

## What this replaced

`plans.md` is deleted. It held five lines — two future character ideas, Sanjit
and Kovacs, both of which have since shipped as full kits. Nothing was lost, and
future character ideas now live in **D2** and **Beyond beta** where they have an
owner and a phase.
