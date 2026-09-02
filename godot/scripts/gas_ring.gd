class_name GasRing
extends Node3D
## Shrinking poison gas, ported from the 2D game (including the full-closure
## rule so matches can't stalemate).

const FIRST_SHRINK_DELAY := 18.0
const SHRINK_INTERVAL := 12.0
const TILES_PER_SHRINK := 2
const TICK_INTERVAL := 1.0

## The gas takes a share of the target's own maximum health, not a flat number.
## A flat 500 killed a 3500 HP Hammy in seven ticks and a cube-loaded 8850 HP
## Kovacs in eighteen, so the ring hit hardest exactly the fighters least able
## to win the cubes that made them tanky. A share kills anyone in TICKS_TO_KILL
## seconds — a full-health fighter caught outside has that long to get back in,
## whatever kit it is and however loaded it is. Cubes buy survivability against
## other fighters, never against the map.
const TICKS_TO_KILL := 6.0

var inset := 0
var map_tiles := 39
var _next_shrink_at := 0.0
var _next_tick_at := 0.0
var _overlay: Array[Node3D] = []

func start(now: float, tiles: int) -> void:
	map_tiles = tiles
	_next_shrink_at = now + FIRST_SHRINK_DELAY

func is_fully_closed() -> bool:
	return inset * 2 >= map_tiles

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
	var max_inset := int(ceil(map_tiles / 2.0))
	if now >= _next_shrink_at and inset < max_inset:
		inset += TILES_PER_SHRINK
		_next_shrink_at = now + SHRINK_INTERVAL
		_rebuild_overlay()
	if now < _next_tick_at:
		return []
	_next_tick_at = now + TICK_INTERVAL
	if inset == 0:
		return []
	var damaged := []
	for f in fighters:
		if not f.is_dead() and not contains(f.global_position):
			f.take_damage(damage_for(f), now)
			damaged.append(f)
	return damaged

## Rounded up, so TICKS_TO_KILL ticks always finish a fighter off rather than
## leaving it on a sliver from integer division.
func damage_for(f) -> int:
	return maxi(1, int(ceil(float(f.max_health) / TICKS_TO_KILL)))

const CLOUD_MODEL := "res://assets/gas_cloud.glb"
const CLOUD_SPACING := 1.9      # the cloud is ~1.9 wide; overlap closes the bank
const CLOUD_LIFT := 1.1

var _clouds: MultiMeshInstance3D
var _cloud_mesh: Mesh
var _cloud_base: Array[Transform3D] = []
var _drift_t := 0.0

## The safe-zone edge is a bank of Meshy gas clouds — one MultiMesh, one draw
## call — with a faint purple fill over everything outside it so the danger
## zone still reads from above. If the model is missing the fill stands alone.
func _rebuild_overlay() -> void:
	for n in _overlay:
		n.queue_free()
	_overlay.clear()
	if _clouds != null:
		_clouds.queue_free()
		_clouds = null
	_cloud_base.clear()
	var full := map_tiles * Kits.TILE
	var lo := safe_min()
	var hi := safe_max()
	var bands: Array = [
		[Vector3(full / 2, 0, lo / 2), Vector3(full, 4, lo)],                        # far strip
		[Vector3(full / 2, 0, (hi + full) / 2), Vector3(full, 4, full - hi)],        # near strip
		[Vector3(lo / 2, 0, (lo + hi) / 2), Vector3(lo, 4, hi - lo)],                # left
		[Vector3((hi + full) / 2, 0, (lo + hi) / 2), Vector3(full - hi, 4, hi - lo)],# right
	]
	for band in bands:
		var size: Vector3 = band[1]
		if size.x < 0.05 or size.z < 0.05:
			continue
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.15, 0.62, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material = mat
		m.mesh = box
		m.position = band[0] + Vector3(0, 2, 0)
		add_child(m)
		_overlay.append(m)
	if inset <= 0 or is_fully_closed():
		return
	_build_cloud_bank(lo, hi)

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
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color = Color(0.85, 0.6, 1.0, 0.88)
			break
	root.queue_free()
	return _cloud_mesh

func _build_cloud_bank(lo: float, hi: float) -> void:
	var mesh: Mesh = _cloud_mesh_or_null()
	if mesh == null:
		return
	# One cloud every CLOUD_SPACING along the four edges of the safe square,
	# jittered so the bank looks like weather rather than a fence.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + inset
	var points: Array[Vector3] = []
	var n: int = maxi(1, int((hi - lo) / CLOUD_SPACING))
	for i in n:
		var t: float = lo + (float(i) + 0.5) * (hi - lo) / float(n)
		points.append(Vector3(t, 0, lo))
		points.append(Vector3(t, 0, hi))
		points.append(Vector3(lo, 0, t))
		points.append(Vector3(hi, 0, t))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		var scale: float = rng.randf_range(1.35, 1.85)
		var yaw: float = rng.randf_range(0.0, TAU)
		var jitter := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		var xf := Transform3D(basis, points[i] + jitter + Vector3(0, CLOUD_LIFT * scale, 0))
		_cloud_base.append(xf)
		mm.set_instance_transform(i, xf)
	_clouds = MultiMeshInstance3D.new()
	_clouds.multimesh = mm
	_clouds.name = "GasClouds"
	add_child(_clouds)

## A slow roll so the bank breathes; cheap enough to do on the CPU for a
## few hundred instances.
func _process(delta: float) -> void:
	if _clouds == null:
		return
	_drift_t += delta
	var mm: MultiMesh = _clouds.multimesh
	for i in _cloud_base.size():
		var base: Transform3D = _cloud_base[i]
		var phase: float = float(i) * 0.37
		var bob: float = sin(_drift_t * 0.9 + phase) * 0.12
		var turn := Basis(Vector3.UP, sin(_drift_t * 0.35 + phase) * 0.18)
		mm.set_instance_transform(i, Transform3D(turn * base.basis, base.origin + Vector3(0, bob, 0)))
