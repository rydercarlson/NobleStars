class_name SettingsScreen
extends MenuScreen
## Settings, as a page rather than a sheet.
##
## *New 7 Sep 2026, from Jackson's notes.* It was a popup, which capped what
## could go on it: a popup is 760 wide with a scrolling body, so every row had
## to be one line with one control on the right, and "music" could only be a
## switch. A switch cannot say **quieter** — that is the actual request, and it
## needs a slider and a mute, which is two controls on one row and does not fit
## a sheet.
##
## Your name moved to the profile, where the rest of your identity is. It was
## here because this was the only screen that existed to put it on.

const ROW_H := 92.0
const CONTROL_W := 460.0

func _build() -> void:
	screen_name = "settings"
	topbar("Settings")
	var column: VBoxContainer = scroll_content(0)

	var audio: Array = MenuUI.block("gear", "AUDIO", "MUTE, OR JUST QUIETER")
	var audio_body: VBoxContainer = audio[1]
	audio_body.add_child(_volume_row("Music", "The menu loop", "music"))
	audio_body.add_child(MenuUI.rule(MenuUI.RULE))
	audio_body.add_child(_volume_row("Sound FX", "Buttons, fighters and rewards", "sfx"))
	column.add_child(audio[0])
	column.add_child(MenuUI.gap(12, true))

	var game: Array = MenuUI.block("power", "GAME", "")
	var game_body: VBoxContainer = game[1]
	game_body.add_child(_switch_row("Hints", "Show tips on the lobby", "hints",
			func(_on: bool) -> void: menu.home.refresh()))
	game_body.add_child(MenuUI.rule(MenuUI.RULE))
	# Shown on desktop too, where it can do nothing: the save goes to the phone
	# with the build, and this is the only place it can be set.
	game_body.add_child(_switch_row("Haptics", "Vibration on a phone", "haptics",
			func(on: bool) -> void:
				if on:
					Haptics.fire("ui_reward")))
	column.add_child(game[0])
	column.add_child(MenuUI.gap(12, true))

	var save: Array = MenuUI.block("shield", "THIS DEVICE", "")
	var save_body: VBoxContainer = save[1]
	save_body.add_child(_developer_row())
	save_body.add_child(MenuUI.rule(MenuUI.RULE))
	# Support sits under developer mode rather than above it: the two are the
	# "something is wrong" pair, and support was stranded up among the switches.
	var help: Button = MenuUI.small_button("HELP", "grey")
	help.custom_minimum_size = Vector2(200, 56)
	help.pressed.connect(func() -> void:
		sfx("click")
		toast("Support: dm the dev", "inbox"))
	save_body.add_child(_row("Support", "Nobles Brawl · Noble Stars menu v1", help))
	save_body.add_child(MenuUI.rule(MenuUI.RULE))
	var reset: Button = MenuUI.small_button("RESET", "red")
	reset.custom_minimum_size = Vector2(200, 56)
	reset.pressed.connect(func() -> void:
		var ok: bool = await menu.confirm("Reset progress?",
				"This deletes your local save and restarts the menu.", "RESET", "red")
		if not ok:
			return
		SaveGame.reset()
		get_tree().reload_current_scene())
	save_body.add_child(_row("Reset progress",
			"Wipes coins, gems, unlocks and settings on this device", reset))
	column.add_child(save[0])
	column.add_child(MenuUI.gap(40, true))

## A slider track: 10px tall, rounded, one flat fill.
func _track(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(5)
	box.set_content_margin(SIDE_TOP, 5)
	box.set_content_margin(SIDE_BOTTOM, 5)
	return box

# MARK: rows

## Name and one line of what it does on the left, the control on the right.
func _row(title: String, sub: String, control: Control) -> Control:
	var row := MenuUI.hbox(20)
	row.custom_minimum_size = Vector2(0, ROW_H)
	var text := MenuUI.vbox(2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(MenuUI.display(title.to_upper(), 36))
	text.add_child(MenuUI.label(sub, 26, MenuUI.TEXT_DIM))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row

## A slider with its own mute beside it. Muting leaves the slider where it is,
## so unmuting comes back to the level you chose rather than to full.
func _volume_row(title: String, sub: String, key: String) -> Control:
	var group := MenuUI.hbox(18)
	group.custom_minimum_size = Vector2(CONTROL_W, 0)
	group.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = SaveGame.music_volume if key == "music" else SaveGame.sfx_volume
	slider.custom_minimum_size = Vector2(300, 44)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# An HSlider's track takes its THICKNESS from the stylebox's content margins,
	# so a box with margin 0 draws a hairline you cannot see. These are the same
	# 10px track and gold fill MenuUI.bar uses, by hand, because a Panel is not
	# a stylebox and the two cannot share.
	slider.add_theme_stylebox_override("slider", _track(MenuUI.RULE))
	slider.add_theme_stylebox_override("grabber_area", _track(MenuUI.GOLD))
	slider.add_theme_stylebox_override("grabber_area_highlight", _track(MenuUI.GOLD_HI))
	var knob := StyleBoxFlat.new()
	knob.bg_color = MenuUI.TEXT
	knob.set_corner_radius_all(14)
	knob.set_content_margin_all(14)
	knob.set_border_width_all(3)
	knob.border_color = MenuUI.INK
	slider.add_theme_stylebox_override("grabber", knob)
	slider.add_theme_stylebox_override("grabber_highlight", knob)

	var readout: Label = MenuUI.display("%d%%" % int(slider.value * 100.0), 32, MenuUI.GOLD)
	readout.custom_minimum_size = Vector2(84, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var mute: Button = MenuPopups.setting_toggle(key, func(on: bool) -> void:
		if key == "music":
			menu.audio.set_music(on)
		elif on:
			menu.sfx("click"))
	mute.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	slider.value_changed.connect(func(value: float) -> void:
		if key == "music":
			SaveGame.music_volume = value
			menu.audio.apply_volumes()
		else:
			SaveGame.sfx_volume = value
		readout.text = "%d%%" % int(value * 100.0)
		SaveGame.save())
	# One click of the SFX slider is worth hearing at the new level.
	if key == "sfx":
		slider.drag_ended.connect(func(changed: bool) -> void:
			if changed:
				menu.sfx("click"))
	group.add_child(slider)
	group.add_child(readout)
	group.add_child(mute)
	return _row(title, sub, group)

func _switch_row(title: String, sub: String, key: String, on_change: Callable) -> Control:
	return _row(title, sub, MenuPopups.setting_toggle(key, on_change))

func _developer_row() -> Control:
	var button: Button = MenuUI.small_button(
			"UNLOCKED" if SaveGame.all_brawlers_unlocked() else "UNLOCK ALL", "blue")
	button.custom_minimum_size = Vector2(200, 56)
	button.disabled = SaveGame.all_brawlers_unlocked()
	if button.disabled:
		button.modulate = Color(0.7, 0.7, 0.7)
	button.pressed.connect(func() -> void:
		SaveGame.unlock_all_brawlers()
		button.text = "UNLOCKED"
		button.disabled = true
		button.modulate = Color(0.7, 0.7, 0.7)
		sfx("reward")
		menu.brawler_changed.emit()
		toast("Developer mode: all brawlers unlocked", "brawlers"))
	return _row("Developer mode", "Unlock every brawler on this save", button)
