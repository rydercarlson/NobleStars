extends Node
## LAN multiplayer plumbing, autoloaded as `Net` (see project.godot).
## Owns the ENet connection, the pre-match room roster, and wifi game
## discovery (UDP broadcast probe/reply). Match replication lives in main.gd.
##
## iOS note: an iPhone cannot receive the broadcast half of this without Apple's
## multicast entitlement, so discovery finds nothing there — neither the probe a
## browsing phone would have to hear replies to, nor the probe a HOSTING phone
## would have to hear in the first place. `discovery_works()` is what the room
## screen reads to decide whether to lead with the games list or with the
## join-by-IP field, and on iOS it is the field.

signal roster_changed
signal join_failed(reason: String)
signal host_disconnected
signal games_updated

const GAME_PORT := 42537
const DISCOVERY_PORT := 42538
const PROBE := "NS3_FIND_V1"
const REPLY := "NS3_HOST_V1"
const MAX_PLAYERS := 10
## Where the last address joined by hand is kept. Typing an IPv4 address on a
## phone keyboard is the whole cost of the iOS flow, and it is the same address
## every time in one house — so it is remembered across launches rather than
## across a session. Its own tiny file: the save is the player's progress and
## has no business carrying a LAN address.
const LAN_FILE := "user://lan.cfg"

var active := false            # hosting or joined (room or match)
var locked := false            # host started the match; no new joins
var players: Dictionary = {}   # peer_id -> {"name": String, "kit": String}
var games: Dictionary = {}     # host ip -> {"name": String, "count": int, "seen": float}
var last_ip := ""              # last address joined by hand; see LAN_FILE

var _pending: Dictionary = {}  # my name/kit while a join handshake is in flight
var _discovery: PacketPeerUDP  # host side: answers probes
var _probe: PacketPeerUDP      # client side: browses for games
var _next_probe_at := 0.0

func is_host() -> bool:
	return active and multiplayer.is_server()

## Whether UDP broadcast discovery can be relied on here. False on iOS, where
## both halves of it need the multicast entitlement.
##
## `NS3_FAKE_IOS=1` forces the false branch on a desktop. Without it the iOS
## room layout can only be looked at on a phone, and the phone is the one place
## this project cannot take a screenshot.
func discovery_works() -> bool:
	return OS.get_name() != "iOS" and OS.get_environment("NS3_FAKE_IOS") == ""

func _ready() -> void:
	_load_last_ip()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: _fail("Could not reach host"))
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# MARK: host / join / leave

func host_game(player_name: String, kit: String) -> Error:
	browse_stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	locked = false
	players = {1: {"name": player_name, "kit": kit}}
	_discovery = PacketPeerUDP.new()
	_discovery.bind(DISCOVERY_PORT)
	roster_changed.emit()
	return OK

func join_game(ip: String, player_name: String, kit: String) -> void:
	browse_stop()
	var peer := ENetMultiplayerPeer.new()
	var address := ip.strip_edges()
	if peer.create_client(address, GAME_PORT) != OK:
		join_failed.emit("Bad address")
		return
	remember_ip(address)
	multiplayer.multiplayer_peer = peer
	active = true
	players = {}
	_pending = {"name": player_name, "kit": kit}

func remember_ip(ip: String) -> void:
	var address := ip.strip_edges()
	if address == "" or address == last_ip:
		return
	last_ip = address
	var cfg := ConfigFile.new()
	cfg.set_value("lan", "last_ip", address)
	cfg.save(LAN_FILE)

func _load_last_ip() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAN_FILE) == OK:
		last_ip = String(cfg.get_value("lan", "last_ip", ""))

func leave() -> void:
	active = false
	locked = false
	players = {}
	_pending = {}
	if _discovery:
		_discovery.close()
		_discovery = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	roster_changed.emit()

## Host presses START: lock the room and pull everyone into the match scene.
func start_game() -> void:
	if not is_host():
		return
	locked = true
	_rpc_start_game.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_start_game() -> void:
	print("[net] match starting (%d players)" % players.size())
	SaveGame.ensure_loaded()
	Session.kit = Kits.named(SaveGame.selected_kit)
	Session.mode = "showdown"
	get_tree().change_scene_to_file("res://game.tscn")

## The LAN IP to show the host so friends can join by address.
func local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return ""

# MARK: connection plumbing

func _on_connected_to_server() -> void:
	print("[net] connected to host, registering as %s" % _pending.get("name", "Star"))
	_register.rpc_id(1, _pending.get("name", "Star"), _pending.get("kit", "Nova"))

func _on_peer_connected(id: int) -> void:
	if is_host() and (locked or players.size() >= MAX_PLAYERS):
		multiplayer.multiplayer_peer.disconnect_peer(id)

func _on_peer_disconnected(id: int) -> void:
	if is_host() and players.has(id):
		players.erase(id)
		_sync_roster.rpc(players)
		roster_changed.emit()

func _on_server_disconnected() -> void:
	leave()
	host_disconnected.emit()

func _fail(reason: String) -> void:
	print("[net] join failed: %s" % reason)
	leave()
	join_failed.emit(reason)

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, kit: String) -> void:
	if not is_host():
		return
	print("[net] %s joined (peer %d)" % [player_name, multiplayer.get_remote_sender_id()])
	players[multiplayer.get_remote_sender_id()] = {"name": player_name, "kit": kit}
	_sync_roster.rpc(players)
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_roster(roster: Dictionary) -> void:
	players = roster
	roster_changed.emit()

# MARK: wifi discovery

func browse_start() -> void:
	if _probe:
		return
	_probe = PacketPeerUDP.new()
	_probe.bind(0)   # ephemeral port so the host's reply can find us
	_probe.set_broadcast_enabled(true)
	games = {}
	_next_probe_at = 0.0

func browse_stop() -> void:
	if _probe:
		_probe.close()
		_probe = null
	games = {}

func _process(_delta: float) -> void:
	var clock := Time.get_ticks_msec() / 1000.0
	# Host: answer "anyone hosting?" probes with our name + player count.
	if _discovery:
		while _discovery.get_available_packet_count() > 0:
			var msg := _discovery.get_packet().get_string_from_utf8()
			if msg == PROBE and is_host() and not locked:
				_discovery.set_dest_address(_discovery.get_packet_ip(), _discovery.get_packet_port())
				var me: Dictionary = players.get(1, {"name": "Star"})
				_discovery.put_packet(("%s|%s|%d" % [REPLY, me.name, players.size()]).to_utf8_buffer())
	# Browser: probe the subnet every second, collect replies, expire stale ones.
	if _probe:
		if clock >= _next_probe_at:
			_next_probe_at = clock + 1.0
			_probe.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_probe.put_packet(PROBE.to_utf8_buffer())
		var changed := false
		while _probe.get_available_packet_count() > 0:
			var parts := _probe.get_packet().get_string_from_utf8().split("|")
			if parts.size() == 3 and parts[0] == REPLY:
				games[_probe.get_packet_ip()] = {"name": parts[1], "count": int(parts[2]), "seen": clock}
				changed = true
		for ip in games.keys():
			if clock - games[ip].seen > 4.0:
				games.erase(ip)
				changed = true
		if changed:
			games_updated.emit()
