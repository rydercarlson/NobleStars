class_name TouchStick
extends Control
## Floating joystick: appears where the touch lands, knob follows the finger.
## Value is normalized (-1..1 per axis). Drawn directly — no textures.

const RADIUS := 90.0
const KNOB := 38.0

var active := false
var touch_index := -1
var origin := Vector2.ZERO
var value := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func begin(pos: Vector2, index: int) -> void:
	active = true
	touch_index = index
	origin = pos
	value = Vector2.ZERO
	queue_redraw()

func update_drag(pos: Vector2) -> void:
	if not active:
		return
	value = (pos - origin).limit_length(RADIUS) / RADIUS
	queue_redraw()

func release() -> void:
	active = false
	touch_index = -1
	value = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	draw_circle(origin, RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(origin, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
	draw_circle(origin + value * RADIUS, KNOB, Color(1, 1, 1, 0.35))
	draw_arc(origin + value * RADIUS, KNOB, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0, true)
