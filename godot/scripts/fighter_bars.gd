class_name FighterBars
extends Control
## Screen-space health + ammo bars for every fighter, drawn as flat 2D over
## the 3D view (no billboards — nothing rotates or overlaps in 3D).

const BAR_W := 110.0
const BAR_H := 14.0
const PIP_H := 8.0
const PIP_GAP := 3.0
const BAR_GAP := 5.0
const HEAD_OFFSET := Vector3(0, 2.7, 0)

const TRACK_COLOR := Color(0.055, 0.065, 0.08, 0.92)
const OUTLINE_COLOR := Color(0.015, 0.02, 0.03, 0.95)
const AMMO_COLOR := Color(1.0, 0.65, 0.1, 1.0)

var _styles: Dictionary = {}

var game: Node3D   # main scene; provides fighters + cam

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if game == null or game.cam == null:
		return
	var cam: Camera3D = game.cam
	for f in game.fighters:
		if not is_instance_valid(f) or f.is_dead() or not f.visible:
			continue
		# global_position is the raw physics step; the mesh renders at the
		# interpolated transform, so unprojecting the former makes bars buzz.
		var world: Vector3 = f.get_global_transform_interpolated().origin + HEAD_OFFSET
		if cam.is_position_behind(world):
			continue
		var p: Vector2 = cam.unproject_position(world).round()
		var left := p.x - BAR_W / 2.0

		# Health bar: rounded, outlined track with an inset fill. Keeping the fill
		# inside its track prevents the square, clipped look of raw rectangles.
		var health_rect := Rect2(left, p.y, BAR_W, BAR_H)
		draw_style_box(_style(TRACK_COLOR, 5, OUTLINE_COLOR, 2), health_rect)
		var frac: float = clamp(float(f.health) / float(f.max_health), 0.0, 1.0)
		var health_inner := health_rect.grow(-2.0)
		var health_fill := Rect2(health_inner.position,
				Vector2(health_inner.size.x * frac, health_inner.size.y))
		if health_fill.size.x > 0.5:
			draw_style_box(_style(f.kit.color, 3), health_fill)

		# Ammo pips underneath, each filling left-to-right.
		var pip_w := (BAR_W - 2.0 * PIP_GAP) / 3.0
		var pip_y := p.y + BAR_H + BAR_GAP
		for i in 3:
			var px := left + i * (pip_w + PIP_GAP)
			var pip_rect := Rect2(px, pip_y, pip_w, PIP_H)
			draw_style_box(_style(TRACK_COLOR, 3, OUTLINE_COLOR, 1), pip_rect)
			var pf: float = clamp(f.ammo - i, 0.0, 1.0)
			if pf > 0.02:
				var pip_inner := pip_rect.grow(-1.5)
				var pip_fill := Rect2(pip_inner.position,
						Vector2(pip_inner.size.x * pf, pip_inner.size.y))
				draw_style_box(_style(AMMO_COLOR, 2), pip_fill)

## Cache the tiny draw styles instead of allocating new resources every frame.
func _style(fill: Color, radius: int, border := Color.TRANSPARENT,
		border_width := 0) -> StyleBoxFlat:
	var key := "%s:%d:%s:%d" % [fill.to_html(), radius, border.to_html(), border_width]
	if _styles.has(key):
		return _styles[key]
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border_width > 0:
		style.border_color = border
		style.set_border_width_all(border_width)
	_styles[key] = style
	return style
