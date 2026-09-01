class_name Projectile
extends Area3D
## A pellet, shell, or controller button in flight.

var weapon: Dictionary
var damage := 0
var owner_fighter: Fighter
var direction := Vector3.FORWARD
var origin := Vector3.ZERO
var already_hit: Array = []
var button_text := ""
var button_color := Color.WHITE
var _flight_time := 0.0

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
	mat.albedo_color = button_color if button_text != "" else \
			(Color(1.0, 0.45, 0.15) if weapon.destroys_walls else Color(1.0, 0.85, 0.3))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.6
	mesh.material = mat
	m.mesh = mesh
	add_child(m)
	if button_text != "":
		var label := Label3D.new()
		label.text = button_text
		label.font_size = 56
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.009
		label.position.y = weapon.radius + 0.06
		add_child(label)

func _physics_process(delta: float) -> void:
	_flight_time += delta
	var traveled: float = _flight_time * float(weapon.speed)
	global_position = origin + direction * traveled
	if traveled > weapon.range:
		queue_free()
