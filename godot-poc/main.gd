extends Node3D
# PoC arena: everything except the player is built in code, which keeps the
# .tscn files trivial and the whole project reviewable as text.

@onready var cam: Camera3D = $Camera3D
@onready var player: CharacterBody3D = $Player

var _shot_timer := 0.0

func _ready() -> void:
	_build_lighting()
	_build_arena()
	cam.position = player.position + Vector3(0, 14, 9)
	cam.look_at(player.position, Vector3.UP)

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.75, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

func _build_arena() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(30, 1, 30), Color(0.45, 0.70, 0.35))  # ground
	# A few Brawl-style cover blocks
	for p in [Vector3(-6, 0.75, -4), Vector3(-4, 0.75, -4), Vector3(5, 0.75, 2),
			  Vector3(5, 0.75, 4), Vector3(0, 0.75, -8), Vector3(-8, 0.75, 6)]:
		_box(p, Vector3(2, 1.5, 2), Color(0.62, 0.46, 0.32))
	# Border walls
	_box(Vector3(0, 0.75, -15), Vector3(30, 1.5, 1), Color(0.55, 0.40, 0.28))
	_box(Vector3(0, 0.75, 15), Vector3(30, 1.5, 1), Color(0.55, 0.40, 0.28))
	_box(Vector3(-15, 0.75, 0), Vector3(1, 1.5, 30), Color(0.55, 0.40, 0.28))
	_box(Vector3(15, 0.75, 0), Vector3(1, 1.5, 30), Color(0.55, 0.40, 0.28))

func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	add_child(body)

func _process(delta: float) -> void:
	# Brawl-style chase camera
	var target := player.global_position + Vector3(0, 14, 9)
	cam.global_position = cam.global_position.lerp(target, 0.08)
	cam.look_at(player.global_position, Vector3.UP)

	# Automated verification: POC_SHOT=/path.png saves a frame and quits.
	var shot_path := OS.get_environment("POC_SHOT")
	if shot_path != "":
		_shot_timer += delta
		if _shot_timer > 2.5:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			get_tree().quit()
