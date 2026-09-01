class_name Shockwave
extends MeshInstance3D
## A fast expanding, fading ground ring. It can be a full circle (ground
## smash) or a directional arc (Kovacs' clap).

var radius := 3.0
var tint := Color.WHITE
var direction := Vector3.ZERO
var arc_degrees := 360.0

const DURATION := 0.30
const BAND_WIDTH := 0.32
var _time := 0.0

func _ready() -> void:
	mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	_rebuild(0.0)

func _process(delta: float) -> void:
	_time += delta
	if _time >= DURATION:
		queue_free()
		return
	_rebuild(_time / DURATION)

func _rebuild(progress: float) -> void:
	var im: ImmediateMesh = mesh
	im.clear_surfaces()
	var outer := maxf(0.1, radius * progress)
	var inner := maxf(0.0, outer - BAND_WIDTH - radius * 0.08 * progress)
	var alpha := (1.0 - progress) * 0.9
	var half := deg_to_rad(arc_degrees) / 2.0
	var base := atan2(direction.x, direction.z) if direction.length() > 0.01 else 0.0
	var steps := maxi(12, int(arc_degrees / 12.0))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0 := base - half + (2.0 * half * i / steps)
		var a1 := base - half + (2.0 * half * (i + 1) / steps)
		var in0 := Vector3(sin(a0), 0, cos(a0)) * inner
		var in1 := Vector3(sin(a1), 0, cos(a1)) * inner
		var out0 := Vector3(sin(a0), 0.08, cos(a0)) * outer
		var out1 := Vector3(sin(a1), 0.08, cos(a1)) * outer
		im.surface_set_color(Color(tint, alpha * 0.15)); im.surface_add_vertex(in0)
		im.surface_set_color(Color(tint.lightened(0.5), alpha)); im.surface_add_vertex(out0)
		im.surface_set_color(Color(tint.lightened(0.5), alpha)); im.surface_add_vertex(out1)
		im.surface_set_color(Color(tint, alpha * 0.15)); im.surface_add_vertex(in0)
		im.surface_set_color(Color(tint.lightened(0.5), alpha)); im.surface_add_vertex(out1)
		im.surface_set_color(Color(tint, alpha * 0.15)); im.surface_add_vertex(in1)
	im.surface_end()
