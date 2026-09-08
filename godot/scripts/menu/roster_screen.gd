class_name RosterScreen
extends MenuScreen
## Brawler select: a rail of faces you scroll sideways.
##
## *Rebuilt twice in one day, and the second one is the point.* It began as nine
## numbered rows, became a grid of portrait tiles on the morning of 7 Sep, and
## became this in the afternoon on Jackson's notes. The grid fixed the right
## thing — you recognise a fighter by face, not by comparing trophy counts — and
## got two things wrong that only show up on a phone:
##
##   **A grid of nine is a wall; a rail of nine is a queue.** Sideways scrolling
##   is the gesture this shape asks for on a handset, and it lets each card be
##   large enough to carry its own numbers instead of shrinking them to fit two
##   rows on screen at once.
##
##   **Choosing and studying are different gestures.** The tile used to select
##   on any tap, so there was nowhere to look a fighter up. The picture now
##   opens their page (`BrawlerScreen`); the SELECT button under it picks them
##   and returns. That is the Brawl Stars shape, and it is what the notes ask
##   for by name.
##
## Everything a card shows is a thing you would compare across fighters while
## picking one: power level, trophies, and how far this one is from their next
## rank. Anything that only matters once you have picked is on their page.

const CARD_W := 360.0
const CARD_H := 600.0
const CARD_PAD := 12
const RAIL_GAP := 16

func _build() -> void:
	screen_name = "roster"
	var unlocked: int = 0
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.id)):
			unlocked += 1
	topbar("Roster", "%d of %d" % [unlocked, MenuData.brawlers.size()])

	var column: VBoxContainer = fill_content(0)
	var rail := ScrollContainer.new()
	rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# SHOW_NEVER, not AUTO: an auto bar reserves its height under the rail even
	# when it is not drawn. The rail is dragged.
	rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.add_child(rail)
	var row := MenuUI.hbox(RAIL_GAP)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.add_child(row)
	for i in MenuData.brawlers.size():
		row.add_child(_card(MenuData.brawlers[i], i + 1))
	stagger_children(row, 0.03)
	_scroll_to_selected(rail)

## Open on the fighter you are playing, not on the left end of the rail.
func _scroll_to_selected(rail: ScrollContainer) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(rail):
		return
	var index: int = 0
	for i in MenuData.brawlers.size():
		if str(MenuData.brawlers[i].id) == SaveGame.selected_kit.to_lower():
			index = i
			break
	var step: float = CARD_W + RAIL_GAP
	rail.scroll_horizontal = int(maxf(0.0, index * step - (rail.size.x - CARD_W) * 0.5))

# MARK: the card

func _card(b: Dictionary, index: int) -> Control:
	var id: String = str(b.id)
	var unlocked: bool = SaveGame.is_unlocked(id)
	var selected: bool = id == SaveGame.selected_kit.to_lower()
	var color: Color = MenuUI.hex(b.get("color"), MenuUI.BLUE)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box: StyleBoxFlat = MenuUI.flat_box(MenuUI.PANEL,
			MenuUI.GOLD if selected else MenuUI.RULE_HI, CARD_PAD).duplicate()
	if selected:
		box.set_border_width_all(3)
		box.border_color = MenuUI.GOLD
	card.add_theme_stylebox_override("panel", box)
	var column := MenuUI.vbox(10)
	card.add_child(column)
	column.add_child(_face(b, index, color, unlocked))
	column.add_child(_name_row(b, unlocked, selected))
	column.add_child(_numbers(id, unlocked))
	column.add_child(MenuUI.spacer())
	column.add_child(_action(b, id, unlocked, selected))
	return card

## The picture, and the button that opens this fighter's page. Pressing it does
## NOT select them — that is the control underneath.
func _face(b: Dictionary, index: int, color: Color, unlocked: bool) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, CARD_W - 2.0 * CARD_PAD)
	button.clip_contents = true
	var fill: Color = MenuUI.INK.lerp(color, 0.42) if unlocked else MenuUI.PANEL_HI
	for state in ["normal", "focus", "disabled"]:
		button.add_theme_stylebox_override(state,
				MenuUI.flat_box(fill, Color(0, 0, 0, 0), 0, MenuUI.RADIUS_SMALL))
	button.add_theme_stylebox_override("hover",
			MenuUI.flat_box(fill.lerp(MenuUI.TEXT, 0.10), MenuUI.GOLD, 0, MenuUI.RADIUS_SMALL))
	button.add_theme_stylebox_override("pressed",
			MenuUI.flat_box(fill.lerp(MenuUI.INK, 0.3), MenuUI.GOLD, 0, MenuUI.RADIUS_SMALL))
	MenuUI.press_feedback(button)
	button.pressed.connect(func() -> void:
		menu.sfx("click")
		menu.open_brawler(b))

	var art: Texture2D = MenuData.portrait(str(b.id))
	if art != null:
		var face := TextureRect.new()
		face.texture = art
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			face.modulate = Color(0.16, 0.17, 0.21, 1.0)
		button.add_child(face)
	else:
		var initial: Label = MenuUI.display(str(b.get("name", "?")).substr(0, 1).to_upper(),
				160, MenuUI.INK.lerp(MenuUI.TEXT, 0.30 if unlocked else 0.12))
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(initial)

	var number: Label = MenuUI.display("%02d" % index, 28,
			Color(1, 1, 1, 0.45) if unlocked else MenuUI.TEXT_FAINT)
	MenuUI.pin(number, false, false, 12.0)
	button.add_child(number)
	if not unlocked:
		var lock: TextureRect = MenuUI.icon("lock", 40)
		MenuUI.pin(lock, true, false, 12.0)
		button.add_child(lock)
	else:
		# Power level, in the corner, wearing the glyph it wears on the
		# fighter's own page — it was two different pictures before.
		var chip := MenuUI.hbox(4)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glyph: TextureRect = MenuUI.icon("power", 26)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(glyph)
		var level: Label = MenuUI.display(str(SaveGame.brawler_power(str(b.id))), 30)
		level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(level)
		MenuUI.pin(chip, true, false, 12.0)
		button.add_child(chip)
	return button

func _name_row(b: Dictionary, unlocked: bool, selected: bool) -> Control:
	var column := MenuUI.vbox(0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label: Label = MenuUI.display(str(b.get("name", "")).to_upper(), 46,
			MenuUI.GOLD if selected else (MenuUI.TEXT if unlocked else MenuUI.TEXT_DIM))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	column.add_child(MenuUI.label(str(b.get("role", "")), 26,
			MenuUI.TEXT_DIM if unlocked else MenuUI.TEXT_FAINT))
	return column

## Trophies and the rank they are worth, with the bar that says how far the
## next one is. A rank number on its own says nothing about that.
func _numbers(id: String, unlocked: bool) -> Control:
	var column := MenuUI.vbox(6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		return column
	var trophies: int = SaveGame.brawler_trophies(id)
	var rank: int = MenuData.rank_of(trophies)
	var span: Array = MenuData.rank_span(rank)
	var row := MenuUI.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	var cup: TextureRect = MenuUI.pack_icon("trophy", 30)
	cup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cup)
	var figure: Label = MenuUI.display(MenuUI.fmt(trophies), 32, MenuUI.GOLD)
	figure.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(figure)
	row.add_child(MenuUI.spacer())
	var rank_word: Label = MenuUI.label("RANK", 22, MenuUI.TEXT_FAINT)
	rank_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(rank_word)
	var rank_value: Label = MenuUI.display(str(rank), 32)
	rank_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(rank_value)
	var bar: Panel = MenuUI.bar(8, MenuUI.GOLD)
	column.add_child(bar)
	if int(span[1]) < 0:
		MenuUI.set_bar(bar, 1.0, false)
	else:
		var lo: int = int(span[0])
		var hi: int = int(span[1])
		MenuUI.set_bar(bar, float(trophies - lo) / maxf(1.0, float(hi - lo)), false)
	return column

## The one control that picks a fighter. A locked one says how to get them here
## instead, in the space the button would take.
func _action(b: Dictionary, id: String, unlocked: bool, selected: bool) -> Control:
	if not unlocked:
		var hint: Label = MenuUI.wrap(MenuUI.label(str(b.get("unlock_hint", "Locked")), 26,
				MenuUI.TEXT_FAINT))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.custom_minimum_size = Vector2(0, 64)
		return hint
	if selected:
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel",
				MenuUI.flat_box(MenuUI.GOLD_DIM.lerp(MenuUI.INK, 0.55), MenuUI.GOLD, 0))
		badge.custom_minimum_size = Vector2(0, 64)
		var word: Label = MenuUI.label("SELECTED", 28, MenuUI.GOLD)
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(word)
		return badge
	var select: Button = MenuUI.button("SELECT", "gold", 30, Vector2(0, 64), 10)
	select.pressed.connect(func() -> void:
		menu.sfx("reward")
		menu.select_brawler(id)
		close_screen())
	return select
