# Shot Feel — how Brawl Stars tunes projectile speed, and where we differ

Research note, Sept 2026. Source data: the Brawl Stars wiki's raw infobox fields
pulled for 89 brawlers (`MovementSpeed`, `AttackSpeed`, `AttackRange`,
`AttackWidth`), plus our own `kits.gd`. Brawl Stars measures speed in units where
**300 units = 1 tile/second**, and range and hitbox width directly in tiles.

The short version: **everything in our game happens about 2.3× too fast for the
size of the fighters.** Movement, projectile speed and range are all high
together, which produces two separate complaints at once — shots are *hard to
aim* at a strafing target, and simultaneously *impossible to dodge* once fired,
because they arrive in 0.38s. The fix is a coordinated slowdown, not a single
knob. The recommendation is in §6.

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
| Tony lob | 5.04 | 5.5 | 0.42 | 10.6 | 2.10 | 1.04 | .79 | 1.48 |
| Tony Super | 5.04 | 6.0 | 0.56 | 19.7 | 3.90 | .61 | .36 | 1.27 |
| Henry sweep | 5.04 | 1.5 | — | — | — | — | — | — |
| Henry dash | 5.04 | 3.4 | — | 16.1 | 3.20 | .42 | .17 | — |
| Sanjit combo | 6.72 | 1.4 | — | — | — | — | — | — |
| Sanjit Super | 6.72 | 5.0 | 0.64 | 19.2 | 2.85 | .52 | .27 | 1.36 |
| Kovacs clap | 4.48 | 2.4 | — | — | — | — | — | — |
| Kovacs leap | 4.48 | 3.6 | — | — | — | — | — | — |
| Leon button | 5.60 | 4.8 | 0.46 | 17.9 | 3.20 | .54 | .29 | 1.35 |
| Leon Super | 5.60 | 4.8 | 0.66 | 11.8 | 2.10 | .82 | .57 | 0.76 |
| Anders sack | 5.60 | 2.8 | 0.44 | 9.5 | 1.70 | .59 | .34 | 0.81 |
| Anders Pop Off | 5.60 | 2.8 | 0.48 | 15.7 | 2.80 | .36 | .11 | 0.35 |
| Hammy shot | 5.60 | 5.5 | 0.62 | 20.2 | 3.60 | .55 | **.30** | 1.20 |
| Hammy Super | 5.60 | 6.0 | 0.70 | 18.5 | 3.30 | .65 | .40 | 1.35 |

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
2. **Run clips are speed-matched to ground speed.**
   `fighter.gd:update_animation` played the run clip at a fixed rate, so the
   feet skated — forward at 7 m/s, and they would have skated backward at 4.
   `_anim.speed_scale` is now `velocity.length() / SPEED_NORMAL`, clamped
   0.6–1.6, which fixes the long-standing foot-slide and gives each speed tier
   its own stride. `play_attack_animation` resets it to 1.0, because the attack
   clips' timings are tuned frame-by-frame against their own `speed`.
3. **Models scale with the hitbox.** `MODEL_SCALE = 1.44` keeps the GLB
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

- **Damage.** eDPS is per-second so the formula is untouched, but the **A**
  factor is not: `lead/hit` roughly halved across the roster and the fighter is
  44% wider, so measured hit rates are materially higher than when A was set.
  Leon's `A = 1.40` came off a 39% hit rate that no longer holds. Re-derive from
  `NS3_SIM`, reading `hits/atk` before `win%`.
- **Bot match lead.** `LEAD_MATCH_MIN/MAX` (0.15–0.45) was tuned against 0.38s
  flights. At 0.5s flights a 0.15-lead bot now misses by 1.4 m against 2.0 m of
  hit width, so it grazes rather than whiffing — arguably the intended
  sloppiness, but worth a look in the sim before deciding.
- **Melee closing time** roughly doubles (Henry onto Hammy: 1.1s → 2.1s). Brawl
  Stars' equivalent is 2.7s, so we are still ahead, but §8 of
  `CHARACTER_BUILDING.md` already warns the sim under-rates melee.
- **Wall height.** Walls are 1.5 m boxes and fighters are now ~2.5 m of scaled
  model. Brawl Stars keeps cover and brawlers about the same height; ours no
  longer do, so cover reads shorter than it plays.
- **`TILE` is still 2.0 m** against a 1.30 m fighter, so cover is 1.5
  body-widths where Brawl Stars' is 1.0 (§5.5). Closer than the 2.2 it was, and
  no longer worth an arena re-author on its own.

---

## 8. Unload speed — there isn't one

`main.gd:_fire_player` calls `Fighter.consume_ammo()`, which does exactly one
thing:

```gdscript
func consume_ammo() -> bool:
    if ammo < 1.0: return false
    ammo -= 1.0
```

**There is no minimum gap between attacks anywhere in the codebase.** A full
magazine leaves the barrel as fast as the player can flick the aim stick.

| kit | ammo × dmg | as a healthbar | time to dump today | time to refill |
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

### Two knock-on effects

**The reload tier currently does nothing it claims to.**
`CHARACTER_BUILDING.md` §2 says reload "decides whether a kit feels like one
committing swing or a stream of chip damage… pick it for feel." It cannot,
because with no cooldown every kit is maximum burst regardless of reload —
reload only sets how long you wait afterwards. **The attack cooldown is the
missing mechanic that makes the reload tier mean what the doc says it means.**

**Bots and the player are on completely different clocks.**
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

### Proposal

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
burst now takes 1.0s, during which the target covers 3.0 m — 3.3 body-widths,
plenty to break the second and third shot. Today it is ~0.2s and 1.4 m.

**Inter-projectile spacing** for stream-style attacks — a new optional `unload`
key on the weapon dict, seconds between projectiles:

| attack | pellets | `unload` | total | why |
|---|---|---|---|---|
| Leon buttons | 6 | **0.05** | 0.25s | a cone of six is Colt's stream, not a shotgun |
| Nova pellets | 5 | **0** | instant | a shotgun fan; Shelly fires hers simultaneously |
| Sanjit combo | 2 | 0.22 | 0.22s | already staggered in `perform_attack` |

### Implementation notes

The pattern already exists in the codebase twice — the `Style.MELEE` combo
staggers with `create_timer(0.22 * i)`, and Kovacs' clap uses a `delay` key.

- `Fighter`: add `attack_cooldown` (from the kit) and `next_attack_at`; have
  `consume_ammo()` refuse while `now < next_attack_at` and set it on success.
  Gating inside `consume_ammo` covers the player and bot paths at once, and the
  net path too, since clients route through the host's `_fire_player`.
- `main.gd:perform_attack`, `Style.PELLETS`: stagger the spawn loop by
  `weapon.get("unload", 0.0) * p`, same timer pattern as the melee combo, with
  the same instance-id capture (a fighter can die mid-unload).
- `bot_brain`: replace `_fire_interval = randf_range(1.0, 1.6)` with something
  derived from the kit — `reload * randf_range(0.85, 1.15)` keeps a bot roughly
  on its own ammo economy instead of a constant.
- Watch the Super: it is gated by charge, not ammo, so it should bypass the
  cooldown or a tapped Super will silently eat the gap after a basic attack.

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
