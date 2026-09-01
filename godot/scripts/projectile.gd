class_name Projectile
extends Area3D
## A pellet, shell, or controller button in flight.

var weapon: Dictionary
var damage := 0
var owner_fighter: Fighter
var direction := Vector3.FORWARD
var origin := Vector3.ZERO
var already_hit: Array = []
var button_text := ""
var button_color := Color.WHITE
## Set by the main scene to its _on_projectile_hit. The swept ray below reports
## through this rather than through body_entered; see _physics_process.
var on_sweep_hit := Callable()
var _flight_time := 0.0

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = (1 << 0) | (1 << 2) | (1 << 5)  # walls | fighters | boxes
	monitoring = true

	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = weapon.radius
	col.shape = s
	add_child(col)

	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = button_color if button_text != "" else \
			(Color(1.0, 0.45, 0.15) if weapon.destroys_walls else Color(1.0, 0.85, 0.3))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.6
	mesh.material = mat
	m.mesh = mesh
	add_child(m)
	if button_text != "":
		var label := Label3D.new()
		label.text = button_text
		label.font_size = 56
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.009
		label.position.y = weapon.radius + 0.06
		add_child(label)

func _physics_process(delta: float) -> void:
	_flight_time += delta
	var traveled: float = _flight_time * float(weapon.speed)
	var next_pos := origin + direction * traveled
	# Area3D overlap is sampled once per physics tick, so a fast projectile can
	# jump clean past a fighter between ticks and never report the hit. A ray
	# over the full frame movement makes every shot deterministic, the same fix
	# HackySack already uses. This is worst under NS3_SIM, where 10x time scale
	# advances a 25 m/s pellet ~4 m per tick against a ~0.6 m hitbox (it made
	# every pellet kit read as broken in the balance table), but a 42 m/s Super
	# can skip past a target's edge at normal speed too.
	var query := PhysicsRayQueryParameters3D.create(global_position, next_pos, collision_mask)
	var skip: Array[RID] = []
	if is_instance_valid(owner_fighter):
		skip.append(owner_fighter.get_rid())
	for b in already_hit:      # a piercing shot must not re-hit what it passed
		if is_instance_valid(b) and b is CollisionObject3D:
			skip.append(b.get_rid())
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = next_pos
	else:
		# A piercing shot keeps its momentum; anything else stops where it hit.
		global_position = next_pos if weapon.pierces else hit.position
		if on_sweep_hit.is_valid():
			on_sweep_hit.call(hit.collider, self)
	if traveled > weapon.range:
		queue_free()
