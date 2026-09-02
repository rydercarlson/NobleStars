class_name Kits
## Fighter kit data, ported from the SpriteKit game's FighterKit/Weapon.
## Distances are in meters; TILE converts from the 2D game's tile units.
##
## Every kit is statted against CHARACTER_BUILDING.md in the repo root: pick one
## tier from each of health / speed / reload / range, then DERIVE damage from the
## formula there rather than picking it by taste. The tier comment above each kit
## is the record of that choice — keep it in sync when you retune.

const TILE := 2.0

## Fighter width — the unit every "body-width" figure in SHOT_FEEL.md is in.
## 1.30 m across. The match camera shows 23 m, so that is 17.7 fighters wide
## against the ~21 brawlers Brawl Stars fits on screen: deliberately chunkier,
## which is what lets fighters move faster than Brawl Stars without shots
## becoming impossible to aim. Grow this and every range gets shorter in the
## units that actually decide whether a shot lands.
const FIGHTER_RADIUS := 0.65
## Models are authored against the old 0.45 capsule; keep them in step with it.
const MODEL_SCALE := 1.44

# Speed tiers (m/s). Normal is 2.8 tiles/second = 4.31 body-widths/second.
# THIS IS THE FEEL DIAL — see SHOT_FEEL.md §6.
#
# Judge it in body-widths per second, never in m/s: perceived speed tracks
# body-lengths, so widening the fighter SLOWS the game down at a fixed m/s.
# The original game was 7.0 m/s on a 0.90 m fighter = 7.78 body-widths/s; this
# is 55% of that feel, where the raw m/s number alone reads like 80%.
#
# Every projectile speed below is a multiple of one of these constants, so
# raising a tier speeds its shots up with it and aiming difficulty (lead/hit)
# stays put. What moves is the player's reaction window: dodge = lead/hit x
# hit_width / move - 0.25s, so going faster has to be paid for with fatter
# projectiles. Below ~0.15s of window a shot stops reading as a travelling
# object and reads as hitscan — that was "Hammy beams people".
const SPEED_VERY_SLOW := 4.48
const SPEED_SLOW := 5.04
const SPEED_NORMAL := 5.60
const SPEED_FAST := 6.16
const SPEED_VERY_FAST := 6.72

## Ground speed the Meshy run clips were tuned against. Stride is scaled
## against THIS, not against SPEED_NORMAL — the clips were matched when a
## fighter moved 7 m/s, so referencing the current Normal tier keeps the legs
## churning at their old rate while the body covers less ground, which reads as
## sluggish no matter what the speed number says.
const RUN_CLIP_SPEED := 7.0

# Reload tiers: seconds to regain one of the three ammo pips. Reload does not
# change sustained DPS (the damage formula scales the hit by it) — it decides
# whether a kit feels like one committing swing or a stream of chip damage.
const RELOAD_VERY_SLOW := 2.6
const RELOAD_SLOW := 2.2
const RELOAD_NORMAL := 1.8
const RELOAD_FAST := 1.4
const RELOAD_VERY_FAST := 1.0

# Health tiers. Damage across the roster is balanced against HEALTH_NORMAL.
const HEALTH_VERY_LOW := 3500
const HEALTH_LOW := 4250
const HEALTH_NORMAL := 5000
const HEALTH_HIGH := 5750
const HEALTH_VERY_HIGH := 6500

const MAX_AMMO := 3.0
const AMMO_RECHARGE_SECONDS := RELOAD_NORMAL   # default; kits override via "reload"
const SUPER_CHARGE_DAMAGE := 3500.0            # 0.7 healthbars to charge a Super
const REGEN_DELAY := 3.0
const REGEN_RATE_PER_SECOND := 0.14
const BASE_MAX_HEALTH := HEALTH_NORMAL         # default; kits override via "max_health"
const HEALTH_PER_CUBE := 550                   # 11% of base health
const DAMAGE_BONUS_PER_CUBE := 0.10
const MOVE_SPEED := SPEED_NORMAL               # default; kits override via "move_speed"

# Weapons cap at 5.5 tiles and Supers at 6.0 — past that a fighter is shooting
# at something off the player's screen. See CHARACTER_BUILDING.md section 4.
# 5.5 tiles is 11 m = 8.5 body-widths against Brawl Stars' longest at 10.0, so
# the cap did not need to move once fighters grew — growing them is what pulled
# every range in, in the units that decide whether a shot lands.
const MAX_WEAPON_RANGE_TILES := 5.5
const MAX_SUPER_RANGE_TILES := 6.0

## Direct-fire projectiles travel this many times the firer's move speed. Brawl
## Stars sits near 4.9; we sit near 3.1 because our fighters move roughly 1.7x
## faster than theirs relative to body size, and the ratio has to come down to
## keep a shot in the air long enough to react to. The ratio is a means, not the
## goal — `dodge window` and `lead/hit` are what the player feels, and both are
## on target. What we DO copy is that speed never tracks range: it correlates
## with range at r=0.05 there, with flight time at r=0.86. A kit may deviate
## about +/-20% for character (a sniper's shot snaps, a controller's floats),
## never to compensate for how far it has to travel. Lobs and arcing attacks are
## the deliberate exception again, down at ~1.7-2.2.
const PROJECTILE_SPEED_RATIO := 3.1

## Minimum gap between two attacks, as a fraction of the reload. Brawl Stars
## documents 0.5s for Piper against her 2.3s reload. Without this an entire
## magazine leaves the barrel in one flick — 72-97% of a healthbar with no
## reaction window — and the reload tier below controls nothing but the wait
## afterwards. See SHOT_FEEL.md section 8.
const ATTACK_COOLDOWN_RATIO := 0.22

## Seconds a fighter must wait between attacks, derived from its reload tier.
static func attack_cooldown_for(reload_seconds: float) -> float:
	return reload_seconds * ATTACK_COOLDOWN_RATIO

## The speed to lead a shot by — how fast it closes on its target, which is not
## always how fast it travels. A weaving shot (Ayaan's Slalom) spends part of
## every metre on the swerve, so `distance / speed` under-states its flight time
## and both the bots and the player's tap-fire would aim short. CHARACTER_BUILDING
## section 8: "If you add a new attack style, check `_aim_point` knows its flight
## time."
static func aim_speed(weapon: Dictionary, aim_distance := -1.0) -> float:
	var speed: float = float(weapon.get("speed", 0.0))
	if not weapon.has("curve_min_deg"):
		return speed * curve_axial_factor(float(weapon.get("curve_deg", 0.0)))
	# A Slalom shot's swerve depends on how far it was aimed, so its flight time
	# does too. A caller with no distance to hand gets the middle of the band
	# rather than either extreme, which are 20% apart.
	var d := aim_distance if aim_distance >= 0.0 else \
			(float(weapon.range) + float(weapon.get("range_min", weapon.range))) * 0.5
	return speed * curve_axial_factor(float(slalom_weave(weapon, d).curve_deg))

## The fraction of its own speed a shot swerving `curve_deg` off the aim line
## makes good ALONG that line: the mean of `cos(A·cos wt)` over a period, which
## is the Bessel function J0(A). The series is within a few tenths of a percent
## out to the 58 degrees Slalom's hardest braid uses, and the floor guards
## against anyone pushing the swerve past where the series is honest.
static func curve_axial_factor(curve_deg: float) -> float:
	var a := deg_to_rad(curve_deg)
	if a <= 0.0:
		return 1.0
	var a2 := a * a
	return maxf(0.3, 1.0 - a2 / 4.0 + a2 * a2 / 64.0)

## The weave a Slalom shot flies when it is aimed `aim_distance` out:
## `{period, reach, curve_deg, waves, gate}`.
##
## ONE RULE: **the shot ends where you aimed, and the pair meets there.** What
## the aim distance buys is the SHAPE of the trip, and the two ends of the band
## are all but different weapons:
##
##   aimed long  -> one lazy arc. A gentle 27-degree swerve, bowing wide enough
##                  to pass either side of a body, meeting once at 4.5 tiles.
##   aimed short -> a hard 58-degree braid, crossing three times inside 2.8
##                  tiles. Dense and hard to slip, and it gets nowhere.
##
## **A braid cannot be long-ranged, by construction** — Ryder's rule from
## playtest, given twice: "the less wiggled it is the more range he gets", then
## "the more braided it is the shorter it should go". The build before this one
## had it exactly backwards, and the reason is worth keeping: it capped the
## crossing SPACING instead of the crossing COUNT, so reaching further needed
## more crossings, and the longest shot came out as the tightest braid. Cap the
## count and the whole thing inverts into the shape it should have been.
##
## Every caller hands this a distance without needing to know any of that — a
## drag has its own length, a tap has the distance to the target, a bot has the
## distance to its lead point — so drag, tap, bot and the net replay all agree.
static func slalom_weave(weapon: Dictionary, aim_distance: float) -> Dictionary:
	var reach_max: float = float(weapon.range)
	var reach_min: float = float(weapon.get("range_min", reach_max))
	var reach := clampf(aim_distance, reach_min, reach_max)
	var t := (reach - reach_min) / maxf(0.01, reach_max - reach_min)
	var curve := lerpf(float(weapon.get("curve_max_deg", 0.0)),
			float(weapon.get("curve_min_deg", 0.0)), t)
	var most := int(weapon.get("waves_max", 3))
	# Whole half-waves only. The pair is back ON the line only at a whole one, so
	# a fractional count would end the shot mid-swing and break the one promise
	# the weapon makes.
	var waves := clampi(int(round(lerpf(float(most), 1.0, t))), 1, most)
	var axial: float = float(weapon.speed) * curve_axial_factor(curve)
	return {"period": 2.0 * (reach / float(waves)) / maxf(0.01, axial),
			"reach": reach, "curve_deg": curve, "waves": waves,
			"gate": reach / float(waves)}

enum Style { PELLETS, LOB, MELEE, DASH, BOOMERANG, SHOCKWAVE, JUMP_SMASH, BUTTONS, DISCONNECT, KEEP_IT_UP, POP_OFF, SLALOM, DOWNHILL }

static func all() -> Array:
	return [nova(), tony(), henry(), sanjit(), kovacs(), leon(), anders(), hammy(),
			ayaan()]

static func named(kit_name: String) -> Dictionary:
	for k in all():
		if k.name.to_lower() == kit_name.to_lower():
			return k
	return nova()

## Health Normal · Speed Normal · Reload Normal · Range Medium 4.3
## The reference kit: Normal in all four tiers, so her only modifier is A=1.15
## for a shotgun that has to close distance to land the full burst. Every other
## fighter reads as a deviation from Nova.
## A=1.00 measured: her pellets now land 69% of the time, up from the 47% that
## justified 1.15, because the fighter got wider and the pellets got fatter.
## 1250 × 1.000(R) × 1.00(G) × 1.00(M) × 1.00(S) × 1.00(A) = 1250 → 5 × 250
static func nova() -> Dictionary:
	return {
		"name": "Nova", "color": Color(0.25, 0.75, 0.95),
		"role": "Shotgunner",
		"desc": "Mid-range shotgun burst — shreds up close, fades with distance.",
		"super_desc": "A wall-busting mega blast that knocks enemies flying.",
		"max_health": HEALTH_NORMAL,
		"move_speed": SPEED_NORMAL,
		"reload": RELOAD_NORMAL,
		# Her pellets only converge up close, so bots must hug rather than take
		# the default 0.7 standoff — at 0.7 x range only the centre pellet hits.
		"ideal_range_mult": 0.30,
		"weapon": {
			"style": Style.PELLETS, "pellets": 5, "spread_deg": 22.0, "damage": 250,
			"range": 4.3 * TILE, "speed": SPEED_NORMAL * 3.05, "radius": 0.44,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 2.4x total, spread over 9 pellets that rarely all connect.
		"super": {
			"style": Style.PELLETS, "pellets": 9, "spread_deg": 34.0, "damage": 333,
			"range": 5.0 * TILE, "speed": SPEED_NORMAL * 3.30, "radius": 0.52,
			"destroys_walls": true, "knockback": 12.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

## Health Low · Speed Slow · Reload Slow · Range Long 5.5
## Artillery: the longest weapon range in the game and an AOE that arcs over
## walls with no line-of-sight check, paid for with the squishiest slow body.
## A=1.00 measured (74%), not the 0.85 a lob's AOE implies: the blast only
## forgives a miss if the shell ARRIVES near the target, and an arc long enough
## to clear a wall gives the target time to leave. Forgiving was aspirational.
## 1250 × 1.222(R) × 0.85(G) × 1.06(M) × 1.06(S) × 1.00(A) = 1459
static func tony() -> Dictionary:
	return {
		"name": "Tony", "color": Color(0.98, 0.85, 0.25),
		"role": "Artillery",
		"desc": "Lobs explosive shells over walls that blast an area on impact.",
		"super_desc": "A piercing cannon shot that smashes straight through walls.",
		"model": "res://assets/tony.glb",
		"clips": {"idle": "Idle", "run": "Running", "attack": "Thrust_Slash",
				  "attack_speed": 3.0},
		"max_health": HEALTH_LOW,
		"move_speed": SPEED_SLOW,
		"reload": RELOAD_SLOW,
		"weapon": {
			# 3.0x, not the 2.1x the dodge-window maths alone wanted. A lob
			# resolves where it LANDS, so its AOE only forgives a miss if the
			# shell arrives near the target — a longer hang amplifies any lead
			# error instead of being paid for by the blast radius. Slowing it to
			# 2.1x dropped his measured hit rate from 81% to 63% in NS3_SIM. At
			# 3.0x the shell hangs 0.73s and the target covers 4.1 m, which is
			# what it covered before the retune. See CHARACTER_BUILDING.md:
			# "An arcing attack has to be timed against how fast people move."
			"style": Style.LOB, "pellets": 1, "spread_deg": 0.0, "damage": 1459,
			"range": 5.5 * TILE, "speed": SPEED_SLOW * 3.00, "radius": 0.42,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.7 * TILE, "water_mult": 1.0,
		},
		# 1.8x for one reliable piercing hit.
		"super": {
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 2626,
			"range": 6.0 * TILE, "speed": SPEED_SLOW * 3.90, "radius": 0.56,
			"destroys_walls": true, "knockback": 10.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

## Health Normal · Speed Very Fast · Reload VERY FAST · Range Very Short 1.4
## Assassin: fastest fighter in the game and the quickest reload, so he picks
## every fight — but he still has to get inside 2.8 metres to throw a punch.
## A=1.15, measured: the one-two lands 59% per strike where Henry's single
## sweep lands 86%, because the second punch arrives 0.22s late through a 70
## degree arc rather than 110. He was priced as the most reliable melee in the
## game while being the least. Health moved Low -> Normal because his measured
## shortfall was attack opportunity (5.0 swings per life, the fewest of anyone)
## rather than damage — a bigger hit is worth nothing if he dies on the walk in.
## A HELD at 1.15 against a measured 62%, which would band to 1.00. Melee hit
## rates are the one thing NS3_SIM inflates: bots walk at each other in straight
## lines, so a punch lands far more often there than against a player who kites
## — Henry measures 93% in-sim against the 85% this doc recorded from play.
## Deriving A from an inflated rate would under-pay every melee kit. Ranged hit
## rates have no such bias, so they are derived. Revisit off a playtest.
##
## The combo LUNGES. He was the only melee kit with no gap-closer: Henry dashes
## and Kovacs leaps, but Sanjit's Super throws his staff AWAY from him, so his
## only approach was legs. Very Fast is +1.12 m/s over a Normal kit, which put
## Hammy's 11 m at 7.3 seconds of chase — 3.3 sniper shots, 4113 of his 5000
## health, arriving with nothing left. Each strike now carries him 0.8 m, so a
## full magazine buys 4.8 m almost at once and the chase drops to ~3s. It fires
## on a whiff too, so swinging at air is a legitimate way to travel.
##
## Reload Fast -> Very Fast is a FEEL change, not a power one: the formula
## scales damage per attack by reload, so eDPS is 879 either way. It buys the
## fastest cadence in the game to steer a dive with, and the lunge is the
## actual buff. Hits-to-kill lands at 5.7, outside the 3-5 band — accepted,
## because for the fastest reload in the roster "more, smaller hits" IS the
## tier, and time-to-kill is 5.7s against a roster median near 7s.
## 1250 × 0.556(R) × 1.25(G) × 0.88(M) × 1.00(S) × 1.15(A) = 879 → 2 × 440
static func sanjit() -> Dictionary:
	# Fast brawler: MELEE with pellets=2 is a one-two punch (second hit lands
	# a beat later); the Super staff flies out over walls and boomerangs back,
	# hitting on both passes.
	return {
		"name": "Sanjit", "color": Color(0.95, 0.5, 0.2),
		"role": "Assassin",
		"desc": "Fast on his feet with a lightning one-two punch combo.",
		"super_desc": "Hurls his staff over walls; it boomerangs back, hitting both ways.",
		"model": "res://assets/sanjit.glb",
		"clips": {"idle": "Idle", "run": "Running", "attack": "Double_Combo_Attack",
				  "attack_speed": 4.5,
				  # The Super plays the real throw: Crouch_Charge_and_Throw is
				  # 7.7s of crouch-charge-release; seeking to 5.2s at 4x shows
				  # the coil, the release (~0.1s in, matching the boomerang
				  # spawn), and the follow-through in ~0.6s.
				  "super": "Crouch_Charge_and_Throw", "super_speed": 4.0,
				  "super_seek": 5.2},
		"max_health": HEALTH_NORMAL,
		"move_speed": SPEED_VERY_FAST,
		"reload": RELOAD_VERY_FAST,
		"weapon": {
			"style": Style.MELEE, "pellets": 2, "spread_deg": 70.0, "damage": 440,
			"range": 1.4 * TILE, "speed": 0.0, "radius": 0.0,
			# metres carried forward per strike; see the note above.
			"lunge": 0.8,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 2.4x total split across the two passes -> 1.2x per pass.
		"super": {
			"style": Style.BOOMERANG, "pellets": 1, "spread_deg": 0.0, "damage": 1056,
			"range": 5.0 * TILE, "speed": SPEED_VERY_FAST * 2.85, "radius": 0.64,
			"destroys_walls": false, "knockback": 4.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

## Health High · Speed Slow · Reload Slow · Range Very Short 1.5
## Heavyweight: the hardest single hit in the game off a 110-degree arc that is
## very hard to miss, but slow to swing and slow to walk into range.
## 1250 × 1.222(R) × 1.25(G) × 1.06(M) × 0.94(S) × 0.85(A) = 1617
static func henry() -> Dictionary:
	return {
		"name": "Henry", "color": Color(0.45, 0.55, 0.95),
		"role": "Heavyweight",
		"desc": "Wide paddle sweeps that punish anyone who gets too close.",
		"super_desc": "A charging dash that doubles its punch across water.",
		"model": "res://assets/henry.glb",
		"clips": {"idle": "Idle", "run": "Running", "attack": "Attack_Sweep",
				  "attack_speed": 1.0},
		"max_health": HEALTH_HIGH,
		"move_speed": SPEED_SLOW,
		"reload": RELOAD_SLOW,
		"weapon": {
			"style": Style.MELEE, "pellets": 1, "spread_deg": 110.0, "damage": 1620,
			"range": 1.5 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 1.4x, not 1.8x: the dash is also mobility, knockback, and doubles its
		# damage across water. water_mult 2.0 puts it at 4540 on a crossing, so
		# a bigger base number here would one-shot most of the roster.
		"super": {
			"style": Style.DASH, "pellets": 1, "spread_deg": 0.0, "damage": 2270,
			"range": 3.4 * TILE, "speed": SPEED_SLOW * 3.20, "radius": 0.0,
			"destroys_walls": false, "knockback": 9.0, "pierces": false,
			"aoe": 0.0, "water_mult": 2.0,
		},
	}

## Health Very High · Speed Very Slow · Reload Normal · Range Short 2.4
## Tank: the biggest healthbar and the slowest legs. His clap pierces a
## 78-degree cone, so it lands on everyone in front without needing precision.
## 1250 × 1.000(R) × 1.15(G) × 1.12(M) × 0.88(S) × 0.85(A) = 1204
static func kovacs() -> Dictionary:
	# Clip timing: Angry_Ground_Stomp_2 is 1.8s with the foot landing at 0.68s,
	# so at 3x the wave is held 0.23s to fire on impact. Backflip_and_Rise is
	# 2.7s and crashes down at 1.30s; at 2.7x that lands 0.48s in — exactly the
	# leap duration in Fighter.begin_leap — and the rise plays after the smash.
	return {
		"name": "Kovacs", "color": Color(0.38, 0.82, 0.58),
		"role": "Tank",
		"desc": "A durable front-liner whose thunderclap sends a short shockwave ahead.",
		"super_desc": "Leaps forward, then slams the ground to unleash a damaging shockwave.",
		"model": "res://assets/kovacs.glb",
		"clips": {"idle": "Idle", "run": "Running", "attack": "Angry_Ground_Stomp_2",
				  "attack_speed": 3.0,
				  "super": "Backflip_and_Rise", "super_speed": 2.7},
		"max_health": HEALTH_VERY_HIGH,
		"move_speed": SPEED_VERY_SLOW,
		"reload": RELOAD_NORMAL,
		"weapon": {
			"style": Style.SHOCKWAVE, "pellets": 1, "spread_deg": 78.0, "damage": 1200,
			"range": 2.4 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 4.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0, "delay": 0.23,
		},
		# 1.4x: the leap is a gap-closer and an escape on top of the damage.
		"super": {
			"style": Style.JUMP_SMASH, "pellets": 1, "spread_deg": 360.0, "damage": 1680,
			"range": 3.6 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 10.0, "pierces": true,
			"aoe": 2.15 * TILE, "water_mult": 1.0,
		},
	}

## Health Low · Speed Normal · Reload Fast · Range Long 4.8
## Controller: a fast, chippy stream of six buttons in a tight cone. Fragile,
## and each button is small, so he wins by attrition rather than by bursts.
## A=1.40 (Very Demanding), measured rather than guessed: six small projectiles
## thrown 7 m with no AOE to forgive a near miss land 39% of the time, where
## Henry's single melee swing lands 85%. Priced at A=1.00 he realised 251 eDPS
## against a roster median near 470, and no amount of delivery fixing moved it
## (see CHARACTER_BUILDING.md section 3).
## A=1.15 measured: his buttons land 50% of the time now, up from the 39% that
## justified 1.40. Still Demanding — six small projectiles thrown 9.6 m — but no
## longer the outlier tier. He was the strongest kit in the roster at 1.40.
## 1250 × 0.778(R) × 0.85(G) × 1.00(M) × 1.06(S) × 1.15(A) = 1008 → 6 × 168
static func leon() -> Dictionary:
	# Clip timing: both casts are long wind-ups, so they seek straight to their
	# release frames — mage_soell_cast_3 throws at 0.90s (seek 0.6 @ 4x fires
	# 0.075s in), mage_soell_cast_2 slams at 1.28s (seek 0.75 @ 3x, 0.18s in).
	return {
		"name": "Leon", "color": Color(0.72, 0.38, 0.95),
		"role": "Controller",
		"desc": "Rapid-fires six controller buttons in a tight medium-range cone.",
		"super_desc": "Disconnect: lobs a controller that blasts an area, then leaves a field that keeps enemies from attacking.",
		"model": "res://assets/leon.glb",
		"clips": {"idle": "Idle", "run": "Running", "attack": "mage_soell_cast_3",
				  "attack_speed": 4.0, "attack_seek": 0.6,
				  "super": "mage_soell_cast_2", "super_speed": 3.0,
				  "super_seek": 0.75},
		"max_health": HEALTH_LOW,
		"move_speed": SPEED_NORMAL,
		"reload": RELOAD_FAST,
		"weapon": {
			# 7 degrees, not 10: the outer buttons sit at +/-3.15 deg, so at his
			# full 9.6 m range they land 0.53 m off centre and still connect with
			# a 2.02 m hittable width. At 10 deg they missed past about 8 m.
			"style": Style.BUTTONS, "pellets": 6, "spread_deg": 7.0, "damage": 168,
			"range": 4.8 * TILE, "speed": SPEED_NORMAL * 3.20, "radius": 0.46,
			"destroys_walls": false, "knockback": 1.5, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
			# A tight cone of six is Colt's stream, not Shelly's shotgun blast:
			# they leave 0.05s apart so the attack reads as a burst of buttons
			# rather than a wall of geometry appearing at once. Brawl Stars
			# spaces its stream attacks the same way (Ruffs 0.2s, Larry 0.3s).
			"unload": 0.05,
		},
		# 1.4x: the damage is incidental, the silence is the payload. The blast
		# hard-stops everyone it catches for `disconnect_seconds`; the field it
		# leaves then holds `zone_seconds` as denied ground — anyone standing in
		# it cannot attack, and the silence lifts a beat after they step off.
		"super": {
			"style": Style.DISCONNECT, "pellets": 1, "spread_deg": 360.0, "damage": 1411,
			"range": 4.8 * TILE, "speed": SPEED_NORMAL * 2.10, "radius": 0.66,
			"destroys_walls": false, "knockback": 5.0, "pierces": false,
			"aoe": 1.7 * TILE, "water_mult": 1.0, "disconnect_seconds": 2.4,
			"zone_seconds": 4.0,
		},
	}

## Health High · Speed Normal · Reload Normal · Range Medium 3.5 · ONE ammo
## Mid-range thrower. Every throw is aimed; the sack arcs onto a spot, damages
## what is there, and hops home. Catching it refunds the pip instantly and
## steps a streak (+25% per step, 3 deep) so the next throw lands harder —
## catching is TEMPO, not free damage. Drop it and he pays the full 1.8s and
## the streak resets, so his fire rate is a skill expression rather than a
## timer.
##
## He used to rally himself: after one aimed kick the sack picked its own
## targets and kicked itself out for ~2.5s while the player could only walk.
## It tuned fine and played badly — five configurations moved his win rate
## between 3.8% and 25.6% without changing how he felt, because the problem was
## never damage. He got ~2.7 aimed inputs per 10s against ~5.5 for the rest of
## the roster, each resolving two seconds later and decided by code.
##
## One ammo still, because one sack exists at a time — but the pip is no longer
## a timer he waits on, it is refunded by playing well.
##
## Calibrated, not computed: a streak makes `damage_per_attack` ambiguous, so
## he is set against measured eDPS like the doc's rally note says.
static func anders() -> Dictionary:
	return {
		"name": "Anders", "color": Color(0.2, 0.88, 0.78),
		"role": "Skirmisher",
		"model": "res://assets/anders.glb",
		# Clip timing, measured off the export: the kick's foot speed peaks at
		# 0.54s, so seeking to 0.28 at 2.2x strikes ~0.12s after the cast. The
		# backflip is airborne 0.60-1.35s, and Pop Off's leap lasts 0.48s
		# (fighter.gd:begin_leap), so seeking to 0.55 at 1.6x puts the flight
		# over the leap and leaves the landing recovery to play after it.
		"clips": {"idle": "Idle", "run": "Running", "attack": "Kick_a_Soccer_Ball",
				  "attack_speed": 2.2, "attack_seek": 0.28,
				  "super": "Backflip", "super_speed": 1.6, "super_seek": 0.55},
		"desc": "Throws a hacky sack that arcs down on a spot — catch it on the way back to reload instantly and hit harder next throw.",
		"super_desc": "Pop Off: flicks the sack up and leaps clear, then spikes the ground he left, blasting everyone there away from him.",
		"max_health": HEALTH_HIGH,
		"move_speed": SPEED_NORMAL,
		"reload": RELOAD_NORMAL,
		"ammo": 1,
		"weapon": {
			# speed is the ARC's travel rate, not a bullet's — and a sack is a
			# LANDING-SPOT weapon, so it is timed against how far the target
			# moves, NEVER by the dodge-window rule that sets projectile speeds.
			# At 1.70x the opening 5.6 m kick hung 0.59s while a 5.6 m/s target
			# covered 3.3 m against a 1.9 m landing radius, and a third of every
			# sack's landings hit bare floor. 3.0x brings the hop to 0.33s and
			# the drift to 1.9 m, so it connects without needing the lead to be
			# right. Exactly the same rule as Tony's shell — an arcing attack is
			# timed against movement, not against reaction time.
			"style": Style.KEEP_IT_UP, "pellets": 1, "spread_deg": 0.0, "damage": 900,
			"range": 3.5 * TILE, "speed": SPEED_NORMAL * 3.00, "radius": 0.44,
			"destroys_walls": false, "knockback": 3.0, "pierces": false,
			"aoe": 0.95 * TILE, "water_mult": 1.0,
			# The kick blasts the ground Anders kicks from, at `kick_damage_mult`
			# of whatever the rally is worth. This is where his burst lives now:
			# the landings alone gave him a third of the roster's burst DPS
			# because the two hops HOME dealt nothing at all.
			#
			# It is ANTI-DIVE, not burst, and it is not funded out of base
			# damage. Measured: only ~38% of blasts hit anything, because the
			# blast is centred on Anders and Anders is a mid-range skirmisher
			# who is usually not next to anyone when he catches — the more he
			# holds his distance (which is the point of not leading him on the
			# hop home), the more it whiffs. Cutting base damage 1100 -> 850 to
			# pay for it therefore just made him worse: 8.6% -> 6.0%. It earns
			# its keep by punishing someone who closed on him, and his burst
			# has to come from somewhere else.
			"kick_aoe": 1.2 * TILE, "kick_damage_mult": 0.45,
		},
		# The escape is the utility, so 1.4x rather than 1.8x. `range` is how far
		# he leaps. The spike arcs down onto the ground he vacated and blasts
		# `aoe` there — a spot, not a line, because the leap takes half a second
		# and a thin projectile fired down a fixed vector could not catch anyone
		# who had moved. speed is the spike's dive rate, so it lands fast.
		"super": {
			# spread_deg 360 so the blast ring draws as a full circle.
			"style": Style.POP_OFF, "pellets": 1, "spread_deg": 360.0, "damage": 1800,
			"range": 2.8 * TILE, "speed": SPEED_NORMAL * 2.80, "radius": 0.48,
			"destroys_walls": false, "knockback": 14.0, "pierces": true,
			"aoe": 1.7 * TILE, "water_mult": 1.0,
		},
	}

## Health Very Low · Speed Normal · Reload Slow · Range Long 5.5
## Sniper: one big basketball at the screen-range cap. Consecutive fighter hits
## light him On Fire.
##
## A=0.85 measured (83%), and U goes back to 1.00 to pay for it. A and U are
## both discounts, and 0.85(G) × 0.85(A) × 0.85(U) = 0.61 is exactly the
## stacked-discount trap CHARACTER_BUILDING.md records Anders falling into at
## 2.7% wins. The sim is the proof that doc asks for: 3.8% over 240 matches.
##
## Note what this does NOT fix. His delivery is fine — 83%, the second-best in
## the roster. He loses because he gets 5.1 attacks a life on 3500 health, so
## the shortfall is uptime, not damage per shot, and the damage formula has no
## lever for that. If he still loses after a playtest, the honest fix is his
## health tier, which is a change to the character rather than to its maths.
## 1250 × 1.222(R) × 0.85(G) × 1.00(M) × 1.12(S) × 0.85(A) × 1.00(U) = 1236
static func hammy() -> Dictionary:
	return {
		"name": "Hammy", "color": Color(1.0, 0.36, 0.08),
		"role": "Sniper",
		"model": "res://assets/hammy.glb",
		# The export only has one shooting take. Crop its long four-second recovery
		# and accelerate the follow-through after the ball leaves his hand. The
		# Super explicitly owns a tighter version of the take so menus expose a
		# SUPER preview instead of silently falling back to the basic attack.
		"clips": {"idle": "Idle", "run": "Running",
				  "attack": "baseball_pitching", "attack_speed": 2.8,
				  "attack_fast_at": 1.15, "attack_end_speed": 6.0,
				  "attack_end": 2.05,
				  "super": "baseball_pitching", "super_speed": 3.2,
				  "super_fast_at": 1.05, "super_end_speed": 7.0,
				  "super_end": 1.90},
		"desc": "Sinks long-range three-pointers; three consecutive hits set his shots On Fire.",
		"super_desc": "Bank Is Open: fires a huge basketball that gains power on every wall bounce and sets enemies on fire.",
		"max_health": HEALTH_VERY_LOW,
		"move_speed": SPEED_NORMAL,
		"reload": RELOAD_SLOW,
		"weapon": {
			# 3.6x is the fast end of the house band — he is the sniper, and
			# Brawl Stars gives its snipers the quick end too. Even so the shot
			# is airborne 0.55s at full range, which leaves 0.30s of reaction
			# after a human's 0.25s: he aims now instead of beaming.
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 1236,
			"range": 5.5 * TILE, "speed": SPEED_NORMAL * 3.60, "radius": 0.62,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0, "heat_trait": true,
			"projectile_color": Color(1.0, 0.34, 0.04),
		},
		# The direct hit is deliberately modest: banking is the point. Each wall
		# adds 25%, so three clean banks ramp 1600 -> 3125 before the fire damage.
		"super": {
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 1580,
			"range": 6.0 * TILE, "speed": SPEED_NORMAL * 3.30, "radius": 0.70,
			"destroys_walls": false, "knockback": 5.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0, "bounces": 3,
			"bounce_damage_mult": 1.25, "bounce_speed_mult": 1.08,
			"burn_duration": 3.0, "burn_tick_damage": 100,
			"projectile_color": Color(1.0, 0.20, 0.01),
		},
	}

## Health Normal · Speed Fast · Reload Normal · Range Medium 4.0
## Carver: two snow shots that swing off the aim line and cross back onto it at
## a fixed distance. Every other kit in the roster is aimed by ANGLE; Ayaan is
## the only one aimed by DISTANCE, which is the whole reason he exists.
##
## THE WEAVE. Each shot's heading is `base + curve_deg * cos(TAU * t /
## curve_period)`, mirrored between the pair by Projectile's `curve_sign`. The
## offset from the aim line is that heading's integral:
##
##     y(t) ~= (speed * curve_rad / w) * sin(w*t),   w = TAU / curve_period
##
## — zero at the muzzle, +/-1.34 m a quarter period in, and back on the line at
## the HALF period. That crossing is the gate. At 3.2 tiles both shots are dead
## centre and the pair lands as one hit; at 1.6 tiles they are 2.7 m apart and a
## target standing between them eats neither. So his dead zone is not a
## direction, it is a ring, and the counterplay is to stand off the gate.
##
## Range is measured DOWN THE AIM LINE, not along the wandering path (see
## `projectile.gd:_advance`). Otherwise "4.0 tiles" would mean 3.6 for him and
## 4.0 for everyone else, and `bot_brain`'s range gate — which is the straight
## line to the target — would expire his opening shot in mid-air.
##
## A=1.15 is HELD against a measurement of 41%, which bands to 1.40. Two 40-match
## NS3_SIMs read 45.0% and 38.2% of shots finding a body (1684 projectiles), and
## paying Very Demanding would put his eDPS at 914 against the 820 ceiling — the
## sanity check in CHARACTER_BUILDING section 3 refusing the answer. He is also
## already winning 18.5% of his spawns against a 1-in-9 roster, so the correction
## the delivery number asks for is the wrong direction. See the roster note in
## section 7 before touching this; the honest lever is a tier, not the formula.
## 1250 × 1.000(R) × 1.00(G) × 0.94(M) × 1.00(S) × 1.15(A) × 1.00(U) = 1352 → 2 × 676
static func ayaan() -> Dictionary:
	return {
		"name": "Ayaan", "color": Color(0.62, 0.88, 1.0),
		"role": "Carver",
		"desc": "Two snow shots that meet exactly where you aim: one wide arc far out, a tight braid up close.",
		"super_desc": "Downhill: plants his poles and launches into a two-second run you carve with the stick, bulldozing anyone in the way and spraying snow that slows.",
		"max_health": HEALTH_NORMAL,
		"move_speed": SPEED_FAST,
		"reload": RELOAD_NORMAL,
		# A bot aims the gate at whatever it is shooting (its `fire_dist` is the
		# distance to its own lead point), so unlike Nova's 0.30 this is not
		# there to park it on a sweet spot — the sweet spot follows the target.
		# It only keeps the bot off the far edge, where the pair would cross on
		# the same frame the shot expires.
		"ideal_range_mult": 0.75,
		"weapon": {
			# 3.05x. A swerving shot gives up part of every metre to the sideways
			# travel — 5% at his gentlest arc — so the ratio runs a touch fast to
			# keep the long shot inside SHOT_FEEL's numbers: at his 4.5-tile reach
			# the dodge window is 0.26s (floor 0.22) and lead/hit is 1.41 (band
			# tops at 1.45).
			"style": Style.SLALOM, "pellets": 2, "spread_deg": 0.0, "damage": 676,
			"range": 4.5 * TILE, "speed": SPEED_FAST * 3.05, "radius": 0.46,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
			# RANGE IS A BAND and `range` is only its top: the shot ends where it
			# was aimed, anywhere from 2.8 to 4.5 tiles, and the aim point is what
			# picks the shape it flies to get there. The tier stays Medium
			# because the band straddles it, and because the setting that beats
			# cover — the wide single arc — is the LONG one.
			"range_min": 2.8 * TILE,
			# The two ends of that shape. A long shot draws one gentle 27-degree
			# arc, bowing ~1.4 m off the line: wide enough to pass either side of
			# a body and rejoin on it. A short shot swerves 58 degrees and crosses
			# three times inside 2.8 tiles — dense, hard to slip, and it never
			# gets anywhere. Steeper than 58 and the series in
			# `curve_axial_factor` stops being honest.
			"curve_min_deg": 27.0, "curve_max_deg": 58.0,
			# Half-waves at the braided end. Three crossings in 2.8 tiles is a
			# braid; more and it stops reading as two objects.
			"waves_max": 3,
			"projectile_color": Color(0.85, 0.95, 1.0),
		},
		# 1.4x. The ride is two seconds of steerable mobility, a shove that clears
		# bodies out of the lane, and a slow field where it stops — three
		# utilities on top of the hit, which is what the utility tier is for.
		#
		# `range` is the AIM reach: what the indicator draws and what bots gate
		# on. It is NOT how far the run goes — `duration` x `speed` is 23 m. That
		# is travel rather than reach, so it does not break the 6.0-tile Super cap
		# in CHARACTER_BUILDING section 4; nothing is being shot at off-screen.
		#
		# THE RIDE CARVES, and `turn_rate` is the whole feel of it. The history is
		# the tuning guide, so keep it: 2.0 rad/s (a 5.9 m turning circle) and 3.4
		# both read as stiff — the arena decided where the run went, not the
		# player. Uncapped read as a speed boost with a steering wheel, which lost
		# the carve entirely. 4.0 rad/s is a 2.9 m circle, under a tile and a
		# half, and swings him 180 degrees in 0.79s of a 2.0s ride: rounded enough
		# to see the arc, sharp enough to put him on a body, and awkward enough to
		# be worth learning. Raise it toward 6 to make it forgiving, drop it
		# toward 3 to make it a commitment.
		"super": {
			"style": Style.DOWNHILL, "pellets": 1, "spread_deg": 360.0, "damage": 1893,
			"range": 5.5 * TILE, "speed": SPEED_FAST * 1.90, "radius": 0.0,
			"destroys_walls": false, "knockback": 11.0, "pierces": false,
			"aoe": 1.6 * TILE, "water_mult": 1.0,
			"duration": 2.0, "turn_rate": 4.0,
			"slow_seconds": 1.5, "slow_factor": 0.6,
		},
	}
