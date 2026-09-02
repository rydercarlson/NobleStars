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
var hit_fighter := false
## Called once when a heat-trait shot ends: (hit_fighter: bool).
var on_finished := Callable()
## Set by the main scene to its _on_projectile_hit. The swept ray below reports
## through this rather than through body_entered; see _physics_process.
var on_sweep_hit := Callable()
## Ayaan's Slalom: +1 or -1 mirrors the weave, so a pair of shots bows to
## opposite sides and crosses back together. 0 flies straight. The bow's angle
## is the weapon's `curve_deg`; its period is set per shot, because the player
## aims the crossing distance.
var curve_sign := 0.0
## Seconds for one full weave. The pair crosses back onto the aim line every
## HALF of this, so the shooter sets it from where they want the crossing —
## `Kits.slalom_weave`.
var curve_period := 0.0
## Degrees this shot swings off the aim line. Per shot, not per weapon: a Slalom
## aimed short braids at 58 degrees and one aimed long draws a 27-degree arc.
var curve_deg := 0.0
## How far down the aim line this shot reaches before it expires. Defaults to
## the weapon's `range`; a Slalom shot overrides it per shot, because the swerve
## is paid for out of range — the wider the carve, the shorter the reach.
var reach := 0.0
var _distance_traveled := 0.0
var _speed := 0.0
var _bounces_left := 0
var _sweep: PhysicsShapeQueryParameters3D
var _base_dir := Vector3.FORWARD
var _curve_rad := 0.0
var _curve_omega := 0.0
var _age := 0.0

func _ready() -> void:
	_speed = float(weapon.speed)
	_bounces_left = int(weapon.get("bounces", 0))
	_base_dir = direction
	if reach <= 0.0:
		reach = float(weapon.range)
	if curve_sign != 0.0:
		_curve_rad = deg_to_rad(curve_deg)
		_curve_omega = TAU / maxf(0.05, curve_period)
	collision_layer = 1 << 3
	collision_mask = (1 << 0) | (1 << 2) | (1 << 5)  # walls | fighters | boxes
	monitoring = true

	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = weapon.radius
	col.shape = s
	add_child(col)

	# Reused every frame by the swept-sphere test in _physics_process.
	_sweep = PhysicsShapeQueryParameters3D.new()
	_sweep.shape = s
	_sweep.collision_mask = collision_mask

	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = button_color if button_text != "" else weapon.get(
			"projectile_color", Color(1.0, 0.45, 0.15) if weapon.destroys_walls \
			else Color(1.0, 0.85, 0.3))
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

## How much of a frame's travel counts against `weapon.range`. A weaving shot
## covers ~9% more ground than it gains on the aim line, so its range is spent
## along that line instead — otherwise "4.0 tiles" would mean 3.6 for Ayaan and
## 4.0 for everyone else, and a bot firing at a target exactly at range (which
## it measures straight-line) would watch the shot expire short of them.
func _advance(step: Vector3) -> float:
	return step.dot(_base_dir) if _curve_rad > 0.0 else step.length()

func _physics_process(delta: float) -> void:
	if _curve_rad > 0.0:
		# Heading swings as curve_deg * cos(wt), so the offset from the aim line
		# is its integral: zero at the muzzle, widest a quarter period in, and
		# back on the line at the half period. `curve_sign` mirrors it, so the
		# pair crosses each other there. See the kit note in kits.gd.
		#
		# Sampled at the frame's MIDPOINT, not its start. That is not polish: the
		# player aims the crossing distance, so the closed-form gate has to be
		# where the shot actually crosses. Sampling at the frame start runs the
		# curve ~6% long at 60 Hz — a fifth of a tile of lie in the one number
		# the kit asks the player to read.
		direction = _base_dir.rotated(Vector3.UP,
				_curve_rad * curve_sign * cos(_curve_omega * (_age + delta * 0.5)))
		_age += delta
	var motion := direction * _speed * delta
	var next_pos := global_position + motion
	# Area3D overlap is sampled once per physics tick, so a fast projectile can
	# jump clean past a fighter between ticks and never report the hit. A ray
	# over the full frame movement makes every shot deterministic, the same fix
	# HackySack already uses. This is worst under NS3_SIM, where 10x time scale
	# advances a 25 m/s pellet ~4 m per tick against a ~0.6 m hitbox (it made
	# every pellet kit read as broken in the balance table), but a 42 m/s Super
	# can skip past a target's edge at normal speed too.
	var skip: Array[RID] = []
	if is_instance_valid(owner_fighter):
		skip.append(owner_fighter.get_rid())
	for b in already_hit:      # a piercing shot must not re-hit what it passed
		if is_instance_valid(b) and b is CollisionObject3D:
			skip.append(b.get_rid())
	_sweep.transform = Transform3D(Basis(), global_position)
	_sweep.motion = motion
	_sweep.exclude = skip
	var space := get_world_3d().direct_space_state
	# Sweep the pellet's actual sphere, not a bare line. A ray would only score
	# when it passed through the 0.45 m capsule itself, throwing away the
	# projectile's own radius — a third of the hit width on a 0.2 m button.
	var frac := space.cast_motion(_sweep)
	if frac[0] >= 1.0:
		global_position = next_pos
		_distance_traveled += _advance(motion)
	else:
		_sweep.transform = Transform3D(Basis(), global_position + motion * frac[1])
		_sweep.motion = Vector3.ZERO
		var rest := space.get_rest_info(_sweep)
		var impact := global_position + motion * frac[0]
		_distance_traveled += _advance(motion) if weapon.pierces \
				else _advance(motion * frac[0])
		# A piercing shot keeps its momentum; anything else stops where it hit.
		global_position = next_pos if weapon.pierces else impact
		var collider: Object = instance_from_id(rest.collider_id) if rest.has("collider_id") else null
		var wall_hit := collider is CollisionObject3D \
				and (int((collider as CollisionObject3D).collision_layer) & (1 << 0)) != 0
		if wall_hit and _bounces_left > 0 and rest.has("normal"):
			_bounces_left -= 1
			direction = direction.bounce(rest.normal).normalized()
			damage = int(round(damage * float(weapon.get("bounce_damage_mult", 1.0))))
			_speed *= float(weapon.get("bounce_speed_mult", 1.0))
			global_position = impact + direction * 0.05
		elif collider is Node3D and on_sweep_hit.is_valid():
			on_sweep_hit.call(collider, self)
		elif collider == null:
			global_position = next_pos   # nothing resolved; don't stall in place
	if _distance_traveled > reach:
		queue_free()

func _exit_tree() -> void:
	if on_finished.is_valid():
		on_finished.call(hit_fighter)
