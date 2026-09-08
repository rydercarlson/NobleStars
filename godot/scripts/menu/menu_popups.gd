class_name MenuPopups
## Settings and Profile — web-menu/src/screens/settings.js. Both are popups
## rather than screens, so the auditorium stays visible behind them.

## What the three bars in the top-right corner open. It used to open Settings
## directly, which is why a control shaped like a menu felt broken: a hamburger
## that is a single destination is a button wearing a menu's clothes. These are
## the places the bottom nav does not go.
static func main_menu(shell: MenuShell) -> MenuPopup:
	var popup: MenuPopup = shell.popup("Menu", 620)
	var column := MenuUI.vbox(10)
	popup.body_box.add_child(column)
	column.add_child(_destination(shell, popup, "avatar", "PROFILE",
			"Your name, trophies and matches", func() -> void: profile(shell)))
	column.add_child(_destination(shell, popup, "bulldog", "EVENTS",
			"Pick the mode you play", func() -> void: shell.show_screen("modes")))
	column.add_child(_destination(shell, popup, "gear", "SETTINGS",
			"Sound, hints and this device's save",
			func() -> void: shell.show_screen("settings")))
	return popup

## One row of that menu: a glyph, a name over a line of what it is, a chevron.
static func _destination(shell: MenuShell, popup: MenuPopup, icon_name: String,
		name_text: String, sub: String, action: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 104)
	for state in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, MenuUI.flat_box(MenuUI.INK, MenuUI.RULE, 0))
	b.add_theme_stylebox_override("hover", MenuUI.flat_box(MenuUI.PANEL_HI, MenuUI.GOLD, 0))
	b.add_theme_stylebox_override("pressed", MenuUI.flat_box(MenuUI.INK, MenuUI.GOLD, 0))
	MenuUI.press_feedback(b)
	b.pressed.connect(func() -> void:
		shell.sfx("click")
		popup.close_screen()
		action.call())
	var row := MenuUI.hbox(18)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20
	row.offset_right = -20
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var glyph: TextureRect = MenuUI.pack_icon(icon_name, 44)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	var text := MenuUI.vbox(0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(MenuUI.display(name_text, 38))
	text.add_child(MenuUI.label(sub, 22, MenuUI.TEXT_DIM))
	var chevron: Label = MenuUI.display("›", 44, MenuUI.TEXT_SOFT)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)
	return b

## The pill toggle from the CSS, bound to one of the save's settings flags. It
## needs no MenuShell of its own: each caller's `on_change` closes over the one
## it already has.
## Your record, on your own page. Matches used to sit under your name on the
## lobby, where it was the one number there you could do nothing with; this is
## the screen it belongs on, next to the rest of what you have done.
static func _profile_stats() -> Control:
	var owned: int = 0
	var best_name: String = "—"
	var best: int = -1
	for b in MenuData.brawlers:
		var id: String = str(b.get("id", ""))
		if not SaveGame.is_unlocked(id):
			continue
		owned += 1
		var t: int = SaveGame.brawler_trophies(id)
		if t > best:
			best = t
			best_name = str(b.get("name", "")).to_upper()
	var grid: GridContainer = MenuUI.grid(4, 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: Array in [
			["TROPHIES", MenuUI.fmt(SaveGame.total_trophies()), MenuUI.GOLD],
			["MATCHES", MenuUI.fmt(SaveGame.matches), MenuUI.TEXT],
			["FIGHTERS", "%d / %d" % [owned, MenuData.brawlers.size()], MenuUI.TEXT],
			["BEST", best_name, MenuUI.TEXT]]:
		var cell := MenuUI.vbox(0)
		cell.add_child(MenuUI.display(str(row[1]), 38, row[2]))
		cell.add_child(MenuUI.label(str(row[0]), 22, MenuUI.TEXT_FAINT))
		grid.add_child(cell)
	return grid

static func setting_toggle(key: String, on_change: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(124, 58)
	button.toggle_mode = true
	button.button_pressed = _setting(key)
	_style_toggle(button)
	MenuUI.press_feedback(button)
	button.toggled.connect(func(pressed: bool) -> void:
		_set_setting(key, pressed)
		SaveGame.save()
		_style_toggle(button)
		on_change.call(pressed))
	return button

static func _style_toggle(button: Button) -> void:
	var on: bool = button.button_pressed
	button.text = "ON" if on else "OFF"
	button.add_theme_font_override("font", MenuUI.display_font())
	button.add_theme_font_size_override("font_size", 22)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, MenuUI.TEXT)
	var box: StyleBoxFlat = MenuUI.plate_box("green" if on else "grey", 29, 4, 8)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, box)

static func _setting(key: String) -> bool:
	match key:
		"music":
			return SaveGame.music_on
		"sfx":
			return SaveGame.sfx_on
		"haptics":
			return SaveGame.haptics_on
	return SaveGame.hints_on

static func _set_setting(key: String, value: bool) -> void:
	match key:
		"music":
			SaveGame.music_on = value
		"sfx":
			SaveGame.sfx_on = value
		"haptics":
			SaveGame.haptics_on = value
		_:
			SaveGame.hints_on = value

## Player card, rename box and lifetime stats.
static func profile(shell: MenuShell) -> MenuPopup:
	var popup: MenuPopup = shell.popup("Profile", 860)
	var brawler: Dictionary = shell.selected_brawler()
	var head := MenuUI.hbox(22)
	popup.body_box.add_child(head)
	var frame := Panel.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = MenuUI.INK
	frame_style.set_corner_radius_all(20)
	frame_style.set_border_width_all(3)
	frame_style.border_color = MenuUI.LINE
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.custom_minimum_size = Vector2(140, 140)
	frame.clip_contents = true
	var portrait := TextureRect.new()
	portrait.texture = MenuData.portrait(str(brawler.get("id", "")))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_top = 10
	frame.add_child(portrait)
	head.add_child(frame)
	var lines := MenuUI.vbox(6)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lines)
	lines.add_child(MenuUI.display(SaveGame.player_name, 52))
	lines.add_child(MenuUI.label("#NOBLES%03d  ·  LEVEL %d" % [SaveGame.level,
			SaveGame.level], 26, MenuUI.TEXT_DIM))
	lines.add_child(MenuUI.gap(4, true))
	lines.add_child(_profile_stats())

	popup.body_box.add_child(MenuUI.display("CHANGE NAME", 26, MenuUI.TEXT, 4))
	var name_row := MenuUI.hbox(12)
	popup.body_box.add_child(name_row)
	var input := LineEdit.new()
	input.text = SaveGame.player_name
	input.max_length = 14
	input.placeholder_text = "Player name"
	input.custom_minimum_size = Vector2(0, 66)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_override("font", MenuUI.body_font())
	input.add_theme_font_size_override("font_size", 26)
	name_row.add_child(input)
	var save_button: Button = MenuUI.button("SAVE", "green")
	save_button.pressed.connect(func() -> void:
		var value: String = input.text.strip_edges()
		if value.length() < 2:
			shell.sfx("error")
			shell.toast("Name must be at least 2 characters")
			return
		SaveGame.player_name = value.to_upper()
		SaveGame.save()
		shell.home.refresh()
		shell.profile_changed.emit()
		shell.sfx("reward")
		shell.toast("Name updated!", "check")
		popup.close_screen())
	name_row.add_child(save_button)

	popup.body_box.add_child(MenuUI.display("STATS", 26, MenuUI.TEXT, 4))
	var stats: GridContainer = MenuUI.grid(3, 14)
	popup.body_box.add_child(stats)
	var unlocked: int = 0
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.id)):
			unlocked += 1
	stats.add_child(_stat("Trophies", MenuUI.fmt(SaveGame.total_trophies()), "trophy"))
	stats.add_child(_stat("Coins", MenuUI.fmt(SaveGame.coins), "coin"))
	stats.add_child(_stat("Brawlers", "%d/%d" % [unlocked, MenuData.brawlers.size()], "brawlers"))
	stats.add_child(_stat("Matches", MenuUI.fmt(SaveGame.matches), ""))
	stats.add_child(_stat("Pass tier", str(SaveGame.pass_tier), "token"))
	stats.add_child(_stat("Star points", MenuUI.fmt(SaveGame.star_points), "star_drop"))
	return popup

static func _stat(key: String, value: String, icon_name: String) -> PanelContainer:
	var p: PanelContainer = MenuUI.dark_panel(14, 0.35, 16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := MenuUI.vbox(4)
	p.add_child(column)
	column.add_child(MenuUI.body(key.to_upper(), 18, MenuUI.TEXT_DIM))
	var row := MenuUI.hbox(8)
	if icon_name != "":
		row.add_child(MenuUI.icon(icon_name, 32))
	row.add_child(MenuUI.display(value, 36))
	column.add_child(row)
	return p
