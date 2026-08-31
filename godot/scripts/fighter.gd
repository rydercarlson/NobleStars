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
var _attack_anim_until := 0.0
var _bar_fill: Sprite3D
var _bar_bg: Sprite3D
var _ammo_backs: Array[Sprite3D] = []
var _ammo_fills: Array[Sprite3D] = []
var _last_ammo_shown := -1.0
var _pending_popup := 0

const BAR_WIDTH := 1.06   # _bar_fill scale.x at full health
const PIP_WIDTH := 0.30
const PIP_GAP := 0.08

func is_dead() -> bool:
	return health <= 0

func is_dashing() -> bool:
	return not dash.is_empty()

func damage_multiplier() -> float:
	return 1.0 + Kits.DAMAGE_BONUS_PER_CUBE * cubes

func is_super_ready() -> bool:
	return super_charge >= 1.0

static func white_tex() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

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

	_bar_bg = _bar(Color(0.1, 0.1, 0.1, 0.8), 2.25)
	_bar_fill = _bar(kit.color, 2.28)
	for i in 3:
		_ammo_backs.append(_pip(i, Color(0.1, 0.1, 0.1, 0.7), 2.06))
		_ammo_fills.append(_pip(i, Color(1.0, 0.65, 0.1, 0.95), 2.08))
	_refresh_bar()

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

func play_attack_animation(game_now: float) -> void:
	if _anim == null:
		return
	var clips: Dictionary = kit.clips
	var speed: float = clips.get("attack_speed", 1.0)
	_anim.play(clips.attack, 0.05, speed)
	var a: Animation = _anim.get_animation(clips.attack)
	if a:
		_attack_anim_until = game_now + a.length / speed

func _bar(color: Color, y: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = white_tex()
	s.modulate = color
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.pixel_size = 0.3
	s.scale = Vector3(1.1, 0.12, 1)
	s.position.y = y
	add_child(s)
	return s

func _pip(index: int, color: Color, y: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = white_tex()
	s.modulate = color
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.pixel_size = 0.3
	s.scale = Vector3(PIP_WIDTH, 0.07, 1)
	s.position = Vector3(1.2 * (-0.38 + (PIP_WIDTH + PIP_GAP) * index), y, 0)
	add_child(s)
	return s

func _refresh_bar() -> void:
	# Health drains from the right; the left edge stays fixed.
	var frac: float = clamp(float(health) / float(max_health), 0.0, 1.0)
	_bar_fill.scale.x = BAR_WIDTH * frac
	_bar_fill.position.x = -(BAR_WIDTH * 1.2 / 2.0) * (1.0 - frac)

func _refresh_ammo() -> void:
	if abs(ammo - _last_ammo_shown) < 0.02:
		return
	_last_ammo_shown = ammo
	for i in 3:
		var f: float = clamp(ammo - i, 0.0, 1.0)
		_ammo_fills[i].scale.x = max(PIP_WIDTH * f, 0.001)
		# Anchor each pip's fill to its own left edge.
		var pip_left := -0.53 + (PIP_WIDTH + PIP_GAP) * i
		_ammo_fills[i].position.x = 1.2 * (pip_left + PIP_WIDTH * f / 2.0)
		_ammo_fills[i].visible = f > 0.02

func apply_movement(input_dir: Vector3) -> void:
	if is_dashing():
		if dash.windup > 0.0:
			velocity = Vector3.ZERO
		else:
			velocity = dash.direction * dash.weapon.speed
		move_and_slide()
		return
	velocity = input_dir * Kits.MOVE_SPEED + knockback_vel
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
	_refresh_bar()
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
	_refresh_bar()
	_popup("+%d HP" % Kits.HEALTH_PER_CUBE, Color(0.85, 0.45, 1.0))

func tick(delta: float, now: float) -> void:
	if ammo < Kits.MAX_AMMO:
		ammo = min(Kits.MAX_AMMO, ammo + delta / Kits.AMMO_RECHARGE_SECONDS)
	_refresh_ammo()
	if not is_dead() and health < max_health and now - last_damage_at > Kits.REGEN_DELAY:
		health = min(max_health, health + int(ceil(max_health * Kits.REGEN_RATE_PER_SECOND * delta)))
		_refresh_bar()
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
