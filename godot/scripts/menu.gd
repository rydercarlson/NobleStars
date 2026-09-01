class_name MenuShell
extends Control
## The Nobles Brawl menu — the web menu (web-menu/) rebuilt natively so it
## ships inside the iOS app. Same assets, same data files, same screens.
##
## Layout is authored in the web build's "stage pixels": a 1920x1080 stage that
## is scaled to the device and widened (never letterboxed sideways) on taller
## phones, exactly like fitStage() in web-menu/src/main.js. Children therefore
## use the same coordinates the CSS does.

const STAGE_H := 1080.0
const STAGE_MIN_W := 1920.0
## Where the auditorium art's stage floor sits in the background image.
const FLOOR_FRAC := 0.715
const BRAWLER_VIEW := Vector2(900, 760)

signal currency_changed
signal brawler_changed
signal mode_changed
signal profile_changed

static var _stripes: ImageTexture

var stage: Control
var bg: TextureRect
var brawler_view: MenuStage
var home: HomeScreen
var screens_root: Control
var toast_column: VBoxContainer
var fx: Control
var audio: MenuAudio

var _stack: Array[MenuScreen] = []
var _currency_labels: Array = []   # [{label, kind}]

func _ready() -> void:
	SaveGame.ensure_loaded()
	MenuData.ensure_loaded()
	if _handle_debug_hooks():
		return
	_build_stage()
	_wire_debug_screenshot()

## Debug hooks that skip the menu entirely. Returns true if one took over.
func _handle_debug_hooks() -> bool:
	if OS.get_environment("NS3_HOST") != "":
		var want := int(OS.get_environment("NS3_HOST"))
		Net.host_game(SaveGame.player_name, SaveGame.selected_kit)
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
	letterbox.color = Color("#05070f")
	letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letterbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(letterbox)

	stage = Control.new()
	stage.clip_contents = true
	add_child(stage)

	bg = TextureRect.new()
	bg.texture = load("res://assets/menu/bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bg)

	brawler_view = MenuStage.new()
	stage.add_child(brawler_view)

	home = HomeScreen.new()
	home.menu = self
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(home)

	screens_root = Control.new()
	screens_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(screens_root)

	toast_column = MenuUI.vbox(12)
	toast_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_column.offset_top = 170
	toast_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(toast_column)

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

# MARK: stage scaling

## fitStage() from web-menu/src/main.js: keep 1080 stage-pixels of height and
## widen the stage on anything wider than 16:9, so a phone gains stage width
## instead of black bars. The device's safe area is honoured on iPhone.
func _fit_stage() -> void:
	if stage == null:
		return
	var view: Rect2 = _safe_rect()
	var scale_factor: float = minf(view.size.x / STAGE_MIN_W, view.size.y / STAGE_H)
	var stage_w: float = maxf(STAGE_MIN_W, view.size.x / scale_factor)
	stage.scale = Vector2(scale_factor, scale_factor)
	stage.size = Vector2(stage_w, STAGE_H)
	stage.position = view.position + (view.size - stage.size * scale_factor) / 2.0
	# Device pixels per stage pixel: the 3D view renders at that resolution so
	# the fighter stays sharp on a retina phone rather than being upscaled.
	var window: Vector2i = DisplayServer.window_get_size()
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var density: float = 1.0
	if window.x > 0 and visible.x > 0:
		density = float(window.x) / visible.x
	brawler_view.set_render_scale(scale_factor * density)
	_place_brawler()

## The viewport rect, inset by the device's safe area (notch / home indicator).
## Desktop reports the whole display here, so the inset is mobile-only.
func _safe_rect() -> Rect2:
	var visible: Vector2 = get_viewport().get_visible_rect().size
	if not OS.has_feature("mobile"):
		return Rect2(Vector2.ZERO, visible)
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var window: Vector2i = DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0:
		return Rect2(Vector2.ZERO, visible)
	var k := Vector2(visible.x / float(window.x), visible.y / float(window.y))
	var full := Rect2(Vector2.ZERO, visible)
	var rect: Rect2 = full.intersection(Rect2(Vector2(safe.position) * k,
			Vector2(safe.size) * k))
	# Some platforms report the whole display rather than the window's safe
	# area; anything that implausibly small is ignored.
	if rect.size.x < visible.x * 0.5 or rect.size.y < visible.y * 0.5:
		return full
	return rect

## Place the 3D view so the fighter's feet land on the auditorium's stage
## floor — positionBrawler() in the web build, same numbers.
func _place_brawler() -> void:
	if brawler_view == null:
		return
	var w: float = stage.size.x
	var bg_aspect := STAGE_MIN_W / STAGE_H
	var bw: float
	var bh: float
	var bx: float
	var by: float
	if w / STAGE_H > bg_aspect:
		bw = w
		bh = w / bg_aspect
		bx = 0.0
		by = (STAGE_H - bh) / 2.0
	else:
		bh = STAGE_H
		bw = STAGE_H * bg_aspect
		bx = (w - bw) / 2.0
		by = 0.0
	var floor_y: float = by + bh * FLOOR_FRAC
	brawler_view.size = BRAWLER_VIEW
	brawler_view.position = Vector2(bx + bw * 0.5 - BRAWLER_VIEW.x / 2.0,
			floor_y - brawler_view.foot_fraction() * BRAWLER_VIEW.y)
	if home:
		home.floor_y = floor_y

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

func pop_all() -> void:
	for screen in _stack.duplicate():
		pop_screen(screen)

func screen_depth() -> int:
	return _stack.size()

## Compatibility with the pre-rebuild shell (RoomScreen still calls this).
func show_screen(name: String) -> void:
	match name:
		"lobby", "home":
			pop_all()
		"fighters", "brawlers":
			push_screen(BrawlersScreen.new())
		"modes":
			push_screen(ModesScreen.new())
		"shop":
			push_screen(ShopScreen.new())
		"pass":
			push_screen(PassScreen.new())
		"road", "trophy-road":
			push_screen(TrophyRoadScreen.new())
		"news":
			push_screen(NewsScreen.new())
		"friends":
			push_screen(FriendsScreen.new())
		"club":
			push_screen(ClubScreen.new())
		"inbox":
			push_screen(InboxScreen.new())
		"matchmaking", "play":
			push_screen(MatchmakingScreen.new())
		"settings":
			MenuPopups.settings(self)
		"profile":
			MenuPopups.profile(self)
		"wifi":
			var room := RoomScreen.new()
			room.menu = self
			room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var host := MenuScreen.new()
			host.menu = self
			host.screen_name = "wifi"
			push_screen(host)
			host.add_child(room)
			room.refresh()   # the old shell refreshed a screen when it showed it

func _update_stage_dim() -> void:
	var dim: bool = not _stack.is_empty()
	bg.modulate = Color(0.34, 0.34, 0.4) if dim else Color.WHITE
	brawler_view.visible = not dim
	home.visible = not dim

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _stack.is_empty():
		sfx("back")
		pop_screen(_stack[-1])
		get_viewport().set_input_as_handled()

# MARK: shared chrome

func sfx(sound: String) -> void:
	if audio:
		audio.play(sound)

## The coins / gems pills used by the home HUD and every screen top bar.
func currency_pills() -> HBoxContainer:
	var row := MenuUI.hbox(12)
	row.add_child(_currency_pill("coins", "coin"))
	row.add_child(_currency_pill("gems", "gem"))
	return row

func _currency_pill(kind: String, icon_name: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(176, 62)
	b.add_theme_stylebox_override("normal", MenuUI.plate_box("navy", 31, 5, 10))
	for state in ["hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, MenuUI.plate_box("navy", 31, 5, 10))
	MenuUI.press_feedback(b)
	b.pressed.connect(func() -> void:
		sfx("click")
		push_screen(ShopScreen.new()))
	var row := MenuUI.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -12
	row.offset_bottom = -5
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(MenuUI.icon(icon_name, 40))
	var value: Label = MenuUI.display(MenuUI.fmt(currency(kind)), 30, MenuUI.TEXT, 0)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	row.add_child(MenuUI.spacer())
	var plus := PanelContainer.new()
	var plus_style := StyleBoxFlat.new()
	plus_style.bg_color = MenuUI.GREEN
	plus_style.set_corner_radius_all(17)
	plus_style.set_border_width_all(3)
	plus_style.border_color = MenuUI.LINE
	plus_style.set_content_margin_all(2)
	plus.add_theme_stylebox_override("panel", plus_style)
	plus.custom_minimum_size = Vector2(34, 34)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var plus_label: Label = MenuUI.display("+", 26, MenuUI.TEXT, 0)
	plus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_child(plus_label)
	row.add_child(plus)
	_currency_labels.append({"label": value, "kind": kind})
	return b

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
func refresh_currencies() -> void:
	var live: Array = []
	for entry in _currency_labels:
		var label: Label = entry.label
		if is_instance_valid(label):
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
	brawler_view.show_brawler(b)
	_place_brawler()
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
	get_tree().change_scene_to_file("res://game.tscn")

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
		var label: Label = entry.label
		if is_instance_valid(label) and str(entry.kind) == kind and label.is_visible_in_tree():
			found = label
	return found

# MARK: debug

## NS3_MENU_SHOT=/path.png screenshots the menu and quits. NS3_MENU_SCREEN
## picks the screen and NS3_MENU_DETAIL=<kit> opens a brawler's detail view.
func _wire_debug_screenshot() -> void:
	var start: String = OS.get_environment("NS3_MENU_SCREEN")
	var detail: String = OS.get_environment("NS3_MENU_DETAIL")
	if start != "" and start != "lobby" and start != "home":
		show_screen(start)
	if detail != "" and not _stack.is_empty() and _stack[-1] is BrawlersScreen:
		(_stack[-1] as BrawlersScreen).open_detail(MenuData.brawler(detail))
	var shot: String = OS.get_environment("NS3_MENU_SHOT")
	if shot == "":
		return
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit())

## The faint diagonal weave the CSS lays over every screen backdrop.
static func stripes_texture() -> ImageTexture:
	if _stripes != null:
		return _stripes
	var size := 44
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var on: bool = ((x + y) % size) < size / 2
			img.set_pixel(x, y, Color(1, 1, 1, 0.035) if on else Color(0, 0, 0, 0))
	_stripes = ImageTexture.create_from_image(img)
	return _stripes
