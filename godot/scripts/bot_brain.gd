class_name BotBrain
extends RefCounted
## Priority-based bot decisions, ported from the SpriteKit BotBrain:
## escape gas > flee > engage > loot > wander, with unstick detours.

var fighter: Fighter
var _wander_target := Vector3.ZERO
var _repick_at := 0.0
var _next_fire_at := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_check_at := 0.0
var _detour := Vector3.ZERO
var _detour_until := 0.0

var _aim_error_deg := randf_range(3.0, 9.0)
var _fire_interval := randf_range(1.0, 1.6)
var _engage_range := Kits.TILE * randf_range(5.5, 7.0)

func _init(f: Fighter) -> void:
	fighter = f

## Returns {move: Vector3, fire_dir: Vector3 or null, fire_dist: float, use_super: bool}
func decide(now: float, game) -> Dictionary:
	var d := {"move": Vector3.ZERO, "fire_dir": null, "fire_dist": 0.0, "use_super": false}
	var enemy: Fighter = game.nearest_visible_enemy(fighter, _engage_range)

	if not game.gas_contains(fighter.global_position):
		d.move = _dir_to(game.gas_safe_center())
	elif enemy and fighter.health < fighter.max_health * 0.3:
		d.move = (_dir_from(enemy.global_position) + _dir_to(game.gas_safe_center()) * 0.5).normalized()
	elif enemy:
		var dist := fighter.global_position.distance_to(enemy.global_position)
		var ideal: float = max(Kits.TILE * 0.9, fighter.kit.weapon.range * 0.7)
		var toward := _dir_to(enemy.global_position)
		if dist > ideal * 1.2:
			d.move = toward
		elif dist < ideal * 0.7:
			d.move = -toward
		else:
			d.move = Vector3(-toward.z, 0, toward.x) * 0.6
	else:
		var loot = game.nearest_loot(fighter.global_position)
		if loot != null:
			d.move = _dir_to(loot)
		else:
			if _wander_target == Vector3.ZERO or now >= _repick_at \
					or fighter.global_position.distance_to(_wander_target) < Kits.TILE:
				_wander_target = game.random_wander_point(fighter.global_position)
				_repick_at = now + randf_range(2.5, 4.5)
			d.move = _dir_to(_wander_target)

	if enemy and now >= _next_fire_at:
		var dist := fighter.global_position.distance_to(enemy.global_position)
		var use_super := fighter.is_super_ready()
		var weapon: Dictionary = fighter.kit["super"] if use_super else fighter.kit.weapon
		if dist < weapon.range + Kits.TILE * 0.5:
			_next_fire_at = now + _fire_interval
			var base := _dir_to(enemy.global_position)
			var err := deg_to_rad(randf_range(-_aim_error_deg, _aim_error_deg))
			d.fire_dir = base.rotated(Vector3.UP, err)
			d.fire_dist = dist
			d.use_super = use_super

	_unstick(now, d)
	return d

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
			var side := 1.0 if randf() > 0.5 else -1.0
			_detour = Vector3(-d.move.z * side, 0, d.move.x * side).normalized()
			_detour_until = now + 0.5
		_stuck_pos = fighter.global_position
		_stuck_check_at = now + 0.6

func _dir_to(p: Vector3) -> Vector3:
	var v := p - fighter.global_position
	v.y = 0
	return v.normalized() if v.length() > 0.001 else Vector3.ZERO

func _dir_from(p: Vector3) -> Vector3:
	return -_dir_to(p)
