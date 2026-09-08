class_name MenuUI
## The menu's design system: a printed game program and a gym scoreboard.
##
## Everything is authored in "stage pixels" — a 1920x1080 coordinate space that
## MenuShell scales to the device — and drawn with flat fills inside rounded
## cards with a one-pixel edge. Nothing here paints a gradient, a bevel or a
## drop shadow: Jackson's 6 Sep mockup brought the rounded card (RADIUS) and the
## coloured stat bar back into the system, and those two are the whole budget.
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
## - RADIUS IS ONE NUMBER. Every card, box and button rounds by RADIUS (12) and
##   the small chips by RADIUS_SMALL (6); a corner that rounds by anything else
##   reads as a different design system.
## - DEPTH IS HAIRLINE RULES, and only hairline rules. No shadow, no bevel, no
##   inset highlight. Adding one shadow means adding it everywhere or the one
##   element that has it looks broken, and then this is the old system again.
## - NOTHING IN THE UTILITY TIER CLEARS APPLE'S 11 pt FLOOR, and that is
##   measured rather than feared: stage px convert at x0.364 on an iPhone 15 in
##   landscape, so 11 pt is 30.2 stage px and this tier's own ceiling is 30. All
##   39 sized utility labels were under it on 7 Sep. Roster, Shop and Events
##   hold the 26 floor below; Season and Home do not, and Season cannot without
##   showing fewer Pass tiers at once, because its page is a fixed 816 px that
##   does not scroll. That is todo 1.3, the last open P0, and it is a redesign
##   of the hole below rather than a multiply — do not fix it by bumping sizes
##   one screen at a time.
## - THE TYPE SCALE HAS A HOLE IN IT ON PURPOSE. Utility labels sit at 26-30 and
##   display sits at 44+, with almost nothing between. Filling the middle is
##   what makes an interface read as evenly loud. The utility tier used to be
##   18-22, which on a phone is 6-8 pt against Apple's 11 pt floor (todo 1.3);
##   it moved up as a tier, and display moved with it where the two met.
## - DEPTH IS SPACING, NOT LINES. The hairline rules that used to underline
##   every section head and stat row, and cap the home screen top and bottom,
##   are gone — on a phone they read as stray lines, not structure. `rule()`
##   survives for the few places a line IS the content (a progress track).
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
static func label(text: String, size: int = 26, color: Color = TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", _spaced(label_font(), maxi(1, size / 6)))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Running copy — ability write-ups, unlock hints. Condensed, so a two-sentence
## blurb fits a narrow column without wrapping into a paragraph.
static func body(text: String, size: int = 30, color: Color = TEXT_SOFT,
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

const RADIUS := 12
const RADIUS_SMALL := 6

## Flat fill, rounded by RADIUS, optional one-pixel edge. This is the only box
## in the system — `plate_box`, `dark_box` and the card helpers below are all
## this with arguments.
static func flat_box(fill: Color, border: Color = Color(0, 0, 0, 0),
		margin: int = 0, radius: int = RADIUS) -> StyleBoxFlat:
	var key: String = "%s|%s|%d|%d" % [fill.to_html(), border.to_html(), margin, radius]
	if _boxes.has(key):
		return _boxes[key]
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	s.set_content_margin_all(margin)
	_boxes[key] = s
	return s

## Named fills, keyed by the old variant names so pre-overhaul callers land on
## something sensible.
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

# MARK: blocks of type

## A section head: letterspaced caps that open a block. No rule under it —
## the gap above it is what separates blocks.
static func section(text: String, color: Color = TEXT_DIM) -> VBoxContainer:
	var column := vbox(0)
	column.add_child(label(text, 26, color))
	return column

# MARK: buttons

## Flat block, square, no bevel. Press sinks it 2px and dims it; that is the
## whole feedback, and it is the same on every button in the menu.
## `pad` is the box's content margin, and it is what sets a button's MINIMUM
## height — the display face's line box is 1.64x its size, so a 20px CLAIM at
## the default padding cannot be smaller than 65 tall no matter what min_size
## says. Pass a smaller one for a chip inside a card; 16 is the standard key.
static func button(text: String, variant: String = "green", size: int = 34,
		min_size: Vector2 = Vector2.ZERO, pad: int = 16) -> Button:
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
		b.add_theme_stylebox_override(state, _keyed(flat_box(fill, border, pad), fill))
	b.add_theme_stylebox_override("hover", _keyed(flat_box(fill.lerp(TEXT, 0.10), border, pad), fill))
	b.add_theme_stylebox_override("pressed", flat_box(fill.lerp(INK, 0.28), border, pad))
	press_feedback(b)
	return b

## A copy of a box with a darker bottom edge — the one concession to depth,
## and only on pressables, so a button reads as a key rather than as a label.
static func _keyed(base: StyleBoxFlat, fill: Color) -> StyleBoxFlat:
	var key: String = "keyed|%s|%s" % [fill.to_html(), base.bg_color.to_html()]
	if _boxes.has(key):
		return _boxes[key]
	var s: StyleBoxFlat = base.duplicate()
	s.border_width_bottom = 4
	s.border_color = fill.lerp(INK, 0.35)
	_boxes[key] = s
	return s

static func small_button(text: String, variant: String = "grey") -> Button:
	var b: Button = button(text, variant, 24)
	b.custom_minimum_size = Vector2(0, 54)
	return b

## A flat text link — the bottom bar's destinations. No box at all: the label is
## the whole control, and the gold rule under it is the hover state.
static func link(text: String, size: int = 28) -> Button:
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

## Sink 2px and dim. The old feedback scaled the control, which needed a pivot
## and fought every container it sat in; a position offset does not.
static func press_feedback(c: BaseButton) -> void:
	c.button_down.connect(func() -> void:
		if c.disabled:
			return
		# Every pressable in the menu goes through here, so this one line is the
		# whole menu's haptics. On button_down rather than pressed: the tap has
		# to arrive with the sink, not after the finger lifts.
		Haptics.fire("ui_tap")
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
	track.add_theme_stylebox_override("panel", flat_box(RULE, Color(0, 0, 0, 0), 0, int(height / 2)))
	track.custom_minimum_size = Vector2(0, height)
	track.clip_contents = true
	var fill_panel := Panel.new()
	fill_panel.add_theme_stylebox_override("panel", flat_box(fill, Color(0, 0, 0, 0), 0, int(height / 2)))
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

## A solid block of team colour — the program's position tag.
static func tag(text: String, fill: Color, ink: Color = TEXT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_box(fill, Color(0, 0, 0, 0), 0, RADIUS_SMALL))
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 3)
	inner.add_theme_constant_override("margin_bottom", 3)
	inner.add_child(label(text, 22, ink))
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

## The profile icon pack (`assets/menu/profile/`): coin, gem, trophy, avatar,
## shop, pass, shield, bulldog, dagger — 256 px PNGs with clean alpha, used
## where a word would be slower to read than a picture: the currency readout,
## the nav tabs, the identity block. Falls back to the svg glyph of the same
## name, so callers need not know which folder a name lives in.
const PACK_DIR := "res://assets/menu/profile/"

static func pack_texture(icon_name: String) -> Texture2D:
	var key: String = "pack:" + icon_name
	if _icons.has(key):
		return _icons[key]
	var path: String = PACK_DIR + icon_name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else icon_texture(icon_name)
	_icons[key] = tex
	return tex

static func pack_icon(icon_name: String, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = pack_texture(icon_name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## A small square with one glyph in it — the back arrow, the menu's three bars.
## Flat panel, hairline edge, square corners, like everything else here.
const SQUARE := 68.0

static func square_button(icon_name: String, size: float = SQUARE) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	for state in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, flat_box(PANEL, RULE_HI, 0))
	b.add_theme_stylebox_override("hover", flat_box(PANEL_HI, RULE_HI, 0))
	b.add_theme_stylebox_override("pressed", flat_box(INK, RULE_HI, 0))
	var glyph: TextureRect = icon(icon_name, size * 0.46)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(glyph)
	press_feedback(b)
	return b

## A destination tab for the bottom nav: picture over a word, and a gold bar
## under the active one. The bar is the whole "you are here" — no fill, no
## box, so the four tabs read as one row rather than four buttons.
const NAV_H := 150.0
const NAV_TAB_W := 190.0
const NAV_TAB_H := 100.0

## A picture over a word, with a gold bar right under the word when it is the
## place you are. It was a word alone with the bar pinned to the bottom of a
## 100px button, which put four blank pixels-worth of nothing between the two
## and made the bar read as a rule under the whole row rather than as a mark on
## one tab. Icons because a row of four words is slower to aim at than a row of
## four pictures, and because that is the shape a thumb learns.
static func nav_tab(text: String, icon_name: String = "") -> Button:
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(NAV_TAB_W * 0.62, NAV_TAB_H)
	var clear: StyleBoxFlat = flat_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, clear)

	var column := vbox(4)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_bottom = -10
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(column)
	var glyph: TextureRect = pack_icon(icon_name, 44)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(glyph)
	var word: Label = label(text, 26, TEXT_DIM)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(word)

	var bar := ColorRect.new()
	bar.color = GOLD
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = 10
	bar.offset_right = -10
	bar.offset_top = -4
	bar.offset_bottom = 0
	bar.visible = false
	b.add_child(bar)
	b.set_meta("nav_bar", bar)
	b.set_meta("nav_word", word)
	b.set_meta("nav_glyph", glyph)
	press_feedback(b)
	return b

static func set_nav_active(b: Button, active: bool) -> void:
	var bar: ColorRect = b.get_meta("nav_bar")
	var word: Label = b.get_meta("nav_word")
	var glyph: TextureRect = b.get_meta("nav_glyph")
	word.add_theme_color_override("font_color", TEXT if active else TEXT_DIM)
	glyph.modulate = Color.WHITE if active else Color(1, 1, 1, 0.55)
	bar.visible = active

## A rounded card with a one-pixel edge: the ability write-ups, the record.
static func card_box(fill: Color = PANEL, border: Color = RULE_HI, margin: int = 22) -> StyleBoxFlat:
	return flat_box(fill, border, margin)

## A small rounded square holding one glyph — the box beside each stat.
static func icon_box(icon_name: String, size: float = 52.0, glyph: float = 0.55) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_box(PANEL_HI, RULE_HI, 0, RADIUS_SMALL + 2))
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: TextureRect = icon(icon_name, size * glyph)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(t)
	return p

## A bordered block with a head — a glyph, a name, and the rule that governs
## what is inside it — and a body for the caller to fill. Season and Shop are
## both built out of these, which is what makes two dense screens read as one
## system rather than as two layouts that happen to share a palette. Returns
## `[card, body]`; the body is a `VBoxContainer` with no separation.
static func block(icon_name: String, title: String, rule_text: String = "",
		pad: int = 14) -> Array:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", card_box(PANEL, RULE_HI, pad))
	var column := vbox(0)
	card.add_child(column)

	var head := hbox(12)
	head.custom_minimum_size = Vector2(0, 36)
	column.add_child(head)
	if icon_name != "":
		var glyph: TextureRect = icon(icon_name, 30)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(glyph)
	var name_label: Label = label(title, 26, TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	if rule_text != "":
		var dot: Label = label("·", 26, TEXT_FAINT)
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(dot)
		var rule_label: Label = label(rule_text, 22, TEXT_DIM)
		rule_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(rule_label)
	head.add_child(spacer())
	column.add_child(gap(8, true))
	return [card, column]

## The glyph for a reward kind. Season names rewards on two rails and Shop
## names them in its deals, and they have to name them the same way — a Dawg
## Treat that is a bone in one place and a word in the other is two systems.
## Callers that can resolve a fighter (`brawler`, `skin`, `pin`) should show
## that fighter's portrait instead; this is the fallback for all three.
const REWARD_GLYPH := {
	"coins": "coin",
	"gems": "gem",
	"power_points": "power_point",
	"bling": "bling",
	"dawg_treat": "dawg_treat",
	"star_drop": "dawg_treat",
	"pin": "pin",
	"skin": "hanger",
	"gadget": "gadget",
	"star_power": "star_power",
	"hypercharge": "hypercharge",
	"brawler": "shield",
	"brawler_drop": "shield",
}

static func reward_glyph(kind: String) -> String:
	return REWARD_GLYPH.get(kind, "token")

## What to call a quantity of something. Returns "" for the kinds that need a
## fighter looked up (`brawler`, `skin`, `pin`), which is the caller's job —
## everything else is named here so Season's rails and Shop's deals cannot
## drift into calling the same reward two different things.
static func reward_name(kind: String, amount: int) -> String:
	match kind:
		"coins":
			return "%s COINS" % fmt(amount)
		"gems":
			return "%s GEMS" % fmt(amount)
		"power_points":
			return "%s POWER PTS" % fmt(amount)
		"bling":
			return "%s BLING" % fmt(amount)
		"dawg_treat", "star_drop":
			return "%s DAWG TREAT%s" % [fmt(amount), "S" if amount != 1 else ""]
	return ""

## A round medallion: ink inside, a ring of the accent colour, a glyph in the
## middle. The ability cards wear one each.
static func medallion(icon_name: String, accent: Color, size: float = 110.0) -> PanelContainer:
	var p := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = INK
	box.set_corner_radius_all(int(size / 2.0))
	box.set_border_width_all(3)
	box.border_color = accent
	p.add_theme_stylebox_override("panel", box)
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: TextureRect = icon(icon_name, size * 0.52)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(t)
	return p

## The stat row from the mockup: glyph box, name over a coloured bar, figure.
## `ratio` is the bar's fill against the roster's best, so a column of them
## reads as a comparison and not as five decorations.
static func stat_bar_row(icon_name: String, key: String, value: String, unit: String,
		ratio: float, color: Color, bar_width: float = 264.0) -> HBoxContainer:
	var row := hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: PanelContainer = icon_box(icon_name)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	var middle := vbox(8)
	middle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(middle)
	middle.add_child(label(key, 24, TEXT_SOFT))
	var track: Panel = bar(8.0, color)
	track.custom_minimum_size = Vector2(bar_width, 8)
	middle.add_child(track)
	set_bar(track, ratio, false)
	row.add_child(spacer())
	# The figure and its unit are one reading, so they sit in a box of their own
	# with 6px between them rather than the row's 18 — and the unit is TEXT_DIM,
	# not TEXT_FAINT, which at this size was grey on grey.
	var pair := hbox(6)
	pair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pair)
	var figure: Label = display(value, 40, TEXT)
	figure.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pair.add_child(figure)
	if unit != "":
		var u: Label = label(unit, 22, TEXT_DIM)
		u.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		pair.add_child(u)
	return row

## A row inside the record card: gold glyph, name, figure.
static func record_row(icon_name: String, key: String, value: String,
		accent: Color = TEXT) -> HBoxContainer:
	var row := hbox(16)
	row.custom_minimum_size = Vector2(0, 54)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: TextureRect = pack_icon(icon_name, 34)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var k: Label = label(key, 24, TEXT_SOFT)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)
	row.add_child(spacer())
	var v: Label = display(value, 38, accent)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(v)
	return row

## The menu control from the mockup: three bars over the word, no box.
static func menu_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(72, 72)
	var clear: StyleBoxFlat = flat_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, clear)
	var column := vbox(2)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(column)
	var bars: TextureRect = icon("menu", 36)
	bars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bars)
	var word: Label = label("MENU", 18, TEXT_DIM)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(word)
	press_feedback(b)
	return b

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
