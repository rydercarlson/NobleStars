class_name FighterBars
extends Control
## Screen-space health + ammo bars for every fighter, drawn as flat 2D over
## the 3D view (no billboards — nothing rotates or overlaps in 3D).

const BAR_W := 110.0
const BAR_H := 16.0
const PIP_H := 8.0
const PIP_GAP := 3.0
const BAR_GAP := 5.0
const HEALTH_TEXT_SIZE := 13
const HEAD_OFFSET := Vector3(0, 2.7, 0)

# Loot boxes carry the same bar at roughly half scale, sat lower since a box is
# knee-high next to a fighter.
const BOX_BAR_W := 58.0
const BOX_BAR_H := 9.0
const BOX_HEAD_OFFSET := Vector3(0, 1.9, 0)
const BOX_COLOR := Color(0.95, 0.72, 0.25)

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
	_draw_lootboxes(cam)
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
		_draw_health_number(health_rect, f.health)

		# Ammo pips underneath, each filling left-to-right.
		var pips: int = maxi(1, int(f.max_ammo))
		var pip_w := (BAR_W - float(pips - 1) * PIP_GAP) / float(pips)
		var pip_y := p.y + BAR_H + BAR_GAP
		for i in pips:
			var px := left + i * (pip_w + PIP_GAP)
			var pip_rect := Rect2(px, pip_y, pip_w, PIP_H)
			draw_style_box(_style(TRACK_COLOR, 3, OUTLINE_COLOR, 1), pip_rect)
			var pf: float = clamp(f.ammo - i, 0.0, 1.0)
			if pf > 0.02:
				var pip_inner := pip_rect.grow(-1.5)
				var pip_fill := Rect2(pip_inner.position,
						Vector2(pip_inner.size.x * pf, pip_inner.size.y))
				draw_style_box(_style(AMMO_COLOR, 2), pip_fill)

		# Hammy's streak changes how the next shot should be played, so show three
		# compact Heat pips directly below ammo. All three burn while On Fire.
		if bool(f.kit.get("weapon", {}).get("heat_trait", false)):
			var heat_y := pip_y + PIP_H + 3.0
			for i in 3:
				var heat_rect := Rect2(left + i * (pip_w + PIP_GAP), heat_y, pip_w, 5.0)
				var lit: bool = f.is_on_fire(game.now) or i < f.heat_hits
				draw_style_box(_style(Color(1.0, 0.22, 0.01) if lit else TRACK_COLOR,
						2, OUTLINE_COLOR, 1), heat_rect)

## Loot boxes are shootable targets, so they read like one: the same health bar
## the fighters wear, drawn under them so a fighter's bar always wins the
## overlap. Boxes never move, so no interpolated transform is needed.
func _draw_lootboxes(cam: Camera3D) -> void:
	for box in get_tree().get_nodes_in_group("lootbox"):
		if not is_instance_valid(box):
			continue
		var world: Vector3 = box.global_position + BOX_HEAD_OFFSET
		if cam.is_position_behind(world):
			continue
		var p: Vector2 = cam.unproject_position(world).round()
		var rect := Rect2(p.x - BOX_BAR_W / 2.0, p.y, BOX_BAR_W, BOX_BAR_H)
		draw_style_box(_style(TRACK_COLOR, 4, OUTLINE_COLOR, 2), rect)
		var frac: float = clamp(float(box.get_meta("health", 0))
				/ maxf(1.0, float(box.get_meta("max_health", 1))), 0.0, 1.0)
		var inner := rect.grow(-2.0)
		var fill := Rect2(inner.position, Vector2(inner.size.x * frac, inner.size.y))
		if fill.size.x > 0.5:
			draw_style_box(_style(BOX_COLOR, 2), fill)

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

## Brawl Stars-style current HP: compact white numerals with a heavy dark edge.
## Drawing the edge manually keeps it crisp without adding a Label per fighter.
func _draw_health_number(rect: Rect2, health: int) -> void:
	var font := ThemeDB.fallback_font
	var value := str(health)
	var baseline := Vector2(rect.position.x, rect.position.y + 13.5)
	for offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, baseline + offset, value, HORIZONTAL_ALIGNMENT_CENTER,
				rect.size.x, HEALTH_TEXT_SIZE, OUTLINE_COLOR)
	draw_string(font, baseline, value, HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x, HEALTH_TEXT_SIZE, Color.WHITE)
