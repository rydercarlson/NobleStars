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
## The three touch controls, parked on screen and colour-coded: blue walks, red
## shoots, gold is the Super. The Super's stick draws its own charge dial, so
## there is no separate Super button any more.
var move_stick: TouchStick
var aim_stick: TouchStick
var super_stick: TouchStick
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

## NS3_AUTOPLAY=1: hand the player's own fighter to a bot brain and let the match
## play itself at normal speed, HUD and all. NS3_SIM cannot do this job — it
## bolts on Showdown's gas ring and Showdown's end-of-match bookkeeping, neither
## of which a Nobles Cup match wants — and without it a Cup match run from the
## command line is a 2v3 against a player who never moves, which is over inside
## fifteen seconds and never produces the situation being watched for.
var autoplay := OS.get_environment("NS3_AUTOPLAY") != ""

## NS3_AIM_SHOW=attack|super|kick: hold the aim indicator on with nobody
## touching the screen, so it can be shot with NS3_SHOTS. `attack`/`super` draw
## the DRAG indicator at full deflection along the player's facing — a tap draws
## nothing on purpose, so there is no tap state left to shoot. See
## _update_aim_indicator.
var _aim_show := OS.get_environment("NS3_AIM_SHOW")

## Opponent usernames left to deal this match; refilled and reshuffled by
## next_bot_name(). Emptied by start_match so a rematch cannot repeat a name
## inside one lobby by carrying the tail of the previous shuffle into it.
var _name_pool: Array = []

# Wifi play (see net_play.gd): host-authoritative. The host runs the sim
# exactly like single-player; clients send stick input up and render the
# snapshots/events the host broadcasts. `authoritative` is false only on
# clients — it gates every mutation (damage, loot, walls) so client-side
# projectiles and melee arcs stay purely visual.
const NET_WAIT_TIMEOUT := 6.0     # start anyway if a client stalls loading
## How far behind the host a client draws everyone else. Two and a half
## snapshots at 30 Hz: enough slack that one late or dropped packet is covered
## by the buffer rather than showing as a freeze followed by a jump, and short
## enough that shooting where a body is drawn still hits it at LAN latency. This
## is a fixed delay ON TOP of the link's own — buying it back by shrinking this
## buys the stutter back with it.
const NET_INTERP_DELAY := 0.085
## Longest a starved buffer carries a puppet on the velocity of its last two
## samples before it simply holds. Past this, extrapolation reads as a fighter
## skating through a wall, which is worse than a fighter standing still.
const NET_EXTRAP_MAX := 0.12
## Reconciliation thresholds for the client's own fighter. Under TOLERANCE the
## host and the local prediction agree closely enough to leave alone — replaying
## every frame to chase three centimetres is pure cost. Over HARD_SNAP something
## happened that the client could not have predicted (a knockback, a dash, a
## respawn), and easing across that distance is a fighter swimming to their new
## position rather than being put there.
const NET_PRED_TOLERANCE := 0.05
const NET_PRED_HARD_SNAP := 2.5
## How fast a reconciliation offset bleeds off, per second. 12 puts a 30 cm
## correction under a centimetre inside a quarter of a second.
const NET_PRED_FIX_RATE := 12.0
## Inputs kept for replay, and the most that will ever be replayed on one frame.
## The cap is what stops a client that stalled for two seconds from paying for
## it with a hundred move_and_slide calls on the frame it comes back.
const NET_INPUT_HISTORY := 128
const NET_REPLAY_MAX := 30
## Host-side input buffer: one input is consumed per physics tick, so a pair
## that arrive in the same frame are not thrown away. Past this the client is
## running ahead of us and the backlog is dropped rather than replayed late.
const NET_INPUT_QUEUE_MAX := 3
## Snapshot wire format: positions in centimetres. The Showdown map is 78 m
## across and world coordinates start at zero, so u16 covers it with room over.
const NET_POS_SCALE := 100.0
## Nobles Cup's trailer on a snapshot: carrier index, ball x/z, both scores, the
## match clock, the kickoff freeze remaining, and a flags byte. Absent entirely
## in Showdown, which is why the decoder tests for it by length.
## Snapshot header: host clock, phase, gas inset, fighters left, the living mask,
## and how far into the countdown the host is. Named because it is the base
## offset three separate places index from.
const NET_HEADER_BYTES := 11
const NET_CUP_BYTES := 11
## Fixed-point divisor for the gas inset in a snapshot. The inset is in TILES and
## eases fractionally between steps, so it cannot ride as the plain integer it
## once was. 1/256th of a tile is far finer than the ~2 cm a pixel covers at the
## match camera, and the widest ring this game builds (half of a 39-tile map)
## comes to 2560 — an order of magnitude inside the s16 it is packed into.
const NET_INSET_SCALE := 256.0

var net_active := false
var net_host := false
var authoritative := true
var net_fighters: Array = []      # roster index -> Fighter (freed after death)
var _net_roster: Array = []
var _my_kit_name := ""            # for trophies after `player` is freed
var _my_idx := -1                 # my own roster index, for acks and prediction
var _match_ready := false         # roster applied, arena built
var _match_seq := 0               # dedupes re-sent _net_start RPCs
var _net_seen_seq := 0
var _net_ready_peers: Dictionary = {}
var _peer_inputs: Dictionary = {}     # peer_id -> {seq, move, face} last applied
var _peer_queue: Dictionary = {}      # peer_id -> Array of pending inputs
var _next_ready_send := 0.0
var _cube_seq := 0
var _snap_tick := 0

# Client-side replication state (see the wifi play section at the bottom).
var _snap_buf: Array = []         # decoded snapshots, ascending by host time
var _snap_intake: Array = []      # arrived this frame, not yet buffered
var _snap_applied_t := -1.0       # host time of the last snapshot whose discrete half ran
var _host_offset := 0.0           # local `now` minus host `now`, min-filtered
var _clock_synced := false
var _input_seq := 0
var _pred_pos := Vector3.ZERO     # the reconciled prediction; the body is drawn at
var _pred_error := Vector3.ZERO   # this plus the correction still bleeding off
var _pred_hist: Array = []        # [[seq, move, resulting position], ...] oldest first
var _my_net_stats: Dictionary = {}   # what the host says I did, for the results card
## The host's countdown, and the local instant it was heard at. -1 until the
## first snapshot arrives, when the client falls back to its own clock.
var _net_count_elapsed := 0.0
var _net_count_at := -1.0
var _rematch_wanted: Dictionary = {} # host: peers that asked for another match
var results_wait: Label              # the rematch line on the results card

# NS3_NET_LAG / NS3_NET_JITTER (ms) and NS3_NET_LOSS (0-1) fake a worse link
# than a LAN so interpolation and prediction can actually be seen working.
# Applied on both sides: the host delays inbound inputs, the client delays
# inbound snapshots, so setting it on both instances is a full round trip.
var _net_lag := float(OS.get_environment("NS3_NET_LAG")) / 1000.0 \
		if OS.get_environment("NS3_NET_LAG") != "" else 0.0
var _net_jitter := float(OS.get_environment("NS3_NET_JITTER")) / 1000.0 \
		if OS.get_environment("NS3_NET_JITTER") != "" else 0.0
var _net_loss := float(OS.get_environment("NS3_NET_LOSS")) \
		if OS.get_environment("NS3_NET_LOSS") != "" else 0.0
var _net_stats_on := OS.get_environment("NS3_NET_STATS") != ""
## NS3_NET_KILL=<sec>: host-side sibling of NS3_KILL. Eliminates every REMOTE
## player's fighter that long after FIGHT!, because the one screen the wifi
## harness otherwise cannot reach is the client's own results card — a client
## dies when a bot happens to kill it, which is neither on a schedule nor at a
## moment either instance is taking a screenshot.
var _net_kill_at := float(OS.get_environment("NS3_NET_KILL")) \
		if OS.get_environment("NS3_NET_KILL") != "" else 0.0
## NS3_NET_REMATCH=1: on a client, ask for a rematch the moment the results card
## goes up; on a host, deal the next match once everyone has asked. The rematch
## flow is a round trip between two instances, so without this it can only be
## checked by hand on two machines.
var _net_auto_rematch := OS.get_environment("NS3_NET_REMATCH") != ""
var _net_rematch_fired := false
var _lag_snaps: Array = []
var _lag_inputs: Array = []
var _lag_last_at := -1.0          # ordered channel: a packet overtaken is dropped
var _stat_at := 0.0
var _stat_bytes := 0
var _stat_packets := 0
var _stat_legacy := 0
var _stat_starved := 0
var _stat_err_sum := 0.0
var _stat_err_max := 0.0
var _stat_err_n := 0

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
## Watched in _update_status rather than hooked into deal_damage, because a wifi
## CLIENT never runs deal_damage at all — `authoritative` returns it early — and
## its own health arrives in the snapshot stream. Reading the number covers both.
var _last_player_health := -1
## Damage the PLAYER dealt, and the max health of whoever took it. Banked in
## deal_damage and spent in _update_status for the same reason the line above is
## watched there: one exchange should be one tap.
##
## Banked over a WINDOW rather than a frame, which the first pass got wrong. A
## shotgun's nine pellets are nine projectiles with their own flight times, so
## they land across three or four frames, not one — the repeat gap in haptics.gd
## still collapsed them to a single tap, but that tap carried the first frame's
## share of the damage and read as a third of the blow it was. The window is
## short enough that the delay it adds is under a tenth of a second.
const LANDED_WINDOW := 0.07
var _landed_damage := 0.0
var _landed_max := 1.0
var _landed_at := 0.0

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

## What the three sticks look like and where they park. Colour is the only thing
## telling them apart at a glance, so they are the three that never read as each
## other: blue walks, red shoots, gold spends.
const MOVE_STICK_COLOR := Color(0.36, 0.64, 1.0)
const AIM_STICK_COLOR := Color(1.0, 0.34, 0.30)
const SUPER_STICK_COLOR := Color(1.0, 0.82, 0.20)
const SUPER_STICK_RADIUS := 70.0
const SUPER_STICK_KNOB := 30.0
## The Super's grab radius is deliberately much wider than the ring it draws.
## The old button was 62 px with a 16 px pad and it was genuinely hard to hit
## with a thumb mid-fight, which is exactly the complaint this answers — and
## because an uncharged Super now falls THROUGH to the aim stick, a generous
## radius costs nothing when there is no charge to spend.
const SUPER_GRAB_RADIUS := 118.0
## How far the move and aim sticks park from their corner, and where the Super
## sits relative to the aim stick: up and inboard, so a thumb reaching for it
## never crosses the stick it is already holding.
const STICK_INSET := 168.0
const SUPER_STICK_OFFSET := Vector2(-186.0, -132.0)

## Margin from the safe rect's own edge, the gap between the two right-hand
## labels, and how far down the screen the centre label sits.
const HUD_MARGIN := 20.0
const HUD_FEED_DROP := 40.0
const CENTER_LABEL_FRAC := 1.0 / 3.0

## Where the HUD's chrome may go: the display's safe area on a phone, the whole
## viewport everywhere else. The match PICTURE deliberately keeps the lot and
## runs under the notch and the home indicator — but a label there cannot be
## read and a stick there cannot be reached.
func _hud_rect() -> Rect2:
	return Session.safe_rect(get_viewport())

## Re-park the sticks and the labels for the current viewport. Both are placed
## in viewport pixels rather than laid out as Controls, so this runs on every
## resize — and it has to, which is todo 1.1.
##
## These four labels used to be placed at coordinates authored for a 1280-wide
## viewport, which is a size no shipping device has: `stretch/aspect="expand"`
## hands a 19.5:9 phone 1561x720 instead. So `players_label`, pinned at x=1130
## inside a 430-wide box, put its right edge at 1560 — entirely OFF SCREEN at
## the project's own 1280x720 base resolution, which is why the "N LEFT"
## counter has never once been visible in a desktop run, and flush against the
## display edge on the phone, where the final glyph fell under the rounded
## corner. `status_label` at x=20 sat under the Dynamic Island, 33 device px
## into a 177 px inset. And `center_label` was never centred at any width: with
## a zero minimum size, CENTER alignment centres the text inside nothing and
## `position` is only its left edge.
func _layout_hud() -> void:
	var r: Rect2 = _hud_rect()
	move_stick.park(Vector2(r.position.x + STICK_INSET, r.end.y - STICK_INSET))
	var aim_home := Vector2(r.end.x - STICK_INSET, r.end.y - STICK_INSET)
	aim_stick.park(aim_home)
	super_stick.park(aim_home + SUPER_STICK_OFFSET)
	# Every label spans the full safe width and aligns inside it, rather than
	# sitting in a fixed-width box at a computed x. A Label grows RIGHTWARD past
	# its minimum size to fit its text, so a right-aligned one in a 430-wide box
	# walks off the edge the moment an elimination line is long; given the whole
	# width it has nowhere to overflow to.
	var inner := Vector2(r.position.x + HUD_MARGIN, r.position.y + HUD_MARGIN)
	var span: float = r.size.x - HUD_MARGIN * 2.0
	for l: Label in [status_label, players_label, feed_label, center_label]:
		l.custom_minimum_size.x = span
		l.size.x = span
	status_label.position = inner
	players_label.position = inner
	feed_label.position = inner + Vector2(0.0, HUD_FEED_DROP)
	center_label.position = Vector2(inner.x,
			r.position.y + r.size.y * CENTER_LABEL_FRAC)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	fighter_bars = FighterBars.new()
	fighter_bars.game = self
	hud.add_child(fighter_bars)   # under the sticks and labels
	move_stick = TouchStick.new()
	move_stick.tint = MOVE_STICK_COLOR
	aim_stick = TouchStick.new()
	aim_stick.tint = AIM_STICK_COLOR
	super_stick = TouchStick.new()
	super_stick.tint = SUPER_STICK_COLOR
	super_stick.radius = SUPER_STICK_RADIUS
	super_stick.knob = SUPER_STICK_KNOB
	super_stick.grab_radius = SUPER_GRAB_RADIUS
	super_stick.charge = 0.0      # >= 0 is what puts the dial and the star on it
	hud.add_child(move_stick)
	hud.add_child(aim_stick)
	hud.add_child(super_stick)
	center_label = _label(72, HORIZONTAL_ALIGNMENT_CENTER)
	players_label = _label(30, HORIZONTAL_ALIGNMENT_RIGHT)
	feed_label = _label(24, HORIZONTAL_ALIGNMENT_RIGHT)
	status_label = _label(22, HORIZONTAL_ALIGNMENT_LEFT)
	# After the labels exist: _layout_hud places the sticks and all four.
	_layout_hud()
	get_viewport().size_changed.connect(_layout_hud)
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
## `net_wait` is the wifi client's card: it cannot start a match, so instead of
## PLAY AGAIN it gets a REMATCH request it sends up to the host, and a line that
## says what it is waiting on.
func _show_results(outcome: int, headline: String, kit_name: String,
		award: Dictionary, rows: Array, rematch: bool, board: Control = null,
		net_wait := false) -> void:
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

	# Kept apart from results_note, which is already carrying "X wins!" by the
	# time anyone asks for a rematch.
	results_wait = MenuUI.display("", 18, MenuUI.TEXT_DIM, 4)
	results_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_wait.visible = false
	col.add_child(results_wait)

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
	elif net_wait:
		# Only the host can deal a new roster, so a client asks for one. The
		# button reports itself rather than vanishing: "I have asked and nothing
		# has happened yet" is the state that needed saying.
		var ask: Button = MenuUI.button("REMATCH", "green", 30, Vector2(250, 74))
		ask.pressed.connect(func() -> void:
			ask.disabled = true
			_net_rematch_request.rpc_id(1)
			results_wait.text = "WAITING FOR THE HOST…"
			results_wait.visible = true)
		buttons.add_child(ask)
		if _net_auto_rematch:
			ask.pressed.emit()   # NS3_NET_REMATCH: ask without waiting for a thumb
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
		_fade_in_rows(table, 0.06)

## The stagger for the results table, and deliberately NOT `MenuUI.stagger`.
##
## That one goes through `pop_in`, which also tweens `position:y` — and the rows
## live in a VBoxContainer, which OWNS its children's positions. `pop_in` reads
## `home` off a child that the container has not laid out yet, so on the losing
## side of that race every row records home = 0 and the tween walks all four back
## to the top of the table, stacked, where only the last one drawn is visible.
## That is exactly what a wifi client's four-row card did while the host's
## identical card, built a frame later in its own life, came out fine.
##
## Alpha is the half of the effect a container cannot fight, so this fades only.
func _fade_in_rows(table: Control, step: float) -> void:
	var i := 0
	for child in table.get_children():
		if child is Control:
			child.modulate.a = 0.0
			var tw := child.create_tween()
			tw.tween_interval(i * step)
			tw.tween_property(child, "modulate:a", 1.0, 0.16)
			i += 1

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

## A HUD label. Position and width are _layout_hud's job, not constructor
## arguments — all four move and resize on every viewport change.
func _label(size: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = align
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
	_name_pool = []   # a fresh shuffle per match, so no lobby repeats a username
	_last_player_health = -1
	_landed_damage = 0.0
	# Ahead of the first tap rather than on it: Godot builds the Core Haptics
	# engine with auto-shutdown on, so it idles down between taps and the first
	# one after a lull pays the start-up cost. A Showdown lull is easily ten
	# seconds, which makes the late tap exactly the one that mattered.
	Haptics.warm()

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

		var roster: Array = lineup_kits(10, player_kit())
		player = _spawn_fighter(roster[0], spawns.pop_front(), not sim_active)
		player.display_name = "%s 0" % player.kit.name if sim_active else "You"
		if sim_active:
			brains.append(BotBrain.new(player))

		var i := 1
		while not spawns.is_empty() and i <= 9:
			var kit: Dictionary = roster[i]
			var bot := _spawn_fighter(kit, spawns.pop_front(), false)
			bot.display_name = "%s %d" % [kit.name, i] if sim_active else next_bot_name()
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

## A match lineup of `count` kits with no repeats, `first` (the player's) at
## index 0. Every slot used to be its own `Kits.all().pick_random()`, which put
## two of the same character on one Nobles Cup team about a third of the time and
## dealt Showdown the same fighter three or four times over.
##
## The pool is refilled when it runs dry rather than capped, so Showdown's ten
## slots against nine kits fill nine of them with nine different characters and
## only the tenth can echo one. `first` is dealt out of the FIRST pass only —
## the player's own character is allowed to come back in that refill, and
## comparison is by NAME because player_kit() returns Session's own copy of the
## dictionary rather than one of the instances Kits.all() builds fresh per call.
func lineup_kits(count: int, first: Dictionary = {}) -> Array:
	var out: Array = []
	var pool: Array = []
	var dealt := ""
	if not first.is_empty():
		out.append(first)
		dealt = str(first.name)
	while out.size() < count:
		if pool.is_empty():
			pool = Kits.all()
			pool.shuffle()
			for k in range(pool.size() - 1, -1, -1):
				if str(pool[k].name) == dealt:
					pool.remove_at(k)
			dealt = ""
		out.append(pool.pop_back())
	return out

## The next bot username, dealt without repeats from a per-match shuffle of
## MenuData's pool. Bots were called "Kovacs 3", which reads as a debug label in
## the four places display_name prints: the versus cards, the elimination feed,
## the nameplate over the fighter and the results table. NS3_SIM keeps the old
## kit-based naming on purpose — "[sim] match 12/60: Kovacs 4 wins" is the line
## that has to stay readable.
func next_bot_name() -> String:
	if _name_pool.is_empty():
		_name_pool = MenuData.opponent_names().duplicate()
		_name_pool.shuffle()
	return str(_name_pool.pop_back()) if not _name_pool.is_empty() else "Rival"

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
			if body == player:
				Haptics.fire("cube")
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

## Anders' sack, born where the kick lands it — at his foot when the kit
## has the gear, a step ahead of him otherwise (see KEEP_IT_UP).
func _launch_sack(f: Fighter, weapon: Dictionary, unit: Vector3, hop_to: float) -> void:
	var sack := HackySack.new()
	sack.weapon = weapon
	sack.base_damage = int(weapon.damage * f.damage_multiplier())
	sack.owner_fighter = f
	sack.game = self
	sack.position = f.gear_global_position() + Vector3(0, 0.2, 0) if f.has_gear() \
			else f.global_position + unit * 0.8 + Vector3(0, 1.0, 0)
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
	if f.has_gear():
		# Born at the size of the sack on his foot and grown to its own over
		# the first stretch of the arc, so the hand-off reads as one object
		# rather than a small ball popping into a bigger one. Visual only:
		# hits and landings resolve by radius, never by this scale.
		var grow: float = float(f.kit.gear.get("radius", 0.22)) / float(weapon.radius)
		sack.scale = Vector3.ONE * grow
		create_tween().tween_property(sack, "scale", Vector3.ONE, 0.15) \
				.set_ease(Tween.EASE_OUT)


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
		# The attacker goes with the shove: Nobles Cup's strip rule compares this
		# impulse against that fighter's OWN regular attack, which is the only way
		# to tell a Super's knock from a basic one — see CupMode._knock_was_super.
		target.receive_knockback(kb_dir, kb_strength, attacker)
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
		# Your shot arriving on somebody — the one piece of feedback the first
		# haptics pass had no entry for at all, and the one thing in a firefight
		# you genuinely cannot read off the screen. Banked rather than fired, so
		# the whole exchange is one tap; skipped when the target goes down,
		# because `elimination` outranks it a few lines below and says more.
		if attacker == player and target != player and not target.is_dead():
			if _landed_damage <= 0.0:
				_landed_at = now
			_landed_damage += float(amount)
			_landed_max = float(target.max_health)
		var was_charged: bool = attacker.is_super_ready()
		attacker.charge_super(amount)
		# The moment the bar fills is the only cue the player gets that the
		# Super is available without looking away from the fight.
		if attacker == player and not was_charged and attacker.is_super_ready():
			sfx_ui("super_ready", 1.0)
			Haptics.fire("super_ready")
		if sim_active:
			_sim_kit(attacker.kit.name).damage += amount
			_sim_kit(attacker.kit.name).hits += 1
	if target.is_dead():
		if attacker == player:
			Haptics.fire("elimination")
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
	# Only your own, and only the Super: a tap per ordinary shot would fire
	# several times a second, which the throttle would mostly eat and the rest
	# of which would be noise. The style picks the shape — a Super that carries
	# you somewhere gets a launch and then a bed under the ride, which is the
	# one thing a continuous-only haptic API is genuinely the right tool for.
	if is_super and f == player:
		Haptics.super_fired(int(weapon.style))
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
			# Gated like DASH and DOWNHILL below: `_update_leaps` runs only in the
			# host's match loop, so a client that started a leap never ended one —
			# `is_leaping()` stayed true for the rest of the match and
			# `apply_movement` returns early while it is, which froze the client's
			# own fighter the moment it used the Super. Harmless while the local
			# fighter was a puppet moved by the snapshot stream; fatal once it
			# predicts its own movement.
			if authoritative:
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
			# The sack rides his kicking foot through the wind-up and leaves from
			# it when the kick lands, `delay` seconds in. The projectile is not
			# born until then, so there is never a second sack on screen. The sim
			# runs unattended and gets it at once.
			if sim_active or not f.has_gear():
				_launch_sack(f, weapon, unit, hop_to)
			else:
				f.set_gear_visible(true)
				get_tree().create_timer(float(weapon.get("delay", 0.12))).timeout.connect(func() -> void:
					if not is_instance_valid(f) or f.is_dead():
						return
					f.set_gear_visible(false)
					_launch_sack(f, weapon, unit, hop_to))
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

## What a tapped ATTACK fires at: the nearest visible enemy, or a loot box when
## no enemy is in range, so tapping in a quiet corner opens boxes instead of
## firing at nothing. Reach is 1.1x the weapon's range, matching the enemy check.
##
## Nearest, and `_super_target` is nearest too — the one rule a player can
## predict without reading a marker. A picker that re-ranks on every tap sends
## consecutive shots at different people, which reads as the game arguing with
## you.
func auto_aim_target(viewer: Fighter, weapon: Dictionary) -> Node3D:
	var reach: float = weapon.range * 1.1
	var enemy := nearest_visible_enemy(viewer, reach, _lobbed(weapon))
	if enemy:
		return enemy
	return nearest_visible_lootbox(viewer, reach, _lobbed(weapon))

## What a tapped SUPER fires at: the nearest visible enemy, over the same reach
## and the same wall and bush rules a tapped attack uses.
##
## This was briefly an expected-value picker — worth of the target (would it
## finish them, were you already trading with them, are they hurt, are they
## close) times how likely the shot looked to arrive. It read as the game
## arguing with you. A Super is aimed under pressure at the fighter you are
## looking at, and any rule that quietly prefers a different one is wrong at the
## moment it matters however good its reasoning is. The one thing kept from the
## split is that a Super never picks a LOOT BOX, which `auto_aim_target` will:
## burning a charge on a box is never what the tap meant.
func _super_target(weapon: Dictionary) -> Fighter:
	return nearest_visible_enemy(player, float(weapon.range) * 1.1, _lobbed(weapon))

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
	if f == player:
		Haptics.fire("death")
	# How long they lasted, for the results card. Not set in Nobles Cup, where a
	# death is a three-second setback and "survived" means nothing.
	if cup == null:
		f.stats.survived = maxf(0.0, now - match_start)
	if cup != null:
		# Ahead of on_death, which parks the body: a client runs the same call in
		# _net_cup_down and has to see it in the same order.
		if net_host:
			_net_cup_down.rpc(net_fighters.find(f), killer)
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
		# Their own numbers first: every mutation is host-side, so a client's
		# copy of its Fighter.stats is a column of noughts. Both RPCs are
		# reliable on the same channel, so this lands before the elimination
		# that raises the card it fills in.
		_net_push_stats(f)
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
	# Losing while dead is silent on purpose: `death` fired a beat earlier in
	# _eliminate and outlasts this call, and a second, smaller statement on top
	# of it says nothing the first one did not. In Showdown that is every loss;
	# the branch is here for a Cup scoreline, where you can lose on your feet.
	if victory:
		Haptics.fire("victory")
	elif player == null or not is_instance_valid(player) or not player.is_dead():
		Haptics.fire("defeat")
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
func end_cup_match(blue: int, red: int, rows: Array = []) -> void:
	phase = Phase.ENDED
	center_label.text = ""
	move_stick.release()
	aim_stick.release()
	super_stick.release()
	var won := blue > red
	var drew := blue == red
	sfx_ui("victory" if won else "defeat", 2.0)
	# The whistle, not an elimination: a Cup match ends on the clock with the
	# player usually alive, so unlike Showdown there is nothing already playing
	# for this to sit on top of. A draw takes the losing shape — it is not a win.
	Haptics.fire("victory" if won else "defeat")
	var award: Dictionary = SaveGame.award_match(player.kit.name, 1 if won else (5 if drew else 9))
	var board_rows: Array = rows if not rows.is_empty() else _cup_rows()
	if net_host:
		# The host is the only machine that counted a goal or a hit, so the whole
		# table goes out from here — see _cup_rows.
		_net_cup_over.rpc(blue, red, board_rows)
	_show_results(1 if won else (0 if drew else -1), "%d — %d" % [blue, red],
			str(player.kit.name), award, [], authoritative,
			_cup_scoreboard([blue, red], board_rows), net_active and not net_host)

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
func _cup_scoreboard(score: Array, rows: Array) -> Control:
	var board: HBoxContainer = MenuUI.hbox(16)
	# Your OWN side on the left, not team 0. In single player you are always team
	# 0 and the two are the same thing; over wifi you may well be on team 1, and
	# a card that labels the other team "YOUR TEAM" is worse than no label.
	var mine: int = player.team if is_instance_valid(player) and player.team >= 0 else 0
	for side in 2:
		var team: int = mine if side == 0 else 1 - mine
		board.add_child(_cup_team_column(team, int(score[team]), rows, team == mine))
	return board

## The board as DATA rather than as six live fighters.
##
## It has to be data because of who holds the numbers. Every hit and every goal
## is resolved on the host — `deal_damage` returns early when `not authoritative`
## — so a client's own `Fighter.stats` are a column of noughts, and a table built
## from them locally would report a match nobody played. The host builds this
## once and sends the identical array to everyone, which also means the two cards
## cannot disagree about who finished top.
##
## `idx` is the roster index, and it is what each machine uses to find ITSELF in
## someone else's table: the host marks its own row with `you` on the way out,
## and a client re-marks the row matching its own `_my_idx` on the way in. In
## single player there is no roster, `find` returns -1, and `you` stands as sent.
func _cup_rows() -> Array:
	var rows: Array = []
	for f: Fighter in fighters:
		if not is_instance_valid(f) or f.team < 0:
			continue
		var idx := net_fighters.find(f)
		# The REAL name off the roster, never `display_name`. Every machine calls
		# its own fighter "You", so a table built from display_name and broadcast
		# gives all five other players a team-mate literally called YOU — and it
		# is the host's fighter, not theirs. Who "you" is has to be decided at
		# each end, which is what the `you` flag and `idx` are for.
		var who := String(f.display_name)
		if idx >= 0 and idx < _net_roster.size():
			who = String((_net_roster[idx] as Dictionary).get("fname", who))
		rows.append({"name": who, "kit": String(f.kit.name),
				"team": f.team, "goals": int(f.stats.goals),
				"kills": int(f.stats.kills), "damage": int(f.stats.damage),
				"idx": idx, "you": f == player})
	return rows

## Width of one stat cell. Fixed rather than shrink-to-fit so the three columns
## line up down the card however wide the damage number gets.
const CUP_STAT_W := 54.0
## Matches MenuUI.dark_panel's internal padding, so the key line above the rows
## sits over the numbers rather than 8px off them.
const CUP_ROW_PAD := 8

func _cup_team_column(team: int, goals: int, rows: Array, mine: bool) -> Control:
	var tint: Color = Arena.TEAM_COLORS[team]
	var column: VBoxContainer = MenuUI.vbox(6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head: PanelContainer = MenuUI.dark_panel(11, 0.44, CUP_ROW_PAD)
	var head_line: HBoxContainer = MenuUI.hbox(8)
	head.add_child(head_line)
	# Named by side rather than by colour: "YOUR TEAM" is what the player needs
	# to find first, and team 0 is always theirs in single-player Cup.
	var side: Label = MenuUI.display("YOUR TEAM" if mine else "OPPONENTS", 20, tint, 4)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_line.add_child(side)
	head_line.add_child(MenuUI.display(str(goals), 30, Color.WHITE, 5))
	column.add_child(head)

	column.add_child(_cup_column_key())
	for row: Dictionary in _cup_team_rows(team, rows):
		column.add_child(_cup_player_row(row, tint))
	return column

## One team's fighters, best contribution first, so whoever decided the match is
## at the top of their column. Goals outrank damage: a striker who scored once
## and dealt little did more than a team-mate who chipped away and did not.
func _cup_team_rows(team: int, rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		if int(row.get("team", -1)) == team:
			out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.goals) != int(b.goals):
			return int(a.goals) > int(b.goals)
		return int(a.damage) > int(b.damage))
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

func _cup_player_row(row: Dictionary, tint: Color) -> Control:
	var you: bool = bool(row.get("you", false))
	# Your own row is lifted out of its column with a brighter plate and a white
	# name, so you can find yourself in six without reading the names.
	var plate: PanelContainer = MenuUI.dark_panel(10, 0.52 if you else 0.30, CUP_ROW_PAD)
	var line: HBoxContainer = MenuUI.hbox(8)
	plate.add_child(line)
	line.add_child(_cup_face(str(row.get("kit", "")), tint))
	# Your own row says YOU on whichever machine is reading it, the way the
	# nameplate and the feed already do; everyone else is named.
	var name_l: Label = MenuUI.body("YOU" if you else str(row.get("name", "")).to_upper(),
			17, Color.WHITE if you else MenuUI.TEXT_SOFT, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name_l)
	line.add_child(_cup_stat(str(int(row.get("goals", 0)))))
	line.add_child(_cup_stat(str(int(row.get("kills", 0)))))
	line.add_child(_cup_stat(MenuUI.fmt(int(row.get("damage", 0)))))
	return plate

func _cup_stat(text: String) -> Label:
	var l: Label = MenuUI.display(text, 20, Color.WHITE, 4)
	l.custom_minimum_size = Vector2(CUP_STAT_W, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## A row's portrait chip, on its team colour. Same fallback as the big card:
## a kit with no rendered portrait (Nova, Ayaan) shows its initial in kit colour.
func _cup_face(kit_name: String, tint: Color) -> Control:
	var holder: Panel = MenuUI.card("dark", 9, 3)
	holder.custom_minimum_size = Vector2(38, 38)
	holder.add_child(MenuUI.card_backdrop(Color(tint.r, tint.g, tint.b, 0.34)))
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
				Kits.named(kit_name).get("color", Color.WHITE), 4)
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
	if net_active and _net_lag > 0.0:
		_net_drain_lag()
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
					Haptics.fire("count_go")
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
	if net_host and _match_ready and _net_live():
		_snap_tick += 1
		if _snap_tick % 2 == 0:   # 30Hz is plenty on LAN; clients interpolate
			_net_send_snapshot()
		_net_stats_tick()

func _update_aim_indicator() -> void:
	var im: ImmediateMesh = aim_mesh.mesh
	im.clear_surfaces()
	if phase != Phase.PLAYING or player == null or not is_instance_valid(player) \
			or player.is_dead():
		return
	# NS3_AIM_SHOW=attack|super|kick holds the indicator on with no finger on the
	# stick. It is drawn only while a touch is DRAGGED, so it is the one thing on
	# screen NS3_SHOTS could never catch — the same reason NS3_END and NS3_KILL
	# exist. `kick` needs a Nobles Cup match and the ball in hand. The synthetic
	# stick is a full deflection along the player's own facing, which is the one
	# direction that is meaningful with nobody holding the stick.
	if _aim_show != "":
		var facing := Vector2(player.facing.x, player.facing.z).normalized()
		# Carrying beats everything here exactly as it does below, so the hook can
		# never draw an attack the player is not allowed to make.
		if cup != null and cup.ball.carrier == player:
			_draw_kick_aim(im, Vector2.ZERO, _aim_show == "super", false)
		elif _aim_show != "kick":
			_draw_weapon_aim(im, facing, _aim_show == "super")
		return
	# The dedicated Super stick takes priority over the aim stick.
	var use_super := super_stick.active
	var stick: TouchStick = super_stick if use_super else aim_stick
	if not stick.active:
		return
	var dragging := stick.value.length() >= TAP_THRESHOLD
	# Holding the ball replaces the weapon's aimer with the ball's own path.
	# The kick is a different action with a different reach, and it banks off
	# walls, so drawing the weapon lane here would preview an attack the player
	# cannot currently make and hide the one they can. Its tap DOES draw, because
	# the ring there disambiguates a pass from a shot at goal rather than
	# pointing out a target — see `_draw_kick_aim`.
	if cup != null and cup.ball.carrier == player:
		_draw_kick_aim(im, stick.value, use_super, dragging)
		return
	# A finger that is down but not yet dragged is a TAP, and a tap draws
	# NOTHING. It used to preview the auto-aim's pick — a lane to the chosen
	# fighter and a ring around their feet — and that is a lock-on marker: it
	# hands you the target for free and makes the tap the obvious play, when
	# aiming is meant to be the thing you get good at. It was also where Nova's
	# indicator turned into a thin straight line, since the lane to a target is
	# drawn the same way for every kit and has nothing to do with the shape the
	# weapon actually covers. Drag and the real cone comes back.
	if not dragging:
		return
	_draw_weapon_aim(im, stick.value, use_super)

## The weapon's own lane, cone, arc or weave, in the direction and to the reach
## `stick_value` asks for — the drag indicator, and the only combat indicator
## there is. Split out of `_update_aim_indicator` so NS3_AIM_SHOW can hold it on.
func _draw_weapon_aim(im: ImmediateMesh, stick_value: Vector2, use_super: bool) -> void:
	var weapon: Dictionary = player.kit["super"] if use_super else player.kit.weapon
	var color := Color(1.0, 0.7, 0.2, 0.4) if use_super else Color(1, 1, 1, 0.3)
	var origin := player.global_position + Vector3(0, 0.08, 0)
	var dir := Vector3(stick_value.x, 0, stick_value.y).normalized()
	if dir == Vector3.ZERO:
		return
	var style := int(weapon.style)
	var bouncing := int(weapon.get("bounces", 0)) > 0
	var targeted := style == Kits.Style.LOB or style == Kits.Style.JUMP_SMASH \
			or style == Kits.Style.DISCONNECT or style == Kits.Style.KEEP_IT_UP
	var cone := style == Kits.Style.MELEE or style == Kits.Style.SHOCKWAVE \
			or style == Kits.Style.BUTTONS \
			or (style == Kits.Style.PELLETS and int(weapon.pellets) > 1 \
					and float(weapon.spread_deg) > 0.0)
	var target_dist: float = clamp(stick_value.length() * weapon.range,
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
				stick_value.length() * float(weapon.range))
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

## The carrier's aimer: the ball's own path, bounces and all. A drag goes where
## the stick points; a tap goes wherever CupMode decides, so it is drawn from the
## same `kick_plan` the kick itself runs on and marked with a ring on the thing
## being aimed at — the goal for a shot, a team-mate's feet for a pass. That ring
## is the whole tell. The rule (shoot inside SHOT_RANGE, pass outside it) is
## Brawl Ball's own and is unchanged; what was missing was any way to know which
## of the two a tap was about to be, since the deciding distance is invisible.
##
## A clearance draws no ring on purpose. It is aimed at the goal like a shot but
## will not reach it, and a ring out at the goal would promise exactly the thing
## the lane is already showing it cannot do — the lane stops where the ball does.
func _draw_kick_aim(im: ImmediateMesh, stick_value: Vector2, use_super: bool,
		dragging: bool) -> void:
	var powerful := use_super and player.is_super_ready()
	var plan: Dictionary = cup.kick_plan(player, powerful)
	var kick_dir: Vector3 = Vector3(stick_value.x, 0, stick_value.y).normalized() if dragging \
			else (plan.dir as Vector3).normalized()
	if kick_dir == Vector3.ZERO:
		return
	var from := Vector3(cup.ball.position.x, 0.08, cup.ball.position.z)
	var tint: Color = SUPER_KICK_AIM_COLOR if powerful else KICK_AIM_COLOR
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(tint)
	for segment in _aim_bounce_segments(from, kick_dir,
			Ball.kick_range(Ball.SUPER_KICK_MULT if powerful else 1.0), 2, Ball.BOUNCE):
		_aim_add_segment(im, segment[0], segment[1], Ball.RADIUS, tint)
	if not dragging and String(plan.kind) != "clear":
		var at: Vector3 = plan.at
		_aim_add_ring(im, Vector3(at.x, 0.09, at.z), MARK_RADIUS, MARK_WIDTH, tint)
	im.surface_end()

## A flat ring on the ground, for marking a kick's destination. Sized to be seen
## rather than to be accurate: the match camera shows about 55 px per metre, so
## a marker any smaller than a fighter is a handful of pixels.
const MARK_RADIUS := 1.15
const MARK_WIDTH := 0.22

func _aim_add_ring(im: ImmediateMesh, center: Vector3, radius: float,
		width: float, color: Color) -> void:
	var steps := 28
	im.surface_set_color(color)
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var inner := maxf(radius - width, 0.01)
		im.surface_add_vertex(center + d0 * inner)
		im.surface_add_vertex(center + d0 * radius)
		im.surface_add_vertex(center + d1 * radius)
		im.surface_add_vertex(center + d0 * inner)
		im.surface_add_vertex(center + d1 * radius)
		im.surface_add_vertex(center + d1 * inner)

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
	_net_kill_check()
	if _force_end_at > 0.0 and now - match_start >= _force_end_at and not sim_active:
		_force_end_at = 0.0
		if cup != null:
			cup.finished = true
			end_cup_match(cup.score[0], cup.score[1])
		elif player != null and is_instance_valid(player):
			_end_match(fighters.size(), fighters.size() == 1)
		return
	# NS3_AIM_SHOW=kick shoots the carrier's aimer, and that needs a carrier. Over
	# a whole match the ball is in the player's own hands for a few seconds and
	# never on the frame NS3_SHOTS asked for, so the hook puts it there.
	if _aim_show == "kick" and cup != null and cup.ball.carrier == null \
			and not cup.frozen(now) and is_instance_valid(player) and not player.is_dead():
		cup.ball.pick_up(player)
	# In sim mode the player slot is brain-driven; skip input. After it dies
	# the node is freed while the match runs on, hence the validity guards.
	# Nobles Cup holds everyone still through the kickoff beat and once the
	# final whistle has gone; the match loop otherwise runs exactly as usual.
	var held := cup != null and cup.frozen(now)
	if held:
		for f in fighters:
			if not f.is_dead():
				f.apply_movement(Vector3.ZERO)
	if not sim_active and not autoplay and is_instance_valid(player) and not player.is_dead() \
			and not held:
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

	# `not held` matters here as much as it does for the local player and the
	# bots above, and this block was the one that did not check it. A Nobles Cup
	# kickoff zeroes everyone's movement at the top of this function — and then
	# this put a remote player's LAST input straight back on top, because
	# `_consume_input` returns the previous one when the queue is empty and a
	# frozen client has stopped sending. So their fighter crept across the pitch
	# on the host while standing still on their own screen, and the moment the
	# freeze lifted the difference came back as a correction. Measured: 2-3 cm
	# average prediction error with spikes to 29 cm in Cup, against a flat 0 in
	# Showdown, which has no freeze for this to happen in.
	if net_host and not held:
		# Remote players: drive their fighters from the latest input RPC.
		for i in net_fighters.size():
			var f = net_fighters[i]
			if f == null or not is_instance_valid(f) or f.is_dead() or f == player:
				continue
			var peer := int(f.get_meta("peer", 0))
			if peer <= 1:
				continue   # bots (0) belong to brains; 1 is the host itself
			var inp: Dictionary = _consume_input(peer)
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
	if net_active and not net_host:
		# Clients ask the host to fire; the attack echoes back as _net_attack, and
		# a kick as _net_cup_kick. This test comes BEFORE the kick below, which is
		# the whole of what stops a client moving the ball on its own screen and
		# never telling anybody — the host runs the identical cup.kick inside
		# _net_fire. The aim was already resolved by _release_fire, which reads
		# CupMode.kick_plan, so a client still aims its kicks locally.
		_net_fire.rpc_id(1, use_super, dir, dist)
		return
	# Last line of defence for the carrier's kick. _release_fire and
	# _auto_aim_fire resolve the aim and kick before they reach here, but every
	# player attack funnels through this call — NS3_AUTOFIRE included — and none
	# of them may fire a weapon while the ball is in hand. A Super spent here
	# goes into the ball rather than the kit.
	if cup != null and cup.kick(player, dir, now, use_super):
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
		# You pressed fire and nothing came out, which is the definition of a
		# state change you would otherwise have to look at the screen to notice.
		# Two flat identical ticks: the only shape in the vocabulary that
		# neither rises nor falls, because it is the one that means "no".
		Haptics.fire("empty")

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
			if player.is_super_ready() and not super_stick.active \
					and super_stick.hit(event.position):
				# The Super's own stick gets first refusal on a touch near it,
				# and ONLY while there is a charge to spend. An uncharged Super
				# used to swallow the press: a thumb that landed on the button in
				# the half second before it filled fired nothing at all, which is
				# indistinguishable from a control that does not work. Now it
				# falls through and shoots.
				super_stick.begin(event.position, event.index)
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
	# Routed through _fire_player rather than straight into cup.kick, because
	# _fire_player is where "am I a client?" lives — and this, not that, is the
	# function a tap or a stick release actually reaches. Calling cup.kick here
	# moved the ball on the client's OWN screen and told nobody: the host never
	# heard about the kick, and the next snapshot put the ball straight back in
	# the carrier's hands. It read as the pass button not working at all.
	_fire_player(player.kit["super"] if use_super else player.kit.weapon,
			dir, dir.length())
	# True regardless: the carrier check above already claimed this input for the
	# ball, and a kick the host declines is still not an attack.
	return true

## Which way a tapped escape Super sets off: the way the player is already
## running, or their facing when standing still.
func _run_or_facing() -> Vector3:
	var run := Vector3(player.velocity.x, 0.0, player.velocity.z)
	return run.normalized() if run.length() > 0.5 else player.facing

## What a tap will do with `weapon`. `kind` is one of:
##
##   "target"  fire at `target`, already led — a Fighter, or a loot box for a
##             regular attack in a quiet corner
##   "free"    nobody in reach, and the tap goes anyway: forward for most kits,
##             the way you are already running for Pop Off and Downhill
##
## **Every tap fires.** There used to be a third case, "hold", where a tapped
## Super with nobody in reach kept its charge rather than spending it. It reads
## as a dead button — you press the thing and the game decides not to — and a
## Super aimed at empty ground is the player's call to make, not this function's.
func _tap_plan(weapon: Dictionary, use_super: bool) -> Dictionary:
	var style := int(weapon.get("style", -1))
	# Pop Off is an ESCAPE, so a tapped one leaps the way Anders is already
	# running. Auto-aiming it at the nearest enemy made the tap jump him into the
	# fight he was trying to leave. Drag from the stick to aim it anywhere else.
	if style == Kits.Style.POP_OFF:
		return {"kind": "free", "dir": _run_or_facing(), "target": null}
	# A Super only ever aims at fighters, never at a loot box: burning the charge
	# on a crate is never what the tap meant.
	var target: Node3D = _super_target(weapon) if use_super \
			else auto_aim_target(player, weapon)
	if target != null:
		var aim: Vector3 = _aim_lead(player, target as Fighter, weapon) if target is Fighter \
				else target.global_position
		return {"kind": "target", "dir": aim - player.global_position, "target": target}
	# Downhill is travel as much as damage, so with nobody in reach a tap sets
	# off down the hill — rotating, or leaving a fight — rather than firing at
	# the wall in front of you.
	if style == Kits.Style.DOWNHILL:
		return {"kind": "free", "dir": _run_or_facing(), "target": null}
	return {"kind": "free", "dir": player.facing, "target": null}

func _auto_aim_fire(weapon: Dictionary, use_super: bool) -> void:
	if _kick_instead(Vector2.ZERO, use_super):
		return
	var plan := _tap_plan(weapon, use_super)
	if String(plan.kind) == "target":
		var v: Vector3 = plan.dir
		_fire_player(weapon, v, v.length())
	else:
		_fire_player(weapon, plan.dir, float(weapon.range))

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
	# The sticks are part of the frame while you are alive and playing, and
	# nothing but clutter under a results card or over a body waiting out a
	# Nobles Cup respawn. Set before the validity guard below, because a
	# Showdown elimination FREES the player and would otherwise leave three
	# parked joysticks sitting under the results card for the rest of the match.
	var live: bool = phase == Phase.PLAYING and player != null \
			and is_instance_valid(player) and not player.is_dead()
	move_stick.visible = live
	aim_stick.visible = live
	super_stick.visible = live
	if player == null or not is_instance_valid(player):
		return
	super_stick.set_charge(player.super_charge)
	_update_aim_detent()
	status_label.text = "%s   HP %d/%d   ammo %.1f   cubes %d" % [
		player.kit.name, player.health, player.max_health, player.ammo, player.cubes]
	# A pip crossing a whole number is a shot you have got back. Watched here
	# rather than signalled from fighter.gd, which regenerates ammo for bots too
	# and has no business knowing about audio.
	var pips := int(player.ammo)
	if phase == Phase.PLAYING and pips > _last_ammo_pips:
		sfx_ui("reload_tick", -12.0)
		# Only the pip that takes you from empty back to able to shoot, not
		# every pip returning. A tap per pip fires three or four times a reload
		# cycle for the whole match, which is the fastest way to teach a hand to
		# stop reading the feedback; going from nothing to something is the
		# state change, and the other pips you can afford to wait for.
		if pips == 1 and _last_ammo_pips == 0:
			Haptics.fire("ammo_ready")
	_last_ammo_pips = pips
	# Your health going DOWN is the one thing worth a buzz whatever caused it —
	# a pellet, the gas, a Super you never saw. Health only ever climbs on a
	# respawn or a kickoff restore, so an increase is deliberately silent.
	if _last_player_health >= 0 and player.health < _last_player_health:
		Haptics.hit(float(_last_player_health - player.health), float(player.max_health))
	_last_player_health = player.health
	# The other half of the exchange, banked by deal_damage over LANDED_WINDOW so
	# a nine-pellet shotgun is one connect at the weight of nine pellets. Spent
	# after the damage-taken watch on purpose: when you trade, what landed on
	# YOU is the tap worth keeping.
	if _landed_damage > 0.0 and now - _landed_at >= LANDED_WINDOW:
		Haptics.landed(_landed_damage, _landed_max)
		_landed_damage = 0.0
	# A slow pulse under a quarter health, so the decision to break off is one
	# you can make without watching the bar.
	if phase == Phase.PLAYING and not player.is_dead() \
			and float(player.health) / maxf(1.0, float(player.max_health)) < 0.25:
		if now - _low_health_at >= 1.6:
			_low_health_at = now
			sfx_ui("low_health", -8.0)
	else:
		_low_health_at = -1.0

## A tap on the aim stick's detent — the moment `value` crosses `TAP_THRESHOLD`
## in either direction, which is where the stick stops meaning "tap to auto-aim"
## and starts meaning "this is the lane". That boundary is invisible: the aim
## indicator does change with it, but the indicator is under your thumb and your
## eyes are on the fight, which makes it exactly the state change haptics are
## for. The Super stick takes priority over the aim stick here for the same
## reason it does in `_update_aim_indicator` — only one of them is ever the one
## being aimed.
##
## Watched per frame rather than hooked into `_unhandled_input`, because a drag
## event only arrives while the finger is MOVING: a thumb that crosses the line
## and then holds still stops generating them, and a dwell counted off those
## events alone would never complete.
const AIM_DETENT_DWELL := 0.05
var _aim_detent_on := false
var _aim_detent_since := -1.0

func _update_aim_detent() -> void:
	var stick: TouchStick = super_stick if super_stick.active else aim_stick
	if not stick.active or phase != Phase.PLAYING:
		# Releasing is not a crossing. The shot that follows has its own
		# feedback, and a tap on top of it would land inside the same frame.
		_aim_detent_on = false
		_aim_detent_since = -1.0
		return
	var dragging: bool = stick.value.length() >= TAP_THRESHOLD
	if dragging == _aim_detent_on:
		_aim_detent_since = -1.0
		return
	# The new state has to HOLD before it is reported. This is a debounce and
	# not hysteresis on purpose: a hysteresis band would have the tap claim a
	# state the game is not actually in for the width of the band, whereas this
	# only declines to report a crossing that did not last. A thumb resting on
	# the threshold is otherwise the one input that can chatter across it every
	# single frame.
	if _aim_detent_since < 0.0:
		_aim_detent_since = now
	elif now - _aim_detent_since >= AIM_DETENT_DWELL:
		_aim_detent_on = dragging
		_aim_detent_since = -1.0
		Haptics.fire("aim_on" if dragging else "aim_off")

## One beep per second of the pre-match countdown, on the second the number on
## screen changes rather than on a timer of its own.
func _count_beep(count: int) -> void:
	if count == _last_count_beep or count <= 0 or count > 5:
		return
	_last_count_beep = count
	sfx_ui("count_beep", -2.0)
	# GO used to arrive with no rhythm leading into it, which is most of what a
	# countdown is for: three light ticks a second apart make the fourth one
	# land as a release rather than as the first thing you felt.
	Haptics.fire("count_beep")

func _shot_check() -> void:
	if _shot_times.is_empty() or _shot_prefix == "":
		return
	if now >= _shot_times[0]:
		var t: float = _shot_times.pop_front()
		# The engine skips drawing while the window cannot draw (occluded by
		# another app, another Space, the display asleep) and get_image() then
		# hands back whatever frame was drawn last — a harness run under a
		# browser window came back as N identical shots. Draw it ourselves.
		if not DisplayServer.window_can_draw():
			RenderingServer.force_draw(false)
		var img := get_viewport().get_texture().get_image()
		# Whole seconds keep their old names (prefix_8.png); a fractional time
		# keeps its decimals (prefix_7.06.png), so a burst can catch a 0.12 s
		# wind-up instead of every shot in the same second overwriting the last.
		var stamp: String = str(int(t)) if is_equal_approx(t, floor(t)) else String.num(t, 2)
		var out: String = Session.shot_path("%s_%s.png" % [_shot_prefix, stamp])
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
		# ONLY the first match is dealt from here, and the guard is load-bearing.
		# `_start_from_roster` drops `_match_ready` while it rebuilds and this
		# function runs on every frame that flag is down, so without the test the
		# host dealt a brand new match on the very next frame — and because the
		# rebuild AWAITS a frame partway through, the second pass ran its
		# `fighters.clear()` and its `get_children()` sweep BEFORE the first pass
		# had spawned anything. So the first pass's roster was never freed and
		# never cleared: both passes appended, and the match started with exactly
		# twice the fighters. Reported from a phone as 12 in a 3v3 and about 20
		# in a 10-player Showdown, which is precisely 2x each.
		#
		# Rematches do not come through here at all — they come from
		# _net_host_start's own callers: PLAY AGAIN, KEY_R, and the auto-rematch
		# timer in _update_rematch_note.
		if _match_seq > 0:
			return
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

## Host: deal the match everyone will build, and broadcast it.
##
## The roster is the ONLY thing that decides what a match is on every peer — the
## mode, who is in it, what they are wearing, which side they are on and which
## tile they start on. Nothing downstream is allowed to roll its own dice,
## because two machines rolling separately is two different matches.
func _net_host_start() -> void:
	_match_seq += 1
	_rematch_wanted.clear()
	_net_rematch_fired = false
	_name_pool = []   # a fresh shuffle per match, so no lobby repeats a username
	var room_mode: String = "cup" if Net.mode == "cup" else "showdown"
	var roster: Array = _net_cup_roster() if room_mode == "cup" else _net_showdown_roster()
	_net_start.rpc(_match_seq, room_mode, roster)
	_start_from_roster(room_mode, roster)

## Showdown: connected players first, bots filling the empty slots, each assigned
## a shuffled spawn index (the spawn count comes from the map's S tiles).
##
## Bots are dealt through `lineup_kits` and `next_bot_name` like every other
## match rather than a `pick_random()` and a "Nova 3" label — this was the one
## lineup in the game still doing it the old way, so a wifi lobby could field
## four Kovacses with debug names on their nameplates.
func _net_showdown_roster() -> Array:
	var spawn_idx: Array = range(Arena.SHOWDOWN_MAP.count("S"))
	spawn_idx.shuffle()
	var roster: Array = []
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		if roster.size() >= spawn_idx.size():
			break
		var p: Dictionary = Net.players[id]
		roster.append({"peer": int(id), "kit": String(p.kit), "fname": String(p.name),
				"spawn": spawn_idx[roster.size()], "team": -1})
	var bots: Array = lineup_kits(maxi(0, spawn_idx.size() - roster.size()))
	for kit: Dictionary in bots:
		roster.append({"peer": 0, "kit": String(kit.name), "fname": next_bot_name(),
				"spawn": spawn_idx[roster.size()], "team": -1})
	return roster

## Nobles Cup: two teams of three, humans first, bots making up the numbers.
##
## Friends fill ONE side before the other, the way a party does in Brawl Stars.
## Two people who pressed "play with friends" want to be on the same side, and
## splitting them across the halfway line is the one arrangement nobody asked
## for; past three they spill onto the other side, which is what makes a full
## room a real 3v3. Kits are dealt per side, so no character appears twice on a
## team while a mirror across the halfway line stays legal — the same rule
## CupMode.build_match follows in single player.
func _net_cup_roster() -> Array:
	var sides: Array = [[], []]
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var team := 0 if sides[0].size() < CupMode.TEAM_SIZE else 1
		if sides[team].size() >= CupMode.TEAM_SIZE:
			break   # room already full; Net.room_capacity() should have stopped this
		var p: Dictionary = Net.players[id]
		sides[team].append({"peer": int(id), "kit": String(p.kit), "fname": String(p.name)})
	var roster: Array = []
	for team in 2:
		var bots: Array = lineup_kits(CupMode.TEAM_SIZE - sides[team].size())
		for kit: Dictionary in bots:
			sides[team].append({"peer": 0, "kit": String(kit.name),
					"fname": next_bot_name()})
		# Which of the team's three kickoff tiles each of them takes. Shuffled so
		# the host, who is always the first entry on team 0, does not open every
		# match on the same tile — and dealt HERE rather than in CupMode so that
		# both machines place everyone identically. See CupMode._kick_spot for
		# what happened when two ends of this disagreed.
		var spots: Array = range(CupMode.TEAM_SIZE)
		spots.shuffle()
		for i in sides[team].size():
			var e: Dictionary = sides[team][i]
			e["team"] = team
			e["spawn"] = spots[i % spots.size()]
			roster.append(e)
	return roster

## Both sides build the identical match from the host's roster. The MODE travels
## with it rather than being read from Session: a client that reached the scene
## with a stale Session.mode would otherwise build the wrong arena and then
## disagree with every position in the stream.
func _start_from_roster(room_mode: String, roster: Array) -> void:
	mode = room_mode
	cup = null
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
	player = null
	# Replication state is per-MATCH, not per-scene: PLAY AGAIN reuses this node,
	# and a stale snapshot buffer or input history from the last match would be
	# reconciled against the new one's spawn positions.
	_snap_buf.clear()
	_snap_intake.clear()
	_pred_hist.clear()
	_peer_queue.clear()
	_peer_inputs.clear()
	_lag_snaps.clear()
	_lag_inputs.clear()
	_lag_last_at = -1.0
	_snap_applied_t = -1.0
	_net_count_elapsed = 0.0
	_net_count_at = -1.0
	_clock_synced = false
	_input_seq = 0
	_pred_error = Vector3.ZERO
	_my_idx = -1
	_my_net_stats = {}
	_stat_at = now

	arena = Arena.new()
	arena.map_mode = "cup" if mode == "cup" else "showdown"
	add_child(arena)
	gas = null
	await get_tree().process_frame   # let arena _ready run

	var my_id := multiplayer.get_unique_id()
	var kick_spots: Array = []
	for i in roster.size():
		var e: Dictionary = roster[i]
		var own := int(e.peer) == my_id
		var team := int(e.get("team", -1))
		var spot: Vector3 = _net_spawn_point(team, int(e.spawn))
		kick_spots.append(spot)
		var f := _spawn_fighter(Kits.named(e.kit), spot, own, team)
		f.name = "F%d" % i
		f.display_name = "You" if own else String(e.fname)
		f.set_meta("peer", int(e.peer))
		net_fighters.append(f)
		if own:
			player = f
			_my_idx = i
			_my_kit_name = String(e.kit)
			_pred_pos = f.position
		elif authoritative and int(e.peer) == 0:
			brains.append(BotBrain.new(f))
	if net_host and player and OS.get_environment("NS3_SUPER") != "":
		player.super_charge = 1.0

	if mode == "cup":
		# The rules engine on every peer, running only on the host. Its fighters
		# are already spawned above, so it takes the kickoff tiles and starts the
		# match rather than dealing one of its own — see CupMode.adopt_net_match.
		cup = CupMode.new()
		cup.game = self
		cup.authoritative = authoritative
		add_child(cup)
		cup.adopt_net_match(now, kick_spots)
	else:
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
	# `fighters.size()` rather than `roster.size()`: the roster is what was ASKED
	# for and the array is what exists, and the double-deal bug above was a
	# discrepancy between exactly those two that this line was hiding.
	print("[net] roster applied: %d of %d fighters, I am %s" % [fighters.size(),
			roster.size(), player.display_name if player else "spectator"])

## Where roster entry `spawn` puts a fighter. Showdown indexes the map's S tiles;
## Nobles Cup indexes its own team's kickoff row, which is why the team has to
## come along with the index. Clamped rather than trusted: the roster arrives
## over the wire, and an index off the end of the array is a crash on the frame
## the match starts.
func _net_spawn_point(team: int, spawn: int) -> Vector3:
	if team < 0:
		if arena.spawn_points.is_empty():
			return arena.centre()
		return arena.spawn_points[clampi(spawn, 0, arena.spawn_points.size() - 1)]
	var spots: Array = arena.team_spawns[clampi(team, 0, 1)]
	if spots.is_empty():
		return arena.centre()
	return spots[clampi(spawn, 0, spots.size() - 1)]

## Client frame. Three jobs, in this order: take delivery of whatever arrived,
## predict my own fighter forward on my own stick, and draw everyone else at a
## fixed delay behind the host so their motion is a straight line between two
## known positions instead of a chase after the newest one.
func _client_tick(delta: float) -> void:
	_net_intake()
	if phase == Phase.COUNTDOWN:
		# The HOST's countdown position, carried forward locally between packets
		# so it ticks smoothly rather than in 30Hz steps. Falls back to our own
		# clock only until the first snapshot lands, which is a frame or two.
		var elapsed_c: float = now - phase_at
		if _net_count_at >= 0.0:
			elapsed_c = _net_count_elapsed + (now - _net_count_at)
		if versus != null and is_instance_valid(versus):
			versus.update(int(ceil(maxf(PREMATCH_INTRO_AT - elapsed_c, 1.0))), elapsed_c / PREMATCH,
					elapsed_c >= PREMATCH_INTRO_AT)
			_count_beep(int(ceil(PREMATCH_INTRO_AT - elapsed_c)))
		else:
			center_label.text = str(int(ceil(maxf(3.5 - elapsed_c, 1.0))))
	elif versus != null:
		_hide_versus()
	_net_predict(delta)
	_net_render_puppets(delta)
	if cup != null:
		cup.tick(delta, now)
	_net_stats_tick()

## Move MY fighter on MY stick, this frame, and tell the host what I did.
##
## Without this the local fighter is a puppet like everyone else, which means a
## full round trip between pushing the stick and the body moving — invisible on
## a LAN and unplayable on anything worse. The body is simulated through the
## same `apply_movement` the host runs, so walls, water and the kit's own speed
## all resolve identically; the difference between the two sims is corrected in
## `_reconcile`, not papered over here.
##
## `_pred_pos` is the prediction proper and `_pred_error` is a purely visual
## offset that a correction is bled off through. They are kept apart so that a
## correction never feeds back into the simulation: the body moves from where
## the host says it is, and is only DRAWN somewhere slightly else.
func _net_predict(delta: float) -> void:
	if phase != Phase.PLAYING or player == null or not is_instance_valid(player) \
			or player.is_dead():
		return
	# A Nobles Cup kickoff holds everyone still, and the freeze is in the stream.
	# Predicting through it would walk the client off its spot and then have the
	# host drag it back on the next packet, which is the one correction big
	# enough to look like a bug.
	if cup != null and cup.frozen(now):
		return
	var dir := Vector3.ZERO
	if OS.get_environment("NS3_AUTOWALK") != "":
		# Honoured here as well as in _run_playing: a client's stick is the only
		# thing prediction reacts to, so without this the harness has no way to
		# make a predicted fighter move at all.
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
	dir = dir.limit_length(1.0)
	var face := Vector3.ZERO   # aim-stick facing, so the host can mirror it
	var aim: TouchStick = super_stick if super_stick.active else aim_stick
	if aim.active and aim.value.length() > 0.15:
		face = Vector3(aim.value.x, 0, aim.value.y)
	_input_seq = (_input_seq + 1) & 0xFFFF
	_net_input.rpc_id(1, _input_seq, dir, face)

	if face.length() > 0.1:
		player.face_direction(face)
	player.position = _pred_pos
	player.apply_movement(dir)
	_pred_pos = player.position
	_pred_hist.append([_input_seq, dir, _pred_pos])
	while _pred_hist.size() > NET_INPUT_HISTORY:
		_pred_hist.pop_front()
	if _pred_error.length_squared() > 0.0:
		_pred_error *= exp(-NET_PRED_FIX_RATE * delta)
		if _pred_error.length() < 0.004:
			_pred_error = Vector3.ZERO
	player.position = _pred_pos + _pred_error

	# NS3_AUTOFIRE, which lives in _run_playing and so did nothing at all on a
	# client. It is how the harness gets a client to deal damage, which is the
	# only way to tell a real stat table apart from a table of the zeros a
	# client's own Fighter.stats always hold.
	if auto_fire > 0.0 and now - _last_auto_fire >= auto_fire:
		_last_auto_fire = now
		var weapon: Dictionary = player.kit["super"] if player.is_super_ready() \
				else player.kit.weapon
		var target := auto_aim_target(player, weapon)
		var shot_dir := player.facing
		var shot_dist: float = weapon.range
		if target:
			shot_dir = target.global_position - player.global_position
			shot_dist = shot_dir.length()
		_fire_player(weapon, shot_dir, shot_dist)

## Everyone but me, drawn at `NET_INTERP_DELAY` behind the host clock, between
## the two snapshots that bracket that instant.
##
## The discrete half of a snapshot (health, ammo, the gas ring, the fighters-left
## count) is applied at the same delayed instant rather than off the newest
## packet, so a hit flash lands on the frame the body is drawn where it was hit.
func _net_render_puppets(delta: float) -> void:
	if _snap_buf.is_empty() or not _clock_synced:
		return
	var render_t: float = now - _host_offset - NET_INTERP_DELAY
	for s: Dictionary in _snap_buf:
		if float(s.t) <= render_t and float(s.t) > _snap_applied_t:
			_apply_snapshot_state(s)
			_snap_applied_t = float(s.t)
	# Two samples are always kept: the pair the render clock sits between, and
	# the pair a starved buffer extrapolates from.
	while _snap_buf.size() > 2 and float(_snap_buf[1].t) <= render_t:
		_snap_buf.pop_front()
	var a: Dictionary = _snap_buf[0]
	var b: Dictionary = a
	var u := 0.0
	if _snap_buf.size() >= 2:
		b = _snap_buf[1]
		var span: float = float(b.t) - float(a.t)
		if span > 0.0001:
			u = (render_t - float(a.t)) / span
			u = clampf(u, 0.0, 1.0 + NET_EXTRAP_MAX / span)
			if u > 1.0:
				_stat_starved += 1
	for i in net_fighters.size():
		if i == _my_idx:
			continue   # mine is predicted, not interpolated
		var f = net_fighters[i]
		if f == null or not is_instance_valid(f) or f.is_dead():
			continue
		var has_a: bool = a.f.has(i)
		var has_b: bool = b.f.has(i)
		if not has_a and not has_b:
			continue   # they were already down in both samples
		var sa: Dictionary = a.f[i] if has_a else b.f[i]
		var sb: Dictionary = b.f[i] if has_b else sa
		var pa: Vector3 = sa.pos
		var pb: Vector3 = sb.pos
		var prev: Vector3 = f.position
		f.position = pa.lerp(pb, u)
		f.rotation.y = lerp_angle(float(sa.rot), float(sb.rot), clampf(u, 0.0, 1.0))
		f.facing = Vector3(-sin(f.rotation.y), 0, -cos(f.rotation.y))
		f.velocity = (f.position - prev) / delta   # drives run/idle animation
	# A LOOSE ball is a puppet like any other and is interpolated on the same
	# delayed clock, not snapped to the newest packet. It is the fastest thing on
	# the pitch — a Super Shot leaves at 28 m/s, which is nearly a metre between
	# snapshots — so taking it straight off the stream at 30 Hz would show as a
	# ball stepping across the grass on a 60 fps screen. A CARRIED ball is not
	# touched here: CupMode._client_tick rides it in its carrier's hands.
	if cup != null and cup.ball != null and cup.ball.carrier == null \
			and a.has("cup") and b.has("cup"):
		var ball_at: Vector3 = (a.cup.pos as Vector3).lerp(b.cup.pos as Vector3, clampf(u, 0.0, 1.0))
		cup.ball.position = Vector3(ball_at.x, Ball.LOOSE_HEIGHT, ball_at.z)

## The half of a snapshot that is state rather than motion. Skips my own
## fighter, whose numbers were applied the moment they arrived — his body is
## drawn at `now`, so delaying his health bar to match everyone else's would put
## his own hit flash behind his own screen.
func _apply_snapshot_state(s: Dictionary) -> void:
	# Nobles Cup owns this corner of the HUD with its own score and clock, and
	# "6 LEFT" over the top of them is both wrong and permanent — nobody leaves a
	# Cup match.
	if cup == null:
		players_label.text = "%d LEFT" % int(s.left)
	elif s.has("cup"):
		cup.apply_net_state(now, s.cup)
	if phase == Phase.COUNTDOWN and int(s.phase) == int(Phase.PLAYING):
		phase = Phase.PLAYING
		match_start = now
		center_label.text = "FIGHT!"
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if phase == Phase.PLAYING:
				center_label.text = "")
	# The ring's inset is a FLOAT that eases between steps, so it rides the wire
	# as fixed point rather than as the whole tiles it used to be. Rounding it to
	# an int here would hand the client back exactly the two-tile teleport the
	# ease exists to remove, while the host glided — the wall would jump on one
	# screen and creep on the other.
	var inset: float = float(s.inset)
	if inset >= 0.0:
		if gas == null:
			gas = GasRing.new()
			add_child(gas)
			gas.map_tiles = arena.columns
		# Assigned every snapshot, with no equality check and no rebuild: the
		# overlay is built once and `GasRing._process` syncs it to whatever
		# `inset` says each frame, so a client eases for free. `start()` is
		# deliberately NOT called — that would run the shrink schedule and the
		# gas damage loop locally underneath the host's authoritative stream.
		gas.inset = inset
	for i: int in s.f:
		if i == _my_idx or i >= net_fighters.size():
			continue
		_apply_fighter_state(net_fighters[i], s.f[i])

func _apply_fighter_state(f, st: Dictionary) -> void:
	if f == null or not is_instance_valid(f) or f.is_dead():
		return
	f.max_health = int(st.max_health)
	var h := int(st.health)
	if h < f.health:
		f.take_damage(f.health - h, now)   # flash + damage popup
	else:
		f.health = h
	f.ammo = float(st.ammo)
	f.super_charge = float(st.super)
	f.cubes = int(st.cubes)
	f.heat_hits = int(st.heat)
	f.on_fire_until = now + float(st.fire)
	f.burn_until = now + float(st.burn)
	if float(st.burn) > 0.0 and f._burn_glow == null:
		f._setup_burn_glow()

# MARK: net snapshot wire format
# A snapshot as a Variant Array of Arrays costs about twelve bytes a field once
# Godot has tagged every number as a double: ~1.4 KB for ten fighters, 42 KB/s
# at 30 Hz, which a LAN swallows and a phone on a busy access point does not.
# Packed and quantised the same snapshot is a ten-byte header plus fifteen bytes
# per LIVING fighter, measured at about an eighth of the size (NS3_NET_STATS=1
# prints both, so the claim stays checkable rather than remembered).
#
# Nothing here is delta-encoded against the previous snapshot. The stream is
# unreliable: a field only sent when it changes is a field lost for good when
# that one packet drops, and the ack scheme that fixes it costs more — in state
# on both sides and in bugs — than the bytes it would save at this size.
#
# Quantisation, and why each is enough: position to a centimetre (the fighter
# capsule is 0.65 m across), facing to 1/256 of a turn (1.4 degrees, on a body
# that is 70 px wide on screen), ammo to 1/32 of a pip, Super charge to 1/255 of
# the bar, and the two burn clocks to a sixteenth of a second.

func _snapshot_bytes() -> PackedByteArray:
	var live: Array[int] = []
	var mask := 0
	for i in net_fighters.size():
		var f = net_fighters[i]
		if f != null and is_instance_valid(f) and not f.is_dead():
			live.append(i)
			mask |= 1 << i
	var acks: Array = []
	for i in live:
		var f: Fighter = net_fighters[i]
		var peer := int(f.get_meta("peer", 0))
		if peer > 1 and _peer_inputs.has(peer):
			acks.append([i, int(_peer_inputs[peer].get("seq", 0)) & 0xFFFF])
	var buf := PackedByteArray()
	buf.resize(NET_HEADER_BYTES + live.size() * 15 + 1 + acks.size() * 3 \
			+ (NET_CUP_BYTES if cup else 0))
	buf.encode_float(0, now)
	buf.encode_u8(4, int(phase))
	buf.encode_s16(5, int(round(gas.inset * NET_INSET_SCALE)) if gas else -NET_INSET_SCALE)
	buf.encode_u8(7, mini(255, fighters.size()))
	buf.encode_u16(8, mask)
	# How far the HOST is into its countdown. The client cannot work this out for
	# itself: its own `phase_at` is stamped when IT finished building the match,
	# which is later than the host by the network hop plus however long its own
	# fighters took to load — seconds on a phone with cold GLBs. So its countdown
	# started late, ran behind, and was then cut off mid-number when the host's
	# PLAYING phase arrived in this same snapshot. Both machines now count the
	# host's clock, so they reach FIGHT! together.
	buf.encode_u8(10, clampi(int(round(maxf(0.0, now - phase_at) * 16.0)), 0, 255))
	var o := NET_HEADER_BYTES
	for i in live:
		var f: Fighter = net_fighters[i]
		buf.encode_u16(o, clampi(int(round(f.position.x * NET_POS_SCALE)), 0, 65535))
		buf.encode_u16(o + 2, clampi(int(round(f.position.z * NET_POS_SCALE)), 0, 65535))
		buf.encode_u8(o + 4, int(round(fposmod(f.rotation.y, TAU) / TAU * 256.0)) & 0xFF)
		buf.encode_u16(o + 5, clampi(f.health, 0, 65535))
		buf.encode_u16(o + 7, clampi(f.max_health, 0, 65535))
		buf.encode_u8(o + 9, clampi(int(round(f.ammo * 32.0)), 0, 255))
		buf.encode_u8(o + 10, clampi(int(round(f.super_charge * 255.0)), 0, 255))
		buf.encode_u8(o + 11, clampi(f.cubes, 0, 255))
		buf.encode_u8(o + 12, clampi(f.heat_hits, 0, 255))
		buf.encode_u8(o + 13, clampi(int(round(maxf(0.0, f.on_fire_until - now) * 16.0)), 0, 255))
		buf.encode_u8(o + 14, clampi(int(round(maxf(0.0, f.burn_until - now) * 16.0)), 0, 255))
		o += 15
	buf.encode_u8(o, acks.size())
	o += 1
	for a: Array in acks:
		buf.encode_u8(o, int(a[0]))
		buf.encode_u16(o + 1, int(a[1]))
		o += 3
	if cup:
		_encode_cup(buf, o)
	return buf

## Nobles Cup's eleven bytes, appended only in Cup — Showdown pays nothing for
## them. Everything here is state a client cannot derive: who is holding the
## ball, where a loose one is, the score, the clock, and the two flags that
## decide whether input is held.
##
## Nothing here is an EVENT. A goal, a knock-out, a respawn and a kickoff all
## arrive as reliable RPCs instead, for the same reason the elimination feed does
## in Showdown: they happen once, they are not recoverable from a later
## snapshot, and this stream is allowed to drop packets.
##
## The carrier rides as a roster INDEX rather than as the ball's position while
## carried, so a client draws the ball in its carrier's hands using its own copy
## of Ball._carry_point. That is what makes the ball follow the client's own
## PREDICTED fighter with no round trip when the client is the one carrying it.
func _encode_cup(buf: PackedByteArray, o: int) -> void:
	var carrier := 255
	if cup.ball.carrier != null:
		var at := net_fighters.find(cup.ball.carrier)
		if at >= 0:
			carrier = at
	buf.encode_u8(o, carrier)
	buf.encode_u16(o + 1, clampi(int(round(cup.ball.position.x * NET_POS_SCALE)), 0, 65535))
	buf.encode_u16(o + 3, clampi(int(round(cup.ball.position.z * NET_POS_SCALE)), 0, 65535))
	buf.encode_u8(o + 5, clampi(cup.score[0], 0, 255))
	buf.encode_u8(o + 6, clampi(cup.score[1], 0, 255))
	buf.encode_u16(o + 7, clampi(int(round(cup.clock * 16.0)), 0, 65535))
	# Time REMAINING on the kickoff hold, not a deadline: the two machines'
	# clocks are minutes apart and only the difference means anything. A
	# sixteenth of a second over a two-second freeze is far finer than the frame
	# it is read on.
	buf.encode_u8(o + 9, clampi(int(round(maxf(0.0, cup.frozen_left(now)) * 16.0)), 0, 255))
	buf.encode_u8(o + 10, (1 if cup.overtime else 0) | (2 if cup.finished else 0))

func _decode_snapshot(buf: PackedByteArray) -> Dictionary:
	if buf.size() < NET_HEADER_BYTES:
		return {}
	var snap := {"t": buf.decode_float(0), "phase": buf.decode_u8(4),
			"inset": float(buf.decode_s16(5)) / NET_INSET_SCALE, "left": buf.decode_u8(7),
			"elapsed": buf.decode_u8(10) / 16.0, "f": {}, "acks": {}}
	var mask := buf.decode_u16(8)
	var o := NET_HEADER_BYTES
	for i in 16:
		if mask & (1 << i) == 0:
			continue
		if o + 15 > buf.size():
			return snap
		snap.f[i] = {
			"pos": Vector3(buf.decode_u16(o) / NET_POS_SCALE, 0.0,
					buf.decode_u16(o + 2) / NET_POS_SCALE),
			"rot": buf.decode_u8(o + 4) / 256.0 * TAU,
			"health": buf.decode_u16(o + 5),
			"max_health": buf.decode_u16(o + 7),
			"ammo": buf.decode_u8(o + 9) / 32.0,
			"super": buf.decode_u8(o + 10) / 255.0,
			"cubes": buf.decode_u8(o + 11),
			"heat": buf.decode_u8(o + 12),
			"fire": buf.decode_u8(o + 13) / 16.0,
			"burn": buf.decode_u8(o + 14) / 16.0,
		}
		o += 15
	if o < buf.size():
		var n := buf.decode_u8(o)
		o += 1
		for j in n:
			if o + 3 > buf.size():
				break
			snap.acks[buf.decode_u8(o)] = buf.decode_u16(o + 1)
			o += 3
	if o + NET_CUP_BYTES <= buf.size():
		var flags := buf.decode_u8(o + 10)
		snap["cup"] = {
			"carrier": buf.decode_u8(o),
			"pos": Vector3(buf.decode_u16(o + 1) / NET_POS_SCALE, Ball.LOOSE_HEIGHT,
					buf.decode_u16(o + 3) / NET_POS_SCALE),
			"s0": buf.decode_u8(o + 5),
			"s1": buf.decode_u8(o + 6),
			"clock": buf.decode_u16(o + 7) / 16.0,
			"freeze": buf.decode_u8(o + 9) / 16.0,
			"overtime": (flags & 1) != 0,
			"finished": (flags & 2) != 0,
		}
	return snap

func _net_send_snapshot() -> void:
	var buf := _snapshot_bytes()
	if _net_stats_on:
		_stat_bytes += buf.size()
		_stat_packets += 1
		_stat_legacy += var_to_bytes(_legacy_snapshot()).size()
	_net_snapshot.rpc(buf)

## The pre-packing snapshot, kept ONLY as the thing NS3_NET_STATS measures the
## packed one against. Nothing sends it.
func _legacy_snapshot() -> Array:
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
	var out: Array = [int(phase), gas.inset if gas else -1, fighters.size(), states]
	if cup:
		# The Cup trailer counted too, or NS3_NET_STATS compares a packed
		# snapshot that carries the ball and the score against an unpacked one
		# that does not, and quietly understates its own saving.
		out.append([cup.ball.position.x, cup.ball.position.z,
				net_fighters.find(cup.ball.carrier) if cup.ball.carrier else -1,
				cup.score[0], cup.score[1], cup.clock, cup.frozen_left(now),
				cup.overtime, cup.finished])
	return out

# MARK: net client intake, clock and reconciliation

## Take delivery of everything that arrived since the last physics frame.
##
## Deliberately NOT done inside the RPC: reconciliation replays movement through
## `move_and_slide`, which is only legal inside `_physics_process`, and an RPC is
## delivered from the network poll. `now` does not advance outside the physics
## step either, so nothing is lost by waiting for it.
func _net_intake() -> void:
	for snap: Dictionary in _snap_intake:
		var raw: float = float(snap.recv) - float(snap.t)
		if not _clock_synced:
			_clock_synced = true
			_host_offset = raw
		else:
			# Minimum-filtered: the smallest local-minus-host difference seen is
			# the one that travelled with the least latency, so it is the best
			# estimate of the true offset. The upward creep stops one freakishly
			# fast packet from pinning the estimate low forever, which would eat
			# the interpolation buffer and leave every other packet late.
			_host_offset = minf(raw, _host_offset + 0.0006)
		if not _snap_buf.is_empty() and float(snap.t) <= float(_snap_buf.back().t):
			continue   # duplicate, or overtaken on the wire
		_snap_buf.append(snap)
		while _snap_buf.size() > 64:
			_snap_buf.pop_front()
		# My own fighter is not interpolated, so its state and its acknowledged
		# input are both used the moment they land rather than at render time.
		if _my_idx >= 0 and snap.f.has(_my_idx):
			var mine: Dictionary = snap.f[_my_idx]
			if phase == Phase.PLAYING:
				if snap.acks.has(_my_idx):
					_reconcile(int(snap.acks[_my_idx]), mine.pos as Vector3)
			elif player != null and is_instance_valid(player):
				_pred_pos = mine.pos            # still on the countdown; just sit there
				player.position = _pred_pos
			if player != null and is_instance_valid(player):
				_apply_fighter_state(player, mine)
		# Picking the ball up is MY event when it is me picking it up, so it is
		# taken off the newest packet rather than at the delayed render instant —
		# the same rule that already applies to my own health and ammo. Waiting
		# for the delayed clock put NET_INTERP_DELAY (85 ms) on top of the round
		# trip before the ball stuck to my hands, and running onto a loose ball
		# is the single most common thing a player does in this mode.
		if cup != null and snap.has("cup"):
			cup.apply_local_carry(int(snap.cup.carrier), _my_idx)
		if phase == Phase.COUNTDOWN and snap.has("elapsed"):
			# Newest packet, not the delayed render instant: a countdown is a
			# clock, and showing it 85 ms in the past is the one thing it must
			# not do when the number it reaches zero on is shared with the host.
			_net_count_elapsed = float(snap.elapsed)
			_net_count_at = now
	_snap_intake.clear()

## Fold the host's word on where I was into where I think I am.
##
## The host acknowledges the last input it applied; the client kept the position
## each of its own inputs produced. If the two agree at that input, everything
## since is sound and there is nothing to do — which is the normal case, and the
## reason the tolerance test comes before the replay. If they disagree, the body
## is put where the host says it was and every input the host has not seen yet is
## run through `apply_movement` again from there, so walls and water resolve on
## the corrected path rather than being teleported through.
##
## The correction is applied to the SIMULATION immediately and to the PICTURE
## over the next fraction of a second: `_pred_error` absorbs the jump and decays.
## Without that split, a client on a lossy link twitches on every packet.
func _reconcile(seq: int, auth: Vector3) -> void:
	if player == null or not is_instance_valid(player) or player.is_dead():
		return
	var at := -1
	for i in _pred_hist.size():
		if int(_pred_hist[i][0]) == seq:
			at = i
			break
	if at < 0:
		return   # acking an input we no longer hold; the next one will land
	var predicted: Vector3 = _pred_hist[at][2]
	var err := auth - predicted
	err.y = 0.0
	if _net_stats_on:
		# How far the local sim had drifted from the host's by the time the host
		# answered. This is THE number that says whether prediction is working:
		# with none at all it would be the whole round trip's worth of travel.
		_stat_err_sum += err.length()
		_stat_err_max = maxf(_stat_err_max, err.length())
		_stat_err_n += 1
	var pending: Array = _pred_hist.slice(at + 1)
	_pred_hist = pending
	if err.length() < NET_PRED_TOLERANCE:
		return
	var before := _pred_pos
	if err.length() > NET_PRED_HARD_SNAP:
		# Something the client could not have predicted. Easing across two and a
		# half metres is a fighter swimming; put them there.
		_pred_pos = auth
		_pred_error = Vector3.ZERO
		_pred_hist.clear()
		player.position = auth
		player.reset_physics_interpolation()
		return
	_pred_pos = auth
	player.position = auth
	var keep := mini(pending.size(), NET_REPLAY_MAX)
	for i in range(pending.size() - keep, pending.size()):
		player.apply_movement(pending[i][1])
		pending[i][2] = player.position
	_pred_pos = player.position
	_pred_error += before - _pred_pos
	player.position = _pred_pos + _pred_error

## Host: one input is consumed per physics tick. Two that arrive inside the same
## frame are both applied, a frame apart, instead of the first being overwritten
## and the client's own prediction of it corrected back out.
func _consume_input(peer: int) -> Dictionary:
	var q: Array = _peer_queue.get(peer, [])
	if not q.is_empty():
		_peer_inputs[peer] = q.pop_front()
	return _peer_inputs.get(peer, {})

func _queue_input(id: int, seq: int, move: Vector3, face: Vector3) -> void:
	var q: Array = _peer_queue.get(id, [])
	q.append({"seq": seq, "move": move, "face": face})
	while q.size() > NET_INPUT_QUEUE_MAX:
		q.pop_front()   # they are running ahead of us; drop the backlog
	_peer_queue[id] = q

# MARK: net debug hooks (NS3_NET_LAG / JITTER / LOSS / STATS)

## Deliver whatever the fake link has held long enough. Ordering is preserved
## the way the real channel preserves it: `unreliable_ordered` DISCARDS a packet
## that has been overtaken, so a jittered packet that would land out of order is
## dropped rather than delivered late.
func _net_drain_lag() -> void:
	while not _lag_snaps.is_empty() and float(_lag_snaps[0].at) <= now:
		var item: Dictionary = _lag_snaps.pop_front()
		_recv_snapshot(item.buf)
	while not _lag_inputs.is_empty() and float(_lag_inputs[0].at) <= now:
		var item: Dictionary = _lag_inputs.pop_front()
		_queue_input(int(item.id), int(item.seq), item.move, item.face)

func _lag_delay() -> float:
	return _net_lag + (randf_range(-_net_jitter, _net_jitter) if _net_jitter > 0.0 else 0.0)

## NS3_NET_KILL: put every remote player down on a schedule, so that the client's
## results card — which otherwise only appears when a bot gets lucky — happens at
## a time a screenshot can be aimed at.
func _net_kill_check() -> void:
	if _net_kill_at <= 0.0 or not net_host or now - match_start < _net_kill_at:
		return
	_net_kill_at = 0.0
	for f in fighters.duplicate():
		if is_instance_valid(f) and not f.is_dead() and int(f.get_meta("peer", 0)) > 1:
			f.health = 0
			_eliminate(f, "")

func _recv_snapshot(buf: PackedByteArray) -> void:
	var snap := _decode_snapshot(buf)
	if snap.is_empty():
		return
	snap["recv"] = now
	_snap_intake.append(snap)
	if _net_stats_on:
		_stat_bytes += buf.size()
		_stat_packets += 1

## Every two seconds: what the snapshot stream is actually costing, what the
## unpacked form would have cost, and how often the client ran out of buffered
## snapshots and had to extrapolate. Prints on both sides.
func _net_stats_tick() -> void:
	if not _net_stats_on or now - _stat_at < 2.0:
		return
	var span: float = maxf(0.001, now - _stat_at)
	var line := "[net] %s %d snap/s  %.1f KB/s" % [
			"out" if net_host else "in", int(round(_stat_packets / span)),
			_stat_bytes / span / 1024.0]
	if net_host:
		line += "  (unpacked would be %.1f KB/s, %.1fx)" % [
				_stat_legacy / span / 1024.0, float(_stat_legacy) / maxf(1.0, float(_stat_bytes))]
	else:
		line += "  buffer %d  offset %.0fms  extrapolated %d frames" % [
				_snap_buf.size(), _host_offset * 1000.0, _stat_starved]
		line += "  pred err avg %.0fcm max %.0fcm over %d acks" % [
				(_stat_err_sum / maxf(1.0, float(_stat_err_n))) * 100.0,
				_stat_err_max * 100.0, _stat_err_n]
	print(line)
	_stat_at = now
	_stat_bytes = 0
	_stat_packets = 0
	_stat_legacy = 0
	_stat_starved = 0
	_stat_err_sum = 0.0
	_stat_err_max = 0.0
	_stat_err_n = 0

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
			_my_kit_name, award, _net_rows(who), authoritative, null, not authoritative)
	if net_host:
		_update_rematch_note()

## The stat table for a net result. On the host it is the ordinary Showdown one.
## On a client, `Fighter.stats` are all zeros — `deal_damage` returns early when
## `not authoritative`, so the client never counts a hit it did not resolve — and
## the real numbers came down from the host with the elimination. If they somehow
## have not, the survival clock the client keeps itself is still honest, and one
## true row beats four invented ones.
func _net_rows(f: Fighter) -> Array:
	if authoritative:
		return _showdown_rows(f)
	var clock: float = maxf(0.0, now - match_start)
	if _my_net_stats.is_empty():
		return [["SURVIVED", _fmt_clock(clock)]]
	return [
		["DAMAGE DEALT", MenuUI.fmt(int(_my_net_stats.get("d", 0)))],
		["ELIMINATIONS", str(int(_my_net_stats.get("k", 0)))],
		["POWER CUBES", str(int(_my_net_stats.get("c", 0)))],
		["SURVIVED", _fmt_clock(float(_my_net_stats.get("s", clock)))],
	]

## Host: send a player the match stats only the host has. Everything a fighter
## did was resolved here, so this is the only place the numbers exist.
func _net_push_stats(f: Fighter) -> void:
	if not net_host or f == null or not is_instance_valid(f):
		return
	var peer := int(f.get_meta("peer", 0))
	# Still connected: the commonest reason a player's fighter is eliminated is
	# that the player LEFT, and `_on_net_peer_left` eliminates it from inside the
	# disconnect handler — by which point rpc_id to them is an engine error.
	if peer <= 1 or not multiplayer.get_peers().has(peer):
		return
	_net_stats.rpc_id(peer, {"d": int(f.stats.damage), "k": int(f.stats.kills),
			"c": int(f.stats.cubes), "s": float(f.stats.survived)})

## Host: one fighter (or none, if the gas closed) remains — end the match.
func _net_finish() -> void:
	phase = Phase.ENDED
	var idx := -1
	if fighters.size() == 1:
		idx = net_fighters.find(fighters[0])
		# The winner's clock stops here; everyone else's stopped in _eliminate.
		fighters[0].stats.survived = maxf(0.0, now - match_start)
		_net_push_stats(fighters[0])
	_net_match_over.rpc(idx)
	if idx >= 0 and fighters[0] == player:
		_net_show_results(1, true, player)
	elif idx >= 0 and results.visible and is_instance_valid(results_note):
		results_note.text = "%s wins!" % fighters[0].display_name
		results_note.visible = true

## Host: how many of the other players have asked for another match. The host is
## the only one who can deal one, so this is the line that tells them whether
## anybody is still waiting on the button.
func _update_rematch_note() -> void:
	if not net_host or results_wait == null or not is_instance_valid(results_wait):
		return
	var others: int = maxi(0, Net.players.size() - 1)
	if others <= 0:
		results_wait.visible = false
		return
	results_wait.text = "%d of %d ready for a rematch" % [_rematch_wanted.size(), others]
	results_wait.visible = true
	# NS3_NET_REMATCH: deal the next match once the room has asked for it. The
	# delay is so the card it is answering is on screen long enough to be shot.
	if _net_auto_rematch and not _net_rematch_fired and _rematch_wanted.size() >= others:
		_net_rematch_fired = true
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			results.visible = false
			_net_host_start())

## Whether there is still a peer to send to.
##
## The multiplayer peer is torn down BEFORE the scene stops ticking — closing the
## host window, or leaving for the lobby, drops it while `_physics_process` runs
## on for a few more frames. Each of those frames then tried to broadcast a
## snapshot and logged "Trying to call an RPC while no multiplayer peer is
## active" with a full backtrace, which is dozens of lines over a window being
## closed and buries whatever actually happened in the match just before it.
## Seen for real the first time a phone joined this host and the window was shut.
func _net_live() -> bool:
	if not net_active:
		return false
	var peer := multiplayer.multiplayer_peer
	return peer != null \
			and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

## MARK: Nobles Cup net events (host -> clients)
##
## The four things a Cup client cannot get from the snapshot stream, because each
## happens once and a dropped packet would lose it for good: a goal, a knock-out,
## a return from one, and a restart. CupMode calls these; they no-op outside wifi
## play, so single player runs the identical code path with nothing attached.

func net_cup_goal(conceded: int, who: String, own: bool) -> void:
	if net_host and _net_live():
		_net_cup_goal.rpc(conceded, who, own)

func net_cup_kickoff(opening: bool) -> void:
	if net_host and _net_live():
		_net_cup_kickoff.rpc(opening)

func net_cup_respawned(f: Fighter, spot: Vector3) -> void:
	if net_host and _net_live() and is_instance_valid(f):
		_net_cup_respawn.rpc(net_fighters.find(f), spot)

## A kick that actually left someone's hands — a player's, a remote player's or
## a bot's. CupMode.kick calls this after the launch, so the caller has already
## established that it was not swallowed for want of ammo or charge.
func net_cup_kick(f: Fighter, use_super: bool) -> void:
	if net_host and _net_live() and is_instance_valid(f):
		_net_cup_kick.rpc(net_fighters.find(f), use_super)

func _on_net_peer_left(id: int) -> void:
	_peer_inputs.erase(id)
	_peer_queue.erase(id)
	_net_ready_peers.erase(id)
	_rematch_wanted.erase(id)
	_update_rematch_note()
	if not _match_ready:
		return
	for f in fighters.duplicate():
		if not is_instance_valid(f) or int(f.get_meta("peer", 0)) != id:
			continue
		if cup != null:
			# Nobles Cup is 3v3 with no spare bodies, so a player who leaves
			# cannot simply be removed — that would hand their side a permanent
			# two-against-three. Their fighter is handed to a bot brain instead
			# and the match carries on at full strength. The peer meta is cleared
			# first so nothing downstream still treats the body as somebody's.
			f.set_meta("peer", 0)
			var taken := false
			for b in brains:
				if b.fighter == f:
					taken = true
					break
			if not taken:
				brains.append(BotBrain.new(f))
			feed_label.text = "%s left the game" % f.display_name
		elif not f.is_dead():
			_eliminate(f, "", true)

func _on_net_host_lost() -> void:
	center_label.text = "HOST LEFT"
	# The results card covers center_label, and a client sitting on one having
	# just asked for a rematch is exactly who needs telling.
	if results.visible and results_wait != null and is_instance_valid(results_wait):
		results_wait.text = "THE HOST LEFT — BACK TO THE LOBBY"
		results_wait.visible = true
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
		_net_start.rpc_id(id, _match_seq, mode, _net_roster)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_input(seq: int, move: Vector3, face: Vector3) -> void:
	if not net_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if _net_loss > 0.0 and randf() < _net_loss:
		return
	if _net_lag > 0.0:
		var at := now + _lag_delay()
		if at <= _lag_last_at:
			return   # overtaken: the ordered channel would have dropped it
		_lag_last_at = at
		_lag_inputs.append({"at": at, "id": id, "seq": seq, "move": move, "face": face})
		return
	_queue_input(id, seq, move, face)

## A client asks the host for another match. The host is the only peer that can
## deal a roster, so the flow is: everyone who wants one says so, the host sees
## the count on its own results card, and PLAY AGAIN pulls the whole room into
## the next match through the _net_start it already broadcasts.
@rpc("any_peer", "call_remote", "reliable")
func _net_rematch_request() -> void:
	if not net_host:
		return
	_rematch_wanted[multiplayer.get_remote_sender_id()] = true
	_update_rematch_note()

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
	# The same backstop _fire_player carries: a carrier may not fire a weapon,
	# and a Super spent while carrying goes into the ball. It has to be repeated
	# here because a client's input reaches the sim through this function and not
	# through that one.
	if cup != null and cup.kick(f, dir, now, use_super):
		return   # cup.kick announces the launch itself; see net_cup_kick
	if use_super:
		if f.consume_super():
			perform_attack(f, f.kit["super"], dir, dist)
	elif f.consume_ammo(now):
		perform_attack(f, f.kit.weapon, dir, dist)

# MARK: net RPCs (host -> clients)

@rpc("authority", "call_remote", "reliable")
func _net_start(seq: int, room_mode: String, roster: Array) -> void:
	if seq <= _net_seen_seq:
		return   # duplicate (re-sent for a late joiner)
	_net_seen_seq = seq
	_start_from_roster(room_mode, roster)

## `inset` is a float because `GasRing.inset` is: the ring eases between its
## steps rather than teleporting, so an int here would land the client's wall
## back on whole tiles and give it the jump the host no longer has.
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_snapshot(buf: PackedByteArray) -> void:
	if not _match_ready:
		return
	if _net_loss > 0.0 and randf() < _net_loss:
		return
	if _net_lag > 0.0:
		var at := now + _lag_delay()
		if at <= _lag_last_at:
			return   # overtaken: the ordered channel would have dropped it
		_lag_last_at = at
		_lag_snaps.append({"at": at, "buf": buf})
		return
	_recv_snapshot(buf)

## Host -> one client: what that player actually did this match. See _net_rows.
@rpc("authority", "call_remote", "reliable")
func _net_stats(payload: Dictionary) -> void:
	if net_host:
		return
	_my_net_stats = payload

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

# MARK: net RPCs (host -> clients, Nobles Cup)

## A fighter went down. The client parks the body itself rather than being sent
## a "hidden" flag, because going down is an animation and a feed line and a red
## wash, not a boolean — and CupMode.on_death is already all three.
##
## Health is zeroed FIRST: knock_out() does not touch it, and Fighter._hide_body
## and fighter_bars both ask is_dead(), so a body parked while still reading full
## health leaves its health bar hanging over an empty patch of pitch.
@rpc("authority", "call_remote", "reliable")
func _net_cup_down(idx: int, killer: String) -> void:
	if net_host or cup == null or idx < 0 or idx >= net_fighters.size():
		return
	var f = net_fighters[idx]
	if f == null or not is_instance_valid(f) or f.is_dead():
		return
	f.health = 0
	sfx_at("elimination", f.global_position, 3.0)
	if f == player:
		Haptics.fire("death")
		if not cup.overtime:
			_down_until = now + CupMode.RESPAWN_SECONDS
	cup.on_death(f, killer)

## Back on your feet, at the tile the HOST picked. The spot is sent rather than
## recomputed: CupMode._spawn_for takes the emptiest of the three goal-mouth
## tiles, and "emptiest" is measured against positions a client only holds a
## delayed copy of, so two machines choosing separately would choose differently.
@rpc("authority", "call_remote", "reliable")
func _net_cup_respawn(idx: int, spot: Vector3) -> void:
	if net_host or idx < 0 or idx >= net_fighters.size():
		return
	var f = net_fighters[idx]
	if f == null or not is_instance_valid(f):
		return
	f.respawn(spot, now)
	if f == player:
		_net_resync_prediction()

@rpc("authority", "call_remote", "reliable")
func _net_cup_goal(conceded: int, who: String, own: bool) -> void:
	if net_host or cup == null:
		return
	# The score itself is NOT applied here — it rides the snapshot, and applying
	# it twice would double every goal. This is the presentation only.
	cup.goal_effects(conceded, who, own)

@rpc("authority", "call_remote", "reliable")
func _net_cup_kickoff(opening: bool) -> void:
	if net_host or cup == null:
		return
	cup.kickoff(now, opening)
	_net_resync_prediction()

## Anything that TELEPORTS the client's own fighter has to say so here.
##
## `_net_predict` starts each frame with `player.position = _pred_pos`, so a
## kickoff or a respawn that moved the body without moving the prediction is
## undone on the first frame after the freeze lifts — the fighter snaps back to
## wherever it was standing when the goal went in, holds for the round trip it
## takes the host to disagree, and is then dragged forward again. It reads as the
## respawn simply not working. Both of those moves are also exactly the case
## `_reconcile` cannot smooth (they are far past NET_PRED_HARD_SNAP), so the
## history is dropped rather than replayed against a position it never predicted.
func _net_resync_prediction() -> void:
	if player == null or not is_instance_valid(player):
		return
	_pred_pos = player.position
	_pred_error = Vector3.ZERO
	_pred_hist.clear()

## A kick that actually left someone's hands, for its sound and its animation.
## The ball's own motion needs nothing from this: it is already in the stream.
@rpc("authority", "call_remote", "reliable")
func _net_cup_kick(idx: int, use_super: bool) -> void:
	if net_host or cup == null or idx < 0 or idx >= net_fighters.size():
		return
	var f = net_fighters[idx]
	if f == null or not is_instance_valid(f) or f.is_dead():
		return
	sfx_at("super_fire" if use_super else "cup_kick", f.global_position,
			3.0 if use_super else 0.0)
	if f == player:
		Haptics.fire("super_shot" if use_super else "kick")
	f.play_attack_animation(now, use_super)

## Full time, with the host's scoreboard. `you` is re-marked against this
## machine's own roster index: the host sent the table with ITS row flagged.
@rpc("authority", "call_remote", "reliable")
func _net_cup_over(blue: int, red: int, rows: Array) -> void:
	if net_host or cup == null:
		return
	cup.finished = true
	for row in rows:
		row["you"] = int(row.get("idx", -1)) == _my_idx
	end_cup_match(blue, red, rows)
