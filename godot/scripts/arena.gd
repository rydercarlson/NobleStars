class_name Arena
extends Node3D
## Builds the 3D arena from an ASCII map and answers tile queries. Row 0 of
## the ASCII art is the map's -Z (far) edge.
##
## The map is 33x33 — a Brawl Stars Showdown map rescaled to our fighters.
## Theirs is 60x60 tiles with a brawler about a tile wide; ours is 33x33 with a
## 1.10 m fighter on 2 m tiles, so both arenas are 60 body-widths across, and at
## SPEED_NORMAL crossing one takes the same ~24 s it does there.
##
## Terrain has exact 4-fold rotational symmetry about the centre tile: features
## are authored in one quadrant and rotated, so no spawn has a better draw than
## any other, but the angles are chiral rather than mirrored so it reads as a
## pinwheel instead of a kaleidoscope. Concentric bush rings break line of
## sight, their gaps offset ring to ring; ponds sit in the four cardinal lanes
## so the straight run at the centre keep costs you a detour. The keep itself
## is a walled 7x7 with four 3-tile gates holding five of the seventeen power
## cubes, and the gas ring closes onto it.
##
## Every gap is sized for a 1.10 m fighter (Kits.FIGHTER_RADIUS) and the
## generator refuses to emit a map with a cul-de-sac or a pocket sealed behind
## a single tile — being cornered in Showdown should be a mistake you made, not
## one the map made for you. Retune it in Tools/gen_showdown_map.py and
## regenerate with `python3 Tools/gen_showdown_map.py --write`.

const MAP := """
#################################
#..#.bb...............##..bb....#
#..#bb.S##.....S......##.S.bbb..#
#.bb.....X....b#b##..........b###
#.b..~~....bbbbbb##bbb....~~..b.#
#bb.~####.bb..~~.~~..Xbb...#~.bb#
#b..~..##.#...#...~##..b...#~..b#
#.............#...........##....#
#............bb...bb###...##..#.#
###..bb.....bb#...bb###......X#.#
###S.b..##bbb....##.bXb...#b..S.#
#...bX..##Xb.##..##..bb....bb...#
#...b.#.##b..##.......bb....b...#
#...b.#.bb...##...####.bb...b...#
#..##~~.bb##.#X...X###.#b##~bb..#
#..##~....##...~.~.........~b#..#
#..bb...........X...........bb..#
#..#b~.........~.~...##....~##..#
#..bb~##b#.###X...X#.##bb.~~##..#
#...b...bb.####...##...bb.#.b...#
#...b....bb.......##..b##.#.b...#
#...bb....bb..##..##.bX##..Xb.S.#
#.S..b#...bXb.##....bbb##..b..###
#.#X......###bb...#bb.....bb..###
#.#..##...###bb...bb............#
#....##...........#.............#
#b..~#...b..##~...#...#.##..~..b#
#bb.~#...bbX..~~.~~..bb.####~.bb#
#.b..~~....bbb##bbbbbb....~~..b.#
###b....S.....##S#b....XS....bb.#
#..bbb...##............##..bb#..#
#....bb..##...............bb.#..#
#################################
"""

var rows: Array[String] = []
var spawn_points: Array[Vector3] = []
var box_points: Array[Vector3] = []
var columns := 0
var row_count := 0

func map_size() -> float:
	return columns * Kits.TILE

func _ready() -> void:
	for line in MAP.split("\n", false):
		rows.append(line)
	row_count = rows.size()
	columns = rows[0].length()
	_build()

func tile_center(col: int, row: int) -> Vector3:
	return Vector3((col + 0.5) * Kits.TILE, 0, (row + 0.5) * Kits.TILE)

func tile_at(pos: Vector3) -> String:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	if col < 0 or col >= columns or row < 0 or row >= row_count:
		return "#"
	var ch := rows[row][col]
	return "." if ch in ["S", "X"] else ch

func blocks_movement(pos: Vector3) -> bool:
	return tile_at(pos) in ["#", "~"]

func _build() -> void:
	var ts := Kits.TILE
	# Ground: one big checkered-ish plane (two greens via a grid of quads
	# would be 900 nodes; a single plane keeps 3D simple for now).
	_static_box(Vector3(map_size() / 2, -0.5, map_size() / 2),
				Vector3(map_size(), 1, map_size()), Color(0.45, 0.70, 0.35), 1)

	for row in row_count:
		for col in columns:
			var ch := rows[row][col]
			var c := tile_center(col, row)
			match ch:
				"#":
					var is_border := row == 0 or col == 0 or row == row_count - 1 or col == columns - 1
					var wall := _static_box(c + Vector3(0, 0.75, 0), Vector3(ts, 1.5, ts),
											Color(0.62, 0.46, 0.32), 1)
					if not is_border:
						wall.add_to_group("breakable")
						# Stable id so net play can replicate wall destruction.
						wall.name = "Wall_%d_%d" % [row, col]
				"~":
					var w := _static_box(c + Vector3(0, 0.12, 0), Vector3(ts, 0.24, ts),
										 Color(0.30, 0.55, 0.85, 0.85), 2)
					w.add_to_group("water")
				"b":
					_bush(c)
				"S":
					spawn_points.append(c)
				"X":
					box_points.append(c)

func _bush(center: Vector3) -> void:
	# Visual only — bushes never block movement; concealment is logic-side.
	for offset in [Vector3(-0.4, 0.5, -0.3), Vector3(0.45, 0.55, 0.2), Vector3(-0.05, 0.7, 0.35)]:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.75
		s.height = 1.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.50, 0.20, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.material = mat
		m.mesh = s
		m.position = center + offset
		add_child(m)

func _static_box(pos: Vector3, size: Vector3, color: Color, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	add_child(body)
	return body
