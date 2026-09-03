extends SceneTree
## Renders the menu's portrait and full-body card art straight off the character
## GLBs. This replaces web-menu/tools/portraits.mjs, which was deleted with the
## HTML build and left the project with no way to make a portrait at all.
##
## The rig is menu_stage.gd's, deliberately: same 22 degree lens, same warm
## key / cool fill / gold rim, same ambient, so a portrait and the live fighter
## on the stage are lit identically. Framing is the one thing that differs —
## portraits aim at the head bone rather than the model centre, which is why
## these sit centred where the old three.js ones drifted off to one side.
##
## Needs a real renderer, so DO NOT pass --headless (the dummy driver renders
## nothing and every PNG comes out empty):
##   /Applications/Godot.app/Contents/MacOS/Godot --path godot \
##       --script res://tools/render_portraits.gd
##
## Env:
##   NS3_PORTRAIT_KITS=tony,henry   which kits (default: every kit with a model)
##   NS3_PORTRAIT_KIND=portrait|card|both          (default portrait)
##   NS3_PORTRAIT_OUT=res://some/dir               (default: the menu art dirs)

const PORTRAIT_DIR := "res://assets/menu/portraits/"
const CARD_DIR := "res://assets/menu/cards/"

const FOV := 22.0
## The portrait frame is sized to the HEAD, not to a fixed number of metres:
## the head fills this fraction of the frame height on every character. Our
## rigs are not proportioned alike — Tony's head is 41% of his body height
## against Henry's 25% — so a fixed span that framed Henry's head and shoulders
## cut Tony off at the chin. Scaling by head size is what makes a roster grid
## read as one set.
const PORTRAIT_HEAD_FRAC := 0.45
## Where the top of the skull sits in the frame, 0 bottom .. 1 top. Hung off the
## crown rather than centred on a bone, so the headroom above the hair is the
## same on everyone.
const PORTRAIT_CROWN_FRAC := 0.81
## Used only when a GLB has no bone we can read a head off.
const PORTRAIT_FALLBACK_VIEW_H := 0.90
const PORTRAIT_SIZE := 512

## Same as menu_stage.gd: the GLBs are authored at roughly this height and are
## never rescaled, so the card frames against the constant rather than an AABB
## (Meshy puts the scale in the skeleton, leaving the mesh AABB useless).
const MODEL_HEIGHT := 1.75
const CARD_FILL := 0.86
const CARD_SIZE := 768

var _viewport: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _started := false
var _finished := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished


func _run() -> void:
	var kind := OS.get_environment("NS3_PORTRAIT_KIND")
	if kind == "":
		kind = "portrait"
	var out_override := OS.get_environment("NS3_PORTRAIT_OUT")

	var wanted: Array[String] = []
	var kits_env := OS.get_environment("NS3_PORTRAIT_KITS")
	if kits_env != "":
		for k in kits_env.split(",", false):
			wanted.append(k.strip_edges().to_lower())

	_build_rig()

	var rendered := 0
	for kit: Dictionary in Kits.all():
		if not kit.has("model"):
			continue
		# The id the menu resolves art by is the GLB's basename, which is also
		# the lowercased kit name for every character we ship.
		var id: String = str(kit.model).get_file().get_basename().to_lower()
		if not wanted.is_empty() and not wanted.has(id):
			continue
		if kind == "portrait" or kind == "both":
			var dir: String = out_override if out_override != "" else PORTRAIT_DIR
			await _shoot(kit, id, dir, false)
			rendered += 1
		if kind == "card" or kind == "both":
			var dir_c: String = out_override if out_override != "" else CARD_DIR
			await _shoot(kit, id, dir_c, true)
			rendered += 1

	print("render_portraits: wrote %d image(s)" % rendered)
	if rendered == 0:
		print("  (no kit matched — NS3_PORTRAIT_KITS names ids like tony,henry)")
	_finished = true


# MARK: rig

## menu_stage.gd's three-point rig, so portraits match the live stage fighter.
func _build_rig() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_cam)

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


# MARK: shoot

func _shoot(kit: Dictionary, id: String, dir: String, full_body: bool) -> void:
	for child in _pivot.get_children():
		child.queue_free()
	await process_frame

	var model: Node3D = (load(str(kit.model)) as PackedScene).instantiate()
	_pivot.add_child(model)
	# Meshy exports metallicFactor=1.0, which renders black with no reflection
	# probe in the scene. fighter.gd and menu_stage.gd both clear it; so do we.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat: Variant = mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				mat.metallic = 0.0

	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if anim:
		var clips: Dictionary = kit.get("clips", {})
		var idle: String = str(clips.get("idle", "Idle"))
		if anim.has_animation(idle):
			anim.play(idle)
			anim.seek(0.0, true)

	_viewport.size = Vector2i.ONE * (CARD_SIZE if full_body else PORTRAIT_SIZE)
	if full_body:
		_frame(MODEL_HEIGHT * 0.5, MODEL_HEIGHT / CARD_FILL, 0.10 * MODEL_HEIGHT)
	else:
		var head: Vector2 = _head_span(model)   # (chin y, crown y)
		var view_h: float = PORTRAIT_FALLBACK_VIEW_H
		if head.y > head.x:
			view_h = (head.y - head.x) / PORTRAIT_HEAD_FRAC
		_frame(head.y - (PORTRAIT_CROWN_FRAC - 0.5) * view_h, view_h, 0.0)

	# Let the skeleton pose and the lights settle before reading the target.
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = _viewport.get_texture().get_image()
	var path := dir.path_join(id + (".webp" if full_body else ".png"))
	var err: int = img.save_webp(path, true, 0.92) if full_body else img.save_png(path)
	if err != OK:
		# Cards ship as WebP; fall back to PNG rather than losing the render.
		path = dir.path_join(id + ".png")
		err = img.save_png(path)
	print("  %-8s -> %s%s" % [id, path, "" if err == OK else "  FAILED"])


## Camera on the model's front (they face -Z, so the lens sits there), framing
## `view_height` metres of world at `centre_y`.
func _frame(centre_y: float, view_height: float, lift: float) -> void:
	var distance: float = view_height / (2.0 * tan(deg_to_rad(FOV) / 2.0))
	var target := Vector3(0, centre_y, 0)
	_cam.position = Vector3(0, centre_y + lift, -distance)
	_cam.look_at(target)


## Model-space (chin y, crown y) read off the skeleton. On every Meshy rig here
## the bone named `Head` sits at the chin and `head_end` is the tip of the
## skull, so the pair measures the head. Returns a degenerate span (chin >=
## crown) when there is nothing to read, which puts the caller on its fallback
## frame rather than aiming the camera at the floor.
func _head_span(model: Node3D) -> Vector2:
	var none := Vector2(MODEL_HEIGHT * 0.95, MODEL_HEIGHT * 0.95)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return none
	var skel: Skeleton3D = skels[0]
	skel.force_update_all_bone_transforms()
	var to_model := model.global_transform.affine_inverse() * skel.global_transform
	var crown := -INF
	var chin := INF
	for b in skel.get_bone_count():
		var bone_name := skel.get_bone_name(b).to_lower()
		if not bone_name.contains("head"):
			continue
		var y: float = (to_model * skel.get_bone_global_pose(b)).origin.y
		crown = maxf(crown, y)
		chin = minf(chin, y)
	if crown == -INF:
		return none
	return Vector2(chin, crown)
