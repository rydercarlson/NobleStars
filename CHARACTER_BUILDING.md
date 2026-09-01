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
| `MAX_AMMO` | 3.0 | Ammo pips. Everyone gets three. |
| `AMMO_RECHARGE_SECONDS` | 1.8 | The *Normal* reload tier; per-kit `reload` overrides it. |
| `MOVE_SPEED` | 7.0 m/s | The *Normal* speed tier; per-kit `move_speed` overrides it. |
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
| Very Slow | 5.6 | 0.80× |
| Slow | 6.3 | 0.90× |
| **Normal** | **7.0** | 1.00× |
| Fast | 7.7 | 1.10× |
| Very Fast | 8.4 | 1.20× |

7.0 m/s is 3.5 tiles/second. The spread from Very Slow to Very Fast is 50% —
big enough that speed alone decides who picks the fight.

### Reload

Seconds to regain **one** ammo pip. Three pips means a full magazine takes 3×
this.

| Tier | Seconds | Full magazine |
|---|---|---|
| Very Slow | 2.6 | 7.8s |
| Slow | 2.2 | 6.6s |
| **Normal** | **1.8** | 5.4s |
| Fast | 1.4 | 4.2s |
| Very Fast | 1.0 | 3.0s |

**Reload does not change a fighter's damage per second** — the formula in §3
scales damage-per-attack by the reload time, so sustained output stays on
budget either way. What reload actually controls is *burst vs. chip*: a Very
Slow reload means one enormous, committing swing; a Very Fast reload means a
stream of small hits you can course-correct mid-fight. Pick it for feel.

### Range

In tiles. The hard limit is the screen — see §4.

| Tier | Tiles | Meters |
|---|---|---|
| Very Short (melee) | 1.5 – 2.0 | 3 – 4 |
| Short | 2.5 – 3.0 | 5 – 6 |
| **Medium** | **3.5 – 4.5** | 7 – 9 |
| Long | 5.0 – 5.5 | 10 – 11 |

There is deliberately **no "Very Long" tier.** 5.5 tiles is the edge of the
screen; past that a fighter is shooting at something the player cannot see.

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

A is the factor most worth measuring rather than guessing, because the spread is
wider than it looks. From `hits/atk` and the projectile-fate table:

| delivery | measured hit rate |
|---|---|
| Henry, one 110° melee swing | **85%** |
| Tony, one lobbed 1.4m AOE | **81%** |
| Nova, 5 pellets converging at 2.7m | **47%** |
| Leon, 6 buttons thrown 7m | **39%** |

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

The match camera is **orthographic**, `size = 12.9` (metres of vertical view),
sitting at offset `(0, 16, 9.2)` — a 60.1° pitch — with the player dead centre
(`main.gd`, `CAMERA_OFFSET` / `CAMERA_ORTHO_SIZE`). That fixes exactly how far
a player can see from their own fighter:

| Direction | Visible from the player |
|---|---|
| Left / right | 11.5 m = **5.7 tiles** |
| Up / down the screen | 7.4 m = **3.7 tiles** |

Up-screen is much shorter because the ground is foreshortened by the camera
pitch. So:

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

Seven fighters, all rebalanced to this framework.

| Fighter | Role | Health | Speed | Reload | Range | A | U | eDPS | Damage / attack |
|---|---|---|---|---|---|---|---|---|---|
| **Nova** | Shotgunner | Normal 5000 | Normal 7.0 | Normal 1.8 | Medium 4.5 | 1.15 | — | 805 | 1450 (5 × 290) |
| **Tony** | Artillery | Low 4250 | Slow 6.3 | Slow 2.2 | Long 5.5 | 0.85 | — | 564 | 1240 |
| **Henry** | Heavyweight | High 5750 | Slow 6.3 | Slow 2.2 | V.Short 1.9 | 0.85 | — | 736 | 1620 |
| **Sanjit** | Assassin | Low 4250 | V.Fast 8.4 | Fast 1.4 | V.Short 1.5 | 1.00 | — | 807 | 1130 (2 × 565) |
| **Kovacs** | Tank | V.High 6500 | V.Slow 5.6 | Normal 1.8 | Short 2.5 | 0.85 | — | 667 | 1200 |
| **Leon** | Controller | Low 4250 | Normal 7.0 | Fast 1.4 | Long 5.0 | 1.40 | — | 876 | 1224 (6 × 204) |
| **Anders** | Skirmisher | Normal 5000 | Normal 7.0 | Slow 2.2 | Long 5.5 | 1.00 | 1.00 | 591 | 1300 |

**Nova is the reference kit** — Normal in all four tiers, so her only modifier
is the 1.15 for a shotgun that has to close distance. Every other fighter is
readable as a deviation from her.

**Don't stack A and U on the same kit without proof.** Anders originally took
both discounts (0.85 × 0.85 = 0.72) and finished a 120-match sim at 2.7% wins.
Two lessons: piercing and bouncing are worth nothing if the *first* hit misses,
so a slow projectile is Fair delivery and not Forgiving; and a utility you can
only get by luck is not a utility. His sack now returns to him reliably rather
than depending on a random bounce, and U rides free until a sim says otherwise.

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

This matters more than it sounds. With no lead at all, a 25 m/s pellet crossing
7 m is airborne 0.28s while a 7 m/s target travels ~2 m — over three times its
own hitbox — so **every projectile kit misses a moving fighter and only
instant-hit kits (melee, shockwave) ever connect.** A no-lead sim doesn't rank
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
like obvious overtuning. After it they were 15% and 14% against a 14.3% target,
with no stat changed. **Fix the instrument before you touch a kit.**

`NS3_SIM_SPEED=<n>` overrides the 10x default. If a result smells like a physics
artifact, run the same matches at `2` and compare `hits/atk`: real balance
differences hold across time scales, tick-rate artifacts vanish.
