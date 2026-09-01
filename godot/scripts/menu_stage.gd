class_name MenuStage
extends SubViewportContainer
## 3D fighter showcase for the lobby and fighter-detail screens: an own-world
## SubViewport with the kit's GLB idling, or the capsule fallback.

const STAGE_SIZE := Vector2(560, 620)

var _viewport: SubViewport
var _model_root: Node3D
var _sway_t: float = 0.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = STAGE_SIZE

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(STAGE_SIZE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# Models stand on y=0 facing -Z, so the camera sits on the -Z side.
	var cam := Camera3D.new()
	cam.fov = 35.0
	_viewport.add_child(cam)
	cam.position = Vector3(0, 1.4, -4.4)
	cam.look_at(Vector3(0, 0.95, 0))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 180, 0)  # lights the -Z-facing side
	sun.light_energy = 1.2
	_viewport.add_child(sun)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.ambient_light_energy = 0.7
	world_env.environment = env
	_viewport.add_child(world_env)

func show_kit(kit: Dictionary) -> void:
	if _model_root:
		_model_root.queue_free()
	_model_root = Node3D.new()
	_viewport.add_child(_model_root)
	if kit.has("model"):
		_setup_model(kit)
	else:
		_setup_capsule(kit)

## Same load pattern as fighter.gd:_setup_model — Meshy exports
## metallicFactor=1.0, which renders black without reflection probes.
func _setup_model(kit: Dictionary) -> void:
	var scene: PackedScene = load(kit.model)
	var model: Node3D = scene.instantiate()
	_model_root.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mat = mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				mat.metallic = 0.0
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if anim:
		var clips: Dictionary = kit.clips
		var a: Animation = anim.get_animation(clips.idle)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		anim.play(clips.idle)

func _setup_capsule(kit: Dictionary) -> void:
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = kit.color
	mesh.material = mat
	body.mesh = mesh
	body.position.y = 0.8
	_model_root.add_child(body)

	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.14
	nose_mesh.height = 0.28
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.95, 0.95, 0.95)
	nose_mesh.material = nose_mat
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 1.15, -0.42)
	_model_root.add_child(nose)

func _process(delta: float) -> void:
	# Gentle sway keeps the pose alive without ever showing the model's back.
	if _model_root:
		_sway_t += delta
		_model_root.rotation.y = sin(_sway_t * 0.6) * 0.28
