class_name Fighter
extends CharacterBody3D
## One fighter (player or bot): stats, movement, dash, billboard health bar,
## damage popups. Visual is a colored capsule until Meshy models land.

var kit: Dictionary
var display_name := "Fighter"
var is_player := false

var max_health := Kits.BASE_MAX_HEALTH
var health := Kits.BASE_MAX_HEALTH
var ammo := Kits.MAX_AMMO
var super_charge := 0.0
var cubes := 0
var last_damage_at := -100.0
var facing := Vector3.FORWARD

var knockback_vel := Vector3.ZERO
var dash: Dictionary = {}   # empty = not dashing

var _body_mesh: MeshInstance3D
var _material: StandardMaterial3D
var _model: Node3D
var _anim: AnimationPlayer
var _held_item: Node3D   # e.g. Sanjit's staff — hidden while his Super flies
var _attack_anim_until := 0.0
var _pending_popup := 0


func is_dead() -> bool:
	return health <= 0

func is_dashing() -> bool:
	return not dash.is_empty()

func damage_multiplier() -> float:
	return 1.0 + Kits.DAMAGE_BONUS_PER_CUBE * cubes

func is_super_ready() -> bool:
	return super_charge >= 1.0

func _ready() -> void:
	collision_layer = 1 << 2                  # fighters
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 5)  # walls|water|fighters|boxes

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	add_child(col)

	if kit.has("model"):
		_setup_model()
	else:
		_setup_capsule()


## Rigged Meshy character: model stands on y=0 facing -Z, clips per kit.
func _setup_model() -> void:
	var scene: PackedScene = load(kit.model)
	_model = scene.instantiate()
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

## Placeholder capsule for kits without a model yet.
func _setup_capsule() -> void:
	_body_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
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
	nose.position = Vector3(0, 1.15, -0.42)
	add_child(nose)

## Drives idle/run/attack clips; called by the scene each frame with game time.
func update_animation(game_now: float) -> void:
	if _anim == null or is_dead():
		return
	if game_now < _attack_anim_until:
		return
	var clips: Dictionary = kit.clips
	var moving := velocity.length() > 0.5
	var want: String = clips.run if moving else clips.idle
	if _anim.current_animation != want:
		_anim.play(want, 0.15)

func play_attack_animation(game_now: float, is_super: bool = false) -> void:
	if _anim == null:
		return
	var clips: Dictionary = kit.clips
	var clip_name: String = clips.get("super", clips.attack) if is_super else clips.attack
	var speed: float = clips.get("super_speed", clips.get("attack_speed", 1.0)) if is_super \
			else clips.get("attack_speed", 1.0)
	var seek_to: float = clips.get("super_seek", 0.0) if is_super else 0.0
	_anim.play(clip_name, 0.05, speed)
	if seek_to > 0.0:
		_anim.seek(seek_to, true)
	var a: Animation = _anim.get_animation(clip_name)
	if a:
		_attack_anim_until = game_now + (a.length - seek_to) / speed

## Show/hide a model's held item (Sanjit's staff) while a thrown copy flies.
func set_held_item_visible(shown: bool) -> void:
	if _held_item:
		_held_item.visible = shown

func apply_movement(input_dir: Vector3) -> void:
	if is_dashing():
		if dash.windup > 0.0:
			velocity = Vector3.ZERO
		else:
			velocity = dash.direction * dash.weapon.speed
		move_and_slide()
		return
	var speed: float = kit.get("move_speed", Kits.MOVE_SPEED)
	velocity = input_dir * speed + knockback_vel
	move_and_slide()
	if input_dir.length() > 0.1:
		facing = input_dir.normalized()
		rotation.y = atan2(-facing.x, -facing.z)

func face_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.001:
		return
	facing = flat.normalized()
	rotation.y = atan2(-facing.x, -facing.z)

func begin_dash(weapon: Dictionary, direction: Vector3) -> void:
	dash = {"weapon": weapon, "direction": direction.normalized(), "remaining": weapon.range,
			"windup": 0.35, "hit": [], "crossed_water": false}
	face_direction(direction)
	collision_mask = (1 << 0) | (1 << 5)   # walls + boxes only: dash crosses water

func end_dash() -> void:
	dash = {}
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 5)

func consume_ammo() -> bool:
	if ammo < 1.0:
		return false
	ammo -= 1.0
	return true

func consume_super() -> bool:
	if not is_super_ready():
		return false
	super_charge = 0.0
	return true

func charge_super(damage_dealt: int) -> void:
	super_charge = min(1.0, super_charge + damage_dealt / Kits.SUPER_CHARGE_DAMAGE)

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

func collect_cube() -> void:
	cubes += 1
	max_health += Kits.HEALTH_PER_CUBE
	health += Kits.HEALTH_PER_CUBE
	_popup("+%d HP" % Kits.HEALTH_PER_CUBE, Color(0.85, 0.45, 1.0))

func tick(delta: float, now: float) -> void:
	if ammo < Kits.MAX_AMMO:
		ammo = min(Kits.MAX_AMMO, ammo + delta / Kits.AMMO_RECHARGE_SECONDS)
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

func set_concealed(hidden: bool, self_view: bool) -> void:
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
