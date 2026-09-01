class_name GlitchSignal
extends Projectile
## Leon's Super, "Disconnect": a big corrupted signal that flies straight and
## detonates on contact or at max range. The main scene owns the explosion
## (area damage plus a silence that blocks attacking, not moving).

signal expired

var _core: MeshInstance3D
var _ghosts: Array = []
var _emitted := false

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = (1 << 0) | (1 << 2) | (1 << 5)  # walls | fighters | boxes
	monitoring = true

	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = weapon.radius
	col.shape = s
	add_child(col)

	# Corrupted packet: a dark core with two RGB-split ghosts jittering around
	# it, like a signal tearing apart mid-flight.
	_core = _shard(Color(0.12, 0.14, 0.16), weapon.radius)
	for c in [Color(0.1, 0.95, 0.9), Color(0.95, 0.2, 0.85)]:
		var g := _shard(c, weapon.radius * 0.9)
		g.transparency = 0.45
		_ghosts.append(g)

func _shard(c: Color, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(r * 2.0, r * 2.0, r * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c * 0.8
	mesh.material = mat
	m.mesh = mesh
	add_child(m)
	return m

func _physics_process(delta: float) -> void:
	global_position += direction * weapon.speed * delta
	_core.rotate_y(6.0 * delta)
	# Glitch jitter: the ghosts snap to new offsets a few times a second.
	for i in _ghosts.size():
		var g: MeshInstance3D = _ghosts[i]
		g.rotation = _core.rotation
		if randf() < 12.0 * delta:
			g.position = Vector3(randf_range(-0.22, 0.22), randf_range(-0.12, 0.12),
					randf_range(-0.22, 0.22))
	if global_position.distance_to(origin) > weapon.range and not _emitted:
		_emitted = true
		expired.emit()
