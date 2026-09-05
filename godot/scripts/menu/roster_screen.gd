class_name RosterScreen
extends MenuScreen
## The roster, as the programme's team page: nine rows, numbered, with what each
## one is worth beside them.
##
## It is a picker and nothing else. Tapping a row selects that fighter and comes
## straight back to home, where the flanks already show everything the old
## detail screen did — so there is no card to open, no SELECT button to find and
## no second screen to back out of.
##
## A table rather than a grid of portrait cards, for a reason that only holds
## because this roster is small: nine rows fit on one screen with no scrolling
## and no pagination, so the whole team is legible at once and the numbers line
## up in columns you can actually compare down. A grid cannot do either.

const ROW_H := 84.0
const COL_TROPHIES := 200.0
const COL_POWER := 130.0
const COL_STATE := 230.0

func _build() -> void:
	screen_name = "roster"
	var unlocked: int = 0
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.id)):
			unlocked += 1
	topbar("Roster", "%d of %d" % [unlocked, MenuData.brawlers.size()])

	var column: VBoxContainer = fill_content(0)
	column.add_child(_header())
	column.add_child(MenuUI.gap(6, true))
	var rows := MenuUI.vbox(0)
	column.add_child(rows)
	for i in MenuData.brawlers.size():
		rows.add_child(_row(MenuData.brawlers[i], i + 1))
		rows.add_child(MenuUI.rule())
	column.add_child(MenuUI.spacer())
	stagger_children(rows, 0.025)

## The column heads. These are the only labels in the table — every row below
## repeats the shape, so the names do not need repeating with them.
func _header() -> HBoxContainer:
	var row := MenuUI.hbox(0)
	row.custom_minimum_size = Vector2(0, 34)
	row.add_child(MenuUI.gap(7 + 16 + 56))
	var name_label: Label = MenuUI.label("FIGHTER", 18, MenuUI.TEXT_FAINT)
	name_label.custom_minimum_size = Vector2(420, 0)
	row.add_child(name_label)
	row.add_child(MenuUI.label("ROLE", 18, MenuUI.TEXT_FAINT))
	row.add_child(MenuUI.spacer())
	row.add_child(_head("TROPHIES", COL_TROPHIES))
	row.add_child(_head("POWER", COL_POWER))
	row.add_child(_head("", COL_STATE))
	return row

func _head(text: String, width: float) -> Label:
	var l: Label = MenuUI.label(text, 18, MenuUI.TEXT_FAINT)
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

func _row(b: Dictionary, index: int) -> Button:
	var id: String = str(b.id)
	var unlocked: bool = SaveGame.is_unlocked(id)
	var selected: bool = id == SaveGame.selected_kit.to_lower()
	var color: Color = MenuUI.hex(b.get("color"), MenuUI.BLUE)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, ROW_H)
	var fill: Color = MenuUI.PANEL if selected else Color(0, 0, 0, 0)
	for state in ["normal", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, MenuUI.flat_box(fill))
	button.add_theme_stylebox_override("hover", MenuUI.flat_box(MenuUI.PANEL_HI))
	button.add_theme_stylebox_override("pressed", MenuUI.flat_box(MenuUI.PANEL))
	MenuUI.press_feedback(button)
	button.pressed.connect(func() -> void:
		if not unlocked:
			sfx("error")
			toast(str(b.unlock_hint) if str(b.unlock_hint) != "" else "Locked")
			return
		sfx("reward")
		menu.select_brawler(id)
		close_screen())

	# Button is not a container, so the row's contents are an anchored box.
	var row := MenuUI.hbox(0)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	# The team block: the one place a fighter's colour appears in the table, so
	# the column of them reads as the roster's spine.
	var block := ColorRect.new()
	block.color = color if unlocked else MenuUI.RULE
	block.custom_minimum_size = Vector2(7, 0)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(block)
	row.add_child(MenuUI.gap(16))

	var number: Label = MenuUI.display("%02d" % index, 30,
			MenuUI.GOLD if selected else MenuUI.TEXT_FAINT)
	number.custom_minimum_size = Vector2(56, 0)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(number)

	var name_label: Label = MenuUI.display(str(b.name).to_upper(), 46,
			MenuUI.TEXT if unlocked else MenuUI.TEXT_FAINT)
	name_label.custom_minimum_size = Vector2(420, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var role: Label = MenuUI.label(str(b.get("role", "")), 19,
			MenuUI.TEXT_DIM if unlocked else MenuUI.TEXT_FAINT)
	role.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(role)
	row.add_child(MenuUI.spacer())

	if unlocked:
		row.add_child(_figure(MenuUI.fmt(SaveGame.brawler_trophies(id)), COL_TROPHIES,
				MenuUI.GOLD))
		row.add_child(_figure(str(SaveGame.brawler_power(id)), COL_POWER, MenuUI.TEXT))
		var state: Label = MenuUI.label("SELECTED" if selected else "", 19, MenuUI.GOLD)
		state.custom_minimum_size = Vector2(COL_STATE, 0)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(state)
	else:
		# A locked fighter's row carries how to get them, in the space the
		# numbers would occupy — the numbers do not exist yet, and an empty
		# column plus a padlock says less than the sentence does.
		var hint: Label = MenuUI.label(str(b.get("unlock_hint", "Locked")), 19,
				MenuUI.TEXT_FAINT)
		hint.custom_minimum_size = Vector2(COL_TROPHIES + COL_POWER + COL_STATE, 0)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(hint)
	row.add_child(MenuUI.gap(8))
	return button

func _figure(text: String, width: float, color: Color) -> Label:
	var l: Label = MenuUI.display(text, 34, color)
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
