class_name ModesScreen
extends MenuScreen
## Choose an event.
##
## Two modes are built. Five are not, and the old screen gave all seven the same
## sized card with an IN DEVELOPMENT flash on five of them — which made the
## screen mostly a list of things you cannot do, and made the two you can do
## hard to find in it. So the built ones are large and the rest are one dim line
## each under a heading that says what they are.

func _build() -> void:
	screen_name = "modes"
	topbar("Events")
	var column: VBoxContainer = fill_content(0)

	var playable: Array = []
	var planned: Array = []
	for mode in MenuData.modes():
		if MenuData.mode_playable(str(mode.id)):
			playable.append(mode)
		else:
			planned.append(mode)

	var row := MenuUI.hbox(30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for mode: Dictionary in playable:
		row.add_child(_mode_card(mode))
	stagger_children(row, 0.05)

	if not planned.is_empty():
		column.add_child(MenuUI.gap(40, true))
		column.add_child(MenuUI.section("PLANNED   ·   NOT BUILT YET"))
		column.add_child(MenuUI.gap(10, true))
		for mode: Dictionary in planned:
			column.add_child(_planned_row(mode))
			column.add_child(MenuUI.rule())
	column.add_child(MenuUI.gap(24, true))

func _mode_card(mode: Dictionary) -> Control:
	var color: Color = MenuUI.hex(mode.get("color"), MenuUI.GREEN)
	var selected: bool = str(mode.id) == SaveGame.selected_mode

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
			MenuUI.flat_box(MenuUI.PANEL, MenuUI.GOLD if selected else MenuUI.RULE, 0))
	var body_column := MenuUI.vbox(0)
	card.add_child(body_column)

	# The mode's colour as a solid band across the top — the one place it
	# appears, so two cards side by side are told apart by it.
	var band := ColorRect.new()
	band.color = color
	band.custom_minimum_size = Vector2(0, 10)
	body_column.add_child(band)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 34)
	inner.add_theme_constant_override("margin_right", 34)
	inner.add_theme_constant_override("margin_top", 30)
	inner.add_theme_constant_override("margin_bottom", 30)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_column.add_child(inner)
	var text := MenuUI.vbox(0)
	inner.add_child(text)

	text.add_child(MenuUI.label("%s   ·   %s" % [str(mode.sub), str(mode.players)], 20,
			MenuUI.TEXT_DIM))
	text.add_child(MenuUI.display(str(mode.name).to_upper(), 72))
	text.add_child(MenuUI.gap(6, true))
	text.add_child(MenuUI.label(str(mode.map), 22, MenuUI.GOLD))
	text.add_child(MenuUI.gap(20, true))
	text.add_child(MenuUI.rule())
	text.add_child(MenuUI.gap(20, true))
	text.add_child(MenuUI.wrap(MenuUI.body(str(mode.text), 24, MenuUI.TEXT_SOFT)))
	text.add_child(MenuUI.spacer())

	var actions := MenuUI.hbox(14)
	text.add_child(actions)
	if selected:
		var play: Button = MenuUI.button("PLAY", "gold", 34, Vector2(220, 78))
		play.pressed.connect(func() -> void:
			menu.sfx("play")
			menu.start_match())
		actions.add_child(play)
		var tag: Label = MenuUI.label("SELECTED", 19, MenuUI.GOLD)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		actions.add_child(tag)
	else:
		var select: Button = MenuUI.button("SELECT", "navy", 30, Vector2(220, 78))
		select.pressed.connect(func() -> void:
			menu.select_mode(str(mode.id))
			sfx("reward")
			close_screen()
			menu.toast("%s selected" % str(mode.name)))
		actions.add_child(select)
	return card

func _planned_row(mode: Dictionary) -> Control:
	var row := MenuUI.hbox(0)
	row.custom_minimum_size = Vector2(0, 60)
	var block := ColorRect.new()
	block.color = MenuUI.RULE
	block.custom_minimum_size = Vector2(7, 0)
	row.add_child(block)
	row.add_child(MenuUI.gap(16))
	var name_label: Label = MenuUI.display(str(mode.name).to_upper(), 32, MenuUI.TEXT_FAINT)
	name_label.custom_minimum_size = Vector2(360, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var sub: Label = MenuUI.label("%s   ·   %s" % [str(mode.sub), str(mode.map)], 19,
			MenuUI.TEXT_FAINT)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sub)
	row.add_child(MenuUI.spacer())
	return row
