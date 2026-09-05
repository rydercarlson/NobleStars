class_name Fighter
extends CharacterBody3D
## One fighter (player or bot): stats, movement, dash, billboard health bar,
## damage popups. Visual is a colored capsule until Meshy models land.

## How many poses each clip is sampled at when measuring its ground lift. The
## clips are 1-3s, so 24 steps lands well inside the stride and finding the
## true minimum does not need more.
const LIFT_SAMPLES := 24
## Easing time constant for the lift when the clip changes. The clip change
## steps the TARGET while the 0.15s animation blend is still interpolating the
## POSE, so the lift has to ease or the model pops on the frame a run starts;
## 0.08 puts it at 86% after 0.16s, which tracks that blend closely.
const LIFT_EASE_TAU := 0.08

## Ground lift per model per clip, in model space. Shared by every fighter
## wearing the same GLB because it is a property of the model and its clips,
## not of the fighter: sampling is ~25 skeleton poses per clip, and paying that
## once per MODEL rather than once per FIGHTER is the difference between a
## hitch on a six-fighter Nobles Cup spawn and none. Keyed by kit.model.
static var _lift_cache: Dictionary = {}

## How long a hit flash lasts, and how hard a modelled fighter glows for it.
## FLASH_ENERGY is emission energy, so it stacks on top of a lit texture and
## climbs fast: 6.0 erases the character to a white silhouette and even 2.2
## still washes the face out. Tune it by holding the flash open — set
## FLASH_SECONDS to ~1.5 temporarily, since five frames is far too short to
## judge from a screenshot — then put the duration back.
const FLASH_SECONDS := 0.08
const FLASH_ENERGY := 1.6
## What a fighter fades to while standing in a bush, seen by themselves.
## What a concealed fighter is tinted to. NOT an alpha: see set_concealed.
## `albedo_color` MULTIPLIES the texture, so this darkens and greens whatever
## the character is wearing, which is what sinks them into the bush.
const CONCEAL_TINT := Color(0.52, 0.70, 0.52)

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

## What this fighter did this match, for the results card. Always on — the
## NS3_SIM table is a separate per-KIT aggregate kept behind `sim_active`, and
## it answers a different question. Nothing here is cleared by respawn(): a
## Nobles Cup death is a setback inside one match, not the end of one, so a
## carrier who scores and then dies keeps the goal. `cubes` is counted here as
## well as on the fighter because `cubes` itself is zeroed when a body drops
## its load, and "collected 6" is what the card wants to say.
var stats := {
	"damage": 0,      # dealt to other fighters (loot boxes are not fighters)
	"kills": 0,
	"cubes": 0,
	"goals": 0,       # Nobles Cup
	"saves": 0,       # Nobles Cup
	"survived": 0.0,  # seconds of PLAYING phase; set when eliminated or at the whistle
}

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
## Per-instance copies of the model's surface materials — see _setup_model.
## Empty for the two kits still on the capsule fallback, which is what every
## modelled-fighter effect below tests instead of testing for a model.
var _model_mats: Array[BaseMaterial3D] = []
## The body's scale at rest, so a knockdown squash and a landing squash both
## have something exact to spring back to rather than assuming Vector3.ONE —
## a modelled fighter's is MODEL_SCALE and the capsule's is not.
var _body_rest := Vector3.ONE

var _model_emission: Array[Dictionary] = []
var _model_albedo: Array[Color] = []
var _capsule_albedo := Color.WHITE
## Which concealment state is currently painted on: -1 until the first call, so
## that one always lands. set_concealed runs every physics frame for every
## fighter, and changing a material's transparency mode recompiles a shader.
var _conceal_applied := -1
var _anim: AnimationPlayer
var _held_item: Node3D   # e.g. Sanjit's staff — hidden while his Super flies
var _skel: Skeleton3D
var _foot_bones: PackedInt32Array = []
var _foot_rest_y := 0.0
## Per-clip ground lift in MODEL space, keyed by clip name — this fighter's row
## of _lift_cache. Empty for the capsule fallback and for a rig with no
## AnimationPlayer, which is why _ground_feet can look up a missing clip and
## get 0.0 rather than having to test for either case.
var _clip_lift: Dictionary = {}
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
	var body: Node3D = _body()
	if body != null:
		_body_rest = body.scale
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
	#
	# Done on a per-instance DUPLICATE installed as a surface override, not on
	# the material the mesh carries: that material lives on a Mesh *resource*
	# which every fighter wearing the same GLB shares, so the hit flash and the
	# bush fade below would have fired on all of them at once.
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src: Material = mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				var m: BaseMaterial3D = (src as BaseMaterial3D).duplicate()
				m.metallic = 0.0
				mi.set_surface_override_material(s, m)
				_model_mats.append(m)
				# Remembered so the bush tint multiplies the material's OWN
				# colour and reveal puts that colour back, rather than both
				# assuming white.
				_model_albedo.append(m.albedo_color)
				# Remembered so a flash restores a model that legitimately
				# glows to its own emission rather than switching it off.
				_model_emission.append({
					"on": m.emission_enabled,
					"color": m.emission,
					"energy": m.emission_energy_multiplier,
				})
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
	_clip_lift = _measure_clip_lifts()

## The deepest each of the kit's clips drives the feet below the idle rest pose,
## which is exactly what foot_probe.gd prints. Values are MODEL space; the
## conversion to the parent's scale belongs at the point of use in _ground_feet,
## and pre-scaling them here would apply MODEL_SCALE twice.
func _measure_clip_lifts() -> Dictionary:
	if _anim == null:
		return {}
	var key: String = str(kit.model)
	if _lift_cache.has(key):
		return _lift_cache[key]
	var table: Dictionary = {}
	# kit.clips carries tuning floats (attack_speed, super_seek, ...) alongside
	# the clip names, so only the strings the rig actually has are sampled.
	for value: Variant in kit.clips.values():
		if not (value is String) or table.has(value) or not _anim.has_animation(value):
			continue
		var clip: String = value
		var a: Animation = _anim.get_animation(clip)
		var lowest := INF
		_anim.play(clip)
		for i in LIFT_SAMPLES + 1:
			_anim.seek(a.length * float(i) / float(LIFT_SAMPLES), true)
			lowest = minf(lowest, _lowest_foot_y())
		table[clip] = maxf(0.0, _foot_rest_y - lowest)
	# Sampling leaves the AnimationPlayer on the last clip at an arbitrary time.
	# _setup_model played the idle clip immediately before calling in here, so
	# put that back or the fighter renders its first frame mid-attack.
	_anim.play(kit.clips.idle)
	_anim.seek(0.0, true)
	_lift_cache[key] = table
	return table

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
##
## The lift is a CONSTANT per clip — the deepest the feet reach anywhere in that
## clip — and not the current frame's sink. Measuring it per frame tracked the
## stride, so it peaked at the trough of the run and lifted the fighter exactly
## where it used to sink: the bob moved rather than went away. A constant shifts
## the whole cycle up by its own worst frame and leaves the stride's natural
## rise and fall intact. It never pushes down, so a clip whose feet stay high
## (every `run_fast_*` variant measures 0.000) just stands normally.
func _ground_feet(delta: float) -> void:
	if _skel == null or _anim == null:
		return
	# Model space out of the table, parent space into `position`.
	var want: float = float(_clip_lift.get(_anim.current_animation, 0.0)) * _model.scale.y
	_model.position.y = lerpf(_model.position.y, want, 1.0 - exp(-delta / LIFT_EASE_TAU))

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
	_capsule_albedo = _material.albedo_color
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
	_ground_feet(get_physics_process_delta_time())
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
		_turn_to_travel(input_dir.normalized())

## How fast the body swings round while walking, in rad/s: 180 degrees in about
## a fifth of a second, so a flick of the stick still reads as instant while a
## graze along a wall is a turn rather than a snap. Dashes and every deliberate
## face_direction still pivot on the spot — this is walking only.
const TURN_RATE := 14.0
## Below this much travel (m/s) a slide is a fighter stopped dead against
## something, not a direction, so the stick keeps the body pointed at the wall
## it is pushing into.
const TURN_MIN_TRAVEL := 0.5
## A knockback above this (m/s) is a shove, not a walk. The body keeps steering
## where the stick says through it instead of whipping round to face the push.
const TURN_KNOCK_MAX := 1.0

## Point the body where it is ACTUALLY going, not where the stick is pushing.
## move_and_slide deflects anyone grazing a wall, a loot box or another fighter,
## and holding the stick's direction through that deflection is a crab walk: in
## a measured match a third of all moving frames near a wall had the model 20
## degrees or more off its own travel, and many were the full 90. Bush patches
## on the Showdown map are tucked against walls, which is where it reads worst —
## bushes themselves never block anyone (frames in open bush measured 0%).
func _turn_to_travel(stick: Vector3) -> void:
	var want := stick
	var travel := Vector3(velocity.x, 0.0, velocity.z)
	if travel.length() > TURN_MIN_TRAVEL and knockback_vel.length() < TURN_KNOCK_MAX:
		want = travel.normalized()
	var swing := facing.signed_angle_to(want, Vector3.UP)
	var limit := TURN_RATE * get_physics_process_delta_time()
	facing = facing.rotated(Vector3.UP, clampf(swing, -limit, limit)).normalized()
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
	if _material:
		_material.albedo_color = Color.WHITE
		get_tree().create_timer(FLASH_SECONDS).timeout.connect(
			func() -> void: _material.albedo_color = kit.color)
	else:
		_flash_model()

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
	stats.cubes += 1
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

# MARK: going down and coming back

## The pop. A fighter swells for a beat and bursts rather than toppling: at a
## 60 degree camera a body lying on the floor is a shape you have to read, and
## the whole point of the moment is that it is instant.
const POP_SWELL := 0.09
const POP_BURST := 0.13
## The bubble a fighter arrives inside — it grows around them while they scale
## up out of nothing, holds, then bursts and leaves them standing.
const BUBBLE_GROW := 0.26
const BUBBLE_HOLD := 0.10
const BUBBLE_POP := 0.13
const BUBBLE_RADIUS := 1.5

## A soap bubble: additive, unshaded, and brightest where the surface turns away
## from the camera, which is the whole of what makes a sphere read as a shell
## rather than as a ball. It never writes depth, so the fighter growing inside
## it is never hidden by it.
const BUBBLE_SHADER := """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec3 tint : source_color = vec3(0.55, 0.85, 1.0);
// A thicker rim than a real fresnel: at 55 px per metre a shell only a few
// degrees wide is a couple of pixels, and the first pass was almost invisible
// against the pale end zone a Cup respawn happens in.
uniform float power = 1.5;
uniform float strength = 1.0;

void fragment() {
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), power);
	ALBEDO = tint * (f * 1.55 + 0.22) * strength;
	ALPHA = clamp((f * 1.35 + 0.14) * strength, 0.0, 1.0);
}
"""

## The body, whichever kind this fighter has. Every pop and bubble acts on this
## rather than on the fighter itself, because `rotation.y` on the fighter is its
## FACING and half the game reads it — aim, bars, the ball's carry point.
func _body() -> Node3D:
	return _model if _model != null else _body_mesh

## Going down. Shared by a Showdown elimination and a Nobles Cup knock-out,
## because they are the same moment; one of them just comes back.
##
## No GLB here ships a death or hit clip — the models carry only idle, walk, run
## and an attack — so this is code either way, and a pop needs none.
func _pop_out() -> void:
	var tint: Color = kit.get("color", Color(0.9, 0.9, 0.9))
	var body := _body()
	if body == null:
		_on_popped(tint)
		return
	var tw := create_tween()
	tw.tween_property(body, "scale", _body_rest * 1.3, POP_SWELL) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "scale", _body_rest * 0.01, POP_BURST) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# On the burst, not on the hit: a ring thrown while the body is still there
	# reads as something landing on them rather than as them going.
	tw.tween_callback(_on_popped.bind(tint))

func _on_popped(tint: Color) -> void:
	_ground_ring(tint.lightened(0.3), 2.4)
	_body_burst(tint.lightened(0.45), 2.4, 10, 1.0)

## Showdown: down for good, so the node goes with the pop.
func die() -> void:
	_pop_out()
	var tw := create_tween()
	tw.tween_interval(POP_SWELL + POP_BURST + 0.04)
	tw.tween_callback(queue_free)

## Nobles Cup death: the fighter is coming back, so it is parked rather than
## freed. Everything that walks `fighters` already skips is_dead(), and health
## stays at 0 until respawn() so it keeps skipping them.
func knock_out() -> void:
	velocity = Vector3.ZERO
	knockback_vel = Vector3.ZERO
	dash = {}
	leap = {}
	# Off every layer and mask FIRST, and before the pop has finished: a fighter
	# that is going down must stop blocking a shot, soaking a melee sweep or
	# stopping the ball on the frame it dies, not on the frame it disappears.
	collision_layer = 0
	collision_mask = 0
	if _anim:
		_anim.stop()
	_pop_out()
	# Hidden at the END of the pop rather than on the frame of the hit, which is
	# what makes the death readable at all. The health bars already skip a dead
	# fighter (fighter_bars.gd:77), so no full bar hangs over the body.
	var tw := create_tween()
	tw.tween_interval(POP_SWELL + POP_BURST)
	tw.tween_callback(_hide_body)

func _hide_body() -> void:
	if not is_dead():
		return   # already back up: a respawn beat the timer
	visible = false

## Arrives inside a bubble: the shell grows, the fighter scales up out of
## nothing inside it, and it bursts. There is no arrival clip on any model
## either — Kovacs' Backflip_and_Rise and Anders' Backflip are the only two that
## could ever stand in — so this is code, and every kit gets the same one.
func _play_arrival() -> void:
	var body := _body()
	if body == null:
		return
	var tint: Color = kit.get("color", Color(0.9, 0.9, 0.9))
	body.scale = _body_rest * 0.01
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BUBBLE_SHADER
	mat.shader = sh
	mat.set_shader_parameter("tint", tint.lightened(0.45))
	var sphere := SphereMesh.new()
	sphere.radius = BUBBLE_RADIUS
	sphere.height = BUBBLE_RADIUS * 2.0
	var bubble := MeshInstance3D.new()
	bubble.mesh = sphere
	bubble.material_override = mat
	bubble.position = Vector3(0, BUBBLE_RADIUS * 0.82, 0)
	bubble.scale = Vector3.ONE * 0.05
	add_child(bubble)

	var grow := create_tween()
	grow.tween_property(bubble, "scale", Vector3.ONE, BUBBLE_GROW) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The fighter comes up a beat behind the shell, so you see the bubble form
	# and then something appear inside it rather than the two arriving together.
	grow.parallel().tween_property(body, "scale", _body_rest, BUBBLE_GROW) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.set_delay(BUBBLE_GROW * 0.35)

	var pop := create_tween()
	pop.tween_interval(BUBBLE_GROW + BUBBLE_HOLD)
	pop.tween_property(bubble, "scale", Vector3.ONE * 1.5, BUBBLE_POP)
	pop.parallel().tween_method(_fade_bubble.bind(mat), 1.0, 0.0, BUBBLE_POP)
	pop.tween_callback(bubble.queue_free)
	pop.tween_callback(_on_bubble_popped.bind(tint))

func _fade_bubble(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("strength", value)

func _on_bubble_popped(tint: Color) -> void:
	_ground_ring(tint.lightened(0.4), 2.5)
	_body_burst(tint.lightened(0.55), 1.9, 8, 0.9)

## Both effects go on the PARENT, not on the fighter: they have to outlive a
## Showdown death, which frees the fighter a third of a second later, and they
## must not inherit the topple or the collapse.
func _ground_ring(tint: Color, radius: float) -> void:
	var host := get_parent()
	if host == null:
		return
	var sw := Shockwave.new()
	sw.radius = radius
	sw.tint = tint
	host.add_child(sw)
	sw.global_position = Vector3(global_position.x, 0.03, global_position.z)

func _body_burst(tint: Color, spread: float, shards: int, height: float) -> void:
	var host := get_parent()
	if host == null:
		return
	var s := HitSpark.new()
	s.tint = tint
	s.direction = Vector3.ZERO   # no travel to fan around: HitSpark goes all round
	s.cone = PI
	s.spread = spread
	s.shards = shards
	s.height = height
	s.duration = 0.30
	host.add_child(s)
	s.global_position = Vector3(global_position.x, 0.0, global_position.z)

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
	# Undoes the topple before the drop starts: a fighter that came back still
	# lying on its back was the whole failure mode here.
	_play_arrival()

## A Nobles Cup kickoff for a fighter who is still standing. Everything respawn()
## restores EXCEPT position (kickoff places them itself) and `super_charge`,
## which is deliberately kept: losing a Super you had charged would punish the
## team that just scored, and a fighter who died for one already loses it in
## respawn(). Without this a team could concede, be handed the restart on a
## sliver of health, and lose the next one immediately — and a burn lit before
## the whistle went on ticking through a freeze that holds the victim still.
func kickoff_restore(game_now: float) -> void:
	health = max_health
	ammo = max_ammo
	ammo_locked = false
	heat_hits = 0
	sack_streak = 0
	burn_until = -1.0
	on_fire_until = -1.0
	disconnected_until = -1.0
	slow_until = -1.0
	slow_factor = 1.0
	knockback_vel = Vector3.ZERO
	dash = {}
	leap = {}
	last_damage_at = game_now
	next_attack_at = -1.0

## Damage feedback on a rigged model. The capsule can simply go white, but a
## textured character cannot: `albedo_color` MULTIPLIES the texture, so setting
## it to white is a no-op there. Emission is what reads as a hit on one.
func _flash_model() -> void:
	if _model_mats.is_empty():
		return
	for m in _model_mats:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_energy_multiplier = FLASH_ENERGY
	get_tree().create_timer(FLASH_SECONDS).timeout.connect(_unflash_model)

## Restores what each material was doing before the flash, so overlapping hits
## are idempotent rather than each one turning the glow off on its way out.
func _unflash_model() -> void:
	for i in _model_mats.size():
		var m: BaseMaterial3D = _model_mats[i]
		var was: Dictionary = _model_emission[i]
		m.emission_enabled = bool(was.on)
		m.emission = was.color
		m.emission_energy_multiplier = float(was.energy)

func set_concealed(hidden: bool, self_view: bool) -> void:
	if is_dead():
		return   # knocked out in Nobles Cup: respawn() owns `visible`, not this
	if self_view:
		var want: int = 1 if hidden else 0
		if want == _conceal_applied:
			return
		_conceal_applied = want
		# Concealment is a TINT, not a fade, and that is the whole point. A
		# character is a closed solid, so every per-fragment transparency mode
		# shows you its own far side — the inside of its skull through its face,
		# Sanjit's staff through his chest, shoes through shins. The usual
		# answer, ALPHA_DEPTH_PRE_PASS, is what this used and it does nothing
		# under the **Forward Mobile** renderer this project runs on: every
		# model came out a smear the moment it stood in a bush. ALPHA_HASH fixes
		# the sort (it renders in the opaque pass with a stochastic discard) but
		# dithers, and at any alpha low enough to read as hidden the sparkle on
		# a moving fighter is worse than what it replaced.
		#
		# So: stay opaque and multiply the albedo down toward the bush instead.
		# No sorting, no dithering, and the tell still reads — you go dark and
		# green while the foliage around you opens up.
		if _material:
			_material.albedo_color = _capsule_albedo * CONCEAL_TINT if hidden \
					else _capsule_albedo
		for i in _model_mats.size():
			var m: BaseMaterial3D = _model_mats[i]
			m.albedo_color = _model_albedo[i] * CONCEAL_TINT if hidden \
					else _model_albedo[i]
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
