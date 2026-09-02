# Character Building Guidelines

How to stat a new Noble Stars fighter so it slots into the roster without
breaking it. Every number here is enforced by hand — pick tiers, run the damage
formula, type the result into `godot/scripts/kits.gd`, then validate with
`NS3_SIM`.

The rule behind all of it: **a fighter buys damage by giving up something else.**
Health, speed, reload and range are the currency. Nothing is free.

---

## 1. Fixed constants

These are the same for everyone and live in `kits.gd`:

| Constant | Value | Meaning |
|---|---|---|
| `BASE_MAX_HEALTH` | **5000** | Default fighter health. Damage is balanced against this. |
| `MAX_AMMO` | 3.0 | Default ammo pips; a kit can override with `ammo`. |
| `AMMO_RECHARGE_SECONDS` | 1.8 | The *Normal* reload tier; per-kit `reload` overrides it. |
| `MOVE_SPEED` | 5.6 m/s | The *Normal* speed tier; per-kit `move_speed` overrides it. |
| `FIGHTER_RADIUS` | 0.65 m | Fighter is 1.30 m wide. The unit ranges actually matter in — see SHOT_FEEL.md. |
| `PROJECTILE_SPEED_RATIO` | 3.1 | Direct-fire shot speed as a multiple of the firer's move speed. |
| `ATTACK_COOLDOWN_RATIO` | 0.22 | Minimum gap between attacks, as a fraction of the reload. |
| `SUPER_CHARGE_DAMAGE` | 3500 | Damage dealt to fill a Super (= 0.7 healthbars). |
| `HEALTH_PER_CUBE` | 550 | Power cube pickup (= 11% of base health). |
| `DAMAGE_BONUS_PER_CUBE` | 0.10 | +10% damage per cube. |
| `REGEN_DELAY` / `REGEN_RATE_PER_SECOND` | 3.0s / 0.14 | Out-of-combat regen. |
| `TILE` | 2.0 m | One tile. All ranges are written as `n * TILE`. |

---

## 2. The four tiers

Every fighter picks one tier from each table. **Write the tier names in a
comment above the kit** so the intent survives later tuning.

### Health

| Tier | Value | Feel |
|---|---|---|
| Very Low | 3500 | Glass cannon. Dies to two clean hits. |
| Low | 4250 | Squishy. Must not get caught. |
| **Normal** | **5000** | The default. |
| High | 5750 | Trades blows and wins. |
| Very High | 6500 | Front-liner. Soaks a whole Super. |

### Speed

| Tier | m/s | vs. Normal |
|---|---|---|
| Very Slow | 4.48 | 0.80× |
| Slow | 5.04 | 0.90× |
| **Normal** | **5.60** | 1.00× |
| Fast | 6.16 | 1.10× |
| Very Fast | 6.72 | 1.20× |

5.6 m/s is 2.8 tiles/second, or 4.31 fighter-widths/second. **Always judge
speed in fighter-widths, not m/s** — perceived speed tracks body-lengths, so
widening the fighter slows the game down at a fixed m/s. The spread from
Very Slow to Very Fast is 50% — big enough that speed alone decides who picks
the fight.

**`SPEED_NORMAL` is the game's feel dial.** Every projectile speed in `kits.gd`
is written as a multiple of a speed tier, so raising a tier speeds its shots up
with it and aiming difficulty stays fixed. What changes is how long a shot hangs
in the air — the player's reaction window. See SHOT_FEEL.md §6 for the cost
curve before touching it.

### Reload

Seconds to regain **one** ammo pip. Three pips means a full magazine takes 3×
this. It also sets the **attack cooldown** — the minimum gap between two
attacks — at `0.22 × reload`, which is what stops a whole magazine leaving the
barrel in a single flick.

| Tier | Seconds | Full magazine |
|---|---|---|
| Very Slow | 2.6 | 7.8s |
| Slow | 2.2 | 6.6s |
| **Normal** | **1.8** | 5.4s |
| Fast | 1.4 | 4.2s |
| Very Fast | 1.0 | 3.0s |

| Tier | Seconds | Attack cooldown | Full magazine dumps in |
|---|---|---|---|
| Very Slow | 2.6 | 0.57 | 1.14s |
| Slow | 2.2 | 0.48 | 0.96s |
| **Normal** | **1.8** | **0.40** | 0.80s |
| Fast | 1.4 | 0.31 | 0.62s |
| Very Fast | 1.0 | 0.22 | 0.44s |

**Reload does not change a fighter's damage per second** — the formula in §3
scales damage-per-attack by the reload time, so sustained output stays on
budget either way. Nor does the cooldown: three pips refill in 4.2–6.6s and
dump in 0.4–1.1s, so it caps *burst* and never gates steady state. What reload
actually controls is *burst vs. chip*: a Very Slow reload means one enormous,
committing swing; a Very Fast reload means a stream of small hits you can
course-correct mid-fight. Pick it for feel.

### Range

In tiles. The hard limit is the screen — see §4.

| Tier | Tiles | Meters | Fighter-widths |
|---|---|---|---|
| Very Short (melee) | 1.2 – 1.5 | 2.4 – 3.0 | 1.8 – 2.3 |
| Short | 2.2 – 2.8 | 4.4 – 5.6 | 3.4 – 4.3 |
| **Medium** | **3.5 – 4.3** | 7.0 – 8.6 | 5.4 – 6.6 |
| Long | 4.8 – 5.5 | 9.6 – 11.0 | 7.4 – 8.5 |

There is deliberately **no "Very Long" tier.** 5.5 tiles is the edge of the
screen; past that a fighter is shooting at something the player cannot see.

**Read the fighter-widths column, not the tiles.** Range only means anything
relative to how big the target is, and the fighter is 1.30 m wide. These tiers
were pulled in at the short end and the fighter was widened by 44%, which
between them took the roster from reaching *past* Brawl Stars' longest range to
sitting just inside it.

---

## 3. The damage formula

A fighter's damage is not chosen — it is derived from the tiers.

```
damage_per_attack = 1250 × R × G × M × S × A × U
```

`1250` is the baseline hit: four of them kill a Normal-health (5000) target.

| Factor | What it prices | Values |
|---|---|---|
| **R** — reload | Longer wait, bigger hit | `reload / 1.8` |
| **G** — range | Safety is worth damage | Very Short **1.25**, Short **1.15**, Medium **1.00**, Long **0.85** |
| **M** — mobility | Control of the engagement | V.Slow **1.12**, Slow **1.06**, Normal **1.00**, Fast **0.94**, V.Fast **0.88** |
| **S** — survivability | Time on the field | V.Low **1.12**, Low **1.06**, Normal **1.00**, High **0.94**, V.High **0.88** |
| **A** — delivery | How hard it is to miss | Forgiving **0.85**, Fair **1.00**, Demanding **1.15**, Very Demanding **1.40** |
| **U** — utility | Non-damage value on the *basic attack* | Strong **0.85**, None **1.00** |

**Choosing A.** Forgiving = AOE ≥ 1 tile, a melee arc ≥ 90°, piercing, or arcs
over walls with no line-of-sight check. Demanding = the full damage only lands
under a condition the player has to work for — a tight spread, a small fast
projectile, point-blank-only pellet convergence. **Very Demanding** = several
small projectiles that must *all* connect, thrown far enough that the target can
move between the shot and the landing.

**Don't judge A — measure it.** Run `NS3_SIM`, take `hits/atk ÷ pellets`, and
band it:

| measured hit rate | A | tier |
|---|---|---|
| ≥ 75% | **0.85** | Forgiving |
| 60 – 75% | **1.00** | Fair |
| 45 – 60% | **1.15** | Demanding |
| < 45% | **1.40** | Very Demanding |

This is not a new invention: it reproduces all four hit rates this doc had
already recorded, with nothing fudged — Henry 85% → 0.85, Tony 81% → 0.85,
Nova 47% → 1.15, Leon 39% → 1.40. Using it makes the whole roster reproducible:
after any change to speed, fighter size or projectile size, re-run the sim and
the A values fall out instead of being re-argued.

**Except for melee, which the sim inflates.** Bots walk at each other in
straight lines, so a punch lands far more often in the sim than against a player
who kites — Henry measures 93% in-sim against the 85% this doc recorded from
play. Deriving A from an inflated rate under-pays every melee kit, so melee A
stays a judgement anchored on playtest. Ranged hit rates have no such bias.
This is the same lesson as §8's "the sim under-rates melee", applied to A.

That is a 2.2× spread in how much of its nominal damage a kit actually collects,
so the 0.85–1.15 range alone cannot express it — hence the 1.40 tier. Leon was
priced at A=1.00 and realised 251 eDPS against a roster median near 470; five
separate delivery fixes barely moved him, because the shortfall was never a bug
after the physics was corrected. **If a kit's realised eDPS (`dmg/atk ÷ reload`)
sits far off the roster, check its hit rate before assuming the stats are
wrong — and if the hit rate is simply low by design, that belongs in A.**

**Choosing U.** Only fires when the *ordinary attack* does something besides
damage — returns ammo, heals, slows. Utility that lives on the Super is already
priced by the Super multiplier below, so don't count it twice.

**Multi-hit attacks.** The formula gives the total for one trigger pull. Divide
by `pellets` to get the per-projectile number that goes in the kit.

### Supers

```
super_damage = weapon_damage_total × super_multiplier
```

| Multiplier | When |
|---|---|
| **1.8×** | One reliable hit — a piercing line, a dash, a targeted smash. |
| **2.4×** | Spread across pellets, passes or ticks that rarely all connect. Divide by the number of hits a target can realistically eat. |
| **1.4×** | The Super also grants strong utility — a stun, a leap, area denial, big knockback. |

A Super costs 3500 damage dealt to charge, so a fighter earns roughly one per
kill-and-a-half.

### Sanity check

After computing, verify:

- **Effective DPS** = `damage_per_attack / reload`. Should land between
  **420 and 820**. Below 420 the fighter can't close out a kill; above 820 it
  deletes people before they can react.
- **Hits to kill a Normal target** = `5000 / damage_per_attack`. Should be
  **3 to 5**. Two is a one-combo delete; six is a war of attrition.

---

## 4. Range and the screen

The match camera uses a **very narrow perspective**, `fov = 7°`, sitting at
offset `(0, 91.4, 52.8)` — a 60° pitch — with the player at the centre ray
(`main.gd`, `CAMERA_OFFSET` / `CAMERA_FOV`). Its centre-plane framing matches
the old 12.9 m orthographic view, while perspective gives slightly more ground
visibility up-screen and slightly less down-screen:

| Direction | Visible from the player |
|---|---|
| Left / right | 11.5 m = **5.7 tiles** = 8.8 fighter-widths |
| Up-screen / down-screen | 7.7 m / 7.2 m = **3.9 / 3.6 tiles** |

The full screen width is 23 m = **17.7 fighter-widths**. Brawl Stars fits about
21 brawler-widths across, so our fighters read a little chunkier than theirs —
which is deliberate, and is what lets them move faster than Brawl Stars without
shots becoming impossible to aim (SHOT_FEEL.md §6).

The ground is foreshortened by the camera pitch, and perspective makes the
up-screen half longer than the down-screen half. So:

- **Weapons cap at 5.5 tiles.** That fills the wide axis and nothing more.
- **Supers may reach 6.5 tiles**, but only when the projectile visibly travels
  out of frame, so the player understands what happened. This is the exception,
  not the standard.
- Anything above 6.5 tiles is a bug, not a design choice. A fighter aiming at
  an enemy that has never been on screen is not playing the game.

---

## 5. Worked example

*"A slow, tough grenadier who lobs a big forgiving blast at range."*

1. **Tiers.** Health High (5750, S = 0.94) · Speed Slow (6.3, M = 1.06) ·
   Reload Very Slow (2.6, R = 1.444) · Range Long, 5.0 tiles (G = 0.85).
2. **Delivery.** A lobbed AOE that ignores line of sight → Forgiving, A = 0.85.
3. **Utility.** Nothing beyond damage → U = 1.00.
4. **Damage.** `1250 × 1.444 × 0.85 × 1.06 × 0.94 × 0.85 × 1.00` = **1301**.
5. **Check.** eDPS = 1301 / 2.6 = **500** ✓ (420–820). Hits to kill =
   5000 / 1301 = **3.8** ✓ (3–5).
6. **Super.** Targeted smash, one reliable hit → 1.8× → **2340**.

---

## 6. Checklist for a new fighter

- [ ] Role is one line, and no existing fighter already owns it.
- [ ] One tier picked from each of health / speed / reload / range, written in
      a comment above the kit.
- [ ] Damage derived from the formula, not from taste.
- [ ] eDPS in 420–820; hits-to-kill in 3–5.
- [ ] Weapon range ≤ 5.5 tiles, Super range ≤ 6.5 tiles.
- [ ] Super multiplier picked from the table and its category justified.
- [ ] Godot reimported (`--headless --import`) after any new script.
- [ ] `NS3_SIM=200 --headless` run: win rate near **1/roster_size**, average
      placement near the middle of the field.
- [ ] The fighter's weakness is nameable in one sentence. If it isn't, the kit
      has no counterplay.

---

## 7. Current roster

Nine fighters, all rebalanced to this framework.

| Fighter | Role | Health | Speed | Reload | Range | hit rate | A | U | eDPS | Damage / attack |
|---|---|---|---|---|---|---|---|---|---|---|
| **Nova** | Shotgunner | Normal 5000 | Normal 5.6 | Normal 1.8 | Medium 4.3 | 69% | 1.00 | — | 694 | 1250 (5 × 250) |
| **Tony** | Artillery | Low 4250 | Slow 5.04 | Slow 2.2 | Long 5.5 | 74% | 1.00 | — | 663 | 1459 |
| **Henry** | Heavyweight | High 5750 | Slow 5.04 | Slow 2.2 | V.Short 1.5 | 93%† | 0.85 | — | 736 | 1620 |
| **Sanjit** | Assassin | Normal 5000 | V.Fast 6.72 | V.Fast 1.0 | V.Short 1.4 | 62%† | 1.15 | — | 879 | 880 (2 × 440) |
| **Kovacs** | Tank | V.High 6500 | V.Slow 4.48 | Normal 1.8 | Short 2.4 | 90%† | 0.85 | — | 667 | 1200 |
| **Leon** | Controller | Low 4250 | Normal 5.6 | Fast 1.4 | Long 4.8 | 50% | 1.15 | — | 720 | 1008 (6 × 168) |
| **Anders** | Skirmisher | High 5750 | Normal 5.6 | Fast 1.4 | Short 2.8 | — | n/a | — | n/a (1 pip) | 1100 / 1375 / 1650 rally |
| **Hammy** | Sniper | V.Low 3500 | Normal 5.6 | Slow 2.2 | Long 5.5 | 83% | 0.85 | 1.00 | 562 | 1236 |
| **Ayaan** | Carver | Normal 5000 | Fast 6.16 | Normal 1.8 | Medium 2.8–4.5‡ | 41%‡ | 1.15 | — | 751 | 1352 (2 × 676) |

† melee — A is held by judgement, not derived, because the sim inflates melee
hit rates (see §3). Hit rates are from a 240-match `NS3_SIM` on the 39×39 map.

‡ **Ayaan's range is a band, not a number, and it is set by the aim.** The shot
ends where it was pointed, anywhere from 2.8 to 4.5 tiles, and the distance
picks the shape it flies to get there: 4.5 tiles is one 27° arc bowing 1.39 m
off the line, 2.8 tiles is a 58° braid crossing three times. `kits.gd` carries
the ends as `range` / `range_min`; `Kits.slalom_weave` does the rest. G is 1.00
because the band straddles Medium — and note which end beats cover: the LONG
one, because only the wide single arc bows further than the 1.11 m it takes to
pass a body.

**His A of 1.15 was measured on the previous weave and has not been re-measured
since.** Two 40-match `NS3_SIM` runs on the build before this one read 45.0%
(784 shots) and 38.2% (900 shots), pooling to 41.4% — Very Demanding by §3's
table. Two things then argued against paying it, and both still hold: `1250 ×
0.94(M) × 1.40(A)` = 1645 is an eDPS of **914** against the 820 ceiling, which
is what that sanity check is for; and he was already taking 17 of 92 spawns to a
win, 18.5% against the 11.1% a nine-kit roster expects. A kit cannot be Very
Demanding at Normal health and Fast speed — if a playtest confirms the 41%, **the
honest fix is a tier, not the formula** (Health Normal → High puts A=1.40 at
eDPS 804 and fits).

**One 40-match run on the reworked weave reads 35.1% (838 shots) at a 12.8% win
rate over 39 spawns** — delivery down, results down onto the 11.1% line. Both
move the way the inversion predicts: shots now end where they were aimed instead
of overshooting, and the long setting spends its whole flight more than a metre
off the line, so half of them find scenery. It is one run and it does not settle
anything, but it is the reason nothing was retuned off it. Run
`NS3_SIM=200 --headless` with no other Godot instance open — a live editor
session kills long runs — and treat 200 matches as the first number worth
acting on.

**Do not up-rate him on the hit rate alone: he is already winning too much.**
Across those same 80 matches he took 17 of 92 spawns to a win, 18.5% against the
11.1% a nine-kit roster expects — 2.2σ high, suggestive rather than settled, but
pointing the opposite way to his delivery number. The two readings are not
contradictory: he misses a lot and still wins, which is what a kit with the
roster's second-best mobility and a Super that repositions across a third of the
map looks like. **Re-run `NS3_SIM=200 --headless` with no other Godot instance
open** (a live editor session kills long runs) and settle both before touching
anything.

**A melee kit needs a gap-closer, and it has to be somewhere specific.** Henry
dashes and Kovacs leaps, both on the Super, and both are slower than a Normal
kit — the Super *is* their approach. Sanjit was Very Fast instead, but Very Fast
is only +1.12 m/s, which put an 11 m sniper at 7.3 seconds of chase: 3.3 shots
and 4113 of his 5000 health before he arrived. His Super throws his staff
*away*, so it could never be the answer. The fix is a 0.8 m lunge on each melee
strike (`"lunge"` on the weapon, `Fighter.lunge`), which puts the approach on
the basic attack and fires whether or not the swing connects. **Before adding a
melee kit, name where its gap-closer lives.**

**Hammy lost his U discount rather than taking both.** A measured at 0.85 and U
at 0.85 would have given him 0.85(G) × 0.85(A) × 0.85(U) = 0.61 — precisely the
stacked-discount trap recorded below for Anders, who finished a sim at 2.7%.
Hammy was at 3.8% over 240 matches with both applied, which is the proof that
rule asks for. **Note what this does not fix:** his delivery is fine at 83%, and
he loses because he gets 5.1 attacks a life on 3500 health. That is uptime, and
the damage formula has no lever for it — the honest fix would be his health
tier, which is a change to the character rather than to its maths.

**Nova is the reference kit** — Normal in all four tiers, so her only modifier
is the 1.15 for a shotgun that has to close distance. Every other fighter is
readable as a deviation from her.

**Give a kit fewer pips when it cannot spend them.** Anders holds one sack at a
time, so his second and third pips could never be used — around 45% of his kicks
were refused outright, which reads as an unresponsive character rather than a
design. He now has `"ammo": 1`, and the pip stays empty until the rally ends
(`Fighter.ammo_locked`), so the reload is the price of *losing* the sack rather
than a clock ticking during it. Blocked kicks went to zero. If a kit's mechanic
gates its own fire rate, the magazine should match the mechanic, not the default.

**Watch what a kit turns into in play, then stat it for that.** Anders was built
as a mid-range skirmisher and is played as a close brawler, because the rally
pulls him toward wherever the sack is coming down. Rather than fight that, he
was restatted for the pocket: reach 4.5 -> 3.0 tiles, health Normal -> High, and
a much heavier landing. He now sits at Henry's cadence — 6.1 attacks a life at
1466 damage against Henry's 6.8 at 1422.

**A Super aimed as an escape needs its own bot rule.** Pop Off spikes the ground
Anders jumped *away* from, so its aim is the leap, not the target. Bots aim
every attack at whoever they are fighting, which made them leap onto an enemy
and spike empty floor seven metres behind — the Super had never once connected
in a sim. `bot_brain` now inverts the aim for that style. Any Super whose aim
means something other than "at the enemy" needs the same treatment.

**Never make a Super punish the mechanic it belongs to.** Pop Off consumes the
sack, and half of all uses were fired mid-rally — so the Super's most common
outcome was destroying the thing the kit exists to keep alive. It now cashes the
rally in: the spike lands for whatever multiplier that sack had climbed to, so
popping at rally 3 is a payoff rather than a loss.

**An arcing attack has to be timed against how fast people move.** The sack
first shipped at 8 m/s: a 9 m hop hung for 1.1 seconds, in which a 7 m/s fighter
walks 7.9 m, so the landing spot was stale before it arrived and it hit almost
nothing (0.13 hits per attack). At 12 m/s with a lob's landing radius it lands.
Any attack that resolves where it *arrives* rather than along its path needs
flight time checked against 7 m/s of target movement before anything else.

**A rally kit does not fit the per-attack formula.** Anders spends one ammo on a
sack that can touch three times, so `damage_per_attack` has no single meaning.
He is calibrated against *measured* eDPS (`dmg/atk ÷ reload`) relative to the
roster instead, and his A is 0.85 rather than the 1.15 the paper design implies:
every touch redirects to the nearest fighter, so a miss converts itself into a
hit on somebody else. Just over half his sacks find a body — it homes, so it is
priced as homing. When a kit's attack has state, calibrate, don't compute.

**Don't stack A and U on the same kit without proof.** Anders originally took
both discounts (0.85 × 0.85 = 0.72) and finished a 120-match sim at 2.7% wins.
Two lessons: piercing and bouncing are worth nothing if the *first* hit misses,
so a slow projectile is Fair delivery and not Forgiving; and a utility you can
only get by luck is not a utility. His sack now returns to him reliably rather
than depending on a random bounce, and U rides free until a sim says otherwise.

**A weapon aimed by distance needs the distance to be an input.** Ayaan's two
Slalom shots swing off the aim line and cross back onto it, and the crossing is
where his damage is — so the crossing is the aim. It shipped first at a fixed
3.2 tiles, and a playtest called it immediately: a weapon whose sweet spot is a
ring you cannot move is not aimed, it is *stood in*. `Kits.slalom_weave` now
takes the aim distance and returns the weave that puts a crossing exactly
there. It costs nothing at the input layer because every path already carries a
distance — a drag has its own length, a tap has the distance to the target, a
bot has the distance to its lead point — so drag, tap, bot and the net replay
all agree without any of them knowing what the number means. **If a new attack
has a sweet spot, ask what moves it before asking what it's worth.**

**Then make the shape cost something, or the choice is free** — and check you
made it cost the thing you meant. The playtest note was "the less wiggled it is
the more range he gets", and the build that answered it did the exact opposite,
which took a second note to catch: *"the more braided it is the shorter it
should go — this isn't quite working"*.

The bug is worth keeping because it is not a typo, it is a modelling error. That
build capped the crossing **spacing** and let the count fall out, so reaching
further needed *more* crossings and the longest shot came out as the tightest
braid — the precise opposite of the rule, arrived at by tuning the wrong end of
the same relationship. Cap the **count** instead and it inverts into the shape
it should always have had: one lazy arc for the long shot, a dense braid for the
short one, a braid that cannot be long-ranged by construction. **When a shape
control comes out backwards, look for the quantity you bounded, not the constant
you set.**

**Draw a curved attack's real path, and integrate the drawing the way the shot
flies.** The aim ribbon for Slalom runs the same heading law at the same 60 Hz
tick as `Projectile`, midpoint-sampled in both places. That is not tidiness:
sampling the swerve at the frame's start instead of its middle runs the curve
several percent long, which would have put the drawn crossing a fifth of a tile
from the real one — a lie about the one number the kit asks the player to read.

**A weaving shot's range is not its path length.** A Slalom shot covers 5-24%
more ground than it gains on the aim line depending on how hard it swerves, so
`projectile.gd:_advance` spends its range along that line. Otherwise "ends at
4.5 tiles" would mean 4.3 for a gentle arc and 3.4 for a hard braid, and
`bot_brain`'s range gate — which measures straight-line distance to the target —
would expire his opening shot in mid-air. The same correction has to reach
anything that turns speed into a flight time, which is what `Kits.aim_speed` is
for; both `_aim_point` and `_aim_lead` call it, and both pass the aim distance,
because the swerve (and so the flight time) depends on it.

**A steered Super is a dash with a clock, and it steers with the ordinary
stick.** Downhill reuses the `dash` channel deliberately — every guard that
already asks `is_dashing()` covers it for free — but it ends on `duration`
rather than on distance, and `Fighter.apply_movement` sets its heading straight
from the move input.

It shipped twice with a capped turn rate first, 2.0 rad/s and then 3.4, on the
theory that a committed arc was what made it a Super. Both times the playtest
said the same thing, and the second time named it: *"super steering shouldn't be
relative to where he is facing"*. A rate cap turns the stick toward the
**current heading**, so pushing left does not go left, it curves left from
wherever he happens to point — which reads as relative control however the input
is framed, and the tighter the cap the more the arena decides where the run
goes. **Rate-limited steering is relative steering. If a mechanic should feel
like the normal controls, give it the normal controls** and let the commitment
live in the duration and the speed you cannot cancel. The other half is a swept
contact test rather than a per-frame point check, or a 12 m/s body skates
straight through people at `NS3_SIM`'s 10x time scale.

---

## 8. Bot piloting

`NS3_SIM` measures *bot* play, and bots stand at
`weapon.range × ideal_range_mult` from their target (`bot_brain.gd`). A kit
whose damage depends on distance — a shotgun, anything with spread — needs a
per-kit `ideal_range_mult` or the bots will fight at exactly the wrong range
and the sim will report it as broken when the kit is fine. Nova's is `0.30`;
the default is `0.70`.

Bots also **lead their shots**, and by different amounts depending on who is
watching (`LEAD_SIM` / `_lead_skill` in `bot_brain.gd`):

| | Lead strength | Why |
|---|---|---|
| Sim bots (`NS3_SIM`) | 0.85 | So the table measures the kit, not the AI. |
| Match bots | 0.15 – 0.45, rolled per bot | Present enough to read as aimed, sloppy enough to walk out of. |

This matters more than it sounds. With no lead at all, a 17.6 m/s pellet
crossing 8.6 m is airborne 0.49s while a 4.0 m/s target travels 2.0 m — more
than its own 1.30 m width — so **every projectile kit misses a moving fighter
and only instant-hit kits (melee, shockwave) ever connect.** The player's
tap-fire now leads too (`main.gd:_aim_lead`); it did not before, which meant a
tap at range could not hit a strafing enemy while bots could. A no-lead sim doesn't rank
kits, it ranks hitscan against everything else. If you add a new attack style,
check `_aim_point` knows its flight time: it derives one from `weapon.speed`,
and special-cases the styles that have none.

Sim results are still a floor rather than a ceiling — bots don't dodge, don't
kite, and never save a Super for the right moment. A kit that looks weak in the
sim may be fine in a player's hands, but a kit that looks *strong* in the sim is
genuinely strong.

### Read `hits/atk` before you believe `win%`

The table reports `atk/spawn`, `hits/atk` and `dmg/atk` for exactly one reason:
**a kit that looks broken is usually not landing its shots, and that is rarely a
balance problem.** `hits/atk` should land near a kit's projectile count — about
6 for Leon, 5 for Nova, 1 for a melee swing. Anything near zero means the damage
never arrived, so the win rate is measuring delivery, not strength.

Three separate bugs hid behind bad win rates during the first rebalance, and all
three looked exactly like "this kit is undertuned":

1. **Bots aimed where the target already was.** No lead meant a 25 m/s pellet
   crossing 7 m missed by ~2 m. Only instant-hit kits could ever connect.
2. **Match-grade aim scatter in the sim.** 3–9° at 7 m is 0.37–1.10 m against a
   ~0.65 m hitbox, so a bot rolling above ~5° could never land a precision
   weapon. Wide arcs and big AOEs didn't care — the table ranked *forgiveness*.
3. **Projectiles tunnelled through targets.** `Area3D` overlap is sampled once
   per physics tick, and at 10x time scale a pellet advances ~4 m per tick.
   `projectile.gd` now sweeps a ray over its frame movement instead.

Before that third fix Kovacs sat at 45% wins and Henry at 24%, and both looked
like obvious overtuning. After it they fell to 7.0% and 8.6% over 120 matches,
with no stat changed. **Fix the instrument before you touch a kit.**

### The sim under-rates melee. Trust the playtest.

Those same post-fix numbers had Kovacs at 7.0% and Sanjit at 0.6%, yet in a
human's hands Kovacs and Henry are the *easiest* kits to win with. Bots walk
at people in straight lines; a player uses cover, waits out an ammo dump and
picks the moment to close. Closing a gap is a skill the sim cannot express, so
every melee kit reads weaker there than it plays.

Use the sim to catch kits that cannot deliver their damage at all — that is a
mechanical fault and it shows up honestly. Do not use it to set the melee/ranged
balance point. Sanjit was buffed off a playtest that agreed with the sim; Kovacs
and Henry were left alone because the playtest disagreed.

`NS3_SIM_SPEED=<n>` overrides the 10x default. If a result smells like a physics
artifact, run the same matches at `2` and compare `hits/atk`: real balance
differences hold across time scales, tick-rate artifacts vanish.
