class_name HitSpark
extends MeshInstance3D
## The burst where a hit lands, and the flash at the barrel when one is fired.
##
## Built the way `shockwave.gd` is — an ImmediateMesh rebuilt each frame, drawn
## unshaded from vertex colours, freeing itself when it is done — rather than
## with GPUParticles3D. The match camera is a fixed steep top-down, so a spray
## drawn flat in XZ reads correctly from the only angle anyone ever sees it
## from, costs one draw call, and needs no art file, which is the same reason
## every sound in this game is synthesized.
##
## One class covers both jobs because they are the same shape at different
## settings: a hit is a wide spray of shards, a muzzle flash is a narrow, short,
## faster one. `main.gd:_hit_spark` and `:_muzzle_flash` are the two presets.

var tint := Color(1.0, 0.92, 0.55)
## Which way the thing that caused this was travelling; the spray fans around
## it, so a shot throws its shards on past the target rather than symmetrically.
var direction := Vector3.ZERO
## Half-angle of the fan, in radians.
var cone := 1.15
## How far the longest shard reaches, in metres. The match camera shows about
## 23 m across 1280 px — roughly 55 px per metre — and a fighter is only ~70 px
## wide, so anything under a metre is a handful of pixels and reads as nothing.
## The first pass at 1.5 m with darts spanning half that was invisible on
## screen despite rendering perfectly.
var spread := 2.4
var shards := 7
var duration := 0.22
## Where the burst sits above the floor — chest height for a hit on a fighter,
## barrel height for a muzzle flash.
var height := 1.0
## The bright pop at the origin. Wanted on an impact, too fat on a muzzle flash.
var core := true

var _time := 0.0
var _dirs: Array[Vector3] = []
var _lens: Array[float] = []

func _ready() -> void:
	mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Additive, so overlapping shards and two hits landing together build up
	# into a brighter flash instead of compositing into a flat wash.
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Drawn over everything, the way the damage popups are. A burst sits at
	# chest height ON the fighter it belongs to, and the match camera looks
	# down at 60° — so with depth testing the body hides its own hit, and a
	# muzzle flash at the barrel disappears behind the fighter that fired it.
	mat.no_depth_test = true
	material_override = mat
	var base: float = atan2(direction.x, direction.z) if direction.length() > 0.01 \
			else randf() * TAU
	for i in shards:
		var a: float = base + randf_range(-cone, cone)
		_dirs.append(Vector3(sin(a), 0, cos(a)))
		_lens.append(spread * randf_range(0.45, 1.0))
	_rebuild(0.0)

func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	_rebuild(_time / duration)

func _rebuild(p: float) -> void:
	var im: ImmediateMesh = mesh
	im.clear_surfaces()
	# Shards fly out fast and decelerate; the whole burst fades linearly.
	var travel: float = 1.0 - (1.0 - p) * (1.0 - p)
	var alpha: float = 1.0 - p
	var hot: Color = Color(tint.lightened(0.5), alpha)
	var tail: Color = Color(tint, 0.0)
	var up := Vector3(0, height, 0)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _dirs.size():
		var d: Vector3 = _dirs[i]
		var side := Vector3(d.z, 0, -d.x)
		var outer: float = _lens[i] * travel
		var inner: float = outer * 0.28
		var w: float = 0.22 * alpha
		# A tapered dart: wide at the trailing end, a point at the leading one.
		im.surface_set_color(hot); im.surface_add_vertex(up + d * inner + side * w)
		im.surface_set_color(hot); im.surface_add_vertex(up + d * inner - side * w)
		im.surface_set_color(tail); im.surface_add_vertex(up + d * outer)
	if core:
		# A disc that pops and shrinks, so the first frame reads as the moment
		# of contact rather than as shards already in flight.
		var r: float = 0.8 * (1.0 - p) * (1.0 - p) + 0.12
		var ca: Color = Color(tint.lightened(0.7), alpha * alpha)
		var edge: Color = Color(tint, 0.0)
		var steps := 10
		for i in steps:
			var a0: float = TAU * i / steps
			var a1: float = TAU * (i + 1) / steps
			im.surface_set_color(ca); im.surface_add_vertex(up)
			im.surface_set_color(edge); im.surface_add_vertex(up + Vector3(sin(a0), 0, cos(a0)) * r)
			im.surface_set_color(edge); im.surface_add_vertex(up + Vector3(sin(a1), 0, cos(a1)) * r)
	im.surface_end()
