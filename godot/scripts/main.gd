extends Node3D
## Match controller: spawning, phases, combat resolution, camera, HUD.
## Debug env hooks (see CLAUDE.md): NS3_KIT, NS3_AUTOFIRE, NS3_AUTOWALK,
## NS3_GODMODE, NS3_CUBES, NS3_SHOTS="prefix:t1,t2,..." (screenshots at match times).

enum Phase { COUNTDOWN, PLAYING, ENDED }

## Pre-match: the VS cards count 5..1, then the mode title holds for the rest.
const PREMATCH := 7.0
const PREMATCH_INTRO_AT := 5.0

const BOX_HEALTH := 900   # loot box hit points; also the bar's full width
# Loading the 3D pickup on the fatal-hit frame caused a large synchronous disk
# and texture decode spike. Keep it resident before the match starts instead.
const POWER_CUBE_SCENE: PackedScene = preload("res://assets/power_cube.glb")

var arena: Arena
var gas: GasRing
## Nobles Cup rules engine; null in Showdown. See cup_mode.gd.
var cup: CupMode
var mode := "showdown"
var cam: Camera3D
var player: Fighter
var fighters: Array[Fighter] = []
var brains: Array[BotBrain] = []
var phase := Phase.COUNTDOWN
var phase_at := 0.0
var now := 0.0
## When the fighting actually started. `now` runs for the life of the scene, so
## PLAY AGAIN would otherwise report the second match's survival time as the sum
## of both. Everything on the results card that is a duration measures off this.
var match_start := 0.0

# HUD
var hud: CanvasLayer
var center_label: Label
var versus: VersusScreen
var players_label: Label
var feed_label: Label
var status_label: Label
var move_stick: TouchStick
var aim_stick: TouchStick
var super_stick: TouchStick   # dedicated Super joystick, anchored at the button
var super_btn: SuperButton
var fighter_bars: FighterBars
var results: Control
## The "you are down" wash and the count to your return. Nobles Cup only — a
## Showdown death has nothing to count to, and raises the results card instead.
var down_overlay: ColorRect
var down_label: Label
## Where the results card itself is built. Cleared and refilled per result, so
## the overlay root and its dim survive a rematch while the card does not.
var results_body: Control
## The "Nova 3 wins!" line a net client gets after its own fighter went down and
## the host's match ran on without it. Empty and hidden the rest of the time.
var results_note: Label
var aim_mesh: MeshInstance3D

# The steep, low-distortion 2.5D framing. Defined on Arena (MATCH_CAM_OFFSET /
# MATCH_CAM_FOV, with the reasoning) so tools/render_map.gd can shoot the arena
# through the same lens without importing this script.
const CAMERA_OFFSET := Arena.MATCH_CAM_OFFSET
const CAMERA_FOV := Arena.MATCH_CAM_FOV
const TAP_THRESHOLD := 0.3
## The carrier's kick lane. Cool and pale so it never reads as a weapon's aim;
## the Super Shot's is hotter and twice as long, so the two are never confused.
const KICK_AIM_COLOR := Color(0.55, 0.86, 1.0, 0.45)
const SUPER_KICK_AIM_COLOR := Color(1.0, 0.78, 0.30, 0.55)
## How far Pop Off's spike will snap onto an enemy who drifted off the spot
## Anders jumped away from.
const SPIKE_SNAP := 3.2
## The wash a Nobles Cup death puts over the screen, and how long it takes to
## arrive and to clear.
const DOWN_TINT := Color(0.78, 0.05, 0.07)
const DOWN_FADE := 0.26

## A vignette rather than a flat pane. Flat red at an alpha low enough to keep
## the pitch readable does not read as red at all — over green it composites to
## olive, and the screen just looks dirty. Banking it into the corners lets the
## edges go properly saturated while the middle, where the match is, stays
## nearly clear.
const DOWN_SHADER := """
shader_type canvas_item;

uniform vec3 tint : source_color = vec3(0.78, 0.05, 0.07);
uniform float strength = 0.0;
uniform float middle = 0.14;
uniform float edge = 0.82;

void fragment() {
	vec2 p = UV - vec2(0.5);
	// Squashed on Y so the falloff is an ellipse the shape of the screen; a
	// round one on a 16:9 frame reaches the top and bottom long before the sides.
	float r = length(p * vec2(1.0, 0.62)) * 2.0;
	float v = smoothstep(0.28, 1.0, r);
	COLOR = vec4(tint, (middle + (edge - middle) * v) * strength);
}
"""

# Debug hooks
var god_mode := OS.get_environment("NS3_GODMODE") != ""
var auto_fire := float(OS.get_environment("NS3_AUTOFIRE")) if OS.get_environment("NS3_AUTOFIRE") != "" else 0.0
var _last_auto_fire := 0.0
var _shot_prefix := ""
var _shot_times: Array[float] = []
## NS3_END=<sec>: end the match this many seconds after FIGHT!, with whatever
## placement the player has earned by then. The results card is otherwise only
## reachable by surviving or dying at an unpredictable moment, which makes it
## the one screen in the game that cannot be shot with NS3_SHOTS.
var _force_end_at := float(OS.get_environment("NS3_END")) if OS.get_environment("NS3_END") != "" else 0.0
## NS3_KILL=<sec>: eliminate the player this many seconds after FIGHT!. The
## sibling of NS3_END, and for the same reason — going down is a thing that
## happens at an unpredictable moment, so the knockdown, the results card a
## Showdown death raises and the Nobles Cup respawn three seconds later were all
## unshootable. In Cup this is the only way to see an arrival on purpose: a
## whole match produces two or three deaths and none of them where you are
## looking.
var _force_kill_at := float(OS.get_environment("NS3_KILL")) if OS.get_environment("NS3_KILL") != "" else 0.0

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

## Battle music. The menu owns its own track; the match had none at all, so it
## starts one here and honours the same Settings toggle.
const BATTLE_MUSIC := "res://assets/menu/audio/clash_carnival.mp3"

var _music: AudioStreamPlayer

## Match SFX. Every sound is synthesized at runtime by MenuAudio, so the match
## borrows the menu's engine wholesale rather than growing a second one and the
## game still ships no audio files. Null under NS3_SIM, where a headless batch
## at 10x speed has no use for audio and every _render would be wasted work.
var sfx: MenuAudio

## Distance falloff for a sound that happened somewhere on the map. Inside NEAR
## it plays at its own level; past FAR it is not played at all. The match camera
## shows about 23 m, so a shot from the far corner of the view is already well
## down and one fired off-screen is gone.
const SFX_NEAR := 6.0
const SFX_FAR := 30.0
## Where the match is heard from — the player while they are alive, and wherever
## they fell afterwards. Tracked rather than read off `cam`, whose transform is
## an overhead position that would put every sound tens of metres away.
var _listener := Vector3.ZERO
## Damage resolves per pellet, so a nine-pellet shotgun would fire nine impacts
## on one frame. One is all you can hear anyway.
const IMPACT_GAP := 0.05
var _last_impact_at := -1.0
var _last_count_beep := -1
var _low_health_at := -1.0
var _last_ammo_pips := 0
var _last_empty_click := -1.0

func _start_battle_music() -> void:
	if not SaveGame.music_on or not ResourceLoader.exists(BATTLE_MUSIC):
		return
	var track: AudioStream = load(BATTLE_MUSIC) as AudioStream
	if track == null:
		return
	if track is AudioStreamMP3:
		track.loop = true
	_music = AudioStreamPlayer.new()
	_music.stream = track
	_music.volume_db = -13.0
	_music.bus = "Master"
	add_child(_music)
	_music.play()

func _ready() -> void:
	SaveGame.ensure_loaded()   # NS3_KIT runs skip the menu, so load here too
	_start_battle_music()
	if not sim_active:
		sfx = MenuAudio.new()
		add_child(sfx)
	net_active = Net.active
	net_host = net_active and multiplayer.is_server()
	authoritative = not net_active or net_host
	# Both the sun and the environment are Arena's, so that a terrain change can
	# be shot outside a match under exactly the light the match uses.
	add_child(Arena.make_sun())
	var env := WorldEnvironment.new()
	env.environment = Arena.make_environment()
	add_child(env)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = CAMERA_FOV
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
		Loading.done()   # the roster is not built yet, but the wait is the screen
	elif net_active:
		print("[net] match scene up as client")
		Net.host_disconnected.connect(_on_net_host_lost)
		center_label.text = "CONNECTING…"
		Loading.done()
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
	_build_down_overlay()

## A red wash over the match and a count to your return, for the three seconds
## a Nobles Cup death costs you. Anchored rather than placed at fixed HUD
## coordinates like the labels above it: this one has to cover the screen at
## whatever size the screen happens to be.
##
## It cannot reach over Cup's own scoreboard, which sits on its own CanvasLayer
## above this one — the same thing `_show_results` has to work around — and that
## is deliberate here: the score and the clock stay legible through the wash.
func _build_down_overlay() -> void:
	down_overlay = ColorRect.new()
	down_overlay.color = Color.WHITE   # the shader paints it; this is just the quad
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = DOWN_SHADER
	mat.shader = sh
	mat.set_shader_parameter("tint", DOWN_TINT)
	mat.set_shader_parameter("strength", 0.0)
	down_overlay.material = mat
	down_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	down_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	down_overlay.visible = false
	hud.add_child(down_overlay)

	down_label = Label.new()
	down_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Centred in the LOWER part of the screen, not dead centre: `center_label`
	# lives there and a kickoff's "GO!" landed straight through the count.
	down_label.anchor_top = 0.56
	down_label.offset_top = 0.0
	down_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	down_label.add_theme_font_size_override("font_size", 110)
	down_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.93))
	down_label.add_theme_constant_override("outline_size", 12)
	down_label.add_theme_color_override("font_outline_color", Color(0.24, 0.02, 0.03, 0.9))
	down_overlay.add_child(down_label)

## Drives the wash from `now`. Kept as a two-state flip rather than a per-frame
## tween: fading a colour every frame from _process would start a new tween on
## every one of them, and they would fight each other rather than the clock.
func _update_down_overlay() -> void:
	if down_overlay == null:
		return
	var down: bool = _down_until > now and cup != null and not cup.finished
	if down:
		if not _down_shown:
			_down_shown = true
			down_overlay.visible = true
			# Over the fighter bars, which are added to the HUD before this and
			# would otherwise draw a health bar on top of the wash.
			hud.move_child(down_overlay, -1)
			var tw := create_tween()
			tw.tween_method(_set_down_strength, 0.0, 1.0, DOWN_FADE)
		down_label.text = "%d" % maxi(1, int(ceil(_down_until - now)))
	elif _down_shown:
		_down_shown = false
		down_label.text = ""
		var tw := create_tween()
		tw.tween_method(_set_down_strength, 1.0, 0.0, DOWN_FADE)
		tw.tween_callback(_hide_down_overlay)

func _set_down_strength(value: float) -> void:
	(down_overlay.material as ShaderMaterial).set_shader_parameter("strength", value)

func _hide_down_overlay() -> void:
	down_overlay.visible = false

## The overlay root: a dim, and an empty holder the card is built into. Only
## these two persist — the card itself is thrown away and rebuilt per result,
## because what it shows differs by mode and a scene can end several matches.
func _build_results_overlay() -> void:
	results = Control.new()
	results.set_anchors_preset(Control.PRESET_FULL_RECT)
	results.visible = false
	hud.add_child(results)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	results.add_child(dim)   # STOP by default, which is what keeps taps off the match

	results_body = Control.new()
	results_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_body.mouse_filter = Control.MOUSE_FILTER_IGNORE   # its buttons still take clicks
	results.add_child(results_body)

## The one way a match result reaches the screen. All three endings (Showdown
## placement, a Nobles Cup scoreline, and a net client whose own fighter went
## down while the host's match ran on) funnel through here so they cannot drift
## apart. `outcome` is +1 win / 0 draw / -1 loss — enough to colour the card.
## `rows` is the per-match stat table as [label, value] pairs.
## `board` is an alternative to the portrait-plus-stat-table body: Nobles Cup
## hands in a full team scoreboard, because a 3v3 result is about what both
## sides did and not only about you. Showdown and the net client leave it null
## and get the personal card unchanged.
func _show_results(outcome: int, headline: String, kit_name: String,
		award: Dictionary, rows: Array, rematch: bool, board: Control = null) -> void:
	for c in results_body.get_children():
		results_body.remove_child(c)
		c.queue_free()
	var accent: Color = MenuUI.YELLOW_HI if outcome > 0 else \
			(MenuUI.TEXT_SOFT if outcome == 0 else Color("#ff8a8a"))
	var title: String = "VICTORY!" if outcome > 0 else ("DRAW" if outcome == 0 else "DEFEATED")

	var card: PanelContainer = MenuUI.panel("card", 22, 8, 24)
	card.modulate.a = 0.0   # pop_in is a frame away; don't flash at full opacity first
	card.custom_minimum_size = Vector2(700, 0)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	results_body.add_child(card)

	var col: VBoxContainer = MenuUI.vbox(14)
	card.add_child(col)

	var head: Label = MenuUI.display(title, 54, accent, 9)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var sub: Label = MenuUI.display(headline, 26, MenuUI.TEXT_SOFT, 5)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	results_note = MenuUI.display("", 20, MenuUI.TEXT_DIM, 4)
	results_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_note.visible = false
	col.add_child(results_note)

	var body: HBoxContainer = MenuUI.hbox(18)
	col.add_child(body)
	# Whichever of the two bodies got built is what _animate_results staggers:
	# Showdown's stat rows, or Cup's two team columns.
	var staggered: Control = board
	if board != null:
		board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(board)
	else:
		body.add_child(_results_portrait(kit_name, accent))
		var table: VBoxContainer = MenuUI.vbox(7)
		table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.add_child(table)
		for r: Array in rows:
			table.add_child(_results_stat_row(str(r[0]), str(r[1])))
		staggered = table

	col.add_child(_results_rewards(award))

	var buttons: HBoxContainer = MenuUI.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	if rematch:
		var again: Button = MenuUI.button("PLAY AGAIN", "green", 30, Vector2(250, 74))
		again.pressed.connect(func() -> void:
			results.visible = false
			if net_host:
				_net_host_start()
			else:
				start_match())
		buttons.add_child(again)
	var menu: Button = MenuUI.button("LOBBY", "grey", 26, Vector2(168, 74))
	menu.pressed.connect(func() -> void:
		Net.leave()
		Loading.to_menu(get_tree()))
	buttons.add_child(menu)

	# Nobles Cup's scoreboard and the fighter health bars are added to the HUD
	# after this overlay is built in _ready, so without this they draw straight
	# through the card — a frozen 1 — 2 and a clock sitting over the headline.
	hud.move_child(results, -1)
	# Raising the card covers what is BEHIND it; Cup's score sits above it and
	# stayed on screen, printing the scoreline a second time over the top of a
	# card that already gives it twice. Hidden, not freed: PLAY AGAIN builds a
	# fresh CupMode with a HUD of its own, and _build_hud sweeps this one.
	for n in hud.get_children():
		if n.is_in_group(CupMode.HUD_GROUP):
			n.visible = false
	results.visible = true
	_animate_results(card, staggered)

## Held back a frame: pop_in pivots on `size`, which a container has not worked
## out until it has sorted its children at least once.
func _animate_results(card: Control, table: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	MenuUI.pop_in(card)
	if is_instance_valid(table):
		MenuUI.stagger(table, 0.06)

## Your fighter, on the rarity-less dark backdrop the menu cards use. Falls back
## to the kit's initial in its own colour for Nova and Ayaan, which have no
## portrait because they have no model yet.
func _results_portrait(kit_name: String, accent: Color) -> Control:
	var holder: Panel = MenuUI.card("dark", 16, 6)
	holder.custom_minimum_size = Vector2(196, 214)
	holder.add_child(MenuUI.card_backdrop(Color(accent.r, accent.g, accent.b, 0.30)))
	var id: String = kit_name.to_lower()
	var tex: Texture2D = MenuData.portrait(id)
	if tex != null:
		var pr := TextureRect.new()
		pr.texture = tex
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pr.offset_bottom = -34
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pr)
	else:
		var kit: Dictionary = Kits.named(kit_name)
		var initial: Label = MenuUI.display(kit_name.substr(0, 1).to_upper(), 96,
				kit.get("color", Color.WHITE), 8)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.offset_bottom = -34
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(initial)
	var name_l: Label = MenuUI.display(kit_name.to_upper(), 24, Color.WHITE, 6)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -44
	name_l.offset_bottom = -12
	holder.add_child(name_l)
	return holder

## One "DAMAGE DEALT ....... 4,820" line.
func _results_stat_row(label: String, value: String) -> Control:
	var row: PanelContainer = MenuUI.dark_panel(11, 0.34, 9)
	var line: HBoxContainer = MenuUI.hbox(8)
	row.add_child(line)
	var l: Label = MenuUI.body(label, 18, MenuUI.TEXT_DIM, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(l)
	var v: Label = MenuUI.display(value, 24, Color.WHITE, 4)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(v)
	return row

## Trophies, coins and Pass tokens, each counting up from zero with its own
## chime — the beat the menu already gives every other reward it hands out.
func _results_rewards(award: Dictionary) -> Control:
	var row: HBoxContainer = MenuUI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_reward_chip("trophy", int(award.get("trophies", 0)), true, 0.35))
	row.add_child(_reward_chip("coin", int(award.get("coins", 0)), false, 0.60))
	row.add_child(_reward_chip("token", int(award.get("tokens", 0)), false, 0.85))
	return row

func _reward_chip(icon_name: String, amount: int, signed: bool, delay: float) -> Control:
	var chip: PanelContainer = MenuUI.dark_panel(13, 0.42, 10)
	var line: HBoxContainer = MenuUI.hbox(7)
	chip.add_child(line)
	line.add_child(MenuUI.icon(icon_name, 32))
	# A trophy loss must read as one, so the sign is always shown for trophies.
	var tint: Color = Color("#ff8a8a") if (signed and amount < 0) else MenuUI.YELLOW_HI
	var value: Label = MenuUI.display("", 28, tint, 5)
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(value)
	_count_up(value, amount, signed, delay)
	return chip

func _count_up(l: Label, amount: int, signed: bool, delay: float) -> void:
	var render := func(v: int) -> String:
		return ("+%s" % MenuUI.fmt(v)) if (signed and v >= 0) else MenuUI.fmt(v)
	l.text = render.call(0)
	var tw := l.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: sfx_ui("reward", 1.0))
	tw.tween_method(func(v: float) -> void:
		l.text = render.call(int(round(v))), 0.0, float(amount), 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## MM:SS for the survival row.
func _fmt_clock(seconds: float) -> String:
	var s: int = int(round(maxf(0.0, seconds)))
	return "%d:%02d" % [s / 60, s % 60]

## The stat table for a Showdown result. Cup builds its own in end_cup_match.
func _showdown_rows(f: Fighter) -> Array:
	if f == null or not is_instance_valid(f):
		return []
	return [
		["DAMAGE DEALT", MenuUI.fmt(int(f.stats.damage))],
		["ELIMINATIONS", str(int(f.stats.kills))],
		["POWER CUBES", str(int(f.stats.cubes))],
		["SURVIVED", _fmt_clock(float(f.stats.survived))],
	]

func _label(pos: Vector2, size: int, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(430, 0) if align != HORIZONTAL_ALIGNMENT_CENTER else Vector2(0, 0)
	hud.add_child(l)
	return l

# MARK: impact VFX

## Styles that leave the barrel. Everything else is a swing, a leap or an area
## effect, and already has its own MeleeSwipe or Shockwave to sell it — a
## muzzle flash on a melee lunge would read as a gun going off.
const MUZZLE_STYLES := [Kits.Style.PELLETS, Kits.Style.LOB, Kits.Style.BOOMERANG,
		Kits.Style.BUTTONS, Kits.Style.KEEP_IT_UP, Kits.Style.SLALOM]

## The burst where something landed. `travel` is the direction the hit was
## moving, so shards carry on past the target rather than spraying evenly.
func _hit_spark(pos: Vector3, travel: Vector3, tint: Color) -> void:
	var s := HitSpark.new()
	s.position = Vector3(pos.x, 0.0, pos.z)
	s.direction = Vector3(travel.x, 0, travel.z)
	s.tint = tint.lerp(Color(1, 0.95, 0.7), 0.55)
	s.height = 1.05          # roughly where a shot meets a 1.6 m fighter
	add_child(s)

## The flash at the barrel. Narrow, short and coreless — it is a hint of where
## the shot came from, not an event in its own right.
func _muzzle_flash(f: Fighter, unit: Vector3, weapon: Dictionary) -> void:
	if not MUZZLE_STYLES.has(int(weapon.style)):
		return
	var s := HitSpark.new()
	s.position = f.global_position + unit * 0.55
	s.direction = unit
	s.tint = f.kit.get("color", Color.WHITE)
	s.cone = 0.42
	s.spread = 1.5
	s.shards = 5
	s.duration = 0.12
	s.height = 1.0
	s.core = false
	add_child(s)

## Everything a weapon has put in the air, and the lingering areas two Supers
## leave behind. Shared by start_match and CupMode.kickoff so the two lists
## cannot drift: a lob or a boomerang thrown a moment before a goal would
## otherwise sail through the reset and land on someone standing on the centre
## spot. The Ball is deliberately not in here — a kickoff re-places it rather
## than replacing it, and start_match frees it separately.
##
## Freeing a Boomerang is also what gives Sanjit his staff back
## (`boomerang.gd:_exit_tree`), so nothing here may be skipped for one.
func clear_in_flight() -> void:
	for c in get_children():
		if c is Projectile or c is Lob or c is Boomerang or c is HackySack \
				or c is MeleeSwipe or c is Shockwave or c is DisconnectZone:
			c.queue_free()

func start_match() -> void:
	clear_in_flight()
	for c in get_children():
		if c is Arena or c is GasRing or c is Fighter or c is Ball or c is CupMode:
			c.queue_free()
	for c in get_tree().get_nodes_in_group("lootbox") + get_tree().get_nodes_in_group("cube"):
		c.queue_free()
	fighters.clear()
	brains.clear()
	_last_count_beep = -1
	_last_impact_at = -1.0
	_low_health_at = -1.0
	_last_ammo_pips = int(Kits.MAX_AMMO)   # spawning full is not a reload

	# Mode hook. Nobles Cup swaps the map, the roster and the win condition;
	# everything below the branch is Showdown's and stays that way. NS3_MODE
	# beats the menu's pick so game.tscn can be run straight into a mode.
	var mode_env := OS.get_environment("NS3_MODE")
	mode = mode_env if mode_env != "" else Session.mode
	cup = null

	arena = Arena.new()
	arena.map_mode = "cup" if mode == "cup" else "showdown"
	add_child(arena)
	gas = null

	await get_tree().process_frame   # let arena _ready run

	if mode == "cup":
		cup = CupMode.new()
		cup.game = self
		add_child(cup)
		cup.build_match(now)
	else:
		var spawns := arena.spawn_points.duplicate()
		spawns.shuffle()

		player = _spawn_fighter(player_kit(), spawns.pop_front(), not sim_active)
		player.display_name = "%s 0" % player.kit.name if sim_active else "You"
		if sim_active:
			brains.append(BotBrain.new(player))

		var i := 1
		while not spawns.is_empty() and i <= 9:
			var kit: Dictionary = Kits.all().pick_random()
			var bot := _spawn_fighter(kit, spawns.pop_front(), false)
			bot.display_name = "%s %d" % [kit.name, i]
			brains.append(BotBrain.new(bot))
			i += 1

		for p in arena.box_points:
			_spawn_lootbox(p)

	if OS.get_environment("NS3_SUPER") != "":   # debug: start with Super charged
		player.super_charge = 1.0
	for _c in int(OS.get_environment("NS3_CUBES")):   # debug: start loaded with cubes
		player.collect_cube()

	_start_countdown()
	if sim_active:
		for f in fighters:
			_sim_kit(f.kit.name).spawns += 1
		phase = Phase.PLAYING   # no countdown between sim matches
		match_start = now
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
	# The arena, the roster and the HUD are all up: this is the first frame
	# worth looking at, so the loading screen can come off. start_match() awaits
	# a frame partway through, which is why this cannot live in _ready.
	Loading.done()

## What the player brought to the match: the menu's pick, or a random kit when
## the balance sim is driving every slot.
func player_kit() -> Dictionary:
	if sim_active:
		return Kits.all().pick_random()
	return Session.kit if not Session.kit.is_empty() else Kits.nova()

func _start_countdown() -> void:
	phase = Phase.COUNTDOWN
	phase_at = now
	center_label.text = ""
	feed_label.text = ""
	results.visible = false
	_show_versus()

## The pre-match versus card over the countdown. Showdown lists the ten solo
## fighters five a side with you on the left; Nobles Cup lists the two teams.
## The balance sim skips it — nobody is watching.
func _show_versus() -> void:
	if versus != null and is_instance_valid(versus):
		versus.queue_free()
	versus = null
	if sim_active:
		return
	MenuData.ensure_loaded()
	var top: Array = []
	var bottom: Array = []
	if mode == "cup":
		for f in fighters:
			if f.team == player.team:
				bottom.append(f)
			else:
				top.append(f)
	else:
		bottom.append(player)
		var others: Array = []
		for f in fighters:
			if f != player:
				others.append(f)
		for i in others.size():
			if top.size() < 5:
				top.append(others[i])
			else:
				bottom.append(others[i])
	versus = VersusScreen.new()
	hud.add_child(versus)
	versus.build(mode, top, bottom, player)
	# The match HUD waits behind the cards.
	status_label.visible = false
	players_label.visible = false
	feed_label.visible = false

func _hide_versus() -> void:
	if versus != null and is_instance_valid(versus):
		versus.dismiss()
	versus = null
	status_label.visible = true
	players_label.visible = true
	feed_label.visible = true

func _spawn_fighter(kit: Dictionary, pos: Vector3, is_player: bool, team := -1) -> Fighter:
	var f := Fighter.new()
	f.kit = kit
	f.is_player = is_player
	f.team = team
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
	# Meshy crate model; the collider below stays the authority on its size.
	var m: Node3D = (load("res://assets/loot_crate.glb") as PackedScene).instantiate()
	m.scale = Vector3.ONE * 0.58   # model is ~1.9 across; match the 1.1 collider
	# No random yaw: under the steep match camera an off-axis crate presents a
	# corner to the viewer and reads as tipped over rather than sat on the floor.
	# Square-on is how Brawl Stars sits its boxes, and the model is symmetric so
	# there is nothing to vary anyway.
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var mat = mesh.surface_get_material(si)
			if mat is BaseMaterial3D:
				mat.metallic = 0.0
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
	var m: Node3D = POWER_CUBE_SCENE.instantiate()
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
			if not body is Fighter or body.is_dead() or not is_instance_valid(area) \
					or area.is_queued_for_deletion() or area.get_meta("claimed", false):
				return
			# queue_free() is deferred until the end of the frame. Mark the pickup
			# first so two overlapping fighters/body_entered signals cannot both
			# collect this same cube during that window.
			area.set_meta("claimed", true)
			area.queue_free()
			sfx_at("cube_pickup", area.global_position, 1.0)
			body.collect_cube()
			if net_host:
				_net_cube_gone.rpc(String(area.name), net_fighters.find(body)))
	add_child(area)

# MARK: sfx

## NS3_SFX_LOG=1 prints every sound as it fires. Synthesized audio is easy to
## mis-hear as missing when it is only quiet, so this is how you tell "the hook
## never ran" from "turn it up".
var _sfx_log := OS.get_environment("NS3_SFX_LOG") != ""

## One sound that happened at a place on the map: attenuated by its distance
## from the listener and nudged off-pitch, because a stream of bit-identical
## samples reads as a loop rather than as gunfire.
func sfx_at(sound: String, at: Vector3, gain_db := 0.0, pitch_var := 0.06) -> void:
	if sfx == null:
		return
	var d: float = at.distance_to(_listener)
	if d > SFX_FAR:
		return
	if _sfx_log:
		print("[sfx] %-14s %5.1f m" % [sound, d])
	var fade: float = clampf((d - SFX_NEAR) / (SFX_FAR - SFX_NEAR), 0.0, 1.0)
	sfx.play_at(sound, gain_db - 6.0 - 24.0 * fade,
			1.0 + randf_range(-pitch_var, pitch_var))

## A sound with no place on the map — the countdown, the results sting, the
## whistle. Always at full level, never pitched.
func sfx_ui(sound: String, gain_db := 0.0) -> void:
	if sfx != null:
		if _sfx_log:
			print("[sfx] %-14s   ui" % sound)
		sfx.play_at(sound, gain_db - 4.0, 1.0)

## Which synthesized shape a weapon fires. Keyed off `style` rather than off the
## kit, so a new character inherits a sound from the style it picks and only
## needs an entry here if it introduces a style.
func _attack_sound(weapon: Dictionary) -> String:
	match int(weapon.style):
		Kits.Style.PELLETS:
			# A spread reads as a shotgun; one projectile reads as a rifle.
			return "shot_shotgun" if int(weapon.pellets) > 2 else "shot_single"
		Kits.Style.LOB, Kits.Style.DISCONNECT:
			return "shot_lob"
		Kits.Style.MELEE:
			return "melee_swing"
		Kits.Style.BOOMERANG:
			return "shot_boomerang"
		Kits.Style.SHOCKWAVE, Kits.Style.JUMP_SMASH, Kits.Style.POP_OFF:
			return "shockwave"
		Kits.Style.BUTTONS:
			return "shot_button"
		Kits.Style.KEEP_IT_UP:
			return "shot_sack"
		Kits.Style.SLALOM:
			return "shot_curve"
		Kits.Style.DASH, Kits.Style.DOWNHILL:
			return "super_fire"
	return "shot_single"

# MARK: combat

## Owner references on in-flight projectiles can outlive the fighter; typed
## params reject freed instances, so sanitize them to null before deal_damage.
func _live(f) -> Fighter:
	return f if is_instance_valid(f) else null

## `impact_sound` is what the connection sounds like; melee passes its own so a
## swing that lands does not sound like a bullet arriving.
func deal_damage(amount: int, target: Fighter, attacker: Fighter,
		kb_dir := Vector3.ZERO, kb_strength := 0.0, impact_sound := "impact") -> void:
	if not authoritative:   # client-side attacks are visual only
		return
	if target.is_dead():
		return
	if god_mode and target == player:
		return
	if attacker != null and attacker.is_ally(target):
		return   # Nobles Cup teams; Showdown fighters are never allies
	target.take_damage(amount, now)
	if kb_strength > 0.0:
		target.receive_knockback(kb_dir, kb_strength)
	if now - _last_impact_at >= IMPACT_GAP:
		_last_impact_at = now
		sfx_at(impact_sound, target.global_position)
		# Sharing the sound's throttle on purpose: a nine-pellet shotgun would
		# otherwise stack nine identical bursts on one frame, which reads as one
		# fat flash rather than as nine hits and costs nine draw calls to do it.
		var from: Vector3 = kb_dir if kb_strength > 0.0 else \
				(target.global_position - attacker.global_position if attacker != null else Vector3.ZERO)
		_hit_spark(target.global_position, from, target.kit.get("color", Color.WHITE))
	if attacker != null:
		attacker.stats.damage += amount
		var was_charged: bool = attacker.is_super_ready()
		attacker.charge_super(amount)
		# The moment the bar fills is the only cue the player gets that the
		# Super is available without looking away from the fight.
		if attacker == player and not was_charged and attacker.is_super_ready():
			sfx_ui("super_ready", 1.0)
		if sim_active:
			_sim_kit(attacker.kit.name).damage += amount
			_sim_kit(attacker.kit.name).hits += 1
	if target.is_dead():
		if attacker != null:
			attacker.stats.kills += 1
			if sim_active:
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
	# A Super is its own sound whatever style it borrows: it is the loudest
	# thing that happens in a match and has to cut through the shot it replaces.
	sfx_at("super_fire" if is_super else _attack_sound(weapon), f.global_position,
			3.0 if is_super else 0.0)
	_muzzle_flash(f, unit, weapon)
	match int(weapon.style):
		Kits.Style.PELLETS:
			var shot_weapon := weapon
			var flaming := bool(weapon.get("heat_trait", false)) and f.is_on_fire(now)
			if flaming:
				shot_weapon = weapon.duplicate()
				shot_weapon.speed = float(weapon.speed) * 1.35
				shot_weapon["burn_duration"] = 2.0
				shot_weapon["burn_tick_damage"] = 75
				shot_weapon.projectile_color = Color(1.0, 0.12, 0.01)
			var base := atan2(unit.x, unit.z)
			# `unload` staggers a multi-projectile attack so it reads as a stream
			# rather than a fan appearing all at once (Brawl Stars spaces its
			# stream attacks 0.2-0.3s). A shotgun leaves it at 0 and fires the
			# whole spread on one frame, which is what Shelly does.
			var unload: float = float(weapon.get("unload", 0.0))
			var fid := f.get_instance_id()
			for p in int(weapon.pellets):
				var t: float = (float(p) / float(max(1, int(weapon.pellets) - 1)) - 0.5) \
					if int(weapon.pellets) > 1 else 0.0
				var ang: float = base + deg_to_rad(weapon.spread_deg) * t
				if unload <= 0.0 or p == 0:
					_spawn_pellet(f, shot_weapon, ang)
				else:
					# By id, not reference: the fighter can die mid-unload.
					get_tree().create_timer(unload * p).timeout.connect(func() -> void:
						var fx := instance_from_id(fid)
						if phase == Phase.PLAYING and fx is Fighter and not fx.is_dead():
							_spawn_pellet(fx, shot_weapon, ang))
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
			# A lunging melee closes its own gap. Sanjit is the only melee kit
			# whose Super travels AWAY from him, so where Henry dashes and
			# Kovacs leaps, his approach has to live on the basic attack — and
			# it fires whether or not the swing connects, so swinging at air is
			# a legitimate way to travel.
			var lunge: float = float(weapon.get("lunge", 0.0))
			f.lunge(unit, lunge)
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
						fx.lunge(fx.facing, lunge)
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
		Kits.Style.SLALOM:
			# `dist` is not a throw distance here, it is where the two shots
			# MEET — the one thing this weapon asks the player to choose.
			# `slalom_weave` turns it into the weave that puts a crossing there
			# and still has the range to arrive; a drag, a tap and a bot all hand
			# it a distance without needing to know that is what it means.
			var weave: Dictionary = Kits.slalom_weave(weapon, dist)
			# Both shots leave on the SAME frame, deliberately: the pair only
			# reads as a slalom if you can watch it split and cross again, and an
			# `unload` stagger would smear the two lanes into one stream.
			for p in int(weapon.pellets):
				_spawn_slalom_shot(f, weapon, unit, 1.0 if p % 2 == 0 else -1.0, weave)
		Kits.Style.DOWNHILL:
			# Clients skip the ride state machine for the same reason they skip
			# a dash: the host simulates it and the snapshot stream moves them.
			if authoritative:
				f.begin_ride(weapon, unit)
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
		Kits.Style.KEEP_IT_UP:
			# One sack, always. A rally continues the existing sack rather than
			# spawning another, so the count can never climb the way the old
			# ammo-refunding version let it.
			for n in get_children():
				if n is HackySack and n.owner_fighter == f:
					f.ammo = minf(f.max_ammo, f.ammo + 1.0)   # kick never happened
					if sim_active:
						_sim_kit(f.kit.name).s_blocked += 1
						_sim_kit(f.kit.name).attacks -= 1   # never happened; keep dmg/atk honest
					return
			var hop_to: float = clamp(dist, Kits.TILE * 1.5, weapon.range)
			var sack := HackySack.new()
			sack.weapon = weapon
			sack.base_damage = int(weapon.damage * f.damage_multiplier())
			sack.owner_fighter = f
			sack.game = self
			sack.position = f.global_position + unit * 0.8 + Vector3(0, 1.0, 0)
			# Damage step is capped; the streak the player sees is not.
			sack.rally = clampi(f.sack_streak + 1, 1, HackySack.MAX_RALLY)
			sack.streak = f.sack_streak + 1
			sack.on_enemy_hit = _on_rally_sack_hit
			sack.on_rally = _on_sack_caught
			sack.on_land = _on_sack_land
			sack.on_box_hit = _on_sack_box_hit
			if sim_active:
				_sim_kit(f.kit.name).s_launch += 1
			add_child(sack)
			# After add_child: the arc needs the node in the tree to sweep for
			# walls and to place its landing ring.
			sack.launch_at(f.global_position + unit * hop_to)
		Kits.Style.POP_OFF:
			# Pops the sack up and leaps clear along the aim; the spike fires
			# back down the same line on landing (see _update_leaps). Consumes
			# whatever rally was in flight — it is "the" sack.
			if sim_active:
				_sim_kit(f.kit.name).s_super += 1
				if f.ammo_locked:
					_sim_kit(f.kit.name).s_lock += 1
			if authoritative:
				# A live rally is CASHED IN rather than thrown away: the spike
				# lands for whatever that sack had climbed to. Half of all Pop
				# Offs were fired mid-rally, so consuming one for nothing made
				# the Super a punishment for running the kit's own engine.
				var cash_in := 1.0
				for n in get_children():
					if n is HackySack and n.owner_fighter == f:
						cash_in = float(n.rally_damage()) / maxf(1.0, float(n.base_damage))
						n.queue_free()
				f.begin_leap(weapon, unit, float(weapon.range))
				f.leap["spike_mult"] = cash_in

## One pellet, launched along an absolute world heading. Split out of
## perform_attack so that a staggered `unload` can fire the later pellets from
## the fighter's CURRENT position while keeping the aim it was given — a moving
## shooter trails its stream behind it instead of dragging the whole spread.
func _spawn_pellet(f: Fighter, weapon: Dictionary, ang: float) -> void:
	var pd := Vector3(sin(ang), 0, cos(ang))
	var proj := Projectile.new()
	proj.weapon = weapon
	proj.damage = int(weapon.damage * f.damage_multiplier())
	proj.owner_fighter = f
	proj.direction = pd
	proj.position = f.global_position + pd * (Kits.FIGHTER_RADIUS + 0.25) + Vector3(0, 1.0, 0)
	proj.origin = proj.position
	# Ricochets are resolved by Projectile's swept collision, which has the
	# wall normal. A body_entered callback cannot reflect the shot and can
	# race the sweep by deleting it at the first wall.
	if int(weapon.get("bounces", 0)) == 0:
		proj.body_entered.connect(_on_projectile_hit.bind(proj))
	proj.on_sweep_hit = _on_projectile_hit
	if bool(weapon.get("heat_trait", false)):
		proj.on_finished = _on_heat_shot_finished.bind(f.get_instance_id())
	if sim_active:
		_sim_kit(f.kit.name).p_spawn += 1
	add_child(proj)

## One Slalom shot. `curve_sign` mirrors the weave, so a pair leaves together,
## bows to opposite sides, and crosses back onto the aim line at the gate. The
## curve itself lives in Projectile; the geometry is documented on the kit.
func _spawn_slalom_shot(f: Fighter, weapon: Dictionary, unit: Vector3,
		curve_sign: float, weave: Dictionary) -> void:
	var proj := Projectile.new()
	proj.weapon = weapon
	proj.damage = int(weapon.damage * f.damage_multiplier())
	proj.owner_fighter = f
	proj.direction = unit
	proj.curve_sign = curve_sign
	proj.curve_period = weave.period
	proj.curve_deg = weave.curve_deg
	# Both are per SHOT, not per weapon: the aim distance chose this weave, and
	# `range` on the kit is only the top of a band.
	proj.reach = weave.reach
	# Both shots leave the muzzle, not offset lanes: the split has to come from
	# the curve, or the first metre reads as a shotgun spread instead.
	proj.position = f.global_position + unit * (Kits.FIGHTER_RADIUS + 0.25) + Vector3(0, 1.0, 0)
	proj.origin = proj.position
	proj.body_entered.connect(_on_projectile_hit.bind(proj))
	proj.on_sweep_hit = _on_projectile_hit
	if sim_active:
		_sim_kit(f.kit.name).p_spawn += 1
	add_child(proj)

func _spawn_button_burst(f: Fighter, weapon: Dictionary, unit: Vector3) -> void:
	var labels := ["A", "B", "X", "Y", "LB", "RB"]
	var colors := [Color(0.25, 0.9, 0.35), Color(0.95, 0.22, 0.2),
			Color(0.22, 0.55, 1.0), Color(1.0, 0.82, 0.18),
			Color(0.72, 0.38, 0.95), Color(0.2, 0.9, 0.9)]
	# Six quick launches read as a button mash rather than one shotgun blast.
	# Every button flies along the one `unit` captured when the trigger was
	# pulled, so a button leaving late is aimed where the target was that much
	# earlier — which is what used to cap this at 0.035s: at 0.06s apart the
	# last one flew 0.30s stale, ~1m of drift against ~0.65m of hittable width.
	# Both halves of that changed. Fighters now move at 4.0 m/s instead of 7.0
	# and are 1.30m wide, so at the kit's 0.05s the last button is 0.25s stale
	# = 1.0m of drift against 2.02m of hit width. Capture the fighter by ID: it
	# may be freed before a delayed button is due to launch.
	var unload: float = float(weapon.get("unload", 0.035))
	var fighter_id := f.get_instance_id()
	for i in labels.size():
		if i == 0 or unload <= 0.0:
			_launch_button_shot(fighter_id, weapon, unit, labels[i], colors[i], i)
		else:
			get_tree().create_timer(unload * i).timeout.connect(_launch_button_shot.bind(
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
	if sim_active:
		_sim_kit(f.kit.name).p_spawn += 1
	add_child(proj)

func _on_projectile_hit(body: Node3D, proj: Projectile) -> void:
	if not is_instance_valid(proj):
		return
	if body is Fighter:
		if body == proj.owner_fighter or body.is_dead() or proj.already_hit.has(body):
			return
		proj.already_hit.append(body)
		proj.hit_fighter = true
		if sim_active and is_instance_valid(proj.owner_fighter):
			_sim_kit(proj.owner_fighter.kit.name).p_fighter += 1
		deal_damage(proj.damage, body, _live(proj.owner_fighter), proj.direction, proj.weapon.knockback)
		if authoritative and proj.weapon.has("burn_duration") and not body.is_dead():
			body.ignite(now, float(proj.weapon.burn_duration),
					int(proj.weapon.burn_tick_damage), _live(proj.owner_fighter))
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
			sfx_at("wall_break", body.global_position, 1.0)
			arena.open_at(body.global_position)
			body.queue_free()
	elif not body.is_in_group("water"):
		if sim_active and is_instance_valid(proj.owner_fighter):
			_sim_kit(proj.owner_fighter.kit.name).p_scenery += 1
		proj.queue_free()

func _on_heat_shot_finished(hit_fighter: bool, fighter_id: int) -> void:
	if not authoritative:
		return
	var shooter := instance_from_id(fighter_id)
	if shooter is Fighter and is_instance_valid(shooter) and not shooter.is_dead():
		if hit_fighter:
			shooter.register_heat_hit(now)
		else:
			shooter.register_heat_miss(now)

func _update_burns() -> void:
	if not authoritative:
		return
	for f in fighters:
		if not is_instance_valid(f) or f.is_dead():
			continue
		while f.burn_tick_at > 0.0 and f.burn_tick_at <= now and f.burn_tick_at <= f.burn_until:
			f.burn_tick_at += 0.5
			deal_damage(f.burn_damage, f, _live(f.burn_source))
			if f.is_dead():
				break

## Leon's Disconnect lands in two parts: a one-off burst (damage, knockback and
## the full silence on everyone caught in it) and the field it leaves behind,
## which re-silences whoever is standing in it until it expires.
func _disconnect_lob_land(lob: Lob) -> void:
	if not is_instance_valid(lob):
		return
	var center := lob.target_pos
	var caster := _live(lob.owner_fighter)
	_spawn_shockwave(center, lob.weapon, Color(1.0, 0.2, 0.85))
	for target in fighters:
		# The silence is friendly fire like any other, and deal_damage's own
		# ally guard does not cover it — a Disconnect thrown into a scrap in
		# front of your goal was cutting your own team off with the enemy.
		if target == lob.owner_fighter or target.is_dead():
			continue
		if caster != null and caster.is_ally(target):
			continue
		var delta := target.global_position - center
		delta.y = 0
		if delta.length() <= lob.weapon.aoe + 0.5:
			deal_damage(lob.damage, target, caster, delta.normalized(), lob.weapon.knockback)
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
		zone.owner_fighter = caster
		# Kept separately from the fighter: the field outlives its caster, and
		# in Showdown the caster's node is gone the moment they die.
		zone.owner_team = caster.team if caster != null else -1
		zone.position = center
		add_child(zone)

## A landing that came down on a power cube box. Anders' sack resolves by
## landing radius rather than by collision, so boxes have to be checked
## explicitly — they were invisible to it otherwise.
func _on_sack_box_hit(box: Node, sack: HackySack) -> void:
	if sim_active and is_instance_valid(sack.owner_fighter):
		_sim_kit(sack.owner_fighter.kit.name).s_box += 1
	if is_instance_valid(sack):
		_damage_lootbox(box, sack.rally_damage())

## Diagnostics only: where every sack landing ends up.
func _on_sack_land(struck, sack: HackySack) -> void:
	if not sim_active or not is_instance_valid(sack.owner_fighter):
		return
	var k := _sim_kit(sack.owner_fighter.kit.name)
	k.s_land += 1
	if struck == sack.owner_fighter:
		k.s_catch += 1
	elif struck != null:
		k.s_hit += 1

## An enemy caught by the rally. The sack redirects itself afterwards, so this
## only has to resolve damage.
func _on_rally_sack_hit(target: Fighter, sack: HackySack) -> void:
	if not is_instance_valid(sack) or target.is_dead():
		return
	deal_damage(sack.rally_damage(), target, _live(sack.owner_fighter),
			sack.travel_dir(), sack.weapon.knockback)

## Anders got back under it. The catch is worth TEMPO: it refunds the pip so he
## can throw again immediately, steps the streak so the next throw hits harder,
## and blasts the ground at his feet. It used to kick itself back out instead,
## which is what took the controller off the player for seconds at a time.
func _on_sack_caught(sack: HackySack) -> void:
	if not is_instance_valid(sack) or not is_instance_valid(sack.owner_fighter):
		return
	var f: Fighter = sack.owner_fighter
	f.play_attack_animation(now)
	# The catch IS his reload. Dropping it is what makes him pay the real one.
	# Uncapped: damage stops climbing at MAX_RALLY but the number does not, so
	# a long run stays worth chasing for its own sake.
	f.sack_streak += 1
	f.ammo = f.max_ammo
	var tint: Color = HackySack.STREAK_TINTS[clampi(f.sack_streak,
			0, HackySack.STREAK_TINTS.size() - 1)]
	f._popup("x%d" % (f.sack_streak + 1), tint)
	# The kick hits. Every point of Anders' damage used to sit on the landings,
	# so the two hops HOME were dead air — half of his burst window producing
	# nothing, which is why his burst DPS sat at a third of the roster. Blasting
	# the ground he kicks from converts that dead half into damage and gives him
	# an answer to being dived, which a landing-only kit never had.
	var blast: float = float(sack.weapon.get("kick_aoe", 0.0))
	var dmg := sack.kick_damage()
	if blast <= 0.0 or dmg <= 0:
		return
	var ring: Dictionary = sack.weapon.duplicate()
	ring.spread_deg = 360.0
	ring.aoe = blast
	_spawn_shockwave(f.global_position, ring, Color(0.35, 1.0, 0.85))
	for other in fighters:
		if not is_instance_valid(other) or other == f or other.is_dead():
			continue
		var d := Vector2(other.global_position.x - f.global_position.x,
				other.global_position.z - f.global_position.z)
		if d.length() <= blast:
			var away := Vector3(d.x, 0.0, d.y).normalized() if d.length() > 0.01 \
					else f.facing
			deal_damage(dmg, other, f, away, float(sack.weapon.knockback))

## Pop Off's returning kick. It arcs down onto the ground he vacated and blasts
## a radius there, so it connects with whoever chased him instead of needing
## them to still be standing on one line. Snaps onto an enemy near that spot if
## one drifted, which keeps it reliable without making it home.
func _pop_off_spike(f: Fighter, weapon: Dictionary, spot: Vector3, mult: float) -> void:
	# The backflip already played across the leap. Landing transitions into the
	# kick that sends the sack down, rather than restarting a second backflip.
	f.play_attack_animation(now)
	var target := spot
	var best := SPIKE_SNAP
	for other in fighters:
		if other == f or not is_instance_valid(other) or other.is_dead():
			continue
		var d := other.global_position.distance_to(spot)
		if d < best:
			best = d
			target = other.global_position
	var spike := Lob.new()
	spike.weapon = weapon
	spike.damage = int(weapon.damage * f.damage_multiplier() * mult)
	spike.owner_fighter = f
	spike.start_pos = f.global_position + Vector3(0, 1.2, 0)
	spike.target_pos = target
	spike.on_land = _pop_off_land
	add_child(spike)

## Everyone caught in the spike is thrown outward from the impact, which is what
## makes it a peel: the diver ends up further from Anders, not on top of him.
func _pop_off_land(lob: Lob) -> void:
	var center: Vector3 = lob.target_pos
	var radius: float = float(lob.weapon.aoe) + 0.5
	# A visible blast ring at the impact, so the Super reads as an explosion
	# going off where he was rather than a sack quietly touching down.
	_spawn_shockwave(center, lob.weapon, Color(1.0, 0.85, 0.35))
	for f in fighters:
		if not is_instance_valid(f) or f == lob.owner_fighter or f.is_dead():
			continue
		var away := f.global_position - center
		away.y = 0.0
		var gap := away.length()
		if gap > radius:
			continue
		# Peel outward from ANDERS, not from the impact spot. He leapt AWAY from
		# `center`, so anyone standing between the two was being shoved along
		# (them - center) — straight onto him. The Super exists to make space
		# and it was closing it: jump clear, then pull the diver after you.
		var push := Vector3.FORWARD
		if is_instance_valid(lob.owner_fighter):
			var from_him := f.global_position - lob.owner_fighter.global_position
			from_him.y = 0.0
			if from_him.length() > 0.05:
				push = from_him.normalized()
			elif gap > 0.05:
				push = away.normalized()
		elif gap > 0.05:
			push = away.normalized()
		# Splash falloff: full damage at the centre, 55% at the rim. Landing it
		# on someone is still worth more than catching them in the edge.
		var falloff: float = lerpf(1.0, 0.55, clampf(gap / maxf(radius, 0.01), 0.0, 1.0))
		deal_damage(int(lob.damage * falloff), f, _live(lob.owner_fighter),
				push, lob.weapon.knockback)
	# Power cube boxes are caught by the blast too.
	for box in get_tree().get_nodes_in_group("lootbox"):
		if is_instance_valid(box) and box.global_position.distance_to(center) <= radius:
			_damage_lootbox(box, lob.damage)

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
		deal_damage(dmg, target, f, unit, weapon.knockback, "melee_hit")
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
	if not authoritative or not is_instance_valid(box) or box.is_queued_for_deletion() \
			or box.get_meta("broken", false):
		return
	var hp: int = box.get_meta("health") - amount
	box.set_meta("health", hp)
	if hp > 0 and net_host:
		_net_box_damaged.rpc(String(box.name), hp)   # keeps client bars honest
	if hp <= 0:
		# A projectile's sweep and Area3D signal (or several AOE callbacks) can
		# report the fatal hit in the same physics frame. queue_free() does not
		# remove the box until that frame ends, so make destruction one-shot
		# before spawning its drop.
		box.set_meta("broken", true)
		box.remove_from_group("lootbox")
		sfx_at("box_break", box.global_position, 2.0)
		var pos: Vector3 = box.global_position - Vector3(0, 0.5, 0)
		var box_name := String(box.name)
		box.queue_free()
		_spawn_cube(pos, _cube_seq)
		if net_host:
			_net_box_broken.rpc(box_name, _cube_seq, pos)
		_cube_seq += 1

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
			if zone.owner_team >= 0 and f.team == zone.owner_team:
				continue   # your own field does not silence your own team
			if zone.contains(f.global_position):
				f.apply_disconnect(now, DisconnectZone.TAIL)

func _update_dashes(delta: float) -> void:
	for f in fighters:
		if not f.is_dashing():
			continue
		var d: Dictionary = f.dash
		var riding: bool = f.is_riding()
		if riding:
			d.elapsed += delta
		else:
			d.remaining -= d.weapon.speed * delta
		if arena.tile_at(f.global_position) == "~":
			d.crossed_water = true
		var from: Vector3 = d.get("last_pos", f.global_position)
		for enemy in fighters:
			if enemy == f or enemy.is_dead() or d.hit.has(enemy):
				continue
			# A ride sweeps its contact test over the whole frame's travel. At
			# 11.7 m/s under NS3_SIM's 10x time scale a fighter advances ~2 m a
			# tick, so the point test a dash uses would skate straight through
			# people — the same tunnelling projectile.gd already sweeps for.
			var gap: float = Geometry3D.get_closest_point_to_segment(
					enemy.global_position, from, f.global_position
					).distance_to(enemy.global_position) if riding \
					else f.global_position.distance_to(enemy.global_position)
			if gap < 1.3:
				d.hit.append(enemy)
				var mult: float = d.weapon.water_mult if d.crossed_water else 1.0
				deal_damage(int(d.weapon.damage * mult * f.damage_multiplier()),
							enemy, f, _ride_shove(d, f, enemy) if riding else d.direction,
							d.weapon.knockback)
		var over_water := arena.tile_at(f.global_position) == "~"
		if riding:
			d.last_pos = f.global_position
			# Never end over water — the ride crosses it on skis, and dropping
			# the normal collision mask back on mid-river would strand him. The
			# grace cap is the same escape hatch a dash uses.
			var spent: bool = d.elapsed >= float(d.duration)
			if spent and (not over_water or d.elapsed > float(d.duration) + 1.5):
				f.end_dash()
				_snow_spray(f, d.weapon)
			continue
		if d.remaining <= 0.0 and not over_water:
			f.end_dash()
		elif d.remaining < -4.0 * Kits.TILE:
			f.end_dash()

## Which way a Downhill victim gets thrown. "Pushes them aside", not "punts them
## down the hill": mostly along the run, plus a lateral kick to whichever side
## they were already on, so bodies are cleared out of the lane instead of being
## pinned in front of the skis for the rest of the ride.
func _ride_shove(d: Dictionary, f: Fighter, enemy: Fighter) -> Vector3:
	var run: Vector3 = d.direction
	var side := Vector3(-run.z, 0, run.x)
	var offset: float = side.dot(enemy.global_position - f.global_position)
	return (run + side * (1.2 if offset >= 0.0 else -1.2)).normalized()

## The tail of Downhill: a spray of snow that slows but does not damage. All of
## the Super's damage is on the bodies the run hit, so the spray is pure utility
## and is already paid for by the 1.4x multiplier on the kit.
func _snow_spray(f: Fighter, weapon: Dictionary) -> void:
	_spawn_shockwave(f.global_position, weapon, Color(0.86, 0.95, 1.0))
	if not authoritative:
		return   # visual on clients; the host owns the slow
	for target in fighters:
		if target == f or target.is_dead() or f.is_ally(target):
			continue
		var offset := target.global_position - f.global_position
		offset.y = 0
		if offset.length() <= float(weapon.aoe) + 0.5:
			target.apply_slow(now, float(weapon.get("slow_seconds", 1.5)),
					float(weapon.get("slow_factor", 0.6)))

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
			if int(leap.weapon.style) == Kits.Style.POP_OFF:
				# Spiked at the SPOT he jumped away from, not along a line back
				# toward it. The leap takes half a second, in which whoever
				# dived him walks several metres off any fixed vector — aiming a
				# thin projectile down it was very nearly unlandable.
				_pop_off_spike(f, leap.weapon, start, float(leap.get("spike_mult", 1.0)))
			else:
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
	if arena.tile_at(target.global_position) == "b" and dist > Kits.BUSH_REVEAL:
		return false
	return through_walls or has_line_of_sight(viewer.global_position, target.global_position)

func nearest_visible_enemy(viewer: Fighter, within: float, through_walls := false) -> Fighter:
	var best: Fighter = null
	var best_d := INF
	for f in fighters:
		if f == viewer or f.is_dead() or viewer.is_ally(f):
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
	# KEEP_IT_UP arcs over walls now, so it picks targets through them too.
	return style == Kits.Style.LOB or style == Kits.Style.DISCONNECT \
			or style == Kits.Style.KEEP_IT_UP

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
	return gas.safe_center() if gas else arena.centre()

## Whether the ring has actually started closing. Bots herding a target toward
## the gas read this rather than `gas_depth` alone: before the first shrink
## `depth_inside` measures to the MAP edge, so without it a bot would spend the
## opening of every match pressing opponents against an arena wall that does
## nothing to them.
func gas_closing() -> bool:
	return gas != null and gas.inset > 0

# MARK: match flow

func _eliminate(f: Fighter, killer: String, left_game := false) -> void:
	# Ahead of the Cup branch: a Cup death is a setback rather than an exit, but
	# it still wants the sound.
	sfx_at("elimination", f.global_position, 3.0)
	# How long they lasted, for the results card. Not set in Nobles Cup, where a
	# death is a three-second setback and "survived" means nothing.
	if cup == null:
		f.stats.survived = maxf(0.0, now - match_start)
	if cup != null:
		# Your own death is the only one that gets the wash and the counter, and
		# only when there is something to count to — overtime books no respawn.
		if f == player and not cup.overtime:
			_down_until = now + CupMode.RESPAWN_SECONDS
		# Nobles Cup: the fighter is parked and comes back, and the roster it
		# was counted in never shrinks, so none of the Showdown flow applies.
		cup.on_death(f, killer)
		return
	var rank := fighters.size()
	if net_host:
		_net_eliminate.rpc(net_fighters.find(f), killer, rank, left_game)
	_drop_cubes(f)
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
			_net_show_results(rank, false, f)
		if fighters.size() <= 1:
			_net_finish()
		return
	if f == player:
		_end_match(rank, false)
	elif fighters.size() == 1 and fighters[0] == player:
		_end_match(1, true)

## A fallen fighter puts half of what it was carrying back on the floor,
## rounded up, so killing a loaded fighter is worth chasing without handing the
## whole match's cubes to one player.
func _drop_cubes(f: Fighter) -> void:
	if not authoritative or f.cubes <= 0:
		return
	var drop := int(ceil(f.cubes / 2.0))
	f.cubes = 0
	var origin := f.global_position
	for i in drop:
		var angle := TAU * float(i) / float(drop) + randf() * 0.7
		var pos := _cube_drop_spot(origin, angle, 0.0 if drop == 1 else 1.0)
		_spawn_cube(pos, _cube_seq)
		if net_host:
			_net_cube_dropped.rpc(_cube_seq, pos)
		_cube_seq += 1

## Scattering the drop can push a cube through the wall a fighter died against,
## where nothing could ever pick it up. Walk the offset back toward the death
## spot until it lands somewhere walkable.
func _cube_drop_spot(origin: Vector3, angle: float, radius: float) -> Vector3:
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var r := radius
	while r > 0.05:
		var p := origin + dir * r
		if not arena.blocks_movement(p):
			return p
		r -= 0.3
	return origin

func _elim_feed_text(who: String, killer: String, left_game: bool) -> String:
	if left_game:
		return "%s left the game" % who
	if killer != "":
		return "%s eliminated %s" % [killer, who]
	return "%s died in the gas" % who

func _end_match(rank: int, victory: bool) -> void:
	phase = Phase.ENDED
	if _music != null and _music.playing:
		var fade := _music.create_tween()
		fade.tween_property(_music, "volume_db", -40.0, 1.6)
		fade.tween_callback(_music.stop)
	center_label.text = ""
	move_stick.release()
	aim_stick.release()
	super_stick.release()
	sfx_ui("victory" if victory else "defeat", 2.0)
	# A winner is still standing, so their clock stops here; a loser's was
	# stopped by _eliminate on the way in.
	if player != null and is_instance_valid(player) and not player.is_dead():
		player.stats.survived = maxf(0.0, now - match_start)
	var award: Dictionary = SaveGame.award_match(player.kit.name, rank)
	_show_results(1 if victory else -1, "You placed #%d of 10" % rank,
			str(player.kit.name), award, _showdown_rows(player), authoritative)

## Called by CupMode when the whistle goes. Nobles Cup has no placement, so it
## borrows Showdown's reward curve at the ranks that pay what a 3v3 result
## should: a win like a Showdown win, a draw mid-table, a loss just under the
## break-even rank.
func end_cup_match(blue: int, red: int) -> void:
	phase = Phase.ENDED
	center_label.text = ""
	move_stick.release()
	aim_stick.release()
	super_stick.release()
	var won := blue > red
	var drew := blue == red
	sfx_ui("victory" if won else "defeat", 2.0)
	var award: Dictionary = SaveGame.award_match(player.kit.name, 1 if won else (5 if drew else 9))
	_show_results(1 if won else (0 if drew else -1), "%d — %d" % [blue, red],
			str(player.kit.name), award, [], authoritative,
			_cup_scoreboard([blue, red]))

## Nobles Cup's end card: a TEAM SCOREBOARD, both sides, every player — the way
## Brawl Stars ends a Brawl Ball match. It replaced a four-row personal table,
## which said what you did and nothing about the five people you did it with.
##
## This is only possible in Cup. `fighters` never shrinks there, because a death
## parks the fighter rather than freeing it, so all six are still present at the
## whistle with their stats intact. Showdown FREES a fighter on elimination, so
## by the time its results card is built most of the roster is gone — which is
## why the two modes cannot share this layout, and why Showdown keeps the
## portrait-and-stat-table body.
##
## Survival is not a column: it is meaningless where death costs three seconds.
## Neither is SAVES, for the reason the old table carried — measured with
## NS3_SAVE_LOG=1 the ball changes hands about seven times a match and nearly
## every one is a team collecting its own forward pass, so the column would read
## 0 for all six. `Fighter.stats.saves` and `CupMode._is_save` stay maintained.
func _cup_scoreboard(score: Array) -> Control:
	var board: HBoxContainer = MenuUI.hbox(16)
	for team in 2:
		board.add_child(_cup_team_column(team, int(score[team])))
	return board

## Width of one stat cell. Fixed rather than shrink-to-fit so the three columns
## line up down the card however wide the damage number gets.
const CUP_STAT_W := 54.0
## Matches MenuUI.dark_panel's internal padding, so the key line above the rows
## sits over the numbers rather than 8px off them.
const CUP_ROW_PAD := 8

func _cup_team_column(team: int, goals: int) -> Control:
	var tint: Color = Arena.TEAM_COLORS[team]
	var column: VBoxContainer = MenuUI.vbox(6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head: PanelContainer = MenuUI.dark_panel(11, 0.44, CUP_ROW_PAD)
	var head_line: HBoxContainer = MenuUI.hbox(8)
	head.add_child(head_line)
	# Named by side rather than by colour: "YOUR TEAM" is what the player needs
	# to find first, and team 0 is always theirs in single-player Cup.
	var side: Label = MenuUI.display("YOUR TEAM" if team == 0 else "OPPONENTS", 20, tint, 4)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_line.add_child(side)
	head_line.add_child(MenuUI.display(str(goals), 30, Color.WHITE, 5))
	column.add_child(head)

	column.add_child(_cup_column_key())
	for f: Fighter in _cup_team_fighters(team):
		column.add_child(_cup_player_row(f, tint))
	return column

## One team's fighters, best contribution first, so whoever decided the match is
## at the top of their column. Goals outrank damage: a striker who scored once
## and dealt little did more than a team-mate who chipped away and did not.
func _cup_team_fighters(team: int) -> Array:
	var out: Array = []
	for f: Fighter in fighters:
		if is_instance_valid(f) and f.team == team:
			out.append(f)
	out.sort_custom(func(a: Fighter, b: Fighter) -> bool:
		if int(a.stats.goals) != int(b.stats.goals):
			return int(a.stats.goals) > int(b.stats.goals)
		return int(a.stats.damage) > int(b.stats.damage))
	return out

func _cup_column_key() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", CUP_ROW_PAD)
	margin.add_theme_constant_override("margin_right", CUP_ROW_PAD)
	var line: HBoxContainer = MenuUI.hbox(8)
	margin.add_child(line)
	line.add_child(MenuUI.spacer())
	for key: String in ["G", "K", "DMG"]:
		var l: Label = MenuUI.body(key, 14, MenuUI.TEXT_DIM, true)
		l.custom_minimum_size = Vector2(CUP_STAT_W, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(l)
	return margin

func _cup_player_row(f: Fighter, tint: Color) -> Control:
	var you: bool = f == player
	# Your own row is lifted out of its column with a brighter plate and a white
	# name, so you can find yourself in six without reading the names.
	var row: PanelContainer = MenuUI.dark_panel(10, 0.52 if you else 0.30, CUP_ROW_PAD)
	var line: HBoxContainer = MenuUI.hbox(8)
	row.add_child(line)
	line.add_child(_cup_face(f, tint))
	var name_l: Label = MenuUI.body(str(f.display_name).to_upper(), 17,
			Color.WHITE if you else MenuUI.TEXT_SOFT, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name_l)
	line.add_child(_cup_stat(str(int(f.stats.goals))))
	line.add_child(_cup_stat(str(int(f.stats.kills))))
	line.add_child(_cup_stat(MenuUI.fmt(int(f.stats.damage))))
	return row

func _cup_stat(text: String) -> Label:
	var l: Label = MenuUI.display(text, 20, Color.WHITE, 4)
	l.custom_minimum_size = Vector2(CUP_STAT_W, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## A row's portrait chip, on its team colour. Same fallback as the big card:
## a kit with no rendered portrait (Nova, Ayaan) shows its initial in kit colour.
func _cup_face(f: Fighter, tint: Color) -> Control:
	var holder: Panel = MenuUI.card("dark", 9, 3)
	holder.custom_minimum_size = Vector2(38, 38)
	holder.add_child(MenuUI.card_backdrop(Color(tint.r, tint.g, tint.b, 0.34)))
	var kit_name: String = str(f.kit.name)
	var tex: Texture2D = MenuData.portrait(kit_name.to_lower())
	if tex != null:
		var pr := TextureRect.new()
		pr.texture = tex
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pr)
	else:
		var initial: Label = MenuUI.display(kit_name.substr(0, 1).to_upper(), 22,
				f.kit.get("color", Color.WHITE), 4)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(initial)
	return holder

func _update_players_label() -> void:
	# Nobles Cup shows a score and a clock instead; CupMode owns those labels.
	players_label.text = "" if cup != null else "%d LEFT" % fighters.size()

# MARK: balance sim (NS3_SIM)

func _sim_kit(kit_name: String) -> Dictionary:
	if not sim_stats.has(kit_name):
		sim_stats[kit_name] = {"spawns": 0, "wins": 0, "kills": 0,
				"damage": 0, "placement_sum": 0, "attacks": 0, "hits": 0,
				"p_spawn": 0, "p_fighter": 0, "p_scenery": 0,
				"s_launch": 0, "s_land": 0, "s_hit": 0, "s_catch": 0, "s_blocked": 0, "s_box": 0, "s_super": 0, "s_lock": 0}
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
	for n in names:
		var sk: Dictionary = sim_stats[n]
		if sk.s_launch == 0:
			continue
		print("\n[sim] sacks: launched %d (blocked %d) -> landings %d = %d on an enemy, %d caught, %d on floor" \
				% [sk.s_launch, sk.s_blocked, sk.s_land, sk.s_hit, sk.s_catch,
					sk.s_land - sk.s_hit - sk.s_catch])
		print("[sim] sack landings on power cube boxes: %d" % sk.s_box)
		print("[sim] Pop Off used %d times (%d while ammo was still locked)" % [sk.s_super, sk.s_lock])
	print("\n[sim] projectile fates (spawned -> fighter / scenery / flew past):")
	for n in names:
		var s2: Dictionary = sim_stats[n]
		if s2.p_spawn == 0:
			continue
		var tot: float = float(s2.p_spawn)
		print("%-8s spawned %5d  fighter %5.1f%%  scenery %5.1f%%  past %5.1f%%" % [n,
				s2.p_spawn, 100.0 * s2.p_fighter / tot, 100.0 * s2.p_scenery / tot,
				100.0 * (s2.p_spawn - s2.p_fighter - s2.p_scenery) / tot])

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
				var elapsed: float = now - phase_at
				var remaining: float = (PREMATCH if versus != null else 3.5) - elapsed
				if remaining <= 0.0:
					phase = Phase.PLAYING
					match_start = now
					_hide_versus()
					center_label.text = "FIGHT!"
					sfx_ui("count_go", 3.0)
					get_tree().create_timer(0.8).timeout.connect(func() -> void:
						if phase == Phase.PLAYING:
							center_label.text = "")
					if cup == null:      # the pitch has no gas closing in
						gas = GasRing.new()
						add_child(gas)
						gas.start(now, arena.columns)
				elif versus != null and is_instance_valid(versus):
					versus.update(int(ceil(PREMATCH_INTRO_AT - elapsed)), elapsed / PREMATCH,
							elapsed >= PREMATCH_INTRO_AT)
					_count_beep(int(ceil(PREMATCH_INTRO_AT - elapsed)))
				else:
					center_label.text = str(int(ceil(remaining)))
					_count_beep(int(ceil(remaining)))
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

	# The match is heard from wherever the player is; once they are gone it
	# stays where they fell rather than snapping to the origin.
	if player != null and is_instance_valid(player) and not player.is_dead():
		_listener = player.global_position
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
	# Holding the ball replaces the weapon's aimer with the ball's own path.
	# The kick is a different action with a different reach, and it banks off
	# walls, so drawing the weapon lane here would preview an attack the player
	# cannot currently make and hide the one they can.
	if cup != null and cup.ball.carrier == player:
		var powerful := use_super and player.is_super_ready()
		var kick_dir := Vector3(stick.value.x, 0, stick.value.y).normalized()
		var from := Vector3(cup.ball.position.x, 0.08, cup.ball.position.z)
		var tint: Color = SUPER_KICK_AIM_COLOR if powerful else KICK_AIM_COLOR
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		im.surface_set_color(tint)
		for segment in _aim_bounce_segments(from, kick_dir,
				Ball.kick_range(Ball.SUPER_KICK_MULT if powerful else 1.0), 2, Ball.BOUNCE):
			_aim_add_segment(im, segment[0], segment[1], Ball.RADIUS, tint)
		im.surface_end()
		return

	var weapon: Dictionary = player.kit["super"] if use_super else player.kit.weapon
	var color := Color(1.0, 0.7, 0.2, 0.4) if use_super else Color(1, 1, 1, 0.3)
	var origin := player.global_position + Vector3(0, 0.08, 0)
	var dir := Vector3(stick.value.x, 0, stick.value.y).normalized()
	var style := int(weapon.style)
	var bouncing := int(weapon.get("bounces", 0)) > 0
	var targeted := style == Kits.Style.LOB or style == Kits.Style.JUMP_SMASH \
			or style == Kits.Style.DISCONNECT or style == Kits.Style.KEEP_IT_UP
	var cone := style == Kits.Style.MELEE or style == Kits.Style.SHOCKWAVE \
			or style == Kits.Style.BUTTONS \
			or (style == Kits.Style.PELLETS and int(weapon.pellets) > 1 \
					and float(weapon.spread_deg) > 0.0)
	var target_dist: float = clamp(stick.value.length() * weapon.range,
			Kits.TILE if style == Kits.Style.JUMP_SMASH else Kits.TILE * 1.5, weapon.range)

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(color)
	if bouncing:
		for segment in _aim_bounce_segments(origin, dir, float(weapon.range),
				int(weapon.bounces)):
			_aim_add_segment(im, segment[0], segment[1],
					maxf(float(weapon.radius), 0.16), color)
	elif targeted:
		# Targeted attacks use an impact-zone marker rather than a misleading
		# cone. Orbit attacks show the area around the fighter instead.
		var center := origin + dir * target_dist
		var radius: float = weapon.aoe
		for i in 24:
			var a0 := TAU * i / 24.0
			var a1 := TAU * (i + 1) / 24.0
			im.surface_add_vertex(center)
			im.surface_add_vertex(center + Vector3(cos(a0), 0, sin(a0)) * radius)
			im.surface_add_vertex(center + Vector3(cos(a1), 0, sin(a1)) * radius)
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
	elif style == Kits.Style.SLALOM:
		# Draw the real weave, both lanes, for the shot this drag would fire —
		# how wide it carves, where the pair meets, and how far that leaves it
		# able to reach. All three move together and all three are the point, so
		# a straight lane would hide the whole weapon.
		#
		# The RAW drag reach, not `target_dist`: `slalom_weave` applies the kit's
		# own floor, and _release_fire hands the shot this same unclamped number,
		# so anything else here would draw a weave that is not the one fired.
		var weave: Dictionary = Kits.slalom_weave(weapon,
				stick.value.length() * float(weapon.range))
		for curve_sign in [1.0, -1.0]:
			_aim_add_ribbon(im, _slalom_path(origin, dir, weapon, curve_sign, weave),
					maxf(float(weapon.radius), 0.16), color)
	elif style == Kits.Style.DOWNHILL:
		# The run is steered, so the lane is only where it STARTS. Draw the aim
		# reach rather than the full 11-tile ride, which would leave the screen
		# and read as a weapon range it is not. Body-width, because it is a body.
		_aim_add_segment(im, origin, origin + dir * float(weapon.range),
				Kits.FIGHTER_RADIUS, color)
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

## A continuous band along a polyline. Chaining `_aim_add_segment` would work,
## but each quad would overlap its neighbour at the joint and the alpha would
## stack into a bright dot on every bend; sharing the seam edge keeps the weave
## one even ribbon.
func _aim_add_ribbon(im: ImmediateMesh, points: PackedVector3Array,
		half_width: float, color: Color) -> void:
	if points.size() < 2:
		return
	im.surface_set_color(color)
	var prev_side := Vector3.ZERO
	for i in points.size() - 1:
		var travel := points[i + 1] - points[i]
		travel.y = 0.0
		if travel.length_squared() < 0.000001:
			continue
		var side := Vector3(travel.z, 0, -travel.x).normalized() * half_width
		if prev_side == Vector3.ZERO:
			prev_side = side
		im.surface_add_vertex(points[i] - prev_side)
		im.surface_add_vertex(points[i + 1] - side)
		im.surface_add_vertex(points[i + 1] + side)
		im.surface_add_vertex(points[i] - prev_side)
		im.surface_add_vertex(points[i + 1] + side)
		im.surface_add_vertex(points[i] + prev_side)
		prev_side = side

## The path a Slalom shot actually flies, sampled for the aim indicator. It
## integrates the same heading law Projectile does and spends its range down the
## aim line the same way, so the drawing and the shot cannot drift apart.
func _slalom_path(origin: Vector3, dir: Vector3, weapon: Dictionary,
		curve_sign: float, weave: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array([origin])
	var curve_rad := deg_to_rad(float(weave.curve_deg))
	var omega: float = TAU / maxf(0.05, float(weave.period))
	var speed: float = float(weapon.speed)
	var reach: float = float(weave.reach)
	# The physics tick and the midpoint sample, exactly as Projectile flies it.
	# The ribbon is a promise about where the pair crosses, so it integrates the
	# same way rather than more accurately.
	var step := 1.0 / 60.0
	var axial := 0.0
	var point := origin
	var t := 0.0
	while axial < reach and t < 3.0:
		var motion := dir.rotated(Vector3.UP,
				curve_rad * curve_sign * cos(omega * (t + step * 0.5))) * speed * step
		axial += motion.dot(dir)
		point += motion
		points.append(point)
		t += step
	return points

## `decay` shortens what is left of the path at every bounce. Projectiles keep
## their speed off a wall and leave it at 1.0; the ball does not, so its preview
## passes Ball.BOUNCE and the drawn path ends where the real one stops.
func _aim_bounce_segments(origin: Vector3, direction: Vector3,
		total_distance: float, bounces: int, decay := 1.0) -> Array:
	var segments: Array = []
	var start := origin + Vector3(0, 0.05, 0)
	var heading := direction.normalized()
	var remaining := total_distance
	for _bounce in bounces + 1:
		var finish := start + heading * remaining
		var query := PhysicsRayQueryParameters3D.create(start, finish, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			segments.append([start, finish])
			break
		var impact: Vector3 = hit.position
		segments.append([start, impact])
		remaining = (remaining - start.distance_to(impact)) * decay
		if remaining <= 0.05:
			break
		heading = heading.bounce(hit.normal).normalized()
		start = impact + heading * 0.05
	return segments

func _run_playing(delta: float) -> void:
	if _force_kill_at > 0.0 and now - match_start >= _force_kill_at and not sim_active \
			and player != null and is_instance_valid(player) and not player.is_dead():
		_force_kill_at = 0.0
		player.health = 0
		_eliminate(player, "")
	if _force_end_at > 0.0 and now - match_start >= _force_end_at and not sim_active:
		_force_end_at = 0.0
		if cup != null:
			cup.finished = true
			end_cup_match(cup.score[0], cup.score[1])
		elif player != null and is_instance_valid(player):
			_end_match(fighters.size(), fighters.size() == 1)
		return
	# In sim mode the player slot is brain-driven; skip input. After it dies
	# the node is freed while the match runs on, hence the validity guards.
	# Nobles Cup holds everyone still through the kickoff beat and once the
	# final whistle has gone; the match loop otherwise runs exactly as usual.
	var held := cup != null and cup.frozen(now)
	if held:
		for f in fighters:
			if not f.is_dead():
				f.apply_movement(Vector3.ZERO)
	if not sim_active and is_instance_valid(player) and not player.is_dead() and not held:
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
		if held or b.fighter.is_dead():
			continue      # a knocked-out fighter is waiting on its respawn
		var d := b.decide(now, self)
		b.fighter.apply_movement(d.move)
		# Carrying is the whole move set: the weapon is unavailable and the
		# Super goes into the ball, so nothing below this runs for a carrier.
		if cup != null and cup.ball.carrier == b.fighter:
			if d.kick_dir != null:
				cup.kick(b.fighter, d.kick_dir, now, bool(d.kick_super))
			continue
		if d.fire_dir != null and not b.fighter.is_dashing() and not b.fighter.is_disconnected(now):
			if d.use_super and b.fighter.consume_super():
				perform_attack(b.fighter, b.fighter.kit["super"], d.fire_dir, d.fire_dist)
			elif not d.use_super and b.fighter.consume_ammo(now):
				perform_attack(b.fighter, b.fighter.kit.weapon, d.fire_dir, d.fire_dist)

	_update_dashes(delta)
	_update_leaps(delta)
	_update_disconnect_zones()
	_update_burns()
	for f in fighters:
		f.tick(delta, now)
	if cup != null:
		cup.tick(delta, now)

	if gas:
		var vulnerable := fighters.filter(func(f): return not (god_mode and f == player))
		for f in gas.tick(now, vulnerable):
			if f == player:
				sfx_ui("gas_tick", -8.0)   # only your own burn is worth hearing
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
	if cup != null and cup.frozen(now):
		return
	var use_super: bool = weapon == player.kit["super"]
	# Last line of defence for the carrier's kick. _release_fire and
	# _auto_aim_fire resolve the aim and kick before they reach here, but every
	# player attack funnels through this call — NS3_AUTOFIRE included — and none
	# of them may fire a weapon while the ball is in hand. A Super spent here
	# goes into the ball rather than the kit.
	if cup != null and cup.kick(player, dir, now, use_super):
		return
	if net_active and not net_host:
		# Clients ask the host to fire; the attack echoes back as _net_attack.
		_net_fire.rpc_id(1, use_super, dir, dist)
		return
	if use_super:
		if player.consume_super():
			perform_attack(player, weapon, dir, dist)
	elif player.consume_ammo(now):
		perform_attack(player, weapon, dir, dist)
	elif player.ammo < 1.0 and now - _last_empty_click >= 0.3:
		# Out of ammo, as opposed to still inside the attack cooldown — the
		# cooldown blocks several times a second and clicking through it would
		# be constant. Held fire still repeats, but at a rate you can hear.
		_last_empty_click = now
		sfx_ui("empty_click", -6.0)

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
	if _kick_instead(stick_value, use_super):
		return
	var weapon: Dictionary = player.kit["super"] if use_super else player.kit.weapon
	if stick_value.length() >= TAP_THRESHOLD:
		var dir := Vector3(stick_value.x, 0, stick_value.y)
		_fire_player(weapon, dir, stick_value.length() * weapon.range)
	else:
		_auto_aim_fire(weapon, use_super)

## Where to aim so a shot MEETS a moving target rather than arriving where it
## used to be. Brawl Stars' tap-to-shoot leads; ours did not, so at range a tap
## could not hit a strafing enemy at all — the shot was off by roughly twice the
## target's own width — while bots, which have led since `bot_brain._aim_point`,
## could. Full lead, because this is the player's aim assist rather than a
## deliberately sloppy bot. Instant-hit styles (melee, shockwave) have no speed,
## fall through to a zero flight time, and aim where the target stands.
func _aim_lead(shooter: Fighter, target: Fighter, weapon: Dictionary) -> Vector3:
	var speed: float = Kits.aim_speed(weapon,
			shooter.global_position.distance_to(target.global_position))
	var flight := 0.0
	if int(weapon.style) == Kits.Style.JUMP_SMASH:
		flight = BotBrain.LEAP_FLIGHT      # a leap, not a projectile: fixed airtime
	elif speed > 0.1:
		flight = shooter.global_position.distance_to(target.global_position) / speed
	if flight <= 0.0:
		return target.global_position
	var travel := Vector3(target.velocity.x, 0.0, target.velocity.z)
	var aim := target.global_position + travel * flight
	# One refinement pass: leading moves the aim point, which changes how long
	# the shot is airborne, which moves the aim point again.
	if speed > 0.1:
		flight = shooter.global_position.distance_to(aim) / speed
		aim = target.global_position + travel * flight
	return aim

## Holding the ball swaps the attack for a kick: dragged, it goes where you
## point; tapped, CupMode picks the shot or the pass. Spending the Super here is
## the Super Shot — twice as fast and twice as far — so a charged Super while
## carrying never fires the kit's own Super.
func _kick_instead(stick_value: Vector2, use_super: bool) -> bool:
	if cup == null or cup.frozen(now) or cup.ball.carrier != player:
		return false
	var powerful := use_super and player.is_super_ready()
	var dir: Vector3 = Vector3(stick_value.x, 0, stick_value.y) \
			if stick_value.length() >= TAP_THRESHOLD else cup.kick_aim(player, powerful)
	return cup.kick(player, dir, now, use_super)

func _auto_aim_fire(weapon: Dictionary, use_super: bool) -> void:
	if _kick_instead(Vector2.ZERO, use_super):
		return
	# Pop Off is an ESCAPE, so a tapped one leaps the way Anders is already
	# running. Auto-aiming it at the nearest enemy made the tap jump him into
	# the fight he was trying to leave. Falls back to his facing when standing
	# still; drag from the button to aim it anywhere else.
	if int(weapon.get("style", -1)) == Kits.Style.POP_OFF:
		var run := Vector3(player.velocity.x, 0.0, player.velocity.z)
		var away: Vector3 = run.normalized() if run.length() > 0.5 else player.facing
		_fire_player(weapon, away, float(weapon.range))
		return
	# A Super only auto-aims at fighters — burning the charge on a loot box is
	# never what the tap meant.
	var target: Node3D = nearest_visible_enemy(player, weapon.range * 1.1, _lobbed(weapon)) \
			if use_super else auto_aim_target(player, weapon)
	if target:
		var aim: Vector3 = _aim_lead(player, target as Fighter, weapon) if target is Fighter \
				else target.global_position
		var v := aim - player.global_position
		_fire_player(weapon, v, v.length())
	elif not use_super:
		_fire_player(weapon, player.facing, weapon.range)
	elif int(weapon.get("style", -1)) == Kits.Style.DOWNHILL:
		# Downhill is travel as much as damage, so with nobody in reach a tap
		# still sets off down the hill — rotating, or leaving a fight — rather
		# than sitting on the charge. It runs the way the player is already
		# going, falling back to their facing when standing still.
		var run := Vector3(player.velocity.x, 0.0, player.velocity.z)
		_fire_player(weapon, run.normalized() if run.length() > 0.5 else player.facing,
				float(weapon.range))
	# Any other tapped Super with no target keeps its charge instead of firing
	# blind; drag from the button to aim it manually.

func _update_concealment() -> void:
	if player == null or not is_instance_valid(player):
		return
	# The bush canopy opens up around the player over the same radius that
	# decides who is concealed, so the shader and can_see() cannot drift apart.
	arena.set_reveal_center(player.global_position)
	for f in fighters:
		var in_bush := arena.tile_at(f.global_position) == "b"
		if f == player:
			f.set_concealed(in_bush, true)
		else:
			var near := f.global_position.distance_to(player.global_position) < Kits.BUSH_REVEAL
			f.set_concealed(in_bush and not near, false)

## How hard the camera chases: briskly on the player, and a slower glide while
## it is away on a goal, so a celebration pan reads as a move rather than a cut.
const CAM_FOLLOW := 0.15
const CAM_PAN := 0.055
## Somewhere other than the player to look, until `_cam_focus_until`.
var _cam_focus := Vector3.ZERO
var _cam_focus_until := -1.0
## When the local player is back on the pitch, and whether the wash is up.
var _down_until := -1.0
var _down_shown := false

## Send the camera somewhere that is not the player for a beat. Used by
## CupMode when a goal goes in: the freeze that follows already holds input, so
## nobody loses control of anything while the view is away.
func focus_camera(at: Vector3, seconds: float) -> void:
	_cam_focus = at
	_cam_focus_until = now + seconds

func _process(_delta: float) -> void:
	_update_down_overlay()
	var anchor: Vector3
	if now < _cam_focus_until:
		anchor = _cam_focus
	elif player != null and is_instance_valid(player):
		anchor = player.global_position
	else:
		return
	# Translate only — rotation is fixed at match start. Re-aiming at the
	# player every frame yaws/rolls the world whenever the camera lags a
	# strafing player.
	var target := anchor + CAMERA_OFFSET
	cam.global_position = cam.global_position.lerp(target,
			CAM_PAN if now < _cam_focus_until else CAM_FOLLOW)

func _update_status() -> void:
	if player == null or not is_instance_valid(player):
		return
	super_btn.set_charge(player.super_charge)
	status_label.text = "%s   HP %d/%d   ammo %.1f   cubes %d" % [
		player.kit.name, player.health, player.max_health, player.ammo, player.cubes]
	# A pip crossing a whole number is a shot you have got back. Watched here
	# rather than signalled from fighter.gd, which regenerates ammo for bots too
	# and has no business knowing about audio.
	var pips := int(player.ammo)
	if phase == Phase.PLAYING and pips > _last_ammo_pips:
		sfx_ui("reload_tick", -12.0)
	_last_ammo_pips = pips
	# A slow pulse under a quarter health, so the decision to break off is one
	# you can make without watching the bar.
	if phase == Phase.PLAYING and not player.is_dead() \
			and float(player.health) / maxf(1.0, float(player.max_health)) < 0.25:
		if now - _low_health_at >= 1.6:
			_low_health_at = now
			sfx_ui("low_health", -8.0)
	else:
		_low_health_at = -1.0

## One beep per second of the pre-match countdown, on the second the number on
## screen changes rather than on a timer of its own.
func _count_beep(count: int) -> void:
	if count == _last_count_beep or count <= 0 or count > 5:
		return
	_last_count_beep = count
	sfx_ui("count_beep", -2.0)

func _shot_check() -> void:
	if _shot_times.is_empty() or _shot_prefix == "":
		return
	if now >= _shot_times[0]:
		var t: float = _shot_times.pop_front()
		var img := get_viewport().get_texture().get_image()
		var out: String = Session.shot_path("%s_%d.png" % [_shot_prefix, int(t)])
		img.save_png(out)
		print("NS3_SHOTS wrote ", ProjectSettings.globalize_path(out))
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
	# Wifi play is Showdown only, so the spawn count comes from that map.
	var spawn_idx: Array = range(Arena.SHOWDOWN_MAP.count("S"))
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
				or c is HackySack or c is Ball or c is CupMode:
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
	center_label.text = ""
	feed_label.text = ""
	results.visible = false
	_update_players_label()
	_show_versus()
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
		var elapsed_c: float = now - phase_at
		if versus != null and is_instance_valid(versus):
			versus.update(int(ceil(maxf(PREMATCH_INTRO_AT - elapsed_c, 1.0))), elapsed_c / PREMATCH,
					elapsed_c >= PREMATCH_INTRO_AT)
		else:
			center_label.text = str(int(ceil(maxf(3.5 - elapsed_c, 1.0))))
	elif versus != null:
		_hide_versus()
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
					f.health, f.max_health, f.ammo, f.super_charge, f.cubes,
					f.heat_hits, maxf(0.0, f.on_fire_until - now),
					maxf(0.0, f.burn_until - now)])
	_net_snapshot.rpc(int(phase), gas.inset if gas else -1, fighters.size(), states)

## Net results overlay: unlike _end_match this never flips the phase — the
## host's sim keeps running for whoever is still alive.
func _net_show_results(rank: int, victory: bool, who: Fighter = null) -> void:
	center_label.text = ""
	move_stick.release()
	aim_stick.release()
	super_stick.release()
	if who != null and is_instance_valid(who) and not who.is_dead():
		who.stats.survived = maxf(0.0, now - match_start)
	var award: Dictionary = SaveGame.award_match(_my_kit_name, rank)
	_show_results(1 if victory else -1, "You placed #%d of %d" % [rank, _net_roster.size()],
			_my_kit_name, award, _net_rows(who), authoritative)

## A net client never runs deal_damage — every mutation is host-side and the
## client only renders snapshots — so the one line it can fill in honestly is
## the clock it keeps itself. The rest would be a column of zeros.
func _net_rows(f: Fighter) -> Array:
	if authoritative:
		return _showdown_rows(f)
	return [["SURVIVED", _fmt_clock(maxf(0.0, now - match_start))]]

## Host: one fighter (or none, if the gas closed) remains — end the match.
func _net_finish() -> void:
	phase = Phase.ENDED
	var idx := -1
	if fighters.size() == 1:
		idx = net_fighters.find(fighters[0])
	_net_match_over.rpc(idx)
	if idx >= 0 and fighters[0] == player:
		_net_show_results(1, true, player)
	elif idx >= 0 and results.visible and is_instance_valid(results_note):
		results_note.text = "%s wins!" % fighters[0].display_name
		results_note.visible = true

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
		Loading.to_menu(get_tree()))

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
	elif f.consume_ammo(now):
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
		match_start = now
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
		if s.size() >= 11:
			f.heat_hits = int(s[8])
			f.on_fire_until = now + float(s[9])
			f.burn_until = now + float(s[10])
			if float(s[10]) > 0.0 and f._burn_glow == null:
				f._setup_burn_glow()

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
			_net_show_results(1, true, player)
		elif results.visible and is_instance_valid(results_note):
			results_note.text = "%s wins!" % w.display_name
			results_note.visible = true

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
func _net_cube_dropped(cube_id: int, pos: Vector3) -> void:
	if net_host:
		return
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
			arena.open_at(w.global_position)
			w.queue_free()
			break
