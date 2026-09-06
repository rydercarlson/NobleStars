class_name HomeScreen
extends Control
## The home screen: a game programme's roster page, laid out in five zones.
##
##   top-left      who you are — avatar, name, trophies and matches
##   top-right     coins and gems as a readout, then the menu's three bars
##   flanks        the selected fighter's numbers (left) and abilities (right)
##   bottom-left   the four destinations — a nav bar owned by MenuShell
##   bottom-right  the mode plate and PLAY, one gap apart, on one baseline
##
## Two decisions worth not undoing:
##
## HOME IS ALSO THE DETAIL SCREEN. Everything the old BrawlerDetailScreen showed
## — stats, attack and Super write-ups, rank and trophies — is on the flanks,
## live, for whoever is selected. That is what lets the roster be a plain picker
## that selects and returns instead of a grid that opens a card that has a
## SELECT button on it, and it takes choosing a fighter from five taps to two.
##
## THE FLANKS ARE WHY THERE IS NO DEAD SPACE. A single figure centred on a
## 1920-wide stage leaves two empty thirds, which is exactly the gap Brawl
## Stars fills with columns of icon buttons. Filling them with the selected
## fighter's own data instead means the width carries content rather than
## navigation — and it gets better, not worse, as the stage widens on a phone,
## because MenuShell._fit_stage hands the extra width to the flanks.
##
## Nothing is drawn around the fighter but the one hint under his feet, and
## there are no rules: the zones are separated by where they sit.

var menu: MenuShell

const MARGIN_X := 68.0
const TOP_Y := 34.0
const FLANK_W := 460.0
const FLANK_TOP := 176.0
const FLANK_H := 700.0
## The bottom row: PLAY and the mode plate share this baseline with the nav.
const BOTTOM_INSET := 44.0
const PLAY_SIZE := Vector2(380, 110)
const MODE_SIZE := Vector2(340, 110)
const PLAY_GAP := 14.0
## PLAY sits a touch further from the right edge than the flank does, so the
## corner is not crowded on a phone with rounded glass.
const PLAY_RIGHT_INSET := MARGIN_X + 16.0
## Where the fighter's feet meet the ground on the stage, for the hint.
const FEET_Y := 866.0

var _name_label: Label
var _record_label: Label
var _left_flank: VBoxContainer
var _right_flank: VBoxContainer
var _mode_name: Label
var _mode_sub: Label
var _mode_flag: ColorRect
var _hint: Label
var _intro_done := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_flanks()
	_build_bottom_right()
	_build_hint()
	refresh()
	menu.brawler_view.tapped.connect(_on_brawler_tapped)
	_play_intro()

# MARK: top bar

func _build_top_bar() -> void:
	# Who you are: the avatar badge in the slot a pushed screen keeps its back
	# square in, so the top-left corner means the same thing on every screen.
	var identity := MenuUI.hbox(18)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(identity, MARGIN_X, TOP_Y, 760, MenuUI.SQUARE)
	var badge: TextureRect = MenuUI.pack_icon("avatar", MenuUI.SQUARE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(badge)
	var words := MenuUI.vbox(0)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(words)
	_name_label = MenuUI.display("GUEST", 44)
	words.add_child(_name_label)
	_record_label = MenuUI.label("0 TROPHIES", 24, MenuUI.TEXT_DIM)
	words.add_child(_record_label)

	# Coins, gems, then the menu — the readout is information and the square
	# is the only thing up here that presses.
	var right := MenuUI.hbox(30)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -760
	right.offset_right = -MARGIN_X
	right.offset_top = TOP_Y
	right.offset_bottom = TOP_Y + MenuUI.SQUARE
	add_child(right)
	right.add_child(MenuUI.spacer())
	var money: HBoxContainer = menu.currency_readout()
	money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(money)
	right.add_child(MenuUI.gap(6))
	var settings: Button = MenuUI.square_button("menu")
	settings.pressed.connect(func() -> void:
		menu.sfx("click")
		MenuPopups.settings(menu))
	right.add_child(settings)

# MARK: flanks

func _build_flanks() -> void:
	_left_flank = MenuUI.vbox(0)
	_left_flank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_left_flank, MARGIN_X, FLANK_TOP, FLANK_W, FLANK_H)

	_right_flank = MenuUI.vbox(0)
	_right_flank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_flank.anchor_left = 1.0
	_right_flank.anchor_right = 1.0
	_right_flank.offset_left = -MARGIN_X - FLANK_W
	_right_flank.offset_right = -MARGIN_X
	_right_flank.offset_top = FLANK_TOP
	_right_flank.offset_bottom = FLANK_TOP + FLANK_H
	add_child(_right_flank)

## Who he is, and the five numbers that decide every fight. These come from
## kits.gd through MenuData, so the menu is quoting the same figures the match
## runs on rather than a copy in the JSON that can drift from them.
func _fill_left(b: Dictionary, index: int) -> void:
	for child in _left_flank.get_children():
		child.queue_free()
	var stats: Dictionary = b.get("stats", {})

	var head := MenuUI.hbox(14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(MenuUI.display("%02d" % index, 40, MenuUI.GOLD))
	var role: PanelContainer = MenuUI.tag(str(b.get("role", "")),
			MenuUI.hex(b.get("color"), MenuUI.BLUE))
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(role)
	_left_flank.add_child(head)
	_left_flank.add_child(MenuUI.gap(4, true))

	var name_label: Label = MenuUI.display(str(b.get("name", "")).to_upper(), 84)
	_left_flank.add_child(name_label)
	var title: Label = MenuUI.label(str(b.get("title", "")), 26, MenuUI.TEXT_DIM)
	_left_flank.add_child(title)

	_left_flank.add_child(MenuUI.gap(34, true))
	_left_flank.add_child(MenuUI.section("ATTRIBUTES"))
	_left_flank.add_child(MenuUI.gap(8, true))
	for row: Array in [["HEALTH", MenuUI.fmt(int(stats.get("health", 0))), ""],
			["DAMAGE", MenuUI.fmt(int(stats.get("damage", 0))), ""],
			["SPEED", "%.1f" % float(stats.get("speed_value", 0.0)), "M/S"],
			["RANGE", "%.1f" % float(stats.get("range_value", 0.0)), "TILES"],
			["RELOAD", "%.2f" % float(stats.get("reload_value", 0.0)), "SEC"]]:
		_left_flank.add_child(MenuUI.stat_line(str(row[0]), str(row[1]), MenuUI.TEXT,
				46, str(row[2])))
		_left_flank.add_child(MenuUI.gap(6, true))

## What he does, and what you have done with him. The write-ups are cards in
## all but the box: a head, a name, a paragraph, and room under each for the
## ability preview that is coming.
func _fill_right(b: Dictionary) -> void:
	for child in _right_flank.get_children():
		child.queue_free()
	var id: String = str(b.get("id", ""))
	var trophies: int = SaveGame.brawler_trophies(id)
	var rank: int = clampi(int(floor(sqrt(float(trophies) / 4.0))) + 1, 1, 35)

	for ability: Array in [["ATTACK", b.get("attack", {})],
			["SUPER", b.get("super", {})]]:
		var data: Dictionary = ability[1]
		if data.is_empty():
			continue
		_right_flank.add_child(MenuUI.section(str(ability[0])))
		_right_flank.add_child(MenuUI.display(str(data.get("name", "")).to_upper(), 36))
		_right_flank.add_child(MenuUI.gap(2, true))
		var text: Label = MenuUI.wrap(MenuUI.body(str(data.get("text", "")), 26,
				MenuUI.TEXT_DIM))
		text.add_theme_constant_override("line_spacing", 2)
		_right_flank.add_child(text)
		_right_flank.add_child(MenuUI.gap(22, true))

	# The record as one row of three figures rather than three stat lines, so
	# the two write-ups above get the height.
	_right_flank.add_child(MenuUI.section("RECORD"))
	_right_flank.add_child(MenuUI.gap(4, true))
	var record := MenuUI.hbox(0)
	record.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_flank.add_child(record)
	for figure: Array in [["TROPHIES", MenuUI.fmt(trophies), MenuUI.GOLD],
			["RANK", str(rank), MenuUI.TEXT],
			["POWER", str(SaveGame.brawler_power(id)), MenuUI.TEXT]]:
		var column := MenuUI.vbox(0)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(MenuUI.display(str(figure[1]), 40, figure[2]))
		column.add_child(MenuUI.label(str(figure[0]), 22, MenuUI.TEXT_FAINT))
		record.add_child(column)

# MARK: bottom right

## The mode plate and PLAY: one gap apart, the same height, on the baseline the
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
	var play: Button = MenuUI.button("PLAY", "gold", 66, PLAY_SIZE)
	play.pressed.connect(func() -> void:
		menu.sfx("play")
		menu.start_match())
	right.add_child(play)

## The mode plate: a block of the mode's colour, its name, and the note that it
## is a choice. No card art — the old plate carried a baked illustration of a
## tropical island for Nobles Cup, which is a school field.
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
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	_mode_flag = ColorRect.new()
	_mode_flag.color = MenuUI.GREEN
	_mode_flag.custom_minimum_size = Vector2(8, 0)
	_mode_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_mode_flag)
	var text := MenuUI.vbox(0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	_mode_sub = MenuUI.label("EVENT", 22, MenuUI.TEXT_FAINT)
	_mode_name = MenuUI.display("SHOWDOWN", 36)
	text.add_child(_mode_sub)
	text.add_child(_mode_name)
	row.add_child(MenuUI.spacer())
	var chevron: Label = MenuUI.display("›", 46, MenuUI.TEXT_DIM)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)
	row.add_child(MenuUI.gap(16))
	return b

## The one thing near the fighter: what touching him does, right under his feet.
func _build_hint() -> void:
	_hint = MenuUI.label("TAP TO ATTACK   ·   DRAG TO SPIN", 24, MenuUI.TEXT_FAINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.offset_left = -320
	_hint.offset_right = 320
	_hint.offset_top = FEET_Y
	_hint.offset_bottom = FEET_Y + 34
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
	_record_label.text = "%s TROPHIES   ·   %s MATCHES" % [
			MenuUI.fmt(SaveGame.total_trophies()), MenuUI.fmt(SaveGame.matches)]

	var b: Dictionary = menu.selected_brawler()
	if not b.is_empty():
		var index: int = 1
		for i in MenuData.brawlers.size():
			if str(MenuData.brawlers[i].id) == str(b.id):
				index = i + 1
				break
		_fill_left(b, index)
		_fill_right(b)

	var mode: Dictionary = menu.selected_mode()
	if not mode.is_empty():
		_mode_flag.color = MenuUI.hex(mode.get("color"), MenuUI.GREEN)
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
