class_name HackySack
extends Area3D
## A kicked sack stays active long enough to reward bank shots and recovery.

var weapon: Dictionary
var damage := 0
var owner_fighter: Fighter
var direction := Vector3.FORWARD
var bounces_left := 3
var on_body_hit := Callable()
var on_pickup := Callable()
var last_hit_normal := Vector3.ZERO

const LIFETIME := 2.8
const PICKUP_DELAY := 0.35
const PICKUP_RADIUS := 0.9
## Fall back to homing even if the sack never travelled its full range — a shot
## into a nearby wall would otherwise rattle around and never come home.
const RETURN_AFTER := 1.2
var _age := 0.0
var _bounce_lock: Node3D
var _bounce_lock_until := 0.0
var _origin := Vector3.ZERO
var _returning := false

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = (1 << 0) | (1 << 2) | (1 << 5) # walls, fighters, boxes
	monitoring = true
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = weapon.radius
	col.shape = shape
	add_child(col)
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
	_origin = global_position

## Once the sack has done its outbound work it curves back to Anders instead of
## relying on the random turn in bounce_from, which made recovery pure luck.
func _begin_return() -> void:
	_returning = true
	# Fly home over the terrain: re-homing every frame would otherwise pin the
	# sack against whatever wall it last bounced off. It still hits fighters.
	collision_mask = 1 << 2

func _physics_process(delta: float) -> void:
	_age += delta
	if not _returning and (_age >= RETURN_AFTER or bounces_left <= 0 \
			or global_position.distance_to(_origin) >= float(weapon.range)):
		_begin_return()
	if _returning and is_instance_valid(owner_fighter):
		var home := owner_fighter.global_position + Vector3(0, 0.8, 0) - global_position
		if home.length() > 0.01:
			direction = home.normalized()
	var next_pos := global_position + direction * float(weapon.speed) * delta
	# Area3D's body_entered can miss a small, fast sack between physics ticks.
	# A ray over the full frame movement makes every bank shot deterministic.
	var query := PhysicsRayQueryParameters3D.create(global_position, next_pos, collision_mask)
	if is_instance_valid(owner_fighter):
		query.exclude = [owner_fighter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = next_pos
	else:
		global_position = hit.position
		last_hit_normal = hit.normal
		if on_body_hit.is_valid():
			on_body_hit.call(hit.collider, self)
	rotation += Vector3(9.0, 12.0, 5.0) * delta
	if _age >= PICKUP_DELAY and is_instance_valid(owner_fighter) \
			and global_position.distance_to(owner_fighter.global_position + Vector3(0, 0.8, 0)) <= PICKUP_RADIUS:
		if on_pickup.is_valid():
			on_pickup.call(self)
		queue_free()
	elif _age >= LIFETIME:
		queue_free()

func can_bounce_from(body: Node3D) -> bool:
	return body != _bounce_lock or _age >= _bounce_lock_until

func bounce_from(point: Vector3, surface_normal := Vector3.ZERO) -> void:
	_bounce_pulse()
	if _returning:
		return   # already homing; clipping a fighter must not knock it off course
	bounces_left -= 1
	if bounces_left < 0:
		queue_free()
		return
	var away := surface_normal if surface_normal.length() > 0.05 else global_position - point
	away.y = 0
	if away.length() < 0.05:
		away = -direction
	direction = reflected_direction(direction, away)
	global_position += direction * 0.24
	_bounce_lock = null
	_bounce_lock_until = _age + 0.10

static func reflected_direction(incoming: Vector3, surface_normal: Vector3) -> Vector3:
	var normal := Vector3(surface_normal.x, 0, surface_normal.z).normalized()
	if normal.length_squared() < 0.001:
		return -incoming.normalized()
	var reflected := incoming.bounce(normal)
	return (reflected + normal * 0.25).normalized()

func _bounce_pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.45, 0.7, 1.45), 0.06)
	tw.tween_property(self, "scale", Vector3.ONE, 0.10)
