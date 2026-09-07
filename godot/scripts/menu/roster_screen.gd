class_name RosterScreen
extends MenuScreen
## The roster, as a wall of faces: one tile per fighter, tapped to pick them.
##
## It is a picker and nothing else. Tapping a tile selects that fighter and
## comes straight back to home, where the flanks already show everything the old
## detail screen did — so there is no card to open, no SELECT button to find and
## no second screen to back out of.
##
## *This was a numbered table until 7 Sep 2026,* and the argument for the table
## was that nine rows fit one screen with no scrolling and put the numbers in
## columns you can compare down, which a grid cannot do. Both halves were true
## and neither was the point. **You do not pick a fighter by comparing trophy
## counts** — you pick the one you want to play, and you recognise them by face.
## The table made the two figures the loudest thing on a screen whose whole job
## is recognition, and it showed nine names in the display face where nine
## portraits were already rendered and sitting unused (`assets/menu/portraits/`,
## shot off the models on the menu stage's own rig, so a tile and the fighter
## who walks out are lit identically). The numbers are still here, small, in the
## footer of each tile, which is the right weight for them.
##
## Two rows always: `_columns()` is `ceil(n / 2)`, so nine fighters lay out 5+4
## and the twelve the beta bar asks for lay out 6+6, both on one fixed-height
## screen with no scrolling. Past twelve this needs a scroll or a third row.

## A floor, not the size — the tiles expand to fill the screen (see `_build`).
const TILE_MIN := Vector2(300, 330)
const GRID_GAP := 16
## The face's share of a tile. The rest is the name, the role and the footer.
const ART_FRAC := 0.56

func _build() -> void:
	screen_name = "roster"
	var unlocked: int = 0
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.id)):
			unlocked += 1
	topbar("Roster", "%d of %d" % [unlocked, MenuData.brawlers.size()])

	var column: VBoxContainer = fill_content(0)
	var grid: GridContainer = MenuUI.grid(_columns(), GRID_GAP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(grid)
	for i in MenuData.brawlers.size():
		grid.add_child(_tile(MenuData.brawlers[i], i + 1))
	stagger_children(grid, 0.02)

func _columns() -> int:
	return maxi(1, int(ceil(MenuData.brawlers.size() / 2.0)))

# MARK: the tile

func _tile(b: Dictionary, index: int) -> Button:
	var id: String = str(b.id)
	var unlocked: bool = SaveGame.is_unlocked(id)
	var selected: bool = id == SaveGame.selected_kit.to_lower()
	var color: Color = MenuUI.hex(b.get("color"), MenuUI.BLUE)
	var edge: Color = MenuUI.GOLD if selected else MenuUI.RULE_HI

	var tile := Button.new()
	tile.custom_minimum_size = TILE_MIN
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.clip_contents = true
	var box: StyleBoxFlat = MenuUI.flat_box(MenuUI.PANEL, edge, 0).duplicate()
	if selected:
		box.set_border_width_all(3)
		box.border_color = MenuUI.GOLD
	for state in ["normal", "focus", "disabled"]:
		tile.add_theme_stylebox_override(state, box)
	tile.add_theme_stylebox_override("hover", MenuUI.flat_box(MenuUI.PANEL_HI, edge, 0))
	tile.add_theme_stylebox_override("pressed", MenuUI.flat_box(MenuUI.INK, edge, 0))
	MenuUI.press_feedback(tile)
	tile.pressed.connect(func() -> void:
		if not unlocked:
			sfx("error")
			toast(str(b.get("unlock_hint", "")) if str(b.get("unlock_hint", "")) != "" else "Locked")
			return
		sfx("reward")
		menu.select_brawler(id)
		close_screen())

	# Button is not a container, so the tile's contents are an anchored column.
	var column := MenuUI.vbox(0)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(column)
	column.add_child(_face(b, index, color, unlocked, selected))
	column.add_child(_footer(b, id, unlocked, selected))
	return tile

## The face, on a ground of the fighter's own colour. The ground is the only
## place a kit's colour is a solid block in the menu outside the home flanks,
## and it is what makes a wall of nine tiles readable at a glance rather than
## nine identical dark rectangles.
func _face(b: Dictionary, index: int, color: Color, unlocked: bool,
		selected: bool) -> Control:
	# A Panel, not a PanelContainer: a container lays its children out to fill
	# it and ignores their anchors, so the roster number and the SELECTED mark
	# both landed on top of each other in the top-left corner.
	var ground := Panel.new()
	ground.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ground.size_flags_stretch_ratio = ART_FRAC
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: Color = MenuUI.INK.lerp(color, 0.42) if unlocked else MenuUI.PANEL_HI
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	# Top corners follow the tile; the bottom edge is a straight seam against
	# the name plate, not a second rounded box floating inside the first.
	box.set_corner_radius(CORNER_TOP_LEFT, MenuUI.RADIUS)
	box.set_corner_radius(CORNER_TOP_RIGHT, MenuUI.RADIUS)
	ground.add_theme_stylebox_override("panel", box)

	var art: Texture2D = MenuData.portrait(str(b.id))
	if art != null:
		var face := TextureRect.new()
		face.texture = art
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			# Silhouetted rather than hidden: which fighter it is stays part of
			# the reason to go and unlock them.
			face.modulate = Color(0.16, 0.17, 0.21, 1.0)
		ground.add_child(face)
	else:
		# Nova has no render yet (todo 4.1). An initial in the display face
		# reads as "not shot yet" where a broken-image box reads as a bug.
		var initial: Label = MenuUI.display(str(b.get("name", "?")).substr(0, 1).to_upper(),
				150, MenuUI.INK.lerp(MenuUI.TEXT, 0.30 if unlocked else 0.12))
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.add_child(initial)

	# The programme's roster number, kept from the table it replaces.
	var number: Label = MenuUI.display("%02d" % index, 26,
			Color(1, 1, 1, 0.45) if unlocked else MenuUI.TEXT_FAINT)
	MenuUI.pin(number, false, false, 12.0)
	ground.add_child(number)
	if selected:
		var mark: Label = MenuUI.label("SELECTED", 22, MenuUI.GOLD)
		MenuUI.pin(mark, true, false, 12.0)
		ground.add_child(mark)
	elif not unlocked:
		var lock: TextureRect = MenuUI.icon("lock", 34)
		MenuUI.pin(lock, true, false, 12.0)
		ground.add_child(lock)
	return ground

## Name, role, and the two figures the table used to lead with — trophies and
## power — at the weight they deserve. A locked fighter spends the same strip
## on how to get them, because the numbers do not exist yet and a blank row
## plus a padlock says less than the sentence does.
func _footer(b: Dictionary, id: String, unlocked: bool, selected: bool) -> Control:
	var plate := MarginContainer.new()
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plate.size_flags_stretch_ratio = 1.0 - ART_FRAC
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right"]:
		plate.add_theme_constant_override(side, 16)
	plate.add_theme_constant_override("margin_top", 10)
	plate.add_theme_constant_override("margin_bottom", 12)
	var column := MenuUI.vbox(2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)

	var name_label: Label = MenuUI.display(str(b.get("name", "")).to_upper(), 44,
			MenuUI.GOLD if selected else (MenuUI.TEXT if unlocked else MenuUI.TEXT_DIM))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	column.add_child(MenuUI.label(str(b.get("role", "")), 22,
			MenuUI.TEXT_DIM if unlocked else MenuUI.TEXT_FAINT))
	column.add_child(MenuUI.gap(6, true))

	if not unlocked:
		var hint: Label = MenuUI.wrap(MenuUI.label(str(b.get("unlock_hint", "Locked")), 22,
				MenuUI.TEXT_FAINT))
		column.add_child(hint)
		return plate

	var figures := MenuUI.hbox(8)
	figures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(figures)
	var cup: TextureRect = MenuUI.pack_icon("trophy", 28)
	cup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	figures.add_child(cup)
	var trophies: Label = MenuUI.display(MenuUI.fmt(SaveGame.brawler_trophies(id)), 30,
			MenuUI.GOLD)
	trophies.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	figures.add_child(trophies)
	figures.add_child(MenuUI.spacer())
	var power_word: Label = MenuUI.label("PWR", 22, MenuUI.TEXT_FAINT)
	power_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	figures.add_child(power_word)
	var power: Label = MenuUI.display(str(SaveGame.brawler_power(id)), 30, MenuUI.TEXT)
	power.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	figures.add_child(power)
	return plate
