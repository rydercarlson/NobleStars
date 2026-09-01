class_name UIKit
## Shared menu styling helpers — codifies the navy/gold StyleBoxFlat idiom
## from the original menu so screens don't repeat the boilerplate.

const NAVY := Color(0.13, 0.16, 0.24)
const NAVY_PANEL := Color(0.16, 0.20, 0.30)
const NAVY_DEEP := Color(0.10, 0.12, 0.19)
const GOLD := Color(1.0, 0.85, 0.25)
const PLAY_YELLOW := Color(1.0, 0.8, 0.1)
const MUTED := Color(1, 1, 1, 0.65)
const FAINT := Color(1, 1, 1, 0.25)

static func flat(bg: Color, radius: int = 14, border_w: int = 0,
		border: Color = FAINT, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_w)
	style.border_color = border
	style.set_content_margin_all(margin)
	return style

static func style_button(b: Button, bg: Color, selected := false) -> void:
	var border: Color = GOLD if selected else FAINT
	var border_w: int = 4 if selected else 1
	b.add_theme_stylebox_override("normal", flat(bg, 14, border_w, border))
	b.add_theme_stylebox_override("hover", flat(bg.lightened(0.08), 14, border_w, border))
	b.add_theme_stylebox_override("pressed", flat(bg.darkened(0.1), 14, border_w, border))
	b.add_theme_stylebox_override("focus", flat(bg, 14, border_w, border))

static func button(text: String, font_size: int, bg: Color,
		min_size := Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	style_button(b, bg)
	return b

static func label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

static func panel(radius: int = 14, bg: Color = NAVY_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(bg, radius, 1, FAINT))
	return p

## Small rounded readout (name / trophies / coins). The inner Label is stored
## as metadata "label" so callers can update the text later.
static func pill(text: String, accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(NAVY_DEEP, 18, 2, accent, 8))
	var l := label(text, 20, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.set_meta("label", l)
	return p

static func set_pill_text(p: PanelContainer, text: String) -> void:
	var l: Label = p.get_meta("label")
	l.text = text

## Standard top-left back button; caller connects pressed.
static func back_button() -> Button:
	var b := button("  < BACK  ", 24, NAVY_PANEL)
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.position = Vector2(24, 20)
	return b
