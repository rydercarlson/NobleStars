class_name MenuShell
extends Control
## The Nobles Brawl menu.
##
## Layout is authored in "stage pixels": a 1920x1080 stage that is scaled to the
## device and widened (never letterboxed sideways) on taller phones, so a phone
## gains stage width instead of black bars.
##
## The stage is one live 3D view of the selected fighter with flat 2D chrome
## over it. There is no background image: MenuStage draws the arena's own ground
## and takes it out to ink, which is why the framing constants that used to line
## the 3D fighter's feet up with a painted floor (FLOOR_FRAC, BRAWLER_VIEW,
## _place_brawler) are gone.

const STAGE_H := 1080.0
const STAGE_MIN_W := 1920.0

signal currency_changed
signal brawler_changed
signal mode_changed
signal profile_changed

var stage: Control
var bg: ColorRect
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
	Loading.done()   # lifts the loading screen if we got here from a match

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

	brawler_view = MenuStage.new()
	brawler_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
		"modes", "events":
			push_screen(ModesScreen.new())
		"shop":
			push_screen(ShopScreen.new())
		"season", "pass", "road", "trophy-road":
			push_screen(SeasonScreen.new())
		"settings":
			MenuPopups.settings(self)
		"profile":
			MenuPopups.profile(self)
		"wifi", "friends":
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

func sfx(sound: String) -> void:
	if audio:
		audio.play(sound)

## The coins / gems readout used by the home bar and every screen top bar: a
## figure with its name under it, right-aligned so the two columns line up. It
## is not a button — the old pills were, and a currency counter that opens the
## shop when you glance at it is a store fixture, not a readout.
func currency_readout() -> HBoxContainer:
	var row := MenuUI.hbox(34)
	row.add_child(_currency_figure("coins"))
	row.add_child(_currency_figure("gems"))
	return row

## The name the pre-overhaul screens call this by.
func currency_pills() -> HBoxContainer:
	return currency_readout()

func _currency_figure(kind: String) -> Control:
	var column := MenuUI.vbox(0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value: Label = MenuUI.display(MenuUI.fmt(currency(kind)), 34)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(value)
	var name_label: Label = MenuUI.label(kind, 17, MenuUI.TEXT_FAINT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(name_label)
	_currency_labels.append({"label": value, "kind": kind})
	return column

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
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		var out: String = Session.shot_path(shot)
		get_viewport().get_texture().get_image().save_png(out)
		print("NS3_MENU_SHOT wrote ", ProjectSettings.globalize_path(out))
		get_tree().quit())
