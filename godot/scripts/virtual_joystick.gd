class_name TouchStick
extends Control
## A floating joystick that is PARKED on screen when nobody is touching it.
## Value is normalized (-1..1 per axis). Drawn directly — no textures, the same
## reason the sounds are synthesized: three circles at a fixed size cost one
## script and nothing at import time.
##
## Two behaviours that sound contradictory and are not:
##
## **It is always on screen.** The sticks used to be invisible until touched,
## which is legible only once you already know they are there — nothing said
## that the left half walks and the right half shoots, and the Super button was
## the only control you could see, which is most of why it was the only one
## anybody aimed at. Parked and translucent they read as controls, and colour
## carries which is which: blue moves, red shoots, gold is the Super.
##
## **It still floats to the finger.** A parked stick you have to hit accurately
## is a worse control than one that comes to you, so a touch anywhere in the
## stick's own region re-anchors the base under the finger and the base slides
## home on release. That is also what keeps a TAP unambiguous — `value` is zero
## at the instant of the press however far from home it landed, so a
## press-and-release always reads as a tap and never as a full-deflection drag.
## The old Super button anchored its stick at the button and fed it the touch
## position, so a thumb landing on the button's edge released a manually aimed
## Super it never asked for.

const RADIUS := 90.0
const KNOB := 38.0
## How long a released stick takes to slide home and fade back down. Short
## enough to be over before the next touch, long enough to read as the stick
## returning rather than teleporting.
const RETURN_TIME := 0.12
## How visible a parked stick is. It has to survive being drawn over lit grass
## without becoming the brightest thing on the screen.
const IDLE_ALPHA := 0.42

var active := false
var touch_index := -1
var origin := Vector2.ZERO
var value := Vector2.ZERO

## Where the stick sits with no finger on it. `main.gd:_layout_sticks` owns
## these and re-parks them whenever the viewport changes size.
var home := Vector2.ZERO
var tint := Color(1, 1, 1)
var radius := RADIUS
var knob := KNOB
## >= 0 draws a charge dial in the base and a star on the knob: the Super's
## stick is also its meter, which is why there is no longer a separate Super
## button drawing a second circle over the same corner.
var charge := -1.0
## How near `home` a touch has to land to grab this stick, for a stick that owns
## a patch of screen rather than half of it. 0 = the caller decides.
var grab_radius := 0.0

## The drawn knob offset, which lags `value` back to centre on release. Kept
## apart from `value` so the animation can never be read as input.
var _shown := Vector2.ZERO
## 0 parked, 1 in hand. Drives both the fade and nothing else.
var _lit := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	origin = home

## Move the resting position. Takes effect immediately when the stick is idle,
## and on release when it is not.
func park(at: Vector2) -> void:
	home = at
	if not active:
		origin = at
	queue_redraw()

## Whether a touch at `pos` should grab this stick. Only meaningful for a stick
## with its own `grab_radius` — the move and aim sticks are handed a whole half
## of the screen by the caller instead.
func hit(pos: Vector2) -> bool:
	return grab_radius > 0.0 and pos.distance_to(home) <= grab_radius

func set_charge(c: float) -> void:
	if absf(c - charge) > 0.005 or (c >= 1.0) != (charge >= 1.0):
		charge = c
		queue_redraw()

func begin(pos: Vector2, index: int) -> void:
	active = true
	touch_index = index
	origin = pos
	value = Vector2.ZERO
	_shown = Vector2.ZERO
	queue_redraw()

func update_drag(pos: Vector2) -> void:
	if not active:
		return
	value = (pos - origin).limit_length(radius) / radius
	_shown = value
	queue_redraw()

func release() -> void:
	active = false
	touch_index = -1
	value = Vector2.ZERO
	queue_redraw()

func _process(delta: float) -> void:
	# Exponential approach rather than a Tween: the stick can be re-grabbed
	# mid-return, and a tween would have to be chased down and killed.
	var k: float = 1.0 - exp(-delta / RETURN_TIME)
	var moved := false
	var want: float = 1.0 if active else 0.0
	if absf(_lit - want) > 0.002:
		_lit = lerpf(_lit, want, k)
		moved = true
	elif _lit != want:
		_lit = want
		moved = true
	if not active:
		if origin.distance_to(home) > 0.5:
			origin = origin.lerp(home, k)
			moved = true
		elif origin != home:
			origin = home
			moved = true
		if _shown.length() > 0.004:
			_shown = _shown.lerp(Vector2.ZERO, k)
			moved = true
		elif _shown != Vector2.ZERO:
			_shown = Vector2.ZERO
			moved = true
	if moved:
		queue_redraw()

func _draw() -> void:
	var a: float = lerpf(IDLE_ALPHA, 1.0, _lit)
	var charged := charge >= 1.0
	draw_circle(origin, radius, Color(tint.r, tint.g, tint.b, 0.16 * a))
	if charge > 0.01:
		# The charge dial fills the base clockwise from the top, as the old
		# Super button's did. It is the only reason this stick is bigger than a
		# ring: there has to be something for the fill to fill.
		var pie := PackedVector2Array([origin])
		var steps := 40
		for i in steps + 1:
			var ang: float = -PI / 2.0 + TAU * minf(charge, 1.0) * i / steps
			pie.append(origin + Vector2(cos(ang), sin(ang)) * (radius - 5.0))
		draw_colored_polygon(pie, Color(tint.r, tint.g, tint.b, (0.7 if charged else 0.38) * a))
	# A dark backing arc under the coloured one. The sticks sit over lit grass,
	# pale end zones and dark bushes in the same match, and a thin translucent
	# ring disappears into at least one of those without it.
	var ring_w: float = 5.0 if charged else 3.0
	draw_arc(origin, radius, 0, TAU, 48, Color(0, 0, 0, 0.3 * a), ring_w + 3.0, true)
	draw_arc(origin, radius, 0, TAU, 48,
			Color(tint.r, tint.g, tint.b, (1.0 if charged else 0.7) * a), ring_w, true)
	var at := origin + _shown * radius
	draw_circle(at, knob, Color(tint.r, tint.g, tint.b, (0.7 if charged else 0.3) * a))
	draw_arc(at, knob, 0, TAU, 32, Color(0, 0, 0, 0.3 * a), 5.0, true)
	draw_arc(at, knob, 0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.9 * a), 2.5, true)
	if charge >= 0.0:
		var star := PackedVector2Array()
		for i in 10:
			var ang: float = -PI / 2.0 + TAU * i / 10.0
			var r: float = knob * 0.62 if i % 2 == 0 else knob * 0.26
			star.append(at + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(star, Color(0.06, 0.06, 0.06, 0.9 * a) if charged
				else Color(tint.r, tint.g, tint.b, 0.75 * a))
