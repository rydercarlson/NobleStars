class_name BrawlerScreen
extends MenuScreen
## One fighter's page: who they are, what they do, what you have done with them,
## and the only place their power level is bought.
##
## *New 7 Sep 2026, from Jackson's notes.* Everything here used to live on the
## home screen's flanks, on the argument that making home the detail view saved
## a screen and took choosing a fighter from five taps to two. What it actually
## did was put five stat bars, two ability write-ups and a record card on the
## lobby permanently — so the lobby was never quiet, and the record read as
## *your* record rather than as this fighter's, because nothing around it said
## whose it was. Both problems are the same problem: **information belongs on
## the screen where you are making the decision it informs.** You read stats
## when you are choosing a fighter, not while you are picking a mode.
##
## Reached by tapping a roster tile's picture — the SELECT button on the tile
## picks the fighter without coming here, so choosing and studying are two
## different gestures.

const LEFT_W := 620.0

var brawler: Dictionary = {}

## Stat rows, as home's flanks had them, plus POWER — which is not a record,
## because you cannot lose it. It is a property of the fighter like the rest.
const STAT_ROWS := [
	["health", "HEALTH", "stat_health", Color("#57c96b"), "", false],
	["damage", "DAMAGE", "stat_damage", Color("#f2a81c"), "", false],
	["speed_value", "SPEED", "stat_speed", Color("#3c9bff"), "M/S", false],
	["range_value", "RANGE", "stat_range", Color("#9b5cff"), "TILES", false],
	["reload_value", "RELOAD", "stat_reload", Color("#5fd4f0"), "SEC", true],
]

var _best: Dictionary = {}
var _worst: Dictionary = {}

func _build() -> void:
	screen_name = "brawler"
	if brawler.is_empty():
		brawler = menu.selected_brawler()
	_measure_roster()
	var id: String = str(brawler.get("id", ""))
	topbar(str(brawler.get("name", "FIGHTER")), str(brawler.get("title", "")))

	var column: VBoxContainer = scroll_content(0)
	var row := MenuUI.hbox(28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	var left := MenuUI.vbox(16)
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	row.add_child(left)
	left.add_child(_identity())
	left.add_child(_record(id))

	var right := MenuUI.vbox(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(_attributes(id))
	right.add_child(_ability_card("ATTACK", brawler.get("attack", {}), MenuUI.BLUE_HI,
			MenuUI.PANEL))
	right.add_child(_ability_card("SUPER", brawler.get("super", {}), MenuUI.GREEN_HI,
			Color("#0f1c17")))
	column.add_child(MenuUI.gap(20, true))

func _measure_roster() -> void:
	for stat_row: Array in STAT_ROWS:
		var key: String = str(stat_row[0])
		var lo := INF
		var hi := -INF
		for b in MenuData.brawlers:
			var v: float = float((b.get("stats", {}) as Dictionary).get(key, 0.0))
			lo = minf(lo, v)
			hi = maxf(hi, v)
		_best[key] = hi if hi > -INF else 1.0
		_worst[key] = lo if lo < INF else 0.0

# MARK: identity

## The picture, then the name with the roster number and role UNDER it rather
## than above — a number floating over a name reads as a heading for it.
func _identity() -> Control:
	var color: Color = MenuUI.hex(brawler.get("color"), MenuUI.BLUE)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.card_box(MenuUI.PANEL, MenuUI.RULE_HI, 0))
	card.clip_contents = true
	var column := MenuUI.vbox(0)
	card.add_child(column)

	var ground := Panel.new()
	ground.custom_minimum_size = Vector2(0, 330)
	var box := StyleBoxFlat.new()
	box.bg_color = MenuUI.INK.lerp(color, 0.42)
	box.set_corner_radius(CORNER_TOP_LEFT, MenuUI.RADIUS)
	box.set_corner_radius(CORNER_TOP_RIGHT, MenuUI.RADIUS)
	ground.add_theme_stylebox_override("panel", box)
	column.add_child(ground)
	var art: Texture2D = MenuData.portrait(str(brawler.get("id", "")))
	if art != null:
		var face := TextureRect.new()
		face.texture = art
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.add_child(face)
	else:
		var initial: Label = MenuUI.display(str(brawler.get("name", "?")).substr(0, 1).to_upper(),
				170, MenuUI.INK.lerp(MenuUI.TEXT, 0.30))
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ground.add_child(initial)

	var body := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		body.add_theme_constant_override(side, 22)
	body.add_theme_constant_override("margin_top", 16)
	body.add_theme_constant_override("margin_bottom", 20)
	column.add_child(body)
	var text := MenuUI.vbox(6)
	body.add_child(text)
	text.add_child(MenuUI.display(str(brawler.get("name", "")).to_upper(), 76))
	var line := MenuUI.hbox(12)
	text.add_child(line)
	var number: Label = MenuUI.display("%02d" % _index(), 30, MenuUI.GOLD)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(number)
	var role: PanelContainer = MenuUI.tag(str(brawler.get("role", "")), color, MenuUI.INK)
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(role)
	text.add_child(MenuUI.gap(4, true))
	text.add_child(MenuUI.wrap(MenuUI.body(_description(), 26, MenuUI.TEXT_SOFT)))
	return card

func _index() -> int:
	for i in MenuData.brawlers.size():
		if str(MenuData.brawlers[i].id) == str(brawler.get("id", "")):
			return i + 1
	return 1

## The write-up, and a fallback that says something rather than repeating the
## role. Several fighters' JSON blurbs are one clause long and read as a second
## role tag; where that happens the kit's own attack copy carries the meaning.
func _description() -> String:
	var text: String = str(brawler.get("description", "")).strip_edges()
	var attack_text: String = str((brawler.get("attack", {}) as Dictionary).get("text", ""))
	if text.length() < 60 and attack_text != "":
		return text + ("  " if text != "" else "") + attack_text
	return text

# MARK: record

## What you have done with THIS fighter. Trophies and rank only — power level
## moved out to the attributes, because a record is a thing you can lose and a
## power level is not.
func _record(id: String) -> Control:
	var trophies: int = SaveGame.brawler_trophies(id)
	var rank: int = MenuData.rank_of(trophies)
	var span: Array = MenuData.rank_span(rank)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.card_box(MenuUI.PANEL, MenuUI.RULE_HI, 22))
	var column := MenuUI.vbox(10)
	card.add_child(column)
	column.add_child(MenuUI.label("RECORD WITH %s" % str(brawler.get("name", "")).to_upper(),
			26, MenuUI.TEXT_DIM))
	column.add_child(MenuUI.record_row("trophy", "TROPHIES", MenuUI.fmt(trophies), MenuUI.GOLD))

	# Rank as a bar, not a bare number: the bands widen as they climb, so "RANK
	# 6" alone says nothing about whether you are one match or forty from seven.
	var head := MenuUI.hbox(12)
	column.add_child(head)
	var badge: TextureRect = MenuUI.icon("rank", 34)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	var word: Label = MenuUI.label("RANK", 26, MenuUI.TEXT_SOFT)
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(word)
	head.add_child(MenuUI.spacer())
	var value: Label = MenuUI.display(str(rank), 38)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(value)
	var bar: Panel = MenuUI.bar(10, MenuUI.GOLD)
	column.add_child(bar)
	var to_next: String = "MAX RANK"
	if int(span[1]) < 0:
		MenuUI.set_bar(bar, 1.0, false)
	else:
		var lo: int = int(span[0])
		var hi: int = int(span[1])
		MenuUI.set_bar(bar, float(trophies - lo) / maxf(1.0, float(hi - lo)), false)
		to_next = "%s TO RANK %d" % [MenuUI.fmt(hi - trophies), rank + 1]
	column.add_child(MenuUI.label(to_next, 22, MenuUI.TEXT_FAINT))
	return card

# MARK: attributes

func _attributes(id: String) -> Control:
	var parts: Array = MenuUI.block("power", "ATTRIBUTES", "", 20)
	var body: VBoxContainer = parts[1]
	var stats: Dictionary = brawler.get("stats", {})
	for stat_row: Array in STAT_ROWS:
		var key: String = str(stat_row[0])
		var v: float = float(stats.get(key, 0.0))
		var ratio: float
		if bool(stat_row[5]):
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
		body.add_child(MenuUI.stat_bar_row(str(stat_row[2]), str(stat_row[1]), text,
				str(stat_row[4]), ratio, stat_row[3], 300.0))
		body.add_child(MenuUI.gap(10, true))

	# Power sits with the stats it will one day change, and buying a level is
	# the one purchase on this page.
	var power: int = SaveGame.brawler_power(id)
	var cost: int = 200 * power
	var affordable: bool = SaveGame.coins >= cost
	var row := MenuUI.hbox(18)
	body.add_child(row)
	var box: PanelContainer = MenuUI.icon_box("power")
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	var name_label: Label = MenuUI.label("POWER LEVEL", 26, MenuUI.TEXT_SOFT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	row.add_child(MenuUI.spacer())
	var figure: Label = MenuUI.display(str(power), 40)
	figure.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(figure)
	var buy: Button = MenuUI.button("UPGRADE — %s" % MenuUI.fmt(cost),
			"gold" if affordable else "grey", 24, Vector2(240, 52), 8)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = not affordable
	buy.pressed.connect(func() -> void: _upgrade(id, power, cost, buy))
	row.add_child(buy)
	return parts[0]

## Confirmed, with the price in the question. Spending 200-1,800 coins used to
## happen on one unlabelled tap from a list of nine identical rows.
func _upgrade(id: String, power: int, cost: int, button: Control) -> void:
	var name_text: String = str(brawler.get("name", "This fighter"))
	var ok: bool = await menu.confirm("Power Up",
			"Raise %s from Power %d to Power %d for %s coins. You have %s." % [
				name_text, power, power + 1, MenuUI.fmt(cost),
				MenuUI.fmt(SaveGame.coins)],
			"UPGRADE — %s" % MenuUI.fmt(cost))
	if not ok:
		return
	if not SaveGame.spend("coins", cost):
		sfx("error")
		toast("Need %s coins" % MenuUI.fmt(cost))
		return
	SaveGame.set_brawler_power(id, power + 1)
	SaveGame.save()
	menu.refresh_currencies()
	sfx("purchase")
	menu.burst(center_of(button), "coin", 10)
	toast("%s is now Power %d" % [name_text, power + 1])
	_reopen()

# MARK: abilities

## One ability: the medallion, the tier word, the name, what it hits for, and
## the write-up. The damage line is new — a card that names an ability and does
## not say what it does is the first question anyone asks of it, and the Super's
## number was not printed anywhere in the menu at all.
func _ability_card(tier: String, data: Dictionary, accent: Color, fill: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			MenuUI.card_box(fill, accent.lerp(MenuUI.RULE_HI, 0.45), 22))
	var row := MenuUI.hbox(24)
	card.add_child(row)
	var glyph: String = "style_" + str(data.get("style", "pellets"))
	var badge: PanelContainer = MenuUI.medallion(glyph, accent)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var words := MenuUI.vbox(0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	var head := MenuUI.hbox(12)
	words.add_child(head)
	head.add_child(MenuUI.label(tier, 26, accent))
	head.add_child(MenuUI.spacer())
	var damage: int = int(data.get("damage", 0))
	if damage > 0:
		var hits: int = maxi(1, int(data.get("hits", 1)))
		var figure: Label = MenuUI.display(MenuUI.fmt(damage), 34, MenuUI.TEXT)
		figure.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(figure)
		var unit: Label = MenuUI.label("DAMAGE" if hits == 1 else "x%d DAMAGE" % hits,
				22, MenuUI.TEXT_FAINT)
		unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(unit)
	words.add_child(MenuUI.display(str(data.get("name", "")).to_upper(), 42))
	words.add_child(MenuUI.gap(6, true))
	var text: Label = MenuUI.wrap(MenuUI.body(str(data.get("text", "")), 26, MenuUI.TEXT_SOFT))
	text.add_theme_constant_override("line_spacing", 2)
	words.add_child(text)
	return card

func _reopen() -> void:
	var next := BrawlerScreen.new()
	next.brawler = brawler
	menu.push_screen(next)
	close_screen()
