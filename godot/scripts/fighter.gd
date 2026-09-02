class_name Fighter
extends CharacterBody3D
## One fighter (player or bot): stats, movement, dash, billboard health bar,
## damage popups. Visual is a colored capsule until Meshy models land.

var kit: Dictionary
var display_name := "Fighter"
var is_player := false
## Team-mode index (Nobles Cup): 0 or 1. Showdown leaves it at -1, which means
## "no allies" — is_ally() is false for everyone, so free-for-all is unchanged.
var team := -1

var max_health := Kits.BASE_MAX_HEALTH
var health := Kits.BASE_MAX_HEALTH
var ammo := Kits.MAX_AMMO
var max_ammo := Kits.MAX_AMMO
## While true the ammo clock is stopped. Anders holds this for as long as his
## sack is alive, so his single pip only starts refilling once the rally ends
## rather than ticking back during it.
var ammo_locked := false
## Anders' consecutive catches. Lives on the fighter because the sack is
## destroyed on every catch — it seeds the next throw's damage step.
var sack_streak := 0
var reload := Kits.AMMO_RECHARGE_SECONDS   # seconds per ammo pip; set from the kit
## Minimum gap between two attacks, derived from `reload`. Without it a whole
## magazine leaves the barrel in one flick — see SHOT_FEEL.md section 8.
var attack_cooldown := Kits.attack_cooldown_for(Kits.AMMO_RECHARGE_SECONDS)
var next_attack_at := -1.0
var super_charge := 0.0
var cubes := 0
var last_damage_at := -100.0
var facing := Vector3.FORWARD

var knockback_vel := Vector3.ZERO
var dash: Dictionary = {}   # empty = not dashing; `steer` marks a Downhill ride
var leap: Dictionary = {}   # empty = grounded; used by jump-smash Supers
var disconnected_until := -1.0
## Ayaan's snow spray. `slow_factor` multiplies move speed until `slow_until`;
## `tick` puts it back to 1.0.
var slow_until := -1.0
var slow_factor := 1.0

# Hammy's three-hit rhythm. Keeping it on the fighter makes the trait identical
# for humans and bots and lets the HUD show the current streak.
var heat_hits := 0
var on_fire_until := -1.0
var burn_until := -1.0
var burn_tick_at := -1.0
var burn_damage := 0
var burn_source: Fighter = null

var _body_mesh: MeshInstance3D
var _material: StandardMaterial3D
var _model: Node3D
var _anim: AnimationPlayer
var _held_item: Node3D   # e.g. Sanjit's staff — hidden while his Super flies
var _skel: Skeleton3D
var _foot_bones: PackedInt32Array = []
var _foot_rest_y := 0.0
var _attack_anim_until := 0.0
var _attack_anim_fast_at := INF
var _attack_anim_end_speed_scale := 1.0
var _pending_popup := 0
var _heat_glow: MeshInstance3D
var _burn_glow: MeshInstance3D


func is_dead() -> bool:
	return health <= 0

## Nobles Cup only. Two Showdown fighters are never allies even though both
## carry team -1, so an unset team must never match itself.
func is_ally(other: Fighter) -> bool:
	return team >= 0 and other != self and other.team == team

func is_dashing() -> bool:
	return not dash.is_empty()

## A steered, time-bounded dash: Ayaan's Downhill. It rides the same `dash`
## channel on purpose, so every guard that already asks `is_dashing()` — no
## shooting mid-dash, for the player and the bots alike — covers the ride too.
func is_riding() -> bool:
	return bool(dash.get("steer", false))

## How much of a Downhill run is left, 1.0 down to 0.0 — the timer bar the HUD
## paints over his head. Zero when there is no ride, so callers can ask flatly.
func ride_fraction() -> float:
	if not is_riding():
		return 0.0
	return clampf(1.0 - float(dash.elapsed) / maxf(0.01, float(dash.duration)), 0.0, 1.0)

func is_leaping() -> bool:
	return not leap.is_empty()

func is_disconnected(game_now: float) -> bool:
	return game_now < disconnected_until

func apply_disconnect(game_now: float, duration: float) -> void:
	var was_disconnected := is_disconnected(game_now)
	disconnected_until = maxf(disconnected_until, game_now + duration)
	if not was_disconnected:
		_popup("DISCONNECTED", Color(1.0, 0.25, 0.85))

func damage_multiplier() -> float:
	return 1.0 + Kits.DAMAGE_BONUS_PER_CUBE * cubes

func is_super_ready() -> bool:
	return super_charge >= 1.0

func _ready() -> void:
	max_health = int(kit.get("max_health", Kits.BASE_MAX_HEALTH))
	health = max_health
	reload = float(kit.get("reload", Kits.AMMO_RECHARGE_SECONDS))
	attack_cooldown = Kits.attack_cooldown_for(reload)
	max_ammo = float(kit.get("ammo", Kits.MAX_AMMO))
	ammo = max_ammo
	collision_layer = 1 << 2                  # fighters
	# Fighters do NOT mask each other: bodies walk straight over one another, as
	# they do in Brawl Stars, so a teammate can never wall you into a corner and
	# a crowd around a loot box does not turn into a shoving match. The layer
	# stays on, because shots, boomerangs and melee sweeps all still find them.
	collision_mask = (1 << 0) | (1 << 1) | (1 << 5)  # walls|water|boxes

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Kits.FIGHTER_RADIUS
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	add_child(col)

	if team >= 0:
		_setup_team_ring()
	if kit.has("model"):
		_setup_model()
	else:
		_setup_capsule()
	if bool(kit.get("weapon", {}).get("heat_trait", false)):
		_setup_heat_glow()

func _setup_heat_glow() -> void:
	_heat_glow = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.62
	mesh.height = 1.75
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.01, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.12, 0.0) * 1.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_heat_glow.mesh = mesh
	_heat_glow.position.y = 0.88
	_heat_glow.visible = false
	add_child(_heat_glow)

func _setup_burn_glow() -> void:
	_burn_glow = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.54
	mesh.height = 1.65
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.42, 0.02, 0.20)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.18, 0.01) * 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_burn_glow.mesh = mesh
	_burn_glow.position.y = 0.82
	_burn_glow.visible = false
	add_child(_burn_glow)


## Rigged Meshy character: model stands on y=0 facing -Z, clips per kit.
func _setup_model() -> void:
	var scene: PackedScene = load(kit.model)
	_model = scene.instantiate()
	# The GLBs were sized against the old 0.45 m capsule; scale them in step so
	# the silhouette still matches what projectiles actually collide with.
	_model.scale = Vector3.ONE * Kits.MODEL_SCALE
	add_child(_model)
	# Meshy exports metallicFactor=1.0; full metal renders black without
	# reflection probes, so clamp it on every imported surface.
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mat = mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				mat.metallic = 0.0
	_held_item = _model.find_child("held_item", true, false)
	_anim = _model.find_child("AnimationPlayer", true, false)
	if _anim:
		var clips: Dictionary = kit.clips
		for clip_name in [clips.idle, clips.run]:
			var a: Animation = _anim.get_animation(clip_name)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
		_anim.play(clips.idle)
	_calibrate_feet()

## Meshy's run and attack clips drop the hips well below the rest pose, which
## drives the feet through the floor. Record where the feet sit in the idle pose
## so `_ground_feet` can lift the model by however far they later sink.
func _calibrate_feet() -> void:
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	_skel = skels[0]
	for b in _skel.get_bone_count():
		var bone_name := _skel.get_bone_name(b).to_lower()
		if bone_name.contains("foot") or bone_name.contains("toe"):
			_foot_bones.append(b)
	if _foot_bones.is_empty():
		_skel = null
		return
	if _anim:
		_anim.seek(0.0, true)
	_foot_rest_y = _lowest_foot_y()

## Height of the lowest foot/toe bone in the model's own space — independent of
## the lift `_ground_feet` applies, so the two never chase each other.
func _lowest_foot_y() -> float:
	_skel.force_update_all_bone_transforms()
	var to_model := _model.global_transform.affine_inverse() * _skel.global_transform
	var lowest := INF
	for b in _foot_bones:
		lowest = minf(lowest, (to_model * _skel.get_bone_global_pose(b)).origin.y)
	return lowest

## Lift the model so the planted foot never sinks below its idle resting height.
## Never pushes down, so a clip that keeps its feet high just stands normally.
func _ground_feet() -> void:
	if _skel == null:
		return
	# The sink is measured in the model's own space, but position is the
	# parent's, so it has to be scaled by MODEL_SCALE to land on the floor.
	_model.position.y = maxf(0.0, (_foot_rest_y - _lowest_foot_y()) * _model.scale.y)

## Show/hide a model's held item (Sanjit's staff) while a thrown copy flies.
func set_held_item_visible(shown: bool) -> void:
	if _held_item:
		_held_item.visible = shown

## Nobles Cup team marker: a flat ring on the ground under the fighter. It has
## to sit outside the body rather than tint it, because five of eight kits wear
## a GLB whose materials are the character's own and must not be recoloured.
func _setup_team_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = Kits.FIGHTER_RADIUS * 0.92
	torus.outer_radius = Kits.FIGHTER_RADIUS * 1.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Arena.TEAM_COLORS[team]
	mat.emission_enabled = true
	mat.emission = Arena.TEAM_COLORS[team]
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = mat
	ring.mesh = torus
	ring.position.y = 0.06
	add_child(ring)

## Placeholder capsule for kits without a model yet.
func _setup_capsule() -> void:
	_body_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = Kits.FIGHTER_RADIUS
	mesh.height = 1.6
	_material = StandardMaterial3D.new()
	_material.albedo_color = kit.color
	mesh.material = _material
	_body_mesh.mesh = mesh
	_body_mesh.position.y = 0.8
	add_child(_body_mesh)

	# Facing nose so aim direction reads on a capsule.
	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.14
	nose_mesh.height = 0.28
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.95, 0.95, 0.95)
	nose_mesh.material = nose_mat
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 1.15, -(Kits.FIGHTER_RADIUS + 0.03))
	add_child(nose)

## Drives idle/run/attack clips; called by the scene each frame with game time.
func update_animation(game_now: float) -> void:
	if _heat_glow:
		_heat_glow.visible = is_on_fire(game_now)
	if _burn_glow:
		_burn_glow.visible = game_now < burn_until
	if _anim == null or is_dead():
		return
	_ground_feet()
	if game_now < _attack_anim_until:
		if _anim.current_animation_position >= _attack_anim_fast_at:
			_anim.speed_scale = _attack_anim_end_speed_scale
		return
	var clips: Dictionary = kit.clips
	var moving := velocity.length() > 0.5
	var want: String = clips.run if moving else clips.idle
	# Match the stride to the actual ground speed, or the feet skate. The
	# reference is RUN_CLIP_SPEED — the speed the clips were tuned against —
	# NOT the current Normal tier. Referencing SPEED_NORMAL would always give
	# 1.0 at normal pace, so the legs would churn at their old 7 m/s rate while
	# the body covered far less ground, which reads as sluggish however fast
	# the speed constant says the fighter is moving.
	_anim.speed_scale = clampf(velocity.length() / Kits.RUN_CLIP_SPEED, 0.35, 1.6) \
			if moving else 1.0
	if _anim.current_animation != want:
		_anim.play(want, 0.15)

## Plays the kit's attack clip, or its `super` clip when the Super fires (kits
## without one reuse the attack clip). `*_seek` skips a clip's wind-up so the
## impact frame lands with the hit instead of a beat after it.
func play_attack_animation(game_now: float, is_super: bool = false) -> void:
	if _anim == null:
		return
	var clips: Dictionary = kit.clips
	var prefix := "super" if is_super else "attack"
	var clip_name: String = clips.get("super", clips.attack) if is_super else clips.attack
	var speed: float = clips.get("super_speed", clips.get("attack_speed", 1.0)) if is_super \
			else clips.get("attack_speed", 1.0)
	var seek_to: float = clips.get("super_seek", 0.0) if is_super else clips.get("attack_seek", 0.0)
	# The movement stride scale must not multiply into the attack clip — its
	# timings are tuned frame-by-frame against `speed`, and `_attack_anim_until`
	# below is computed from `speed` alone.
	_anim.speed_scale = 1.0
	_anim.play(clip_name, 0.05, speed)
	if seek_to > 0.0:
		_anim.seek(seek_to, true)
	var a: Animation = _anim.get_animation(clip_name)
	if a:
		var end_at := clampf(float(clips.get(prefix + "_end", a.length)), seek_to, a.length)
		var fast_at := clampf(float(clips.get(prefix + "_fast_at", end_at)), seek_to, end_at)
		var end_speed := maxf(0.01, float(clips.get(prefix + "_end_speed", speed)))
		# AnimationPlayer's custom speed is `speed`; speed_scale changes only the
		# tail once it crosses fast_at. Keeping the timing calculation identical
		# prevents movement from taking control before the cropped take is done.
		_attack_anim_fast_at = fast_at
		_attack_anim_end_speed_scale = end_speed / maxf(0.01, speed)
		_attack_anim_until = game_now + (fast_at - seek_to) / speed \
				+ (end_at - fast_at) / end_speed

func apply_movement(input_dir: Vector3) -> void:
	if is_leaping():
		velocity = Vector3.ZERO
		return
	if is_dashing():
		# A ride CARVES: it swings toward the stick at `turn_rate` rad/s rather
		# than snapping to it, so a change of direction costs ground and reads as
		# a turn rather than a pivot. Letting go holds the current heading, so the
		# run coasts on instead of stopping dead. The rate is the whole feel of
		# the Super — see the tuning history on the kit.
		# A plain dash ignores input entirely and holds the line it launched on.
		if is_riding() and input_dir.length() > 0.1:
			var want := input_dir.normalized()
			var limit: float = float(dash.turn_rate) * get_physics_process_delta_time()
			var swing: float = (dash.direction as Vector3).signed_angle_to(want, Vector3.UP)
			dash.direction = (dash.direction as Vector3).rotated(
					Vector3.UP, clampf(swing, -limit, limit)).normalized()
			face_direction(dash.direction)
		velocity = dash.direction * dash.weapon.speed
		move_and_slide()
		return
	var speed: float = float(kit.get("move_speed", Kits.MOVE_SPEED)) * slow_factor
	velocity = input_dir * speed + knockback_vel
	move_and_slide()
	if input_dir.length() > 0.1:
		facing = input_dir.normalized()
		rotation.y = atan2(-facing.x, -facing.z)

## Distance a knockback impulse of strength 1.0 actually travels. The decay is
## `v *= 0.0001 ** delta`, i.e. v(t) = v0 * e^(-9.21t), so the integral is
## v0 / 9.21. Converting the other way lets a lunge be authored in metres.
const IMPULSE_TRAVEL := 0.1086

## A short forward hop on a melee strike, so a combo carries the fighter in.
## Rides the knockback channel deliberately: it decays in about 0.08s, so it
## reads as a lunge rather than a slide, it is summed with input in
## apply_movement so the player keeps steering throughout, and move_and_slide
## already stops it dead against a wall.
func lunge(direction: Vector3, distance: float) -> void:
	if distance <= 0.0 or direction.length() < 0.01:
		return
	knockback_vel += direction.normalized() * (distance / IMPULSE_TRAVEL)

func face_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.001:
		return
	facing = flat.normalized()
	rotation.y = atan2(-facing.x, -facing.z)

func begin_dash(weapon: Dictionary, direction: Vector3) -> void:
	dash = {"weapon": weapon, "direction": direction.normalized(), "remaining": weapon.range,
			"hit": [], "crossed_water": false}
	face_direction(direction)
	collision_mask = (1 << 0) | (1 << 5)   # walls + boxes only: dash crosses water

## Ayaan's Downhill. Bounded by TIME rather than by distance, and steered every
## frame in apply_movement, so `remaining` never counts down. Same collision mask
## as a dash: fighters are hit by the ride's own contact test, and the skis
## glide over water on top of that.
func begin_ride(weapon: Dictionary, direction: Vector3) -> void:
	dash = {"weapon": weapon, "direction": direction.normalized(), "remaining": INF,
			"hit": [], "crossed_water": false, "steer": true, "elapsed": 0.0,
			"turn_rate": float(weapon.get("turn_rate", 4.0)),
			"duration": float(weapon.get("duration", 2.0)),
			"last_pos": global_position}
	face_direction(direction)
	collision_mask = (1 << 0) | (1 << 5)

func end_dash() -> void:
	dash = {}
	collision_mask = (1 << 0) | (1 << 1) | (1 << 5)

func begin_leap(weapon: Dictionary, direction: Vector3, distance: float) -> void:
	var dir := direction.normalized()
	var landing := global_position + dir * clampf(distance, Kits.TILE, weapon.range)
	# Sweep for terrain first. Kovacs leaps forward into open ground and got
	# away without this, but Pop Off leaps BACKWARD to escape a diver, so the
	# aim points at whatever is behind him — landing inside a wall is the
	# common case there, not the edge case.
	var q := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0, 0.8, 0), landing + Vector3(0, 0.8, 0), 1)
	q.exclude = [get_rid()]
	var blocked := get_world_3d().direct_space_state.intersect_ray(q)
	if not blocked.is_empty():
		var stop: Vector3 = blocked.position - Vector3(0, 0.8, 0) - dir * 0.6
		landing = stop if stop.distance_to(global_position) > 0.3 else global_position
	leap = {"weapon": weapon, "start": global_position, "landing": landing, "elapsed": 0.0,
			"duration": 0.48}
	face_direction(direction)

## Spends one ammo pip if the fighter has one AND the attack cooldown has
## elapsed. Gating here rather than at each caller covers the player, the bots
## and the net path in one place. The Super deliberately does not go through
## this — it is charge-gated, so making it wait on the cooldown would eat a
## tapped Super after a basic attack.
func consume_ammo(game_now: float) -> bool:
	if ammo < 1.0 or game_now < next_attack_at:
		return false
	ammo -= 1.0
	next_attack_at = game_now + attack_cooldown
	return true

func consume_super() -> bool:
	if not is_super_ready():
		return false
	super_charge = 0.0
	return true

func charge_super(damage_dealt: int) -> void:
	super_charge = min(1.0, super_charge + damage_dealt / Kits.SUPER_CHARGE_DAMAGE)

func is_on_fire(game_now: float) -> bool:
	return game_now < on_fire_until

func register_heat_hit(game_now: float) -> void:
	if is_on_fire(game_now):
		return
	heat_hits += 1
	if heat_hits >= 3:
		heat_hits = 0
		on_fire_until = game_now + 4.0
		_popup("ON FIRE!", Color(1.0, 0.28, 0.02))
	else:
		_popup("HEAT %d/3" % heat_hits, Color(1.0, 0.55, 0.08))

func register_heat_miss(game_now: float) -> void:
	if is_on_fire(game_now) or heat_hits <= 0:
		return
	heat_hits -= 1

func ignite(game_now: float, duration: float, tick_damage: int, source: Fighter) -> void:
	if _burn_glow == null:
		_setup_burn_glow()
	if game_now >= burn_until:
		burn_damage = tick_damage
	else:
		burn_damage = maxi(burn_damage, tick_damage)
	burn_until = maxf(burn_until, game_now + duration)
	if burn_tick_at < game_now:
		burn_tick_at = game_now + 0.5
	burn_source = source
	_popup("BURNING", Color(1.0, 0.3, 0.02))

func take_damage(amount: int, now: float) -> void:
	if is_dead():
		return
	health = max(0, health - amount)
	last_damage_at = now
	_pending_popup += amount
	# Hit flash (capsule placeholder only; models keep their own material)
	if _material:
		_material.albedo_color = Color.WHITE
		get_tree().create_timer(0.07).timeout.connect(
			func() -> void: _material.albedo_color = kit.color)

func receive_knockback(direction: Vector3, strength: float) -> void:
	knockback_vel += direction.normalized() * strength

## Ayaan's snow spray. Overlapping sprays take the STRONGEST slow and the
## LATEST expiry, so skiing through the same crowd twice never shortens the
## first one — the same "only ever extend" rule apply_disconnect uses.
func apply_slow(game_now: float, duration: float, factor: float) -> void:
	slow_factor = factor if game_now >= slow_until else minf(slow_factor, factor)
	slow_until = maxf(slow_until, game_now + duration)
	_popup("SLOWED", Color(0.65, 0.9, 1.0))

func collect_cube() -> void:
	cubes += 1
	max_health += Kits.HEALTH_PER_CUBE
	health += Kits.HEALTH_PER_CUBE
	_popup("+%d HP" % Kits.HEALTH_PER_CUBE, Color(0.85, 0.45, 1.0))

func tick(delta: float, now: float) -> void:
	if slow_factor < 1.0 and now >= slow_until:
		slow_factor = 1.0
	if ammo < max_ammo and not ammo_locked:
		ammo = min(max_ammo, ammo + delta / reload)
	if not is_dead() and health < max_health and now - last_damage_at > Kits.REGEN_DELAY:
		health = min(max_health, health + int(ceil(max_health * Kits.REGEN_RATE_PER_SECOND * delta)))
	if _pending_popup > 0 and now - last_damage_at > 0.12:
		_popup(str(_pending_popup), Color(1.0, 0.25, 0.2))
		_pending_popup = 0
	knockback_vel = knockback_vel * pow(0.0001, delta) if knockback_vel.length() > 0.05 else Vector3.ZERO

func die() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.35)
	tw.tween_callback(queue_free)

## Nobles Cup death: the fighter is coming back, so it is parked rather than
## freed. Everything that walks `fighters` already skips is_dead(), and health
## stays at 0 until respawn() so it keeps skipping them.
func knock_out() -> void:
	velocity = Vector3.ZERO
	knockback_vel = Vector3.ZERO
	dash = {}
	leap = {}
	visible = false
	# Off every layer and mask: a parked fighter must not block a shot, soak a
	# melee sweep, or stop the ball rolling over the spot where it fell.
	collision_layer = 0
	collision_mask = 0
	if _anim:
		_anim.stop()

func respawn(pos: Vector3, game_now: float) -> void:
	position = pos
	health = max_health
	ammo = max_ammo
	# Super charge does not survive: a fighter who trades its life for a Super
	# it never spent should not come straight back holding it.
	super_charge = 0.0
	heat_hits = 0
	sack_streak = 0
	ammo_locked = false
	burn_until = -1.0
	on_fire_until = -1.0
	disconnected_until = -1.0
	slow_until = -1.0
	slow_factor = 1.0
	last_damage_at = game_now
	next_attack_at = -1.0
	scale = Vector3.ONE
	visible = true
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 5)
	reset_physics_interpolation()
	if _anim:
		_anim.play(kit.clips.idle)

func set_concealed(hidden: bool, self_view: bool) -> void:
	if is_dead():
		return   # knocked out in Nobles Cup: respawn() owns `visible`, not this
	if self_view:
		if _material:
			_material.albedo_color.a = 0.55 if hidden else 1.0
			_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if hidden else BaseMaterial3D.TRANSPARENCY_DISABLED
		# Model fighters stay visible to themselves in bushes.
	else:
		visible = not hidden

func _popup(text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.pixel_size = 0.012
	label.position = Vector3(randf_range(-0.3, 0.3), 2.6, 0)
	add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", 3.4, 0.7)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)
