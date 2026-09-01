class_name Kits
## Fighter kit data, ported from the SpriteKit game's FighterKit/Weapon.
## Distances are in meters; TILE converts from the 2D game's tile units.
##
## Every kit is statted against CHARACTER_BUILDING.md in the repo root: pick one
## tier from each of health / speed / reload / range, then DERIVE damage from the
## formula there rather than picking it by taste. The tier comment above each kit
## is the record of that choice — keep it in sync when you retune.

const TILE := 2.0

# Speed tiers (m/s). Normal is 3.5 tiles/second.
const SPEED_VERY_SLOW := 5.6
const SPEED_SLOW := 6.3
const SPEED_NORMAL := 7.0
const SPEED_FAST := 7.7
const SPEED_VERY_FAST := 8.4

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

# Weapons cap at 5.5 tiles and Supers at 6.5 — past that a fighter is shooting
# at something off the player's screen. See CHARACTER_BUILDING.md section 4.
const MAX_WEAPON_RANGE_TILES := 5.5
const MAX_SUPER_RANGE_TILES := 6.5

enum Style { PELLETS, LOB, MELEE, DASH, BOOMERANG, SHOCKWAVE, JUMP_SMASH, BUTTONS, DISCONNECT, HACKY_SACK, ORBIT_SACK }

static func all() -> Array:
	return [nova(), tony(), henry(), sanjit(), kovacs(), leon(), anders()]

static func named(kit_name: String) -> Dictionary:
	for k in all():
		if k.name.to_lower() == kit_name.to_lower():
			return k
	return nova()

## Health Normal · Speed Normal · Reload Normal · Range Medium 4.5
## The reference kit: Normal in all four tiers, so her only modifier is A=1.15
## for a shotgun that has to close distance to land the full burst. Every other
## fighter reads as a deviation from Nova.
## 1250 × 1.000(R) × 1.00(G) × 1.00(M) × 1.00(S) × 1.15(A) = 1437 → 5 × 290
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
			"style": Style.PELLETS, "pellets": 5, "spread_deg": 22.0, "damage": 290,
			"range": 4.5 * TILE, "speed": 25.0, "radius": 0.14,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 2.4x total, spread over 9 pellets that rarely all connect.
		"super": {
			"style": Style.PELLETS, "pellets": 9, "spread_deg": 34.0, "damage": 385,
			"range": 5.5 * TILE, "speed": 27.0, "radius": 0.26,
			"destroys_walls": true, "knockback": 12.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

## Health Low · Speed Slow · Reload Slow · Range Long 5.5
## Artillery: the longest weapon range in the game and an AOE that arcs over
## walls with no line-of-sight check, paid for with the squishiest slow body.
## 1250 × 1.222(R) × 0.85(G) × 1.06(M) × 1.06(S) × 0.85(A) = 1240
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
			"style": Style.LOB, "pellets": 1, "spread_deg": 0.0, "damage": 1240,
			"range": 5.5 * TILE, "speed": 19.0, "radius": 0.22,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.7 * TILE, "water_mult": 1.0,
		},
		# 1.8x for one reliable piercing hit.
		"super": {
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 2230,
			"range": 6.5 * TILE, "speed": 42.0, "radius": 0.32,
			"destroys_walls": true, "knockback": 10.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

## Health Low · Speed Very Fast · Reload Fast · Range Very Short 1.5
## Assassin: fastest fighter in the game and the quickest reload, so he picks
## every fight — but he has to be inside 3 metres and folds if he is caught out.
## 1250 × 0.778(R) × 1.25(G) × 0.88(M) × 1.06(S) × 1.00(A) = 1133 → 2 × 565
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
				  "attack_speed": 4.5},
		"max_health": HEALTH_LOW,
		"move_speed": SPEED_VERY_FAST,
		"reload": RELOAD_FAST,
		"weapon": {
			"style": Style.MELEE, "pellets": 2, "spread_deg": 70.0, "damage": 565,
			"range": 1.5 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 2.4x total split across the two passes -> 1.2x per pass.
		"super": {
			"style": Style.BOOMERANG, "pellets": 1, "spread_deg": 0.0, "damage": 1360,
			"range": 5.5 * TILE, "speed": 16.0, "radius": 0.45,
			"destroys_walls": false, "knockback": 4.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

## Health High · Speed Slow · Reload Slow · Range Very Short 1.9
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
			"range": 1.9 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 1.4x, not 1.8x: the dash is also mobility, knockback, and doubles its
		# damage across water. water_mult 2.0 puts it at 4540 on a crossing, so
		# a bigger base number here would one-shot most of the roster.
		"super": {
			"style": Style.DASH, "pellets": 1, "spread_deg": 0.0, "damage": 2270,
			"range": 4.5 * TILE, "speed": 34.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 9.0, "pierces": false,
			"aoe": 0.0, "water_mult": 2.0,
		},
	}

## Health Very High · Speed Very Slow · Reload Normal · Range Short 2.5
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
			"range": 2.5 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 4.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0, "delay": 0.23,
		},
		# 1.4x: the leap is a gap-closer and an escape on top of the damage.
		"super": {
			"style": Style.JUMP_SMASH, "pellets": 1, "spread_deg": 360.0, "damage": 1680,
			"range": 4.5 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 10.0, "pierces": true,
			"aoe": 2.15 * TILE, "water_mult": 1.0,
		},
	}

## Health Low · Speed Normal · Reload Fast · Range Long 5.0
## Controller: a fast, chippy stream of six buttons in a tight cone. Fragile,
## and each button is small, so he wins by attrition rather than by bursts.
## 1250 × 0.778(R) × 0.85(G) × 1.00(M) × 1.06(S) × 1.00(A) = 875 → 6 × 146
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
			# full 10 m range they land 0.55 m off centre and still connect with
			# a ~0.65 m hittable width. At 10 deg they missed past about 8 m.
			"style": Style.BUTTONS, "pellets": 6, "spread_deg": 7.0, "damage": 146,
			"range": 5.0 * TILE, "speed": 22.0, "radius": 0.20,
			"destroys_walls": false, "knockback": 1.5, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 1.4x: the damage is incidental, the silence is the payload. The blast
		# hard-stops everyone it catches for `disconnect_seconds`; the field it
		# leaves then holds `zone_seconds` as denied ground — anyone standing in
		# it cannot attack, and the silence lifts a beat after they step off.
		"super": {
			"style": Style.DISCONNECT, "pellets": 1, "spread_deg": 360.0, "damage": 1230,
			"range": 5.5 * TILE, "speed": 18.0, "radius": 0.52,
			"destroys_walls": false, "knockback": 5.0, "pierces": false,
			"aoe": 1.7 * TILE, "water_mult": 1.0, "disconnect_seconds": 2.4,
			"zone_seconds": 4.0,
		},
	}

## Health Normal · Speed Normal · Reload Slow · Range Long 5.5
## Skirmisher: kicks a slow sack out at range and gets it back for ammo or HP.
## A=1.00, not 0.85 — piercing and bouncing are worth nothing if the first hit
## misses, and at 16 m/s his sack is the slowest projectile in the game, so it
## is no easier to land than anyone else's. U is deliberately NOT applied even
## though the return is now reliable: he was the weakest kit by a wide margin
## (2.7% wins over 120 sim matches), so the recovery rides free until a sim
## says it needs paying for.
## 1250 × 1.222(R) × 0.85(G) × 1.00(M) × 1.00(S) × 1.00(A) × 1.00(U) = 1299
static func anders() -> Dictionary:
	return {
		"name": "Anders", "color": Color(0.2, 0.88, 0.78),
		"role": "Skirmisher",
		"desc": "Kicks a bouncing hacky sack, then recovers it for ammo or health.",
		"super_desc": "Around the World: a spinning sack knocks enemies out of his space.",
		"max_health": HEALTH_NORMAL,
		"move_speed": SPEED_NORMAL,
		"reload": RELOAD_SLOW,
		"weapon": {
			"style": Style.HACKY_SACK, "pellets": 1, "spread_deg": 0.0, "damage": 1300,
			"range": 5.5 * TILE, "speed": 16.0, "radius": 0.26,
			"destroys_walls": false, "knockback": 3.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0, "bounces": 3,
		},
		# Bodyguard ring. orbit_radius is how far out the sack circles; `range`
		# stays the reach that tells a bot when popping it is worth it. They were
		# the same field before, which put the ring 6 m out — a 2 m band that
		# could not touch anyone actually diving him.
		# 2.4x total (3120) spread over the passes a target eats before the
		# knockback throws them clear: ~2-3 typical, 5 hard-capped by hit_cooldown.
		"super": {
			"style": Style.ORBIT_SACK, "pellets": 1, "spread_deg": 360.0, "damage": 700,
			"range": 3.0 * TILE, "speed": 0.0, "radius": 0.5,
			"destroys_walls": false, "knockback": 8.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0, "duration": 3.0,
			"orbit_radius": 0.9 * TILE, "hit_cooldown": 0.55,
		},
	}
