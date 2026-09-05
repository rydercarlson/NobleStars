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
	# The hole changes the outline of everything around it: a wall that was an
	# interior tile a moment ago now has an open side and needs its rim drawn.
	_wall_meshes.erase(Vector2i(col, row))
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_apply_wall_edges(Vector2i(col, row) + step)

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

# MARK: match presentation

## How the match camera frames the arena. Brawl Stars uses a steep,
## low-distortion perspective rather than a true orthographic view: near walls
## grow subtly and off-axis boxes reveal different sides. A 60 degree pitch and
## a very narrow 7 degree vertical FOV reproduce that 2.5D feel. The 105.5 m
## offset preserves the pre-perspective camera's ~12.9 m centre-plane height,
## so the framing changed without unexpectedly changing combat visibility.
##
## Here rather than in main.gd so `tools/render_map.gd` can frame a shot the
## same way without importing main.gd — which does not compile outside a game
## run, since it reaches for the Net autoload.
const MATCH_CAM_OFFSET := Vector3(0, 91.4, 52.8)
const MATCH_CAM_FOV := 7.0

# MARK: match lighting

## The match's key light and environment. They live here rather than in main.gd
## because the terrain look is only as real as the light it is judged under —
## `tools/render_map.gd` renders the arena outside a match and has to light it
## identically, and a second copy of these numbers would have drifted the first
## time either was touched.
static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	# `shadow_enabled` alone rendered nothing for the life of the project, and
	# this is why: the match camera sits 105.5 m back behind a 7 degree lens, so
	# the whole arena is further away than the 100 m DEFAULT shadow range.
	# Shadows were on, correct, and entirely outside the volume they are drawn
	# in. Everything visible lies between roughly 85 m and 125 m out, so the
	# range only has to clear that — and keeping it tight is also what keeps the
	# map crisp, since one orthogonal split spends its whole texture on this
	# span. Widen it and the shadows go soft again for no gain.
	sun.directional_shadow_max_distance = 145.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# A flat top-down map is nearly all surfaces facing the light, where normal
	# bias does the work and depth bias only detaches a shadow from its caster.
	sun.shadow_normal_bias = 1.6
	sun.shadow_bias = 0.03
	# Not black: a cartoon arena wants a shadow to read as shape rather than as
	# a hole, and the ambient term is doing the rest of the lifting.
	sun.shadow_opacity = 0.62
	return sun

static func make_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	# Exactly what the surround fades to at its outer ring, so the scenery meets
	# the background with no visible seam. At a 60 degree pitch behind a 7 degree
	# lens the view never contains the horizon, so a procedural sky would only
	# ever show its own ground hemisphere — this is that colour, directly.
	e.background_color = SURROUND_HORIZON
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.76, 0.82)
	e.ambient_light_energy = 0.68
	return e

# MARK: terrain look

## The arena's palette and its three terrain shaders. Everything here is flat
## colour plus a fragment shader — no art files — for the same reason the sounds
## are synthesized: a fixed steep top-down camera only ever shows one angle, so
## the look is cheaper to compute than it is to author.
## The checker is deliberately near-invisible tile to tile. A 10% step read as
## a chessboard and pulled the eye off the fighters; what the floor actually
## needs is enough structure to tell you how far a tile is, which the seam and
## the per-tile mottle give without the grid becoming the subject.
const GRASS_A := Color(0.45, 0.70, 0.35)
const GRASS_B := Color(0.441, 0.686, 0.341)
const GRASS_SEAM := Color(0.35, 0.56, 0.27)
## The slab the arena sits on. Seen at the near edge and past the border walls,
## it is what makes the map read as a raised platform rather than as a plane
## that simply stops.
const SLAB_COLOR := Color(0.33, 0.25, 0.18)
const SLAB_DEPTH := 3.0
## Ground outside the arena, and how far it reaches before it fades to the sky.
const SURROUND_COLOR := Color(0.26, 0.40, 0.24)
const SURROUND_HORIZON := Color(0.47, 0.64, 0.74)
const SURROUND_MARGIN := 46.0
const SURROUND_DROP := 1.1

const WALL_TOP := Color(0.72, 0.55, 0.39)
const WALL_SIDE := Color(0.47, 0.33, 0.22)
const WALL_EDGE := Color(0.24, 0.15, 0.09)
## `=` walls: goal frames and the pitch end line. Cool and pale, so a wall that
## can never be shot out never reads like one that can.
## Bright white blew out: the pitch's end rows are 30 tiles of `=` between
## them, so whatever colour this is, there is a lot of it directly behind the
## goal a player is shooting at.
const STRUCT_TOP := Color(0.79, 0.82, 0.88)
const STRUCT_SIDE := Color(0.51, 0.54, 0.61)
const STRUCT_EDGE := Color(0.25, 0.28, 0.34)
const WALL_HEIGHT := 1.5

const WATER_DEEP := Color(0.10, 0.30, 0.60)
const WATER_SHALLOW := Color(0.27, 0.57, 0.86)
## Not white. A single-tile pond is 2 m across, so a shoreline wide enough to
## see at all is a large fraction of it — the first pass at 24% of a tile per
## side left almost no water in the middle of one.
const WATER_FOAM := Color(0.72, 0.88, 0.98)
const WATER_TOP := 0.24
## Nobles Cup's pitch markings. Painted by the floor shader rather than laid
## down as geometry, so a line costs nothing and cannot z-fight with the grass.
const PITCH_LINE := Color(0.88, 0.94, 0.88)
const GOAL_NET := Color(0.94, 0.96, 1.0)
const GOAL_FRAME := Color(0.95, 0.96, 0.98)
const GOAL_POST_RADIUS := 0.17
## Deliberately above WALL_HEIGHT: a crossbar level with the wall behind it
## disappears into it at this camera pitch.
const GOAL_FRAME_HEIGHT := 2.15

## The goal mouth. The net is a grid over a team-coloured floor that darkens
## toward the back, which is the whole of the depth cue — the recess is only one
## tile deep and a top-down camera cannot see into it at all.
const GOAL_NET_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 team_color : source_color = vec3(1.0, 0.32, 0.30);
uniform vec3 net_color : source_color = vec3(0.94, 0.96, 1.0);
uniform float cell = 0.44;
uniform float thickness = 0.11;
uniform float goal_line_z = 0.0;
uniform float depth_span = 2.0;
uniform float depth_dir = 1.0;

varying vec3 v_world;
varying vec3 v_nrm;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = NORMAL;
}

void fragment() {
	if (v_nrm.y < 0.5) {
		ALBEDO = team_color * 0.30;
	} else {
		// 0 on the goal line, 1 at the back of the net.
		float t = clamp((v_world.z - goal_line_z) * depth_dir / depth_span, 0.0, 1.0);
		vec3 col = mix(team_color * 0.88, team_color * 0.30, t);
		vec2 g = abs(fract(v_world.xz / cell) - 0.5);
		float net = smoothstep(0.5 - thickness, 0.5, max(g.x, g.y));
		// The net fades into the dark at the back, which is what sells a recess
		// that is only two metres deep and seen from almost straight above.
		col = mix(col, net_color, net * mix(0.60, 0.18, t));
		// The line the ball actually has to cross.
		col = mix(col, net_color, 1.0 - smoothstep(0.07, 0.15, t * depth_span));
		ALBEDO = col;
	}
	ROUGHNESS = 1.0;
}
"""

## The floor. One plane, one draw call: the tile checker, the per-tile mottle
## and the seam all come out of the world position rather than out of geometry,
## so a 39x39 arena costs exactly what a 1x1 one would.
##
## Every terrain shader here splits its top face from its sides on a
## model-space normal carried down as a varying — `NORMAL` is view space by the
## time the fragment stage sees it, so testing `NORMAL.y` there yaws with the
## camera instead of pointing at the sky.
const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 grass_a : source_color = vec3(0.45, 0.70, 0.35);
uniform vec3 grass_b : source_color = vec3(0.441, 0.686, 0.341);
uniform vec3 seam_color : source_color = vec3(0.35, 0.56, 0.27);
uniform vec3 slab_color : source_color = vec3(0.33, 0.25, 0.18);
uniform float tile_size = 2.0;
uniform float seam_width = 0.05;
uniform float seam_strength = 0.08;
uniform float mottle = 0.05;
uniform float patch_strength = 0.14;
uniform float slab_depth = 3.0;
// Nobles Cup only. Zero on Showdown, where the branch costs one comparison and
// the whole marking block is never evaluated.
uniform float pitch_lines = 0.0;
uniform vec2 pitch_min = vec2(0.0);
uniform vec2 pitch_max = vec2(0.0);
uniform vec3 line_color : source_color = vec3(0.88, 0.94, 0.88);
uniform float line_width = 0.17;
uniform float line_strength = 0.36;
uniform float circle_radius = 3.6;
// Half-width and depth of the box in front of each goal.
uniform vec2 goal_area = vec2(5.0, 4.0);

varying vec3 v_world;
varying vec3 v_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Signed distance to a rectangle: negative inside, zero on the border. Every
// marking below is one of these, drawn as a band around its own zero, which is
// why a corner joins cleanly instead of overshooting the way four clipped
// half-planes do.
float box_sdf(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float stripe(float d, float w) {
	return 1.0 - smoothstep(w * 0.55, w, abs(d));
}

// The markings, in world XZ. Mirrored through the centre spot, so the pitch is
// symmetric for the same reason PITCH_MAP is: neither end may be the better
// one to defend.
float pitch_mark(vec2 p) {
	vec2 c = (pitch_min + pitch_max) * 0.5;
	vec2 h = (pitch_max - pitch_min) * 0.5;
	vec2 q = p - c;
	float m = stripe(box_sdf(q, h - vec2(0.5)), line_width);
	m = max(m, stripe(q.y, line_width) * (1.0 - step(h.x - 0.5, abs(q.x))));
	float r = length(q);
	m = max(m, stripe(r - circle_radius, line_width));
	m = max(m, 1.0 - smoothstep(0.22, 0.34, r));
	vec2 gp = vec2(q.x, abs(q.y) - (h.y - goal_area.y * 0.5));
	m = max(m, stripe(box_sdf(gp, vec2(goal_area.x, goal_area.y * 0.5)), line_width));
	return clamp(m, 0.0, 1.0);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = NORMAL;
}

void fragment() {
	if (v_nrm.y > 0.5) {
		vec2 t = v_world.xz / tile_size;
		vec2 cell = floor(t);
		vec3 col = mix(grass_a, grass_b, mod(cell.x + cell.y, 2.0));
		col *= 1.0 + (hash21(cell) - 0.5) * mottle;
		// Broad organic patches on top of the grid. This, not the checker, is
		// what stops a 78 m field reading as one colour: a regular pattern at
		// tile scale only ever looks like a chessboard, however faint it is
		// made, while two octaves at 18 m and 6 m read as ground.
		float patch = vnoise(v_world.xz * 0.055) * 0.66 + vnoise(v_world.xz * 0.17) * 0.34;
		col *= 1.0 + (patch - 0.5) * patch_strength;
		vec2 f = abs(fract(t) - 0.5);
		float seam = smoothstep(0.5 - seam_width, 0.5, max(f.x, f.y));
		col = mix(col, seam_color, seam * seam_strength);
		if (pitch_lines > 0.5) {
			col = mix(col, line_color, pitch_mark(v_world.xz) * line_strength);
		}
		ALBEDO = col;
	} else {
		ALBEDO = slab_color * mix(0.40, 1.0, clamp(1.0 + v_world.y / slab_depth, 0.0, 1.0));
	}
	ROUGHNESS = 1.0;
}
"""

## The ground outside the arena. Without it the map's edge is raw sky, which
## makes the arena look like it stops rather than like it is somewhere. The
## fade is measured from the map RECTANGLE, not from its centre, so it starts
## the same distance out on a corner as on a side — and it reaches the horizon
## colour before the plane's own outer edge, which is what keeps that edge from
## being the thing you notice.
const SURROUND_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 near_color : source_color = vec3(0.26, 0.40, 0.24);
uniform vec3 far_color : source_color = vec3(0.47, 0.64, 0.74);
uniform vec2 arena_center = vec2(0.0);
uniform vec2 arena_extent = vec2(40.0);
uniform float fade_start = 6.0;
uniform float fade_end = 34.0;
uniform float tile_size = 2.0;

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = near_color * (1.0 + (vnoise(v_world.xz * 0.045) - 0.5) * 0.30);
	vec2 q = abs(v_world.xz - arena_center) - arena_extent;
	float d = length(max(q, vec2(0.0)));
	ALBEDO = mix(col, far_color, smoothstep(fade_start, fade_end, d));
	ROUGHNESS = 1.0;
}
"""

## Walls read as one mass with a crisp outline for exactly the reason the
## bushes do: the rim is drawn only on a side with no wall behind it, so a
## block of nine is one shape rather than nine squares in a grid. The per-wall
## edge mask rides an `instance uniform`, so every wall on the map shares one
## material and one shader while still keeping its own outline — and a wall
## that gets shot out hands its neighbours a fresh mask through `open_at`.
##
## The sides carry a gradient to a dark base and a hard line under the cap.
## That line is what separates a wall's top from its face at a 60 degree pitch,
## where the two are only a few shades apart under one directional light.
const WALL_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

instance uniform vec4 open_edges = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec3 top_color : source_color = vec3(0.72, 0.55, 0.39);
uniform vec3 side_color : source_color = vec3(0.47, 0.33, 0.22);
uniform vec3 edge_color : source_color = vec3(0.24, 0.15, 0.09);
uniform float tile_size = 2.0;
uniform float wall_height = 1.5;
uniform float rim_width = 0.13;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float max4(vec4 v) {
	return max(max(v.x, v.y), max(v.z, v.w));
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 col;
	if (v_nrm.y > 0.5) {
		// x/y/z/w = the west/east/north/south side is OPEN, matching _open_edges.
		vec2 p = v_local.xz / tile_size;
		vec4 edge = vec4(p.x + 0.5, 0.5 - p.x, p.y + 0.5, 0.5 - p.y);
		float rim = max4((1.0 - smoothstep(vec4(rim_width * 0.55), vec4(rim_width), edge))
				* open_edges);
		// A lit lip immediately inside the outline. Two bands rather than one
		// soft gradient is what makes a wall read as struck rather than painted.
		float lip = max4((smoothstep(vec4(rim_width), vec4(rim_width * 1.4), edge)
				- smoothstep(vec4(rim_width * 1.9), vec4(rim_width * 2.7), edge))
				* open_edges);
		col = mix(top_color, top_color * 1.11, clamp(lip, 0.0, 1.0));
		col = mix(col, edge_color, rim);
		col *= 1.0 + (hash21(floor(v_world.xz / tile_size)) - 0.5) * 0.07;
	} else {
		float h = clamp(v_local.y / wall_height + 0.5, 0.0, 1.0);
		col = mix(mix(edge_color, side_color, 0.30), side_color, h);
		col = mix(col, edge_color, smoothstep(0.88, 1.0, h));
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
"""

## Water is opaque, which is a change: the old translucent slabs each blended
## against the floor AND against each other, so a pond showed a grid of seams
## where its tiles overlapped. Depth is drawn instead of transmitted, the ripple
## is two crossed travelling sines, and the shoreline foam uses the same
## merge-aware edge mask as the walls, so a pond gets an outline and its
## interior tile lines vanish.
const WATER_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

instance uniform vec4 open_edges = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec3 deep_color : source_color = vec3(0.10, 0.30, 0.60);
uniform vec3 shallow_color : source_color = vec3(0.27, 0.57, 0.86);
uniform vec3 foam_color : source_color = vec3(0.72, 0.88, 0.98);
uniform float tile_size = 2.0;
uniform float foam_width = 0.11;
uniform float foam_strength = 0.8;
uniform float wave_scale = 0.85;
uniform float wave_speed = 0.5;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_nrm;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = NORMAL;
}

void fragment() {
	if (v_nrm.y > 0.5) {
		vec2 w = v_world.xz * wave_scale;
		float t = TIME * wave_speed;
		float ripple = (sin(w.x + t) + sin(w.y * 1.31 - t * 0.83)) * 0.25 + 0.5;
		vec3 col = mix(deep_color, shallow_color, ripple);
		vec2 p = v_local.xz / tile_size;
		vec4 edge = vec4(p.x + 0.5, 0.5 - p.x, p.y + 0.5, 0.5 - p.y);
		vec4 band = (1.0 - smoothstep(vec4(0.0), vec4(foam_width), edge)) * open_edges;
		float foam = max(max(band.x, band.y), max(band.z, band.w));
		foam *= foam_strength * (0.72 + 0.28 * sin(TIME * 2.1 + v_world.x * 1.7 + v_world.z));
		ALBEDO = mix(col, foam_color, clamp(foam, 0.0, 1.0));
		ROUGHNESS = 0.16;
		SPECULAR = 0.65;
	} else {
		ALBEDO = deep_color * 0.5;
		ROUGHNESS = 0.7;
	}
}
"""

## One material per terrain kind, shared by every tile of it. Per-tile
## variation is world position (floor) or an instance uniform (walls, water).
var _wall_mat: ShaderMaterial
var _struct_mat: ShaderMaterial
var _water_mat: ShaderMaterial
## tile -> the MeshInstance3D whose `open_edges` describes it. Walls only:
## water never changes shape mid-match, so its mask is set once and forgotten.
var _wall_meshes: Dictionary = {}

func _build() -> void:
	var ts := Kits.TILE
	_build_terrain_materials()
	_build_ground()
	_build_surround()

	_bush_centers.clear()
	_bush_tiles.clear()
	_wall_meshes.clear()
	var water_tiles: Array[Vector2i] = []
	for row in row_count:
		for col in columns:
			var ch := rows[row][col]
			var c := tile_center(col, row)
			match ch:
				"#":
					var is_border := row == 0 or col == 0 or row == row_count - 1 or col == columns - 1
					var wall := _shaded_box(c + Vector3(0, WALL_HEIGHT / 2.0, 0),
										   Vector3(ts, WALL_HEIGHT, ts), _wall_mat, 1)
					_wall_meshes[Vector2i(col, row)] = _mesh_of(wall)
					if not is_border:
						wall.add_to_group("breakable")
						# Stable id so net play can replicate wall destruction.
						wall.name = "Wall_%d_%d" % [row, col]
				"=":
					# Structural: goal posts and the pitch's end walls. Never
					# joins "breakable", so overtime cannot open the goal up.
					var s := _shaded_box(c + Vector3(0, WALL_HEIGHT / 2.0, 0),
										Vector3(ts, WALL_HEIGHT, ts), _struct_mat, 1)
					_wall_meshes[Vector2i(col, row)] = _mesh_of(s)
				"0", "1":
					goal_mouths[int(ch)].append(c)
				"~":
					var w := _shaded_box(c + Vector3(0, WATER_TOP / 2.0, 0),
										Vector3(ts, WATER_TOP, ts), _water_mat, 2)
					w.add_to_group("water")
					_mesh_of(w).set_instance_shader_parameter(
							"open_edges", _open_sides(Vector2i(col, row), "~"))
					water_tiles.append(Vector2i(col, row))
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
	for tile: Vector2i in _wall_meshes:
		_apply_wall_edges(tile)
	_finish_goals()
	_build_bushes()

## Built once and shared. A 39x39 arena has ~400 walls; giving each its own
## material would be 400 shader compiles' worth of pipeline state for a look
## that differs only by which sides get an outline.
func _build_terrain_materials() -> void:
	_wall_mat = _shader_material(WALL_SHADER)
	_wall_mat.set_shader_parameter("top_color", WALL_TOP)
	_wall_mat.set_shader_parameter("side_color", WALL_SIDE)
	_wall_mat.set_shader_parameter("edge_color", WALL_EDGE)
	_wall_mat.set_shader_parameter("tile_size", Kits.TILE)
	_wall_mat.set_shader_parameter("wall_height", WALL_HEIGHT)

	_struct_mat = _shader_material(WALL_SHADER)
	_struct_mat.set_shader_parameter("top_color", STRUCT_TOP)
	_struct_mat.set_shader_parameter("side_color", STRUCT_SIDE)
	_struct_mat.set_shader_parameter("edge_color", STRUCT_EDGE)
	_struct_mat.set_shader_parameter("tile_size", Kits.TILE)
	_struct_mat.set_shader_parameter("wall_height", WALL_HEIGHT)

	_water_mat = _shader_material(WATER_SHADER)
	_water_mat.set_shader_parameter("deep_color", WATER_DEEP)
	_water_mat.set_shader_parameter("shallow_color", WATER_SHALLOW)
	_water_mat.set_shader_parameter("foam_color", WATER_FOAM)
	_water_mat.set_shader_parameter("tile_size", Kits.TILE)

## The arena slab. Sized from columns AND rows — the pitch is taller than it is
## wide — and deep enough that its side is a visible lip rather than a hairline.
func _build_ground() -> void:
	var mat := _shader_material(GROUND_SHADER)
	mat.set_shader_parameter("grass_a", GRASS_A)
	mat.set_shader_parameter("grass_b", GRASS_B)
	mat.set_shader_parameter("seam_color", GRASS_SEAM)
	mat.set_shader_parameter("slab_color", SLAB_COLOR)
	mat.set_shader_parameter("tile_size", Kits.TILE)
	mat.set_shader_parameter("slab_depth", SLAB_DEPTH)
	if map_mode == "cup":
		var rect := _playable_rect()
		mat.set_shader_parameter("pitch_lines", 1.0)
		mat.set_shader_parameter("pitch_min", rect.position)
		mat.set_shader_parameter("pitch_max", rect.end)
		mat.set_shader_parameter("line_color", PITCH_LINE)
	var ground := _shaded_box(centre() + Vector3(0, -SLAB_DEPTH / 2.0, 0),
			Vector3(map_width(), SLAB_DEPTH, map_depth()), mat, 1)
	ground.name = "Ground"

## Two triangles of scenery, no collision. Nothing can reach it — the border
## wall ring is solid — so it exists purely to stop the map's edge being sky.
func _build_surround() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(map_width() + SURROUND_MARGIN * 2.0,
			map_depth() + SURROUND_MARGIN * 2.0)
	var mat := _shader_material(SURROUND_SHADER)
	mat.set_shader_parameter("near_color", SURROUND_COLOR)
	mat.set_shader_parameter("far_color", SURROUND_HORIZON)
	mat.set_shader_parameter("arena_center", Vector2(centre().x, centre().z))
	mat.set_shader_parameter("arena_extent",
			Vector2(map_width() / 2.0, map_depth() / 2.0))
	mat.set_shader_parameter("fade_start", 6.0)
	mat.set_shader_parameter("fade_end", SURROUND_MARGIN * 0.75)
	mat.set_shader_parameter("tile_size", Kits.TILE)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = centre() + Vector3(0, -SURROUND_DROP, 0)
	mi.name = "Surround"
	# It sits below and outside everything, and it is huge: letting it cast into
	# the one directional shadow map would spend the whole range on scenery.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## The world rect of everything a fighter can stand on. Walls, the `=` end
## rows and the goal mouths are all excluded — the mouth in particular, because
## a touchline drawn through the back of the net is a touchline in the wrong
## place.
func _playable_rect() -> Rect2:
	var lo := Vector2i(columns, row_count)
	var hi := Vector2i(-1, -1)
	for row in row_count:
		for col in columns:
			if rows[row][col] in ["#", "=", "0", "1"]:
				continue
			lo = Vector2i(mini(lo.x, col), mini(lo.y, row))
			hi = Vector2i(maxi(hi.x, col), maxi(hi.y, row))
	if hi.x < lo.x:
		return Rect2()
	return Rect2(Vector2(lo) * Kits.TILE, Vector2(hi - lo + Vector2i.ONE) * Kits.TILE)

func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat

## 1.0 on each side of `tile` whose neighbour is not the same terrain — the
## sides that get an outline. Order matches the shaders' `open_edges` and the
## bush skirt's `_open_edges`: west, east, north, south. Off-map counts as
## matching, so the border ring is not outlined against the void.
func _open_sides(tile: Vector2i, kinds: String) -> Color:
	return Color(
			0.0 if _tile_is(tile.x - 1, tile.y, kinds) else 1.0,
			0.0 if _tile_is(tile.x + 1, tile.y, kinds) else 1.0,
			0.0 if _tile_is(tile.x, tile.y - 1, kinds) else 1.0,
			0.0 if _tile_is(tile.x, tile.y + 1, kinds) else 1.0)

func _tile_is(col: int, row: int, kinds: String) -> bool:
	if row < 0 or row >= row_count or col < 0 or col >= columns:
		return true   # off-map: no outline against the edge of the world
	return kinds.contains(rows[row][col])

## Re-reads one wall's outline from the map. Called for every wall at build and
## for the four neighbours of a hole when one is shot out.
func _apply_wall_edges(tile: Vector2i) -> void:
	var mesh: Variant = _wall_meshes.get(tile)
	if mesh == null or not is_instance_valid(mesh):
		return
	(mesh as MeshInstance3D).set_instance_shader_parameter(
			"open_edges", _open_sides(tile, "#="))

func _mesh_of(body: StaticBody3D) -> MeshInstance3D:
	return body.get_node("Mesh") as MeshInstance3D

## Called once the whole map is read: the aim point for a shot on each goal,
## and the goal itself.
func _finish_goals() -> void:
	for team in 2:
		if goal_mouths[team].is_empty():
			continue
		var sum := Vector3.ZERO
		for p: Vector3 in goal_mouths[team]:
			sum += p
		goal_centers[team] = sum / float(goal_mouths[team].size())
		_build_goal(team)

## A net painted on the mouth floor and a real frame standing on the goal line.
## Before this a goal was a flat team-coloured rectangle recessed in a grey
## wall, which read as a painted panel rather than as somewhere you score: from
## a 60 degree camera the mouth FLOOR is nearly all of a goal you can see, so
## that is where the net has to be, and the frame is what says how tall it is.
##
## Everything is derived from `goal_mouths`, never from PITCH_MAP's row numbers,
## so a wider mouth or a second pitch gets its goal for free.
func _build_goal(team: int) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in goal_mouths[team]:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var half := Kits.TILE / 2.0
	var x0 := lo.x - half
	var x1 := hi.x + half
	var z_mid := (lo.y + hi.y) / 2.0
	var depth := (hi.y - lo.y) + Kits.TILE
	# Which way the pitch lies from the mouth. The goal line is the mouth's own
	# edge on that side, and the net deepens away from it.
	var toward: float = signf(centre().z - z_mid)
	var line_z: float = z_mid + toward * depth / 2.0

	var mat := _shader_material(GOAL_NET_SHADER)
	mat.set_shader_parameter("team_color", TEAM_COLORS[team])
	mat.set_shader_parameter("net_color", GOAL_NET)
	mat.set_shader_parameter("goal_line_z", line_z)
	mat.set_shader_parameter("depth_span", depth)
	mat.set_shader_parameter("depth_dir", -toward)
	var slab := _shaded_box(Vector3((x0 + x1) / 2.0, 0.025, z_mid),
			Vector3(x1 - x0, 0.05, depth), mat, 4)
	slab.collision_layer = 0   # paint only; nothing should collide with it
	slab.name = "GoalNet%d" % team

	# The frame is taller than the 1.5 m walls on purpose: at this camera pitch
	# a bar level with the wall behind it disappears into it.
	var frame := StandardMaterial3D.new()
	frame.albedo_color = GOAL_FRAME
	frame.roughness = 0.5
	for x: float in [x0, x1]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = GOAL_POST_RADIUS
		cyl.bottom_radius = GOAL_POST_RADIUS
		cyl.height = GOAL_FRAME_HEIGHT
		cyl.material = frame
		var post := MeshInstance3D.new()
		post.mesh = cyl
		post.position = Vector3(x, GOAL_FRAME_HEIGHT / 2.0, line_z)
		add_child(post)
	var box := BoxMesh.new()
	box.size = Vector3(x1 - x0 + GOAL_POST_RADIUS * 2.0,
			GOAL_POST_RADIUS * 1.8, GOAL_POST_RADIUS * 1.8)
	box.material = frame
	var bar := MeshInstance3D.new()
	bar.mesh = box
	bar.position = Vector3((x0 + x1) / 2.0, GOAL_FRAME_HEIGHT, line_z)
	add_child(bar)

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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _shaded_box(pos, size, mat, layer)

## A solid box wearing `mat`. The mesh is named so callers that need to reach
## it for an instance uniform can (`_mesh_of`); the material is shared, so the
## per-tile part of the look has to ride on the instance rather than on a copy.
func _shaded_box(pos: Vector3, size: Vector3, mat: Material, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
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
