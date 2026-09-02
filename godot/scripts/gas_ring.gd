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

func _rebuild_overlay() -> void:
	for n in _overlay:
		n.queue_free()
	_overlay.clear()
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
		mat.albedo_color = Color(0.5, 0.2, 0.65, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = mat
		m.mesh = box
		m.position = band[0] + Vector3(0, 2, 0)
		add_child(m)
		_overlay.append(m)
