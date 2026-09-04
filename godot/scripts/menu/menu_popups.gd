class_name MenuPopups
## Settings and Profile — web-menu/src/screens/settings.js. Both are popups
## rather than screens, so the auditorium stays visible behind them.

## Music / SFX / hints toggles, name change, support and reset.
static func settings(shell: MenuShell) -> MenuPopup:
	var popup: MenuPopup = shell.popup("Settings")
	popup.setting_row("Music", "Menu music", _toggle("music",
			func(on: bool) -> void: shell.audio.set_music(on)))
	popup.setting_row("Sound FX", "Button and brawler sounds",
			_toggle("sfx", func(_on: bool) -> void: shell.sfx("click")))
	popup.setting_row("Hints", "Show tips on the home screen",
			_toggle("hints", func(_on: bool) -> void: shell.home.refresh()))

	var change: Button = MenuUI.small_button("CHANGE", "blue")
	change.pressed.connect(func() -> void:
		popup.close_screen()
		profile(shell))
	popup.setting_row("Player name", "Shown on your profile and in the club", change)

	var help: Button = MenuUI.small_button("HELP", "grey")
	help.pressed.connect(func() -> void:
		shell.toast("Support: dm the dev", "inbox"))
	popup.setting_row("Support", "Nobles Brawl · Noble Stars menu v1", help)

	var unlock_all: Button = MenuUI.small_button(
			"UNLOCKED" if SaveGame.all_brawlers_unlocked() else "UNLOCK ALL", "blue")
	unlock_all.disabled = SaveGame.all_brawlers_unlocked()
	if unlock_all.disabled:
		unlock_all.modulate = Color(0.7, 0.7, 0.7)
	unlock_all.pressed.connect(func() -> void:
		SaveGame.unlock_all_brawlers()
		unlock_all.text = "UNLOCKED"
		unlock_all.disabled = true
		unlock_all.modulate = Color(0.7, 0.7, 0.7)
		shell.sfx("reward")
		shell.brawler_changed.emit()
		shell.toast("Developer mode: all brawlers unlocked", "brawlers"))
	popup.setting_row("Developer mode", "Unlock every brawler on this save", unlock_all)

	var reset: Button = MenuUI.small_button("RESET", "red")
	reset.pressed.connect(func() -> void:
		var ok: bool = await shell.confirm("Reset progress?",
				"This deletes your local save and restarts the menu.", "RESET", "red")
		if not ok:
			return
		SaveGame.reset()
		shell.get_tree().reload_current_scene())
	popup.setting_row("Reset progress",
			"Wipes coins, gems, unlocks and settings on this device", reset)
	return popup

## The pill toggle from the CSS, bound to one of the save's settings flags. It
## needs no MenuShell of its own: each caller's `on_change` closes over the one
## it already has.
static func _toggle(key: String, on_change: Callable) -> Button:
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
	var box: StyleBoxTexture = MenuUI.plate_box("green" if on else "grey", 29, 4, 8)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, box)

static func _setting(key: String) -> bool:
	match key:
		"music":
			return SaveGame.music_on
		"sfx":
			return SaveGame.sfx_on
	return SaveGame.hints_on

static func _set_setting(key: String, value: bool) -> void:
	match key:
		"music":
			SaveGame.music_on = value
		"sfx":
			SaveGame.sfx_on = value
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
	var club: Dictionary = MenuData.game.get("club", {})
	lines.add_child(MenuUI.body("#NOBLES%03d · Level %d · Club: %s"
			% [SaveGame.level, SaveGame.level, str(club.get("name", "—"))],
			22, MenuUI.TEXT_DIM))

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
