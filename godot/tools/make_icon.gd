extends SceneTree
## One-shot: draws the app icon (gold star on navy, matching UIKit's palette)
## to res://icon.png at 1024x1024. Run:
## Godot --path godot --headless --script res://tools/make_icon.gd

func _init() -> void:
	var size := 1024
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var navy := Color(0.13, 0.16, 0.24)
	var navy_hi := Color(0.20, 0.26, 0.40)
	var gold := Color(1.0, 0.85, 0.25)

	var star := PackedVector2Array()
	var c := Vector2(size / 2.0, size / 2.0 + 20)
	for i in 10:
		var r := 430.0 if i % 2 == 0 else 175.0
		var a := -PI / 2.0 + TAU * i / 10.0
		star.append(c + Vector2(cos(a), sin(a)) * r)

	for y in size:
		var t := float(y) / size   # vertical navy gradient
		var bg := navy.lerp(navy_hi, t * 0.6)
		for x in size:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, star):
				# subtle shading: lower half of the star slightly darker
				img.set_pixel(x, y, gold.darkened(0.12) if p.y > c.y else gold)
			else:
				img.set_pixel(x, y, bg)

	img.save_png("res://icon.png")
	print("icon written")
	quit()
