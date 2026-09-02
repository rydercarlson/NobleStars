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
# The whole stack hangs down from this point, so it has to clear the top of a
# fighter's head plus the bar, the ammo pips and the gap between them. Fighters
# got taller (Kits.MODEL_SCALE) and the old 2.7 m anchor left the bar painted
# across their faces.
const HEAD_OFFSET := Vector3(0, 3.4, 0)

# Loot boxes carry the same bar at roughly half scale, sat lower since a box is
# knee-high next to a fighter.
const BOX_BAR_W := 58.0
const BOX_BAR_H := 9.0
const BOX_HEAD_OFFSET := Vector3(0, 1.9, 0)
const BOX_COLOR := Color(0.95, 0.72, 0.25)

const TRACK_COLOR := Color(0.055, 0.065, 0.08, 0.92)
const OUTLINE_COLOR := Color(0.015, 0.02, 0.03, 0.95)
const AMMO_COLOR := Color(1.0, 0.65, 0.1, 1.0)

# Power-cube tally, Brawl Stars-style: a little cube token and a count, sat off
# the left end of the health bar so it never eats into the bar itself. The
# greens match the power_cube model so the HUD token reads as the same object
# that is lying on the floor.
const CUBE_HALF_W := 6.5     # half-width of the token
const CUBE_TOP_H := 3.4      # half-height of its top face
const CUBE_SIDE_H := 7.5     # height of its side faces
const CUBE_RIM := 1.30       # how far the dark rim is grown past the token
const CUBE_TEXT_SIZE := 15
const CUBE_TOP_COLOR := Color(0.56, 0.93, 0.35)
const CUBE_LEFT_COLOR := Color(0.30, 0.71, 0.21)
const CUBE_RIGHT_COLOR := Color(0.19, 0.52, 0.15)

## Offsets for the heavy dark edge under HUD numerals. One draw per offset
## keeps the text crisp without a Label node per fighter.
const TEXT_EDGE := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

## Nobles Cup only: which side someone is on has to be readable at a glance, so
## the health bar carries it. Showdown is a free-for-all and keeps kit colours.
const ALLY_COLOR := Color(0.30, 0.80, 0.32)
const ENEMY_COLOR := Color(0.92, 0.26, 0.24)

## Ayaan's Downhill clock. It sits ABOVE the health bar rather than joining the
## stack below it, because it is a temporary state and not another permanent
## stat — and because the player is steering an 11.7 m/s body at the time and
## needs "how long have I got" in the same glance as the fighter.
const RIDE_H := 7.0
const RIDE_GAP := 4.0
const RIDE_COLOR := Color(0.58, 0.89, 1.0)      # ice

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

		# Downhill's clock, draining left to right over the two seconds of the
		# run. Only the host simulates a ride (`authoritative` in main.gd), so on
		# a wifi CLIENT this stays empty even for your own fighter — the snapshot
		# stream carries positions, not ride state.
		var ride: float = f.ride_fraction()
		if ride > 0.0:
			var ride_rect := Rect2(left, p.y - RIDE_H - RIDE_GAP, BAR_W, RIDE_H)
			draw_style_box(_style(TRACK_COLOR, 4, OUTLINE_COLOR, 2), ride_rect)
			var ride_inner := ride_rect.grow(-2.0)
			var ride_fill := Rect2(ride_inner.position,
					Vector2(ride_inner.size.x * ride, ride_inner.size.y))
			if ride_fill.size.x > 0.5:
				draw_style_box(_style(RIDE_COLOR, 2), ride_fill)

		# Health bar: rounded, outlined track with an inset fill. Keeping the fill
		# inside its track prevents the square, clipped look of raw rectangles.
		var health_rect := Rect2(left, p.y, BAR_W, BAR_H)
		draw_style_box(_style(TRACK_COLOR, 5, OUTLINE_COLOR, 2), health_rect)
		var frac: float = clamp(float(f.health) / float(f.max_health), 0.0, 1.0)
		var health_inner := health_rect.grow(-2.0)
		var health_fill := Rect2(health_inner.position,
				Vector2(health_inner.size.x * frac, health_inner.size.y))
		if health_fill.size.x > 0.5:
			draw_style_box(_style(_bar_color(f), 3), health_fill)
		_draw_health_number(health_rect, f.health)
		if f.cubes > 0:
			_draw_cube_badge(health_rect, f.cubes)

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

## Kit colour in Showdown; team colour in Nobles Cup, where telling a team-mate
## from an opponent apart matters more than telling Nova from Tony.
func _bar_color(f: Fighter) -> Color:
	# Validity is checked BEFORE the typed local: Showdown frees the player on
	# death and main.player keeps pointing at it, and merely assigning a freed
	# instance to a `Fighter` variable throws — thousands of times a second.
	if f.team < 0 or not is_instance_valid(game.player):
		return f.kit.color
	var you: Fighter = game.player
	return ALLY_COLOR if f == you or f.is_ally(you) else ENEMY_COLOR

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
func _draw_health_number(rect: Rect2, health: int) -> void:
	_outlined_text(Vector2(rect.position.x, rect.position.y + 13.5), str(health),
			HEALTH_TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _outlined_text(baseline: Vector2, text: String, size: int,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	for offset in TEXT_EDGE:
		draw_string(font, baseline + offset, text, align, width, size, OUTLINE_COLOR)
	draw_string(font, baseline, text, align, width, size, Color.WHITE)

## How many power cubes this fighter is carrying: the cube token, then the
## count, ending just short of the health bar's left edge.
func _draw_cube_badge(bar: Rect2, count: int) -> void:
	var font := ThemeDB.fallback_font
	var text := str(count)
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			CUBE_TEXT_SIZE).x
	var mid := bar.position.y + bar.size.y / 2.0
	var text_x := bar.position.x - 5.0 - text_w
	_draw_cube_token(Vector2(text_x - 4.0 - CUBE_HALF_W * CUBE_RIM, mid))
	_outlined_text(Vector2(text_x, mid + CUBE_TEXT_SIZE * 0.36), text, CUBE_TEXT_SIZE)

## An isometric cube drawn as three faces over a grown dark silhouette, so the
## token stays legible against the arena floor and against a fighter behind it.
func _draw_cube_token(c: Vector2) -> void:
	var top := c.y - (CUBE_SIDE_H + CUBE_TOP_H * 2.0) / 2.0
	var apex := Vector2(c.x, top)                                  # top corner
	var right := Vector2(c.x + CUBE_HALF_W, top + CUBE_TOP_H)
	var front := Vector2(c.x, top + CUBE_TOP_H * 2.0)              # near vertical edge
	var left := Vector2(c.x - CUBE_HALF_W, top + CUBE_TOP_H)
	var down := Vector2(0, CUBE_SIDE_H)
	var silhouette := PackedVector2Array([apex, right, right + down,
			front + down, left + down, left])
	var rim := PackedVector2Array()
	for pt in silhouette:
		rim.append(c + (pt - c) * CUBE_RIM)
	draw_colored_polygon(rim, OUTLINE_COLOR)
	draw_colored_polygon(PackedVector2Array([apex, right, front, left]), CUBE_TOP_COLOR)
	draw_colored_polygon(PackedVector2Array([left, front, front + down, left + down]),
			CUBE_LEFT_COLOR)
	draw_colored_polygon(PackedVector2Array([front, right, right + down, front + down]),
			CUBE_RIGHT_COLOR)
