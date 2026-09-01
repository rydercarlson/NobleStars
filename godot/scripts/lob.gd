class_name Lob
extends Node3D
## An arcing projectile that travels over walls to a target point, then asks
## the main scene to resolve its landing effect.

var weapon: Dictionary
var damage := 0
var owner_fighter: Fighter
var start_pos := Vector3.ZERO
var target_pos := Vector3.ZERO
var on_land: Callable
var is_controller := false

var _t := 0.0
var _duration := 1.0
var _visual: Node3D

func _ready() -> void:
	_duration = max(0.15, start_pos.distance_to(target_pos) / weapon.speed)
	_visual = Node3D.new()
	add_child(_visual)
	if is_controller:
		_build_controller()
	else:
		var mesh := SphereMesh.new()
		mesh.radius = weapon.radius
		mesh.height = weapon.radius * 2
		_add_mesh(mesh, Vector3.ZERO, Color(0.85, 0.95, 0.30))

func _add_mesh(mesh: PrimitiveMesh, offset: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.45
	mesh.material = mat
	part.mesh = mesh
	part.position = offset
	_visual.add_child(part)

func _build_controller() -> void:
	# A chunky, readable gamepad silhouette with colored face buttons. It spins
	# end-over-end in flight so the Super reads as a thrown physical object.
	var body := BoxMesh.new()
	body.size = Vector3(1.15, 0.28, 0.68)
	_add_mesh(body, Vector3.ZERO, Color(0.34, 0.16, 0.52))
	for x in [-0.43, 0.43]:
		var grip := SphereMesh.new()
		grip.radius = 0.30
		grip.height = 0.62
		_add_mesh(grip, Vector3(x, -0.12, 0.20), Color(0.27, 0.11, 0.43))
	var button_colors := [Color(0.25, 0.9, 0.35), Color(0.95, 0.22, 0.2),
			Color(0.22, 0.55, 1.0), Color(1.0, 0.82, 0.18)]
	var button_offsets := [Vector3(0.28, 0.18, -0.10), Vector3(0.43, 0.18, 0.02),
			Vector3(0.13, 0.18, 0.02), Vector3(0.28, 0.18, 0.14)]
	for i in button_colors.size():
		var button := SphereMesh.new()
		button.radius = 0.07
		button.height = 0.08
		_add_mesh(button, button_offsets[i], button_colors[i])

func _physics_process(delta: float) -> void:
	_t += delta / _duration
	if is_controller:
		_visual.rotation.x += delta * 6.0
		_visual.rotation.z += delta * 3.5
	if _t >= 1.0:
		global_position = target_pos
		if on_land.is_valid():
			on_land.call(self)
		queue_free()
		return
	var flat := start_pos.lerp(target_pos, _t)
	var height := 4.0 * 3.0 * _t * (1.0 - _t)   # parabola, peak 3m
	global_position = flat + Vector3(0, height + 0.3, 0)
