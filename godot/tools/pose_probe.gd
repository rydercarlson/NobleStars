extends SceneTree
## Freeze a kit's model at chosen clip frames and shoot it, the way the menu
## stage and the gear probe light it — how an idle stance or a synthesized clip
## is judged without playing a match. Run WITHOUT --headless (nothing renders).
##
##   NS3_POSE_KIT=ayaan NS3_POSES="Idle:0,Idle:0:front,Running:0.3" \
##   NS3_POSE_OUT=/abs/dir Tools/godot.sh --path godot --script res://tools/pose_probe.gd
##
## Each pose is CLIP:SECONDS, with an optional third field `front` for the
## straight-on camera. NS3_POSE_BALL=1 adds the match ball from four sides
## (front, back, side, top), which is how a re-textured ball is checked.
var POSES: Array = []
var BALL_VIEWS: Array = []
var _i := 0
var _wait := 0
var _booted := false
var _model: Node3D
var _anim: AnimationPlayer
var _ball: Node3D
var _cam: Camera3D
var _label: Label
var _out := ""

func _initialize() -> void:
	# Godot skips drawing entirely while its window cannot draw (occluded,
	# minimized, display asleep), and get_image() then returns the last
	# frame it did draw — every shot comes out identical. Stay on top, and
	# force the draw ourselves before each capture regardless.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_out = OS.get_environment("NS3_POSE_OUT")
	if _out == "":
		_out = OS.get_environment("POSE_DIR")   # the older name, still honoured
	for item in OS.get_environment("NS3_POSES").split(",", false):
		var parts: PackedStringArray = item.strip_edges().split(":")
		if parts.size() >= 2:
			var pose: Array = [parts[0], float(parts[1])]
			if parts.size() > 2:
				pose.append(parts[2])
			POSES.append(pose)
	if OS.get_environment("NS3_POSE_BALL") != "":
		BALL_VIEWS = [Vector3(0, 0.6, -3.0), Vector3(0, 0.6, 3.0), Vector3(3.0, 0.6, 0), Vector3(0, 3.2, 0.01)]
	if POSES.is_empty() and BALL_VIEWS.is_empty():
		push_error("pose_probe: set NS3_POSES=\"CLIP:SECONDS,...\" and/or NS3_POSE_BALL=1")
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.42, 0.52)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.70, 0.35)
	pm.material = fm
	floor.mesh = pm
	world.add_child(floor)
	var kit_name: String = OS.get_environment("NS3_POSE_KIT")
	if kit_name == "":
		kit_name = "ayaan"
	var kit: Dictionary = Kits.named(kit_name.capitalize())
	if kit.is_empty() or str(kit.get("model", "")) == "":
		push_error("pose_probe: no modelled kit named %s" % kit_name)
		quit(1)
		return
	_model = (load(kit.model) as PackedScene).instantiate()
	world.add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	# NS3_POSE_BALL=live shoots the match ball as `ball.gd` draws it; anything
	# else shoots the raw GLB, which is how a re-textured export is checked.
	if OS.get_environment("NS3_POSE_BALL") == "live":
		_ball = Ball.new()
	else:
		_ball = (load("res://assets/soccer_ball.glb") as PackedScene).instantiate()
		for mi in _ball.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(si)
				if m is BaseMaterial3D:
					m.metallic = 0.0
	_ball.position = Vector3(0, 0.6, 0)
	_ball.visible = false
	world.add_child(_ball)
	_cam = Camera3D.new()
	_cam.fov = 30
	world.add_child(_cam)
	var ui := CanvasLayer.new()
	root.add_child(ui)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 26)
	ui.add_child(_label)

func _show(i: int) -> void:
	if i < POSES.size():
		_model.visible = true
		_ball.visible = false
		_anim.play(POSES[i][0])
		_anim.seek(POSES[i][1], true)
		_anim.pause()
		if POSES[i].size() > 2 and str(POSES[i][2]) == "front":
			_cam.position = Vector3(0.0, 1.35, -3.8)   # the menu stage's straight-on view
		else:
			_cam.position = Vector3(1.6, 1.7, -3.0)
		_cam.look_at(Vector3(0, 0.9, 0))
		_label.text = "%s t=%.2f%s" % [POSES[i][0], POSES[i][1], " front" if POSES[i].size() > 2 else ""]
	else:
		var v: int = i - POSES.size()
		_model.visible = false
		_ball.visible = true
		_cam.position = BALL_VIEWS[v]
		_cam.look_at(Vector3(0, 0.6, 0))
		_label.text = "ball view %d (%s)" % [v, ["front -Z", "back +Z", "side +X", "top"][v]]

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_cam.make_current()
		_show(0)
		return false
	_wait += 1
	if _wait < 12:
		return false
	_wait = 0
	if not DisplayServer.window_can_draw():
		RenderingServer.force_draw(false)
	print("shot %d: can_draw=%s frames=%d cam=%s label=%s" % [_i, DisplayServer.window_can_draw(), Engine.get_frames_drawn(), _cam.position, _label.text])
	root.get_viewport().get_texture().get_image().save_png("%s/p_%02d.png" % [_out, _i])
	_i += 1
	if _i >= POSES.size() + BALL_VIEWS.size():
		quit()
		return true
	_show(_i)
	return false
