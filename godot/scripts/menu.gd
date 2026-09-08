class_name MenuShell
extends Control
## The Nobles Brawl menu.
##
## Layout is authored in "stage pixels": a 1920x1080 stage that is scaled to the
## device and grown — never letterboxed — to cover it: a phone gains stage
## width, a 16:10 laptop in fullscreen gains stage height.
##
## The stage is a painted hall (the icon pack's green-lit stage, STAGE_BACKDROP)
## with the selected fighter rendered over it on a transparent viewport and a
## lit ring under his feet, and flat 2D chrome over all of it. The fighter's
## feet land at HomeScreen.FEET_Y because MenuStage frames him to the stage
## height (FILL) about a fixed look point — there is no per-image floor line.

const STAGE_H := 1080.0
const STAGE_MIN_W := 1920.0

signal currency_changed
signal brawler_changed
signal mode_changed
signal profile_changed

var stage: Control
var bg: ColorRect
var brawler_view: MenuStage
## Everything a thumb presses or an eye reads, inset by the device's safe area
## while the stage behind it fills the display. See _fit_stage.
var chrome: Control
var home: HomeScreen
var screens_root: Control
var toast_column: VBoxContainer
var fx: Control
var audio: MenuAudio

var _stack: Array[MenuScreen] = []
var _currency_labels: Array = []   # [{label, kind}]

## The bottom nav: four destinations, always on screen, the current one lit.
## It lives here rather than on the home screen so a pushed screen keeps it —
## the tab you are on stays gold, and switching is one tap, not back-then-tap.
const NAV_TABS := [["ROSTER", "roster", "shield"], ["SEASON", "season", "pass"],
		["SHOP", "shop", "shop"], ["WIFI", "wifi", "wifi"]]
var nav_bar: VBoxContainer
var _nav_buttons: Dictionary = {}   # target -> Button

func _ready() -> void:
	SaveGame.ensure_loaded()
	MenuData.ensure_loaded()
	# The menu is where the first tap of a session happens, and the haptic
	# engine idles down on its own — so warm it here as well as at match start,
	# or the very first button press is the one that arrives late.
	Haptics.warm()
	if _handle_debug_hooks():
		return
	_build_stage()
	_wire_debug_screenshot()
	Loading.done()   # lifts the loading screen if we got here from a match

## Debug hooks that skip the menu entirely. Returns true if one took over.
func _handle_debug_hooks() -> bool:
	if OS.get_environment("NS3_HOST") != "":
		var want := int(OS.get_environment("NS3_HOST"))
		# NS3_MODE picks the room's mode for the harness, the same way it picks
		# the mode for a single-player run. Only the HOST reads it: the room's
		# mode travels to the client with the roster, which is exactly the
		# behaviour the harness exists to check.
		var room_mode := OS.get_environment("NS3_MODE")
		Net.host_game(SaveGame.player_name, SaveGame.selected_kit,
				room_mode if room_mode != "" else "showdown")
		Net.roster_changed.connect(func() -> void:
			if Net.active and Net.players.size() >= want and not Net.locked:
				Net.start_game())
		return true
	if OS.get_environment("NS3_JOIN") != "":
		Net.join_game(OS.get_environment("NS3_JOIN"), SaveGame.player_name,
				SaveGame.selected_kit)
		return true
	if OS.get_environment("NS3_KIT") != "" or OS.get_environment("NS3_AUTOFIRE") != "" \
			or OS.get_environment("NS3_SIM") != "":
		Session.kit = Kits.named(OS.get_environment("NS3_KIT"))
		Session.mode = OS.get_environment("NS3_MODE") if OS.get_environment("NS3_MODE") != "" else "showdown"
		get_tree().change_scene_to_file.call_deferred("res://game.tscn")
		return true
	return false

func _build_stage() -> void:
	var letterbox := ColorRect.new()
	letterbox.color = MenuUI.INK
	letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letterbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(letterbox)

	stage = Control.new()
	stage.clip_contents = true
	add_child(stage)

	# Sits behind the 3D view so the stage is never bare during the frame a
	# fighter is being swapped, and is what _update_stage_dim darkens.
	bg = ColorRect.new()
	bg.color = MenuUI.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bg)

	# The painted stage from the icon pack: a dark hall with a green-lit floor.
	# It is scaled to cover the stage, so on a wider phone it is cropped top and
	# bottom rather than stretched. The fighter renders over it on a
	# transparent viewport (see MenuStage), with a lit ring under his feet.
	_backdrop = TextureRect.new()
	_backdrop.texture = load(STAGE_BACKDROP)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_tint = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = STAGE_TINT_SHADER
	_stage_tint.shader = sh
	_backdrop.material = _stage_tint
	stage.add_child(_backdrop)
	_build_floor_ring()

	brawler_view = MenuStage.new()
	brawler_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(brawler_view)
	# Shifted right by half the nav rail, so the fighter is centred in the space
	# the rail leaves rather than in the middle of the stage. He is the subject
	# of this screen; being 84 px off the middle of what you can actually see
	# reads as a mistake even when you cannot name it.
	#
	# AFTER add_child, not before: MenuStage._ready() applies PRESET_FULL_RECT
	# to itself, which zeroes any offset set on the way in. Setting these first
	# looked right and did nothing.
	brawler_view.offset_left = STAGE_SHIFT
	brawler_view.offset_right = STAGE_SHIFT

	# The picture above fills the stage; everything below is inset into the safe
	# area by _fit_stage. Screens anchor FULL_RECT to this rather than to the
	# stage, so no screen file has to know the safe area exists.
	chrome = Control.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(chrome)

	home = HomeScreen.new()
	home.menu = self
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chrome.add_child(home)

	screens_root = Control.new()
	screens_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(screens_root)

	_build_nav()

	toast_column = MenuUI.vbox(12)
	toast_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_column.offset_top = 170
	toast_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(toast_column)

	# Deliberately NOT in `chrome`: particle bursts are decorative, they should
	# be free to cross the whole picture, and MenuScreen.center_of / fly_to both
	# compute their destinations in STAGE space off `stage.global_position`.
	# Reparenting this would silently offset every burst by the safe inset.
	fx = Control.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fx)

	audio = MenuAudio.new()
	add_child(audio)
	if SaveGame.music_on:
		audio.set_music(true)

	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()
	select_brawler(SaveGame.selected_kit.to_lower(), false)

## Half the nav rail: what the fighter, his ring and his hint move right by.
const STAGE_SHIFT := MenuUI.NAV_W * 0.5
const STAGE_BACKDROP := "res://assets/menu/background/stage.jpg"
const RING_SIZE := Vector2(900, 300)

var _backdrop: TextureRect
var _stage_tint: ShaderMaterial
var _glow: TextureRect
var _ring: TextureRect

## The stage is lit in the selected fighter's colour. One painting, recoloured
## by its own light: where the hall is dark it stays the hall's navy, and where
## the floor is lit the light takes the kit colour — so nine fighters get nine
## stages without nine paintings. A kit that names its own `stage` art gets
## that instead, untinted.
const STAGE_TINT_SHADER := """
shader_type canvas_item;
uniform vec3 tint : source_color = vec3(0.34, 0.79, 0.42);
uniform vec3 hall : source_color = vec3(0.10, 0.16, 0.24);
uniform float strength = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// The painting's hall reads about 0.15 in luminance and its lit floor
	// about 0.44; everything between is the light's falloff.
	float k = smoothstep(0.17, 0.42, lum);
	vec3 dark = hall * (lum / 0.15);
	vec3 lit = tint * (lum / 0.44) * 1.08;
	vec3 col = mix(dark, lit, k);
	COLOR = vec4(mix(c.rgb, col, strength), 1.0);
}
"""

## Light the stage for a fighter: the floor, the pool and the rings all take
## the kit colour, lifted a little toward white so a dark team colour still
## reads as light on the floor.
func _light_stage(b: Dictionary) -> void:
	if _backdrop == null:
		return
	var art: String = str(b.get("stage", ""))
	if art != "" and ResourceLoader.exists(art):
		_backdrop.texture = load(art)
		_stage_tint.set_shader_parameter("strength", 0.0)
	else:
		_backdrop.texture = load(STAGE_BACKDROP)
		_stage_tint.set_shader_parameter("strength", 1.0)
	var colour: Color = MenuUI.hex(b.get("color"), MenuUI.GREEN_HI).lerp(Color.WHITE, 0.12)
	_stage_tint.set_shader_parameter("tint", Vector3(colour.r, colour.g, colour.b))
	if _ring:
		_ring.modulate = colour
	if _glow:
		var tex: GradientTexture2D = _glow.texture
		tex.gradient.set_color(0, Color(colour.r, colour.g, colour.b, 0.42))
		tex.gradient.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))

## A soft green pool and two rings where the fighter stands, centred under his
## feet (HomeScreen.FEET_Y). Two 2D textures rather than a lit disc in the 3D
## set: the floor is painted, so the light on it is painted too.
func _build_floor_ring() -> void:
	var glow := TextureRect.new()
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.34, 0.79, 0.42, 0.42))
	g.set_color(1, Color(0.34, 0.79, 0.42, 0.0))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_at_feet(glow, RING_SIZE * Vector2(1.25, 1.25))
	stage.add_child(glow)
	_glow = glow
	var ring := TextureRect.new()
	ring.texture = MenuUI.icon_texture("stage_ring")
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_at_feet(ring, RING_SIZE)
	stage.add_child(ring)
	_ring = ring
	_build_foot_shadow()

## A soft dark ellipse under the fighter. He casts a real shadow in the 3D
## viewport — the sun is set up for it and every mesh has casting on — but
## there is nothing in there to receive it: the floor was taken out when the
## stage became a painting, so the shadow fell through the world and he read
## as pasted onto the picture rather than standing on it. This is drawn under
## him in 2D, between the ring and the viewport, which is the cheap half of a
## contact shadow and the half that does the work.
func _build_foot_shadow() -> void:
	var shadow := TextureRect.new()
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	# A middle stop keeps the core dark instead of fading from the centre out,
	# which reads as a smudge rather than as contact with the ground.
	g.add_point(0.45, Color(0, 0, 0, 0.34))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	shadow.texture = tex
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_at_feet(shadow, Vector2(360, 112))
	stage.add_child(shadow)

## Centred under the feet by PROPORTION of the stage (HomeScreen.FEET_FRAC),
## not by a pixel row: MenuStage frames the fighter to the stage height, so on
## a taller stage his feet move down with it and the ring has to follow.
func _place_at_feet(c: Control, size_px: Vector2) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = HomeScreen.FEET_FRAC
	c.anchor_bottom = HomeScreen.FEET_FRAC
	# STAGE_SHIFT, so the ring, pool and shadow move with the fighter.
	c.offset_left = STAGE_SHIFT - size_px.x / 2.0
	c.offset_right = STAGE_SHIFT + size_px.x / 2.0
	c.offset_top = -size_px.y * 0.56
	c.offset_bottom = c.offset_top + size_px.y

func _build_nav() -> void:
	# A column down the left edge: evenly spaced, and centred as a GROUP rather
	# than spread across the whole height. Stretched to fill, four tabs sat 200
	# px apart and read as four unrelated buttons that happened to share an
	# edge; at 14 px they read as one control.
	nav_bar = MenuUI.vbox(14)
	nav_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_bar.anchor_bottom = 1.0
	nav_bar.offset_left = 0
	nav_bar.offset_right = MenuUI.NAV_W
	nav_bar.offset_top = MenuUI.NAV_TOP
	nav_bar.offset_bottom = -MenuUI.NAV_BOTTOM
	chrome.add_child(nav_bar)
	for entry: Array in NAV_TABS:
		var target: String = str(entry[1])
		var tab: Button = MenuUI.nav_tab(str(entry[0]), str(entry[2]))
		tab.pressed.connect(func() -> void:
			if _active_tab() == target:
				return
			sfx("click")
			pop_all()
			show_screen(target))
		nav_bar.add_child(tab)
		_nav_buttons[target] = tab
	_refresh_nav()

## The topmost real screen's name — popups do not count as a place.
func _active_tab() -> String:
	for i in range(_stack.size() - 1, -1, -1):
		if not _stack[i].is_popup:
			return _stack[i].screen_name
	return ""

func _refresh_nav() -> void:
	if nav_bar == null:
		return
	var active: String = _active_tab()
	for target in _nav_buttons:
		MenuUI.set_nav_active(_nav_buttons[target], str(target) == active)
	# Under a popup the nav is neither reachable nor the point; hide it.
	nav_bar.visible = _stack.is_empty() or not _stack[-1].is_popup

# MARK: stage scaling

## fitStage() from web-menu/src/main.js: keep 1080 stage-pixels of height and
## widen the stage on anything wider than 16:9, so a phone gains stage width
## instead of black bars.
##
## The safe area is honoured by insetting `chrome`, NOT by shrinking the stage,
## and that distinction is the whole of todo 1.2. Fitting the stage itself into
## the safe rect is what the first version did, and on an iPhone 15 it threw
## away 177 device px on each side and 63 at the bottom — 13.9% of the screen —
## which read exactly as "the menu does not reach the edges". It was invisible
## in development because the bars and MenuUI.INK are the same colour, and a
## desktop window has no safe area to inset by. Measured on the device: the
## stage now fills all 2556x1179, and the chrome still gets 2017 stage px of
## width to lay out in, which is more than the 1920 it is authored against.
func _fit_stage() -> void:
	if stage == null:
		return
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var scale_factor: float = minf(view.size.x / STAGE_MIN_W, view.size.y / STAGE_H)
	# The stage COVERS the display: wider than 16:9 (a phone) it gains width,
	# narrower (a 16:10 laptop in fullscreen) it gains height. The first
	# version kept the height at 1080 whatever the display, which on a 16:10
	# screen left the picture a letterboxed band with the chrome — anchored to
	# the display, not the band — sitting in the bars above and below it.
	var stage_w: float = maxf(STAGE_MIN_W, view.size.x / scale_factor)
	var stage_h: float = maxf(STAGE_H, view.size.y / scale_factor)
	stage.scale = Vector2(scale_factor, scale_factor)
	stage.size = Vector2(stage_w, stage_h)
	stage.position = view.position + (view.size - stage.size * scale_factor) / 2.0
	# The safe rect arrives in viewport pixels and `chrome` is a child of the
	# scaled stage, so it is divided back into stage pixels — and offset by the
	# stage's own position, which is non-zero when the display is narrower than
	# 16:9 and the stage really is letterboxed (an iPad).
	var safe: Rect2 = Session.safe_rect(get_viewport())
	chrome.position = (safe.position - stage.position) / scale_factor
	chrome.size = safe.size / scale_factor
	# Device pixels per stage pixel: the 3D view renders at that resolution so
	# the fighter stays sharp on a retina phone rather than being upscaled.
	var window: Vector2i = DisplayServer.window_get_size()
	var density: float = 1.0
	if window.x > 0 and view.size.x > 0:
		density = float(window.x) / view.size.x
	brawler_view.set_render_scale(scale_factor * density)

# MARK: screen stack

func push_screen(screen: MenuScreen) -> MenuScreen:
	screen.menu = self
	# Only the top screen draws: the ones below are opaque enough that leaving
	# them visible reads as two screens printed on top of each other.
	if not _stack.is_empty() and not screen.is_popup:
		_stack[-1].visible = false
	screens_root.add_child(screen)
	_stack.append(screen)
	_update_stage_dim()
	_refresh_nav()
	if not screen.is_popup:
		sfx("open")
	return screen

func pop_screen(screen: MenuScreen) -> void:
	var i: int = _stack.find(screen)
	if i < 0:
		return
	_stack.remove_at(i)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := screen.create_tween()
	tw.set_parallel()
	tw.tween_property(screen, "modulate:a", 0.0, 0.2)
	if not screen.is_popup:
		tw.tween_property(screen, "position:x", 80.0, 0.24)
	else:
		tw.tween_property(screen, "scale", Vector2(0.9, 0.9), 0.2)
	tw.chain().tween_callback(screen.queue_free)
	if not _stack.is_empty():
		_stack[-1].visible = true
	_update_stage_dim()
	_refresh_nav()

func pop_all() -> void:
	for screen in _stack.duplicate():
		pop_screen(screen)

func screen_depth() -> int:
	return _stack.size()

## Every route into a screen goes through here, by name — the home bar, the
## NS3_MENU_SCREEN hook and RoomScreen all use it. Five surfaces and two popups
## is the whole menu; the aliases are the names the old thirteen-screen shell
## used, kept so a stale hook lands somewhere sensible instead of silently
## doing nothing.
func show_screen(name: String) -> void:
	match name:
		"lobby", "home":
			pop_all()
		"roster", "fighters", "brawlers":
			push_screen(RosterScreen.new())
		"brawler", "detail":
			open_brawler(selected_brawler())
		"modes", "events":
			push_screen(ModesScreen.new())
		"shop":
			push_screen(ShopScreen.new())
		"season", "pass":
			push_screen(SeasonScreen.new())
		"road", "trophy-road":
			push_screen(TrophyRoadScreen.new())
		"settings":
			push_screen(SettingsScreen.new())
		"profile":
			MenuPopups.profile(self)
		"wifi", "friends":
			var room := RoomScreen.new()
			room.menu = self
			room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			# Leave the bottom nav its strip; the room draws its own header.
			room.offset_left = MenuUI.NAV_W
			room.offset_bottom = -MenuUI.NAV_H
			var host := MenuScreen.new()
			host.menu = self
			host.screen_name = "wifi"
			push_screen(host)
			host.add_child(room)
			room.refresh()   # the old shell refreshed a screen when it showed it

## One fighter's page. Takes the fighter rather than reading the selection,
## because the roster opens it for a fighter you have not chosen — looking at
## someone and picking them are two different gestures now.
func open_brawler(b: Dictionary) -> void:
	if b.is_empty():
		return
	var screen := BrawlerScreen.new()
	screen.brawler = b
	push_screen(screen)

func _update_stage_dim() -> void:
	# A pushed screen covers the stage completely, so the 3D view is not merely
	# dimmed but stopped: leaving a SubViewport on UPDATE_ALWAYS behind an opaque
	# screen renders the whole set every frame for nobody.
	var dim: bool = not _stack.is_empty()
	brawler_view.visible = not dim
	home.visible = not dim

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _stack.is_empty():
		sfx("back")
		pop_screen(_stack[-1])
		get_viewport().set_input_as_handled()

# MARK: shared chrome

## Sounds that mark something being GRANTED get a haptic to match. Presses
## already tap through MenuUI.press_feedback, so this is only the handful the
## press does not cover — and they land a beat later than the press did, so the
## throttle does not swallow them.
const HAPTIC_SOUNDS := ["reward", "purchase", "found"]

func sfx(sound: String) -> void:
	if audio:
		audio.play(sound)
	if sound in HAPTIC_SOUNDS:
		Haptics.fire("ui_reward")

## The coins / gems readout used by the home bar and every screen top bar: the
## coin or gem from the icon pack and the figure beside it, nothing else. It is
## not a button — the old pills were, and a currency counter that opens the
## shop when you glance at it is a store fixture, not a readout.
func currency_readout() -> HBoxContainer:
	var row := MenuUI.hbox(28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_currency_figure("coins"))
	row.add_child(_currency_figure("gems"))
	return row

## The name the pre-overhaul screens call this by.
func currency_pills() -> HBoxContainer:
	return currency_readout()

func _currency_figure(kind: String) -> Control:
	var pair := MenuUI.hbox(10)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture: TextureRect = MenuUI.pack_icon("gem" if kind == "gems" else "coin", 40)
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(picture)
	var column := MenuUI.vbox(0)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_child(column)
	var value: Label = MenuUI.display(MenuUI.fmt(currency(kind)), 34)
	column.add_child(value)
	column.add_child(MenuUI.label(kind, 18, MenuUI.TEXT_FAINT))
	_currency_labels.append({"label": value, "kind": kind})
	return pair

func currency(kind: String) -> int:
	match kind:
		"gems":
			return SaveGame.gems
		"star_points":
			return SaveGame.star_points
		"trophies":
			return SaveGame.total_trophies()
	return SaveGame.coins

## Re-reads every visible currency pill, counting up to the new value.
##
## Validity is checked BEFORE the typed local: a pill belonging to a screen that
## has since closed is a freed instance, and merely assigning one to a `Label`
## throws. That aborted the whole function on the first stale entry, so the
## counters stopped animating, the list never got pruned, and it threw again on
## every grant for the rest of the session.
func refresh_currencies() -> void:
	var live: Array = []
	for entry in _currency_labels:
		if is_instance_valid(entry.label):
			var label: Label = entry.label
			live.append(entry)
			count_to(label, currency(str(entry.kind)))
	_currency_labels = live
	currency_changed.emit()

## countTo() from ui.js — eases a number up rather than snapping.
func count_to(label: Label, target: int, duration: float = 0.7) -> void:
	var start: int = int(String(label.text).replace(",", "").replace("+", ""))
	if start == target:
		label.text = MenuUI.fmt(target)
		return
	var step := func(v: float) -> void:
		label.text = MenuUI.fmt(int(round(v)))
	var tw := label.create_tween()
	tw.tween_method(step, float(start), float(target), duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# MARK: brawler selection

func selected_brawler() -> Dictionary:
	return MenuData.brawler(SaveGame.selected_kit.to_lower())

func selected_mode() -> Dictionary:
	return MenuData.mode(SaveGame.selected_mode)

func select_brawler(id: String, announce: bool = true) -> void:
	var b: Dictionary = MenuData.brawler(id)
	SaveGame.selected_kit = str(b.kit_name)
	SaveGame.save()
	_light_stage(b)
	brawler_view.show_brawler(b)
	if home:
		home.refresh()
	if announce:
		brawler_changed.emit()

func select_mode(id: String) -> void:
	SaveGame.selected_mode = id
	SaveGame.save()
	if home:
		home.refresh()
	mode_changed.emit()

## PLAY: hands the menu's choices to the match scene.
func start_match() -> void:
	var mode: Dictionary = selected_mode()
	Session.kit = Kits.named(SaveGame.selected_kit)
	Session.mode = MenuData.engine_mode(str(mode.id))
	Loading.to_match(get_tree())

# MARK: toasts, popups, particles

func toast(text: String, icon_name: String = "") -> void:
	var plate: PanelContainer = MenuUI.panel("navy", 14, 5, 16)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := MenuUI.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		row.add_child(MenuUI.icon(icon_name, 36))
	var label: Label = MenuUI.display(text, 30, MenuUI.TEXT, 5)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	plate.add_child(row)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toast_column.add_child(plate)
	plate.modulate.a = 0.0
	var tw := plate.create_tween()
	tw.tween_property(plate, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.0)
	tw.tween_property(plate, "modulate:a", 0.0, 0.3)
	tw.tween_callback(plate.queue_free)

## popup() from ui.js: a centred plate with a title bar and a body the caller
## fills. Returns the popup screen so callers can close it.
func popup(title: String, width: float = 760.0) -> MenuPopup:
	var p := MenuPopup.new()
	p.is_popup = true
	p.title = title
	p.width = width
	push_screen(p)
	return p

## Awaitable yes/no popup. Returns true when the OK button is pressed.
func confirm(title: String, text: String, ok_label: String = "OK",
		ok_variant: String = "yellow", cancel_label: String = "CANCEL") -> bool:
	var p: MenuPopup = popup(title)
	var message: Label = MenuUI.wrap(MenuUI.body(text, 26, MenuUI.TEXT_SOFT))
	p.body_box.add_child(message)
	var row := MenuUI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	p.body_box.add_child(row)
	var result: Array = [false]
	var cancel: Button = MenuUI.button(cancel_label, "grey")
	cancel.pressed.connect(func() -> void:
		sfx("back")
		p.close_screen())
	row.add_child(cancel)
	var ok: Button = MenuUI.button(ok_label, ok_variant)
	ok.pressed.connect(func() -> void:
		result[0] = true
		sfx("click")
		p.close_screen())
	row.add_child(ok)
	await p.tree_exited
	return result[0]

## burst() from ui.js — icons fly up from a stage point under gravity.
func burst(at: Vector2, icon_name: String = "coin", count: int = 14) -> void:
	for i in count:
		var particle: TextureRect = MenuUI.icon(icon_name, 40)
		particle.position = at - Vector2(20, 20)
		fx.add_child(particle)
		var angle: float = -PI / 2.0 + randf_range(-1.1, 1.1)
		var speed: float = randf_range(260.0, 620.0)
		var velocity := Vector2(cos(angle), sin(angle)) * speed
		var spin: float = randf_range(-4.0, 4.0)
		var life: float = randf_range(0.7, 1.1)
		var origin: Vector2 = particle.position
		var step := func(t: float) -> void:
			particle.position = origin + velocity * t + Vector2(0, 450.0 * t * t)
			particle.rotation = spin * t
			var k: float = t / life
			particle.modulate.a = 1.0 - k * k
			particle.scale = Vector2.ONE * (1.0 - k * 0.4)
		var tw := particle.create_tween()
		tw.tween_method(step, 0.0, life, life)
		tw.tween_callback(particle.queue_free)

## flyTo() from ui.js — coins arc from a point into the currency pill.
func fly_to(at: Vector2, kind: String = "coins", count: int = 8) -> void:
	var target: Control = _currency_target(kind)
	if target == null:
		burst(at, "gem" if kind == "gems" else "coin", count)
		return
	var dest: Vector2 = (target.get_global_rect().get_center() - stage.global_position) \
			/ maxf(stage.scale.x, 0.0001) - Vector2(20, 20)
	for i in count:
		var particle: TextureRect = MenuUI.icon("gem" if kind == "gems" else "coin", 40)
		var from: Vector2 = at + Vector2(randf_range(-60, 60), randf_range(-40, 40)) - Vector2(20, 20)
		particle.position = from
		fx.add_child(particle)
		var step := func(t: float) -> void:
			var e: float = t * t * (3.0 - 2.0 * t)
			particle.position = from.lerp(dest, e) - Vector2(0, sin(t * PI) * 120.0)
			particle.scale = Vector2.ONE * (1.0 - t * 0.3)
		var tw := particle.create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_method(step, 0.0, 1.0, 0.52)
		tw.tween_callback(particle.queue_free)
	refresh_currencies()

func _currency_target(kind: String) -> Control:
	var found: Control = null
	for entry in _currency_labels:
		if not is_instance_valid(entry.label):
			continue   # see refresh_currencies: the assignment below would throw
		var label: Label = entry.label
		if str(entry.kind) == kind and label.is_visible_in_tree():
			found = label
	return found

# MARK: debug

## NS3_MENU_SHOT=/path.png screenshots the menu and quits. NS3_MENU_SCREEN
## picks the screen; NS3_MENU_DETAIL=<kit> selects a fighter, which is now what
## "the detail view" means — home's flanks show whoever is selected, so the
## detail view is the lobby with that fighter on it.
func _wire_debug_screenshot() -> void:
	var start: String = OS.get_environment("NS3_MENU_SCREEN")
	var detail: String = OS.get_environment("NS3_MENU_DETAIL")
	var progress: String = OS.get_environment("NS3_MENU_PROGRESS")
	if progress != "":
		_seed_progress(progress)
	if detail != "":
		select_brawler(detail.to_lower(), false)
	if start != "" and start != "lobby" and start != "home":
		show_screen(start)
	# "loading" is not a screen in the stack — it is the transition out of the
	# menu. Pressing PLAY here is what puts it on screen, and it is done whether
	# or not a menu shot was asked for, so that pairing it with NS3_SHOTS
	# instead exercises the whole menu -> loading -> match handoff.
	if start == "loading":
		start_match.call_deferred()
	var shot: String = OS.get_environment("NS3_MENU_SHOT")
	if shot == "":
		return
	# Deliberately inside LoadingScreen.MIN_SHOW, or the match is already up.
	var delay: float = 0.55 if start == "loading" else 2.0
	# NS3_MENU_ATTACK=<seconds before the shot> taps the fighter, so the swing
	# and the shot it fires can be photographed. Without it the only way to see
	# a menu projectile is to be holding the mouse.
	var attack: String = OS.get_environment("NS3_MENU_ATTACK")
	if attack != "" and attack.is_valid_float():
		var lead: float = clampf(attack.to_float(), 0.0, delay)
		get_tree().create_timer(maxf(0.05, delay - lead)).timeout.connect(
				func() -> void: brawler_view.play_attack())
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		var out: String = Session.shot_path(shot)
		# ALWAYS force a draw, not only when the window says it cannot. Another
		# app's window in front leaves window_can_draw() true while the engine
		# still skips frames, and the capture then returns whatever was on
		# screen BEFORE the screen was pushed — which is what made a Season
		# shot come out half-faded and a Modes shot come out as the lobby.
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png(out)
		print("NS3_MENU_SHOT wrote ", ProjectSettings.globalize_path(out))
		get_tree().quit())

## NS3_MENU_PROGRESS=trophies:2000,tier:11,tokens:300,premium:1,claimed:1 seeds
## progress IN MEMORY for a harness run. A fresh save has nothing reached and
## nothing claimed, so a screenshot of Season only ever showed its locked state
## — and the claimed, claimable and current-tier states are most of what that
## screen is. Nothing here writes the save, so the player's own progress on this
## machine is untouched.
func _seed_progress(spec: String) -> void:
	var backfill := false
	for pair in spec.split(",", false):
		var bits: PackedStringArray = pair.split(":")
		if bits.size() < 2:
			continue
		var value: String = bits[1].strip_edges()
		match bits[0].strip_edges():
			"trophies":
				SaveGame.trophies[SaveGame.selected_kit] = int(value)
			"tier":
				SaveGame.pass_tier = int(value)
			"tokens":
				SaveGame.pass_tokens = int(value)
			"premium":
				SaveGame.pass_premium = value != "0"
			"claimed":
				backfill = value != "0"
			"starters":
				# Back to a first-run roster, so the locked tiles and their
				# unlock hints can be shot from a save with developer mode on.
				if value != "0":
					SaveGame.unlocked.clear()
					for id in MenuData.starting_brawlers():
						SaveGame.unlock(str(id))
	if not backfill:
		return
	# Everything already passed counts as banked, so the rails show the three
	# states side by side the way they do on a save with hours on it.
	var total: int = SaveGame.total_trophies()
	for entry in MenuData.trophy_road():
		var goal: int = int(entry.get("trophies", 0))
		if total >= goal:
			SaveGame.claim("road:%d" % goal)
	for tier in MenuData.game.get("passRewards", []):
		var number: int = int(tier.get("tier", 1))
		if number < SaveGame.pass_tier:
			SaveGame.claim("pass:%d:free" % number)
			if SaveGame.pass_premium:
				SaveGame.claim("pass:%d:premium" % number)
