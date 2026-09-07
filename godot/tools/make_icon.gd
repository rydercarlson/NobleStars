extends SceneTree
## One-shot: draws res://icon.png, the app icon, at 1024x1024. Run:
## Godot --path godot --headless --script res://tools/make_icon.gd
##
## The icon is drawn in the MENU's design language, not a language of its own,
## and takes its two colours from MenuUI so there is one definition of each:
## ink field, gold mark, flat, hard-edged, no bevel or gradient or shadow. That
## is the whole reason it does not look like the previous one, which was a gold
## star on a mid-navy VERTICAL GRADIENT with the lower half of the star darkened
## — three things (gradient, shading, the old navy) that the menu overhaul
## deliberately removed everywhere else. An icon is the first thing anyone sees
## and it should agree with the game behind it.
##
## Three decisions worth keeping:
##
## - **It is supersampled.** The old version tested one point per pixel against
##   the star polygon, so every edge was hard-aliased; at the sizes iOS actually
##   downscales to, a jagged 1024 master turns to mush. SS x SS samples per
##   pixel is the entire difference between a crisp mark and a fuzzy one.
## - **The star is CHUNKY and rotated.** A five-point star at the textbook inner
##   radius (0.382) is clip-art, and it is what every casual game on the home
##   screen already has. Widening the inner radius to 0.52 and tilting it off
##   axis is most of what makes a shape read as a mark somebody chose.
## - **Nothing runs to the edge.** iOS masks the icon into a superellipse and
##   crops the corners, so the mark sits inside a safe circle and the rule below
##   it stops well short of the tile edge. A design that bleeds gets clipped by
##   the mask in a way you cannot control and does not match across sizes.

const SIZE := 1024
## Samples per pixel per axis. 3 is enough at this size; the cost is 9x and the
## whole render is still under a second.
const SS := 3

## Fractions of the tile, so the whole thing scales if SIZE ever changes.
const STAR_R := 0.300        ## outer radius
const STAR_INNER := 0.42     ## inner radius as a fraction of the outer
const STAR_TILT := -0.07     ## radians off axis
const STAR_CY := 0.430       ## centre, lifted to leave room for the rule
const RULE_Y := 0.795
const RULE_H := 0.022
const RULE_W := 0.40

func _init() -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var ink: Color = MenuUI.INK
	var gold: Color = MenuUI.GOLD

	var star := _star_polygon()
	var rule := Rect2(
		(0.5 - RULE_W * 0.5) * SIZE, RULE_Y * SIZE,
		RULE_W * SIZE, RULE_H * SIZE)

	for y in SIZE:
		for x in SIZE:
			# Coverage, not a yes/no test: how many of the SS x SS samples in
			# this pixel land on the mark. That fraction IS the antialiasing.
			var hits := 0
			for sy in SS:
				for sx in SS:
					var p := Vector2(
						x + (sx + 0.5) / float(SS),
						y + (sy + 0.5) / float(SS))
					if rule.has_point(p) or Geometry2D.is_point_in_polygon(p, star):
						hits += 1
			var cover := float(hits) / float(SS * SS)
			img.set_pixel(x, y, ink if cover <= 0.0 else ink.lerp(gold, cover))

	img.save_png("res://icon.png")
	print("icon written: res://icon.png %dx%d" % [SIZE, SIZE])
	quit()

func _star_polygon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := Vector2(SIZE * 0.5, SIZE * STAR_CY)
	var outer := SIZE * STAR_R
	for i in 10:
		var r: float = outer if i % 2 == 0 else outer * STAR_INNER
		var a: float = -PI / 2.0 + TAU * i / 10.0 + STAR_TILT
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
