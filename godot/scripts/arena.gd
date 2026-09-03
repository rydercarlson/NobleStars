class_name Arena
extends Node3D
## Builds the 3D arena from an ASCII map and answers tile queries. Row 0 of
## the ASCII art is the map's -Z (far) edge, which is the top of the screen.
##
## Two maps live here, picked by `map_mode` before the node enters the tree:
## the 39x39 Showdown arena and the 15x23 Nobles Cup pitch. Legend: `#` wall
## (breakable unless it is on the border), `=` wall that never breaks, `~`
## water, `b` bush, `S` spawn, `X` loot box, `0`/`1` the goal mouth team 0 and
## team 1 respectively DEFEND.
##
## The map is 39x39 — a Brawl Stars Showdown map rescaled to our fighters.
## Theirs is 60x60 tiles with a brawler about a tile wide; ours is 39x39 with a
## 1.30 m fighter on 2 m tiles, so both arenas are 60 body-widths across.
## N tracks Kits.FIGHTER_RADIUS as N = 60 * FIGHTER_RADIUS — rescale the fighter
## without rescaling this and the arena silently changes size in the only unit
## that matters.
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
## Every gap is sized for a 1.30 m fighter (Kits.FIGHTER_RADIUS) and the
## generator refuses to emit a map with a cul-de-sac or a pocket sealed behind
## a single tile — being cornered in Showdown should be a mistake you made, not
## one the map made for you. Retune it in Tools/gen_showdown_map.py and
## regenerate with `python3 Tools/gen_showdown_map.py --write`.

const SHOWDOWN_MAP := """
#######################################
#...#.bb.##.....#..............bb.....#
#...#bb.........#.......S..##...#b....#
#...bb.S~##X...##S.....##..#.....bb...#
#..bb.#~~......###bb##b##.....~~~.bb###
#.bb.~#~....bbbbbbbb.#bbXbb...~~~~.bb.#
#b#.~~#...#bbb##~~~...~..bbb....###.bb#
#b..~~...##.#.##~##...###..bb#...~~..b#
#...~~..........~##...~...........~~..#
#......#................###....#...#.##
#.#S...b.......###...bbb###...S##..#.##
#.##..bb....#bbbb.....b#bb......b..X..#
#....bb..##.#bb.....##.#bX##...#bb....#
#....bb..##bXb..##..##.##bbb....bb....#
#..##X.#.##bb#..##........bb...##b....#
#..##b.#..b###.............b#..##b##..#
#...bb~#~.bb....##...##.##.b#.~~~b#####
#...##....b.##..#X...X#.##..#.##~b#...#
#...#.......##....~.~.........##~bb...#
#...bb.............X.............bb...#
#...bb~##.........~.~....##.......#...#
#..S#b~##.#..##.#X...X#..##.b.S..##...#
#####b~~~.#b.##.##...##....bb.~#~bb...#
#..##b##..#b.............###b..#.b##..#
#....b##...bb........##..#bb##.#.X##..#
#....bb....bbb##.##..##..bXb##..bb....#
#....bb#...##Xb#.##.....bb#.##..bb....#
#..X..b......bb#b.....bbbb#....bb..##.#
##.#..##....###bbb...###.......b....#.#
##.#...#....###.S.......S......#......#
#..~~...S.......~...##~..........~~...#
#b..~~...#bb..###...##~##.#.##...~~..b#
#bb.###....bbb..~...~~~##bbb#...#~~.#b#
#.bb.~~~~...bbXbb#.bbbbbbbb....~#~.bb.#
###bb.~~~.....##b##bb###......~~#.bb..#
#...bb.....#..##......##...X##~..bb...#
#....b#...##..........#.........bb#...#
#.....bb..............#.....##.bb.#...#
#######################################
"""

## Nobles Cup pitch: 15x23 tiles (30 x 46 m), a little under half the Showdown
## arena's width and about eight seconds' run end to end. Mirrored left-to-right
## AND top-to-bottom, so neither team nor either wing has a better draw, and
## every row is a palindrome — keep it that way when retuning.
##
## The goal is recessed a row behind the back wall with unbreakable `=` posts,
## so a shot has to arrive through the three-tile mouth rather than anywhere
## along the end line. Two tiles out sits the goal wall, which leaves one
## one-tile lane straight at the mouth and otherwise forces the attack around
## the outside — that wall, not a goalkeeper, is what makes scoring work for.
## It is ordinary breakable `#`, so overtime levels it along with everything
## else and the last minute opens both goals right up.
##
## Both teams spawn on the middle third, six metres either side of the centre
## spot, so a kickoff is a race for a loose ball rather than a march upfield.
## The three tiles of a spawn row sit two tiles apart, close enough that the
## whole team is on screen together when the match starts.
## Deaths do NOT come back here — CupMode respawns a fighter inside its own
## goal mouth, which is what puts a body in front of the net.
const PITCH_MAP := """
===============
======111======
#.............#
#....#####....#
#.#.........#.#
#...bb...bb...#
#.##.......##.#
#.............#
#....S.S.S....#
#..bb.....bb..#
#.............#
#..##.....##..#
#.............#
#..bb.....bb..#
#....S.S.S....#
#.............#
#.##.......##.#
#...bb...bb...#
#.#.........#.#
#....#####....#
#.............#
======000======
===============
"""

## Blue defends the near (+Z) goal, red the far one — the player is team 0, so
## the player always attacks up the screen.
const TEAM_COLORS := [Color(0.25, 0.55, 1.0), Color(1.0, 0.32, 0.30)]

## Which map _build reads. Set it before the Arena enters the tree.
var map_mode := "showdown"

var rows: Array[String] = []
var spawn_points: Array[Vector3] = []
var box_points: Array[Vector3] = []
## Nobles Cup only. `goal_mouths[t]` is every tile of the goal team t defends;
## `goal_centers[t]` is the point a kick should be aimed at to score on them.
## `team_spawns[t]` is that team's spawn ring, split by which half it sits in.
var goal_mouths: Array[Array] = [[], []]
var goal_centers: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var team_spawns: Array[Array] = [[], []]
var columns := 0
var row_count := 0
## Tile distance from everywhere to each goal, for Nobles Cup route-finding.
## Rebuilt lazily, and only when a wall opens.
var _goal_field: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _fields_stale := true

## How far down the route to look before steering. One tile at a time reads as
## a robot hugging every corner; this straightens the run out.
const LOOKAHEAD_TILES := 5

## Only meaningful while the map is square (Showdown); the pitch is not, so
## prefer map_width/map_depth and centre() everywhere new.
func map_size() -> float:
	return columns * Kits.TILE

func map_width() -> float:
	return columns * Kits.TILE

func map_depth() -> float:
	return row_count * Kits.TILE

func centre() -> Vector3:
	return Vector3(map_width() / 2.0, 0, map_depth() / 2.0)

func _ready() -> void:
	var source: String = PITCH_MAP if map_mode == "cup" else SHOWDOWN_MAP
	for line in source.split("\n", false):
		rows.append(line)
	row_count = rows.size()
	columns = rows[0].length()
	_build()

func tile_center(col: int, row: int) -> Vector3:
	return Vector3((col + 0.5) * Kits.TILE, 0, (row + 0.5) * Kits.TILE)

## The map character at a point, untouched. Off-map reads as wall so a caller
## that walks off the edge is treated as blocked rather than crashing.
func raw_tile_at(pos: Vector3) -> String:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	if col < 0 or col >= columns or row < 0 or row >= row_count:
		return "#"
	return rows[row][col]

## The terrain at a point: spawns, box sites and goal mouths are all just
## floor, and the unbreakable `=` is wall like any other.
func tile_at(pos: Vector3) -> String:
	var ch := raw_tile_at(pos)
	if ch in ["S", "X", "0", "1"]:
		return "."
	return "#" if ch == "=" else ch

func blocks_movement(pos: Vector3) -> bool:
	return tile_at(pos) in ["#", "~"]

## Opens the tile at a world position. A wall that has been destroyed must
## leave the ASCII map as well as the scene: bot movement, Nobles Cup route
## finding and the ball's bounces all read `rows`, so a wall that is only
## freed goes on blocking every one of them — the ball would rebound off a
## gap you can see straight through, which is exactly what overtime creates.
func open_at(pos: Vector3) -> void:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	if col < 0 or col >= columns or row < 0 or row >= row_count:
		return
	if rows[row][col] != "#":
		return
	rows[row] = rows[row].substr(0, col) + "." + rows[row].substr(col + 1)
	_fields_stale = true

# MARK: routes

## Unit direction a fighter at `from` should run to reach the goal that team
## `goal_team` defends, following the map around whatever is in the way.
## Zero when it is already there or nothing connects.
##
## Nobles Cup bots need this because the goal wall sits square across the
## straight line to the mouth: a carrier steering at the goal walks into that
## wall and stalls against it, which is exactly what they did before this.
func route_to_goal(goal_team: int, from: Vector3) -> Vector3:
	if _fields_stale:
		_rebuild_fields()
	var field: PackedInt32Array = _goal_field[goal_team]
	var idx := _tile_index(from)
	if field.is_empty() or idx < 0 or field[idx] <= 0:
		return Vector3.ZERO
	var aim := from
	var at := idx
	for _step in LOOKAHEAD_TILES:
		at = _downhill(field, at)
		if at < 0:
			break
		var centre := tile_center(at % columns, at / columns)
		if not _clear_line(from, centre):
			break
		aim = centre
	var dir := aim - from
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.05 else Vector3.ZERO

func _rebuild_fields() -> void:
	for team in 2:
		_goal_field[team] = _bfs_from(goal_mouths[team])
	_fields_stale = false

## Tile distance from every walkable tile to the nearest of `sources`.
## -1 marks walls and anything sealed off from them.
func _bfs_from(sources: Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(columns * row_count)
	dist.fill(-1)
	var queue: PackedInt32Array = PackedInt32Array()
	for p: Vector3 in sources:
		var idx := _tile_index(p)
		if idx >= 0 and dist[idx] < 0:
			dist[idx] = 0
			queue.append(idx)
	var head := 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var col: int = idx % columns
		var row: int = idx / columns
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c := col + step.x
			var r := row + step.y
			if c < 0 or c >= columns or r < 0 or r >= row_count:
				continue
			var next := r * columns + c
			if dist[next] >= 0 or rows[r][c] in ["#", "=", "~"]:
				continue
			dist[next] = dist[idx] + 1
			queue.append(next)
	return dist

## The neighbouring tile one step closer to the goal, or -1 at the end.
func _downhill(field: PackedInt32Array, idx: int) -> int:
	var col: int = idx % columns
	var row: int = idx / columns
	var best := -1
	var best_d: int = field[idx]
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := col + step.x
		var r := row + step.y
		if c < 0 or c >= columns or r < 0 or r >= row_count:
			continue
		var next := r * columns + c
		if field[next] >= 0 and field[next] < best_d:
			best_d = field[next]
			best = next
	return best

## Whether a fighter can walk straight from one point to another, sampled
## against the map rather than raycast, so it agrees with blocks_movement.
func _clear_line(from: Vector3, to: Vector3) -> bool:
	var span := to - from
	span.y = 0.0
	var steps := int(ceil(span.length() / (Kits.TILE * 0.4)))
	for i in range(1, steps + 1):
		if blocks_movement(from + span * (float(i) / float(steps))):
			return false
	return true

func _tile_index(pos: Vector3) -> int:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	if col < 0 or col >= columns or row < 0 or row >= row_count:
		return -1
	return row * columns + col

func _build() -> void:
	var ts := Kits.TILE
	# Ground: one big checkered-ish plane (two greens via a grid of quads
	# would be 900 nodes; a single plane keeps 3D simple for now). Sized from
	# columns AND rows — the pitch is taller than it is wide.
	_static_box(centre() + Vector3(0, -0.5, 0),
				Vector3(map_width(), 1, map_depth()), Color(0.45, 0.70, 0.35), 1)

	_bush_centers.clear()
	_bush_tiles.clear()
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
				"=":
					# Structural: goal posts and the pitch's end walls. Never
					# joins "breakable", so overtime cannot open the goal up.
					_static_box(c + Vector3(0, 0.75, 0), Vector3(ts, 1.5, ts),
								Color(0.86, 0.88, 0.92), 1)
				"0", "1":
					var team := int(ch)
					goal_mouths[team].append(c)
					_goal_paint(c, team)
				"~":
					var w := _static_box(c + Vector3(0, 0.12, 0), Vector3(ts, 0.24, ts),
										 Color(0.30, 0.55, 0.85, 0.85), 2)
					w.add_to_group("water")
				"b":
					# Appended row-major from row 0, which is the map's -Z edge
					# and so the far side of a camera sitting at +Z. That makes
					# the MultiMesh buffer order back-to-front, which is the
					# depth sort the two transparent bush layers never get.
					_bush_centers.append(c)
					_bush_tiles.append(Vector2i(col, row))
				"S":
					spawn_points.append(c)
					# Cup teams are read off the map: team 0 defends the goal
					# at the +Z end, so it spawns in the +Z half.
					team_spawns[1 if row < row_count / 2 else 0].append(c)
				"X":
					box_points.append(c)
	_finish_goals()
	_build_bushes()

## The goal mouth is floor, so it reads as a goal only if it is painted. The
## `=` posts around it already give the frame; this is the team-coloured slab
## inside it, laid flush with the ground so nothing trips over it.
func _goal_paint(center: Vector3, team: int) -> void:
	var tint: Color = TEAM_COLORS[team]
	var slab := _static_box(center + Vector3(0, 0.02, 0),
			Vector3(Kits.TILE, 0.04, Kits.TILE), Color(tint.r, tint.g, tint.b, 0.75), 4)
	slab.collision_layer = 0   # paint only; nothing should collide with it

## Called once the whole map is read: the aim point for a shot on each goal.
func _finish_goals() -> void:
	for team in 2:
		if goal_mouths[team].is_empty():
			continue
		var sum := Vector3.ZERO
		for p: Vector3 in goal_mouths[team]:
			sum += p
		goal_centers[team] = sum / float(goal_mouths[team].size())

const GRASS_MODEL := "res://assets/tall_grass.glb"
## Half the model's height is 0.49, which sits it flush; less than that buries
## the base disc so only greenery shows above the floor.
const BUSH_LIFT := 0.33
## The clump measures 1.90 x 1.76 across its own origin. Scaling by TILE over
## its shorter axis covers a whole tile in Z and overhangs 8% in X, so
## neighbouring clumps interlock instead of leaving a seam down the tile line.
const CANOPY_SCALE := Kits.TILE / 1.761497
## The dark ground patch, a hair above the floor plane so it never z-fights.
const SKIRT_Y := 0.03
## Bush colour. The canopy multiplies the baked texture; the skirt is flat
## against the floor's Color(0.45, 0.70, 0.35) and is deliberately far darker,
## because on a top-down camera "darker" is the whole reason a player reads a
## patch as cover instead of as more grass.
const CANOPY_TINT := Color(0.50, 0.62, 0.44)
const SKIRT_FILL := Color(0.20, 0.31, 0.16)
const SKIRT_RIM := Color(0.12, 0.19, 0.09)
## How far the outline reaches into a tile, as a fraction of the tile.
const SKIRT_RIM_WIDTH := 0.14
## What a revealed bush fades to. Not 0: a ghost of the canopy keeps the patch
## legible as cover you are still standing inside.
const REVEAL_ALPHA := 0.30
const REVEAL_FEATHER := 1.1

var _bush_centers: Array[Vector3] = []
var _bush_tiles: Array[Vector2i] = []
var _bush_materials: Array[ShaderMaterial] = []

## Both bush layers fade any instance that comes within Kits.BUSH_REVEAL of
## `reveal_center`, which main.gd points at the player. That radius is the same
## one can_see() uses to decide who is hidden, so what you see through is
## exactly what you can be seen through. MODEL_MATRIX[3] is the MultiMesh
## instance's own origin, which makes the fade per-clump rather than per-vertex
## and keeps whole tiles opening together.
const CANOPY_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform vec3 canopy_tint : source_color = vec3(0.5, 0.62, 0.44);
uniform vec3 reveal_center = vec3(0.0);
uniform float reveal_radius = 4.0;
uniform float reveal_feather = 1.1;
uniform float reveal_alpha = 0.3;

varying float v_alpha;

void vertex() {
	v_alpha = mix(reveal_alpha, 1.0, smoothstep(
			reveal_radius - reveal_feather, reveal_radius + reveal_feather,
			distance(MODEL_MATRIX[3].xz, reveal_center.xz)));
}

void fragment() {
	ALBEDO = texture(base_texture, UV).rgb * canopy_tint;
	ALPHA = v_alpha;
	ROUGHNESS = 1.0;
}
"""

## The skirt is what actually makes a bush read as a TILE: a flat quad sized
## exactly to the tile, so a patch of them meets edge to edge with no seam and
## becomes one contiguous dark shape. Only an edge with no bush behind it draws
## the outline, which is what stops a 3x3 patch reading as nine squares.
const SKIRT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;

uniform vec3 fill_color : source_color = vec3(0.2, 0.31, 0.16);
uniform vec3 rim_color : source_color = vec3(0.12, 0.19, 0.09);
uniform float rim_width = 0.14;
uniform float tile_size = 2.0;
uniform vec3 reveal_center = vec3(0.0);
uniform float reveal_radius = 4.0;
uniform float reveal_feather = 1.1;
uniform float reveal_alpha = 0.3;

varying float v_alpha;
varying vec2 v_local;
varying vec4 v_open;

void vertex() {
	// -0.5..0.5 across the tile, read from local space so it does not depend on
	// how PlaneMesh happens to lay its UVs out.
	v_local = VERTEX.xz / tile_size;
	// x/y/z/w = the west/east/north/south edge is OPEN (has no bush neighbour).
	v_open = INSTANCE_CUSTOM;
	v_alpha = mix(reveal_alpha, 1.0, smoothstep(
			reveal_radius - reveal_feather, reveal_radius + reveal_feather,
			distance(MODEL_MATRIX[3].xz, reveal_center.xz)));
}

void fragment() {
	vec4 edge = vec4(v_local.x + 0.5, 0.5 - v_local.x,
					 v_local.y + 0.5, 0.5 - v_local.y);
	vec4 band = (1.0 - smoothstep(vec4(0.0), vec4(rim_width), edge)) * v_open;
	float rim = max(max(band.x, band.y), max(band.z, band.w));
	ALBEDO = mix(fill_color, rim_color, rim);
	ALPHA = v_alpha;
	ROUGHNESS = 1.0;
}
"""

## Bushes are visual only — they never block movement, and concealment stays
## logic-side in main.gd. Each tile gets two instances: the flat skirt that
## tiles with its neighbours, and a grass clump on top for volume. Both are
## MultiMeshes, so the map's 155 bushes are two draw calls rather than 155
## nodes and 1.3M triangles of scene tree.
func _build_bushes() -> void:
	_bush_materials.clear()
	if _bush_centers.is_empty():
		return
	_build_skirt()
	var mesh: Mesh = _grass_mesh()
	if mesh == null:
		_build_bushes_fallback()
		return
	_build_canopy(mesh)

func _build_skirt() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(Kits.TILE, Kits.TILE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = _bush_centers.size()
	for i in _bush_centers.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				_bush_centers[i] + Vector3(0, SKIRT_Y, 0)))
		mm.set_instance_custom_data(i, _open_edges(_bush_tiles[i]))
	var mat := _bush_material(SKIRT_SHADER)
	mat.set_shader_parameter("fill_color", SKIRT_FILL)
	mat.set_shader_parameter("rim_color", SKIRT_RIM)
	mat.set_shader_parameter("rim_width", SKIRT_RIM_WIDTH)
	mat.set_shader_parameter("tile_size", Kits.TILE)
	# Under the canopy. Both layers are transparent and cover the same ground,
	# so without an explicit order the engine sorts them by AABB and can flip
	# them from one frame to the next.
	mat.render_priority = -1
	_add_bush_layer("BushSkirt", mm, mat)

func _build_canopy(mesh: Mesh) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _bush_centers.size()
	# No yaw or scale jitter. The clumps are meant to tile: the jitter that used
	# to be here existed to stop a field reading as a tiled texture, which is
	# now precisely what it should read as.
	var basis := Basis.IDENTITY.scaled(Vector3.ONE * CANOPY_SCALE)
	for i in _bush_centers.size():
		mm.set_instance_transform(i, Transform3D(basis,
				_bush_centers[i] + Vector3(0, BUSH_LIFT * CANOPY_SCALE, 0)))
	var mat := _bush_material(CANOPY_SHADER)
	mat.set_shader_parameter("base_texture", _grass_texture(mesh))
	mat.set_shader_parameter("canopy_tint", CANOPY_TINT)
	_add_bush_layer("BushCanopy", mm, mat)

## 1.0 on each side that has no bush neighbour — the sides that get an outline.
## Order matches the shader's v_open: west, east, north, south.
func _open_edges(tile: Vector2i) -> Color:
	return Color(
			0.0 if _is_bush(tile.x - 1, tile.y) else 1.0,
			0.0 if _is_bush(tile.x + 1, tile.y) else 1.0,
			0.0 if _is_bush(tile.x, tile.y - 1) else 1.0,
			0.0 if _is_bush(tile.x, tile.y + 1) else 1.0)

func _is_bush(col: int, row: int) -> bool:
	if row < 0 or row >= row_count or col < 0 or col >= columns:
		return false
	return rows[row][col] == "b"

func _bush_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("reveal_radius", Kits.BUSH_REVEAL)
	mat.set_shader_parameter("reveal_feather", REVEAL_FEATHER)
	mat.set_shader_parameter("reveal_alpha", REVEAL_ALPHA)
	return mat

func _add_bush_layer(node_name: String, mm: MultiMesh, mat: ShaderMaterial) -> void:
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = mm
	holder.material_override = mat
	holder.name = node_name
	add_child(holder)
	_bush_materials.append(mat)

## Where the bush field opens up. main.gd points this at the player every frame.
func set_reveal_center(pos: Vector3) -> void:
	for mat in _bush_materials:
		mat.set_shader_parameter("reveal_center", pos)

## The clump mesh. Its own material is irrelevant — both layers run under a
## material_override — so this only has to find the geometry.
func _grass_mesh() -> Mesh:
	if not ResourceLoader.exists(GRASS_MODEL):
		return null
	var scene: PackedScene = load(GRASS_MODEL)
	if scene == null:
		return null
	var root: Node3D = scene.instantiate()
	var found: Mesh = null
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		found = mi.mesh
		if found != null:
			break
	root.queue_free()
	return found

func _grass_texture(mesh: Mesh) -> Texture2D:
	for si in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(si)
		if mat is BaseMaterial3D and mat.albedo_texture != null:
			return mat.albedo_texture
	return null

## Pre-model look, kept so a build without the grass asset still has bushes.
## The skirt is built either way, so these only supply the volume on top.
func _build_bushes_fallback() -> void:
	for center in _bush_centers:
		for offset in [Vector3(-0.4, 0.5, -0.3), Vector3(0.45, 0.55, 0.2), Vector3(-0.05, 0.7, 0.35)]:
			var m := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.75
			sph.height = 1.5
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.22, 0.50, 0.20, 0.9)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sph.material = mat
			m.mesh = sph
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
