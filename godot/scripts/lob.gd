class_name Lob
extends Node3D
## Tony's tennis ball: arcs over walls to a target point, then the main
## scene applies splash damage via the callback.

var weapon: Dictionary
var damage := 0
var owner_fighter: Fighter
var start_pos := Vector3.ZERO
var target_pos := Vector3.ZERO
var on_land: Callable

var _t := 0.0
var _duration := 1.0

func _ready() -> void:
	_duration = max(0.15, start_pos.distance_to(target_pos) / weapon.speed)
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.95, 0.30)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.6, 0.1)
	mesh.material = mat
	m.mesh = mesh
	add_child(m)

func _physics_process(delta: float) -> void:
	_t += delta / _duration
	if _t >= 1.0:
		global_position = target_pos
		if on_land.is_valid():
			on_land.call(self)
		queue_free()
		return
	var flat := start_pos.lerp(target_pos, _t)
	var height := 4.0 * 3.0 * _t * (1.0 - _t)   # parabola, peak 3m
	global_position = flat + Vector3(0, height + 0.3, 0)
