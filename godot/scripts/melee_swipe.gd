class_name MeleeSwipe
extends MeshInstance3D
## Animated melee slash: a hot leading blade sweeps across the attack arc
## leaving a fading trail band behind it. The band is an annular sector (not a
## filled pie from the feet) and the outer edge lifts slightly so the slash
## reads as a swing under the 2.5D camera, not a floor decal.

var base_angle := 0.0   # facing, radians (atan2(x, z) convention, matches Fighter)
var half_angle := 1.0   # half the arc width, radians
var reach := 3.0
var tint := Color.WHITE
var sweep_sign := 1.0   # +1 sweeps one way, -1 the other (combo hits alternate)

const DURATION := 0.16
const FADE_EXTRA := 0.10      # linger + fade after the sweep completes
const INNER_FRAC := 0.35      # inner radius of the band, fraction of reach
const OUTER_LIFT := 0.45      # outer-edge height, gives the arc a dished tilt

var _t := 0.0

func _ready() -> void:
	mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	_rebuild()

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION + FADE_EXTRA:
		queue_free()
		return
	_rebuild()

func _rebuild() -> void:
	var im: ImmediateMesh = mesh
	im.clear_surfaces()
	var p := clampf(_t / DURATION, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - p, 2.0)   # fast start, decelerating finish
	var swept := 2.0 * half_angle * eased  # how much of the arc the blade has crossed
	var fade := 1.0 - clampf((_t - DURATION) / FADE_EXTRA, 0.0, 1.0)

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Trail band from the arc's start edge to the blade, brightest at the blade.
	var steps := 14
	for i in steps:
		var f0 := float(i) / steps
		var f1 := float(i + 1) / steps
		var a0 := swept * f0
		var a1 := swept * f1
		var c0 := Color(tint, 0.8 * pow(f0, 1.2) * fade)
		var c1 := Color(tint, 0.8 * pow(f1, 1.2) * fade)
		_slice(im, a0, a1, c0, c1)
	# The blade itself: a thin near-white wedge at the leading edge.
	var hot := tint.lightened(0.7)
	_slice(im, swept, swept + 0.18,
		Color(hot, 1.0 * fade), Color(hot, 0.45 * fade))
	im.surface_end()

## rel0/rel1 are angles measured from the arc's start edge along the sweep.
func _slice(im: ImmediateMesh, rel0: float, rel1: float, c0: Color, c1: Color) -> void:
	var a0 := base_angle + (-half_angle + rel0) * sweep_sign
	var a1 := base_angle + (-half_angle + rel1) * sweep_sign
	var d0 := Vector3(sin(a0), 0, cos(a0))
	var d1 := Vector3(sin(a1), 0, cos(a1))
	var lift := Vector3(0, OUTER_LIFT, 0)
	var in0 := d0 * reach * INNER_FRAC
	var in1 := d1 * reach * INNER_FRAC
	var out0 := d0 * reach + lift
	var out1 := d1 * reach + lift
	im.surface_set_color(Color(c0, c0.a * 0.4))
	im.surface_add_vertex(in0)
	im.surface_set_color(c0)
	im.surface_add_vertex(out0)
	im.surface_set_color(c1)
	im.surface_add_vertex(out1)
	im.surface_set_color(Color(c0, c0.a * 0.4))
	im.surface_add_vertex(in0)
	im.surface_set_color(c1)
	im.surface_add_vertex(out1)
	im.surface_set_color(Color(c1, c1.a * 0.25))
	im.surface_add_vertex(in1)
