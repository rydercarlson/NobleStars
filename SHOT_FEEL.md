# Shot Feel — how Brawl Stars tunes projectile speed, and where we differ

Research note, Sept 2026; **revised 7 Sep 2026** — §§6–8 have all shipped and
the live plan is now **§9**. Source data: the Brawl Stars wiki's raw infobox
fields pulled for 89 brawlers (`MovementSpeed`, `AttackSpeed`, `AttackRange`,
`AttackWidth`), plus our own `kits.gd`. Brawl Stars measures speed in units where
**300 units = 1 tile/second**, and range and hitbox width directly in tiles.

The short version: **everything in our game happens about 2.3× too fast for the
size of the fighters.** Movement, projectile speed and range are all high
together, which produces two separate complaints at once — shots are *hard to
aim* at a strafing target, and simultaneously *impossible to dodge* once fired,
because they arrive in 0.38s. The fix is a coordinated slowdown, not a single
knob. That retune is §6, and it shipped. **What is still open is §9.**

---

## 1. The one metric that matters

Everything about "can I hit someone who is strafing" collapses into one
dimensionless number:

```
lead / hit-width  =  range / (ratio × hit_width)

    ratio     = projectile speed ÷ mover's speed
    hit_width = target hitbox width + projectile hitbox width
```

Read it as: **how many target-widths does the enemy slide sideways while your
shot is in the air, at your maximum range.** Below ~1.0 you can point and shoot;
at 2.0+ you must consciously lead, and a small aim error is a clean miss.

The derivation matters, because it kills an intuition:

```
lead = flight × move = (range / speed) × move
lead / hit_width = (range × move) / (speed × hit_width)
                 = range / ((speed/move) × hit_width)
```

**Movement speed cancels out.** Making fighters slower does *not* make shots
easier to land — only the *ratio*, the *hit width*, and the *range* move it.

### …and a second one, for the other half of the feel

`lead/hit` says whether a shot is hard to *aim*. It says nothing about whether
it can be *dodged*, and that is the other half of what makes Brawl Stars feel
the way it does:

```
dodge window = flight time − reaction time      (reaction ≈ 0.25 s)
```

| | flight @ full range | dodge window |
|---|---|---|
| Brawl Stars | 0.67s (IQR 0.53–0.76) | **0.42s** (IQR 0.28–0.51) |
| Hammy today | 0.38s | **0.13s** |

Both games move the target about one body-width in that window, so on paper the
dodge is equally available. In practice human reaction is a *distribution* with
roughly ±0.1s of spread — at 0.42s of slack you reliably dodge and it feels
skilful; at 0.13s the variance dominates and it feels random. From the
shooter's side, a shot that lands before the target can respond reads as
hitscan. **That is why Hammy beams people from across the map.** This metric is
what makes lowering absolute speeds necessary, not just the ratio.

---

## 2. What Brawl Stars actually does

67 direct-fire brawlers (throwers excluded — they are their own class):

| metric | min | p25 | **median** | p75 | max |
|---|---|---|---|---|---|
| movement, tiles/sec | 1.93 | 2.40 | **2.40** | 2.57 | 2.73 |
| projectile, tiles/sec | 6.33 | 10.67 | **12.00** | 13.33 | 16.67 |
| **ratio** (proj ÷ move) | 2.32 | 4.24 | **4.86** | 5.56 | 7.76 |
| range, tiles | 2.00 | 6.00 | **8.33** | 9.00 | 10.00 |
| flight time at full range | 0.17s | 0.53s | **0.67s** | 0.76s | 0.93s |
| **lead / hit-width** | 0.16 | 0.75 | **1.05** | 1.44 | 2.27 |
| angular tolerance at full range | 2.96° | 4.52° | **5.44°** | 7.58° | 36.9° |

Throwers (Barley, Dyna, Tick, Grom, Sprout, Willow, Spike, Emz…) sit at ratio
~2.4, flight ~1.16s, lead/hit ~2.8 — they are *supposed* to be dodgeable, and
the AOE is what makes them land.

Three structural facts worth stealing:

**a) A brawler's hitbox is one tile wide.** Straight from the official wiki
Beginner's Guide: *"A Brawler's hitbox is slightly larger than a single tile of
cover… shown by the ring around their feet, not the Brawler themselves. This
ring is relatively the same size for every Brawler."* So in Brawl Stars, "tiles"
and "body-widths" are the same unit. Cover blocks, brawlers, and the grid are
all one scale. That is why their numbers are so legible.

**b) Projectile speed varies — but never with range.**

```
corr(range, projectile speed) = 0.05      <- essentially none
corr(range, flight time)      = 0.86
speed spread: 6.33 – 16.67 tiles/s, IQR 10.67 – 13.33, median 12.00, cv 0.17
```

So it is a real variable, just a narrow one: the middle half of the roster sits
within ±11% of the median, and even the extremes only run 0.53× to 1.39×. What
it is *not* is a function of range — Piper's shot is no faster than Shelly's,
it just flies further. Speed is a per-character flavour knob (Ash and Frank at
16.7 tiles/s feel instant; Spike and Poco at 7–8 feel floaty), never a
compensation for how far the attack has to travel. Treat it as **one base speed
for the game, ±20% per kit for character.**

**c) Projectiles are big.** Median `AttackWidth` across the 47 brawlers that
have one is **1.00 tiles — a projectile is as wide as a brawler.** Colt's bullet
is 0.67 tiles, two-thirds of a body. Their bullets are chunky glowing bolts, not
BB pellets, and that is a hit-registration decision as much as an art one.

---

## 3. Where we were (before the §6 retune)

`TILE = 2.0 m`, fighter capsule radius `0.45` → body 0.90 m, normal move 7.0 m/s.

| attack | ratio | flight @ range | lead/hit | angular tol |
|---|---|---|---|---|
| Nova pellet | 3.6 | 0.36s | **2.14** | 3.8° |
| Leon button | 3.1 | 0.45s | **2.45** | 3.7° |
| Hammy shot | 4.1 | 0.38s | **1.92** | 3.6° |
| Nova Super | 3.9 | 0.41s | 2.01 | 3.7° |
| Hammy Super | 3.4 | 0.54s | 2.08 | 4.0° |
| Sanjit Super (boomerang) | 1.9 | 0.69s | **3.21** | 4.7° |
| Tony Super | 6.7 | 0.31s | 1.27 | 3.4° |
| Tony lob | 3.0 | 0.58s | 1.33 | 7.1° |
| Anders sack | 1.7 | 0.50s | 1.05 | 15.5° |

Head to head on the three basic direct-fire attacks:

| | Brawl Stars | Noble Stars | |
|---|---|---|---|
| projectile ÷ move speed | 4.86 | 3.57 | **0.73×** |
| **lead / hit-width** | 1.05 | 2.14 | **2.02×** |
| angular tolerance | 5.44° | 3.72° | **0.68×** |
| projectile width ÷ body width | 1.00 | 0.31 | **0.31×** |

And our projectile widths as a fraction of a fighter:

| | width | body-widths |
|---|---|---|
| Nova pellet | 0.28 m | 0.31 |
| Leon button | 0.40 m | 0.44 |
| Tony shell | 0.44 m | 0.49 |
| Hammy shot | 0.48 m | 0.53 |
| *Brawl Stars median* | — | **1.00** |

---

## 4. What is already correct — don't touch it

- **Range vs. screen.** Brawl Stars 3v3 maps are 21 tiles wide with the whole
  map on screen; max weapon range is 10 tiles = 48% of screen width. Our screen
  is 11.5 tiles wide (16:9) and the weapon cap is 5.5 tiles = 48%. Identical.
  The 5.5-tile cap in `CHARACTER_BUILDING.md` §4 is right.
  **Caveat added 7 Sep 2026:** the *ratio* is identical, but the other half of
  their claim — "with the whole map on screen" — is true of Showdown and **false
  of Nobles Cup**, whose pitch is wider than the view on every display. See
  §9.6; it is the one place this section's identity does not survive.
- **Arena size.** Their Showdown map is 60×60 tiles = 60 body-widths across.
  Ours is 30×30 tiles at 2 m = 67 body-widths. Same.
- **Ammo and reload.** They run 3 pips at 1.3–2.4s each (median 1.5s); we run 3
  pips at 1.0–2.6s (normal 1.8s). In band.
- **Movement while firing.** Both games let you move freely while attacking.

---

## 5. What is wrong, ranked by how much it costs

### 1. The player's tap-fire does not lead. Bots do. *(fixed — §7.1)*

`main.gd:_auto_aim_fire` aims at `target.global_position` — the enemy's *current*
position. Bots aim through `bot_brain._aim_point`, which leads by 0.15–0.45 in
matches and 0.85 in the sim. Against a target strafing at 7 m/s:

| attack | flight | aim error | in hit-widths |
|---|---|---|---|
| Nova pellet | 0.36s | 2.52 m | **2.1** |
| Leon button | 0.45s | 3.18 m | **2.4** |
| Hammy shot | 0.38s | 2.66 m | **1.9** |

Anything past 0.5 hit-widths is a clean miss. **Tap-to-shoot at range currently
cannot hit a moving enemy at all,** while bots can hit you. Brawl Stars'
auto-aim leads. This is the single highest-value fix and it costs one function.

### 2. Projectiles are ~3× too thin relative to the fighter.

0.31 body-widths against their 1.00. This is why shots visibly pass through
people and why the angular tolerance is 3.7° instead of 5.4°. Pure `kits.gd`.

### 3. The ratio is 3.6 where theirs is 4.9.

Shots hang in the air 0.38s at full range where Brawl Stars hangs 0.67s — but
their targets move 2.4 body-widths/sec and ours move 7.8, so despite the shorter
flight our shots are far harder to land.

### 4. Our per-kit speed spread is 4×; theirs is ±20%.

Ratios in our roster run from 1.7 (Anders) to 6.7 (Tony Super). Variation is
correct and wanted — theirs varies too — but ours is four times as wide, and
some of it is compensating for range rather than expressing character. Sanjit's
boomerang at ratio 1.9 with no AOE has a lead/hit of 3.21, the worst number in
the game; Tony's Super at 6.7 arrives in 0.31s with a 0.06s dodge window, which
is the same "beam" problem as Hammy.

### 5. Cover is twice as coarse as the fighter.

A wall block is 2.0 m against a 0.90 m fighter — 2.2 body-widths. In Brawl Stars
a wall block *is* a body-width. Peeking around a single block, threading a gap,
and juking behind cover are all half-resolution for us. This is an arena
decision (`TILE`), not a kit one, and it is the expensive one.

### 6. Pacing: we cross the screen 2.7× faster.

23 m ÷ 7 m/s = 3.3s to cross the visible width; Brawl Stars takes ~8.7s. Our
fighters move 7.8 body-widths/sec against their 2.4. This is a real difference
in how frantic the game reads — but per §1 it is **not** why shots miss, so
treat it as a separate, later decision.

---

## 6. What shipped

Four coordinated moves. None works alone — that is why the first pass at this
doc (speed *up*, fatten the pellets) was wrong: it would have fixed `lead/hit`
and made the beam problem worse.

```
fighter size     x 1.44     hitbox 0.90 -> 1.30 m wide (capsule radius 0.45 -> 0.65)
movement         x 0.80     Normal 7.0 -> 5.6 m/s  (= 55% of the original FEEL, see below)
projectile       ~3.1 x the firer's move speed (17.1 m/s at Normal), +/-20% for character
attack cooldown  0.22 x reload (0.40s at Normal) — new; there was none at all
range            trimmed; weapon cap stays 5.5 tiles, Super cap 6.5 -> 6.0
```

**Growing the fighter is what actually shortened range.** Range only matters in
body-widths, and widening the fighter by 44% pulled every reach in by the same
factor without touching most of the tile numbers: the 5.5-tile cap went from
12.2 body-widths (past Brawl Stars' hard maximum of 10) to 8.5, and Nova's
"Medium" went from 10.0 — Piper's reach — to 6.6, which is mid-band. The tile
values only needed trimming at the short end.

### The dial — and read it in body-widths, never m/s

**Perceived speed tracks body-lengths per second, so widening the fighter slows
the game down at a fixed m/s.** This cost two tuning passes to notice. The
original game was 7.0 m/s on a 0.90 m fighter = 7.78 body-widths/s; going to
4.0 m/s on a 1.30 m fighter reads like 40% of that, not the 57% the m/s number
suggests. Judge the dial by the "feel" column, not the m/s one:

| `SPEED_NORMAL` | vs. original m/s | body-widths/s | **feel** | dodge window | screen |
|---|---|---|---|---|---|
| 2.80 (on a 1.10 m body) | 0.40x | 2.55 | 33% | 0.34s | 8.2s |
| 4.00 (on a 1.30 m body) | 0.57x | 3.08 | 40% | 0.28s | 5.8s |
| **5.60** | **0.80x** | **4.31** | **55%** | **0.25s** | **4.1s** |
| 6.30 | 0.90x | 4.85 | 62% | 0.20s | 3.7s |
| 7.00 | 1.00x | 5.38 | 69% | 0.16s | 3.3s |

Every projectile speed is a multiple of a speed tier (`SPEED_NORMAL * 3.05`),
so raising a tier speeds its shots up with it and **aiming difficulty does not
change** — `lead/hit` has no move-speed term. What moves is the reaction window,
and the relationship is exact:

```
dodge window = (lead/hit) x hit_width / move - 0.25
```

So going faster has to be **paid for with fatter projectiles** — the only free
variable left once range is capped by the screen. That is why the radii roughly
doubled in this pass. Brawl Stars' median projectile is a full body-width wide
so there is room, but not unlimited room, and that ceiling is what ultimately
caps how fast fighters can move in a game this size.

**Tune `SPEED_NORMAL`; never hand-edit projectile speeds.** Past about 6.3 the
window drops under 0.20s and shots start reading as hitscan again.

### Speed tiers (`kits.gd`)

| Tier | was | now | body-widths/s | Brawl Stars |
|---|---|---|---|---|
| Very Slow | 5.6 | **4.48** | 3.45 | 1.93 |
| Slow | 6.3 | **5.04** | 3.88 | 2.20 |
| **Normal** | **7.0** | **5.60** | 4.31 | **2.40** |
| Fast | 7.7 | **6.16** | 4.74 | 2.57 |
| Very Fast | 8.4 | **6.72** | 5.17 | 2.73 |

We run about 1.8x Brawl Stars in body-widths per second. That is a deliberate
choice, not a miss — and the projectile ratio (3.1 against their 4.9) is the
price paid for it, not an error.

### Range tiers (`CHARACTER_BUILDING.md` section 2)

Unchanged in tiles at the long end — the fighter growing is what moved these in
the units that matter. Body-widths are against the new 1.30 m fighter.

| Tier | was (tiles) | now (tiles) | now body-widths | Brawl Stars |
|---|---|---|---|---|
| Very Short (melee) | 1.5 – 2.0 | **1.2 – 1.5** | 1.8 – 2.3 | 2.0 – 3.0 |
| Short | 2.5 – 3.0 | **2.2 – 2.8** | 3.4 – 4.3 | 4.0 – 5.3 |
| Medium | 3.5 – 4.5 | **3.5 – 4.3** | 5.4 – 6.6 | 6.0 – 8.0 |
| Long | 5.0 – 5.5 | **4.8 – 5.5** | 7.4 – 8.5 | 8.7 – 10.0 |

We end up slightly shorter-reaching than Brawl Stars relative to character size,
which is the deliberate consequence of chunkier fighters on a 23 m screen: the
screen cap in section 4 binds before the body-width band does.

### Per-attack table (shipped values)

| attack | move | range (t) | radius | speed | ratio | flight | dodge | lead/hit |
|---|---|---|---|---|---|---|---|---|
| Nova pellet | 5.60 | 4.3 | 0.44 | 17.1 | 3.05 | .50 | .25 | 1.29 |
| Nova Super | 5.60 | 5.0 | 0.52 | 18.5 | 3.30 | .54 | .29 | 1.30 |
| Tony lob | 5.04 | 5.5 | 0.42 | 15.1 | 3.00 | .73 | .48 | 0.74 |
| Tony Super | 5.04 | 6.0 | 0.56 | 19.7 | 3.90 | .61 | .36 | 1.27 |
| Henry sweep | 5.04 | 1.5 | — | — | — | — | — | — |
| Henry dash | 5.04 | 3.4 | — | 16.1 | 3.20 | .42 | .17 | — |
| Sanjit combo | 6.72 | 1.4 | — | — | — | — | — | — |
| Sanjit Super | 6.72 | 5.0 | 0.64 | 19.2 | 2.85 | .52 | .27 | 1.36 |
| Kovacs clap | 4.48 | 2.4 | — | — | — | — | — | — |
| Kovacs leap | 4.48 | 3.6 | — | — | — | — | — | — |
| Leon button | 5.60 | 4.8 | 0.46 | 17.9 | 3.20 | .54 | .29 | 1.35 |
| Leon Super | 5.60 | 4.8 | 0.66 | 11.8 | 2.10 | .82 | .57 | 0.49 |
| Anders sack † | 5.60 | 3.5 | 0.44 | 16.8 | 3.00 | .42 | .17 | — |
| Anders Pop Off | 5.60 | 2.8 | 0.48 | 15.7 | 2.80 | .36 | .11 | 0.22 |
| Hammy shot | 5.60 | 5.5 | 0.62 | 20.2 | 3.60 | .55 | **.30** | 1.20 |
| Hammy Super | 5.60 | 6.0 | 0.70 | 18.5 | 3.30 | .65 | .40 | 1.35 |
| Ayaan slalom | 6.16 | 4.5 | 0.46 | 18.8 | 3.05 | .52 | .27 | 1.43 |
| Ayaan Downhill | 6.16 | 5.5 | — | 11.7 | 1.90 | — | — | — |

**† Anders' sack was retuned after this table was first written**, and the row
above is the current `kits.gd` value, not the shipped-in-§6 one (which was 2.8
tiles at ratio 1.70, flight .59, dodge .34). It is **deliberately outside the
dodge-window target** and has no `lead/hit`, because a sack is a *landing-spot*
weapon: it is timed against how far the target drifts against its 1.9 m landing
radius, never by the reaction-window rule that sets projectile speeds. At 1.70x
a third of every sack landed on bare floor. The full reasoning is in the kit's
own comment in `kits.gd` — the same exemption Tony's shell takes.

**Ayaan's row is computed on his AXIAL speed, not his shot speed, and at the top
of his range band.** His range is a band and so is his swerve: the shot ends
where it was aimed, from 2.8 tiles (a 58° braid) to 4.5 (one 27° arc) — see
CHARACTER_BUILDING §7. The row reports the 4.5 end, because that is where a
dodge window is hardest to earn, and there the 27° swerve means the shot closes
on its target at `J0(0.47) = 0.95` of the 18.8 m/s it actually travels: 17.8
m/s. The braided end gives up 24% instead of 5%, but only over 2.8 tiles, so it
never binds. lead/hit at 1.43 sits just inside the 1.45 top of the band, which
is what fixes his ratio at 3.05 — the house 3.1 pushes it over.

Anything that turns speed into a flight time has to go through `Kits.aim_speed`
rather than reading `weapon.speed`, or it leads him short — `bot_brain._aim_point`
and `main._aim_lead` both do.

**Caveat on the AOE rows.** `lead/hit` treats the blast radius as hit width,
which overstates forgiveness for anything that resolves where it *lands* rather
than along its path — a lob's AOE only helps if the shell arrives near the
target, so a longer hang amplifies lead error instead of being paid for by the
radius. Tony's lob is timed against target movement instead; see its kit note.

Targets: **dodge ≥ 0.22s · lead/hit 0.80–1.45 · projectile width ≤ 1.0
body-widths** (Brawl Stars' median). Ratio is deliberately *not* a target — see
above. Lobs and arcing Supers are the exception again, down at 1.7–2.2, and pay
for it with AOE.

**Hammy: dodge window 0.13s → 0.28s.** His ratio of 5.2 is the highest basic
attack in the roster, which is correct — he is the sniper, and Brawl Stars gives
its snipers the fast end of the band too. He just stops being hitscan.

The lobs get *unlocked* by this rather than nerfed. `CHARACTER_BUILDING.md`
warns that a slow arc lands on nothing — that was measured at 7 m/s. At 4 m/s
Tony's shell can hang a full second and still land, so it drops from 19 to
10.8 m/s and reads as artillery again.

---

## 7. What moved with it

All of the following shipped in the same pass.

1. **The player's tap-fire now leads** (`main.gd:_aim_lead`). It aimed at the
   enemy's *current* position, so at range a tap could not hit a strafing enemy
   at all — off by roughly twice the target's width — while bots, which have led
   since `bot_brain._aim_point`, could. Full lead, because this is the player's
   aim assist rather than a deliberately sloppy bot. Instant-hit styles fall
   through to a zero flight time and aim where the target stands.

   > **SUPERSEDED 7 Sep 2026 — this is being reversed on purpose; see §9.1.**
   > It fixed a real fairness bug and introduced a worse design one: a tap that
   > leads perfectly is strictly better than aiming, which makes the skill the
   > game is built around the slow way to do what the button does for free.
   > Brawl Stars' auto-aim fires at where the enemy *is*. The fairness half of
   > the complaint is answered by bringing the bots' lead down with it (§9.2),
   > not by giving the tap a perfect one. The analysis above stays because the
   > numbers in it are still what make the case *for* §9.1: they are exactly
   > how far a no-lead tap misses by.
2. **Run clips are speed-matched to ground speed.**
   `fighter.gd:update_animation` played the run clip at a fixed rate, so the
   feet skated — forward at 7 m/s, and they would have skated backward at 4.
   `_anim.speed_scale` is now `velocity.length() / SPEED_NORMAL`, clamped
   0.6–1.6, which fixes the long-standing foot-slide and gives each speed tier
   its own stride. `play_attack_animation` resets it to 1.0, because the attack
   clips' timings are tuned frame-by-frame against their own `speed`.
3. **Models scale with the hitbox.** `MODEL_SCALE` (1.44 then; 1.40 now, §10) keeps the GLB
   silhouettes matching what projectiles actually collide with. `_ground_feet`
   multiplies its lift by `_model.scale.y` — the sink is measured in model
   space but applied in the parent's, so without that the feet float.
4. **Dashes and leaps came down with everything else.** `begin_dash` uses
   `weapon.speed` as the dash velocity, so Henry's would have become a 12×
   teleport; it is now `SPEED_SLOW * 4.5`.
5. **Bot fire cadence derives from the kit.** `_fire_interval` was a flat
   `randf_range(1.0, 1.6)` that ignored the kit, so a Slow-reload bot tried to
   shoot faster than it could reload and ran dry while a Fast-reload bot sat on
   full ammo. It is now `reload × randf_range(0.85, 1.15)`, floored at the
   attack cooldown.

### Still open

- **Bot match lead.** `LEAD_MATCH_MIN/MAX` (0.15–0.45) was tuned against 0.38s
  flights. At ~0.55s flights a 0.15-lead bot misses by less than it used to, so
  it grazes rather than whiffing — arguably the intended sloppiness, but worth a
  look now that everything else has settled. **Now coupled to §9.1 and no longer
  optional:** with the player's tap at zero lead, bots at 30–90% of a correct
  lead out-aim the player's own aim assist. See §9.2.
- **Melee is judged, not measured.** `A` is derived from measured hit rate for
  ranged kits, but the sim inflates melee (bots walk in straight lines: Henry
  reads 93% in-sim against 85% from play), so Henry, Sanjit and Kovacs keep
  hand-set values. Their numbers need a playtest, not a longer sim.
- **Hammy's uptime.** His delivery is fine at 83% and his damage is now
  correctly priced, but he gets 5.1 attacks a life on 3500 health and finishes
  last. The damage formula has no lever for that; the fix is his health tier,
  which is a character decision.
- **Wall height.** Walls are 1.5 m boxes and fighters are now ~2.5 m of scaled
  model. Brawl Stars keeps cover and brawlers about the same height; ours no
  longer do, so cover reads shorter than it plays.
- **`TILE` is still 2.0 m** against a 1.30 m fighter, so cover is 1.5
  body-widths where Brawl Stars' is 1.0 (§5.5). Closer than the 2.2 it was, and
  no longer worth an arena re-author on its own.

### Done since

- **The arena is 39×39** — *61×61 as of §10* — = 60 body-widths at the 1.30 m fighter, matching Brawl
  Stars' Showdown map in the unit that matters. `Tools/gen_showdown_map.py` is
  now parameterised — terrain is authored in design units on the original
  33-grid and scaled by `S = N/33`, with `N = 60 × FIGHTER_RADIUS`. Watch the
  density read-out on any future resize: radii scale but a wall clump is a fixed
  number of *tiles*, so the field grows by S² while wall cover does not.
- **Damage re-derived** from measured hit rates — see
  `CHARACTER_BUILDING.md` §3, which now bands `A` off `hits/atk` instead of
  judging it.

---

## 8. Unload speed — shipped

> **This section was a proposal, and the proposal shipped.** It is kept in
> full because the *reasoning* is the valuable part, but read the whole section
> in the past tense: as of 7 Sep 2026 the attack cooldown, the `unload` stagger
> and the kit-derived bot cadence are all in the tree. See "What shipped" below
> for where each one lives. Do not build any of it a second time.

The problem it solved: `main.gd:_fire_player` called `Fighter.consume_ammo()`,
which did exactly one thing:

```gdscript
func consume_ammo() -> bool:
    if ammo < 1.0: return false
    ammo -= 1.0
```

**There was no minimum gap between attacks anywhere in the codebase.** A full
magazine left the barrel as fast as the player could flick the aim stick.

| kit | ammo × dmg | as a healthbar | dumped in (before) | time to refill |
|---|---|---|---|---|
| Henry | 3 × 1620 = 4860 | **97%** | ~0.2s | 6.6s |
| Nova | 3 × 1450 = 4350 | **87%** | ~0.2s | 5.4s |
| Hammy | 3 × 1250 = 3750 | 75% | ~0.2s | 6.6s |
| Tony | 3 × 1240 = 3720 | 74% | ~0.2s | 6.6s |
| Sanjit | 3 × 1230 = 3690 | 74% | ~0.2s | 4.2s |
| Leon | 3 × 1224 = 3672 | 73% | ~0.2s | 4.2s |
| Kovacs | 3 × 1200 = 3600 | 72% | ~0.2s | 5.4s |

Nearly a full healthbar with no reaction window, then four to seven seconds of
nothing. That is not a fight, it is a coin flip on who flicks first.

### Two knock-on effects it had

**The reload tier did nothing it claimed to.**
`CHARACTER_BUILDING.md` §2 says reload "decides whether a kit feels like one
committing swing or a stream of chip damage… pick it for feel." It could not,
because with no cooldown every kit was maximum burst regardless of reload —
reload only set how long you waited afterwards. **The attack cooldown is the
missing mechanic that makes the reload tier mean what the doc says it means**,
and that is the main thing this change bought.

**Bots and the player were on completely different clocks.**
`bot_brain._fire_interval` is `randf_range(1.0, 1.6)` — a flat roll that ignores
the kit entirely. So a bot fires roughly once a second and never bursts, while
the player empties three pips instantly. It also means a Slow-reload bot (Tony,
2.2s) tries to fire faster than it reloads and just runs dry, while a
Fast-reload bot (Sanjit, 1.4s) under-fires. The cadence should derive from
`reload` plus the new cooldown, not from a constant.

### What Brawl Stars does

Two separate timings, both of which we are missing:

1. **Attack cooldown** — the minimum gap between consecutive attacks.
   Documented at **0.5s** for Piper, Carl and Nani; **0.1s** for Amber (her
   continuous flamethrower) and ~0.15s for Lily. Piper's reload is 2.3s, so her
   cooldown is **0.22 × reload**. "Slow unload" is a named, deliberate weakness
   in their design — the wiki's own tips tell you to dive 8-Bit, Pam, Rosa,
   Buzz, Ash, Frank, Griff, Lola, Rico and Eve *because* of it.
2. **Inter-projectile spacing inside one attack** — Ruffs was nerfed to 200ms
   between his two shots (from 50ms); Larry to 0.3s (from 0.15); Griff's row of
   coins unloads over 1.0s. This is what makes a multi-shot attack read as a
   *stream* rather than a wall of geometry appearing at once.

### What shipped — the cooldown

**Attack cooldown = 0.22 × reload**, matching Piper, tiered off the existing
reload tiers so it stays a single derived number:

| Reload tier | reload | **cooldown** | 3 pips dump in |
|---|---|---|---|
| Very Fast | 1.0 | **0.22** | 0.44s |
| Fast | 1.4 | **0.30** | 0.60s |
| Normal | 1.8 | **0.40** | 0.80s |
| Slow | 2.2 | **0.50** | 1.00s |
| Very Slow | 2.6 | **0.55** | 1.10s |

**Sustained DPS is untouched.** Three pips refill in 4.2–6.6s and dump in
0.4–1.1s, so the cooldown is never the limiting factor at steady state — it caps
*burst only*. The damage formula in `CHARACTER_BUILDING.md` §3 needs no change.

Paired with the §6 movement cut this is where the rhythm comes from: Nova's
burst takes 1.0s, during which the target covers 3.0 m — 3.3 body-widths, plenty
to break the second and third shot. Before the change it was ~0.2s and 1.4 m.

**Inter-projectile spacing** for stream-style attacks — a new optional `unload`
key on the weapon dict, seconds between projectiles:

| attack | pellets | `unload` | total | why |
|---|---|---|---|---|
| Leon buttons | 6 | **0.05** | 0.25s | a cone of six is Colt's stream, not a shotgun |
| Nova pellets | 5 | **0** | instant | a shotgun fan; Shelly fires hers simultaneously |
| Sanjit combo | 2 | 0.22 | 0.22s | already staggered in `perform_attack` |

### Where it lives — as built, verified 7 Sep 2026

It followed a pattern that already existed twice — the `Style.MELEE` combo
staggers with `create_timer(0.22 * i)`, and Kovacs' clap uses a `delay` key.

- **`kits.gd`**: `ATTACK_COOLDOWN_RATIO := 0.22` and
  `attack_cooldown_for(reload)`. One derived number, so a new kit gets its
  cooldown from its reload tier with nothing to set.
- **`fighter.gd`**: `attack_cooldown` (set from the kit's `reload` in
  `_ready`) and `next_attack_at`. `consume_ammo(game_now)` refuses while
  `game_now < next_attack_at` and stamps it on success. **Gating it inside
  `consume_ammo` is what makes it cover the player, the bots and the net path at
  once** — clients route through the host's `_fire_player` — and it is why there
  is no cooldown check at any call site. Both reset paths — `respawn` and
  `kickoff_restore` — clear it back to `-1.0`.
- **`main.gd:perform_attack`**: the `unload` stagger, `weapon.get("unload",
  0.0) * p`, with the instance-id capture rather than a node reference, because
  a fighter can die mid-unload. Leon's buttons take a separate path
  (`_launch_button_shot`, default `0.035`) so the stream trails behind a moving
  shooter instead of the whole spread dragging with him.
- **`bot_brain.gd`**: `_fire_interval = maxf(Kits.attack_cooldown_for(reload),
  reload * randf_range(0.85, 1.15))` — floored at the cooldown, so a bot cannot
  ask to fire faster than the gate allows.
- **The Super bypasses the cooldown**, as flagged. It is charge-gated, not
  ammo-gated, so routing it through `consume_ammo` would have made a tapped
  Super silently eat the gap after a basic attack. The comment above
  `consume_ammo` says so, to stop it being "fixed".

---

## 9. The plan — what is still not Brawl Stars

Written 7 Sep 2026, after verifying every claim in §§5–8 against the working
tree. §§6–8 have shipped in full. What follows is ranked by feel per unit of
work.

- **9.1 / 9.2 are decided and unbuilt** — one branch and one constant band, and
  they must land together.
- **9.3 is cheap and uncontroversial** — one constant and a screenshot.
- **9.4 / 9.6 are Ryder's taste calls**, and they are the same call: both move
  fighter size and range-as-a-fraction-of-screen, which is `todo.md` 2.1.
- **9.5 is deliberately not now**, with the reason recorded so it is not
  reopened by accident.

### 9.1 Auto-aim must STOP leading — decided, not yet built

**This reverses §7.1, deliberately.** §7.1 taught the player's tap to lead
because bots led and the player did not, and at 0.38s flights a tapped shot at
range could not hit a strafing target at all. That fixed a fairness bug and
created a worse design bug: **a tap that leads perfectly is strictly better than
aiming**, so the skill this game is built around — drawing a lane with the aim
stick — became the slow way to do something the button already did for free.

Brawl Stars does not do this. Its auto-aim fires at where the enemy *is*, which
is exactly why auto-aim misses a moving target at range, why drag-aim is what
good players do, and why auto-aiming a thrower is a known bad play. **The tap is
the convenience option, not the correct one.**

It is also the rule this project already committed to one screen earlier.
CLAUDE.md, on the aim indicator: *"it used to preview the auto-aim's pick as a
lane to the chosen fighter plus a ring around their feet, which is a lock-on
marker — it hands you the target for free and makes tapping the obvious play,
when aiming is meant to be the thing you get good at."* A leading tap is that
same lock-on, moved out of the indicator and into the shot.

**The change is one branch.** `main.gd:_tap_plan`:

```gdscript
var aim: Vector3 = _aim_lead(player, target as Fighter, weapon) if target is Fighter \
        else target.global_position
```

becomes `target.global_position` unconditionally. `_aim_lead` then has no
callers and goes with it. **Keep `Kits.aim_speed`** — `bot_brain._aim_point` is
its other caller and still needs it (it is what stops Ayaan being led short).

**What it costs, in the units §1 sets up.** A no-lead tap misses a full-speed
strafing target by exactly `lead/hit` body-widths — the §6 table's last column,
which the retune deliberately parked between 0.80 and 1.45. Lead error is
linear in range, so the tap degrades smoothly rather than switching off:

| distance | miss, in hit-widths (Nova, lead/hit 1.29) | verdict |
|---|---|---|
| full range (4.3 t) | 1.29 | clean miss |
| ~70% | 0.90 | miss |
| ~40% | 0.52 | graze |
| ~25% | 0.32 | hit |

That is the intended shape: **tap to brawl, aim to snipe.** Note it also
restores a real cost to firing at max range, which is where a shotgunner should
not be winning by tapping.

**Movement speed does not rescue it** — §1, `lead/hit` has no move-speed term —
so 9.1 and 9.4 are independent and can be decided in either order.

**Watch list for the playtest, not blockers.** The three landing-spot kits take
the biggest change, because their attack resolves where it *lands* rather than
along its path: Tony's lob (0.73s hang), Anders' sack (0.42s) and Kovacs' leap
(0.48s fixed airtime). A tapped one now lands where the target was. That is
authentic — it is precisely what auto-aiming Barley does — but it is a real cut
to those three taps, and Anders was retuned *toward* landing reliably only a
pass ago (see his kit note and the § 6 footnote). If one has to keep its lead,
**Kovacs' leap is the defensible exception**: it is travel, not a shot, and it
is the one case where "where they are" is guaranteed wrong by half a second.

### 9.2 Bot lead comes down with it — same pass

Already flagged in §7's "Still open"; 9.1 forces it.
`bot_brain.LEAD_MATCH_MIN/MAX` is 0.15–0.45s against flights that are now
~0.5s, so a match bot leads **30–90% of the correct amount**. With the player's
tap at 0%, bots aim better than the player's own aim assist — which is §5.1's
original complaint with the sign flipped.

The comparison that matters is bot-lead against **player-drag**, not against
player-tap: a bot has no tap, `_aim_point` *is* its manual aim. So bots should
keep leading. Widen the band downward rather than scrap it, so a meaningful
share of the roster aims where you actually are:

```
LEAD_MATCH_MIN  0.15 -> 0.00
LEAD_MATCH_MAX  0.45 -> 0.40
```

**`LEAD_SIM` (0.85) must not move.** The balance sim wants bots that connect, so
that `hits/atk` measures the weapon and not the bot — that column is what
`CHARACTER_BUILDING.md` §3 bands damage off.

Measure, do not eyeball: `NS3_SIM=60 NS3_SIM_SPEED=2 --headless`, and check
`hits/atk` against each kit's projectile count before and after.

### 9.3 Walls are shorter than the fighters behind them — cheap, do it

§7's "Still open" and `todo.md` 2.1 are describing one thing from two ends.
`Arena.WALL_HEIGHT` is **1.5 m**; `tools/size_probe.gd` measures every rigged
model at **2.29–2.40 m** tall. Cover comes up to a fighter's chest, so it reads
as a hurdle while mechanically blocking line of sight completely (the LOS ray is
at y = 1). **Brawl Stars keeps cover and brawlers about the same height**, which
is most of why peeking reads as peeking there.

CLAUDE.md settles the risk: *"Wall height is purely visual — `Lob` is a
`Node3D` with no collision and arcs over walls logically, `begin_leap` sweeps
terrain itself, and both the LOS ray (y = 1) and every projectile (y = 1)
already sit inside a 1.5 m box. `Arena.WALL_HEIGHT` can be retuned on looks
alone."* So this is a constant and a screenshot.

Raise toward ~2.2 m and shoot it with
`Godot --path godot --script res://tools/render_map.gd`, `NS3_MAP_KIND=game`
(the real match lens). **Not `--headless`** — the dummy driver writes empty
PNGs. Three things to judge in the shot rather than reason about: whether a
raised wall now hides the fighter *behind* it at the 60° camera (the point),
whether it hides the fighter *in front* of it (the cost), and whether Cup's goal
frame — deliberately taller than `WALL_HEIGHT` — still reads as taller.

### 9.4 The movement dial — the big one, and Ryder's call

This is `todo.md` 2.1, and §6's dial table is the decision aid. We ship
`SPEED_NORMAL = 5.60` = **4.31 body-widths/s against Brawl Stars' 2.40**, which
§6 records as *"a deliberate choice, not a miss."* It is the single largest
remaining difference in how the game reads, and it is one constant.

| `SPEED_NORMAL` | body-widths/s | vs Brawl Stars | dodge @ Nova | screen cross |
|---|---|---|---|---|
| **5.60 (today)** | 4.31 | 1.80× | 0.25s | 4.1s |
| 5.04 | 3.88 | 1.62× | 0.28s | 4.5s |
| 4.48 | 3.45 | 1.44× | 0.32s | 5.1s |
| 2.80 | 2.15 | 0.90× | 0.45s | 8.2s |

Three things make it cheaper than it looks, all already true:

- **Every projectile speed is a multiple of a speed tier**, so shots come down
  with it and **`lead/hit` does not move at all** (§1: no move-speed term).
  Aiming difficulty is untouched by this knob — only the dodge window moves.
- **Slowing down is free in the dimension that constrains speeding up.** §6:
  going faster must be paid for with fatter projectiles, and the projectile
  width ceiling (1.0 body-widths) is what caps speed. Going slower just hands
  the dodge window back.
- **Run clips already speed-match ground speed** (§7.2), so feet do not skate at
  a new tier and no animation work falls out of it.

What it actually costs is arena crossing time and how frantic Showdown reads —
taste — plus re-measuring damage if hit rates move, since
`CHARACTER_BUILDING.md` §3 bands `A` off measured `hits/atk`. **Tune
`SPEED_NORMAL`; never hand-edit projectile speeds** (§6).

Do not decide it from a screenshot: `NS3_SIM=60 NS3_SIM_SPEED=2 --headless` for
the balance half, a played match for the feel half.

### 9.5 Not now: `TILE`, and why

§5.5 is still true — cover is 2.0 m against a 1.30 m fighter, **1.54
body-widths where Brawl Stars' is 1.00** — and still not worth an arena
re-author on its own, which is §7's own conclusion. Two reasons to leave it:
`Tools/gen_showdown_map.py` is parameterised on `FIGHTER_RADIUS` and would
regenerate, but every hand-authored map would have to be re-drawn by hand
(`Arena.PITCH_MAP` is a palindrome on both axes *by contract*); and **9.3 buys
most of what this is really complaining about** — cover that does not read as
cover — for one constant and no re-author.

Revisit only if 9.4 lands and the arena then feels coarse at the new pace.

### 9.6 Nobles Cup should be framed like Brawl Ball — pulled back, with stands

Ryder's observation, 7 Sep 2026: Brawl Ball's camera sits farther back and
wider than the rest of Brawl Stars, and the pitch is ringed by stadium
furniture. Both halves check out, and the first one is a measured defect.

**The Cup pitch does not fit on screen, on any display.** `Arena.PITCH_MAP` is
15 × 23 tiles = **30 m wide**. The camera (`Arena.MATCH_CAM_OFFSET`
`(0, 91.4, 52.8)`, `MATCH_CAM_FOV` 7°, `KEEP_HEIGHT`) sits 105.6 m out at 60°
and covers a 12.91 m perpendicular vertical span, so its width is aspect-driven:

| display | view width | pitch width | off screen |
|---|---|---|---|
| 16:9 desktop | 23.0 m (11.5 t) | 30 m (15 t) | **3.5 tiles, 23%** |
| iPhone 15 (2.168:1) | 28.0 m (14.0 t) | 30 m (15 t) | **1.0 tile, 7%** |

**You can never see both touchlines.** In Brawl Stars 3v3 — Brawl Ball included
— you always can; that is §4's own source. This is why the mode reads as
scrolling rather than as a pitch, and it is a stronger complaint than the
scenery one.

**Fitting it costs the two things todo 2.1 is already about.** To put 15 tiles
across a 16:9 frame the camera goes to 138.0 m — a **1.31× pull-back**, offset
`(0, 119.5, 69.0)` — and then:

| | today | fits the pitch | + 1 tile margin |
|---|---|---|---|
| view width | 11.5 t | 15 t (1.31×) | 17 t (1.48×) |
| weapon range as % of view (§4) | **47.8%** | 36.7% | 32.4% |
| fighter as % of screen width | **5.0%** | 3.8% | 3.4% |

Brawl Stars sits at 48% and 8–10%. So pulling back moves *both* numbers away
from them in order to fix a third thing they also do. **That is not an argument
against it — it is the reason this belongs inside `todo.md` 2.1 rather than
beside it.** 2.1 already says movement speed, camera framing and model scale are
one decision; this adds a fourth axis (the camera becomes per-mode) and pins the
pull-back to a matching `Kits.MODEL_SCALE` rise, which is the same lever 2.1
already names. Note 2.1's blocker does not apply here: *zooming in* is blocked
by the range cap, and this is the opposite direction.

**The stands are not decoration — they are what makes the pull-back viable.**
Past the map edge is `Arena.SURROUND_COLOR`, a flat green plane with a
near→far gradient running out to `SURROUND_MARGIN` (46 m). A 1.31× pull-back
spends its new width on ~3.5 more tiles of that flat green per flank, so on its
own it reads as *a smaller game on a bigger lawn*, which is worse than the
problem. Bleachers, a barrier and sponsor boards ringing the pitch are what turn
the extra width into a stadium, and they are also what tells you where the
touchline is once the pitch no longer runs off the screen edge.

**Where it would go.** Three notes, all verified this pass:

- `Arena._playable_rect()` already exists and already drives the floor shader's
  pitch markings, so it is also the rectangle to ring — stands derive from it
  rather than from `PITCH_MAP` row numbers, the same rule `_build_goal` follows
  for `goal_mouths`.
- **The camera is a `const`, used in four places** (`main.gd:986`, `3369`,
  `3720`, and `_ready`), and `tools/render_map.gd` reads
  `Arena.MATCH_CAM_*` too — CLAUDE.md's rule that anything rendering the arena
  must use `Arena.make_sun()` / `make_environment()` applies to the camera for
  the same reason. Per-mode framing means promoting it to a value set once at
  `build_match`, not branching at each use.
- Cup-only, gated on `map_mode == "cup"`, so Showdown's framing — which §4 says
  is right — does not move.

**Judge it in a shot, not in this table.**
`Godot --path godot --script res://tools/render_map.gd` with `NS3_MAP=cup`
and `NS3_MAP_KIND=game` shoots the real match lens; **not `--headless`**, which
writes empty PNGs. The question a screenshot answers and arithmetic does not is
whether a fighter at 3.8% of screen width is still readable at the 60° pitch —
that is the number that decides how much pull-back is affordable.

### Verified correct this pass — do not re-check

Three things that look like they should be shot-feel bugs and are not:

- **A projectile's visual is exactly its hitbox.** `projectile.gd:_ready` builds
  the `SphereShape3D` and the `SphereMesh` from the same `weapon.radius`, and
  the material is emissive. It cannot look thinner than it hits, so "shots pass
  through people" (§5.2) is fully answered by the §6 radii and is not also an
  art bug.
- **The attack cooldown covers bots, the player and net clients at once**,
  because it is gated inside `Fighter.consume_ammo` rather than at a call site
  (§8). The Super deliberately bypasses it — it is charge-gated, and making it
  wait would silently eat the gap after a basic attack.
- **Ammo recharges continuously** — `ammo += delta / reload`, one pip per
  `reload` seconds — which is what Brawl Stars does. It is not a per-pip timer,
  and it does not need to become one.

---

## 10. The rescale — 1 tile = 1 fighter (shipped 7 Sep 2026)

§9 is now history: 9.1, 9.2, 9.3 and 9.4 all shipped in one pass, together with
the change §5.5 had been asking for since the first draft and §9.5 had deferred.

**The move.** `Kits.TILE` 2.0 m → **1.30 m**, which is exactly
`2 * FIGHTER_RADIUS`, so **one tile is one fighter**. Tile counts grew to keep
the world the same physical size: Showdown 39x39 → **61x61** (79.3 m, was 78),
the Cup pitch 15x23 → **21x33** (Brawl Stars' own 3v3 size).

Everything authored as `X * TILE` was multiplied by 1.54, so **nothing moved in
metres**. What moved is what the number *means*: `X` tiles used to be `X × 1.54`
body-widths and is now `X × 1.00`. That is the whole point — every Brawl Stars
figure can now be compared to ours by reading it.

The range re-tier looked like it fell out as arithmetic rather than taste —
converting today's reach into body-widths put every kit inside a named Brawl
Stars tier with no judgement needed. **It did not survive contact with the
screen**, and that correction is §10.3.

**Speed went to parity, and then came back up.** `SPEED_NORMAL` 5.60 → 3.12
(2.40 tiles/s, Brawl Stars' own median) → **3.60 m/s = 2.77 tiles/s**, 1.15x
theirs, crossing the visible width in 7.6 s against their 8.7. Exact parity
came back from play as *"genuinely moving in slow motion"*. The other four tiers
now *derive* from it, so there is one dial. §6 recorded our old 1.8x pace as "a
deliberate choice, not a miss"; this still reverses that, just not all the way.
`lead/hit` did not move at any point, because it has no move-speed term.

**`MODEL_SCALE` went 1.44 → 2.0 → 1.40, and the 2.0 is the part worth
remembering.** It was sized so a fighter's silhouette filled its hitbox ring —
checkable in one screenshot, and wrong: that optimises WIDTH, and our models are
humanoid at ~1:2 width:height against Brawl Stars' 1:1.2 chibi, so it blew the
height out to 2.5 tiles against their 1.5–2.0. Played as *"characters feel
utterly massive"*. **Match height against the grid, not width against the
ring** — and note the grid had already done the work, the same model going from
1.18 tiles tall to 1.85 when `TILE` shrank, with no scale change at all.

**The two compound, and were reported together.** Perceived pace is
body-LENGTHS per second, so an oversized model reads as slow motion at a
movement speed that is numerically correct. Do not tune one without the other.

**Auto-aim stopped leading** (§9.1) and the bot band came down to 0.00–0.40
(§9.2). The hitbox ring is now drawn in **every mode**, and Nobles Cup pulls the
camera back 1.19x *and locks it horizontally* so both touchlines are always
visible.

### What had to be scaled by hand, and what deliberately did not

The rule that fell out: **time constants stay, distance-per-second constants
scale, tile-denominated distances multiply by 1.54.**

- **Stayed** — reload tiers, `ATTACK_COOLDOWN_RATIO`, ammo, the gas cadence, and
  `unload`. All were already inside Brawl Stars' band in absolute seconds (§4).
  `unload`'s *spatial* gap does change: a six-button stream spreads over 0.85
  tiles instead of 0.60, which reads as more of a stream.
- **`RUN_CLIP_SPEED` stays, and it looks like it should not.** It is the speed
  the Meshy clips were *authored* at, so `velocity / RUN_CLIP_SPEED` is the
  physically correct stride at any tier. The real limit is the clamp: 0.35, and
  `SPEED_VERY_SLOW` now lands at 0.357. **We are one step from skating feet.**
- **Knockback stays, in metres.** `IMPULSE_TRAVEL` makes every `knockback` a
  displacement, and the decay is a fixed ~0.109 s — it is an *impact*, not
  travel. 1.52 m for Anders' 14 is 1.17 body-widths, inside Brawl Stars' band.
  Scaling it would have been wrong.
- **The ball is travel, so it time-dilated** — `KICK_SPEED`, `STOP_SPEED` and
  `DRAG` all derive from `Kits.SPEED_NORMAL`, so the dial **cancels out of
  `kick_range()`**: speed changes how long a kick takes and never how far it
  goes. Retune distance with `DRAG` against `KICK_SPEED`, and pace with
  `STOP_SPEED`. See §10.1 — the ball needed far more than dilation.
- **The leap dilated** (`Fighter.LEAP_SECONDS` 0.48 → 0.86). A fixed airtime
  over a preserved distance would have made every mobility Super nearly twice
  the escape it was, relative to running.
- **`TILES_PER_SHRINK` 2 → 3**, because it is counted in tiles: at 2 the ring
  needed 15 steps instead of 10 on a 61-tile map and closure went 126 s → 186 s.

### The bug this created, and why the sim could not see it

**A fighter is exactly as wide as a tile, so a one-tile corridor had ZERO
clearance and you jammed.** The old 2 m tile gave 0.70 m of slack. Showdown has
88 one-tile passages and the Cup pitch 6; measured afterwards, **849 of 2625
open tiles could not fit a fighter at all** — a third of the map.

Fixed with `Arena.TILE_COLLISION_SHRINK` (0.75): terrain *collision* is inset
inside the tile it is *drawn* on, so a one-tile corridor is 1.62 m of collision
against a 1.30 m fighter. Brawl Stars does the same thing — its movement
collider is smaller than its hitbox ring, which is why brawlers squeeze through
one-tile gaps.

**Doing it on the wall rather than the fighter is load-bearing.** The fighter's
capsule is *also* its hurtbox (`projectile.gd` sweeps against it), so narrowing
the fighter would have shrunk `hit_width`, silently retuned every `lead/hit`
figure in this document, and made the new feet-ring a lie. From the outside the
two are identical: a fighter ends up the same distance into the wall's drawn box
either way, and the models are narrower than the capsule so nothing new pokes
through.

**`NS3_SIM` cannot catch this class of bug, and did not.** Bots path on the
ASCII grid and slide along walls, so they route *around* a gap they cannot fit
through; the balance table looked healthy and no match ever ended on gas
closure. It took a person driving a stick straight at a gap. What the sim *did*
show, once there was something to compare against, was the second-order damage:
`hits/atk` fell for all nine kits, with `atk/spawn` **down** (fewer chances to
shoot) and scenery hits **up** (Hammy 47% → 67%) — fighters wedged in cramped
spots. Two wrong explanations were tested and discarded first: point-ray
blocking was identical old vs new (75.1% vs 75.8%), and so was swept-sphere
blocking at a real projectile radius (85.2% vs 85.1%), which rules out the map.

**`tools/fit_probe.gd` is the instrument** — it places a fighter's own capsule
at every open tile and asks the physics server whether it overlaps. Verified to
report the failure it was written for: 849 unfittable tiles at shrink 1.0, zero
at 0.75. Run it after any change to `TILE`, `FIGHTER_RADIUS`,
`TILE_COLLISION_SHRINK` or either map:

```sh
NS3_MAP=showdown Tools/godot.sh --path godot --headless --script res://tools/fit_probe.gd
```

Its own first version reported the *entire map* unwalkable, because the ground
slab is on the walls layer with its top at exactly the height a capsule bottoms
out. It excludes the slab now. **An instrument that cannot fail is worthless —
this one was checked by reintroducing the bug.**

---

### 10.3 Range came back down — the cap is the SHORTEST visible direction

Adopting Brawl Stars' range band was the one part of the rescale that had to be
undone. Their 6–10 tiles fits their camera; **it does not fit ours.**

Measured on the match rig (105.6 m out, 7° vertical FOV, 60° pitch), from the
player at screen centre:

| direction | visible |
|---|---|
| **up-screen** | **5.54 tiles** ← binding |
| down-screen | 5.94 tiles |
| sideways, 16:9 | 8.83 tiles |
| sideways, iPhone | 10.77 tiles |

`CHARACTER_BUILDING.md` §4 had capped weapons at the **wide axis** — 8.5 tiles —
and that is the wrong axis. A weapon fires in every direction, so the cap is the
*smallest* of the four.

**But "no shot may leave the frame" is too strong, and Brawl Stars does not obey
it either.** Measured against their own numbers: range ÷ vertical-half is
**1.43 for them** and was **1.53 for us**. A Piper shot up the screen leaves
their frame by about three tiles, exactly as ours did. The ratios are nearly
identical — what actually differs is that **our camera shows ~82% of the ground
theirs does** (17.7 × 11.5 tiles against roughly 21 × 14).

So the defensible rule is not about your own shot. It is:

> **You should not be hit by someone you cannot see.**

Symmetric, and it lands near the same number without pretending the outgoing
half matters.

**The caps settled at 6.5 tiles for weapons and 8.0 for Supers** — 1.17x and
1.44x the visible radius. The Super cap is 1.44x on purpose: `range` is total
PATH length, so a bouncing Super spends its reach on the detour, and Hammy's
bank shot is meant to carom somewhat off screen and come back. **Only the sniper
belongs near the ceiling.** He sits at 6.5 against the next-longest kit at 5.3,
and out-ranging the roster is the whole of what a sniper is. His shot was
narrowed to 0.50 (0.77 body-widths, against a Brawl Stars median of 1.0) and
sped up to pay for the reach; the shot-feel numbers improved rather than
degraded, lead/hit going 0.78 -> 0.94 from just below the band into the middle
of it.

**Only what poked out came down.** The first attempt reverted *every* range to
its pre-rescale tile number, melee included — and the sim caught it inside one
run: **Sanjit 11.3% → 2.9%, Henry 10.0% → 3.1%**, because a 1.4-body-width reach
means a melee kit is nearly overlapping before it can swing. Melee was never a
visibility problem; it sits deep inside the frame. V.Short and Short are
unchanged, and only Nova, Ayaan, Leon, Tony and Hammy were capped.

Two things deliberately did NOT revert, and the distinction is the rule worth
keeping:

> **AOE is measured against a BODY. Range is measured against the SCREEN.**

So blast radii kept their metres (Tony's is still 1.08 body-widths) while ranges
came down 35%. `BUSH_REVEAL` stayed for the same reason — it is a concealment
radius, not a reach. Bot `_engage_range` came down *with* the ranges, because it
is an acquisition radius sized against them.

**We now reach materially shorter than Brawl Stars at every tier, and that is
forced rather than chosen.** If their ranges are wanted, the lever is the
camera — showing more ground — and that runs straight back into `todo.md` 2.1,
because pulling back shrinks the fighters again.

#### Tony: a range cut is not a Tony nerf

He went 8.46 → **4.6 tiles**, Long to Medium, roughly half his old reach — and
won **27.3% of his spawns afterwards against 26.6% before.** Nothing happened.

**Because the formula pays a range cut back in damage.** `G` goes 0.85 → 1.00,
which is +18% damage, and that exchange rate is exactly what cancelled the
nerf. It is not a bug in the formula so much as a mispriced rate for a weapon
whose AOE meant it barely needed the range it was being charged for.

So his damage is now **held at 1459, deviating from the formula on purpose**,
justified the way §3's sanity checks are justified: measurement overrules the
band, and +4.2σ above a 1-in-9 baseline across two runs at two different ranges
is as clear as that evidence gets.

#### Read the noise floor before reading the table

At 60 matches each kit gets ~65 spawns, so on a 1-in-9 roster **1σ is 3.9
points and anything between 3.3% and 18.9% is noise.** Three of the mid-table
"swings" between consecutive runs here were entirely inside that band and were
briefly taken for signal. Compute it before comparing two sims.

---

### 10.1 Nobles Cup, and the two things only play could find

**The camera had to LOCK, not just pull back.** Brawl Ball never scrolls
sideways — both touchlines are always visible. The 1.19x pull-back fits 21 tiles
in the frame, but the camera still *followed* the player in X, so it slid a
wider window along a pitch that was still wider than it. Pulling back without
locking loses a touchline just the same, only more slowly.

Locking it then rendered the pitch **visibly tilted**. `look_at` was still
aiming at the player while the position was pinned to the pitch centre, so the
camera yawed to face them — and because rotation is fixed at match start, that
skew held for the whole match. **Position and look target must come from the
same anchor.**

**A kick ran 15.3 m the whole time CLAUDE.md described it as "~7 m, a pass, not
a shot from anywhere".** A 2.2x gap between documented intent and code, and
nothing caught it because the camera only ever showed two thirds of the pitch
width. Locking the camera exposed it inside one match. Settled at 8 tiles after
feeling both edges — 11.8 played as "way too far", 6.0 as "too little".

> **A number nobody can see is a number nobody can check.** The camera was
> hiding a balance bug, not just framing the pitch badly.

**And the ball was slower than a runner — it always had been.** Reported as
"kick still too slow" *after* the launch speed had already been cut twice for
it. The launch was never the problem:

| tuning | distance | time | avg speed | |
|---|---|---|---|---|
| original, pre-rescale | 11.8 t | 5.6 s | 0.76x run | runner beats the ball |
| after the first cut | 6.0 t | 3.5 s | 0.62x run | runner beats the ball |
| after the second | 8.0 t | 4.6 s | 0.62x run | runner beats the ball |
| **fixed** | 8.0 t | **2.0 s** | **1.45x run** | **ball wins** |

Exponential decay spends most of its time in the tail, so the ball launched fast
and then *trickled* and a defender could jog after any pass. **`STOP_SPEED` was
the fix, not `KICK_SPEED`** — ending the roll at 0.42x a run rather than 0.11x
cuts the tail, and the same 8 tiles land in 2.0 s instead of 4.6.

**The test to use is whether the ball beats a runner** — `dist / time` against
`SPEED_NORMAL` — not how fast it leaves the boot. That question would have
caught this at any point in the project's history, including before the rescale.

**A tapped kick no longer locks onto a team-mate**, only onto the goal and only
in range; otherwise it goes where you face. The indicator gained a marker where
the ball *stops rolling*, because a kick is the one aim whose useful quantity is
a distance and a lane that fades out does not answer it. Bots keep the pass
search — they have no drag to fall back on.

---

### 10.2 Damage re-derived — and what the formula could not see

`CHARACTER_BUILDING.md` §3 bands `A` off measured `hits/atk ÷ pellets`, so the
whole damage pass is meant to be: run the sim, read the hit rates, let `A` fall
out. It half worked.

| kit | hit rate | A now | A says | outcome |
|---|---|---|---|---|
| Nova | 49.8% | 1.00 | **1.15** | applied — 1250 → 1438 (5 × 288) |
| Tony | 63% | 1.00 | 1.00 | unchanged |
| Leon | 37.3% | 1.15 | 1.40 | **refused** — eDPS 877 vs an 820 ceiling |
| Hammy | 58% → **68%** | 0.85 | **1.00** | applied — 1236 → 1454, *after the 2× re-run* |
| Ayaan | 38% | 1.15 | 1.40 | held, as already recorded — eDPS 914 |

**The artifact check changed an answer for the first time.**
`CHARACTER_BUILDING.md` §3 asks for a re-run at `NS3_SIM_SPEED=2` to tell "the
kit misses" from "the sim never saw the hit", and it has always been a formality.
Not here: 7 of 9 kits band identically at 2× and 10×, and **the two that do not
are exactly the two physics predicts** — Hammy, who carries the fastest
projectile in the roster (58% at 10× against 68% at 2×), and Kovacs, whose clap
is instant (67% against 78%). Fewer physics ticks per metre at 10× under-counts
a fast projectile's hits. The 2× reading is the honest one, so Hammy is priced
at Fair rather than Demanding — which passes both sanity checks where 1.15 was
refused at 2.99 hits to kill, and moves the roster's worst kit in the right
direction. Kovacs' 0.85 was already held by judgement and the 2× reading agrees
with it.

**Nova and Hammy moved.** Nova's has a clean cause: the fighter and her pellets
kept their size in metres while the range they cross grew from 4.3 tiles to 6.6
of them, so a spread weapon has proportionally further to throw a fan that did
not widen.

Hammy's is the sim's own measurement error, described above.

**Two of nine still hit the sanity check rather than the band.** That is the check
working — it exists so a delivery number cannot price a kit out of the game —
but it means `A` is now held by refusal on a third of the roster, and each
refusal is recorded in the kit's own comment. **Do not quietly pick a friendlier
band to get around one.**

#### The blind spot: Tony

He measures an ordinary 63% delivery, so every input to `damage_per_attack` says
he is correctly priced — and he wins **26.6% of his spawns against a 1-in-9
baseline of 11.1%**, places 3.72 where the field averages 5.5, and deals 20.6k
damage per spawn against a roster median near 9k.

The cause is not in the formula at all. **A slower game has longer flight times
and therefore wider dodge windows, which penalises every kit that needs a DIRECT
hit and does nothing to an AOE that forgives a near miss.** The roster's
win-rate spread went from **17 points to 25** across the slowdown, and the movers
fit that story exactly — Tony 14.7 → 26.6, while Henry, who has to close to
melee range, fell 18.5 → 10.0.

> **Anything that changes flight times needs a roster-wide sim, not just a
> per-kit `A` re-derivation.** §1 says movement speed cancels out of `lead/hit`,
> and that is true and still the reason aiming difficulty did not move — but it
> is a statement about AIMING, not about who wins. The dodge window is the term
> that moved, and it does not fall equally on every kit.

The lever for Tony is a tier, not a delivery number, and tiers are a character
decision. `todo.md` 7.3.

---

## Struck this pass — 7 Sep 2026

Per CLAUDE.md: a stale entry is worse than a missing one, because it gets acted
on. All three of these were verified against the working tree, not against
context.

- **§8 was a proposal for work that had already shipped.** It opened *"There is
  no minimum gap between attacks anywhere in the codebase"* and closed with an
  "Implementation notes" to-do list. Every item on that list is in the tree:
  `Kits.ATTACK_COOLDOWN_RATIO` (0.22) and `Kits.attack_cooldown_for`,
  `Fighter.attack_cooldown` / `next_attack_at` gated inside `consume_ammo`, the
  `unload` stagger in `main.gd:perform_attack` (and Leon's `"unload": 0.05` in
  `kits.gd`), and `bot_brain._fire_interval` derived from the kit as
  `maxf(attack_cooldown, reload * randf_range(0.85, 1.15))`. Rewritten as
  shipped with the reasoning kept. Read as it stood, it would have had someone
  build the whole cooldown a second time.
- **§6's per-attack table had drifted on Anders.** The shipped row said 2.8
  tiles at ratio 1.70; `kits.gd` says 3.5 tiles at ratio 3.00. The kit was
  retuned afterwards for a good reason that the table could not express — a
  landing-spot weapon is timed against target drift, not against the dodge
  window — so the row is corrected and footnoted rather than the kit being
  "fixed" back to match a table. **Anders is the one row in that table that is
  supposed to fail the dodge-window target.**
- **§7.1 is superseded, not wrong.** Auto-aim leading is being taken back out
  (§9.1). The section stays in place with a superseded note, because its
  measurements are exactly what make the case for removing it.

- **§4 gained a caveat rather than a strike.** Its range-vs-screen identity
  (5.5 tiles = 48% of view, matching Brawl Stars' 10 of 21) is still exactly
  right. The half of its source claim that does *not* survive is "with the whole
  map on screen": measured this pass, the Nobles Cup pitch is 15 tiles against a
  view 11.5 tiles wide at 16:9, so it is the one mode where §4's model breaks.
  See §9.6. The section keeps its "don't touch it" heading because the number it
  is protecting — the 5.5-tile cap — is not what moved.

Left standing after checking: §5.3–5.6, and every "Still open" item in §7 except
the bot lead, which 9.1 promotes from optional to coupled.

## Struck in the rescale — 7 Sep 2026

- **§5.5 and §9.5 are answered, not deferred.** "Cover is twice as coarse as the
  fighter" was true from the first draft and §9.5 had just concluded it was "not
  worth an arena re-author on its own". It was worth it as the foundation of
  everything else in §10 — and the re-author cost far less than expected,
  because the generator was already parameterised and the range re-tier turned
  out to be arithmetic rather than a taste call.
- **§9.4's dial table was right about the mechanism and wrong about the
  destination.** It offered exact parity as the endpoint; parity played as "slow
  motion" and we settled 15% above it. The table's own framing is what misled —
  it tabulated `SPEED_NORMAL` against feel with model size held constant, and
  model size turned out to be most of the complaint.
- **CLAUDE.md's Nobles Cup kick range was wrong by 2.2x** — "~7 m (3.5 tiles)"
  against a code value of 15.3 m — for long enough that nobody knows when it
  drifted. Corrected, with the reason it survived: the Cup camera never showed
  enough of the pitch to check it against.
- **`Tools/gen_showdown_map.py --write` had been broken outright**, searching
  for `const MAP` where `arena.gd` declares `SHOWDOWN_MAP`. Every use of it
  raised `AttributeError` on `None`. Fixed.
- **CLAUDE.md listed four kits on the capsule fallback**; only Nova is. Anders,
  Hammy and Ayaan have had GLBs for a while.

---

## Sources

- [Brawl Stars Wiki — Colt](https://brawlstars.fandom.com/wiki/Colt) (and 88
  other brawler infoboxes, pulled via the wiki API)
- [Brawl Stars Wiki — Beginner's Guide](https://brawlstars.fandom.com/wiki/Beginner%27s_Guide)
  (hitbox = slightly larger than one tile of cover)
- [Brawl Stars Wiki — unit conversion, 300 = 1 tile/sec](https://brawlstars.fandom.com/f/p/4400000000000112757)
- [Brawl Planet — movement speed tier list](https://www.brawlplanet.com/tier-list/base_movement_speed)
- [Brawl Planet — attack range tier list](https://www.brawlplanet.com/tier-list/attack_range)
- [Brawl Stars Wiki — Map Maker](https://brawlstars.fandom.com/wiki/Map_Maker) (21×33 for 3v3, 60×60 Showdown)
