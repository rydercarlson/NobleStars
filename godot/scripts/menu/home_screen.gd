class_name HomeScreen
extends Control
## The home screen, to Jackson's 6 Sep mockup: five zones over a lit stage.
##
##   top-left      who you are — name, trophies and matches
##   top-right     coins and gems with their names, a divider, the menu
##   left flank    number, role, name, title, and five stats as bars
##   right flank   two ability cards with medallions, then the record card
##   bottom-left   the four destinations — a nav bar owned by MenuShell
##   bottom-right  the mode plate and PLAY, side by side, on one baseline
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

var menu: MenuShell

const MARGIN_X := 60.0
const TOP_Y := 34.0
const LEFT_W := 520.0
const RIGHT_W := 546.0
const FLANK_TOP := 160.0
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

## Stat bars: the glyph, the colour, and whether a lower figure is the better
## one (reload), in which case the bar shows quickness rather than the number.
const STAT_ROWS := [
	["health", "HEALTH", "stat_health", Color("#57c96b"), "", false],
	["damage", "DAMAGE", "stat_damage", Color("#f2a81c"), "", false],
	["speed_value", "SPEED", "stat_speed", Color("#3c9bff"), "M/S", false],
	["range_value", "RANGE", "stat_range", Color("#9b5cff"), "TILES", false],
	["reload_value", "RELOAD", "stat_reload", Color("#5fd4f0"), "SEC", true],
]

var _name_label: Label
var _record_label: Label
var _left_flank: VBoxContainer
var _right_flank: VBoxContainer
var _mode_name: Label
var _mode_sub: Label
var _mode_flag: ColorRect
var _hint: Label
var _intro_done := false
var _best: Dictionary = {}   # stat key -> the roster's best figure
var _worst: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_measure_roster()
	_build_top_bar()
	_build_flanks()
	_build_bottom_right()
	_build_hint()
	refresh()
	menu.brawler_view.tapped.connect(_on_brawler_tapped)
	_play_intro()

## The roster's best and worst of each stat, so a bar is a comparison.
func _measure_roster() -> void:
	for row: Array in STAT_ROWS:
		var key: String = str(row[0])
		var lo: float = INF
		var hi: float = -INF
		for b in MenuData.brawlers:
			var v: float = float((b.get("stats", {}) as Dictionary).get(key, 0.0))
			lo = minf(lo, v)
			hi = maxf(hi, v)
		_best[key] = hi if hi > -INF else 1.0
		_worst[key] = lo if lo < INF else 0.0

# MARK: top bar

func _build_top_bar() -> void:
	var identity := MenuUI.vbox(0)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(identity, MARGIN_X, TOP_Y, 760, 90)
	_name_label = MenuUI.display("GUEST", 46)
	identity.add_child(_name_label)
	_record_label = MenuUI.label("0 TROPHIES", 24, MenuUI.TEXT_DIM)
	identity.add_child(_record_label)

	# Coins, gems, a divider, then the menu — the readout is information and
	# the bars are the only thing up here that presses.
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
	var settings: Button = MenuUI.menu_button()
	settings.pressed.connect(func() -> void:
		menu.sfx("click")
		MenuPopups.settings(menu))
	right.add_child(settings)

# MARK: flanks

func _build_flanks() -> void:
	_left_flank = MenuUI.vbox(0)
	_left_flank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_left_flank, MARGIN_X, FLANK_TOP, LEFT_W, 720)

	_right_flank = MenuUI.vbox(20)
	_right_flank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_flank.anchor_left = 1.0
	_right_flank.anchor_right = 1.0
	_right_flank.offset_left = -MARGIN_X - RIGHT_W
	_right_flank.offset_right = -MARGIN_X
	_right_flank.offset_top = FLANK_TOP
	_right_flank.offset_bottom = FLANK_TOP + 720
	add_child(_right_flank)

## Who he is, and the five numbers that decide every fight, each as a bar
## against the roster's best. The figures come from kits.gd through MenuData,
## so the menu is quoting the same numbers the match runs on.
func _fill_left(b: Dictionary, index: int) -> void:
	for child in _left_flank.get_children():
		child.queue_free()
	var stats: Dictionary = b.get("stats", {})

	var head := MenuUI.hbox(14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(MenuUI.display("%02d" % index, 44, MenuUI.GOLD))
	var role: PanelContainer = MenuUI.tag(str(b.get("role", "")),
			MenuUI.hex(b.get("color"), MenuUI.BLUE), MenuUI.INK)
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(role)
	_left_flank.add_child(head)

	var name_label: Label = MenuUI.display(str(b.get("name", "")).to_upper(), 104)
	_left_flank.add_child(name_label)
	_left_flank.add_child(MenuUI.gap(2, true))
	var title: Label = MenuUI.label(str(b.get("title", "")), 28, MenuUI.TEXT_SOFT)
	_left_flank.add_child(title)

	_left_flank.add_child(MenuUI.gap(30, true))
	_left_flank.add_child(MenuUI.label("ATTRIBUTES", 24, MenuUI.TEXT_DIM))
	_left_flank.add_child(MenuUI.gap(8, true))
	var head_rule: ColorRect = MenuUI.rule(MenuUI.RULE_HI)
	head_rule.custom_minimum_size = Vector2(LEFT_W - 40, 1)
	head_rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left_flank.add_child(head_rule)
	_left_flank.add_child(MenuUI.gap(10, true))
	for row: Array in STAT_ROWS:
		var key: String = str(row[0])
		var v: float = float(stats.get(key, 0.0))
		var ratio: float
		if bool(row[5]):
			# quickness: the roster's fastest reload fills the bar
			var lo: float = float(_worst[key])
			var hi: float = float(_best[key])
			ratio = 1.0 - (v - lo) / maxf(0.001, hi - lo) if hi > lo else 1.0
			ratio = 0.18 + ratio * 0.82
		else:
			ratio = v / maxf(0.001, float(_best[key]))
		var text: String
		match key:
			"health", "damage":
				text = MenuUI.fmt(int(v))
			"reload_value":
				text = "%.2f" % v
			_:
				text = "%.1f" % v
		_left_flank.add_child(MenuUI.stat_bar_row(str(row[2]), str(row[1]), text,
				str(row[4]), ratio, row[3], LEFT_W - 52 - 18 - 200))
		_left_flank.add_child(MenuUI.gap(12, true))

## What he does, and what you have done with him: two ability cards, each with
## a medallion, and the record.
func _fill_right(b: Dictionary) -> void:
	for child in _right_flank.get_children():
		child.queue_free()
	var id: String = str(b.get("id", ""))
	var trophies: int = SaveGame.brawler_trophies(id)
	var rank: int = clampi(int(floor(sqrt(float(trophies) / 4.0))) + 1, 1, 35)

	_right_flank.add_child(_ability_card("ATTACK", b.get("attack", {}), MenuUI.BLUE_HI,
			MenuUI.PANEL))
	_right_flank.add_child(_ability_card("SUPER", b.get("super", {}), MenuUI.GREEN_HI,
			Color("#0f1c17")))

	var record := PanelContainer.new()
	record.add_theme_stylebox_override("panel", MenuUI.card_box(MenuUI.PANEL, MenuUI.RULE_HI, 22))
	record.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := MenuUI.vbox(0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	record.add_child(column)
	column.add_child(MenuUI.label("RECORD", 24, MenuUI.TEXT_DIM))
	column.add_child(MenuUI.gap(6, true))
	column.add_child(MenuUI.record_row("trophy", "TROPHIES", MenuUI.fmt(trophies), MenuUI.GOLD))
	column.add_child(MenuUI.rule(MenuUI.RULE))
	column.add_child(MenuUI.record_row("rank", "RANK", str(rank)))
	column.add_child(MenuUI.rule(MenuUI.RULE))
	column.add_child(MenuUI.record_row("power", "POWER", str(SaveGame.brawler_power(id))))
	_right_flank.add_child(record)

## One ability as a card: medallion on the left, then the tier word in the
## accent colour, the name, and the first sentence of the write-up.
func _ability_card(tier: String, data: Dictionary, accent: Color, fill: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.card_box(fill, accent.lerp(MenuUI.RULE_HI, 0.45), 22))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := MenuUI.hbox(24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var glyph: String = "style_" + str(data.get("style", "pellets"))
	var badge: PanelContainer = MenuUI.medallion(glyph, accent)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var words := MenuUI.vbox(0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	words.add_child(MenuUI.label(tier, 22, accent))
	words.add_child(MenuUI.display(str(data.get("name", "")).to_upper(), 42))
	words.add_child(MenuUI.gap(4, true))
	var text: Label = MenuUI.wrap(MenuUI.body(_first_sentence(str(data.get("text", ""))), 24,
			MenuUI.TEXT_SOFT))
	text.add_theme_constant_override("line_spacing", 2)
	words.add_child(text)
	return card

static func _first_sentence(text: String) -> String:
	var cut: int = text.find(". ")
	return text if cut < 0 else text.substr(0, cut + 1)

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
	_mode_sub = MenuUI.label("EVENT", 20, MenuUI.TEXT_FAINT)
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
	_hint = MenuUI.label("TAP TO ATTACK   ·   DRAG TO SPIN", 22, MenuUI.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = FEET_FRAC
	_hint.anchor_bottom = FEET_FRAC
	_hint.offset_left = -320
	_hint.offset_right = 320
	_hint.offset_top = 36
	_hint.offset_bottom = 70
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
