extends CanvasLayer
## The transition between the lobby and a match, and back.
##
## Both scene changes used to be a bare `change_scene_to_file`, which is a
## BLOCKING load: the menu was torn down, and the process then sat there
## decoding the character GLBs and main.gd's 21 MB power_cube preload with
## nothing on screen but the arena's pale sky clear colour. It read as a hang
## rather than as a transition.
##
## This is an autoload so it can outlive the scene swap it is covering — a
## loading screen owned by the scene being replaced dies halfway through the
## job. It threaded-loads the target scene AND every character model up front,
## holds a reference to each so the later `load()` in fighter.gd hits the
## resource cache instead of the disk, and only lifts once the incoming scene
## says it is built.

enum State { IDLE, LOADING, WAITING }

const MATCH_SCENE := "res://game.tscn"
const MENU_SCENE := "res://menu.tscn"
const KEYART := "res://assets/menu/background/loading_keyart.jpg"

## What the engine's own boot splash says, and the size it is rendered at.
## The splash is not a second design — it is a PNG of THIS screen's first frame,
## shot by tools/make_boot_splash.gd, because the engine paints it before any of
## our code is running and a static image is all it can paint. "Returning" is
## the one word that cannot carry over: a cold start has nowhere to return to.
const BOOT_TITLE := "NOBLE STARS"
const BOOT_SUBTITLE := "Starting up"
## The viewport this screen is authored against — the match HUD's, not the
## menu's 1920x1080 stage. Also what the splash render composes at.
const BOOT_SIZE := Vector2i(1280, 720)
## The ground the keyart sits on. `application/boot_splash/bg_color` in
## project.godot is this colour by hand, and has to stay that way: the engine
## fits the splash inside the window, so on anything wider than 16:9 this is
## what fills the columns either side of it.
const BASE_INK := Color("#05070f")

## A loading screen that flashes for three frames is worse than none: it reads
## as a glitch. Below this the screen is held even once the work is done.
const MIN_SHOW := 0.75
const FADE_IN := 0.15
const FADE_OUT := 0.28
## If the incoming scene never calls done() — a code path that forgot to, or one
## that errored on the way up — the screen lifts anyway rather than stranding
## the player behind it forever.
const SAFETY_SECONDS := 15.0

var _state: State = State.IDLE
var _paths: PackedStringArray = []
var _target := ""
## Every resource this screen pulled in, kept referenced for the life of the
## session. That is the whole point: dropping these would let the cache evict
## them and put the decode back on the frame that spawns a fighter.
var _held: Array[Resource] = []
var _elapsed := 0.0
var _ready_for_lift := false

var _root: Control
var _bar: Panel
var _percent: Label
var _status: Label

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)

# MARK: entry points

## Menu -> match. Reads what to say off Session, which the menu has already set.
func to_match(tree: SceneTree) -> void:
	var kit_name: String = str(Session.kit.get("name", "")) if Session.kit is Dictionary else ""
	var mode: String = Session.mode
	_build(str(VersusScreen.MODE_TITLE.get(mode, mode.to_upper())),
			str(VersusScreen.MODE_SUB.get(mode, "")), kit_name)
	var wanted := PackedStringArray([MATCH_SCENE])
	# Every model, not just the one the player picked: Showdown fills the other
	# nine slots with random kits and Nobles Cup fills five, so any of them can
	# be spawned a frame after the match scene comes up.
	for kit: Dictionary in Kits.all():
		var model: String = str(kit.get("model", ""))
		if model != "" and not wanted.has(model):
			wanted.append(model)
		# Worn gear (Ayaan's skis) is a GLB of its own that `Fighter._setup_gear`
		# loads on the spawn frame, so it wants the same cache hit as the body.
		var gear: String = str((kit.get("gear", {}) as Dictionary).get("model", ""))
		if gear != "" and not wanted.has(gear):
			wanted.append(gear)
		var thrown: String = str((kit.get("weapon", {}) as Dictionary).get("model", ""))
		if thrown != "" and not wanted.has(thrown):
			wanted.append(thrown)
	# The gas bank is built on the match's first frame now (it used to be built
	# on the first shrink), so its model wants to be in the cache by then for the
	# same reason `power_cube.glb` is preloaded: a multi-megabyte GLB coming off
	# disk during play is a visible freeze. Showdown only — the Cup pitch has no
	# ring closing in on it.
	if mode != "cup":
		wanted.append(GasRing.CLOUD_MODEL)
	_begin(tree, MATCH_SCENE, wanted)

## Match -> lobby. Lighter, but it is the same blocking call and the same stall.
func to_menu(tree: SceneTree) -> void:
	_build("NOBLE STARS", "Returning to the lobby", "")
	_begin(tree, MENU_SCENE, PackedStringArray([MENU_SCENE]))

## The incoming scene reporting that it is actually built and worth looking at.
## A no-op when nothing is showing, so the NS3_* debug hooks — which skip this
## screen entirely and change scene directly — can call it unconditionally.
func done() -> void:
	_ready_for_lift = true

# MARK: flow

func _begin(tree: SceneTree, target: String, paths: PackedStringArray) -> void:
	if _state != State.IDLE:
		# Already covering a swap. A second request would start a second _run
		# racing the first to change the scene.
		return
	_target = target
	_paths = paths
	_elapsed = 0.0
	_ready_for_lift = false
	_state = State.LOADING
	for p in _paths:
		# A path already in the cache still has to be requested, or
		# load_threaded_get_status has nothing to report on.
		ResourceLoader.load_threaded_request(p)
	visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	set_process(true)
	# Held so the swap cannot happen before the screen has actually painted.
	_run(tree)

func _process(delta: float) -> void:
	_elapsed += delta

func _run(tree: SceneTree) -> void:
	# Two frames so the fade-in is on screen before the loader starts competing
	# for the main thread on its completion callbacks.
	await tree.process_frame
	await tree.process_frame
	var loaded: Array[Resource] = []
	# Collected as each one lands, never re-polled: load_threaded_get CONSUMES
	# the request, so asking after it a second time reports the path as an
	# invalid resource and every finished load looks like a failure.
	var pending: Array = Array(_paths)
	var finished := 0
	var failed := false
	while not pending.is_empty():
		var partial := 0.0
		for p: String in pending.duplicate():
			var progress: Array = []
			var status := ResourceLoader.load_threaded_get_status(p, progress)
			match status:
				ResourceLoader.THREAD_LOAD_LOADED:
					pending.erase(p)
					finished += 1
					var res: Resource = ResourceLoader.load_threaded_get(p)
					if res != null:
						loaded.append(res)
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					partial += float(progress[0]) if not progress.is_empty() else 0.0
				_:
					# This one will not load. The match matters more than the
					# screen does, so the target is still opened — just without
					# whatever this was warmed into the cache.
					push_warning("Loading: could not load %s (status %d)" % [p, status])
					pending.erase(p)
					finished += 1
					failed = true
		_set_progress((float(finished) + partial) / float(maxi(1, _paths.size())))
		if not pending.is_empty():
			await tree.process_frame

	for res in loaded:
		if not _held.has(res):
			_held.append(res)
	if failed:
		push_warning("Loading: some resources failed; the scene change goes ahead anyway")
	_set_progress(1.0)
	while _elapsed < MIN_SHOW:
		await tree.process_frame

	if is_instance_valid(_status):
		_status.text = "ENTERING THE ARENA" if _target == MATCH_SCENE else "LOADING"
	var packed: PackedScene = null
	for res in loaded:
		if res is PackedScene and res.resource_path == _target:
			packed = res
	if packed != null:
		tree.change_scene_to_packed(packed)
	else:
		tree.change_scene_to_file(_target)

	_state = State.WAITING
	var waited := 0.0
	while not _ready_for_lift and waited < SAFETY_SECONDS:
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
	_lift()

func _lift() -> void:
	_state = State.IDLE
	set_process(false)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(func() -> void: visible = false)

func _set_progress(ratio: float) -> void:
	if not is_instance_valid(_bar):
		return
	var r: float = clampf(ratio, 0.0, 1.0)
	MenuUI.set_bar(_bar, r, false)
	_percent.text = "%d%%" % int(round(r * 100.0))

# MARK: the screen itself

## Rebuilt per transition — it is cheap, and the copy differs every time.
func _build(title: String, subtitle: String, kit_name: String) -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	var parts := compose(title, subtitle, kit_name)
	_root = parts["root"]
	_bar = parts["bar"]
	_percent = parts["percent"]
	_status = parts["status"]
	add_child(_root)

## The screen as a detached Control tree, plus the three nodes the loader drives.
## Static, and building into nothing in particular, so that
## tools/make_boot_splash.gd can render this exact frame into the engine's boot
## splash without an autoload and a scene change. Change the screen and the
## splash is one command behind it rather than a second thing to redraw.
##
## Authored against the 1280x720 viewport the match HUD uses, not the menu's
## 1920x1080 stage, and anchored throughout so "expand" on a taller phone
## widens it rather than cropping it.
##
## `with_progress` is off for the boot splash, which is a STILL: a progress bar
## frozen at 0% for the length of a cold start does not read as "loading", it
## reads as loading that has stalled, and it is the first thing anyone sees. The
## splash says what the game is; the screen that takes over from it a moment
## later says how far along it is. The status caption goes with the bar rather
## than staying behind, because "LOADING" is the bar's label and on its own
## under "Starting up" it just says the subtitle twice.
static func compose(title: String, subtitle: String, kit_name: String,
		with_progress: bool = true) -> Dictionary:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing underneath is ready to be poked

	var base := ColorRect.new()
	base.color = BASE_INK
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(base)

	if ResourceLoader.exists(KEYART):
		var art := TextureRect.new()
		art.texture = load(KEYART)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(art)

	# A scrim over the bottom third so the copy reads against whatever the art
	# happens to be doing down there. Its own vertical ramp rather than MenuUI's
	# horizontal one turned on its side: rotating a Control means sizing it in
	# the rotated frame, and driving that from its own `resized` recurses.
	var scrim := TextureRect.new()
	scrim.texture = _scrim_texture()
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.offset_top = -340
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)

	var strip: VBoxContainer = MenuUI.vbox(6)
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = 46
	strip.offset_right = -46
	strip.offset_top = -212
	strip.offset_bottom = -30
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)

	var head: HBoxContainer = MenuUI.hbox(16)
	strip.add_child(head)
	var words: VBoxContainer = MenuUI.vbox(-2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(words)
	words.add_child(MenuUI.display(title, 46, Color.WHITE, 8))
	words.add_child(MenuUI.body(subtitle, 20, MenuUI.TEXT_DIM))

	if kit_name != "":
		head.add_child(_fighter_badge(kit_name))

	if not with_progress:
		return {"root": root, "bar": null, "percent": null, "status": null}

	var bar_row: HBoxContainer = MenuUI.hbox(12)
	strip.add_child(bar_row)
	var bar: Panel = MenuUI.bar(16, MenuUI.YELLOW, MenuUI.YELLOW_HI)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(bar)
	var percent: Label = MenuUI.display("0%", 22, MenuUI.TEXT_SOFT, 4)
	percent.custom_minimum_size = Vector2(72, 0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(percent)

	var status: Label = MenuUI.body("LOADING", 16, MenuUI.TEXT_DIM, true)
	strip.add_child(status)
	MenuUI.set_bar(bar, 0.0, false)
	return {"root": root, "bar": bar, "percent": percent, "status": status}

static var _scrim: GradientTexture2D

## Transparent at the top, near-black at the bottom, so the copy sits on solid
## ground and the art above it is untouched.
static func _scrim_texture() -> GradientTexture2D:
	if _scrim != null:
		return _scrim
	var ink := Color(0.02, 0.03, 0.07)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(ink.r, ink.g, ink.b, 0.0),
		Color(ink.r, ink.g, ink.b, 0.42),
		Color(ink.r, ink.g, ink.b, 0.96)])
	_scrim = GradientTexture2D.new()
	_scrim.gradient = grad
	_scrim.width = 8
	_scrim.height = 256
	_scrim.fill_from = Vector2(0, 0)
	_scrim.fill_to = Vector2(0, 1)
	return _scrim

## The fighter you picked, riding on the right of the title. Falls back to the
## kit's initial for Nova and Ayaan, which have no portrait yet.
static func _fighter_badge(kit_name: String) -> Control:
	var holder: Panel = MenuUI.card("dark", 14, 5)
	holder.custom_minimum_size = Vector2(118, 118)
	holder.size_flags_vertical = Control.SIZE_SHRINK_END
	var tex: Texture2D = MenuData.portrait(kit_name.to_lower())
	if tex != null:
		var pr := TextureRect.new()
		pr.texture = tex
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pr)
	else:
		var kit: Dictionary = Kits.named(kit_name)
		var initial: Label = MenuUI.display(kit_name.substr(0, 1).to_upper(), 60,
				kit.get("color", Color.WHITE), 7)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(initial)
	return holder
