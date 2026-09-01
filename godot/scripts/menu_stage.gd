class_name MenuStage
extends Control
## The live fighter on the auditorium stage — web-menu/src/brawler3d.js as a
## SubViewport. Same framing maths (model normalised to one unit tall, feet at
## y=0, camera pulled back so the model fills `FILL` of the view), same
## interactions: tap plays the attack clip, drag spins, and it eases back.
##
## The clips it plays are the match's own: kits.gd `clips` drive both, so a
## fighter idles and swings in the menu exactly as they do in a game.

const FOV := 22.0
const FILL := 0.72            # fighter height as a fraction of the view height
## Fighters are modelled at roughly this height in metres, and the match uses
## them at that scale (fighter.gd never rescales a GLB), so the menu frames
## them the same way rather than normalising — Meshy puts the scale in the
## skeleton, which leaves the mesh AABB useless for measuring.
const MODEL_HEIGHT := 1.75
const LOOK_Y := MODEL_HEIGHT * 0.5
const DEFAULT_FOOT_FRAC := 0.885
const SPIN_PER_PIXEL := 0.012
const RETURN_DELAY := 2.2

var _container: SubViewportContainer
var _viewport: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _kit: Dictionary = {}
var _skel: Skeleton3D
var _foot_bones: PackedInt32Array = []
var _foot_rest_y := 0.0
var _model_base_y := 0.0

var _shadow: TextureRect
var _spin := 0.0
var _spin_velocity := 0.0
var _dragging := false
var _drag_moved := false
var _idle_time := 0.0
var _sway := 0.0
var _render_scale := 1.0
var _pending: Dictionary = {}

signal tapped

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false

	_shadow = TextureRect.new()
	_shadow.texture = _shadow_texture()
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	# stretch=false plus a scaled-down container lets the viewport render above
	# stage resolution, so the fighter stays sharp on a retina phone.
	_container = SubViewportContainer.new()
	_container.stretch = false
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_container.add_child(_viewport)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_cam)
	_frame_camera()

	# brawler3d.js's three-point rig: warm key, cool fill, gold rim.
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff1d6")
	key.light_energy = 1.9
	key.rotation_degrees = Vector3(-38, 205, 0)
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9ec1ff")
	fill.light_energy = 0.8
	fill.rotation_degrees = Vector3(-20, 130, 0)
	_viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ffc35c")
	rim.light_energy = 1.3
	rim.rotation_degrees = Vector3(-25, 20, 0)
	_viewport.add_child(rim)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e0")
	env.ambient_light_energy = 0.55
	world_env.environment = env
	_viewport.add_child(world_env)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	resized.connect(_layout)
	_layout()
	# show_brawler() can be called before the stage enters the tree.
	if not _pending.is_empty():
		var queued: Dictionary = _pending
		_pending = {}
		show_brawler(queued)

func _layout() -> void:
	if _viewport == null or size.x < 1.0 or size.y < 1.0:
		return
	var render_size: Vector2 = (size * _render_scale).round()
	_viewport.size = Vector2i(render_size)
	_container.position = Vector2.ZERO
	_container.size = render_size
	_container.scale = Vector2.ONE / _render_scale
	var foot_y: float = foot_fraction() * size.y
	_shadow.size = Vector2(300, 74)
	_shadow.position = Vector2(size.x / 2.0 - 150.0, foot_y - 46.0)

## Device pixels per stage pixel, so the viewport renders sharp on a phone.
func set_render_scale(value: float) -> void:
	_render_scale = clampf(value, 1.0, 2.0)
	_layout()

## brawler3d.js _frame(): pull the camera back until the unit-tall model fills
## FILL of the view height. The models face -Z, so the camera sits there.
func _frame_camera() -> void:
	var visible_height: float = MODEL_HEIGHT / FILL
	var distance: float = visible_height / (2.0 * tan(deg_to_rad(FOV) / 2.0))
	_cam.position = Vector3(0, LOOK_Y + 0.10 * MODEL_HEIGHT, -distance)
	_cam.look_at(Vector3(0, LOOK_Y, 0))

## Where the feet land in the view, 0 top .. 1 bottom — MenuShell uses this to
## sit the fighter on the painted stage floor.
func foot_fraction() -> float:
	if _cam == null or not _cam.is_inside_tree():
		return DEFAULT_FOOT_FRAC
	# Projected by hand rather than through unproject_position, which needs a
	# sized viewport — this is called while the stage is still being laid out.
	var local: Vector3 = _cam.global_transform.affine_inverse() * Vector3.ZERO
	var depth: float = -local.z
	if depth <= 0.001:
		return DEFAULT_FOOT_FRAC
	var half_height: float = tan(deg_to_rad(FOV) * 0.5) * depth
	return clampf((1.0 - local.y / half_height) / 2.0, 0.0, 1.0)

# MARK: model

func show_brawler(brawler: Dictionary) -> void:
	if brawler.is_empty():
		return
	if _pivot == null:
		_pending = brawler
		return
	_kit = Kits.named(str(brawler.get("kit_name", "Nova")))
	_clear()
	_spin = 0.0
	_spin_velocity = 0.0
	if _kit.has("model"):
		_setup_model()
	else:
		_setup_capsule()
	_layout()

func _clear() -> void:
	_model = null
	_model_base_y = 0.0
	_anim = null
	_skel = null
	_foot_bones = PackedInt32Array()
	for child in _pivot.get_children():
		child.queue_free()

## Same load pattern as fighter.gd: Meshy exports metallicFactor=1.0, which
## renders black without reflection probes, then the model is normalised to
## one unit tall with its feet on y=0.
func _setup_model() -> void:
	var scene: PackedScene = load(_kit.model)
	_model = scene.instantiate()
	_pivot.add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat: Variant = mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				mat.metallic = 0.0
	_anim = _model.find_child("AnimationPlayer", true, false)
	if _anim:
		var clips: Dictionary = _kit.clips
		var idle: Animation = _anim.get_animation(clips.idle)
		if idle:
			idle.loop_mode = Animation.LOOP_LINEAR
		_anim.play(clips.idle)
		_anim.animation_finished.connect(_on_clip_finished)
	_calibrate_feet()

func _setup_capsule() -> void:
	var holder := Node3D.new()
	_pivot.add_child(holder)
	_model = holder
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _kit.get("color", Color.WHITE)
	mesh.material = mat
	body.mesh = mesh
	body.position.y = 0.8
	holder.add_child(body)
	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.14
	nose_mesh.height = 0.28
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.95, 0.95, 0.95)
	nose_mesh.material = nose_mat
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 1.15, -0.42)
	holder.add_child(nose)

## Ported from fighter.gd: Meshy's attack clips drop the hips below the rest
## pose, so record the idle foot height and lift the model by any later sink.
func _calibrate_feet() -> void:
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	_skel = skels[0]
	for b in _skel.get_bone_count():
		var bone_name := _skel.get_bone_name(b).to_lower()
		if bone_name.contains("foot") or bone_name.contains("toe"):
			_foot_bones.append(b)
	if _foot_bones.is_empty():
		_skel = null
		return
	if _anim:
		_anim.seek(0.0, true)
	_foot_rest_y = _lowest_foot_y()

func _lowest_foot_y() -> float:
	_skel.force_update_all_bone_transforms()
	var to_model := _model.global_transform.affine_inverse() * _skel.global_transform
	var lowest := INF
	for b in _foot_bones:
		lowest = minf(lowest, (to_model * _skel.get_bone_global_pose(b)).origin.y)
	return lowest

# MARK: playback

## Tap plays the fighter's real attack swing, at the match's own clip speed.
func play_attack() -> void:
	_play_clip("attack", "attack_speed", "attack_seek")

func play_super() -> void:
	_play_clip("super", "super_speed", "super_seek")

func play_run() -> void:
	_play_clip("run", "", "")

func play_idle() -> void:
	if _anim and _kit.has("clips"):
		_anim.play(str(_kit.clips.idle), 0.25)

func has_clip(key: String) -> bool:
	if _anim == null or not _kit.has("clips"):
		return false
	var clips: Dictionary = _kit.clips
	return clips.has(key) and _anim.has_animation(str(clips[key]))

func _play_clip(key: String, speed_key: String, seek_key: String) -> void:
	if not has_clip(key):
		return
	var clips: Dictionary = _kit.clips
	var clip_name: String = str(clips[key])
	var anim: Animation = _anim.get_animation(clip_name)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if key == "run" else Animation.LOOP_NONE
	var speed: float = float(clips.get(speed_key, 1.0)) if speed_key != "" else 1.0
	_anim.play(clip_name, 0.15, speed)
	if seek_key != "" and clips.has(seek_key):
		_anim.seek(float(clips[seek_key]), true)

func _on_clip_finished(clip_name: StringName) -> void:
	if _kit.has("clips") and str(clip_name) != str(_kit.clips.idle):
		play_idle()

# MARK: input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_dragging = true
			_drag_moved = false
			_spin_velocity = 0.0
		elif _dragging:
			_dragging = false
			if not _drag_moved:
				play_attack()
				tapped.emit()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		if absf(mm.relative.x) > 1.0:
			_drag_moved = true
		var scale_x: float = maxf(get_global_transform().get_scale().x, 0.0001)
		var delta: float = (mm.relative.x / scale_x) * SPIN_PER_PIXEL
		_spin += delta
		_spin_velocity = delta * 60.0
		_idle_time = 0.0

func _process(delta: float) -> void:
	if _pivot == null:
		return
	if _dragging:
		_idle_time = 0.0
	else:
		_idle_time += delta
		_spin += _spin_velocity * delta
		_spin_velocity = move_toward(_spin_velocity, 0.0, 6.0 * delta)
		if _idle_time > RETURN_DELAY:
			_spin = lerpf(_spin, 0.0, minf(1.0, 2.0 * delta))
	# The gentle breathing sway only takes over once the model is back home.
	_sway += delta * 0.6
	var rest: float = sin(_sway) * 0.22 * clampf(1.0 - absf(_spin) * 2.0, 0.0, 1.0)
	_pivot.rotation.y = _spin + rest
	if _skel and _model:
		_ground_feet()

## Lift the model by however far the playing clip sinks its feet below the idle
## rest pose. Foot heights are measured pre-scale, so scale the correction.
func _ground_feet() -> void:
	var sink: float = maxf(0.0, _foot_rest_y - _lowest_foot_y())
	_model.position.y = _model_base_y + sink * _model.scale.y

## The soft contact ellipse the CSS draws under the fighter.
static func _shadow_texture() -> ImageTexture:
	var w := 128
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0)
			var d: float = p.length()
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, pow(a, 1.6) * 0.55))
	return ImageTexture.create_from_image(img)
