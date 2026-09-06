class_name GasRing
extends Node3D
## Shrinking poison gas, ported from the 2D game (including the full-closure
## rule so matches can't stalemate).

const FIRST_SHRINK_DELAY := 18.0
const SHRINK_INTERVAL := 12.0
const TILES_PER_SHRINK := 2
const TICK_INTERVAL := 1.0

## How long one step spends in motion. The cadence above is untouched — the ring
## still waits FIRST_SHRINK_DELAY, still steps every SHRINK_INTERVAL, and still
## steps TILES_PER_SHRINK — this is only how long the wall takes to travel those
## two tiles, so three quarters of every cycle is still calm and the step is
## still an event you notice.
##
## `inset` is a FLOAT and EVERYTHING reads the eased value, the rules included.
## Easing only the visuals was the other option on the table and it is a lie the
## player cannot see through: for the whole ease you would burn while standing
## on ground that plainly reads as safe. Every caller outside this file goes
## through `contains()` / `depth_inside()` / `safe_min()` / `safe_max()` /
## `safe_center()`, which were floats already, so the bots' `gas_depth` steering
## gets a continuously moving edge for free.
##
## The rate is the thing to check when retuning it: a smoothstep peaks at 1.5x
## its average, so two tiles in three seconds tops out at 2.0 m/s against a
## 4.48 m/s worst-case fighter (`Kits.SPEED_VERY_SLOW`). The wall must always be
## walkable-out-of, or the ease turns into an execution.
const SHRINK_EASE := 3.0

## The gas takes a share of the target's own maximum health, not a flat number.
## A flat 500 killed a 3500 HP Hammy in seven ticks and a cube-loaded 8850 HP
## Kovacs in eighteen, so the ring hit hardest exactly the fighters least able
## to win the cubes that made them tanky. A share kills anyone in TICKS_TO_KILL
## seconds — a full-health fighter caught outside has that long to get back in,
## whatever kit it is and however loaded it is. Cubes buy survivability against
## other fighters, never against the map.
const TICKS_TO_KILL := 6.0

## Tiles eaten off each side. Eased, so it is fractional for SHRINK_EASE seconds
## after every step. Named `inset` because main.gd and the net snapshot read it.
var inset := 0.0
var map_tiles := 39
## Where the current step is heading. The cadence is scheduled off this rather
## than off `inset`, so a step is never booked twice because the ease is behind.
var _target_inset := 0.0
var _step_from := 0.0
var _step_at := -1.0
var _next_shrink_at := 0.0
var _next_tick_at := 0.0
## The host's ring runs on its own clock; a wifi client's is written straight
## from the snapshot and must not be stepped locally on top of it. `start()` is
## the only thing that turns the clock on and the client never calls it.
var _running := false
var _overlay: Array[Node3D] = []

func start(now: float, tiles: int) -> void:
	map_tiles = tiles
	_next_shrink_at = now + FIRST_SHRINK_DELAY
	_running = true

## Now that `inset` eases, this turns true partway through the LAST step rather
## than on it — about a third of a second early on a 39-tile map. Everyone is
## standing in gas by then either way.
func is_fully_closed() -> bool:
	return inset * 2.0 >= float(map_tiles)

func safe_min() -> float:
	return inset * Kits.TILE

func safe_max() -> float:
	return (map_tiles - inset) * Kits.TILE

func contains(pos: Vector3) -> bool:
	if is_fully_closed():
		return false
	return pos.x >= safe_min() and pos.x <= safe_max() \
		and pos.z >= safe_min() and pos.z <= safe_max()

## Distance from pos to the nearest gas edge; negative when outside the safe zone.
func depth_inside(pos: Vector3) -> float:
	if is_fully_closed():
		return -INF
	return minf(minf(pos.x - safe_min(), safe_max() - pos.x),
			minf(pos.z - safe_min(), safe_max() - pos.z))

func safe_center() -> Vector3:
	var mid := map_tiles * Kits.TILE / 2.0
	return Vector3(mid, 0, mid)

## Returns the fighters damaged this tick.
func tick(now: float, fighters: Array) -> Array:
	if not _running:
		return []
	var max_inset: float = ceil(map_tiles / 2.0)
	if now >= _next_shrink_at and _target_inset < max_inset:
		_step_from = _target_inset
		_target_inset = minf(max_inset, _target_inset + TILES_PER_SHRINK)
		_step_at = now
		_next_shrink_at = now + SHRINK_INTERVAL
	_advance(now)
	if now < _next_tick_at:
		return []
	_next_tick_at = now + TICK_INTERVAL
	if inset <= 0.0:
		return []
	var damaged := []
	for f in fighters:
		if not f.is_dead() and not contains(f.global_position):
			f.take_damage(damage_for(f), now)
			damaged.append(f)
	return damaged

## Pure function of `now`, so the wall's position never depends on how many
## frames went by — the same reason the ball integrates rather than accumulates.
func _advance(now: float) -> void:
	if _step_at < 0.0:
		return
	var t := clampf((now - _step_at) / SHRINK_EASE, 0.0, 1.0)
	inset = lerpf(_step_from, _target_inset, t * t * (3.0 - 2.0 * t))

## Rounded up, so TICKS_TO_KILL ticks always finish a fighter off rather than
## leaving it on a sliver from integer division.
func damage_for(f) -> int:
	return maxi(1, int(ceil(float(f.max_health) / TICKS_TO_KILL)))

# ---------------------------------------------------------------------------
# The look.
#
# Two layers, both built ONCE and driven per frame off the eased `inset`:
# a bank of Meshy gas clouds standing on the safe zone's edge, and the danger
# fill behind it. Nothing here is rebuilt on a step — that was the other half of
# the old jump. The bank reseeded itself off `rng.seed = 7 + inset`, so every
# cloud in it changed shape and place at the same instant the wall teleported,
# and the fill was four flat translucent boxes reallocated the same frame.
# ---------------------------------------------------------------------------

const CLOUD_MODEL := "res://assets/gas_cloud.glb"
const CLOUD_SPACING := 1.9      # the cloud is ~1.9 wide; overlap closes the bank
const CLOUD_LIFT := 1.1
## Perpendicular jitter leans OUT into the gas rather than sitting on the line,
## so the safe side of the boundary stays a crisp lip and the bank has depth.
const CLOUD_OUT_BIAS := 0.55

var _clouds: MultiMeshInstance3D
var _cloud_mesh: Mesh
## Per instance, in edge space: which side (0 far, 1/2 the flanks, 3 near), how
## far along it (0-1), its own offsets, scale and yaw. World positions are
## recomputed from these and the current edge every frame — this array is what
## replaces reseeding an rng.
var _cloud_edge: PackedInt32Array = PackedInt32Array()
var _cloud_u: PackedFloat32Array = PackedFloat32Array()
var _cloud_along: PackedFloat32Array = PackedFloat32Array()
var _cloud_out: PackedFloat32Array = PackedFloat32Array()
var _cloud_scale: PackedFloat32Array = PackedFloat32Array()
var _cloud_yaw: PackedFloat32Array = PackedFloat32Array()
var _drift_t := 0.0

## The danger fill. One shader over two full-map quads: a mat on the floor and a
## haze at head height, drifting at different rates so the pair reads as volume
## from the one steep angle the camera ever shows. Not four translucent boxes —
## a flat slab tints the wall band, the grass and the surround by exactly the
## same amount and comes out as a purple filter laid over the picture rather
## than as gas sitting on the ground.
const GAS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// The safe rectangle in world XZ. Everything outside it is gas; the shader is
// handed the eased edge every frame and there is no geometry to rebuild.
uniform vec2 safe_lo = vec2(0.0);
uniform vec2 safe_hi = vec2(78.0);
// The arena slab, so the quad can fade out before its own straight edge does
// the fading for it. The mat's rim lands on the slab lip and hides there; the
// haze is 2.6 m up, so its rectangle projects well clear of the slab's and its
// edge was the most obviously wrong line on screen.
uniform vec2 map_lo = vec2(0.0);
uniform vec2 map_hi = vec2(78.0);
uniform float rim_fade = 1.2;
uniform float strength = 0.0;    // 0 before the first shrink, 1 once it is under way
// Nearly zero green, and brighter than the purple that is wanted on screen.
// Blending happens in LINEAR space, and the grass's green channel is 0.45
// linear against this purple's 0.003 — so a plausible-looking dark violet at
// 60% still comes out the other side as grey-green, which is exactly what the
// old flat slab did and what this was supposed to fix. Two passes went into
// picking colours in sRGB and wondering where the purple had gone. The way out
// is to go nearly opaque and let ALBEDO be, more or less, the answer.
uniform vec3 body_color : source_color = vec3(0.46, 0.02, 0.64);
uniform vec3 deep_color : source_color = vec3(0.28, 0.01, 0.44);
uniform vec3 front_color : source_color = vec3(0.95, 0.45, 1.0);
uniform float max_alpha = 0.93;
uniform float fade = 1.6;        // metres the fill takes to reach full density
uniform float wobble = 3.0;      // how far the coarse octave pushes the front about
uniform float front_width = 0.7; // the bright lip right on the front
uniform float front_gain = 0.85;
uniform float coarse = 0.055;
uniform float fine = 0.21;
uniform float drift = 0.10;      // metres per second the pattern crawls
uniform float wisps = 0.18;      // on the ALPHA: 0 is one sheet, 1 is separate puffs
uniform float billow = 0.55;     // on the COLOUR, which at this alpha is where the structure has to live

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
	vec2 c = (safe_lo + safe_hi) * 0.5;
	vec2 h = (safe_hi - safe_lo) * 0.5;
	vec2 q = abs(v_world.xz - c) - h;
	// Signed distance to the safe rectangle, positive out in the gas. Same
	// box_sdf the pitch markings use, and for the same reason: the corners join
	// instead of overshooting the way four clipped half-planes do. When the ring
	// has closed past itself h goes negative and this is positive everywhere,
	// which is exactly what full closure should look like.
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);

	vec2 crawl = vec2(TIME * drift, TIME * -drift * 0.63);
	float n_c = vnoise(v_world.xz * coarse + crawl);
	float n_f = vnoise(v_world.xz * fine - crawl * 1.7);

	// Pushing the front about with the coarse octave is the whole reason this
	// does not read as a rectangle. Straight edges are what made it a box.
	float edge = sd + (n_c - 0.5) * wobble;
	// A smoothstep on the noise rather than the noise itself: it gives distinct
	// puffs with clear ground between them instead of an evenly grainy sheet,
	// which is the difference between gas and a dirty lens.
	float wisp = mix(1.0 - wisps, 1.0, smoothstep(0.28, 0.78, n_f * 0.55 + n_c * 0.45));
	float a = smoothstep(0.0, fade, edge) * max_alpha * wisp;
	float lip = exp(-pow((edge - front_width) / front_width, 2.0));
	a = max(a, lip * front_gain * max_alpha);

	// Density is what stops this reading as a filter laid over the picture. At
	// the old 0.22 the grass under it still won, and purple over green averages
	// to a dead grey — the fill looked dirty rather than dangerous. It is nearly
	// solid now and can afford to be: the mat sits at ankle height and a fighter
	// standing in the gas occludes it, so only the thin haze is ever between the
	// camera and anyone worth seeing.
	vec3 col = mix(body_color, deep_color, smoothstep(fade, fade * 3.5, edge));
	col *= 1.0 - billow * 0.5 + billow * (n_f * 0.6 + n_c * 0.4);
	col = mix(col, front_color, clamp(lip * front_gain, 0.0, 1.0));

	// Fade the quad out before its own edge arrives.
	vec2 mc = (map_lo + map_hi) * 0.5;
	vec2 mh = (map_hi - map_lo) * 0.5;
	vec2 mq = abs(v_world.xz - mc) - mh;
	float msd = length(max(mq, vec2(0.0))) + min(max(mq.x, mq.y), 0.0);
	a *= 1.0 - smoothstep(-rim_fade, rim_fade, msd);

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * strength;
}
"""

const GAS_OVERHANG := 8.0       # room for the rim fade to finish inside the quad
const MAT_HEIGHT := 0.09
const HAZE_HEIGHT := 2.60       # above the walls and about a head over a fighter

var _mat_mesh: MeshInstance3D
var _haze_mesh: MeshInstance3D
var _mat_material: ShaderMaterial
var _haze_material: ShaderMaterial
var _built_for := -1

## Kept because `main.gd`'s net client sets `inset` straight off a snapshot and
## then asks the visuals to catch up. Nothing is rebuilt any more: this makes
## sure the layers exist and syncs them to the inset that is there now.
func _rebuild_overlay() -> void:
	_ensure_overlay()
	_sync_overlay()

func _ensure_overlay() -> void:
	if _built_for == map_tiles:
		return
	_built_for = map_tiles
	for n in _overlay:
		n.queue_free()
	_overlay.clear()
	if _clouds != null:
		_clouds.queue_free()
		_clouds = null
	_build_fill()
	_build_cloud_bank()

func _build_fill() -> void:
	var full := map_tiles * Kits.TILE
	var span := full + GAS_OVERHANG * 2.0
	var centre := Vector3(full / 2.0, 0, full / 2.0)
	_mat_material = _gas_material(full)
	_mat_material.render_priority = 1
	_mat_mesh = _gas_plane(span, centre + Vector3(0, MAT_HEIGHT, 0), _mat_material)
	# The haze is thinner, slower to thicken and crawls faster than the mat, so
	# the pair separates under the camera's pitch instead of reading as one
	# decal. It has to stay light: it is the only layer a fighter standing in
	# the gas is ever seen THROUGH.
	_haze_material = _gas_material(full)
	_haze_material.render_priority = 3
	_haze_material.set_shader_parameter("max_alpha", 0.28)
	_haze_material.set_shader_parameter("fade", 4.0)
	_haze_material.set_shader_parameter("wobble", 4.2)
	_haze_material.set_shader_parameter("coarse", 0.048)
	_haze_material.set_shader_parameter("fine", 0.135)
	_haze_material.set_shader_parameter("drift", 0.19)
	_haze_material.set_shader_parameter("front_gain", 0.30)
	_haze_material.set_shader_parameter("wisps", 0.85)
	_haze_material.set_shader_parameter("billow", 0.85)
	_haze_material.set_shader_parameter("rim_fade", 4.0)
	_haze_material.set_shader_parameter("body_color", Color(0.66, 0.20, 0.96))
	_haze_material.set_shader_parameter("deep_color", Color(0.50, 0.10, 0.82))
	_haze_mesh = _gas_plane(span, centre + Vector3(0, HAZE_HEIGHT, 0), _haze_material)

func _gas_material(full: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GAS_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("map_lo", Vector2.ZERO)
	mat.set_shader_parameter("map_hi", Vector2(full, full))
	return mat

func _gas_plane(span: float, at: Vector3, mat: ShaderMaterial) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(span, span)
	plane.material = mat
	var m := MeshInstance3D.new()
	m.mesh = plane
	m.position = at
	# Two map-sized quads over the arena would otherwise throw the whole floor
	# into shade the moment the gas turned on.
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	_overlay.append(m)
	return m

func _cloud_mesh_or_null() -> Mesh:
	if _cloud_mesh != null:
		return _cloud_mesh
	if not ResourceLoader.exists(CLOUD_MODEL):
		return null
	var scene: PackedScene = load(CLOUD_MODEL)
	if scene == null:
		return null
	var root: Node3D = scene.instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			_cloud_mesh = mi.mesh
			for si in _cloud_mesh.get_surface_count():
				var mat = _cloud_mesh.surface_get_material(si)
				if mat is BaseMaterial3D:
					mat.metallic = 0.0
					mat.roughness = 1.0
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color = Color(0.80, 0.55, 1.0, 0.88)
					# A little glow of its own, so the bank reads as gas rather
					# than as purple cotton wool sitting on the grass.
					mat.emission_enabled = true
					mat.emission = Color(0.34, 0.08, 0.48)
					mat.emission_energy_multiplier = 0.6
					# Between the fill's two layers: the mat is on the floor
					# under the bank, the haze is overhead in front of it.
					mat.render_priority = 2
			break
	root.queue_free()
	return _cloud_mesh

## Every cloud is stored in EDGE space — side, position along it, its own
## offsets — and turned into a world transform each frame from wherever the
## eased edge is now. That is the whole fix for the pattern popping: the rng
## runs once, at a constant seed, and never again.
##
## The count per edge is fixed at what the map's FULL width needs and the clouds
## bunch up as the ring closes, rather than being culled as the perimeter
## shortens. Culling is the obvious alternative and it is worse twice over: a
## cloud that vanishes is exactly the pop this change exists to remove, and
## dropping instances out of a fixed buffer breaks the one thing that makes a
## MultiMesh of transparent instances sort — the order they were written in.
## Late in a match the bank reads thicker, which is the right way to be wrong.
func _build_cloud_bank() -> void:
	_cloud_edge = PackedInt32Array()
	_cloud_u = PackedFloat32Array()
	_cloud_along = PackedFloat32Array()
	_cloud_out = PackedFloat32Array()
	_cloud_scale = PackedFloat32Array()
	_cloud_yaw = PackedFloat32Array()
	var mesh: Mesh = _cloud_mesh_or_null()
	if mesh == null:
		return
	var full := map_tiles * Kits.TILE
	var per_edge: int = maxi(2, int(ceil(full / CLOUD_SPACING)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Edge order is far, then the two flanks, then near. A MultiMesh gets no
	# per-instance depth sort, so buffer order IS the painter's order under a
	# camera at +Z — the same thing that makes the bush layers work.
	for edge in 4:
		for j in per_edge:
			_cloud_edge.append(edge)
			_cloud_u.append((float(j) + 0.5) / float(per_edge))
			_cloud_along.append(rng.randf_range(-0.45, 0.45))
			_cloud_out.append(rng.randf_range(-0.5, 1.6) + CLOUD_OUT_BIAS)
			_cloud_scale.append(rng.randf_range(1.25, 1.95))
			_cloud_yaw.append(rng.randf_range(0.0, TAU))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _cloud_edge.size()
	_clouds = MultiMeshInstance3D.new()
	_clouds.multimesh = mm
	_clouds.name = "GasClouds"
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Every instance transform is rewritten in _process, which physics
	# interpolation warns about (and would smear, since it expects them to move
	# on the physics tick). The bank drifts on render time by design.
	_clouds.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_clouds)

## The bank and the fill both recompute from `inset` every frame — that is what
## makes an eased inset creep instead of teleport, and it is the same work
## whether the ring is moving or still.
func _process(delta: float) -> void:
	_drift_t += delta
	_ensure_overlay()
	_sync_overlay()

func _sync_overlay() -> void:
	var lo := safe_min()
	var hi := safe_max()
	# Fades the whole thing up over the first two thirds of a tile, so nothing
	# is painted on a map that has not started closing yet. Short on purpose:
	# scaling the bank up from nothing over any longer than this scatters a row
	# of specks along the border wall, which reads as confetti and not as gas.
	var on := smoothstep(0.0, 0.30, inset)
	if _mat_material != null:
		_mat_material.set_shader_parameter("safe_lo", Vector2(lo, lo))
		_mat_material.set_shader_parameter("safe_hi", Vector2(hi, hi))
		_mat_material.set_shader_parameter("strength", on)
		_haze_material.set_shader_parameter("safe_lo", Vector2(lo, lo))
		_haze_material.set_shader_parameter("safe_hi", Vector2(hi, hi))
		_haze_material.set_shader_parameter("strength", on)
		var lit := on > 0.001
		_mat_mesh.visible = lit
		_haze_mesh.visible = lit
	if _clouds == null:
		return
	# ...and out again as the ring closes on itself, where there is no edge left
	# to stand a bank on. The floor under `on` is not decoration: scaling a whole
	# 78 m edge's worth of clouds up from zero puts a line of ten-pixel specks
	# along the border, which reads as confetti, so the bank arrives at just over
	# half size and grows the rest of the way.
	var closing := clampf((hi - lo) / (Kits.TILE * 2.0), 0.0, 1.0)
	_clouds.visible = on > 0.05 and closing > 0.001
	if not _clouds.visible:
		return
	var bank := (0.55 + 0.45 * on) * closing
	var mm: MultiMesh = _clouds.multimesh
	for i in _cloud_edge.size():
		var t: float = lerpf(lo, hi, _cloud_u[i]) + _cloud_along[i]
		var outward: float = _cloud_out[i]
		var pos: Vector3
		match _cloud_edge[i]:
			0: pos = Vector3(t, 0, lo - outward)
			1: pos = Vector3(lo - outward, 0, t)
			2: pos = Vector3(hi + outward, 0, t)
			_: pos = Vector3(t, 0, hi + outward)
		var phase: float = float(i) * 0.37
		var size: float = _cloud_scale[i] * bank
		var bob: float = sin(_drift_t * 0.9 + phase) * 0.12
		var yaw: float = _cloud_yaw[i] + sin(_drift_t * 0.35 + phase) * 0.18
		pos.y = CLOUD_LIFT * size + bob
		mm.set_instance_transform(i,
				Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), pos))
