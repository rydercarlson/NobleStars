class_name Kits
## Fighter kit data, ported from the SpriteKit game's FighterKit/Weapon.
## Distances are in meters; TILE converts from the 2D game's tile units.

const TILE := 2.0

const MAX_AMMO := 3.0
const AMMO_RECHARGE_SECONDS := 1.8
const SUPER_CHARGE_DAMAGE := 2500.0
const REGEN_DELAY := 3.0
const REGEN_RATE_PER_SECOND := 0.14
const BASE_MAX_HEALTH := 3600
const HEALTH_PER_CUBE := 400
const DAMAGE_BONUS_PER_CUBE := 0.10
const MOVE_SPEED := 7.0   # ~250 pt/s in the 2D game

enum Style { PELLETS, LOB, MELEE, DASH }

static func all() -> Array:
	return [nova(), tony(), henry()]

static func named(kit_name: String) -> Dictionary:
	for k in all():
		if k.name.to_lower() == kit_name.to_lower():
			return k
	return nova()

static func nova() -> Dictionary:
	return {
		"name": "Nova", "color": Color(0.25, 0.75, 0.95),
		"weapon": {
			"style": Style.PELLETS, "pellets": 5, "spread_deg": 22.0, "damage": 300,
			"range": 5.0 * TILE, "speed": 25.0, "radius": 0.14,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		"super": {
			"style": Style.PELLETS, "pellets": 9, "spread_deg": 34.0, "damage": 450,
			"range": 7.0 * TILE, "speed": 27.0, "radius": 0.26,
			"destroys_walls": true, "knockback": 12.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

static func tony() -> Dictionary:
	return {
		"name": "Tony", "color": Color(0.98, 0.85, 0.25),
		"model": "res://assets/tony.glb",
		"clips": {"idle": "Idle", "run": "Running", "attack": "Thrust_Slash",
				  "attack_speed": 3.0},
		"weapon": {
			"style": Style.LOB, "pellets": 1, "spread_deg": 0.0, "damage": 900,
			"range": 6.5 * TILE, "speed": 19.0, "radius": 0.22,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.9 * TILE, "water_mult": 1.0,
		},
		"super": {
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 1300,
			"range": 9.0 * TILE, "speed": 42.0, "radius": 0.32,
			"destroys_walls": true, "knockback": 10.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

static func henry() -> Dictionary:
	return {
		"name": "Henry", "color": Color(0.45, 0.55, 0.95),
		"model": "res://assets/henry.glb",
		"clips": {"idle": "Idle", "run": "Running", "attack": "Attack_Sweep",
				  "attack_speed": 1.0},
		"weapon": {
			"style": Style.MELEE, "pellets": 1, "spread_deg": 110.0, "damage": 750,
			"range": 1.9 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		"super": {
			"style": Style.DASH, "pellets": 1, "spread_deg": 0.0, "damage": 1000,
			"range": 4.5 * TILE, "speed": 34.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 9.0, "pierces": false,
			"aoe": 0.0, "water_mult": 2.0,
		},
	}
