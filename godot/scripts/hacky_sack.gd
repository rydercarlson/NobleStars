class_name HackySack
extends Area3D
## Anders' rally sack — "Keep It Up".
##
## The sack travels in ARCS, not lines. Each kick is a hop: it lifts, floats
## across, and comes down on a landing spot, and only the landing does damage.
## That is the whole feel of the kit — a flat fast projectile reads as a bullet
## no matter what it is drawn as, and gives the target nothing to react to.
##
## One sack exists at a time and it rallies: Anders kicks it out onto an enemy,
## it hops back to him, he kicks it out again. Every landing spends one of three
## touches, and each time Anders gets back under it the rally steps up and the
## sack lands harder. The ring on the floor shows where the current hop comes
## down, so getting under it is a fair read rather than a guess.

var weapon: Dictionary
var base_damage := 0
var owner_fighter: Fighter
var game: Node                     # main scene, for the fighter list

var rally := 1
var on_enemy_hit := Callable()     # (Fighter target, HackySack sack)
var on_rally := Callable()         # (HackySack sack) — Anders kicked it again
var on_land := Callable()          # (Fighter or null, HackySack) — diagnostics

const MAX_RALLY := 3
## Offensive landings only — on an enemy or on bare floor. Being caught by
## Anders is free; the rally counter bounds that instead.
const MAX_TOUCHES := 3
const LIFETIME := 6.0
## Hop length as a fraction of weapon.range, per rally. A sack loses height.
const LEG_FRACTION := [1.0, 0.6, 0.35]
const REACH := 7.5                 # nobody this close to kick to -> rally ends
## How close a landing has to be to connect. Comes from the kit so the aim
## preview ring and the real landing ring are the same circle.
var _land_radius := 1.0
const CATCH_BONUS := 0.3           # Anders is a bigger target: he wants it
const DAMAGE_RAMP := 0.25          # +25% per rally step
const MIN_HOP := 0.45              # seconds; even a short hop keeps hang time

var _age := 0.0
var _touches_left := MAX_TOUCHES
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _dur := 0.6
var _height := 2.0
## Who this hop was aimed at, so the next hop never picks them again. Landing on
## someone leaves the sack inside them, which made "nearest fighter" choose that
## same body and fly straight back through it.
var _last_target: Fighter = null
var _label: Label3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D

func rally_damage() -> int:
	return int(base_damage * (1.0 + DAMAGE_RAMP * float(rally - 1)))

## Called by the main scene right after spawning, with the player's aim point.
func launch_at(point: Vector3) -> void:
	_begin_hop(point, null)

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 0          # landings resolve by radius, not by overlap
	monitoring = false
	_land_radius = maxf(float(weapon.get("aoe", 1.0)), 0.6)

	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.88, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.35, 0.25)
	mesh.material = mat
	visual.mesh = mesh
	add_child(visual)

	_build_marker()

	_label = Label3D.new()
	_label.font_size = 64
	_label.outline_size = 10
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.008
	_label.position.y = weapon.radius + 0.35
	add_child(_label)
	_refresh_rally_visuals()

## Flat ring on the floor at the landing spot. top_level keeps it out of the
## sack's transform so it stays on the ground while the sack arcs above it.
func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.top_level = true
	var ring := TorusMesh.new()
	ring.inner_radius = _land_radius * 0.62
	ring.outer_radius = _land_radius * 0.86
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = Color(1.0, 0.9, 0.4, 0.6)
	ring.material = _marker_mat
	_marker.mesh = ring
	add_child(_marker)

func _refresh_rally_visuals() -> void:
	var tint: Color = [Color(1.0, 0.97, 0.75), Color(1.0, 0.78, 0.3),
			Color(1.0, 0.45, 0.2)][clampi(rally - 1, 0, 2)]
	_label.text = str(rally)
	_label.modulate = tint
	_marker_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.6)

## Start an arc to `point`. `at` is the fighter being aimed at, if any, so the
## next hop can refuse to pick them again.
func _begin_hop(point: Vector3, at: Fighter) -> void:
	_from = global_position
	var aim := point
	if at != null and is_instance_valid(at):
		# Lead a rally hop. The sack floats for the better part of a second, so
		# aiming at where someone stands lands behind them every time.
		var rough := _from.distance_to(point) / maxf(1.0, float(weapon.speed))
		aim = point + Vector3(at.velocity.x, 0.0, at.velocity.z) * rough * 0.8
	_to = _clamp_to_open_ground(aim)
	_last_target = at
	_t = 0.0
	var dist := _from.distance_to(_to)
	# Hop time comes from distance, so a long kick genuinely hangs longer.
	_dur = maxf(MIN_HOP, dist / maxf(1.0, float(weapon.speed)))
	_height = clampf(1.3 + dist * 0.16, 1.5, 4.2)
	_marker.global_position = Vector3(_to.x, 0.04, _to.z)

## Never land inside geometry: pull the landing back to the last open spot.
func _clamp_to_open_ground(point: Vector3) -> Vector3:
	var a := Vector3(global_position.x, 0.5, global_position.z)
	var b := Vector3(point.x, 0.5, point.z)
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)   # walls only
	if is_instance_valid(owner_fighter):
		q.exclude = [owner_fighter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return b
	var back: Vector3 = (a - b).normalized() * 0.7
	return (hit.position as Vector3) + back

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME or not is_instance_valid(owner_fighter) or owner_fighter.is_dead():
		queue_free()
		return
	_t += delta
	var p: float = clampf(_t / _dur, 0.0, 1.0)
	var flat := _from.lerp(_to, p)
	global_position = Vector3(flat.x, flat.y + sin(PI * p) * _height, flat.z)
	rotate_y(6.0 * delta)
	if p >= 1.0:
		_land()

func _land() -> void:
	# Anders gets first refusal, and a wider radius: getting back under the sack
	# is the point of the mechanic, not a lucky overlap.
	if is_instance_valid(owner_fighter) and not owner_fighter.is_dead() \
			and _ground_gap(owner_fighter) <= _land_radius + CATCH_BONUS:
		if on_land.is_valid():
			on_land.call(owner_fighter, self)
		_recovered()
		return
	var struck: Fighter = null
	for f in game.fighters:
		if not is_instance_valid(f) or f.is_dead() or f == owner_fighter:
			continue
		if _ground_gap(f) <= _land_radius:
			struck = f
			break
	if on_land.is_valid():
		on_land.call(struck, self)
	if struck != null and on_enemy_hit.is_valid():
		on_enemy_hit.call(struck, self)
	_spend_touch(struck)

## Flat direction of the hop that just landed, for knockback.
func travel_dir() -> Vector3:
	var d := _to - _from
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD

func _ground_gap(f: Fighter) -> float:
	return Vector2(global_position.x - f.global_position.x,
			global_position.z - f.global_position.z).length()

## One landing resolved. Kick it on if any touches remain.
func _spend_touch(struck: Fighter) -> void:
	_touches_left -= 1
	if _touches_left <= 0:
		queue_free()
		return
	# After landing on an enemy the sack goes back to Anders — that is the rally,
	# out and back, and it is why it must never re-pick whoever it just hit.
	if struck != null and is_instance_valid(owner_fighter) and not owner_fighter.is_dead() \
			and _ground_gap(owner_fighter) <= REACH:
		_begin_hop(owner_fighter.global_position, owner_fighter)
		return
	var next := _nearest_fighter(struck)
	if next == null:
		queue_free()            # nobody in reach to keep it up; the rally dies
		return
	_begin_hop(next.global_position, next)

func _nearest_fighter(skip: Fighter) -> Fighter:
	var best := REACH
	var found: Fighter = null
	for f in game.fighters:
		if not is_instance_valid(f) or f.is_dead() or f == skip or f == _last_target:
			continue
		var d := _ground_gap(f)
		if d < best:
			best = d
			found = f
	return found

func _recovered() -> void:
	# Catching it does NOT spend a touch. Touches are the sack's OFFENSIVE
	# budget; the hop home deals no damage, and charging it one meant a third of
	# every sack was spent flying back to Anders. MAX_RALLY still bounds it.
	if rally >= MAX_RALLY:
		queue_free()
		return
	rally += 1
	_refresh_rally_visuals()
	_bounce_pulse()
	if on_rally.is_valid():
		on_rally.call(self)
	# Kicked straight back out at the nearest enemy, so a rally reads as an
	# exchange between the two of them. Falls back to his facing if nobody is
	# in reach.
	global_position = owner_fighter.global_position + Vector3(0, 1.0, 0)
	var enemy := _nearest_enemy()
	if enemy != null:
		_begin_hop(enemy.global_position, enemy)
	else:
		var leg: float = float(weapon.range) \
				* LEG_FRACTION[clampi(rally - 1, 0, LEG_FRACTION.size() - 1)]
		_begin_hop(owner_fighter.global_position + owner_fighter.facing * leg, null)

func _nearest_enemy() -> Fighter:
	var best := REACH
	var found: Fighter = null
	for f in game.fighters:
		if not is_instance_valid(f) or f.is_dead() or f == owner_fighter:
			continue
		var d := _ground_gap(f)
		if d < best:
			best = d
			found = f
	return found

func _bounce_pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.4, 0.72, 1.4), 0.06)
	tw.tween_property(self, "scale", Vector3.ONE, 0.10)
