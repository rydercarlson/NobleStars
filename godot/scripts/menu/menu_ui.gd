class_name MenuUI
## The web menu's design system (web-menu/styles.css) as Godot helpers.
##
## Everything is authored in "stage pixels" — the same 1920x1080 coordinate
## space the CSS uses — and MenuShell scales the whole stage to the device.
## The Brawl-style plate (rounded box, dark outline, vertical gradient, inset
## highlight, hard drop shadow) can't be a StyleBoxFlat, so it is painted once
## into a small image per colour and served as a 9-patch StyleBoxTexture.

const NAVY := Color("#232838")
const NAVY_HI := Color("#3b425c")
const NAVY_LO := Color("#171b28")
const LINE := Color("#0c0e17")
const YELLOW := Color("#ffc21a")
const YELLOW_HI := Color("#ffe37a")
const YELLOW_LO := Color("#d98f00")
const GREEN := Color("#5bd21e")
const GREEN_HI := Color("#8df05a")
const GREEN_LO := Color("#2e8a0c")
const BLUE := Color("#1f4fdc")
const BLUE_HI := Color("#4d86ff")
const RED := Color("#ea3b3b")
const GREY := Color("#545c78")
const TEXT := Color("#ffffff")
const TEXT_DIM := Color("#aab2cc")
const TEXT_SOFT := Color("#d8def0")
const CARD_HI := Color("#2f3550")
const CARD_LO := Color("#1d2233")
const INK := Color("#10131f")
const GOLD_INK := Color("#3a2400")

const FONT_DISPLAY := "res://assets/menu/fonts/LilitaOne.woff2"
const FONT_BODY := "res://assets/menu/fonts/Nunito-800.woff2"
const FONT_BODY_700 := "res://assets/menu/fonts/Nunito-700.woff2"
const ICON_DIR := "res://assets/menu/svg/"
const PNG_ICON_DIR := "res://assets/menu/icons/"
const TREAT_DIR := "res://assets/menu/treats/"

## Icons that live as @2x PNGs rather than generated SVGs.
const PNG_ICONS := {
	"shield": "nobles_shield", "bulldog": "bulldog_showdown_icon",
	"shop": "shop_icon", "brawlers": "brawlers_icon", "news": "news_icon",
	"friends": "friends_icon", "club": "club_icon", "inbox": "inbox_icon",
	"new_badge": "new_badge",
}

## Icons whose WebP file under icons/ is not simply "<name>.webp".
const WEBP_ICONS := {
	"dawg_treat": "dawg_treat_icon",
}

static var _fonts: Dictionary = {}
static var _plates: Dictionary = {}
static var _icons: Dictionary = {}

static func display_font() -> Font:
	return _font(FONT_DISPLAY)

static func body_font() -> Font:
	return _font(FONT_BODY)

static func body_font_700() -> Font:
	return _font(FONT_BODY_700)

static func _font(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]

# MARK: text

## Display type: Lilita One, uppercase, dark stroke + hard shadow ("t outline").
static func display(text: String, size: int, color: Color = TEXT,
		outline: int = 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", LINE)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", maxi(2, outline / 2))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Body copy: Nunito 800/700, no outline.
static func body(text: String, size: int, color: Color = TEXT_SOFT,
		weight_700: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font_700() if weight_700 else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## 1,250 — the menu prints every number the way the web build does.
static func fmt(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("-" + out) if n < 0 else out

# MARK: icons

static func icon_texture(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var path: String = ICON_DIR + icon_name + ".svg"
	if PNG_ICONS.has(icon_name):
		path = PNG_ICON_DIR + str(PNG_ICONS[icon_name]) + ".png"
	elif not ResourceLoader.exists(path):
		# The v0.5 art pack arrived as WebP under icons/; resolve by name so the
		# mode, currency, gear and rank icons are addressable without a mapping.
		# The treat tiers live in their own directory, so try that too.
		var stem: String = str(WEBP_ICONS.get(icon_name, icon_name))
		for candidate: String in [PNG_ICON_DIR + stem + ".webp",
				TREAT_DIR + stem + ".webp"]:
			if ResourceLoader.exists(candidate):
				path = candidate
				break
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

# MARK: plates

## Named plate colours, as the CSS gradients: [top, base, bottom].
static func plate_colors(variant: String) -> Array:
	match variant:
		"yellow":
			return [YELLOW_HI, YELLOW, YELLOW_LO]
		"green":
			return [GREEN_HI, GREEN, GREEN_LO]
		"blue":
			return [Color("#6fa0ff"), BLUE, Color("#12309a")]
		"red":
			return [Color("#ff8a8a"), RED, Color("#9c1d1d")]
		"grey":
			return [Color("#7a849f"), GREY, Color("#333a52")]
		"card":
			return [CARD_HI, CARD_LO, CARD_LO]
		"dark":
			return [Color("#1b2030"), Color("#12161f"), Color("#12161f")]
		_:
			return [NAVY_HI, NAVY, NAVY]

## 9-patch plate: rounded box with dark outline, top-to-bottom gradient, inset
## highlight and the hard offset drop shadow the CSS paints with box-shadow.
static func plate_box(variant: String = "navy", radius: int = 16,
		shadow: int = 7, margin: int = 12) -> StyleBoxTexture:
	var key: String = "%s|%d|%d|%d" % [variant, radius, shadow, margin]
	if _plates.has(key):
		return _plates[key]
	var cols: Array = plate_colors(variant)
	var box := StyleBoxTexture.new()
	box.texture = _plate_texture(cols[0], cols[1], cols[2], radius, shadow)
	var side: int = radius + 6
	box.texture_margin_left = side
	box.texture_margin_right = side
	box.texture_margin_top = radius + 14
	box.texture_margin_bottom = shadow + radius
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin + shadow
	_plates[key] = box
	return box

static func _plate_texture(hi: Color, base: Color, lo: Color, radius: int,
		shadow: int) -> ImageTexture:
	var w := 128
	var h := 128
	var face_h: float = float(h - shadow)
	var border := 3.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := Vector2(w * 0.5, face_h * 0.5)
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var col := Color(0, 0, 0, 0)
			# hard drop shadow: the same box, pushed down
			var ds: float = _round_rect_sdf(px - Vector2(0, shadow), half, radius)
			var sa: float = clampf(0.5 - ds, 0.0, 1.0) * 0.45
			if sa > 0.0:
				col = Color(0, 0, 0, sa)
			var d: float = _round_rect_sdf(px, half, radius)
			var a: float = clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				var t: float = clampf(px.y / face_h, 0.0, 1.0)
				var face: Color = _grad(hi, base, lo, t)
				if d > -border:
					face = LINE
				elif px.y < border + 4.0:
					face = face.lerp(Color(1, 1, 1), 0.22)
				elif px.y > face_h - border - 6.0:
					face = face.lerp(Color(0, 0, 0), 0.3)
				face.a = a
				col = _over(face, col)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## CSS stops: hi at 0, base by 24%, base to 78%, lo at 100%.
static func _grad(hi: Color, base: Color, lo: Color, t: float) -> Color:
	if t < 0.24:
		return hi.lerp(base, t / 0.24)
	if t < 0.78:
		return base
	return base.lerp(lo, (t - 0.78) / 0.22)

static func _over(fg: Color, bg: Color) -> Color:
	var a: float = fg.a + bg.a * (1.0 - fg.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb: Vector3 = (Vector3(fg.r, fg.g, fg.b) * fg.a
			+ Vector3(bg.r, bg.g, bg.b) * bg.a * (1.0 - fg.a)) / a
	return Color(rgb.x, rgb.y, rgb.z, a)

static func _round_rect_sdf(p: Vector2, half: Vector2, radius: float) -> float:
	var q: Vector2 = (p - half).abs() - (half - Vector2(radius, radius))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius

## The flat inset box the screens use for stat rows (rgba(0,0,0,.35)).
static func dark_box(radius: int = 14, alpha: float = 0.35,
		margin: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, alpha)
	s.set_corner_radius_all(radius)
	s.set_border_width_all(2)
	s.border_color = Color(0, 0, 0, 0.5)
	s.set_content_margin_all(margin)
	return s

static func panel(variant: String = "navy", radius: int = 16, shadow: int = 7,
		margin: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", plate_box(variant, radius, shadow, margin))
	return p

static func dark_panel(radius: int = 14, alpha: float = 0.35,
		margin: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", dark_box(radius, alpha, margin))
	return p

# MARK: buttons

## The CSS .btn: plate face, display type, press-down feedback.
static func button(text: String, variant: String = "green", size: int = 34,
		min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", display_font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", LINE)
	var ink: Color = GOLD_INK if variant == "yellow" else TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(state, ink)
	var box: StyleBoxTexture = plate_box(variant, 14, 6, 16)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	press_feedback(b)
	return b

static func small_button(text: String, variant: String = "grey") -> Button:
	var b: Button = button(text, variant, 26)
	b.add_theme_constant_override("outline_size", 4)
	b.custom_minimum_size = Vector2(0, 64)
	return b

static func disabled_button(text: String) -> Button:
	var b: Button = button(text, "grey", 34)
	b.disabled = true
	b.modulate = Color(0.7, 0.7, 0.7)
	return b

## An icon-only button (back / close), the SVG at its natural aspect.
static func icon_button(icon_name: String, size: float) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = icon_texture(icon_name)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(size, size)
	press_feedback(b)
	return b

## One of the painted button plates from the asset pack, at its own aspect.
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

## CSS ".pressed { transform: translateY(5px) scale(.96) }" — sink and dim.
static func press_feedback(c: BaseButton) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)
	c.button_down.connect(func() -> void:
		if c.disabled:
			return
		c.scale = Vector2(0.97, 0.97)
		c.modulate = Color(0.9, 0.9, 0.9))
	var restore := func() -> void:
		c.scale = Vector2.ONE
		c.modulate = Color.WHITE
	c.button_up.connect(restore)
	c.mouse_exited.connect(restore)

# MARK: bars and chips

## A filled progress bar (trophy road, season tokens). Set with set_bar().
static func bar(height: float, fill: Color, fill_hi: Color) -> Panel:
	var track := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#0d1020")
	s.set_corner_radius_all(int(height / 2.0))
	s.set_border_width_all(2)
	s.border_color = LINE
	track.add_theme_stylebox_override("panel", s)
	track.custom_minimum_size = Vector2(0, height)
	track.clip_contents = true
	var fill_panel := Panel.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = fill
	fs.set_corner_radius_all(int(height / 2.0))
	fs.border_width_top = int(maxf(2.0, height * 0.3))
	fs.border_color = fill_hi
	fill_panel.add_theme_stylebox_override("panel", fs)
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
	tw.tween_property(fill, "anchor_right", target, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Small rounded chip, e.g. the trophy count on a brawler card.
static func chip(text: String, icon_name: String, size: int = 22,
		color: Color = YELLOW_HI) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.55)
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = Color(0, 0, 0, 0.6)
	s.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	if icon_name != "":
		row.add_child(icon(icon_name, size + 2))
	row.add_child(display(text, size, color, 0))
	p.add_child(row)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# MARK: layout helpers

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

## CSS "pop-in" — cards scale up as the screen builds, staggered. The control
## must already be laid out, so screens call this a frame after building.
static func pop_in(c: Control, delay: float = 0.0) -> void:
	c.pivot_offset = c.size / 2.0
	c.modulate.a = 0.0
	c.scale = Vector2(0.7, 0.7)
	var tw := c.create_tween()
	tw.set_parallel()
	tw.tween_property(c, "modulate:a", 1.0, 0.25).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.4).set_delay(delay) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func stagger(container: Node, step: float = 0.045) -> void:
	var i: int = 0
	for child in container.get_children():
		if child is Control:
			pop_in(child, i * step)
			i += 1

static var _radial: ImageTexture

## The soft radial the cards use behind a portrait (CSS radial-gradient at
## 50% 80%). White, so callers tint it with modulate.
static func radial_texture() -> ImageTexture:
	if _radial != null:
		return _radial
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(0.5, 0.8)
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5) / size, (y + 0.5) / size)
			var d: float = ((p - centre) / Vector2(0.62, 0.75)).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	_radial = ImageTexture.create_from_image(img)
	return _radial

## Card background: the rarity's dark tone fading out of a near-black plate.
static func card_backdrop(tint: Color) -> Control:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.color = Color("#1a1e2e")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(base)
	var glow := TextureRect.new()
	glow.texture = radial_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.modulate = tint
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	return holder

## Hex string from the data files -> Color, tolerant of a missing "#".
static func hex(value: Variant, fallback: Color = Color.WHITE) -> Color:
	var s: String = str(value)
	if s.is_empty():
		return fallback
	return Color(s) if s.begins_with("#") else Color("#" + s)

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

## A card you can layer things onto. PanelContainer stretches every child to
## fill it, which turns a corner badge into a full-card rectangle, so a card
## with overlays is a plain Panel plus `card_body()` for its padded content.
static func card(variant: String = "card", radius: int = 18,
		shadow: int = 7) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", plate_box(variant, radius, shadow, 0))
	p.clip_contents = true
	return p

## The padded content area inside card(), clear of the plate's drop shadow.
static func card_body(host: Control, pad: int = 16, shadow: int = 7) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_bottom = -shadow
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(margin)
	return margin

static var _fade: ImageTexture

## Left-to-right white -> transparent ramp, tinted by modulate. Stands in for
## the CSS linear-gradient washes behind the offer and mode cards.
static func fade_texture() -> ImageTexture:
	if _fade != null:
		return _fade
	var width := 64
	var img := Image.create(width, 1, false, Image.FORMAT_RGBA8)
	for x in width:
		var t: float = float(x) / float(width - 1)
		img.set_pixel(x, 0, Color(1, 1, 1, pow(1.0 - t, 1.4)))
	_fade = ImageTexture.create_from_image(img)
	return _fade
