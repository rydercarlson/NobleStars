class_name VersusScreen
extends Control
## The pre-match screen, laid out the way Brawl Stars does it: the arena stays
## live underneath, dimmed; the other side's fighters are a row of tall
## portrait cards across the top on red, yours across the bottom on blue with
## your own card raised and outlined; a big VS sits between the rows, the mode
## and map in the top-left corner, and "Match starts in N" counts down in the
## bottom-right. In the last stretch the cards clear and the mode's name and
## objective take the screen, the way the map fly-over does, and the battle
## sting plays as the screen lands.
##
## Showdown lists all ten solo fighters, five a row, with only your card blue.
## Nobles Cup lists the two teams of three.

const STING := "res://assets/menu/audio/battle_start.mp3"
const MODE_TITLE := {"showdown": "SHOWDOWN", "cup": "NOBLES CUP"}
const MODE_SUB := {"showdown": "Solo · Castle Courtyard", "cup": "3v3 · Lower Field"}
const MODE_GOAL := {"showdown": "Be the last one standing", "cup": "Score three goals to win"}
## The mode reads as a block of its own colour, the same way it does on the home
## plate and the events cards. It used to be an illustrated badge, from art that
## went with the old menu; it sat beside the mode's name and subtitle in both
## places it appeared, so it was saying a third time what the type already said.
## Matches the colours in data/game.json.
const MODE_COLOR := {"showdown": Color("#57c81e"), "cup": Color("#2f7bff")}
const BLUE := Color("#1f4fdc")
const BLUE_LO := Color("#12308f")
const RED := Color("#d23a2f")
const RED_LO := Color("#8c1f18")
const GREY := Color("#3b425c")
const GREY_LO := Color("#232838")
const INK := Color("#10131f")

var _count: Label
var _count_plate: Control
var _cards: Array[Control] = []
var _vs: Control
var _chip: Control
var _intro: Control
var _bar_fill: ColorRect
var _mode := "showdown"
var _intro_shown := false

func build(mode: String, top: Array, bottom: Array, you: Node) -> void:
	_mode = mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.09, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var vp: Vector2 = get_viewport_rect().size
	_chip = _mode_chip(mode)
	_chip.position = Vector2(24, 18)
	add_child(_chip)

	# Card rows. Each row is centred, the top row nudged right and the bottom
	# row nudged left like the reference, so the VS reads as a diagonal clash.
	var n_top: int = top.size()
	var n_bot: int = bottom.size()
	var per_row: int = maxi(n_top, n_bot)
	# Ten-card Showdown rows run narrower and slide further apart, so the
	# bottom row clears the counter and the top row clears the mode chip.
	var card_w: float = 236.0 if per_row <= 3 else 156.0
	var card_h: float = 208.0 if per_row <= 3 else 150.0
	var gap: float = 14.0 if per_row <= 3 else 12.0
	var row_w_top: float = n_top * card_w + (n_top - 1) * gap
	var row_w_bot: float = n_bot * card_w + (n_bot - 1) * gap
	var shift: float = 40.0 if per_row <= 3 else 72.0
	var top_y: float = 78.0 if per_row <= 3 else 102.0
	var bot_y: float = vp.y - card_h - 44.0
	for i in n_top:
		var c: Control = _card(top[i], you, card_w, card_h, top[i] == you)
		c.position = Vector2((vp.x - row_w_top) * 0.5 + shift + i * (card_w + gap), top_y)
		add_child(c)
		_cards.append(c)
		_slide_in(c, Vector2(0, -60), 0.05 * i)
	for i in n_bot:
		var c2: Control = _card(bottom[i], you, card_w, card_h, bottom[i] == you)
		var y: float = bot_y - (14.0 if bottom[i] == you else 0.0)
		c2.position = Vector2((vp.x - row_w_bot) * 0.5 - shift + i * (card_w + gap), y)
		add_child(c2)
		_cards.append(c2)
		_slide_in(c2, Vector2(0, 60), 0.05 * i + 0.1)

	_vs = MenuUI.display("VS", 84, Color.WHITE, 12)
	_vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vs.size = Vector2(200, 100)
	_vs.position = Vector2((vp.x - 200) * 0.5, (top_y + card_h + bot_y) * 0.5 - 50)
	_vs.pivot_offset = Vector2(100, 50)
	_vs.rotation_degrees = -8.0
	add_child(_vs)
	_vs.scale = Vector2(2.2, 2.2)
	_vs.modulate.a = 0.0
	var vst := _vs.create_tween()
	vst.tween_interval(0.25)
	vst.tween_property(_vs, "modulate:a", 1.0, 0.12)
	vst.parallel().tween_property(_vs, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_count_plate = _counter()
	_count_plate.position = Vector2(vp.x - 250 - 24, vp.y - 84 - 30)
	add_child(_count_plate)

	# The thin loader across the bottom edge.
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.18)
	bar.position = Vector2(vp.x * 0.3, vp.y - 12)
	bar.size = Vector2(vp.x * 0.4, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(1, 1, 1, 0.9)
	_bar_fill.position = bar.position
	_bar_fill.size = Vector2(0, 5)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_fill)

	_intro = _mode_intro(mode)
	_intro.visible = false
	add_child(_intro)

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	_play_sting()

## Progress 0..1 through the whole pre-match; the count is the seconds left on
## the card stretch, and past `intro_at` the rows clear for the mode title.
func update(count: int, progress: float, intro: bool) -> void:
	if _count != null and _count.text != str(count) and not intro:
		_count.text = str(count)
		_count.pivot_offset = _count.size * 0.5
		_count.scale = Vector2(1.4, 1.4)
		var tw := _count.create_tween()
		tw.tween_property(_count, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _bar_fill != null:
		_bar_fill.size.x = get_viewport_rect().size.x * 0.4 * clampf(progress, 0.0, 1.0)
	if intro and not _intro_shown:
		_intro_shown = true
		_show_intro()

func dismiss() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)

# MARK: pieces

func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _play_sting() -> void:
	if not ResourceLoader.exists(STING):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(STING)
	p.volume_db = -4.0
	p.bus = "Master"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _slide_in(c: Control, from: Vector2, delay: float) -> void:
	var target: Vector2 = c.position
	c.position = target + from
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "position", target, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate:a", 1.0, 0.18)

func _panel(color: Color, radius: int, border: Color = INK, width: int = 3) -> Panel:
	var p := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(radius)
	st.set_border_width_all(width)
	st.border_color = border
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## One fighter card: team-coloured plate, a big portrait bleeding off the top
## edge, the player's name on a dark footer with the kit's title under it.
func _card(f: Node, you: Node, w: float, h: float, mine: bool) -> Control:
	var kit: Dictionary = f.get("kit") if f.get("kit") != null else {}
	var id: String = str(kit.get("name", "")).to_lower()
	var team_blue: bool = mine or (_mode == "cup" and you != null and f.get("team") == you.get("team"))
	var hi: Color = BLUE if team_blue else (RED if _mode == "cup" else GREY)
	var lo: Color = BLUE_LO if team_blue else (RED_LO if _mode == "cup" else GREY_LO)
	var card := _panel(lo, 14, Color.WHITE if mine else INK, 4 if mine else 3)
	card.size = Vector2(w, h)
	card.clip_contents = true
	# a lighter band up top so the plate reads as lit from above
	var band := ColorRect.new()
	band.color = Color(hi.r, hi.g, hi.b, 0.85)
	band.position = Vector2(3, 3)
	band.size = Vector2(w - 6, h * 0.62)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(band)
	var face := Control.new()
	face.position = Vector2(0, 0)
	face.size = Vector2(w, h * 0.72)
	face.clip_contents = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(face)
	var tex: Texture2D = MenuData.portrait(id) if id != "" else null
	if tex != null:
		var pr := TextureRect.new()
		pr.texture = tex
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.position = Vector2(-w * 0.12, -h * 0.02)
		pr.size = Vector2(w * 1.24, h * 0.86)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(pr)
	else:
		var initial: Label = MenuUI.display(str(kit.get("name", "?")).substr(0, 1), int(h * 0.42),
				kit.get("color", Color.WHITE), 8)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(initial)
	var footer := ColorRect.new()
	footer.color = Color(0.06, 0.07, 0.13, 0.94)
	footer.position = Vector2(3, h * 0.72)
	footer.size = Vector2(w - 6, h * 0.28 - 3)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(footer)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -3)
	who.position = Vector2(10, h * 0.72 + 4)
	who.size = Vector2(w - 20, h * 0.28 - 8)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(who)
	var big: bool = w > 200
	var name_l: Label = MenuUI.display(str(f.get("display_name")).to_upper(), 22 if big else 17,
			Color("#ffe37a") if mine else Color.WHITE, 4)
	name_l.clip_text = true
	who.add_child(name_l)
	var title: String = str(kit.get("name", ""))
	var b: Dictionary = MenuData.brawler(id) if id != "" else {}
	if not b.is_empty() and str(b.get("title", "")) != "":
		title = str(b.get("title"))
	var title_l: Label = MenuUI.body(title, 15 if big else 13, Color(0.8, 0.84, 0.95))
	title_l.clip_text = true
	who.add_child(title_l)
	return card

func _mode_chip(mode: String) -> Control:
	var chip := _panel(Color(0.08, 0.09, 0.16, 0.92), 12)
	chip.size = Vector2(360, 74)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var flag := ColorRect.new()
	flag.color = MODE_COLOR.get(mode, MenuUI.GREEN)
	flag.custom_minimum_size = Vector2(7, 52)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(flag)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(MenuUI.display(str(MODE_TITLE.get(mode, mode.to_upper())), 30, Color.WHITE, 5))
	text.add_child(MenuUI.body(str(MODE_SUB.get(mode, "")), 17, Color(0.8, 0.84, 0.95)))
	return chip

func _counter() -> Control:
	var plate := _panel(Color(0.08, 0.09, 0.16, 0.92), 14)
	plate.size = Vector2(250, 84)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var starts: Label = MenuUI.body("Match\nstarts in", 20, Color(0.85, 0.87, 0.95))
	starts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	starts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	starts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(starts)
	_count = MenuUI.display("5", 66, Color.WHITE, 8)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_count)
	return plate

## The mode's name and objective, centred, for the fly-over stretch.
func _mode_intro(mode: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flag := ColorRect.new()
	flag.color = MODE_COLOR.get(mode, MenuUI.GREEN)
	flag.custom_minimum_size = Vector2(150, 9)
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(flag)
	box.add_child(MenuUI.gap(10, true))
	var title: Label = MenuUI.display(str(MODE_TITLE.get(mode, mode.to_upper())), 64, Color.WHITE, 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var goal: Label = MenuUI.display(str(MODE_GOAL.get(mode, "")), 28, Color("#ffe37a"), 5)
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(goal)
	return box

func _show_intro() -> void:
	for c: Control in _cards:
		var tw: Tween = c.create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.22)
	for c: Control in [_vs, _chip, _count_plate]:
		if c != null:
			var tw2: Tween = c.create_tween()
			tw2.tween_property(c, "modulate:a", 0.0, 0.22)
	_intro.visible = true
	_intro.modulate.a = 0.0
	_intro.scale = Vector2(0.8, 0.8)
	_intro.pivot_offset = _intro.size * 0.5
	var tw3 := _intro.create_tween()
	tw3.tween_property(_intro, "modulate:a", 1.0, 0.2)
	tw3.parallel().tween_property(_intro, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
