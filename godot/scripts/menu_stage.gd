class_name MenuStage
extends Control
## The live fighter, standing on the game's own ground.
##
## This fills the whole menu stage. The set is deliberately almost nothing: the
## arena's GROUND_SHADER on one plane, the pitch's centre circle drawn around
## the fighter's feet, and depth fog that takes the ground out to ink before it
## reaches a horizon. That is the entire backdrop.
##
## It replaces a painted auditorium photograph, for two reasons. The photograph
## was rendered in a different style from the arena, so pressing PLAY was a hard
## cut to a different-looking game; and aligning a 3D fighter's feet to a floor
## line painted into a JPEG needed a chain of framing constants in MenuShell
## (FLOOR_FRAC, BRAWLER_VIEW, foot_fraction) that all exist only to serve the
## photograph. The ground is real now, so the fighter simply stands on it.
##
## The clips it plays are the match's own: kits.gd `clips` drive both, so a
## fighter idles and swings in the menu exactly as they do in a game.

const FOV := 22.0
## Fighter height as a fraction of the FULL stage height. The top and bottom
## bars take roughly 300 of 1080 stage pixels between them, so this keeps the
## figure inside the free band without it floating in the middle of it.
const FILL := 0.52
## Fighters are modelled at roughly this height in metres, and the match uses
## them at that scale (fighter.gd never rescales a GLB), so the menu frames them
## the same way rather than normalising — Meshy puts the scale in the skeleton,
## which leaves the mesh AABB useless for measuring.
const MODEL_HEIGHT := 1.75
const LOOK_Y := MODEL_HEIGHT * 0.5
## Camera pitch. Level would put the horizon across the fighter's chest and show
## the centre circle edge-on; steeper foreshortens a standing figure. This is
## enough to read the circle as a circle and no more.
const PITCH_DEG := 13.0
## Where the ground starts and finishes turning into background.
##
## These are tied to the camera distance and MUST stay outside it. `_frame_camera`
## puts the camera MODEL_HEIGHT / FILL / (2 tan(FOV/2)) away — about 8.6 m at the
## values above — and depth fog does not care that its subject is the point of
## the picture: a FOG_BEGIN inside that distance fogs the fighter. So the fog
## starts just past him and is fully ink a few metres later, which leaves a pool
## of lit ground around his feet and nothing else.
const FOG_BEGIN := 9.2
const FOG_END := 15.0
## The ground is the match's, at a fraction of the match's exposure. A menu is
## not a game: the arena floor is lit for reading a fight on, and at that
## brightness it filled the frame and took every dim label on the flanks with
## it. Same shader, same structure, turned down.
const GROUND_DIM := 0.30
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

var _spin := 0.0
var _spin_velocity := 0.0
var _dragging := false
var _drag_moved := false
var _idle_time := 0.0
var _sway := 0.0
var _render_scale := 1.0
var _pending: Dictionary = {}
var _clip_end_at := INF
var _clip_fast_at := INF
var _clip_end_speed_scale := 1.0

signal tapped

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# stretch=false plus a scaled-down container lets the viewport render above
	# stage resolution, so the fighter stays sharp on a retina phone.
	_container = SubViewportContainer.new()
	_container.stretch = false
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_container.add_child(_viewport)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_cam)
	_frame_camera()

	_build_set()

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	resized.connect(_layout)
	_layout()
	# show_brawler() can be called before the stage enters the tree.
	if not _pending.is_empty():
		var queued: Dictionary = _pending
		_pending = {}
		show_brawler(queued)

# MARK: the set

func _build_set() -> void:
	# The arena's own ground. Same shader the match floor uses, so a change to
	# the grass shows up in both places at once — which is the point of not
	# writing a second one.
	#
	# Markings are OFF. Switching them on to ring the fighter with the pitch's
	# centre circle also draws the halfway line, which `pitch_mark` runs through
	# the centre spot by definition: it came out as a bright band across the
	# fighter's shins. There is no way to ask that function for the circle alone,
	# and a second shader to get one is exactly the duplication above.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	floor_mesh.mesh = plane
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = Arena.GROUND_SHADER
	mat.shader = shader
	mat.set_shader_parameter("grass_a", Arena.GRASS_A * GROUND_DIM)
	mat.set_shader_parameter("grass_b", Arena.GRASS_B * GROUND_DIM)
	mat.set_shader_parameter("seam_color", Arena.GRASS_SEAM * GROUND_DIM)
	mat.set_shader_parameter("slab_color", Arena.SLAB_COLOR * GROUND_DIM)
	mat.set_shader_parameter("tile_size", Kits.TILE)
	mat.set_shader_parameter("slab_depth", Arena.SLAB_DEPTH)
	mat.set_shader_parameter("pitch_lines", 0.0)
	floor_mesh.material_override = mat
	_viewport.add_child(floor_mesh)

	# The match's sun, so the fighter's shadow falls the way it will in a game.
	# Its shadow range is the one thing that has to change: make_sun() sets 145 m
	# because the match camera sits 105 m back, and spending an orthogonal split
	# across 145 m for a subject 9 m away leaves the shadow a smear. This is the
	# same bug the match had, inverted.
	var sun: DirectionalLight3D = Arena.make_sun()
	sun.directional_shadow_max_distance = 26.0
	# Steep and close to the camera's own axis. The match's raking angle threw a
	# long shadow across the pool and lit one side of it far harder than the
	# other, which read as a bright blob off to one side rather than as ground;
	# from up here the pool is even and the shadow is a short one under the feet.
	sun.rotation_degrees = Vector3(-62, 168, 0)
	_viewport.add_child(sun)
	# Cool fill and a rim to separate the figure from the ink behind it; neither
	# casts, so there is exactly one shadow on the ground.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9ec1ff")
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-20, 130, 0)
	_viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ffc35c")
	rim.light_energy = 1.1
	rim.rotation_degrees = Vector3(-25, 20, 0)
	_viewport.add_child(rim)

	var world_env := WorldEnvironment.new()
	world_env.environment = _make_environment()
	_viewport.add_child(world_env)

## The match's environment, re-grounded on ink. Arena.make_environment() fades
## the scenery into SURROUND_HORIZON because at a 7 degree lens pointed 60
## degrees down the match never contains a horizon. This camera is nearly level
## and would, so the ground is taken out to the menu's own background colour by
## depth fog instead — the same "scenery meets background with no seam" trick,
## against a different background.
func _make_environment() -> Environment:
	var e: Environment = Arena.make_environment()
	e.background_color = MenuUI.INK
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = MenuUI.INK
	e.fog_light_energy = 1.0
	e.fog_depth_begin = FOG_BEGIN
	e.fog_depth_end = FOG_END
	e.fog_depth_curve = 1.4
	e.fog_sky_affect = 0.0
	return e

func _layout() -> void:
	if _viewport == null or size.x < 1.0 or size.y < 1.0:
		return
	var render_size: Vector2 = (size * _render_scale).round()
	_viewport.size = Vector2i(render_size)
	_container.position = Vector2.ZERO
	_container.size = render_size
	_container.scale = Vector2.ONE / _render_scale

## Device pixels per stage pixel, so the viewport renders sharp on a phone.
func set_render_scale(value: float) -> void:
	_render_scale = clampf(value, 1.0, 2.0)
	_layout()

## Pull the camera back until the model fills `fill` of the view height, then
## swing it up to PITCH_DEG along a ray of that same length, so raising the
## camera does not also change how big the fighter is.
var fill: float = FILL

func set_fill(value: float) -> void:
	fill = clampf(value, 0.3, 1.0)
	if _cam != null:
		_frame_camera()

func _frame_camera() -> void:
	var visible_height: float = MODEL_HEIGHT / fill
	var distance: float = visible_height / (2.0 * tan(deg_to_rad(FOV) / 2.0))
	var pitch: float = deg_to_rad(PITCH_DEG)
	var look := Vector3(0, LOOK_Y, 0)
	# The models face -Z, so the camera sits there.
	_cam.position = look + Vector3(0, sin(pitch) * distance, -cos(pitch) * distance)
	_cam.look_at(look)

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
## renders black without reflection probes.
func _setup_model() -> void:
	var scene: PackedScene = load(_kit.model)
	_model = scene.instantiate()
	_pivot.add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	# A fighter-sized blob reads as a mistake on the menu stage; a slim, muted
	# pillar reads as a stand-in for art that has not shipped yet.
	mesh.radius = 0.26
	mesh.height = 1.6
	var mat := StandardMaterial3D.new()
	var kit_color: Color = _kit.get("color", Color.WHITE)
	mat.albedo_color = kit_color.lerp(Color(0.5, 0.55, 0.65), 0.35)
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
	nose.position = Vector3(0, 1.15, -0.24)
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
		_clip_end_at = INF
		_clip_fast_at = INF
		_anim.speed_scale = 1.0
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
	_anim.speed_scale = 1.0
	_anim.play(clip_name, 0.15, speed)
	var seek_to := float(clips.get(seek_key, 0.0)) if seek_key != "" else 0.0
	if seek_to > 0.0:
		_anim.seek(seek_to, true)
	if key == "attack" or key == "super":
		_clip_end_at = clampf(float(clips.get(key + "_end", anim.length)), seek_to,
				anim.length)
		_clip_fast_at = clampf(float(clips.get(key + "_fast_at", _clip_end_at)),
				seek_to, _clip_end_at)
		var end_speed := maxf(0.01, float(clips.get(key + "_end_speed", speed)))
		_clip_end_speed_scale = end_speed / maxf(0.01, speed)
	else:
		_clip_end_at = INF
		_clip_fast_at = INF

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
	if _anim and _anim.current_animation_position >= _clip_end_at:
		play_idle()
	elif _anim and _anim.current_animation_position >= _clip_fast_at:
		_anim.speed_scale = _clip_end_speed_scale
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
