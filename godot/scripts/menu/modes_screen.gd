class_name ModesScreen
extends MenuScreen
## Choose Event — web-menu/src/screens/play.js. Every mode from data/game.json
## with its Nobles-themed map; tapping one opens the detail card and SELECT
## puts it on the home plate. Only Showdown launches today, and a mode that
## isn't built says so rather than pretending.

func _build() -> void:
	screen_name = "modes"
	topbar("Choose Event")
	var column: VBoxContainer = scroll_content()
	var grid: GridContainer = MenuUI.grid(4)
	column.add_child(grid)
	for mode in MenuData.modes():
		grid.add_child(_mode_card(mode))
	stagger_children(grid)

func _mode_card(mode: Dictionary) -> Button:
	var color: Color = MenuUI.hex(mode.get("color"), MenuUI.GREEN)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 250)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	for state in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, MenuUI.plate_box("card", 18, 7, 0))
	MenuUI.press_feedback(card)
	card.pressed.connect(func() -> void:
		sfx("click")
		_open_detail(mode))

	var tint := ColorRect.new()
	tint.color = Color(color.r, color.g, color.b, 0.45)
	tint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tint.anchor_bottom = 0.55
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tint)

	var column := MenuUI.vbox(4)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 20
	column.offset_right = -20
	column.offset_top = 20
	column.offset_bottom = -27
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	column.add_child(MenuUI.icon(str(mode.get("icon", "bulldog")), 96))
	column.add_child(MenuUI.spacer())
	column.add_child(MenuUI.display(str(mode.name), 40, MenuUI.TEXT, 6))
	column.add_child(MenuUI.body("%s · %s" % [str(mode.sub), str(mode.players)], 22, MenuUI.TEXT))
	column.add_child(MenuUI.body(str(mode.map), 20, MenuUI.TEXT_DIM))
	if not MenuData.mode_playable(str(mode.id)):
		var soon: PanelContainer = MenuUI.chip("IN DEVELOPMENT", "", 18, MenuUI.TEXT_DIM)
		MenuUI.pin(soon, true, false, 12)
		card.add_child(soon)
	if str(mode.id) == SaveGame.selected_mode:
		var outline := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.set_border_width_all(5)
		style.border_color = MenuUI.YELLOW
		style.set_corner_radius_all(18)
		outline.add_theme_stylebox_override("panel", style)
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outline.offset_bottom = -7
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(outline)
	return card

func _open_detail(mode: Dictionary) -> void:
	var color: Color = MenuUI.hex(mode.get("color"), MenuUI.GREEN)
	var popup: MenuPopup = menu.popup("%s · %s" % [str(mode.name), str(mode.sub)], 1100)
	var row := MenuUI.hbox(30)
	popup.body_box.add_child(row)

	var map: PanelContainer = MenuUI.panel("card", 18, 7, 0)
	map.custom_minimum_size = Vector2(460, 380)
	map.clip_contents = true
	row.add_child(map)
	var backdrop: Control = MenuUI.card_backdrop(color)
	map.add_child(backdrop)
	var map_column := MenuUI.vbox(10)
	map_column.alignment = BoxContainer.ALIGNMENT_CENTER
	map.add_child(map_column)
	var icon_holder := CenterContainer.new()
	var mode_icon: TextureRect = MenuUI.icon(str(mode.get("icon", "bulldog")), 150)
	icon_holder.add_child(mode_icon)
	map_column.add_child(icon_holder)
	var map_name: Label = MenuUI.display(str(mode.map), 44)
	map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_column.add_child(map_name)
	var bob := mode_icon.create_tween().set_loops()
	bob.tween_property(mode_icon, "position:y", -14.0, 1.2).set_trans(Tween.TRANS_SINE)
	bob.tween_property(mode_icon, "position:y", 0.0, 1.2).set_trans(Tween.TRANS_SINE)

	var info := MenuUI.vbox(16)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(MenuUI.display(str(mode.name), 60))
	info.add_child(MenuUI.display(str(mode.map), 34, MenuUI.YELLOW_HI, 5))
	info.add_child(MenuUI.body("%s · %s" % [str(mode.sub), str(mode.players)], 24, MenuUI.TEXT_DIM))
	info.add_child(MenuUI.wrap(MenuUI.body(str(mode.text), 24, MenuUI.TEXT_SOFT)))
	if not MenuData.mode_playable(str(mode.id)):
		info.add_child(MenuUI.wrap(MenuUI.body(
				"This mode isn't built yet — selecting it keeps it on your home plate, "
				+ "but PLAY still drops you into Showdown.", 21, MenuUI.YELLOW_HI)))
	info.add_child(MenuUI.spacer())
	var actions := MenuUI.hbox(14)
	info.add_child(actions)
	var back: Button = MenuUI.button("BACK", "grey")
	back.pressed.connect(popup.close_screen)
	actions.add_child(back)
	var select: Button = MenuUI.button("SELECT", "yellow", 44)
	select.custom_minimum_size = Vector2(0, 96)
	select.pressed.connect(func() -> void:
		menu.select_mode(str(mode.id))
		sfx("reward")
		popup.close_screen()
		close_screen()
		menu.toast("%s %s selected" % [str(mode.name), str(mode.sub)],
				str(mode.get("icon", "bulldog"))))
	actions.add_child(select)
