class_name HackySack
extends Area3D
## Anders' rally sack — "Keep It Up".
##
## Exactly one exists at a time. Every contact kicks it on toward whichever
## fighter is nearest, so a rally circulates between Anders and whoever he is
## fighting instead of flying off across the map. Reaching Anders re-kicks it
## for free and steps the rally up; reaching an enemy damages them.
##
## Each rally flies a shorter leg, the way a real sack loses height on every
## touch. That is what keeps a rally inside one pocket of the arena — without
## it rally 2 lands a full range away, can never be recovered from mid range,
## and the whole mechanic is decoration.
##
## The skill is positioning rather than a footrace: the sack goes to whoever is
## CLOSEST when it bounces, so Anders wants to be that fighter. The ground
## marker shows where the current leg ends, so that read is fair rather than
## guesswork.

var weapon: Dictionary
var base_damage := 0
var owner_fighter: Fighter
var game: Node                     # main scene, for the fighter list
var direction := Vector3.FORWARD

var rally := 1
var on_enemy_hit := Callable()     # (Fighter target, HackySack sack)
var on_rally := Callable()         # (HackySack sack) — Anders kicked it again

const MAX_RALLY := 3
## Every contact spends a touch — enemy, wall, or Anders getting back under it.
## Without this the sack ping-pongs between fighters until its lifetime runs
## out and one ammo pays for far more damage than it was budgeted.
const MAX_TOUCHES := 3
const LIFETIME := 5.0
## Leg length as a fraction of weapon.range, per rally. A sack loses energy.
const LEG_FRACTION := [1.0, 0.6, 0.35]
## Nobody this close to kick to and the rally dies. Kept deliberately short: at
## 11 m the sack found a body almost anywhere on the map and effectively homed,
## which made a miss self-correcting. A rally should need a real fight around it.
const REDIRECT_RANGE := 7.5
const RECOVER_RADIUS := 0.95
const ARM_DISTANCE := 2.0          # must clear this before Anders can catch it
const DAMAGE_RAMP := 0.25          # +25% per rally step

var _age := 0.0
var _leg_left := 0.0
var _touches_left := MAX_TOUCHES
var _already_hit: Array = []
var _armed := false
var _label: Label3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _sweep: PhysicsShapeQueryParameters3D

## Damage for the rally currently in flight: 1.00 / 1.25 / 1.50 of base.
func rally_damage() -> int:
	return int(base_damage * (1.0 + DAMAGE_RAMP * float(rally - 1)))

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = (1 << 0) | (1 << 2) | (1 << 5)   # walls | fighters | boxes
	monitoring = true
	_leg_left = float(weapon.range) * LEG_FRACTION[0]

	var shape := SphereShape3D.new()
	shape.radius = weapon.radius
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	_sweep = PhysicsShapeQueryParameters3D.new()
	_sweep.shape = shape
	_sweep.collision_mask = collision_mask

	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.88, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.35, 0.25)
	mesh.material = mat
	visual.mesh = mesh
	add_child(visual)

	_build_marker()

	# The rally count rides on the sack: it is the thing the player is already
	# watching, and it only exists while a rally is live.
	_label = Label3D.new()
	_label.font_size = 64
	_label.outline_size = 10
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.008
	_label.position.y = weapon.radius + 0.35
	add_child(_label)
	_refresh_rally_visuals()

## Flat ring on the floor at the end of the current leg. top_level keeps it out
## of the sack's transform so it can sit on the ground while the sack flies.
func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.top_level = true
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.58
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = Color(1.0, 0.9, 0.4, 0.55)
	ring.material = _marker_mat
	_marker.mesh = ring
	add_child(_marker)

func _refresh_rally_visuals() -> void:
	# 1 plain, 2 warming, 3 hot — a rally is worth more the higher it climbs.
	var tint: Color = [Color(1.0, 0.97, 0.75), Color(1.0, 0.78, 0.3),
			Color(1.0, 0.45, 0.2)][clampi(rally - 1, 0, 2)]
	_label.text = str(rally)
	_label.modulate = tint
	_marker_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.55)

## Where this leg ends, stopped at the first wall in the way.
func _update_marker() -> void:
	var finish := global_position + direction * _leg_left
	var q := PhysicsRayQueryParameters3D.create(global_position, finish, 1)  # walls
	if is_instance_valid(owner_fighter):
		q.exclude = [owner_fighter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var p: Vector3 = hit.position if not hit.is_empty() else finish
	p.y = 0.04
	_marker.global_position = p

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME or not is_instance_valid(owner_fighter) or owner_fighter.is_dead():
		queue_free()
		return

	var step: float = float(weapon.speed) * delta

	if not _armed and global_position.distance_to(owner_fighter.global_position) > ARM_DISTANCE:
		_armed = true
	# Anders catching it is tested before terrain: reaching him is the whole
	# point of the mechanic and must never be eaten by a wall on the same tick.
	if _armed and global_position.distance_to(
			owner_fighter.global_position + Vector3(0, 0.8, 0)) <= RECOVER_RADIUS:
		_recovered()
		return

	var skip: Array[RID] = [owner_fighter.get_rid()]
	for b in _already_hit:
		if is_instance_valid(b) and b is CollisionObject3D:
			skip.append(b.get_rid())
	_sweep.transform = Transform3D(Basis(), global_position)
	_sweep.motion = direction * step
	_sweep.exclude = skip
	var space := get_world_3d().direct_space_state
	var frac := space.cast_motion(_sweep)
	if frac[0] >= 1.0:
		global_position += direction * step
	else:
		_sweep.transform = Transform3D(Basis(), global_position + direction * step * frac[1])
		_sweep.motion = Vector3.ZERO
		var rest := space.get_rest_info(_sweep)
		var collider: Object = instance_from_id(rest.collider_id) if rest.has("collider_id") else null
		global_position += direction * step * frac[0]
		if collider is Fighter and collider != owner_fighter and not collider.is_dead():
			_already_hit.append(collider)
			if on_enemy_hit.is_valid():
				on_enemy_hit.call(collider, self)
			_spend_touch()
			return
		elif collider != null:
			_spend_touch()       # wall or loot box: kicked on off the surface
			return
		else:
			# cast_motion flagged something it could not resolve; finish the
			# step rather than adding a second one on top of frac[0].
			global_position += direction * step * (1.0 - frac[0])

	_leg_left -= step
	if _leg_left <= 0.0:
		_redirect()
		return
	_update_marker()

## A contact: spend one of the three touches, then kick it on if any are left.
func _spend_touch() -> void:
	_touches_left -= 1
	if _touches_left <= 0:
		queue_free()
		return
	_redirect()

## Kick the sack on toward the nearest fighter — Anders included. Whoever is
## closest gets it, which is what makes recovery a positioning read.
func _redirect() -> void:
	var nearest: Fighter = null
	var best := REDIRECT_RANGE
	for f in game.fighters:
		if not is_instance_valid(f) or f.is_dead():
			continue
		var d := global_position.distance_to(f.global_position)
		if d < best:
			best = d
			nearest = f
	if nearest == null:
		queue_free()            # kicked into empty space; nobody to keep it up
		return
	var to := nearest.global_position + Vector3(0, 0.8, 0) - global_position
	to.y = 0.0
	if to.length() < 0.01:
		queue_free()
		return
	direction = to.normalized()
	# A redirect is a short hop to its new target, not a fresh full-range kick.
	_leg_left = maxf(best + 1.0, 2.0)
	_already_hit.clear()
	_bounce_pulse()
	if nearest == owner_fighter:
		_armed = true           # heading home: let him catch it
	_update_marker()

func _recovered() -> void:
	if rally >= MAX_RALLY:
		queue_free()
		return
	_touches_left -= 1
	if _touches_left <= 0:
		queue_free()
		return
	rally += 1
	_already_hit.clear()
	_armed = false
	_leg_left = float(weapon.range) * LEG_FRACTION[clampi(rally - 1, 0, LEG_FRACTION.size() - 1)]
	# Re-kicked along Anders' current facing, so the rally stays his to aim.
	direction = owner_fighter.facing
	global_position = owner_fighter.global_position + direction * 0.8 + Vector3(0, 1.0, 0)
	_refresh_rally_visuals()
	_bounce_pulse()
	_update_marker()
	if on_rally.is_valid():
		on_rally.call(self)

func _bounce_pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.45, 0.7, 1.45), 0.06)
	tw.tween_property(self, "scale", Vector3.ONE, 0.10)

## Used by the player's aim preview, which draws the first leg's ricochet.
static func reflected_direction(incoming: Vector3, surface_normal: Vector3) -> Vector3:
	var normal := Vector3(surface_normal.x, 0, surface_normal.z).normalized()
	if normal.length_squared() < 0.001:
		return -incoming.normalized()
	return (incoming.bounce(normal) + normal * 0.25).normalized()
