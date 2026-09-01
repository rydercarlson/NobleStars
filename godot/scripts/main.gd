extends Node3D
## Match controller: spawning, phases, combat resolution, camera, HUD.
## Debug env hooks (see CLAUDE.md): NS3_KIT, NS3_AUTOFIRE, NS3_AUTOWALK,
## NS3_GODMODE, NS3_SHOTS="prefix:t1,t2,..." (screenshots at match times).

enum Phase { COUNTDOWN, PLAYING, ENDED }

const BOX_HEALTH := 900   # loot box hit points; also the bar's full width

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
var results_award: Label
var aim_mesh: MeshInstance3D

# Orthographic, like Brawl Stars: wall verticals project straight up-down
# everywhere on screen and nothing shears as the camera pans. ORTHO_SIZE is
# the vertical view extent in meters (~12 tiles across at 16:9).
# Pitch ~57° — oblique enough to show more of the fighters while preserving
# the clear top-down read of the arena.
const CAMERA_OFFSET := Vector3(0, 14.0, 9.2)
const CAMERA_ORTHO_SIZE := 12.9
const TAP_THRESHOLD := 0.3

# Debug hooks
var god_mode := OS.get_environment("NS3_GODMODE") != ""
var auto_fire := float(OS.get_environment("NS3_AUTOFIRE")) if OS.get_environment("NS3_AUTOFIRE") != "" else 0.0
var _last_auto_fire := 0.0
var _shot_prefix := ""
var _shot_times: Array[float] = []

# NS3_SIM=<n>: balance sim — every fighter (the player slot included) is
# bot-driven with a random kit, matches restart back-to-back at 10x speed,
# and after n matches a per-kit results table prints to stdout, then quit.
# Run headless: NS3_SIM=40 NS3_KIT=nova Godot --path godot --headless
var sim_matches := int(OS.get_environment("NS3_SIM")) if OS.get_environment("NS3_SIM") != "" else 0
var sim_active := sim_matches > 0
var sim_stats := {}   # kit name -> {spawns, wins, kills, damage, placement_sum}
var _sim_done := 0

# Wifi play (see net_play.gd): host-authoritative. The host runs the sim
# exactly like single-player; clients send stick input up and render the
# snapshots/events the host broadcasts. `authoritative` is false only on
# clients — it gates every mutation (damage, loot, walls) so client-side
# projectiles and melee arcs stay purely visual.
const NET_WAIT_TIMEOUT := 6.0     # start anyway if a client stalls loading
var net_active := false
var net_host := false
var authoritative := true
var net_fighters: Array = []      # roster index -> Fighter (freed after death)
var _net_roster: Array = []
var _my_kit_name := ""            # for trophies after `player` is freed
var _match_ready := false         # roster applied, arena built
var _match_seq := 0               # dedupes re-sent _net_start RPCs
var _net_seen_seq := 0
var _net_ready_peers: Dictionary = {}
var _peer_inputs: Dictionary = {}     # peer_id -> {move, face}
var _puppet_targets: Dictionary = {}  # roster idx -> {pos, rot}
var _next_ready_send := 0.0
var _cube_seq := 0
var _snap_tick := 0

func _ready() -> void:
	SaveGame.ensure_loaded()   # NS3_KIT runs skip the menu, so load here too
	net_active = Net.active
	net_host = net_active and multiplayer.is_server()
	authoritative = not net_active or net_host
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
	# The camera is driven from _process, so physics interpolation only makes
	# the rendered view lag the transform unproject_position sees (bar buzz).
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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

	if sim_active:
		# NS3_SIM_SPEED overrides the 10x default. Turn it down when a result
		# looks like a physics artifact rather than balance: fast-moving Area3D
		# projectiles get fewer overlap ticks per metre the higher this goes, so
		# comparing hits/atk at 10x against 2x separates "the kit misses" from
		# "the sim never registered the hit".
		var speed_env := OS.get_environment("NS3_SIM_SPEED")
		Engine.time_scale = float(speed_env) if speed_env != "" else 10.0
		Engine.max_physics_steps_per_frame = 64

	if net_host:
		print("[net] match scene up as host")
		multiplayer.peer_disconnected.connect(_on_net_peer_left)
		center_label.text = "WAITING…"
	elif net_active:
		print("[net] match scene up as client")
		Net.host_disconnected.connect(_on_net_host_lost)
		center_label.text = "CONNECTING…"
	else:
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

	results_award = Label.new()
	results_award.add_theme_font_size_override("font_size", 26)
	results_award.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	results_award.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(results_award)

	var again := Button.new()
	again.text = "  PLAY AGAIN  "
	again.add_theme_font_size_override("font_size", 30)
	again.visible = authoritative   # net clients wait for the host's rematch
	again.pressed.connect(func() -> void:
		results.visible = false
		if net_host:
			_net_host_start()
		else:
			start_match())
	vbox.add_child(again)

	var menu := Button.new()
	menu.text = "  LOBBY  "
	menu.add_theme_font_size_override("font_size", 22)
	menu.pressed.connect(func() -> void:
		Net.leave()
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
		if c is Arena or c is GasRing or c is Fighter or c is Projectile or c is Lob or c is Boomerang \
				or c is HackySack or c is OrbitingSack:
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

	# Mode hook: only Showdown exists today; branch on Session.mode when new
	# modes land (the menu only lets "showdown" through for now).
	var _mode: String = Session.mode

	var player_kit: Dictionary = Session.kit if not Session.kit.is_empty() else Kits.nova()
	if sim_active:
		player_kit = Kits.all().pick_random()
	player = _spawn_fighter(player_kit, spawns.pop_front(), not sim_active)
	player.display_name = "%s 0" % player_kit.name if sim_active else "You"
	if sim_active:
		brains.append(BotBrain.new(player))
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
	if sim_active:
		for f in fighters:
			_sim_kit(f.kit.name).spawns += 1
		phase = Phase.PLAYING   # no countdown between sim matches
		center_label.text = ""
		gas = GasRing.new()
		add_child(gas)
		gas.start(now, arena.columns)
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

func _spawn_lootbox(pos: Vector3, box_name := "") -> void:
	var body := StaticBody3D.new()
	if box_name != "":   # stable id for net replication
		body.name = box_name
	body.collision_layer = 1 << 5
	body.position = pos + Vector3(0, 0.5, 0)
	body.set_meta("health", BOX_HEALTH)
	body.set_meta("max_health", BOX_HEALTH)   # fighter_bars draws the bar from these
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

func _spawn_cube(pos: Vector3, cube_id := -1) -> void:
	var area := Area3D.new()
	if cube_id >= 0:
		area.name = "Cube%d" % cube_id
	area.collision_layer = 1 << 4
	area.collision_mask = 1 << 2
	area.position = pos + Vector3(0, 0.5, 0)
	area.add_to_group("cube")
	# Meshy power-cube token, spinning Brawl-style about Y with a soft bob.
	var m: Node3D = (load("res://assets/power_cube.glb") as PackedScene).instantiate()
	m.scale = Vector3.ONE * 0.3
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var mat = mesh.surface_get_material(si)
			if mat is BaseMaterial3D:
				mat.metallic = 0.0
	area.add_child(m)
	var spin := area.create_tween().set_loops()
	spin.tween_property(m, "rotation:y", TAU, 2.6).as_relative()
	var bob := area.create_tween().set_loops()
	bob.tween_property(m, "position:y", 0.09, 1.1).as_relative() \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(m, "position:y", -0.09, 1.1).as_relative() \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	area.add_child(col)
	# Pickup resolves host-side only; clients just render until told it's gone.
	if authoritative:
		area.body_entered.connect(func(body: Node3D) -> void:
			if body is Fighter and not body.is_dead() and is_instance_valid(area):
				body.collect_cube()
				if net_host:
					_net_cube_gone.rpc(String(area.name), net_fighters.find(body))
				area.queue_free())
	add_child(area)

# MARK: combat

## Owner references on in-flight projectiles can outlive the fighter; typed
## params reject freed instances, so sanitize them to null before deal_damage.
func _live(f) -> Fighter:
	return f if is_instance_valid(f) else null

func deal_damage(amount: int, target: Fighter, attacker: Fighter,
		kb_dir := Vector3.ZERO, kb_strength := 0.0) -> void:
	if not authoritative:   # client-side attacks are visual only
		return
	if target.is_dead():
		return
	if god_mode and target == player:
		return
	target.take_damage(amount, now)
	if kb_strength > 0.0:
		target.receive_knockback(kb_dir, kb_strength)
	if attacker != null:
		attacker.charge_super(amount)
		if sim_active:
			_sim_kit(attacker.kit.name).damage += amount
			_sim_kit(attacker.kit.name).hits += 1
	if target.is_dead():
		if sim_active and attacker != null:
			_sim_kit(attacker.kit.name).kills += 1
		_eliminate(target, attacker.display_name if attacker != null else "")

func perform_attack(f: Fighter, weapon: Dictionary, dir: Vector3, dist: float) -> void:
	if f.is_disconnected(now):
		return
	if sim_active:
		_sim_kit(f.kit.name).attacks += 1
	var is_super: bool = weapon == f.kit.get("super", {})
	if net_host:   # echo to clients so they see the shot/swing
		var idx := net_fighters.find(f)
		if idx >= 0:
			_net_attack.rpc(idx, is_super, dir, dist)
	var unit := Vector3(dir.x, 0, dir.z).normalized()
	f.face_direction(unit)
	f.play_attack_animation(now, is_super)
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
				proj.on_sweep_hit = _on_projectile_hit
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
			# Swipes alternate direction so the combo reads as distinct hits.
			# No anim re-trigger: the attack clip covers the whole combo.
			# Captured by id, not reference: the fighter can be freed before
			# the timer fires, and a freed lambda capture logs engine errors.
			var fid := f.get_instance_id()
			for i in range(1, int(weapon.pellets)):
				var sweep := -1.0 if i % 2 == 1 else 1.0
				get_tree().create_timer(0.22 * i).timeout.connect(func() -> void:
					var fx := instance_from_id(fid)
					if phase == Phase.PLAYING and fx is Fighter and not fx.is_dead():
						_melee(fx, weapon, fx.facing, sweep))
		Kits.Style.SHOCKWAVE:
			# `delay` holds the wave until the animation's impact frame, so the
			# hit reads as the stomp landing rather than arriving ahead of it.
			# Captured by id: the fighter can be freed before the timer fires.
			var delay: float = weapon.get("delay", 0.0)
			if delay > 0.0:
				var sid := f.get_instance_id()
				var swipe_dir := unit
				get_tree().create_timer(delay).timeout.connect(func() -> void:
					var fx := instance_from_id(sid)
					if phase == Phase.PLAYING and fx is Fighter and not fx.is_dead():
						_shockwave(fx, weapon, swipe_dir))
			else:
				_shockwave(f, weapon, unit)
		Kits.Style.DASH:
			# Clients skip the dash state machine — the host simulates it and
			# the snapshot stream moves the fighter.
			if authoritative:
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
			f.set_held_item_visible(false)   # the staff is in the air now
		Kits.Style.JUMP_SMASH:
			f.begin_leap(weapon, unit, dist)
		Kits.Style.BUTTONS:
			_spawn_button_burst(f, weapon, unit)
		Kits.Style.DISCONNECT:
			var throw_dist: float = clamp(dist, Kits.TILE * 1.5, weapon.range)
			var controller := Lob.new()
			controller.weapon = weapon
			controller.damage = int(weapon.damage * f.damage_multiplier())
			controller.owner_fighter = f
			controller.start_pos = f.global_position + Vector3(0, 0.5, 0)
			controller.target_pos = f.global_position + unit * throw_dist
			controller.is_controller = true
			controller.on_land = _disconnect_lob_land
			add_child(controller)
		Kits.Style.HACKY_SACK:
			var sack := HackySack.new()
			sack.weapon = weapon
			sack.damage = int(weapon.damage * f.damage_multiplier())
			sack.owner_fighter = f
			sack.direction = unit
			sack.bounces_left = int(weapon.bounces)
			sack.position = f.global_position + unit * 0.8 + Vector3(0, 0.8, 0)
			sack.on_body_hit = _on_hacky_sack_hit
			sack.on_pickup = _recover_hacky_sack
			add_child(sack)
		Kits.Style.ORBIT_SACK:
			var orbit := OrbitingSack.new()
			orbit.game = self
			orbit.owner_fighter = f
			orbit.weapon = weapon
			orbit.damage = int(weapon.damage * f.damage_multiplier())
			orbit.on_hit = _on_orbiting_sack_hit
			add_child(orbit)

func _spawn_button_burst(f: Fighter, weapon: Dictionary, unit: Vector3) -> void:
	var labels := ["A", "B", "X", "Y", "LB", "RB"]
	var colors := [Color(0.25, 0.9, 0.35), Color(0.95, 0.22, 0.2),
			Color(0.22, 0.55, 1.0), Color(1.0, 0.82, 0.18),
			Color(0.72, 0.38, 0.95), Color(0.2, 0.9, 0.9)]
	# Six quick launches still read as a button mash rather than one shotgun
	# blast, but the burst has to stay SHORT. Every button is launched along the
	# one `unit` captured when the trigger was pulled, so a button leaving late
	# is aimed where the target was that much earlier: at 0.06s apart the last
	# one flew 0.30s stale, which is ~1m of drift on a moving fighter — well
	# past the ~0.65m you can actually hit. 0.035s keeps the whole burst inside
	# 0.175s. Capture the fighter by ID: it may be freed before a delayed button
	# is due to launch.
	var fighter_id := f.get_instance_id()
	for i in labels.size():
		if i == 0:
			_launch_button_shot(fighter_id, weapon, unit, labels[i], colors[i], i)
		else:
			get_tree().create_timer(0.035 * i).timeout.connect(_launch_button_shot.bind(
					fighter_id, weapon, unit, labels[i], colors[i], i))

func _launch_button_shot(fighter_id: int, weapon: Dictionary, unit: Vector3,
		label: String, color: Color, index: int) -> void:
	var fighter := instance_from_id(fighter_id)
	if fighter is Fighter and is_instance_valid(fighter) and not fighter.is_dead():
		_spawn_button_shot(fighter, weapon, unit, label, color, index)

func _spawn_button_shot(f: Fighter, weapon: Dictionary, unit: Vector3,
		label: String, color: Color, index: int) -> void:
	var base := atan2(unit.x, unit.z)
	# Left, middle, right, middle, left, right reads as a quick controller
	# button mash instead of a left-to-right sweep. It remains deterministic
	# so every network client sees the same burst.
	var offsets := [-0.45, 0.0, 0.45, 0.0, -0.25, 0.25]
	var t: float = offsets[index % offsets.size()]
	var angle := base + deg_to_rad(float(weapon.spread_deg)) * t
	var shot_dir := Vector3(sin(angle), 0, cos(angle))
	var proj := Projectile.new()
	proj.weapon = weapon
	proj.damage = int(weapon.damage * f.damage_multiplier())
	proj.owner_fighter = f
	proj.direction = shot_dir
	proj.button_text = label
	proj.button_color = color
	# Every button leaves the center, then takes its own compact cone lane.
	proj.position = f.global_position + unit * 0.8 + Vector3(0, 1.0, 0)
	proj.origin = proj.position
	proj.body_entered.connect(_on_projectile_hit.bind(proj))
	proj.on_sweep_hit = _on_projectile_hit
	add_child(proj)

func _on_projectile_hit(body: Node3D, proj: Projectile) -> void:
	if not is_instance_valid(proj):
		return
	if body is Fighter:
		if body == proj.owner_fighter or body.is_dead() or proj.already_hit.has(body):
			return
		proj.already_hit.append(body)
		deal_damage(proj.damage, body, _live(proj.owner_fighter), proj.direction, proj.weapon.knockback)
		if not proj.weapon.pierces:
			proj.queue_free()
	elif body.is_in_group("lootbox"):
		_damage_lootbox(body, proj.damage)
		proj.queue_free()
	elif body.is_in_group("breakable") and proj.weapon.destroys_walls:
		# Shell plows through. Host decides; clients break it on the RPC.
		if authoritative:
			if net_host:
				_net_wall_broken.rpc(String(body.name))
			body.queue_free()
	elif not body.is_in_group("water"):
		proj.queue_free()

## Leon's Disconnect lands in two parts: a one-off burst (damage, knockback and
## the full silence on everyone caught in it) and the field it leaves behind,
## which re-silences whoever is standing in it until it expires.
func _disconnect_lob_land(lob: Lob) -> void:
	if not is_instance_valid(lob):
		return
	var center := lob.target_pos
	_spawn_shockwave(center, lob.weapon, Color(1.0, 0.2, 0.85))
	for target in fighters:
		if target == lob.owner_fighter or target.is_dead():
			continue
		var delta := target.global_position - center
		delta.y = 0
		if delta.length() <= lob.weapon.aoe + 0.5:
			deal_damage(lob.damage, target, _live(lob.owner_fighter), delta.normalized(), lob.weapon.knockback)
			if authoritative:
				target.apply_disconnect(now, float(lob.weapon.disconnect_seconds))
	for box in get_tree().get_nodes_in_group("lootbox"):
		var delta: Vector3 = box.global_position - center
		delta.y = 0
		if delta.length() <= lob.weapon.aoe + 0.7:
			_damage_lootbox(box, lob.damage)
	var zone_seconds: float = lob.weapon.get("zone_seconds", 0.0)
	if zone_seconds > 0.0:
		var zone := DisconnectZone.new()
		zone.radius = lob.weapon.aoe
		zone.duration = zone_seconds
		zone.tint = Color(1.0, 0.2, 0.85)
		zone.owner_fighter = _live(lob.owner_fighter)
		zone.position = center
		add_child(zone)

func _on_hacky_sack_hit(body: Node3D, sack: HackySack) -> void:
	if not is_instance_valid(sack) or body == sack.owner_fighter or not sack.can_bounce_from(body):
		return
	if body is Fighter:
		if body.is_dead():
			return
		deal_damage(sack.damage, body, _live(sack.owner_fighter), sack.direction, sack.weapon.knockback)
	elif body.is_in_group("lootbox"):
		_damage_lootbox(body, sack.damage)
	elif body.is_in_group("water"):
		return
	sack.bounce_from(body.global_position, sack.last_hit_normal)

func _recover_hacky_sack(sack: HackySack) -> void:
	if not is_instance_valid(sack) or not is_instance_valid(sack.owner_fighter):
		return
	var owner: Fighter = sack.owner_fighter
	if owner.ammo < Kits.MAX_AMMO:
		owner.ammo = minf(Kits.MAX_AMMO, owner.ammo + 1.0)
		owner._popup("+1 AMMO", Color(0.3, 0.95, 0.85))
	else:
		var heal := mini(480, owner.max_health - owner.health)   # ~10% of base health
		owner.health += heal
		owner._popup("+%d HP" % heal, Color(0.35, 1.0, 0.5))

func _on_orbiting_sack_hit(target: Fighter, orbit: OrbitingSack) -> void:
	if not is_instance_valid(orbit) or target.is_dead():
		return
	var push := target.global_position - orbit.owner_fighter.global_position
	push.y = 0
	deal_damage(orbit.damage, target, _live(orbit.owner_fighter), push.normalized(), orbit.weapon.knockback)

func _on_boomerang_hit(body: Node3D, boom: Boomerang) -> void:
	if not is_instance_valid(boom):
		return
	if body is Fighter:
		if body == boom.owner_fighter or body.is_dead() or boom.already_hit.has(body):
			return
		boom.already_hit.append(body)
		deal_damage(boom.damage, body, _live(boom.owner_fighter), boom.travel_dir(), boom.weapon.knockback)
	elif body.is_in_group("lootbox") and not boom.already_hit.has(body):
		boom.already_hit.append(body)
		_damage_lootbox(body, boom.damage)

func _on_lob_land(lob: Lob) -> void:
	var center: Vector3 = lob.target_pos
	# Tony's weapon has no directional spread, but its landing damage is a full
	# circle. Flash that exact AOE as a bright tennis-ball-colored splash.
	var splash_weapon: Dictionary = lob.weapon.duplicate()
	splash_weapon.spread_deg = 360.0
	_spawn_shockwave(center, splash_weapon, Color(0.82, 1.0, 0.22))
	for f in fighters:
		if not is_instance_valid(f) or f == lob.owner_fighter or f.is_dead():
			continue
		if Vector2(f.global_position.x - center.x, f.global_position.z - center.z).length() <= lob.weapon.aoe + 0.5:
			deal_damage(lob.damage, f, _live(lob.owner_fighter))
	for box in get_tree().get_nodes_in_group("lootbox"):
		if box.global_position.distance_to(center) <= lob.weapon.aoe + 0.7:
			_damage_lootbox(box, lob.damage)

func _spawn_melee_arc(f: Fighter, weapon: Dictionary, unit: Vector3, sweep := 1.0) -> void:
	var s := MeleeSwipe.new()
	s.base_angle = atan2(unit.x, unit.z)
	s.half_angle = deg_to_rad(weapon.spread_deg) / 2.0
	s.reach = weapon.range
	s.tint = f.kit.color.lightened(0.35)
	s.sweep_sign = sweep
	s.position = f.global_position + Vector3(0, 0.2, 0)
	add_child(s)

func _melee(f: Fighter, weapon: Dictionary, unit: Vector3, sweep := 1.0) -> void:
	_spawn_melee_arc(f, weapon, unit, sweep)
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

func _spawn_shockwave(center: Vector3, weapon: Dictionary, tint: Color, direction := Vector3.ZERO) -> void:
	var wave := Shockwave.new()
	wave.radius = weapon.aoe if weapon.aoe > 0.0 else weapon.range
	wave.tint = tint
	wave.direction = direction
	wave.arc_degrees = weapon.spread_deg
	wave.position = center + Vector3(0, 0.05, 0)
	add_child(wave)

## Kovacs' clap is a short, widening cone: it looks like a shockwave but uses
## the same reliable visibility and hit resolution rules as other melee hits.
func _shockwave(f: Fighter, weapon: Dictionary, unit: Vector3) -> void:
	_spawn_shockwave(f.global_position, weapon, f.kit.color.lightened(0.3), unit)
	var dmg := int(weapon.damage * f.damage_multiplier())
	var half := deg_to_rad(weapon.spread_deg) / 2.0
	for target in fighters:
		if target == f or target.is_dead():
			continue
		var v := target.global_position - f.global_position
		v.y = 0
		if v.length() > weapon.range + 0.5 or v.length() < 0.01:
			continue
		if abs(unit.signed_angle_to(v.normalized(), Vector3.UP)) <= half \
				and has_line_of_sight(f.global_position, target.global_position):
			deal_damage(dmg, target, f, unit, weapon.knockback)
	for box in get_tree().get_nodes_in_group("lootbox"):
		var v: Vector3 = box.global_position - f.global_position
		v.y = 0
		if v.length() <= weapon.range + 0.7 and v.length() > 0.01 \
				and abs(unit.signed_angle_to(v.normalized(), Vector3.UP)) <= half:
			_damage_lootbox(box, dmg)

func _ground_smash(f: Fighter, weapon: Dictionary, center: Vector3) -> void:
	_spawn_shockwave(center, weapon, f.kit.color.lightened(0.45))
	var dmg := int(weapon.damage * f.damage_multiplier())
	for target in fighters:
		if target == f or target.is_dead():
			continue
		var delta := target.global_position - center
		delta.y = 0
		if delta.length() <= weapon.aoe + 0.5:
			deal_damage(dmg, target, f, delta.normalized(), weapon.knockback)
	for box in get_tree().get_nodes_in_group("lootbox"):
		var delta: Vector3 = box.global_position - center
		delta.y = 0
		if delta.length() <= weapon.aoe + 0.7:
			_damage_lootbox(box, dmg)

func _damage_lootbox(box: Node, amount: int) -> void:
	if not authoritative or not is_instance_valid(box):
		return
	var hp: int = box.get_meta("health") - amount
	box.set_meta("health", hp)
	if hp > 0 and net_host:
		_net_box_damaged.rpc(String(box.name), hp)   # keeps client bars honest
	if hp <= 0:
		var pos: Vector3 = box.global_position - Vector3(0, 0.5, 0)
		_spawn_cube(pos, _cube_seq)
		if net_host:
			_net_box_broken.rpc(String(box.name), _cube_seq, pos)
		_cube_seq += 1
		box.queue_free()

## Standing in a Disconnect field keeps the silence topped up to a short tail,
## so it lifts a beat after stepping out. apply_disconnect only ever extends,
## so this never cuts short the longer silence from the landing burst.
func _update_disconnect_zones() -> void:
	if not authoritative:
		return   # zones are visual on clients; the host owns the silence
	for zone in get_tree().get_nodes_in_group("disconnect_zone"):
		# The field outlives its caster, so the owner reference can be stale.
		var caster := _live(zone.owner_fighter)
		for f in fighters:
			if f == caster or f.is_dead():
				continue
			if zone.contains(f.global_position):
				f.apply_disconnect(now, DisconnectZone.TAIL)

func _update_dashes(delta: float) -> void:
	for f in fighters:
		if not f.is_dashing():
			continue
		var d: Dictionary = f.dash
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

func _update_leaps(delta: float) -> void:
	for f in fighters:
		if not f.is_leaping():
			continue
		var leap: Dictionary = f.leap
		leap.elapsed += delta
		var p: float = clampf(leap.elapsed / leap.duration, 0.0, 1.0)
		var start: Vector3 = leap.start
		var landing: Vector3 = leap.landing
		f.global_position = start.lerp(landing, p)
		f.global_position.y = sin(PI * p) * 2.0
		if p >= 1.0:
			f.global_position.y = 0.0
			f.leap = {}
			_ground_smash(f, leap.weapon, f.global_position)

# MARK: senses

func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(
		from + Vector3(0, 1, 0), to + Vector3(0, 1, 0), 1)  # walls layer only
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()

## through_walls: lobbed attacks arc over walls, so targeting skips the wall
## line-of-sight check. Bushes still conceal either way.
func can_see(viewer: Fighter, target: Fighter, through_walls := false) -> bool:
	var dist := viewer.global_position.distance_to(target.global_position)
	if arena.tile_at(target.global_position) == "b" and dist > Kits.TILE * 2.0:
		return false
	return through_walls or has_line_of_sight(viewer.global_position, target.global_position)

func nearest_visible_enemy(viewer: Fighter, within: float, through_walls := false) -> Fighter:
	var best: Fighter = null
	var best_d := INF
	for f in fighters:
		if f == viewer or f.is_dead():
			continue
		var d := viewer.global_position.distance_to(f.global_position)
		if d < within and d < best_d and can_see(viewer, f, through_walls):
			best = f
			best_d = d
	return best

## Loot boxes are aimable like fighters — same reach and wall check. Bushes
## don't hide them: a box you can see is a box you can shoot.
func nearest_visible_lootbox(viewer: Fighter, within: float,
		through_walls := false) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for box in get_tree().get_nodes_in_group("lootbox"):
		if not is_instance_valid(box):
			continue
		var d: float = viewer.global_position.distance_to(box.global_position)
		if d < within and d < best_d and (through_walls
				or has_line_of_sight(viewer.global_position, box.global_position)):
			best = box
			best_d = d
	return best

## Lobbed attacks arc over walls, so they target through them.
func _lobbed(weapon: Dictionary) -> bool:
	var style := int(weapon.style)
	return style == Kits.Style.LOB or style == Kits.Style.DISCONNECT

## What a tap fires at: the nearest visible enemy, or a loot box when no enemy
## is in range, so tapping in a quiet corner opens boxes instead of firing at
## nothing. Reach is 1.1x the weapon's range, matching the enemy check.
func auto_aim_target(viewer: Fighter, weapon: Dictionary) -> Node3D:
	var reach: float = weapon.range * 1.1
	var enemy := nearest_visible_enemy(viewer, reach, _lobbed(weapon))
	if enemy:
		return enemy
	return nearest_visible_lootbox(viewer, reach, _lobbed(weapon))

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

func gas_depth(pos: Vector3) -> float:
	return gas.depth_inside(pos) if gas else INF

func gas_safe_center() -> Vector3:
	return gas.safe_center() if gas else Vector3(arena.map_size() / 2, 0, arena.map_size() / 2)

# MARK: match flow

func _eliminate(f: Fighter, killer: String, left_game := false) -> void:
	var rank := fighters.size()
	if net_host:
		_net_eliminate.rpc(net_fighters.find(f), killer, rank, left_game)
	fighters.erase(f)
	for b in brains.duplicate():
		if b.fighter == f:
			brains.erase(b)
	f.die()
	_update_players_label()
	feed_label.text = _elim_feed_text(f.display_name, killer, left_game)
	if sim_active:
		if phase == Phase.PLAYING:   # post-match stragglers don't score
			_sim_kit(f.kit.name).placement_sum += rank
			if fighters.size() <= 1:
				_sim_match_end()
		return
	if net_active:
		# The host's own death doesn't stop the match — the sim keeps running
		# until one fighter remains (matches only exist host-side).
		if f == player:
			player = null
			_net_show_results(rank, false)
		if fighters.size() <= 1:
			_net_finish()
		return
	if f == player:
		_end_match(rank, false)
	elif fighters.size() == 1 and fighters[0] == player:
		_end_match(1, true)

func _elim_feed_text(who: String, killer: String, left_game: bool) -> String:
	if left_game:
		return "%s left the game" % who
	if killer != "":
		return "%s eliminated %s" % [killer, who]
	return "%s died in the gas" % who

func _end_match(rank: int, victory: bool) -> void:
	phase = Phase.ENDED
	center_label.text = ""
	move_stick.release()
	aim_stick.release()
	super_stick.release()
	results_title.text = ("VICTORY!" if victory else "DEFEATED") + "\nYou placed #%d of 10" % rank
	results_title.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.2) if victory else Color(0.95, 0.4, 0.35))
	var award: Dictionary = SaveGame.award_match(player.kit.name, rank)
	results_award.text = "TROPHIES %+d      COINS +%d" % [award.trophies, award.coins]
	results.visible = true

func _update_players_label() -> void:
	players_label.text = "%d LEFT" % fighters.size()

# MARK: balance sim (NS3_SIM)

func _sim_kit(kit_name: String) -> Dictionary:
	if not sim_stats.has(kit_name):
		sim_stats[kit_name] = {"spawns": 0, "wins": 0, "kills": 0,
				"damage": 0, "placement_sum": 0, "attacks": 0, "hits": 0}
	return sim_stats[kit_name]

func _sim_match_end() -> void:
	phase = Phase.ENDED
	if fighters.size() == 1:   # can be 0 if the gas closes on the last two
		var w: Fighter = fighters[0]
		_sim_kit(w.kit.name).wins += 1
		_sim_kit(w.kit.name).placement_sum += 1
		print("[sim] match %d/%d: %s wins" % [_sim_done + 1, sim_matches, w.display_name])
	else:
		print("[sim] match %d/%d: gas closed, no survivor" % [_sim_done + 1, sim_matches])
	_sim_done += 1
	if _sim_done >= sim_matches:
		_sim_report()
		get_tree().quit()
	else:
		# start_match tears down the nodes this elimination is iterating over.
		call_deferred("start_match")

func _sim_report() -> void:
	print("\n[sim] results over %d matches:" % _sim_done)
	# atk/spawn and hits/atk separate "does this kit get to shoot" from "does the
	# shot connect": a multi-projectile kit should land close to its pellet count
	# per trigger pull, and anything near 1.0 is missing with most of its burst.
	print("%-8s %7s %5s %6s %9s %7s %10s %9s %8s %8s" \
			% ["kit", "spawns", "wins", "win%", "avg place", "kills", "dmg/spawn",
				"atk/spawn", "hits/atk", "dmg/atk"])
	var names := sim_stats.keys()
	names.sort()
	for n in names:
		var s: Dictionary = sim_stats[n]
		var spawns: int = max(1, s.spawns)
		var attacks: int = max(1, s.attacks)
		print("%-8s %7d %5d %5.1f%% %9.2f %7.2f %10.0f %9.2f %8.2f %8.0f" % [n, s.spawns, s.wins,
				100.0 * s.wins / spawns, float(s.placement_sum) / spawns,
				float(s.kills) / spawns, float(s.damage) / spawns,
				float(s.attacks) / spawns, float(s.hits) / attacks,
				float(s.damage) / attacks])

# MARK: loop

func _physics_process(delta: float) -> void:
	now += delta
	if net_active and not _match_ready:
		_net_prestart_tick()
		_shot_check()
		return
	if net_active and not net_host:
		_client_tick(delta)
	else:
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
					if net_host:
						_net_host_start()
					else:
						start_match()

	for f in fighters:
		f.update_animation(now)
	_update_aim_indicator()
	_update_concealment()
	_update_status()
	_shot_check()
	if net_host and _match_ready:
		_snap_tick += 1
		if _snap_tick % 2 == 0:   # 30Hz is plenty on LAN; clients interpolate
			_net_send_snapshot()

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
	var style := int(weapon.style)
	var targeted := style == Kits.Style.LOB or style == Kits.Style.JUMP_SMASH \
			or style == Kits.Style.DISCONNECT
	var orbiting := style == Kits.Style.ORBIT_SACK
	var bouncing := style == Kits.Style.HACKY_SACK
	var cone := style == Kits.Style.MELEE or style == Kits.Style.SHOCKWAVE \
			or style == Kits.Style.BUTTONS \
			or (style == Kits.Style.PELLETS and int(weapon.pellets) > 1 \
					and float(weapon.spread_deg) > 0.0)
	var target_dist: float = clamp(stick.value.length() * weapon.range,
			Kits.TILE if style == Kits.Style.JUMP_SMASH else Kits.TILE * 1.5, weapon.range)

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(color)
	if targeted or orbiting:
		# Targeted attacks use an impact-zone marker rather than a misleading
		# cone. Orbit attacks show the area around the fighter instead.
		var center := origin if orbiting else origin + dir * target_dist
		var radius: float = weapon.range if orbiting else weapon.aoe
		for i in 24:
			var a0 := TAU * i / 24.0
			var a1 := TAU * (i + 1) / 24.0
			im.surface_add_vertex(center)
			im.surface_add_vertex(center + Vector3(cos(a0), 0, sin(a0)) * radius)
			im.surface_add_vertex(center + Vector3(cos(a1), 0, sin(a1)) * radius)
	elif bouncing:
		for segment in _aim_bounce_segments(origin, dir, float(weapon.range), int(weapon.bounces)):
			_aim_add_segment(im, segment[0], segment[1], maxf(float(weapon.radius), 0.16), color)
	elif cone:
		# Cone matching the attack's spread and range.
		var half := deg_to_rad(float(weapon.spread_deg)) / 2.0
		var base := atan2(dir.x, dir.z)
		var steps := 12
		for i in steps:
			var a0 := base - half + 2.0 * half * i / steps
			var a1 := base - half + 2.0 * half * (i + 1) / steps
			im.surface_add_vertex(origin)
			im.surface_add_vertex(origin + Vector3(sin(a0), 0, cos(a0)) * weapon.range)
			im.surface_add_vertex(origin + Vector3(sin(a1), 0, cos(a1)) * weapon.range)
	else:
		# Single projectiles, dashes, and boomerangs occupy a straight lane.
		_aim_add_segment(im, origin, origin + dir * float(weapon.range),
				maxf(float(weapon.radius), 0.16), color)
	im.surface_end()

	if targeted:
		# A trajectory line makes it clear that this is a destination, not a
		# front-facing attack. Kovacs' lower arc matches his actual jump.
		var start := player.global_position + Vector3(0, 0.5, 0)
		var target := player.global_position + dir * target_dist
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		im.surface_set_color(Color(color.r, color.g, color.b, 0.85))
		var arc_steps := 20
		var arc_height := 2.0 if style == Kits.Style.JUMP_SMASH else 3.0
		for i in arc_steps + 1:
			var t := float(i) / arc_steps
			var flat := start.lerp(target, t)
			var height := 4.0 * arc_height * t * (1.0 - t)
			im.surface_add_vertex(flat + Vector3(0, height + 0.3, 0))
		im.surface_end()

func _aim_add_segment(im: ImmediateMesh, from: Vector3, to: Vector3,
		half_width: float, color: Color) -> void:
	var travel := to - from
	travel.y = 0.0
	if travel.length_squared() < 0.001:
		return
	var side := Vector3(travel.z, 0, -travel.x).normalized() * half_width
	im.surface_set_color(color)
	im.surface_add_vertex(from - side)
	im.surface_add_vertex(to - side)
	im.surface_add_vertex(to + side)
	im.surface_add_vertex(from - side)
	im.surface_add_vertex(to + side)
	im.surface_add_vertex(from + side)

func _aim_bounce_segments(origin: Vector3, direction: Vector3,
		total_distance: float, bounces: int) -> Array:
	var segments: Array = []
	var start := origin + Vector3(0, 0.05, 0)
	var heading := direction.normalized()
	var remaining := total_distance
	for _bounce in bounces + 1:
		var finish := start + heading * remaining
		var query := PhysicsRayQueryParameters3D.create(start, finish, 1) # walls only
		query.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			segments.append([start, finish])
			break
		var impact: Vector3 = hit.position
		segments.append([start, impact])
		remaining -= start.distance_to(impact)
		if remaining <= 0.05:
			break
		heading = HackySack.reflected_direction(heading, hit.normal)
		start = impact + heading * 0.05
	return segments

func _run_playing(delta: float) -> void:
	# In sim mode the player slot is brain-driven; skip input. After it dies
	# the node is freed while the match runs on, hence the validity guards.
	if not sim_active and is_instance_valid(player) and not player.is_dead():
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

	if net_host:
		# Remote players: drive their fighters from the latest input RPC.
		for i in net_fighters.size():
			var f = net_fighters[i]
			if f == null or not is_instance_valid(f) or f.is_dead() or f == player:
				continue
			var peer := int(f.get_meta("peer", 0))
			if peer <= 1:
				continue   # bots (0) belong to brains; 1 is the host itself
			var inp: Dictionary = _peer_inputs.get(peer, {})
			f.apply_movement(inp.get("move", Vector3.ZERO))
			var face: Vector3 = inp.get("face", Vector3.ZERO)
			if face.length() > 0.1:
				f.face_direction(face)

	for b in brains:
		var d := b.decide(now, self)
		b.fighter.apply_movement(d.move)
		if d.fire_dir != null and not b.fighter.is_dashing() and not b.fighter.is_disconnected(now):
			if d.use_super and b.fighter.consume_super():
				perform_attack(b.fighter, b.fighter.kit["super"], d.fire_dir, d.fire_dist)
			elif not d.use_super and b.fighter.consume_ammo():
				perform_attack(b.fighter, b.fighter.kit.weapon, d.fire_dir, d.fire_dist)

	_update_dashes(delta)
	_update_leaps(delta)
	_update_disconnect_zones()
	for f in fighters:
		f.tick(delta, now)

	if gas:
		var vulnerable := fighters.filter(func(f): return not (god_mode and f == player))
		for f in gas.tick(now, vulnerable):
			if f.is_dead():
				_eliminate(f, "")

	if auto_fire > 0.0 and now - _last_auto_fire >= auto_fire \
			and is_instance_valid(player) and not player.is_dead():
		_last_auto_fire = now
		var weapon: Dictionary = player.kit["super"] if player.is_super_ready() else player.kit.weapon
		var target := auto_aim_target(player, weapon)   # boxes included
		var dir := player.facing
		var dist: float = weapon.range
		if target:
			dir = target.global_position - player.global_position
			dist = dir.length()
		_fire_player(weapon, dir, dist)

func _fire_player(weapon: Dictionary, dir: Vector3, dist: float) -> void:
	if phase != Phase.PLAYING or player == null or not is_instance_valid(player) \
			or player.is_dead() or player.is_dashing() or player.is_disconnected(now):
		return
	var use_super: bool = weapon == player.kit["super"]
	if net_active and not net_host:
		# Clients ask the host to fire; the attack echoes back as _net_attack.
		_net_fire.rpc_id(1, use_super, dir, dist)
		return
	if use_super:
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
	# A Super only auto-aims at fighters — burning the charge on a loot box is
	# never what the tap meant.
	var target: Node3D = nearest_visible_enemy(player, weapon.range * 1.1, _lobbed(weapon)) \
			if use_super else auto_aim_target(player, weapon)
	if target:
		var v := target.global_position - player.global_position
		_fire_player(weapon, v, v.length())
	elif not use_super:
		_fire_player(weapon, player.facing, weapon.range)
	# A tapped Super with no target keeps its charge instead of firing blind;
	# drag from the button to aim it manually.

func _update_concealment() -> void:
	if player == null or not is_instance_valid(player):
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
	if player == null or not is_instance_valid(player):
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

# MARK: wifi play
# Host-authoritative replication. The host broadcasts a roster to start,
# 30Hz state snapshots, and reliable events (attacks, eliminations, loot,
# walls); clients send stick input and fire requests. All RPCs live on this
# node — game.tscn's root is "Main" on every peer, so paths line up.

## Pre-match handshake: clients announce their scene is loaded; the host
## starts once everyone is in (or after a timeout so a stall can't hang it).
func _net_prestart_tick() -> void:
	if net_host:
		if _net_all_ready() or now >= NET_WAIT_TIMEOUT:
			_net_host_start()
	elif now >= _next_ready_send:
		_next_ready_send = now + 0.5   # re-send: the host may still be loading
		_net_client_ready.rpc_id(1)

func _net_all_ready() -> bool:
	for id in Net.players:
		if id != 1 and not _net_ready_peers.has(id):
			return false
	return true

## Host: roster = connected players first, bots filling the empty slots, each
## assigned a shuffled spawn index (spawn count comes from the map's S tiles).
func _net_host_start() -> void:
	_match_seq += 1
	var spawn_idx: Array = range(Arena.MAP.count("S"))
	spawn_idx.shuffle()
	var roster: Array = []
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		roster.append({"peer": int(id), "kit": String(p.kit), "fname": String(p.name),
				"spawn": spawn_idx[roster.size()]})
	var bot_n := 1
	while roster.size() < spawn_idx.size():
		var kit: Dictionary = Kits.all().pick_random()
		roster.append({"peer": 0, "kit": String(kit.name), "fname": "%s %d" % [kit.name, bot_n],
				"spawn": spawn_idx[roster.size()]})
		bot_n += 1
	_net_start.rpc(_match_seq, roster)
	_start_from_roster(roster)

## Both sides build the identical match from the host's roster.
func _start_from_roster(roster: Array) -> void:
	_net_roster = roster
	_match_ready = false
	for c in get_children():
		if c is Arena or c is GasRing or c is Fighter or c is Projectile or c is Lob or c is Boomerang \
				or c is HackySack or c is OrbitingSack:
			c.queue_free()
	for c in get_tree().get_nodes_in_group("lootbox") + get_tree().get_nodes_in_group("cube"):
		c.queue_free()
	fighters.clear()
	brains.clear()
	net_fighters.clear()
	_puppet_targets.clear()
	player = null

	arena = Arena.new()
	add_child(arena)
	gas = null
	await get_tree().process_frame   # let arena _ready run

	var my_id := multiplayer.get_unique_id()
	for i in roster.size():
		var e: Dictionary = roster[i]
		var own := int(e.peer) == my_id
		var f := _spawn_fighter(Kits.named(e.kit), arena.spawn_points[int(e.spawn)], own)
		f.name = "F%d" % i
		f.display_name = "You" if own else String(e.fname)
		f.set_meta("peer", int(e.peer))
		net_fighters.append(f)
		if own:
			player = f
			_my_kit_name = String(e.kit)
		elif authoritative and int(e.peer) == 0:
			brains.append(BotBrain.new(f))
	if net_host and player and OS.get_environment("NS3_SUPER") != "":
		player.super_charge = 1.0

	for bi in arena.box_points.size():
		_spawn_lootbox(arena.box_points[bi], "Box%d" % bi)
	_cube_seq = 0

	phase = Phase.COUNTDOWN
	phase_at = now
	center_label.text = "3"
	feed_label.text = ""
	results.visible = false
	_update_players_label()
	cam.position = player.position + CAMERA_OFFSET
	cam.look_at(player.position, Vector3.UP)
	for f in fighters:
		f.reset_physics_interpolation()
	cam.reset_physics_interpolation()
	_match_ready = true
	print("[net] roster applied: %d fighters, I am %s" % [roster.size(),
			player.display_name if player else "spectator"])

## Client frame: mirror the countdown, send input up, ease puppets toward the
## latest snapshot. The local fighter is a puppet too — no prediction; on LAN
## the round trip is a few ms.
func _client_tick(delta: float) -> void:
	if phase == Phase.COUNTDOWN:
		center_label.text = str(int(ceil(maxf(3.5 - (now - phase_at), 1.0))))
	if phase == Phase.PLAYING and player != null and is_instance_valid(player) \
			and not player.is_dead():
		var dir := Vector3.ZERO
		if move_stick.active:
			dir = Vector3(move_stick.value.x, 0, move_stick.value.y)
		else:
			if Input.is_physical_key_pressed(KEY_W): dir.z -= 1
			if Input.is_physical_key_pressed(KEY_S): dir.z += 1
			if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
			if Input.is_physical_key_pressed(KEY_D): dir.x += 1
			dir = dir.normalized()
		var face := Vector3.ZERO   # aim-stick facing, so the host can mirror it
		var aim: TouchStick = super_stick if super_stick.active else aim_stick
		if aim.active and aim.value.length() > 0.15:
			face = Vector3(aim.value.x, 0, aim.value.y)
		_net_input.rpc_id(1, dir.limit_length(1.0), face)

	var k := 1.0 - exp(-14.0 * delta)
	for i in net_fighters.size():
		var f = net_fighters[i]
		if f == null or not is_instance_valid(f) or not _puppet_targets.has(i):
			continue
		var t: Dictionary = _puppet_targets[i]
		var prev: Vector3 = f.position
		f.position = f.position.lerp(t.pos, k)
		f.rotation.y = lerp_angle(f.rotation.y, t.rot, k)
		f.facing = Vector3(-sin(f.rotation.y), 0, -cos(f.rotation.y))
		f.velocity = (f.position - prev) / delta   # drives run/idle animation

func _net_send_snapshot() -> void:
	var states: Array = []
	for i in net_fighters.size():
		var f = net_fighters[i]
		if f == null or not is_instance_valid(f) or f.is_dead():
			states.append([])
		else:
			states.append([f.position.x, f.position.z, f.rotation.y,
					f.health, f.max_health, f.ammo, f.super_charge, f.cubes])
	_net_snapshot.rpc(int(phase), gas.inset if gas else -1, fighters.size(), states)

## Net results overlay: unlike _end_match this never flips the phase — the
## host's sim keeps running for whoever is still alive.
func _net_show_results(rank: int, victory: bool) -> void:
	center_label.text = ""
	move_stick.release()
	aim_stick.release()
	super_stick.release()
	results_title.text = ("VICTORY!" if victory else "DEFEATED") \
		+ "\nYou placed #%d of %d" % [rank, _net_roster.size()]
	results_title.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.2) if victory else Color(0.95, 0.4, 0.35))
	var award: Dictionary = SaveGame.award_match(_my_kit_name, rank)
	results_award.text = "TROPHIES %+d      COINS +%d" % [award.trophies, award.coins]
	results.visible = true

## Host: one fighter (or none, if the gas closed) remains — end the match.
func _net_finish() -> void:
	phase = Phase.ENDED
	var idx := -1
	if fighters.size() == 1:
		idx = net_fighters.find(fighters[0])
	_net_match_over.rpc(idx)
	if idx >= 0 and fighters[0] == player:
		_net_show_results(1, true)
	elif idx >= 0 and results.visible:
		results_title.text += "\n%s wins!" % fighters[0].display_name

func _on_net_peer_left(id: int) -> void:
	_peer_inputs.erase(id)
	_net_ready_peers.erase(id)
	if not _match_ready:
		return
	for f in fighters.duplicate():
		if is_instance_valid(f) and int(f.get_meta("peer", 0)) == id and not f.is_dead():
			_eliminate(f, "", true)

func _on_net_host_lost() -> void:
	center_label.text = "HOST LEFT"
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		get_tree().change_scene_to_file("res://menu.tscn"))

# MARK: net RPCs (client -> host)

@rpc("any_peer", "call_remote", "reliable")
func _net_client_ready() -> void:
	if not net_host:
		return
	var id := multiplayer.get_remote_sender_id()
	_net_ready_peers[id] = true
	if _match_ready:   # joined after kickoff (slow load): catch them up
		_net_start.rpc_id(id, _match_seq, _net_roster)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_input(move: Vector3, face: Vector3) -> void:
	if net_host:
		_peer_inputs[multiplayer.get_remote_sender_id()] = {"move": move, "face": face}

@rpc("any_peer", "call_remote", "reliable")
func _net_fire(use_super: bool, dir: Vector3, dist: float) -> void:
	if not net_host or phase != Phase.PLAYING:
		return
	var idx := -1
	for i in net_fighters.size():
		var cand = net_fighters[i]
		if cand != null and is_instance_valid(cand) \
				and int(cand.get_meta("peer", 0)) == multiplayer.get_remote_sender_id():
			idx = i
			break
	if idx < 0:
		return
	var f: Fighter = net_fighters[idx]
	if f.is_dead() or f.is_dashing() or f.is_disconnected(now):
		return
	if use_super:
		if f.consume_super():
			perform_attack(f, f.kit["super"], dir, dist)
	elif f.consume_ammo():
		perform_attack(f, f.kit.weapon, dir, dist)

# MARK: net RPCs (host -> clients)

@rpc("authority", "call_remote", "reliable")
func _net_start(seq: int, roster: Array) -> void:
	if seq <= _net_seen_seq:
		return   # duplicate (re-sent for a late joiner)
	_net_seen_seq = seq
	_start_from_roster(roster)

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_snapshot(phase_h: int, inset: int, left: int, states: Array) -> void:
	if not _match_ready:
		return
	players_label.text = "%d LEFT" % left
	if phase == Phase.COUNTDOWN and phase_h == int(Phase.PLAYING):
		phase = Phase.PLAYING
		center_label.text = "FIGHT!"
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if phase == Phase.PLAYING:
				center_label.text = "")
	if inset >= 0:
		if gas == null:
			gas = GasRing.new()
			add_child(gas)
			gas.map_tiles = arena.columns
		if gas.inset != inset:
			gas.inset = inset
			gas._rebuild_overlay()
	for i in mini(states.size(), net_fighters.size()):
		var s: Array = states[i]
		var f = net_fighters[i]
		if s.is_empty() or f == null or not is_instance_valid(f) or f.is_dead():
			continue
		_puppet_targets[i] = {"pos": Vector3(s[0], 0, s[1]), "rot": float(s[2])}
		f.max_health = int(s[4])
		var h := int(s[3])
		if h < f.health:
			f.take_damage(f.health - h, now)   # flash + damage popup
		else:
			f.health = h
		f.ammo = float(s[5])
		f.super_charge = float(s[6])
		f.cubes = int(s[7])

@rpc("authority", "call_remote", "reliable")
func _net_attack(idx: int, use_super: bool, dir: Vector3, dist: float) -> void:
	if net_host or idx < 0 or idx >= net_fighters.size():
		return
	var f = net_fighters[idx]
	if f == null or not is_instance_valid(f) or f.is_dead():
		return
	perform_attack(f, f.kit["super"] if use_super else f.kit.weapon, dir, dist)

@rpc("authority", "call_remote", "reliable")
func _net_eliminate(idx: int, killer: String, rank: int, left_game: bool) -> void:
	if net_host or idx < 0 or idx >= net_fighters.size():
		return
	var f = net_fighters[idx]
	if f == null or not is_instance_valid(f):
		return
	fighters.erase(f)
	f.die()
	_update_players_label()
	feed_label.text = _elim_feed_text(f.display_name, killer, left_game)
	if f == player:
		player = null
		_net_show_results(rank, false)

@rpc("authority", "call_remote", "reliable")
func _net_match_over(idx: int) -> void:
	if net_host:
		return
	phase = Phase.ENDED
	if idx >= 0 and idx < net_fighters.size() and net_fighters[idx] != null \
			and is_instance_valid(net_fighters[idx]):
		var w: Fighter = net_fighters[idx]
		if w == player:
			_net_show_results(1, true)
		elif results.visible:
			results_title.text += "\n%s wins!" % w.display_name

@rpc("authority", "call_remote", "reliable")
func _net_box_damaged(box_name: String, hp: int) -> void:
	if net_host:
		return
	for box in get_tree().get_nodes_in_group("lootbox"):
		if String(box.name) == box_name:
			box.set_meta("health", hp)
			break

@rpc("authority", "call_remote", "reliable")
func _net_box_broken(box_name: String, cube_id: int, pos: Vector3) -> void:
	if net_host:
		return
	for box in get_tree().get_nodes_in_group("lootbox"):
		if String(box.name) == box_name:
			box.queue_free()
			break
	_spawn_cube(pos, cube_id)   # visual only: clients never connect pickup

@rpc("authority", "call_remote", "reliable")
func _net_cube_gone(cube_name: String, collector_idx: int) -> void:
	if net_host:
		return
	var cube := find_child(cube_name, false, false)
	if cube:
		cube.queue_free()
	if collector_idx >= 0 and collector_idx < net_fighters.size():
		var f = net_fighters[collector_idx]
		if f != null and is_instance_valid(f) and not f.is_dead():
			f.collect_cube()   # popup; the next snapshot re-syncs the stats

@rpc("authority", "call_remote", "reliable")
func _net_wall_broken(wall_name: String) -> void:
	if net_host:
		return
	for w in get_tree().get_nodes_in_group("breakable"):
		if String(w.name) == wall_name:
			w.queue_free()
			break
