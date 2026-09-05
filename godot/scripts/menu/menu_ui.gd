class_name MenuUI
## The menu's design system: a printed game program and a gym scoreboard.
##
## Everything is authored in "stage pixels" — a 1920x1080 coordinate space that
## MenuShell scales to the device — and drawn with flat fills and hairline
## rules. Nothing here paints a gradient, a bevel, a drop shadow or a rounded
## corner, and that is the whole point: the previous system painted all four
## onto every plate, which is the mobile-brawler house style and read as one.
##
## The two references, and what each contributes:
##
##   A home-game program booklet — the roster as numbered people with a stat
##   column beside them, tiny all-caps utility labels, team colour as a solid
##   block rather than a gradient, and figures that line up down a column.
##
##   A gym scoreboard — two type sizes and almost nothing between them, colour
##   that means data (lit or not) rather than decoration, and an ink ground the
##   lit numbers sit on.
##
## Consequences worth knowing before editing:
##
## - RADIUS IS ZERO EVERYWHERE. Not "small". A single rounded corner reads as a
##   different design system, because nothing else here is round.
## - DEPTH IS HAIRLINE RULES, and only hairline rules. No shadow, no bevel, no
##   inset highlight. Adding one shadow means adding it everywhere or the one
##   element that has it looks broken, and then this is the old system again.
## - THE TYPE SCALE HAS A HOLE IN IT ON PURPOSE. Utility labels sit at 18-22 and
##   display sits at 44+, with almost nothing between. Filling the middle is
##   what makes an interface read as evenly loud.
## - Display type is Anton, labels and body are Barlow Condensed. One condensed
##   width family throughout; the old Lilita One is the rounded mobile-game face
##   this replaces, and Nunito is the soft body face that went with it.

# MARK: colour
#
# Ink ground, two panel steps above it, one hairline. Gold is the only colour
# with a job — earned, active, yours — and blue is the team. Everything else is
# neutral, so a lit number is the brightest thing on screen.

const INK := Color("#0a0d13")
const PANEL := Color("#111621")
const PANEL_HI := Color("#19202d")
const RULE := Color("#232b3a")
const RULE_HI := Color("#36415a")

const GOLD := Color("#f2a81c")
const GOLD_HI := Color("#ffc64d")
const GOLD_DIM := Color("#8a6412")
const GOLD_INK := Color("#1a1200")   # text sitting on gold

const BLUE := Color("#1d3fb8")
const BLUE_HI := Color("#3c6bff")
const GREEN := Color("#35a34a")
const GREEN_HI := Color("#57c96b")
const GREEN_LO := Color("#1e6b2c")
const RED := Color("#d8342b")
const GREY := Color("#3a4252")

const TEXT := Color("#f2f4f8")
const TEXT_SOFT := Color("#c3cad8")
const TEXT_DIM := Color("#8a93a6")
const TEXT_FAINT := Color("#565e70")

## Names the pre-overhaul screens still reach for. Kept as aliases so the
## surviving screens compile unchanged; new code should use the names above.
const NAVY := PANEL
const NAVY_HI := PANEL_HI
const NAVY_LO := INK
const LINE := RULE
const YELLOW := GOLD
const YELLOW_HI := GOLD_HI
const YELLOW_LO := GOLD_DIM
const CARD_HI := PANEL_HI
const CARD_LO := PANEL

# MARK: type

const FONT_DISPLAY := "res://assets/menu/fonts/Anton.woff2"
const FONT_LABEL := "res://assets/menu/fonts/BarlowCondensed-600.woff2"
const FONT_BODY := "res://assets/menu/fonts/BarlowCondensed-500.woff2"

const ICON_DIR := "res://assets/menu/svg/"

static var _fonts: Dictionary = {}
static var _boxes: Dictionary = {}
static var _icons: Dictionary = {}

static func display_font() -> Font:
	return _font(FONT_DISPLAY)

static func label_font() -> Font:
	return _font(FONT_LABEL)

static func body_font() -> Font:
	return _font(FONT_BODY)

## Kept for callers written against the old two-weight body font.
static func body_font_700() -> Font:
	return _font(FONT_LABEL)

static func _font(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]

## Figures that line up down a stat column. Barlow's default figures are
## proportional, so a column of them wanders; tabular is what makes a stat block
## read as a table rather than as a list of loose numbers.
static func _tabular(base: Font) -> FontVariation:
	var key: String = "tabular:%s" % base.resource_path
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = base
	fv.opentype_features = {"tnum": 1}
	_fonts[key] = fv
	return fv

## Letterspaced small caps — the program booklet's utility labels. Tracking is
## what lets 18px all-caps read as a deliberate label rather than as small text.
static func _spaced(base: Font, spacing: int) -> FontVariation:
	var key: String = "spaced:%s:%d" % [base.resource_path, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv

## Display type: Anton, no stroke and no shadow. The `outline` argument is
## accepted and ignored — the old system stroked every label in near-black,
## which is the single loudest tell of the house style this replaces.
static func display(text: String, size: int, color: Color = TEXT,
		_outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _tabular(display_font()))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## The tiny letterspaced all-caps label: stat names, section heads, unit
## suffixes. Deliberately small — this tier and `display` are the whole scale.
static func label(text: String, size: int = 19, color: Color = TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", _spaced(label_font(), maxi(1, size / 6)))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Running copy — ability write-ups, unlock hints. Condensed, so a two-sentence
## blurb fits a narrow column without wrapping into a paragraph.
static func body(text: String, size: int = 24, color: Color = TEXT_SOFT,
		_weight_700: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## 1,250 — every number in the menu is printed grouped.
static func fmt(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("-" + out) if n < 0 else out

# MARK: rules and blocks
#
# The only two ways anything is separated from anything else.

## A one-pixel hairline. Horizontal by default; `vertical` makes a column rule.
static func rule(color: Color = RULE, vertical: bool = false) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	if vertical:
		r.custom_minimum_size = Vector2(1, 0)
		r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		r.custom_minimum_size = Vector2(0, 1)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Flat fill, square corners, optional hairline border. This is the only box in
## the system — `plate_box` and `dark_box` below are both this with arguments.
static func flat_box(fill: Color, border: Color = Color(0, 0, 0, 0),
		margin: int = 0) -> StyleBoxFlat:
	var key: String = "%s|%s|%d" % [fill.to_html(), border.to_html(), margin]
	if _boxes.has(key):
		return _boxes[key]
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(0)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	s.set_content_margin_all(margin)
	_boxes[key] = s
	return s

## Named fills, kept keyed by the old variant names so existing callers land on
## something sensible. `radius` and `shadow` are accepted and ignored.
static func plate_colors(variant: String) -> Array:
	var fill: Color = fill_for(variant)
	return [fill, fill, fill]

static func fill_for(variant: String) -> Color:
	match variant:
		"yellow", "gold":
			return GOLD
		"green":
			return GREEN
		"blue":
			return BLUE
		"red":
			return RED
		"grey":
			return GREY
		"card":
			return PANEL
		"dark", "ink":
			return INK
		_:
			return PANEL

static func plate_box(variant: String = "navy", _radius: int = 0,
		_shadow: int = 0, margin: int = 12) -> StyleBoxFlat:
	var fill: Color = fill_for(variant)
	var border: Color = RULE if variant in ["navy", "card", "dark", "ink"] else Color(0, 0, 0, 0)
	return flat_box(fill, border, margin)

static func dark_box(_radius: int = 0, alpha: float = 0.0,
		margin: int = 14) -> StyleBoxFlat:
	return flat_box(Color(INK.r, INK.g, INK.b, maxf(alpha, 1.0)), RULE, margin)

static func panel(variant: String = "navy", radius: int = 0, shadow: int = 0,
		margin: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", plate_box(variant, radius, shadow, margin))
	return p

static func dark_panel(radius: int = 0, alpha: float = 0.0,
		margin: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", dark_box(radius, alpha, margin))
	return p

# MARK: the stat line
#
# The program booklet's own unit: a label, leader space, and a figure that lines
# up with the figure above it. Used down the home screen's flanks.

## `unit` is set small and dim beside the figure rather than folded into it, so
## the figures stay a clean column of tabular numerals you can compare down.
static func stat_row(key: String, value: String, accent: Color = TEXT,
		size: int = 40, unit: String = "") -> HBoxContainer:
	var row := hbox(8)
	var k: Label = label(key, 19, TEXT_DIM)
	k.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(k)
	row.add_child(spacer())
	var v: Label = display(value, size, accent)
	v.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(v)
	if unit != "":
		var u: Label = label(unit, 17, TEXT_FAINT)
		u.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		row.add_child(u)
	return row

## A stat line plus the hairline under it, as one block.
static func stat_line(key: String, value: String, accent: Color = TEXT,
		size: int = 40, unit: String = "") -> VBoxContainer:
	var column := vbox(6)
	column.add_child(stat_row(key, value, accent, size, unit))
	column.add_child(rule())
	return column

## A section head: letterspaced caps over a hairline, used to open a block.
static func section(text: String, color: Color = TEXT_DIM) -> VBoxContainer:
	var column := vbox(8)
	column.add_child(label(text, 19, color))
	column.add_child(rule())
	return column

# MARK: buttons

## Flat block, square, no bevel. Press sinks it 2px and dims it; that is the
## whole feedback, and it is the same on every button in the menu.
static func button(text: String, variant: String = "green", size: int = 34,
		min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", display_font())
	b.add_theme_font_size_override("font_size", size)
	var ink: Color = GOLD_INK if variant in ["yellow", "gold"] else TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(state, ink)
	var fill: Color = fill_for(variant)
	var border: Color = RULE_HI if variant in ["navy", "card", "dark", "ink"] else Color(0, 0, 0, 0)
	for state in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, flat_box(fill, border, 16))
	b.add_theme_stylebox_override("hover", flat_box(fill.lerp(TEXT, 0.10), border, 16))
	b.add_theme_stylebox_override("pressed", flat_box(fill.lerp(INK, 0.28), border, 16))
	press_feedback(b)
	return b

static func small_button(text: String, variant: String = "grey") -> Button:
	var b: Button = button(text, variant, 24)
	b.custom_minimum_size = Vector2(0, 54)
	return b

static func disabled_button(text: String) -> Button:
	var b: Button = button(text, "grey", 34)
	b.disabled = true
	b.modulate = Color(0.55, 0.55, 0.6)
	return b

## A flat text link — the bottom bar's destinations. No box at all: the label is
## the whole control, and the gold rule under it is the hover state.
static func link(text: String, size: int = 24) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.flat = true
	b.add_theme_font_override("font", _spaced(label_font(), 3))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT_DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_focus_color", TEXT)
	var clear: StyleBoxFlat = flat_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 10)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, clear)
	press_feedback(b)
	return b

static func icon_button(icon_name: String, size: float) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = icon_texture(icon_name)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(size, size)
	press_feedback(b)
	return b

static func art_button(texture: Texture2D, height: float) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = texture
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var aspect: float = 1.0
	if texture:
		aspect = float(texture.get_width()) / float(texture.get_height())
	b.custom_minimum_size = Vector2(height * aspect, height)
	press_feedback(b)
	return b

## Sink 2px and dim. The old feedback scaled the control, which needed a pivot
## and fought every container it sat in; a position offset does not.
static func press_feedback(c: BaseButton) -> void:
	c.button_down.connect(func() -> void:
		if c.disabled:
			return
		c.position.y += 2.0
		c.modulate = Color(0.82, 0.82, 0.86)
		c.set_meta("sunk", true))
	var restore := func() -> void:
		if c.get_meta("sunk", false):
			c.position.y -= 2.0
			c.set_meta("sunk", false)
		c.modulate = Color.WHITE
	c.button_up.connect(restore)
	c.mouse_exited.connect(restore)

# MARK: bars and chips

## A square meter. Track is ink with a hairline, fill is one flat colour — no
## gradient and no highlight cap, so it reads as lit rather than as glass.
static func bar(height: float, fill: Color, _fill_hi: Color = Color.WHITE) -> Panel:
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", flat_box(INK, RULE, 0))
	track.custom_minimum_size = Vector2(0, height)
	track.clip_contents = true
	var fill_panel := Panel.new()
	fill_panel.add_theme_stylebox_override("panel", flat_box(fill))
	fill_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	fill_panel.anchor_right = 0.0
	fill_panel.offset_right = 0.0
	fill_panel.offset_left = 0.0
	fill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill_panel)
	track.set_meta("fill", fill_panel)
	return track

static func set_bar(track: Panel, ratio: float, animate: bool = true) -> void:
	var fill: Panel = track.get_meta("fill")
	var target: float = clampf(ratio, 0.0, 1.0)
	if not animate or not track.is_inside_tree():
		fill.anchor_right = target
		return
	var tw := track.create_tween()
	tw.tween_property(fill, "anchor_right", target, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## A small square tag. Optionally icon + figure; on a solid fill when `filled`.
static func chip(text: String, icon_name: String, size: int = 20,
		color: Color = GOLD, filled: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
			flat_box(color, Color(0, 0, 0, 0), 6) if filled else flat_box(INK, RULE, 6))
	var row := hbox(6)
	if icon_name != "":
		row.add_child(icon(icon_name, size + 2))
	row.add_child(display(text, size, GOLD_INK if filled else color))
	p.add_child(row)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## A solid block of team colour — the program's position tag.
static func tag(text: String, fill: Color, ink: Color = TEXT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_box(fill, Color(0, 0, 0, 0), 0))
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 3)
	inner.add_theme_constant_override("margin_bottom", 3)
	inner.add_child(label(text, 18, ink))
	p.add_child(inner)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# MARK: icons
#
# Almost everything that used to be an icon is now a word. What survives is the
# handful of glyphs a label cannot replace, still resolved from svg/.

static func icon_texture(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var path: String = ICON_DIR + icon_name + ".svg"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icons[icon_name] = tex
	return tex

static func icon(icon_name: String, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(icon_name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

# MARK: layout helpers

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## A fixed gap. Spacing here is deliberately bimodal — 8-12 inside a block,
## 40-64 between blocks — so the eye groups without needing a box around each.
static func gap(size: float, vertical: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, size) if vertical else Vector2(size, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hbox(separation: int = 12) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func vbox(separation: int = 12) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func grid(columns: int, separation: int = 22) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", separation)
	g.add_theme_constant_override("v_separation", separation)
	return g

## Pin a control to a corner of its parent. Deliberately not
## set_anchors_and_offsets_preset(..., PRESET_MODE_MINSIZE): that reads a
## minimum size the node does not have until it is inside the tree, and a chip
## built before it is parented ends up stretched across its whole card.
static func pin(c: Control, right: bool, bottom: bool, margin: float = 10.0) -> void:
	c.anchor_left = 1.0 if right else 0.0
	c.anchor_right = c.anchor_left
	c.anchor_top = 1.0 if bottom else 0.0
	c.anchor_bottom = c.anchor_top
	c.offset_left = -margin if right else margin
	c.offset_right = c.offset_left
	c.offset_top = -margin if bottom else margin
	c.offset_bottom = c.offset_top
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END

static func card(variant: String = "card", _radius: int = 0,
		_shadow: int = 0) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", plate_box(variant, 0, 0, 0))
	p.clip_contents = true
	return p

static func card_body(host: Control, pad: int = 16, _shadow: int = 0) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(margin)
	return margin

## Flat backdrop for a card. The old version was a radial glow behind every
## portrait; this is a solid tone, because a glow under nine cards at once is
## nine light sources and the scoreboard has one.
static func card_backdrop(tint: Color) -> Control:
	var base := ColorRect.new()
	base.color = PANEL.lerp(tint, 0.18)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return base

## Hex string from the data files -> Color, tolerant of a missing "#".
##
## Callers mix two sources: game.json carries colours as "#57c81e", and kits.gd
## carries them as real Colors, which MenuData passes straight through. Feeding
## one of those to str() yields "(0.2, 0.88, 0.78, 1)" and "#" + that is not a
## colour name — Godot logged an error per fighter and returned black, which is
## why the roster's team blocks came out unpainted. A Color is now returned as
## itself rather than round-tripped through a string.
static func hex(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if value is Color:
		return value
	var s: String = str(value)
	if s.is_empty():
		return fallback
	return Color(s) if s.begins_with("#") else Color("#" + s)

# MARK: motion
#
# The budget is two ideas: things arrive by rising a few pixels as they fade in,
# and numbers count rather than snap (MenuShell.count_to). Nothing scales, and
# nothing overshoots — a TRANS_BACK bounce on every card is the house style this
# replaces, and at nine cards it reads as a toy.

static func pop_in(c: Control, delay: float = 0.0) -> void:
	c.modulate.a = 0.0
	var home: float = c.position.y
	c.position.y = home + 10.0
	var tw := c.create_tween()
	tw.set_parallel()
	tw.tween_property(c, "modulate:a", 1.0, 0.16).set_delay(delay)
	tw.tween_property(c, "position:y", home, 0.20).set_delay(delay) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

static func stagger(container: Node, step: float = 0.03) -> void:
	var i: int = 0
	for child in container.get_children():
		if child is Control:
			pop_in(child, i * step)
			i += 1
