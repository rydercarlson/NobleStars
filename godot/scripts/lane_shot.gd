class_name LaneShot
extends Projectile
## One of Leon's four button shots (A/B/X/Y). Flies down a parallel lane with
## its own side-to-side drift; hit resolution is the normal Projectile path.

var label := "A"
var tint := Color(0.35, 0.85, 0.3)
var drift_amp := 0.55
var drift_hz := 2.4
var drift_phase := 0.0
var _travel := 0.0
var _lane_origin := Vector3.ZERO
var _perp := Vector3.ZERO

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = (1 << 0) | (1 << 2) | (1 << 5)  # walls | fighters | boxes
	monitoring = true
	_lane_origin = global_position
	_perp = Vector3(-direction.z, 0, direction.x)

	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = weapon.radius
	col.shape = s
	add_child(col)

	# A rounded controller button: colored face, darker rim, letter on top.
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint * 0.7
	mesh.material = mat
	m.mesh = mesh
	add_child(m)
	var text := Label3D.new()
	text.text = label
	text.font_size = 96
	text.pixel_size = 0.004
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.modulate = Color(1, 1, 1, 0.95)
	text.outline_modulate = Color(tint.darkened(0.6), 1.0)
	text.outline_size = 24
	text.position.y = weapon.radius + 0.12
	add_child(text)

func _physics_process(delta: float) -> void:
	_travel += weapon.speed * delta
	var sway: float = sin(drift_phase + _travel / weapon.speed * TAU * drift_hz) * drift_amp
	global_position = _lane_origin + direction * _travel + _perp * sway
	if _travel > weapon.range:
		queue_free()
