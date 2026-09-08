class_name HomeScreen
extends Control
## The lobby, and only the lobby: who you are, what you have, who you are
## playing, what you are playing, and where else you can go.
##
## *Stripped back on 7 Sep 2026, from Jackson's notes.* Home used to be the
## detail screen as well — five stat bars, two ability write-ups and a record
## card down both flanks, live for whoever was selected — on the argument that
## it saved a screen and took choosing a fighter from five taps to two. What it
## really did was make the lobby permanently loud, and it made the record read
## as *your* record rather than as that fighter's, because nothing beside it
## said whose it was. All of it moved to `BrawlerScreen`, which you reach by
## tapping a roster tile. **You read stats when you are choosing a fighter, not
## while you are picking a mode.**
##
## What is left, and where:
##
##   top-left      your name, and trophies with the road's next rung under them
##   top-right     coins and gems, then the menu
##   centre        the fighter, on his shadow, with one hint under him
##   bottom-left   the four destinations — a nav bar owned by MenuShell
##   bottom-right  the mode plate and PLAY, side by side, on one baseline

var menu: MenuShell

const MARGIN_X := 60.0
const TOP_Y := 34.0
## The bottom row: PLAY and the mode plate share this baseline with the nav.
const BOTTOM_INSET := 44.0
const PLAY_SIZE := Vector2(340, 108)
const MODE_SIZE := Vector2(310, 108)
const PLAY_GAP := 8.0
const PLAY_RIGHT_INSET := MARGIN_X - 12.0
## Where the fighter's feet meet the stage, as a fraction of its height —
## MenuStage frames him to the stage height, so this holds on a taller stage.
## (900 of 1080 on a 16:9 display.)
const FEET_FRAC := 900.0 / 1080.0
## The identity block, wide enough for the trophy bar to mean something.
const IDENTITY_W := 460.0

var _name_label: Label
var _trophy_label: Label
var _trophy_bar: Panel
var _trophy_goal: Label
var _mode_name: Label
var _mode_sub: Label
var _mode_flag: ColorRect
var _hint: Label
var _intro_done := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_identity()
	_build_top_right()
	_build_bottom_right()
	_build_hint()
	refresh()
	menu.brawler_view.tapped.connect(_on_brawler_tapped)
	_play_intro()

# MARK: identity

## Name over trophies, with the Trophy Road's next rung as a bar. The figure
## carries the same trophy glyph a fighter's own trophies do, because they are
## the same currency and were drawn two different ways.
func _build_identity() -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(IDENTITY_W, 118)
	var clear: StyleBoxFlat = MenuUI.flat_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	for state in ["normal", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, clear)
	button.add_theme_stylebox_override("hover",
			MenuUI.flat_box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("pressed", clear)
	MenuUI.press_feedback(button)
	button.pressed.connect(func() -> void:
		menu.sfx("click")
		MenuPopups.profile(menu))
	# The trophy row is its own target: the road is what the number is for, and
	# it now lives where the number does rather than on the season's page.
	var road := Button.new()
	road.flat = true
	for state in ["normal", "focus", "disabled", "pressed"]:
		road.add_theme_stylebox_override(state,
				MenuUI.flat_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	road.add_theme_stylebox_override("hover",
			MenuUI.flat_box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0))
	road.pressed.connect(func() -> void:
		menu.sfx("click")
		menu.show_screen("road"))
	MenuUI.press_feedback(road)
	_place(button, MARGIN_X - 10.0, TOP_Y - 8.0, IDENTITY_W, 118)

	var column := MenuUI.vbox(2)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 10
	column.offset_right = -10
	column.offset_top = 8
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)

	_name_label = MenuUI.display("GUEST", 46)
	column.add_child(_name_label)
	road.custom_minimum_size = Vector2(0, 62)
	column.add_child(road)
	var row := MenuUI.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road.add_child(row)
	var cup: TextureRect = MenuUI.pack_icon("trophy", 30)
	cup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cup)
	_trophy_label = MenuUI.display("0", 34, MenuUI.GOLD)
	_trophy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_trophy_label)
	row.add_child(MenuUI.spacer())
	_trophy_goal = MenuUI.label("", 22, MenuUI.TEXT_FAINT)
	_trophy_goal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_trophy_goal)
	_trophy_bar = MenuUI.bar(8, MenuUI.GOLD)
	_trophy_bar.anchor_top = 1.0
	_trophy_bar.anchor_bottom = 1.0
	_trophy_bar.anchor_right = 1.0
	_trophy_bar.offset_top = -8
	_trophy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road.add_child(_trophy_bar)

func _build_top_right() -> void:
	var right := MenuUI.hbox(26)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -760
	right.offset_right = -MARGIN_X + 10
	right.offset_top = TOP_Y - 4
	right.offset_bottom = TOP_Y + 72
	add_child(right)
	right.add_child(MenuUI.spacer())
	var money: HBoxContainer = menu.currency_readout()
	money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(money)
	var divider: ColorRect = MenuUI.rule(MenuUI.RULE_HI, true)
	divider.custom_minimum_size = Vector2(1, 52)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(divider)
	# The three bars open a menu of destinations, not the settings sheet — a
	# control that looks like a menu and is a single screen reads as broken.
	var settings: Button = MenuUI.menu_button()
	settings.pressed.connect(func() -> void:
		menu.sfx("click")
		MenuPopups.main_menu(menu))
	right.add_child(settings)

# MARK: bottom right

## The mode plate and PLAY: side by side, the same height, on the baseline the
## nav bar shares. PLAY is the biggest thing on the screen on purpose.
func _build_bottom_right() -> void:
	var right := MenuUI.hbox(int(PLAY_GAP))
	right.alignment = BoxContainer.ALIGNMENT_END
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -PLAY_RIGHT_INSET - PLAY_SIZE.x - PLAY_GAP - MODE_SIZE.x
	right.offset_right = -PLAY_RIGHT_INSET
	right.offset_top = -BOTTOM_INSET - PLAY_SIZE.y
	right.offset_bottom = -BOTTOM_INSET
	add_child(right)
	right.add_child(_build_mode_button())
	var play: Button = MenuUI.button("PLAY", "gold", 64, PLAY_SIZE)
	play.pressed.connect(func() -> void:
		menu.sfx("play")
		menu.start_match())
	right.add_child(play)

## The mode plate: a dark card with a gold edge on the left, the mode's line
## and name, and a chevron saying it opens.
func _build_mode_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = MODE_SIZE
	for state in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, MenuUI.flat_box(MenuUI.PANEL, MenuUI.RULE_HI, 0))
	b.add_theme_stylebox_override("hover",
			MenuUI.flat_box(MenuUI.PANEL_HI, MenuUI.RULE_HI, 0))
	b.add_theme_stylebox_override("pressed",
			MenuUI.flat_box(MenuUI.INK, MenuUI.RULE_HI, 0))
	MenuUI.press_feedback(b)
	b.pressed.connect(func() -> void:
		menu.sfx("click")
		menu.show_screen("modes"))

	# Button is not a container, so its contents are an anchored row.
	var row := MenuUI.hbox(16)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_top = 10
	row.offset_bottom = -10
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	_mode_flag = ColorRect.new()
	_mode_flag.color = MenuUI.GOLD
	_mode_flag.custom_minimum_size = Vector2(5, 0)
	_mode_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_mode_flag)
	var text := MenuUI.vbox(0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	_mode_sub = MenuUI.label("EVENT", 26, MenuUI.TEXT_FAINT)
	_mode_name = MenuUI.display("SHOWDOWN", 36)
	text.add_child(_mode_sub)
	text.add_child(_mode_name)
	row.add_child(MenuUI.spacer())
	var chevron: Label = MenuUI.display("›", 44, MenuUI.TEXT_SOFT)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)
	row.add_child(MenuUI.gap(14))
	return b

## The one thing near the fighter: what touching him does, right under his feet.
func _build_hint() -> void:
	# Two lines, not one. Under the fighter is a narrow slot: the mode plate and
	# PLAY start 1,214 px across, and once the fighter moved right to sit in the
	# space the nav rail leaves, a single 430 px line ran under the plate.
	_hint = MenuUI.label("TAP TO ATTACK\nDRAG TO SPIN", 26, MenuUI.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = FEET_FRAC
	_hint.anchor_bottom = FEET_FRAC
	_hint.offset_left = MenuShell.STAGE_SHIFT - 160
	_hint.offset_right = MenuShell.STAGE_SHIFT + 160
	_hint.offset_top = 34
	_hint.offset_bottom = 110
	_hint.modulate.a = 0.0
	add_child(_hint)

func _on_brawler_tapped() -> void:
	menu.sfx("hit")
	if SaveGame.first_run:
		SaveGame.first_run = false
		SaveGame.save()
	_hint.modulate.a = 0.0

# MARK: state

func refresh() -> void:
	_name_label.text = SaveGame.player_name.to_upper()
	var total: int = SaveGame.total_trophies()
	_trophy_label.text = MenuUI.fmt(total)

	# The road's next rung, as a bar. A trophy count with nothing to measure it
	# against is a number that only counts up.
	var lo: int = 0
	var hi: int = -1
	for entry in MenuData.trophy_road():
		var goal: int = int(entry.get("trophies", 0))
		if goal > total:
			hi = goal
			break
		lo = goal
	if hi < 0:
		_trophy_goal.text = "ROAD COMPLETE"
		MenuUI.set_bar(_trophy_bar, 1.0, false)
	else:
		_trophy_goal.text = "%s TO %s" % [MenuUI.fmt(hi - total), MenuUI.fmt(hi)]
		MenuUI.set_bar(_trophy_bar, float(total - lo) / maxf(1.0, float(hi - lo)), false)

	var mode: Dictionary = menu.selected_mode()
	if not mode.is_empty():
		_mode_name.text = str(mode.get("name", "SHOWDOWN")).to_upper()
		_mode_sub.text = str(mode.get("sub", "")).to_upper()

	_hint.modulate.a = 0.85 if SaveGame.hints_on else 0.0

# MARK: layout helpers

## Position a control in stage pixels, anchored to the stage's top-left.
func _place(c: Control, x: float, y: float, w: float = -1.0, h: float = -1.0) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + (w if w > 0.0 else c.custom_minimum_size.x)
	c.offset_bottom = y + (h if h > 0.0 else c.custom_minimum_size.y)
	if c.get_parent() == null:
		add_child(c)

## Everything rises into place once, staggered left to right.
func _play_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	await get_tree().process_frame
	var i: int = 0
	for child in get_children():
		if child is Control and child != _hint:
			MenuUI.pop_in(child, 0.035 * i)
			i += 1
