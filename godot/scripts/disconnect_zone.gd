class_name DisconnectZone
extends Node3D
## The lingering half of Leon's Super. The controller's landing burst is
## resolved once, by main.gd; this is what it leaves behind — a glitching
## signal field that keeps re-silencing anyone standing in it until it
## expires. It never deals damage, so clients spawn it as a pure visual and
## only the host reads `contains()` to apply the silence.

const FADE := 0.5     ## seconds of fade-out at the end of the field's life
const TAIL := 0.35    ## silence carried out of the field on stepping off it
const STEPS := 32

## Signal loss reads as an RGB split, so the rim is drawn three times: the
## kit-colored band plus a cyan and a magenta ghost that jump around it.
const GHOST_A := Color(0.25, 0.95, 1.0)
const GHOST_B := Color(1.0, 0.2, 0.85)

var radius := 3.4
var duration := 3.5
var tint := Color(1.0, 0.2, 0.85)
var owner_fighter: Fighter

var _mesh: ImmediateMesh
var _elapsed := 0.0
var _glitch_at := 0.0
var _split_a := Vector2.ZERO
var _split_b := Vector2.ZERO

func _ready() -> void:
	add_to_group("disconnect_zone")
	var mi := MeshInstance3D.new()
	_mesh = ImmediateMesh.new()
	mi.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)
	_rebuild()

## Flat (XZ) containment test — the field is a ground circle, so height is
## deliberately ignored: a leaping fighter is still inside it.
func contains(point: Vector3) -> bool:
	var v := point - global_position
	v.y = 0.0
	return v.length() <= radius

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	# The split snaps to a new offset a few times a second instead of sliding,
	# which is what makes it read as a dropped signal rather than a glow.
	if _elapsed >= _glitch_at:
		_glitch_at = _elapsed + randf_range(0.05, 0.15)
		_split_a = Vector2(randf_range(-0.24, 0.24), randf_range(-0.24, 0.24))
		_split_b = Vector2(randf_range(-0.24, 0.24), randf_range(-0.24, 0.24))
	_rebuild()

func _rebuild() -> void:
	var fade := 1.0 - clampf((_elapsed - (duration - FADE)) / FADE, 0.0, 1.0)
	var pulse := 0.85 + 0.15 * sin(_elapsed * 9.0)
	var alpha := fade * pulse
	var band := radius * 0.14
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# The fill has to read as denied ground against a bright green floor, so it
	# is darkened rather than just tinted — a faint wash disappears on grass.
	_ring(0.0, radius - band, tint.darkened(0.45), alpha * 0.38, Vector2.ZERO, 0.02)
	_ring(radius - band, radius, tint.lightened(0.35), alpha * 0.7, Vector2.ZERO, 0.05)
	_ring(radius - band * 0.45, radius + band * 0.3, GHOST_A, alpha * 0.35, _split_a, 0.07)
	_ring(radius - band * 0.45, radius + band * 0.3, GHOST_B, alpha * 0.35, _split_b, 0.07)
	_mesh.surface_end()

## One flat annulus (inner == 0 gives a filled disc), offset in XZ so the
## ghost rims can sit slightly off-center, and lifted to avoid z-fighting.
func _ring(inner: float, outer: float, color: Color, alpha: float,
		offset: Vector2, height: float) -> void:
	var base := Vector3(offset.x, height, offset.y)
	var c := Color(color, alpha)
	for i in STEPS:
		var a0 := TAU * i / STEPS
		var a1 := TAU * (i + 1) / STEPS
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(base + d0 * inner)
		_mesh.surface_add_vertex(base + d0 * outer)
		_mesh.surface_add_vertex(base + d1 * outer)
		_mesh.surface_add_vertex(base + d0 * inner)
		_mesh.surface_add_vertex(base + d1 * outer)
		_mesh.surface_add_vertex(base + d1 * inner)
