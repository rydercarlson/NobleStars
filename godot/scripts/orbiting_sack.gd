class_name OrbitingSack
extends Node3D
## Anders' Super: a readable, fast circular threat around the owner.

var game: Node
var owner_fighter: Fighter
var weapon: Dictionary
var damage := 0
var on_hit := Callable()
var _age := 0.0
var _angle := 0.0
var _hit_at: Dictionary = {}

func _ready() -> void:
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.88, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.75, 0.55)
	mesh.material = mat
	visual.mesh = mesh
	add_child(visual)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_fighter) or owner_fighter.is_dead():
		queue_free()
		return
	_age += delta
	if _age >= float(weapon.duration):
		queue_free()
		return
	_angle += delta * 11.0
	# Circle close to the body: this Super's job is peeling divers off him, so
	# the ring has to cover the space an attacker actually stands in. `range`
	# is the reach that tells a bot when to pop it, not the orbit size.
	var radius: float = weapon.get("orbit_radius", weapon.range)
	global_position = owner_fighter.global_position + Vector3(cos(_angle) * radius, 0.9,
			sin(_angle) * radius)
	rotation += Vector3(12.0, 16.0, 8.0) * delta
	for target in game.fighters:
		if target == owner_fighter or target.is_dead():
			continue
		if target.global_position.distance_to(global_position) > float(weapon.radius) + 0.7:
			continue
		var key: int = target.get_instance_id()
		if _age - float(_hit_at.get(key, -10.0)) < float(weapon.get("hit_cooldown", 0.45)):
			continue
		_hit_at[key] = _age
		if on_hit.is_valid():
			on_hit.call(target, self)
