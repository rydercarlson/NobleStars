extends SceneTree
## Worn gear (kits.gd `gear`: Ayaan's skis, Anders' sack) bolted to its bones
## exactly as `Fighter._setup_gear` does it, frozen at chosen clip frames — so
## a rotation/scale/offset in kits.gd is judged in seconds instead of by
## catching a 0.12 s wind-up in a live match. Run WITHOUT --headless.
##
##   NS3_GEAR_SHOTS="ayaan:Jump_Over_Obstacle:0.8,anders:Kick_a_Soccer_Ball:0.3" \
##   NS3_GEAR_OUT=/abs/dir Tools/godot.sh --path godot --script res://tools/gear_probe.gd
##
## The solve here must stay a copy of fighter.gd's: if the two drift, this
## probe stops being evidence.
var SHOTS: Array = []
var _out := ""
var _i := 0
var _wait := 0
var _booted := false
var _world: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _cam: Camera3D
var _label: Label

func _initialize() -> void:
	# Godot skips drawing entirely while its window cannot draw (occluded,
	# minimized, display asleep), and get_image() then returns the last
	# frame it did draw — every shot comes out identical. Stay on top, and
	# force the draw ourselves before each capture regardless.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_out = OS.get_environment("NS3_GEAR_OUT")
	if _out == "":
		_out = OS.get_environment("GEAR_DIR")   # the older name, still honoured
	for item in OS.get_environment("NS3_GEAR_SHOTS").split(",", false):
		var parts: PackedStringArray = item.strip_edges().split(":")
		if parts.size() == 3:
			SHOTS.append([parts[0], parts[1], float(parts[2])])
	if SHOTS.is_empty():
		push_error("gear_probe: set NS3_GEAR_SHOTS=\"kit:CLIP:SECONDS,...\"")
		quit(1)
		return
	_world = Node3D.new()
	root.add_child(_world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.42, 0.52)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	_world.add_child(env)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.70, 0.35)
	pm.material = fm
	floor.mesh = pm
	_world.add_child(floor)
	_cam = Camera3D.new()
	_cam.fov = 30
	_world.add_child(_cam)
	var ui := CanvasLayer.new()
	root.add_child(ui)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 26)
	ui.add_child(_label)

func _load(kit_name: String) -> void:
	if _model:
		_model.queue_free()
	var kit: Dictionary = Kits.named(kit_name.capitalize())
	_model = (load(kit.model) as PackedScene).instantiate()
	_world.add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	var skel: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	var gear: Dictionary = kit.gear
	var source: Node3D = null
	if str(gear.get("shape", "")) == "":
		source = (load(gear.model) as PackedScene).instantiate()
		Fighter.flatten_metallic(source)
	var rot: Vector3 = gear.get("rotation_deg", Vector3.ZERO)
	var scl: Vector3 = gear.get("scale", Vector3.ONE)
	var offset: Vector3 = gear.get("offset", Vector3.ZERO)
	for spec in gear.get("pieces", []):
		var bone: int = skel.find_bone(str(spec.get("bone", "")))
		var piece: Node3D
		if source != null and not spec.has("node"):
			# the whole model as one piece, fitted to `radius` (Anders' sack)
			var whole: Node3D = (load(gear.model) as PackedScene).instantiate()
			Fighter.flatten_metallic(whole)
			piece = Fighter.fit_ball(whole, float(gear.get("radius", 0.2)))
		elif source != null:
			var found: Node3D = source.find_child(str(spec.get("node", "")), true, false)
			found.get_parent().remove_child(found)
			var pivot := Node3D.new()
			pivot.add_child(found)
			found.transform = Transform3D.IDENTITY
			piece = pivot
		else:
			var sphere := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = float(gear.get("radius", 0.2))
			sm.height = sm.radius * 2.0
			var mat := StandardMaterial3D.new()
			mat.albedo_color = gear.get("color", Color.WHITE)
			sm.material = mat
			sphere.mesh = sm
			piece = sphere
		var attach := BoneAttachment3D.new()
		attach.bone_name = str(spec.get("bone", ""))
		attach.bone_idx = bone
		skel.add_child(attach)
		attach.add_child(piece)
		# Solved in WORLD space: Meshy armatures carry a 0.01 scale, so a
		# child of the skeleton inherits it; taking the attachment's true
		# global transform (skeleton * bone rest) folds that scale into the
		# inverse, and the piece comes out at the size the kit asked for.
		var rest_global: Transform3D = skel.global_transform * skel.get_bone_global_rest(bone)
		var rest_model: Vector3 = _model.to_local(rest_global.origin)
		var desired_model := Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))).scaled(scl),
				Vector3(rest_model.x + offset.x, offset.y, rest_model.z + offset.z))
		piece.transform = rest_global.affine_inverse() * (_model.global_transform * desired_model)

func _show(i: int) -> void:
	var kit_name: String = SHOTS[i][0]
	if _model == null or _model.get_meta("kit", "") != kit_name:
		_load(kit_name)
		_model.set_meta("kit", kit_name)
	_anim.play(SHOTS[i][1])
	_anim.seek(SHOTS[i][2], true)
	_anim.pause()
	_cam.position = Vector3(1.9, 1.9, -2.9)
	_cam.look_at(Vector3(0, 0.85, 0))
	_label.text = "%s  %s t=%.2f" % [kit_name, SHOTS[i][1], SHOTS[i][2]]

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_cam.make_current()
		_show(0)
		return false
	_wait += 1
	if _wait < 8:
		return false
	_wait = 0
	if not DisplayServer.window_can_draw():
		RenderingServer.force_draw(false)
	print("shot %d: can_draw=%s frames=%d %s" % [_i, DisplayServer.window_can_draw(), Engine.get_frames_drawn(), _label.text])
	root.get_viewport().get_texture().get_image().save_png("%s/g_%02d.png" % [_out, _i])
	_i += 1
	if _i >= SHOTS.size():
		quit()
		return true
	_show(_i)
	return false
