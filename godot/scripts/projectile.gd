class_name Projectile
extends Area3D
## A pellet/shell in flight. Straight-line travel at fixed height; the main
## scene resolves what it hits via the body_entered signal.

var weapon: Dictionary
var damage := 0
var owner_fighter: Fighter
var direction := Vector3.FORWARD
var origin := Vector3.ZERO
var already_hit: Array = []

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = (1 << 0) | (1 << 2) | (1 << 5)  # walls | fighters | boxes
	monitoring = true

	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = weapon.radius
	col.shape = s
	add_child(col)

	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.15) if weapon.destroys_walls else Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.6
	mesh.material = mat
	m.mesh = mesh
	add_child(m)

func _physics_process(delta: float) -> void:
	global_position += direction * weapon.speed * delta
	if global_position.distance_to(origin) > weapon.range:
		queue_free()
