extends SceneTree
## Renders an arena straight off Arena's own build, lit with Arena.make_sun and
## Arena.make_environment — the exact rig main.gd lights a match with, because a
## terrain pass judged under a different light is judged wrong.
##
## Two jobs on one rig:
##   overview  the whole map from above, which is how you look at a floor, a
##             wall silhouette or a pond all at once instead of a fighter's
##             worth of it at a time. It is also the frame the events screen's
##             map thumbnails will want.
##   game      the match camera's own offset and lens, pointed anywhere on the
##             map, so a shader tweak can be checked without playing through
##             seven seconds of pre-match to reach a screenshot. It reads
##             Arena.MATCH_CAM_*, which is where main.gd reads its own framing
##             from, so the two cannot drift.
##
## Needs a real renderer, so DO NOT pass --headless (the dummy driver renders
## nothing and every PNG comes out empty):
##   /Applications/Godot.app/Contents/MacOS/Godot --path godot \
##       --script res://tools/render_map.gd
##
## Env:
##   NS3_MAP=showdown|cup             which map            (default showdown)
##   NS3_MAP_KIND=overview|game|both  which frame          (default overview)
##   NS3_MAP_AT="col,row"             where the game camera looks, in TILES
##                                    from the map's 0,0 corner (default centre)
##   NS3_MAP_OUT=<dir>                where to write       (default user://)
##   NS3_MAP_SIZE=<px>                overview edge        (default 1024)

## The overview keeps the match's 60 degree pitch rather than looking straight
## down: a wall's face and its cast shadow are half of what a top-down arena
## reads by, and a plan view throws both away.
const OVERVIEW_PITCH := -60.0
const OVERVIEW_YAW := 0.0
## Ortho, so no part of the map is nearer the lens than any other and a wall on
## the far edge is the same size as one under the camera.
const OVERVIEW_PAD := 1.06
const GAME_SIZE := Vector2i(1280, 720)

var _viewport: SubViewport
var _cam: Camera3D
var _arena: Arena
var _started := false
var _finished := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished


func _run() -> void:
	var map := OS.get_environment("NS3_MAP")
	if map == "":
		map = "showdown"
	var kind := OS.get_environment("NS3_MAP_KIND")
	if kind == "":
		kind = "overview"
	var out_dir := OS.get_environment("NS3_MAP_OUT")
	if out_dir == "":
		out_dir = "user://"
	if not out_dir.ends_with("/"):
		out_dir += "/"

	var wrote := 0
	if kind == "overview" or kind == "both":
		await _shoot_overview(map, out_dir)
		wrote += 1
	if kind == "game" or kind == "both":
		await _shoot_game(map, out_dir)
		wrote += 1
	if wrote == 0:
		print("render_map: NS3_MAP_KIND must be overview, game or both")
	_finished = true


# MARK: rig

## A fresh world per shot. The arena builds in _ready, so it cannot be rebuilt
## for a second frame — and the two frames want different projections anyway.
func _build_rig(map: String, size: Vector2i) -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = size
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	var world_env := WorldEnvironment.new()
	world_env.environment = Arena.make_environment()
	_viewport.add_child(world_env)
	_viewport.add_child(Arena.make_sun())

	_arena = Arena.new()
	_arena.map_mode = map
	_viewport.add_child(_arena)

	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_cam)


func _tear_down() -> void:
	_viewport.queue_free()
	await process_frame


# MARK: frames

func _shoot_overview(map: String, out_dir: String) -> void:
	var px := int(OS.get_environment("NS3_MAP_SIZE"))
	if px <= 0:
		px = 1024
	_build_rig(map, Vector2i(px, px))

	var pitch := deg_to_rad(OVERVIEW_PITCH)
	# The map's footprint as the camera sees it: full width across, and a depth
	# foreshortened by the pitch. Framing on the raw depth leaves a third of a
	# 39x39 arena as empty margin.
	var span_h: float = _arena.map_depth() * sin(-pitch) + Arena.WALL_HEIGHT * cos(-pitch)
	var span_w: float = _arena.map_width()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = max(span_h, span_w) * OVERVIEW_PAD
	_cam.near = 1.0
	_cam.far = 400.0
	_cam.rotation_degrees = Vector3(OVERVIEW_PITCH, OVERVIEW_YAW, 0)
	_cam.position = _arena.centre() - _cam.global_transform.basis.z * -160.0

	await _write(out_dir + "map_%s_overview.png" % map)
	await _tear_down()


func _shoot_game(map: String, out_dir: String) -> void:
	_build_rig(map, GAME_SIZE)

	var at: Vector3 = _arena.centre()
	var where := OS.get_environment("NS3_MAP_AT")
	if where != "":
		var parts := where.split(",")
		if parts.size() == 2:
			at = _arena.tile_center(int(parts[0]), int(parts[1]))
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = Arena.MATCH_CAM_FOV
	_cam.position = at + Arena.MATCH_CAM_OFFSET
	_cam.look_at(at, Vector3.UP)

	await _write(out_dir + "map_%s_game.png" % map)
	await _tear_down()


## Two frames before reading back: the first builds the arena (its _ready runs
## on entering the tree) and compiles every terrain shader, and a texture read
## on that frame catches the clear colour and nothing else.
func _write(path: String) -> void:
	await process_frame
	await process_frame
	var img := _viewport.get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		print("render_map: could not write %s (%d)" % [path, err])
		return
	print("render_map: wrote %s" % ProjectSettings.globalize_path(path))
