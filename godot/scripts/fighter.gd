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
var _bar_fill: Sprite3D
var _bar_bg: Sprite3D
var _pending_popup := 0

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

	_bar_bg = _bar(Color(0.1, 0.1, 0.1, 0.8), 2.25)
	_bar_fill = _bar(kit.color, 2.28)
	_refresh_bar()

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

func _refresh_bar() -> void:
	var frac: float = clamp(float(health) / float(max_health), 0.0, 1.0)
	_bar_fill.scale.x = 1.06 * frac
	_bar_fill.position.x = -0.53 * (1.0 - frac) * 1.1 * 0.0  # centered is fine at this size

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
	# Hit flash
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
		_material.albedo_color.a = 0.55 if hidden else 1.0
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if hidden else BaseMaterial3D.TRANSPARENCY_DISABLED
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
