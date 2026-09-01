class_name BotBrain
extends RefCounted
## Priority-based bot decisions, ported from the SpriteKit BotBrain:
## escape gas > flee > engage > loot > wander, with unstick detours.
## Movement is re-decided on a short timer (not every physics frame) and the
## output vector is smoothed, so boundary conditions (enemy at the edge of
## range, the gas edge, canceling flee vectors) can't flip velocity per frame.

var fighter: Fighter
var _wander_target := Vector3.ZERO
var _repick_at := 0.0
var _next_fire_at := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_check_at := 0.0
var _detour := Vector3.ZERO
var _detour_until := 0.0
var _detour_side := 0.0
var _stuck_streak := 0
var _last_stuck_at := 0.0

var _target: Fighter = null
var _target_seen_at := 0.0
var _think_at := 0.0
var _move_choice := Vector3.ZERO
var _fleeing_gas := false
var _smoothed := Vector3.ZERO
var _last_now := -1.0

var _aim_error_deg := randf_range(3.0, 9.0)
var _fire_interval := randf_range(1.0, 1.6)
var _engage_range := Kits.TILE * randf_range(5.5, 7.0)
var _think_interval := randf_range(0.15, 0.25)

## How far ahead of a moving target a bot aims, as a fraction of the target's
## travel during the shot's flight. 1.0 is a perfect intercept; 0.0 is aiming
## where the target already stands.
##
## Without any lead, projectile kits simply cannot hit a moving fighter: a
## 25 m/s pellet crossing 7 m is airborne 0.28s, in which a 7 m/s target moves
## ~2 m — over three times its own hitbox. Instant-hit kits (melee, shockwave)
## never miss, so a no-lead sim measures "is this weapon hitscan" rather than
## whether the kit is balanced. Sim bots therefore aim well; match bots lead
## badly on purpose, so shots read as aimed without being hard to walk out of.
const LEAD_SIM := 0.85
const LEAD_MATCH_MIN := 0.15
const LEAD_MATCH_MAX := 0.45
const LEAP_FLIGHT := 0.48   # Fighter.begin_leap duration; JUMP_SMASH has no speed

var _lead_skill := randf_range(LEAD_MATCH_MIN, LEAD_MATCH_MAX)

## Aim scatter has to be tightened for the sim for the same reason lead does.
## A fighter is only ~0.65 m of hittable width, so at a 7 m engagement the match
## spread of 3-9 degrees is 0.37-1.10 m of error: a bot that rolls above ~5 deg
## can never land a precision weapon for its entire life. Wide melee arcs, big
## AOEs and bouncing projectiles don't care, so leaving match scatter in the sim
## ranks kits by how forgiving they are rather than by how strong they are.
const AIM_ERROR_SIM_MIN := 0.5
const AIM_ERROR_SIM_MAX := 2.0

var _aim_error_sim := randf_range(AIM_ERROR_SIM_MIN, AIM_ERROR_SIM_MAX)

func _init(f: Fighter) -> void:
	fighter = f

## Returns {move: Vector3, fire_dir: Vector3 or null, fire_dist: float, use_super: bool}
func decide(now: float, game) -> Dictionary:
	var d := {"move": Vector3.ZERO, "fire_dir": null, "fire_dist": 0.0, "use_super": false}
	_update_target(now, game)

	if now >= _think_at:
		_think_at = now + _think_interval
		_move_choice = _pick_move(now, game)
	d.move = _move_choice

	if _target and now >= _next_fire_at:
		var use_super := fighter.is_super_ready()
		var weapon: Dictionary = fighter.kit["super"] if use_super else fighter.kit.weapon
		var dist := fighter.global_position.distance_to(_target.global_position)
		var thrown: bool = int(weapon.style) == Kits.Style.LOB \
				or int(weapon.style) == Kits.Style.DISCONNECT
		# Strictly inside range: a projectile deletes itself at weapon.range, so
		# the old "+ half a tile" tolerance meant the opening shot of most
		# engagements expired in mid-air before it could reach anyone.
		if dist <= float(weapon.range) \
				and game.can_see(fighter, _target, thrown):
			_next_fire_at = now + _fire_interval
			var aim := _aim_point(_target, weapon, dist, game)
			var base := _dir_to(aim)
			if base == Vector3.ZERO:   # aim point landed on top of us
				base = _dir_to(_target.global_position)
			# Pop Off is an escape: the spike comes down on the ground he jumped
			# AWAY from, so its aim is the leap, not the target. A bot pointing
			# it at an enemy leaps onto them and spikes empty floor behind it.
			if int(weapon.style) == Kits.Style.POP_OFF:
				base = -base
			if base != Vector3.ZERO:
				var scatter: float = _aim_error_sim if game.sim_active else _aim_error_deg
				var err := deg_to_rad(randf_range(-scatter, scatter))
				d.fire_dir = base.rotated(Vector3.UP, err)
				# Thrown styles land where fire_dist says, so it has to be the
				# distance to the lead point, not to the target.
				d.fire_dist = fighter.global_position.distance_to(aim)
				d.use_super = use_super

	_unstick(now, d)

	var dt := clampf(now - _last_now, 0.0, 0.1) if _last_now >= 0.0 else 0.016
	_last_now = now
	_smoothed = _smoothed.lerp(d.move as Vector3, 1.0 - exp(-8.0 * dt))
	d.move = _smoothed if _smoothed.length() > 0.05 else Vector3.ZERO
	return d

## Keep the current target until it dies, gets far out of range, or stays
## unseen too long — re-querying nearest_visible_enemy every frame made bots
## flip-flop when an enemy sat right on the range/visibility boundary.
func _update_target(now: float, game) -> void:
	var lob: bool = int(fighter.kit.weapon.style) == Kits.Style.LOB
	if _target != null:
		if not is_instance_valid(_target) or _target.is_dead() \
				or fighter.global_position.distance_to(_target.global_position) > _engage_range * 1.4:
			_target = null
		elif game.can_see(fighter, _target, lob):
			_target_seen_at = now
		elif now - _target_seen_at > 1.5:
			_target = null
	if _target == null:
		_target = game.nearest_visible_enemy(fighter, _engage_range, lob)
		if _target:
			_target_seen_at = now

func _pick_move(now: float, game) -> Vector3:
	var pos := fighter.global_position
	if not game.gas_contains(pos):
		_fleeing_gas = true
	elif _fleeing_gas and game.gas_depth(pos) > Kits.TILE * 1.5:
		_fleeing_gas = false
	if _fleeing_gas:
		return _dir_to(game.gas_safe_center())

	var enemy := _target
	if enemy and fighter.health < fighter.max_health * 0.3:
		var flee := _dir_from(enemy.global_position) + _dir_to(game.gas_safe_center()) * 0.5
		if flee.length() < 0.3:  # enemy is between us and center; strafe out instead
			var away := _dir_from(enemy.global_position)
			return Vector3(-away.z, 0, away.x)
		return flee.normalized()
	if enemy:
		var dist := pos.distance_to(enemy.global_position)
		# Spread weapons have to hug: at the default 0.7 standoff a shotgun's
		# pellets have already fanned wider than a fighter, so only the centre
		# one lands. Those kits set their own ideal_range_mult (Nova: 0.30).
		var mult: float = fighter.kit.get("ideal_range_mult", 0.7)
		var ideal: float = max(Kits.TILE * 0.9, fighter.kit.weapon.range * mult)
		var toward := _dir_to(enemy.global_position)
		if dist > ideal * 1.2:
			return toward
		elif dist < ideal * 0.7:
			return -toward
		return Vector3(-toward.z, 0, toward.x) * 0.6

	var loot = game.nearest_loot(pos)
	if loot != null:
		return _dir_to(loot)
	if _wander_target == Vector3.ZERO or now >= _repick_at \
			or pos.distance_to(_wander_target) < Kits.TILE:
		_wander_target = game.random_wander_point(pos)
		_repick_at = now + randf_range(2.5, 4.5)
	return _dir_to(_wander_target)

## Detours keep the same side across consecutive stalls (wall-follow) instead
## of re-rolling a random side each time, which made blocked bots ping-pong.
## The side flips only after two failed tries; past four we back out diagonally.
func _unstick(now: float, d: Dictionary) -> void:
	if _detour != Vector3.ZERO and now < _detour_until:
		d.move = _detour
		return
	_detour = Vector3.ZERO
	if d.move.length() < 0.1:
		_stuck_check_at = now + 0.6
		_stuck_pos = fighter.global_position
		return
	if now >= _stuck_check_at:
		if _stuck_check_at > 0.0 and fighter.global_position.distance_to(_stuck_pos) < 0.2:
			if _detour_side == 0.0 or now - _last_stuck_at > 3.0:
				_stuck_streak = 0
				_detour_side = 1.0 if randf() > 0.5 else -1.0
			_stuck_streak += 1
			_last_stuck_at = now
			if _stuck_streak == 3:
				_detour_side = -_detour_side
			var dir := (d.move as Vector3).normalized()
			var side := Vector3(-dir.z, 0, dir.x) * _detour_side
			_detour = side if _stuck_streak <= 4 else (side - dir).normalized()
			_detour_until = now + minf(0.5 + 0.2 * _stuck_streak, 1.5)
		_stuck_pos = fighter.global_position
		_stuck_check_at = now + 0.6

## Where to shoot so the shot and the target arrive in the same place. Melee and
## shockwave resolve instantly, so they always aim straight at the target.
func _aim_point(target: Fighter, weapon: Dictionary, dist: float, game) -> Vector3:
	var speed: float = weapon.speed
	var flight := 0.0
	if int(weapon.style) == Kits.Style.JUMP_SMASH:
		flight = LEAP_FLIGHT      # a leap, not a projectile: fixed airtime
	elif speed > 0.1:
		flight = dist / speed     # Lob matches this: _duration = distance / speed
	if flight <= 0.0:
		return target.global_position
	var lead: float = LEAD_SIM if game.sim_active else _lead_skill
	var travel := Vector3(target.velocity.x, 0.0, target.velocity.z) * lead
	var aim := target.global_position + travel * flight
	# One refinement pass: leading moves the aim point, which changes how long
	# the shot is airborne, which moves the aim point again.
	if speed > 0.1:
		flight = fighter.global_position.distance_to(aim) / speed
		aim = target.global_position + travel * flight
	return aim

func _dir_to(p: Vector3) -> Vector3:
	var v := p - fighter.global_position
	v.y = 0
	return v.normalized() if v.length() > 0.001 else Vector3.ZERO

func _dir_from(p: Vector3) -> Vector3:
	return -_dir_to(p)
