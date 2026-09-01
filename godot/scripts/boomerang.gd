class_name Boomerang
extends Area3D
## Sanjit's Super: a spinning staff that flies out over walls, then arcs back
## to its thrower, damaging on both the outbound and return passes. The main
## scene resolves hits via body_entered; already_hit clears at the turnaround
## so the return pass can hit the same targets again.

var weapon: Dictionary
var damage := 0
var owner_fighter: Fighter
var direction := Vector3.FORWARD
var origin := Vector3.ZERO
var returning := false
var already_hit: Array = []
var _spin: Node3D

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = (1 << 2) | (1 << 5)   # fighters | boxes — flies over walls
	monitoring = true

	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = weapon.radius
	col.shape = s
	add_child(col)

	_spin = Node3D.new()
	add_child(_spin)
	var staff := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.07
	rod.bottom_radius = 0.07
	rod.height = 1.9
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.32, 0.14)
	rod.material = wood
	staff.mesh = rod
	staff.rotation_degrees.x = 90.0   # lie flat, spinning like a rotor
	_spin.add_child(staff)
	for end in [-0.85, 0.85]:
		var tip := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.14
		ball.height = 0.28
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.75, 0.25)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.6, 0.15) * 0.8
		ball.material = glow
		tip.mesh = ball
		tip.position = Vector3(0, 0, end)
		_spin.add_child(tip)

## The staff returns to the thrower's hand however the flight ends —
## caught, owner died, or match cleanup.
func _exit_tree() -> void:
	if owner_fighter != null and is_instance_valid(owner_fighter):
		owner_fighter.set_held_item_visible(true)

## Direction of travel right now — used for hit knockback.
func travel_dir() -> Vector3:
	if not returning:
		return direction
	if owner_fighter and is_instance_valid(owner_fighter):
		return (owner_fighter.global_position + Vector3(0, 1.2, 0) - global_position).normalized()
	return -direction

func _physics_process(delta: float) -> void:
	_spin.rotate_y(14.0 * delta)
	if not returning:
		global_position += direction * weapon.speed * delta
		if global_position.distance_to(origin) >= weapon.range:
			returning = true
			already_hit.clear()
	else:
		if owner_fighter == null or not is_instance_valid(owner_fighter) or owner_fighter.is_dead():
			queue_free()
			return
		var home := owner_fighter.global_position + Vector3(0, 1.2, 0)
		if home.distance_to(global_position) < 0.7:
			queue_free()
			return
		global_position += travel_dir() * weapon.speed * 1.15 * delta
