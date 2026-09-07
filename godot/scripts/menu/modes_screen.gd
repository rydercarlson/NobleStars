class_name ModesScreen
extends MenuScreen
## Choose an event.
##
## Two modes are built. Five are not, and the first version of this screen gave
## all seven the same sized card with an IN DEVELOPMENT flash on five of them —
## which made the screen mostly a list of things you cannot do and made the two
## you can do hard to find in it. So the built ones are large and the rest are
## small, dim, and under a heading that says what they are.
##
## *Relaid out 7 Sep 2026 with the rest of the pushed screens.* Two things were
## wrong beyond the type scale. **The SELECT button was invisible**: it was
## built `"navy"`, which `MenuUI.fill_for` resolves to `PANEL` — the same fill
## as the card it sat on — so the only mode you could not already play offered
## you a word floating in the dark. And each card carried a hairline rule as a
## separator, which the 6 Sep pass removed everywhere else. Each mode also
## names an `icon` in game.json that nothing drew; they are drawn now.

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
		column.add_child(MenuUI.gap(28, true))
		column.add_child(MenuUI.section("PLANNED   ·   NOT BUILT YET"))
		column.add_child(MenuUI.gap(10, true))
		var grid: GridContainer = MenuUI.grid(planned.size(), 12)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(grid)
		for mode: Dictionary in planned:
			grid.add_child(_planned_card(mode))
	column.add_child(MenuUI.gap(10, true))

## The glyph a mode names in game.json. `bulldog` is the pack PNG; the rest are
## the svg set, and the Cup's ball was drawn for this.
func _mode_icon(mode: Dictionary, size: float) -> Control:
	var name: String = str(mode.get("icon", ""))
	if name == "bulldog":
		return MenuUI.pack_icon("bulldog", size)
	if name == "brawl_ball":
		name = "ball"
	return MenuUI.icon(name, size)

func _mode_card(mode: Dictionary) -> Control:
	var color: Color = MenuUI.hex(mode.get("color"), MenuUI.GREEN)
	var selected: bool = str(mode.id) == SaveGame.selected_mode

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
			MenuUI.flat_box(MenuUI.PANEL, MenuUI.GOLD if selected else MenuUI.RULE_HI, 0))
	card.clip_contents = true
	var body_column := MenuUI.vbox(0)
	card.add_child(body_column)

	# The mode's colour as a solid band across the top — the one place it
	# appears, so two cards side by side are told apart by it.
	var band := ColorRect.new()
	band.color = color
	band.custom_minimum_size = Vector2(0, 10)
	body_column.add_child(band)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 30)
	inner.add_theme_constant_override("margin_right", 30)
	inner.add_theme_constant_override("margin_top", 26)
	inner.add_theme_constant_override("margin_bottom", 26)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_column.add_child(inner)
	var text := MenuUI.vbox(0)
	inner.add_child(text)

	var head := MenuUI.hbox(18)
	text.add_child(head)
	var glyph: Control = _mode_icon(mode, 66)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(glyph)
	var titles := MenuUI.vbox(0)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(MenuUI.label("%s   ·   %s" % [str(mode.sub), str(mode.players)], 26,
			MenuUI.TEXT_DIM))
	var name_label: Label = MenuUI.display(str(mode.name).to_upper(), 62)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(name_label)

	# The map, in gold and nothing else. A glyph was tried beside it and there
	# is no map icon in the set — `stage_ring` at 22px reads as a smudge, and
	# the colour already says "this is the place".
	text.add_child(MenuUI.gap(10, true))
	text.add_child(MenuUI.label(str(mode.map), 26, MenuUI.GOLD))
	text.add_child(MenuUI.gap(16, true))
	text.add_child(MenuUI.wrap(MenuUI.body(str(mode.text), 26, MenuUI.TEXT_SOFT)))
	text.add_child(MenuUI.spacer())

	# One control, always visible. SELECT used to be built "navy", which is the
	# card's own fill, so on the mode you had not picked the action was a word
	# with nothing under it.
	if selected:
		var play: Button = MenuUI.button("PLAY", "gold", 36, Vector2(0, 82))
		play.pressed.connect(func() -> void:
			menu.sfx("play")
			menu.start_match())
		text.add_child(play)
	else:
		var select: Button = MenuUI.button("SELECT", "grey", 32, Vector2(0, 82))
		select.pressed.connect(func() -> void:
			menu.select_mode(str(mode.id))
			sfx("reward")
			close_screen()
			menu.toast("%s selected" % str(mode.name)))
		text.add_child(select)
	return card

## A mode that is not built: the same card, small and dim, with what it will be
## rather than a flash saying it is not ready. Five of these under a heading
## reads as a plan; five full-sized cards read as a broken screen.
func _planned_card(mode: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
			MenuUI.flat_box(MenuUI.INK, MenuUI.RULE, 14))
	card.custom_minimum_size = Vector2(0, 132)
	var column := MenuUI.vbox(6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	var glyph: Control = _mode_icon(mode, 40)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glyph.modulate = Color(1, 1, 1, 0.34)
	column.add_child(glyph)
	var name_label: Label = MenuUI.display(str(mode.name).to_upper(), 28, MenuUI.TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	var sub: Label = MenuUI.wrap(MenuUI.label("%s · %s" % [str(mode.sub), str(mode.map)], 26,
			MenuUI.TEXT_FAINT))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	return card
