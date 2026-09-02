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

enum Style { PELLETS, LOB, MELEE, DASH, BOOMERANG, SHOCKWAVE, JUMP_SMASH, BUTTONS, DISCONNECT, KEEP_IT_UP, POP_OFF }

static func all() -> Array:
	return [nova(), tony(), henry(), sanjit(), kovacs(), leon(), anders(), hammy()]

static func named(kit_name: String) -> Dictionary:
	for k in all():
		if k.name.to_lower() == kit_name.to_lower():
			return k
	return nova()

## Health Normal · Speed Normal · Reload Normal · Range Medium 4.3
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
			"range": 4.3 * TILE, "speed": SPEED_NORMAL * 3.05, "radius": 0.44,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 2.4x total, spread over 9 pellets that rarely all connect.
		"super": {
			"style": Style.PELLETS, "pellets": 9, "spread_deg": 34.0, "damage": 385,
			"range": 5.0 * TILE, "speed": SPEED_NORMAL * 3.30, "radius": 0.52,
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
			# 3.0x, not the 2.1x the dodge-window maths alone wanted. A lob
			# resolves where it LANDS, so its AOE only forgives a miss if the
			# shell arrives near the target — a longer hang amplifies any lead
			# error instead of being paid for by the blast radius. Slowing it to
			# 2.1x dropped his measured hit rate from 81% to 63% in NS3_SIM. At
			# 3.0x the shell hangs 0.73s and the target covers 4.1 m, which is
			# what it covered before the retune. See CHARACTER_BUILDING.md:
			# "An arcing attack has to be timed against how fast people move."
			"style": Style.LOB, "pellets": 1, "spread_deg": 0.0, "damage": 1240,
			"range": 5.5 * TILE, "speed": SPEED_SLOW * 3.00, "radius": 0.42,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.7 * TILE, "water_mult": 1.0,
		},
		# 1.8x for one reliable piercing hit.
		"super": {
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 2230,
			"range": 6.0 * TILE, "speed": SPEED_SLOW * 3.90, "radius": 0.56,
			"destroys_walls": true, "knockback": 10.0, "pierces": true,
			"aoe": 0.0, "water_mult": 1.0,
		},
	}

## Health Normal · Speed Very Fast · Reload Fast · Range Very Short 1.4
## Assassin: fastest fighter in the game and the quickest reload, so he picks
## every fight — but he still has to get inside 2.8 metres to throw a punch.
## A=1.15, measured: the one-two lands 59% per strike where Henry's single
## sweep lands 86%, because the second punch arrives 0.22s late through a 70
## degree arc rather than 110. He was priced as the most reliable melee in the
## game while being the least. Health moved Low -> Normal because his measured
## shortfall was attack opportunity (5.0 swings per life, the fewest of anyone)
## rather than damage — a bigger hit is worth nothing if he dies on the walk in.
## 1250 × 0.778(R) × 1.25(G) × 0.88(M) × 1.00(S) × 1.15(A) = 1230 → 2 × 615
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
		"reload": RELOAD_FAST,
		"weapon": {
			"style": Style.MELEE, "pellets": 2, "spread_deg": 70.0, "damage": 615,
			"range": 1.4 * TILE, "speed": 0.0, "radius": 0.0,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0,
		},
		# 2.4x total split across the two passes -> 1.2x per pass.
		"super": {
			"style": Style.BOOMERANG, "pellets": 1, "spread_deg": 0.0, "damage": 1480,
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
## 1250 × 0.778(R) × 0.85(G) × 1.00(M) × 1.06(S) × 1.40(A) = 1227 → 6 × 204
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
			"style": Style.BUTTONS, "pellets": 6, "spread_deg": 7.0, "damage": 204,
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
			"style": Style.DISCONNECT, "pellets": 1, "spread_deg": 360.0, "damage": 1710,
			"range": 4.8 * TILE, "speed": SPEED_NORMAL * 2.10, "radius": 0.66,
			"destroys_walls": false, "knockback": 5.0, "pierces": false,
			"aoe": 1.7 * TILE, "water_mult": 1.0, "disconnect_seconds": 2.4,
			"zone_seconds": 4.0,
		},
	}

## Health High · Speed Normal · Reload Fast · Range Short 2.8 · ONE ammo
## Skirmisher who plays like a close brawler, which is how he actually gets
## used: the rally pulls him toward wherever the sack is coming down, so he
## fights in the pocket rather than at range. Statted for that — shorter reach,
## a High healthbar to survive being there, and a much heavier landing.
##
## One ammo, not three. Only one sack exists at a time, so the other two pips
## could never be spent and ~45% of his kicks were being refused outright. The
## pip does not start refilling until the rally ends (Fighter.ammo_locked), so
## the reload is the price of LOSING the sack — keeping it alive is the reward.
##
## Calibrated against measured output, not the per-attack formula: one ammo, a
## reload lockout and up to three landings per kick leave "damage per attack"
## with no single meaning.
static func anders() -> Dictionary:
	return {
		"name": "Anders", "color": Color(0.2, 0.88, 0.78),
		"role": "Skirmisher",
		"desc": "Keeps a hacky sack alive — every touch kicks it to whoever is closest, and catching it yourself continues the rally for free.",
		"super_desc": "Pop Off: flicks the sack up and leaps clear, then spikes it back the way he came.",
		"max_health": HEALTH_HIGH,
		"move_speed": SPEED_NORMAL,
		"reload": RELOAD_FAST,
		"ammo": 1,
		"weapon": {
			# speed is the ARC's travel rate, not a bullet's. It once had to run
			# at 12 m/s because a 7 m/s target walked out of the landing spot
			# before the sack arrived — at 8.0 it hit almost nothing. Fighters
			# now move at 4.0 m/s, so the constraint is looser and the sack can
			# float again: a 5.6 m kick hangs 0.58s while the target covers
			# 2.3 m against a 1.9 m landing radius. aoe is how close a landing
			# has to be to connect — the same forgiveness a lob gets.
			"style": Style.KEEP_IT_UP, "pellets": 1, "spread_deg": 0.0, "damage": 1100,
			"range": 2.8 * TILE, "speed": SPEED_NORMAL * 1.70, "radius": 0.44,
			"destroys_walls": false, "knockback": 3.0, "pierces": false,
			"aoe": 0.95 * TILE, "water_mult": 1.0,
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
## Sniper: one small, fast basketball at the screen-range cap. Consecutive
## fighter hits light him On Fire; that strong basic-attack utility is U=0.85.
## Formula gives 1422; 1250 is the measured trim for his unusually long uptime.
static func hammy() -> Dictionary:
	return {
		"name": "Hammy", "color": Color(1.0, 0.36, 0.08),
		"role": "Sniper",
		"model": "res://assets/hammy.glb",
		# baseball_pitching is the windup-and-release his three-pointer needs;
		# at 2.5x the ball leaves his hand about 0.5s in. He has no melee clip,
		# so the Super reuses the same shot.
		"clips": {"idle": "Idle", "run": "Running", "attack": "baseball_pitching",
				  "attack_speed": 2.5},
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
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 1250,
			"range": 5.5 * TILE, "speed": SPEED_NORMAL * 3.60, "radius": 0.62,
			"destroys_walls": false, "knockback": 0.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0, "heat_trait": true,
			"projectile_color": Color(1.0, 0.34, 0.04),
		},
		# The direct hit is deliberately modest: banking is the point. Each wall
		# adds 25%, so three clean banks ramp 1600 -> 3125 before the fire damage.
		"super": {
			"style": Style.PELLETS, "pellets": 1, "spread_deg": 0.0, "damage": 1600,
			"range": 6.0 * TILE, "speed": SPEED_NORMAL * 3.30, "radius": 0.70,
			"destroys_walls": false, "knockback": 5.0, "pierces": false,
			"aoe": 0.0, "water_mult": 1.0, "bounces": 3,
			"bounce_damage_mult": 1.25, "bounce_speed_mult": 1.08,
			"burn_duration": 3.0, "burn_tick_damage": 100,
			"projectile_color": Color(1.0, 0.20, 0.01),
		},
	}

## Health Very Low · Speed Normal · Reload Slow · Range Long 5.5
## Sniper: one small, fast basketball at the screen-range cap. Consecutive
## fighter hits light him On Fire; that strong basic-attack utility is U=0.85.
## Formula gives 1422; 1250 is the measured trim for his unusually long uptime.
