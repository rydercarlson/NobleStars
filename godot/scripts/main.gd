extends Node3D
## Match controller: spawning, phases, combat resolution, camera, HUD.
## Debug env hooks (see CLAUDE.md): NS3_KIT, NS3_AUTOFIRE, NS3_AUTOWALK,
## NS3_GODMODE, NS3_SHOTS="prefix:t1,t2,..." (screenshots at match times).

enum Phase { COUNTDOWN, PLAYING, ENDED }

var arena: Arena
var gas: GasRing
var cam: Camera3D
var player: Fighter
var fighters: Array[Fighter] = []
var brains: Array[BotBrain] = []
var phase := Phase.COUNTDOWN
var phase_at := 0.0
var now := 0.0

# HUD
var hud: CanvasLayer
var center_label: Label
var players_label: Label
var feed_label: Label
var status_label: Label
var move_stick: TouchStick
var aim_stick: TouchStick
var super_stick: TouchStick   # dedicated Super joystick, anchored at the button
var super_btn: SuperButton
var fighter_bars: FighterBars
var results: Control
var results_title: Label
var aim_mesh: MeshInstance3D

# Orthographic, like Brawl Stars: wall verticals project straight up-down
# everywhere on screen and nothing shears as the camera pans. ORTHO_SIZE is
# the vertical view extent in meters (~12 tiles across at 16:9).
# Pitch ~60° — oblique enough to read as 2.5D rather than straight top-down.
const CAMERA_OFFSET := Vector3(0, 16.0, 9.2)
const CAMERA_ORTHO_SIZE := 12.9
const TAP_THRESHOLD := 0.3

# Debug hooks
var god_mode := OS.get_environment("NS3_GODMODE") != ""
var auto_fire := float(OS.get_environment("NS3_AUTOFIRE")) if OS.get_environment("NS3_AUTOFIRE") != "" else 0.0
var _last_auto_fire := 0.0
var _shot_prefix := ""
var _shot_times: Array[float] = []

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.75, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAMERA_ORTHO_SIZE
	add_child(cam)

	# Ground-projected aim indicator (cone / lob landing circle).
	aim_mesh = MeshInstance3D.new()
	aim_mesh.mesh = ImmediateMesh.new()
	var aim_mat := StandardMaterial3D.new()
	aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_mat.vertex_color_use_as_albedo = true
	aim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	aim_mesh.material_override = aim_mat
	add_child(aim_mesh)

	_build_hud()

	var shots := OS.get_environment("NS3_SHOTS")
	if shots != "":
		var parts := shots.split(":")
		_shot_prefix = parts[0]
		for t in parts[1].split(","):
			_shot_times.append(float(t))

	start_match()

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	fighter_bars = FighterBars.new()
	fighter_bars.game = self
	hud.add_child(fighter_bars)   # under the sticks and labels
	move_stick = TouchStick.new()
	aim_stick = TouchStick.new()
	super_stick = TouchStick.new()
	super_btn = SuperButton.new()
	hud.add_child(move_stick)
	hud.add_child(aim_stick)
	hud.add_child(super_btn)
	hud.add_child(super_stick)
	super_btn.layout(get_viewport().get_visible_rect().size)
	get_viewport().size_changed.connect(func() -> void:
		super_btn.layout(get_viewport().get_visible_rect().size))

	center_label = _label(Vector2(640, 240), 72, HORIZONTAL_ALIGNMENT_CENTER)
	players_label = _label(Vector2(1130, 20), 26, HORIZONTAL_ALIGNMENT_RIGHT)
	feed_label = _label(Vector2(830, 60), 18, HORIZONTAL_ALIGNMENT_RIGHT)
	status_label = _label(Vector2(20, 20), 20, HORIZONTAL_ALIGNMENT_LEFT)
	_build_results_overlay()

func _build_results_overlay() -> void:
	results = Control.new()
	results.set_anchors_preset(Control.PRESET_FULL_RECT)
	results.visible = false
	hud.add_child(results)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	results.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	results.add_child(vbox)

	results_title = Label.new()
	results_title.add_theme_font_size_override("font_size", 52)
	results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(results_title)

	var again := Button.new()
	again.text = "  PLAY AGAIN  "
	again.add_theme_font_size_override("font_size", 30)
	again.pressed.connect(func() -> void:
		results.visible = false
		start_match())
	vbox.add_child(again)

	var menu := Button.new()
	menu.text = "  CHARACTER SELECT  "
	menu.add_theme_font_size_override("font_size", 22)
	menu.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://menu.tscn"))
	vbox.add_child(menu)

func _label(pos: Vector2, size: int, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(430, 0) if align != HORIZONTAL_ALIGNMENT_CENTER else Vector2(0, 0)
	hud.add_child(l)
	return l

func start_match() -> void:
	for c in get_children():
		if c is Arena or c is GasRing or c is Fighter or c is Projectile or c is Lob or c is Boomerang:
			c.queue_free()
	for c in get_tree().get_nodes_in_group("lootbox") + get_tree().get_nodes_in_group("cube"):
		c.queue_free()
	fighters.clear()
	brains.clear()

	arena = Arena.new()
	add_child(arena)
	gas = null

	await get_tree().process_frame   # let arena _ready run

	var spawns := arena.spawn_points.duplicate()
	spawns.shuffle()

	var player_kit: Dictionary = Session.kit if not Session.kit.is_empty() else Kits.nova()
	player = _spawn_fighter(player_kit, spawns.pop_front(), true)
	player.display_name = "You"
	if OS.get_environment("NS3_SUPER") != "":   # debug: start with Super charged
		player.super_charge = 1.0

	var i := 1
	while not spawns.is_empty() and i <= 9:
		var kit: Dictionary = Kits.all().pick_random()
		var bot := _spawn_fighter(kit, spawns.pop_front(), false)
		bot.display_name = "%s %d" % [kit.name, i]
		brains.append(BotBrain.new(bot))
		i += 1

	for p in arena.box_points:
		_spawn_lootbox(p)

	phase = Phase.COUNTDOWN
	phase_at = now
	center_label.text = "3"
	feed_label.text = ""
	results.visible = false
	_update_players_label()
	cam.position = player.position + CAMERA_OFFSET
	cam.look_at(player.position, Vector3.UP)
	# Fighters were teleported to spawns; don't interpolate from old spots.
	for f in fighters:
		f.reset_physics_interpolation()
	cam.reset_physics_interpolation()

func _spawn_fighter(kit: Dictionary, pos: Vector3, is_player: bool) -> Fighter:
	var f := Fighter.new()
	f.kit = kit
	f.is_player = is_player
	f.position = pos
	add_child(f)
	fighters.append(f)
	return f

func _spawn_lootbox(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 5
	body.position = pos + Vector3(0, 0.5, 0)
	body.set_meta("health", 900)
	body.add_to_group("lootbox")
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 1.0, 1.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.6, 0.26)
	box.material = mat
	m.mesh = box
	body.add_child(m)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 1.0, 1.1)
	col.shape = shape
	body.add_child(col)
	add_child(body)

func _spawn_cube(pos: Vector3) -> void:
	var area := Area3D.new()
	area.collision_layer = 1 << 4
	area.collision_mask = 1 << 2
	area.position = pos + Vector3(0, 0.5, 0)
	area.add_to_group("cube")
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.1, 0.5)
	box.material = mat
	m.mesh = box
	area.add_child(m)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body is Fighter and not body.is_dead() and is_instance_valid(area):
			body.collect_cube()
			area.queue_free())
	add_child(area)

# MARK: combat

func deal_damage(amount: int, target: Fighter, attacker: Fighter,
		kb_dir := Vector3.ZERO, kb_strength := 0.0) -> void:
	if target.is_dead():
		return
	if god_mode and target == player:
		return
	target.take_damage(amount, now)
	if kb_strength > 0.0:
		target.receive_knockback(kb_dir, kb_strength)
	attacker.charge_super(amount)
	if target.is_dead():
		_eliminate(target, attacker.display_name)

func perform_attack(f: Fighter, weapon: Dictionary, dir: Vector3, dist: float) -> void:
	var unit := Vector3(dir.x, 0, dir.z).normalized()
	f.face_direction(unit)
	f.play_attack_animation(now)
	match int(weapon.style):
		Kits.Style.PELLETS:
			var base := atan2(unit.x, unit.z)
			for p in int(weapon.pellets):
				var t: float = (float(p) / float(max(1, int(weapon.pellets) - 1)) - 0.5) \
					if int(weapon.pellets) > 1 else 0.0
				var ang: float = base + deg_to_rad(weapon.spread_deg) * t
				var pd := Vector3(sin(ang), 0, cos(ang))
				var proj := Projectile.new()
				proj.weapon = weapon
				proj.damage = int(weapon.damage * f.damage_multiplier())
				proj.owner_fighter = f
				proj.direction = pd
				proj.position = f.global_position + pd * 0.8 + Vector3(0, 1.0, 0)
				proj.origin = proj.position
				proj.body_entered.connect(_on_projectile_hit.bind(proj))
				add_child(proj)
		Kits.Style.LOB:
			var throw_dist: float = clamp(dist, Kits.TILE * 1.5, weapon.range)
			var lob := Lob.new()
			lob.weapon = weapon
			lob.damage = int(weapon.damage * f.damage_multiplier())
			lob.owner_fighter = f
			lob.start_pos = f.global_position + Vector3(0, 0.5, 0)
			lob.target_pos = f.global_position + unit * throw_dist
			lob.on_land = _on_lob_land
			add_child(lob)
		Kits.Style.MELEE:
			_melee(f, weapon, unit)
			# pellets > 1 = a combo: repeat strikes a beat apart (Sanjit's
			# one-two punch), each following the fighter's current facing.
			# No anim re-trigger: the attack clip covers the whole combo.
			for i in range(1, int(weapon.pellets)):
				get_tree().create_timer(0.22 * i).timeout.connect(func() -> void:
					if phase == Phase.PLAYING and is_instance_valid(f) and not f.is_dead():
						_melee(f, weapon, f.facing))
		Kits.Style.DASH:
			f.begin_dash(weapon, unit)
		Kits.Style.BOOMERANG:
			var boom := Boomerang.new()
			boom.weapon = weapon
			boom.damage = int(weapon.damage * f.damage_multiplier())
			boom.owner_fighter = f
			boom.direction = unit
			boom.position = f.global_position + unit * 0.8 + Vector3(0, 1.2, 0)
			boom.origin = boom.position
			boom.body_entered.connect(_on_boomerang_hit.bind(boom))
			add_child(boom)

func _on_projectile_hit(body: Node3D, proj: Projectile) -> void:
	if not is_instance_valid(proj):
		return
	if body is Fighter:
		if body == proj.owner_fighter or body.is_dead() or proj.already_hit.has(body):
			return
		proj.already_hit.append(body)
		deal_damage(proj.damage, body, proj.owner_fighter, proj.direction, proj.weapon.knockback)
		if not proj.weapon.pierces:
			proj.queue_free()
	elif body.is_in_group("lootbox"):
		_damage_lootbox(body, proj.damage)
		proj.queue_free()
	elif body.is_in_group("breakable") and proj.weapon.destroys_walls:
		body.queue_free()   # shell plows through
	elif not body.is_in_group("water"):
		proj.queue_free()

func _on_boomerang_hit(body: Node3D, boom: Boomerang) -> void:
	if not is_instance_valid(boom):
		return
	if body is Fighter:
		if body == boom.owner_fighter or body.is_dead() or boom.already_hit.has(body):
			return
		boom.already_hit.append(body)
		deal_damage(boom.damage, body, boom.owner_fighter, boom.travel_dir(), boom.weapon.knockback)
	elif body.is_in_group("lootbox") and not boom.already_hit.has(body):
		boom.already_hit.append(body)
		_damage_lootbox(body, boom.damage)

func _on_lob_land(lob: Lob) -> void:
	var center: Vector3 = lob.target_pos
	for f in fighters:
		if f == lob.owner_fighter or f.is_dead():
			continue
		if Vector2(f.global_position.x - center.x, f.global_position.z - center.z).length() <= lob.weapon.aoe + 0.5:
			deal_damage(lob.damage, f, lob.owner_fighter)
	for box in get_tree().get_nodes_in_group("lootbox"):
		if box.global_position.distance_to(center) <= lob.weapon.aoe + 0.7:
			_damage_lootbox(box, lob.damage)

## Fading ground wedge so melee swings are visible (they hit instantly and
## otherwise show nothing but the attack animation).
func _spawn_melee_arc(f: Fighter, weapon: Dictionary, unit: Vector3) -> void:
	var arc := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc.material_override = mat
	var base := atan2(unit.x, unit.z)
	var half := deg_to_rad(weapon.spread_deg) / 2.0
	var tint: Color = f.kit.color.lightened(0.5)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 10
	for i in steps:
		var a0 := base - half + half * 2.0 * float(i) / steps
		var a1 := base - half + half * 2.0 * float(i + 1) / steps
		mesh.surface_set_color(Color(tint, 0.55))
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_set_color(Color(tint, 0.1))
		mesh.surface_add_vertex(Vector3(sin(a0), 0, cos(a0)) * weapon.range)
		mesh.surface_add_vertex(Vector3(sin(a1), 0, cos(a1)) * weapon.range)
	mesh.surface_end()
	arc.mesh = mesh
	arc.position = f.global_position + Vector3(0, 0.15, 0)
	add_child(arc)
	var tw := create_tween()
	tw.tween_property(arc, "transparency", 1.0, 0.22).from(0.0)
	tw.tween_callback(arc.queue_free)

func _melee(f: Fighter, weapon: Dictionary, unit: Vector3) -> void:
	_spawn_melee_arc(f, weapon, unit)
	var dmg := int(weapon.damage * f.damage_multiplier())
	var half := deg_to_rad(weapon.spread_deg) / 2.0
	for target in fighters:
		if target == f or target.is_dead():
			continue
		var v := target.global_position - f.global_position
		v.y = 0
		if v.length() > weapon.range + 0.5:
			continue
		if abs(unit.signed_angle_to(v.normalized(), Vector3.UP)) > half:
			continue
		if not has_line_of_sight(f.global_position, target.global_position):
			continue
		deal_damage(dmg, target, f, unit, weapon.knockback)
	for box in get_tree().get_nodes_in_group("lootbox"):
		var v = box.global_position - f.global_position
		v.y = 0
		if v.length() <= weapon.range + 0.7 and abs(unit.signed_angle_to(v.normalized(), Vector3.UP)) <= half:
			_damage_lootbox(box, dmg)

func _damage_lootbox(box: Node, amount: int) -> void:
	if not is_instance_valid(box):
		return
	var hp: int = box.get_meta("health") - amount
	box.set_meta("health", hp)
	if hp <= 0:
		_spawn_cube(box.global_position - Vector3(0, 0.5, 0))
		box.queue_free()

func _update_dashes(delta: float) -> void:
	for f in fighters:
		if not f.is_dashing():
			continue
		var d: Dictionary = f.dash
		if d.windup > 0.0:
			d.windup -= delta
			continue
		d.remaining -= d.weapon.speed * delta
		if arena.tile_at(f.global_position) == "~":
			d.crossed_water = true
		for enemy in fighters:
			if enemy == f or enemy.is_dead() or d.hit.has(enemy):
				continue
			if f.global_position.distance_to(enemy.global_position) < 1.3:
				d.hit.append(enemy)
				var mult: float = d.weapon.water_mult if d.crossed_water else 1.0
				deal_damage(int(d.weapon.damage * mult * f.damage_multiplier()),
							enemy, f, d.direction, d.weapon.knockback)
		var over_water := arena.tile_at(f.global_position) == "~"
		if d.remaining <= 0.0 and not over_water:
			f.end_dash()
		elif d.remaining < -4.0 * Kits.TILE:
			f.end_dash()

# MARK: senses

func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(
		from + Vector3(0, 1, 0), to + Vector3(0, 1, 0), 1)  # walls layer only
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()

func can_see(viewer: Fighter, target: Fighter) -> bool:
	var dist := viewer.global_position.distance_to(target.global_position)
	if arena.tile_at(target.global_position) == "b" and dist > Kits.TILE * 2.0:
		return false
	return has_line_of_sight(viewer.global_position, target.global_position)

func nearest_visible_enemy(viewer: Fighter, within: float) -> Fighter:
	var best: Fighter = null
	var best_d := INF
	for f in fighters:
		if f == viewer or f.is_dead():
			continue
		var d := viewer.global_position.distance_to(f.global_position)
		if d < within and d < best_d and can_see(viewer, f):
			best = f
			best_d = d
	return best

func nearest_loot(pos: Vector3):
	var best = null
	var best_d := Kits.TILE * 9.0
	for n in get_tree().get_nodes_in_group("lootbox") + get_tree().get_nodes_in_group("cube"):
		var d: float = pos.distance_to(n.global_position)
		if d < best_d and gas_contains(n.global_position):
			best = n.global_position
			best_d = d
	return best

func random_wander_point(origin: Vector3) -> Vector3:
	for i in 8:
		var ang := randf() * TAU
		var r := randf_range(3.0, 6.0) * Kits.TILE
		var p := origin + Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not arena.blocks_movement(p) and gas_contains(p):
			return p
	return gas_safe_center()

func gas_contains(pos: Vector3) -> bool:
	return gas == null or gas.contains(pos)

func gas_safe_center() -> Vector3:
	return gas.safe_center() if gas else Vector3(arena.map_size() / 2, 0, arena.map_size() / 2)

# MARK: match flow

func _eliminate(f: Fighter, killer: String) -> void:
	var rank := fighters.size()
	fighters.erase(f)
	for b in brains.duplicate():
		if b.fighter == f:
			brains.erase(b)
	f.die()
	_update_players_label()
	feed_label.text = "%s eliminated %s" % [killer, f.display_name] if killer != "" \
		else "%s died in the gas" % f.display_name
	if f == player:
		_end_match(rank, false)
	elif fighters.size() == 1 and fighters[0] == player:
		_end_match(1, true)

func _end_match(rank: int, victory: bool) -> void:
	phase = Phase.ENDED
	center_label.text = ""
	move_stick.release()
	aim_stick.release()
	super_stick.release()
	results_title.text = ("VICTORY!" if victory else "DEFEATED") + "\nYou placed #%d of 10" % rank
	results_title.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.2) if victory else Color(0.95, 0.4, 0.35))
	results.visible = true

func _update_players_label() -> void:
	players_label.text = "%d LEFT" % fighters.size()

# MARK: loop

func _physics_process(delta: float) -> void:
	now += delta
	match phase:
		Phase.COUNTDOWN:
			var remaining := 3.5 - (now - phase_at)
			if remaining <= 0.0:
				phase = Phase.PLAYING
				center_label.text = "FIGHT!"
				get_tree().create_timer(0.8).timeout.connect(func() -> void:
					if phase == Phase.PLAYING:
						center_label.text = "")
				gas = GasRing.new()
				add_child(gas)
				gas.start(now, arena.columns)
			else:
				center_label.text = str(int(ceil(remaining)))
			for f in fighters:
				f.apply_movement(Vector3.ZERO)
		Phase.PLAYING:
			_run_playing(delta)
		Phase.ENDED:
			if Input.is_physical_key_pressed(KEY_R):
				start_match()

	for f in fighters:
		f.update_animation(now)
	_update_aim_indicator()
	_update_concealment()
	_update_status()
	_shot_check()

func _update_aim_indicator() -> void:
	var im: ImmediateMesh = aim_mesh.mesh
	im.clear_surfaces()
	if phase != Phase.PLAYING or player == null or not is_instance_valid(player) \
			or player.is_dead():
		return
	# The dedicated Super stick takes priority over the aim stick.
	var use_super := super_stick.active
	var stick: TouchStick = super_stick if use_super else aim_stick
	if not stick.active or stick.value.length() < TAP_THRESHOLD:
		return
	var weapon: Dictionary = player.kit["super"] if use_super else player.kit.weapon
	var color := Color(1.0, 0.7, 0.2, 0.4) if use_super else Color(1, 1, 1, 0.3)
	var origin := player.global_position + Vector3(0, 0.08, 0)
	var dir := Vector3(stick.value.x, 0, stick.value.y).normalized()

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(color)
	if int(weapon.style) == Kits.Style.LOB:
		# Landing-zone circle at the throw distance.
		var dist: float = clamp(stick.value.length() * weapon.range,
								Kits.TILE * 1.5, weapon.range)
		var center := origin + dir * dist
		for i in 24:
			var a0 := TAU * i / 24.0
			var a1 := TAU * (i + 1) / 24.0
			im.surface_add_vertex(center)
			im.surface_add_vertex(center + Vector3(cos(a0), 0, sin(a0)) * weapon.aoe)
			im.surface_add_vertex(center + Vector3(cos(a1), 0, sin(a1)) * weapon.aoe)
	else:
		# Cone matching the attack's spread and range.
		var half := deg_to_rad(maxf(weapon.spread_deg, 8.0)) / 2.0
		var base := atan2(dir.x, dir.z)
		var steps := 12
		for i in steps:
			var a0 := base - half + 2.0 * half * i / steps
			var a1 := base - half + 2.0 * half * (i + 1) / steps
			im.surface_add_vertex(origin)
			im.surface_add_vertex(origin + Vector3(sin(a0), 0, cos(a0)) * weapon.range)
			im.surface_add_vertex(origin + Vector3(sin(a1), 0, cos(a1)) * weapon.range)
	im.surface_end()

	if int(weapon.style) == Kits.Style.LOB:
		# Flight-path arc from the racket to the landing zone.
		var dist2: float = clamp(stick.value.length() * weapon.range,
								 Kits.TILE * 1.5, weapon.range)
		var start := player.global_position + Vector3(0, 0.5, 0)
		var target := player.global_position + dir * dist2
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		im.surface_set_color(Color(color.r, color.g, color.b, 0.85))
		var arc_steps := 20
		for i in arc_steps + 1:
			var t := float(i) / arc_steps
			var flat := start.lerp(target, t)
			var height := 4.0 * 3.0 * t * (1.0 - t)   # same parabola as Lob
			im.surface_add_vertex(flat + Vector3(0, height + 0.3, 0))
		im.surface_end()

func _run_playing(delta: float) -> void:
	if not player.is_dead():
		var dir := Vector3.ZERO
		if OS.get_environment("NS3_AUTOWALK") != "":
			var parts := OS.get_environment("NS3_AUTOWALK").split(",")
			dir = Vector3(float(parts[0]), 0, float(parts[1]))
		elif move_stick.active:
			dir = Vector3(move_stick.value.x, 0, move_stick.value.y)
		else:
			if Input.is_physical_key_pressed(KEY_W): dir.z -= 1
			if Input.is_physical_key_pressed(KEY_S): dir.z += 1
			if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
			if Input.is_physical_key_pressed(KEY_D): dir.x += 1
			dir = dir.normalized()
		player.apply_movement(dir.limit_length(1.0))

	for b in brains:
		var d := b.decide(now, self)
		b.fighter.apply_movement(d.move)
		if d.fire_dir != null and not b.fighter.is_dashing():
			if d.use_super and b.fighter.consume_super():
				perform_attack(b.fighter, b.fighter.kit["super"], d.fire_dir, d.fire_dist)
			elif not d.use_super and b.fighter.consume_ammo():
				perform_attack(b.fighter, b.fighter.kit.weapon, d.fire_dir, d.fire_dist)

	_update_dashes(delta)
	for f in fighters:
		f.tick(delta, now)

	if gas:
		var vulnerable := fighters.filter(func(f): return not (god_mode and f == player))
		for f in gas.tick(now, vulnerable):
			if f.is_dead():
				_eliminate(f, "")

	if auto_fire > 0.0 and now - _last_auto_fire >= auto_fire and not player.is_dead():
		_last_auto_fire = now
		var weapon: Dictionary = player.kit["super"] if player.is_super_ready() else player.kit.weapon
		var enemy := nearest_visible_enemy(player, weapon.range * 1.1)
		var dir := player.facing
		var dist: float = weapon.range
		if enemy:
			dir = enemy.global_position - player.global_position
			dist = dir.length()
		_fire_player(weapon, dir, dist)

func _fire_player(weapon: Dictionary, dir: Vector3, dist: float) -> void:
	if phase != Phase.PLAYING or player.is_dead() or player.is_dashing():
		return
	if weapon == player.kit["super"]:
		if player.consume_super():
			perform_attack(player, weapon, dir, dist)
	elif player.consume_ammo():
		perform_attack(player, weapon, dir, dist)

func _unhandled_input(event: InputEvent) -> void:
	if player == null or not is_instance_valid(player):
		return
	# Touch controls (mouse is emulated as touch on desktop): left half of
	# the screen moves, right half aims — release to fire, tap to auto-aim.
	if event is InputEventScreenTouch:
		var half := get_viewport().get_visible_rect().size.x / 2.0
		if event.pressed:
			if phase != Phase.PLAYING:
				return
			if super_btn.hit(event.position) and not super_stick.active:
				# The Super has its own joystick, anchored at the button.
				if player.is_super_ready():
					super_stick.begin(super_btn.center, event.index)
					super_stick.update_drag(event.position)
			elif event.position.x < half and not move_stick.active:
				move_stick.begin(event.position, event.index)
			elif event.position.x >= half and not aim_stick.active:
				aim_stick.begin(event.position, event.index)
		else:
			if move_stick.active and event.index == move_stick.touch_index:
				move_stick.release()
			elif super_stick.active and event.index == super_stick.touch_index:
				var sv: Vector2 = super_stick.value
				super_stick.release()
				_release_fire(sv, true)
			elif aim_stick.active and event.index == aim_stick.touch_index:
				var v: Vector2 = aim_stick.value
				aim_stick.release()
				_release_fire(v, false)
	elif event is InputEventScreenDrag:
		if move_stick.active and event.index == move_stick.touch_index:
			move_stick.update_drag(event.position)
		elif super_stick.active and event.index == super_stick.touch_index:
			super_stick.update_drag(event.position)
			if super_stick.value.length() > 0.15:
				player.face_direction(Vector3(super_stick.value.x, 0, super_stick.value.y))
		elif aim_stick.active and event.index == aim_stick.touch_index:
			aim_stick.update_drag(event.position)
			if aim_stick.value.length() > 0.15:
				player.face_direction(Vector3(aim_stick.value.x, 0, aim_stick.value.y))
	elif event is InputEventKey and event.pressed and not event.echo and phase == Phase.PLAYING:
		# Desktop shortcuts kept for playtesting.
		if event.physical_keycode == KEY_SPACE:
			_auto_aim_fire(player.kit.weapon, false)
		elif event.physical_keycode == KEY_E and player.is_super_ready():
			_auto_aim_fire(player.kit["super"], true)

func _release_fire(stick_value: Vector2, use_super: bool) -> void:
	if phase != Phase.PLAYING or player.is_dead():
		return
	var weapon: Dictionary = player.kit["super"] if use_super else player.kit.weapon
	if stick_value.length() >= TAP_THRESHOLD:
		var dir := Vector3(stick_value.x, 0, stick_value.y)
		_fire_player(weapon, dir, stick_value.length() * weapon.range)
	else:
		_auto_aim_fire(weapon, use_super)

func _auto_aim_fire(weapon: Dictionary, use_super: bool) -> void:
	var enemy := nearest_visible_enemy(player, weapon.range * 1.1)
	if enemy:
		var v := enemy.global_position - player.global_position
		_fire_player(weapon, v, v.length())
	elif not use_super:
		_fire_player(weapon, player.facing, weapon.range)
	# A tapped Super with no target keeps its charge instead of firing blind;
	# drag from the button to aim it manually.

func _update_concealment() -> void:
	if player == null:
		return
	for f in fighters:
		var in_bush := arena.tile_at(f.global_position) == "b"
		if f == player:
			f.set_concealed(in_bush, true)
		else:
			var near := f.global_position.distance_to(player.global_position) < Kits.TILE * 2.0
			f.set_concealed(in_bush and not near, false)

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# Translate only — rotation is fixed at match start. Re-aiming at the
	# player every frame yaws/rolls the world whenever the camera lags a
	# strafing player.
	var target := player.global_position + CAMERA_OFFSET
	cam.global_position = cam.global_position.lerp(target, 0.15)

func _update_status() -> void:
	if player == null:
		return
	super_btn.set_charge(player.super_charge)
	status_label.text = "%s   HP %d/%d   ammo %.1f   cubes %d" % [
		player.kit.name, player.health, player.max_health, player.ammo, player.cubes]

func _shot_check() -> void:
	if _shot_times.is_empty() or _shot_prefix == "":
		return
	if now >= _shot_times[0]:
		var t: float = _shot_times.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [_shot_prefix, int(t)])
		if _shot_times.is_empty():
			get_tree().quit()
