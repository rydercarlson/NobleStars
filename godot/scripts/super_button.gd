class_name SuperButton
extends Control
## Super meter/button: pie fill shows charge, glows when ready.
## Hit-testing is done by the main scene; this just draws.

const RADIUS := 62.0

var charge := 0.0
var center := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func set_charge(c: float) -> void:
	if abs(c - charge) > 0.005 or (c >= 1.0) != (charge >= 1.0):
		charge = c
		queue_redraw()

func layout(viewport_size: Vector2) -> void:
	center = Vector2(viewport_size.x - 110, viewport_size.y - 110)
	queue_redraw()

func hit(pos: Vector2) -> bool:
	return pos.distance_to(center) <= RADIUS + 16

func _draw() -> void:
	var ready_now := charge >= 1.0
	draw_circle(center, RADIUS, Color(0.1, 0.1, 0.1, 0.4))
	if charge > 0.01:
		var points := PackedVector2Array([center])
		var steps := 40
		for i in steps + 1:
			var a := -PI / 2 + TAU * charge * i / steps
			points.append(center + Vector2(cos(a), sin(a)) * (RADIUS - 4))
		draw_colored_polygon(points, Color(1.0, 0.75, 0.1, 0.85) if ready_now else Color(1.0, 0.75, 0.1, 0.5))
	draw_arc(center, RADIUS, 0, TAU, 48,
			 Color(1.0, 0.85, 0.2, 1.0) if ready_now else Color(1, 1, 1, 0.4),
			 5.0 if ready_now else 3.0, true)
	# Star glyph
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + TAU * i / 10.0
		var r := 24.0 if i % 2 == 0 else 10.0
		star.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(star, Color(0.1, 0.1, 0.1, 0.9) if ready_now else Color(1, 1, 1, 0.5))
