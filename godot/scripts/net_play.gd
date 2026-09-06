extends Node
## LAN multiplayer plumbing, autoloaded as `Net` (see project.godot).
## Owns the ENet connection, the pre-match room roster, the room's MODE, and
## wifi game discovery. Match replication lives in main.gd.
##
## Two ways in, and no server behind either of them. Discovery finds games on
## the wifi by itself; a JOIN CODE is four characters that a friend can read out
## across a room. There is nothing to look the code up in, so the code IS the
## address, compressed — see the join code section below.

signal roster_changed
signal join_failed(reason: String)
signal host_disconnected
signal games_updated

const GAME_PORT := 42537
const DISCOVERY_PORT := 42538
const PROBE := "NS3_FIND_V1"
const REPLY := "NS3_HOST_V1"
## Room capacity by mode. Showdown fills its empty slots with bots, so any
## number up to ten plays; Nobles Cup is 3v3 and six is the whole pitch.
const MAX_PLAYERS := 10
const CUP_PLAYERS := 6
## Where the last address joined by hand is kept. Typing on a phone keyboard is
## the whole cost of the manual flow, and it is the same host every time in one
## house — so it is remembered across launches rather than across a session. Its
## own tiny file: the save is the player's progress and has no business carrying
## a LAN address.
const LAN_FILE := "user://lan.cfg"

var active := false            # hosting or joined (room or match)
var locked := false            # host started the match; no new joins
var players: Dictionary = {}   # peer_id -> {"name": String, "kit": String}
var games: Dictionary = {}     # host ip -> {"name", "count", "mode", "cap", "seen"}
var last_ip := ""              # last address joined by hand; see LAN_FILE
## Which mode the room will play. Owned by the host and pushed to everyone with
## the roster, because it decides the room's capacity as well as the match —
## a client showing "SHOWDOWN" while the host deals a 3v3 is a lie the client
## finds out about by being dropped.
var mode := "showdown"

var _pending: Dictionary = {}  # my name/kit while a join handshake is in flight
var _discovery: PacketPeerUDP  # host side: answers probes
var _probe: PacketPeerUDP      # client side: browses for games
var _next_probe_at := 0.0
var _next_sweep_at := 0.0
var _sweep_at := 0             # next host index in the unicast sweep, 0 = idle
var _sweep_bits := 24          # prefix width being swept; widens when nothing answers
var _log_probes := OS.get_environment("NS3_NET_STATS") != ""
var _last_probe_from := ""     # only announce each searcher once

func is_host() -> bool:
	return active and multiplayer.is_server()

## How many may sit in the room at once, this mode.
func room_capacity() -> int:
	return CUP_PLAYERS if mode == "cup" else MAX_PLAYERS

# MARK: join codes
#
# A short code that a friend reads out, with no server anywhere to look it up in
# — so the code cannot REFER to the address, it has to BE the address. That is
# affordable because a LAN address is not much information, and the commonest
# ones are the least: a home router hands out 192.168.a.b, which is sixteen bits,
# and sixteen bits is four characters of base 32.
#
# THREE WIDTHS, told apart by LENGTH, so the common case stays short without the
# uncommon ones being unreachable:
#   4 chars  192.168.a.b                      (16 bits)  home wifi
#   5 chars  10.a.b.c and 172.16-31.a.b       (25 bits)  bigger private networks
#   7 chars  any other IPv4                   (32 bits)  campus/managed networks
#             that route public addresses to the client
# The seven-character case is the catch-all and covers every remaining address,
# so there is no network on which a host has no code at all. A six-character code
# is not issued by anything and is rejected.
#
# The alphabet drops every character that can be misread aloud or mistyped —
# no 0/O, no 1/I/L — which is what leaves exactly 32.
#
# The number is multiplied by an odd constant mod 32^width before it is spelled
# out, and by that constant's modular inverse on the way back. Two reasons, both
# real. Addresses are small numbers, so without it a house on 192.168.1.x gets
# codes that all begin "22" and the code stops looking like a code. And because
# the scramble spreads the address across the whole code space, a mistyped code
# now usually decodes to NOTHING rather than to somebody else's machine — 94% of
# random four-character strings are rejected outright, and 88% of seven.
const CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
## Per width: [scramble, its modular inverse, bits]. Each multiplier is odd and
## therefore invertible mod 2^bits; the inverse is stored beside it so the pair
## cannot drift apart. Verified exhaustively over 192.168.* and over 300k random
## addresses of every other shape.
const CODE_KEYS := {
	4: [742039, 609575, 20],
	5: [30590391, 6825991, 25],
	7: [97821211, 31338227731, 35],
}
## Where each family starts in the encoded number line. 192.168.* occupies the
## bottom 65536 on its own, which is what lets it fit in four characters.
const CODE_BASE_172 := 65536
const CODE_BASE_10 := 1114112
const CODE_MAX_PRIVATE := 17891327

## (a * b) mod 2^bits, without ever forming a product that overflows.
##
## Godot ints are 64-bit, and the seven-character width multiplies a 35-bit
## number by a 35-bit constant — 70 bits, which silently wraps and gives a code
## that does not decode back to the address it came from. The modulus is a power
## of two, so the multiplicand can be split in half and the halves reduced
## separately: discarding the high bits of the upper half early cannot change the
## low bits of the answer. The widest intermediate this leaves is 2^53.
static func _mulmod(a: int, b: int, bits: int) -> int:
	var mask: int = (1 << bits) - 1
	var half: int = bits / 2
	var lo: int = a & ((1 << half) - 1)
	var hi: int = a >> half
	return (lo * b + ((((hi * b) & (mask >> half)) << half))) & mask

## The code for an address. Never empty for a well-formed IPv4 — the
## seven-character width is the catch-all.
static func ip_to_code(ip: String) -> String:
	var o := ip.strip_edges().split(".")
	if o.size() != 4:
		return ""
	var a := [int(o[0]), int(o[1]), int(o[2]), int(o[3])]
	for part in a:
		if part < 0 or part > 255:
			return ""
	var n := 0
	var width := 7
	if a[0] == 192 and a[1] == 168:
		n = a[2] * 256 + a[3]
		width = 4
	elif a[0] == 172 and a[1] >= 16 and a[1] <= 31:
		n = CODE_BASE_172 + (a[1] - 16) * 65536 + a[2] * 256 + a[3]
		width = 5
	elif a[0] == 10:
		n = CODE_BASE_10 + a[1] * 65536 + a[2] * 256 + a[3]
		width = 5
	else:
		n = (a[0] << 24) | (a[1] << 16) | (a[2] << 8) | a[3]
	var key: Array = CODE_KEYS[width]
	n = _mulmod(n, int(key[0]), int(key[2]))
	var out := ""
	for _i in width:
		out = CODE_ALPHABET[n % 32] + out
		n /= 32
	return out

## The address a code names, or "" if it is not a code we could have issued.
## Rejects rather than guesses: a mistyped code must fail here, not connect to
## whoever happens to live at the address it landed on.
static func code_to_ip(code: String) -> String:
	var c := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if not CODE_KEYS.has(c.length()):
		return ""
	var n := 0
	for i in c.length():
		var at := CODE_ALPHABET.find(c[i])
		if at < 0:
			return ""
		n = n * 32 + at
	var key: Array = CODE_KEYS[c.length()]
	n = _mulmod(n, int(key[1]), int(key[2]))
	if c.length() == 4:
		if n > 65535:
			return ""
		return "192.168.%d.%d" % [n >> 8, n & 255]
	if c.length() == 5:
		if n < CODE_BASE_172 or n > CODE_MAX_PRIVATE:
			return ""
		if n < CODE_BASE_10:
			n -= CODE_BASE_172
			return "172.%d.%d.%d" % [16 + (n >> 16), (n >> 8) & 255, n & 255]
		n -= CODE_BASE_10
		return "10.%d.%d.%d" % [n >> 16, (n >> 8) & 255, n & 255]
	if n > 0xFFFFFFFF:
		return ""
	return "%d.%d.%d.%d" % [n >> 24, (n >> 16) & 255, (n >> 8) & 255, n & 255]

## What the player typed, as an address: a join code, or an IP typed out in full.
## Both are accepted in the one field — the code is what is advertised, and an
## address still works for anyone reading it off a router page.
static func resolve_target(text: String) -> String:
	var t := text.strip_edges()
	if t.count(".") == 3:
		return t
	return code_to_ip(t)

## This machine's own code, for the host to print. Empty if we could not find a
## private address to encode, in which case the room screen falls back to the IP.
func join_code() -> String:
	return ip_to_code(local_ip())

## The code for the last host joined by hand, to prefill the field with.
func last_code() -> String:
	return ip_to_code(last_ip)

## Whether UDP BROADCAST is available here. False on iOS, where sending to
## 255.255.255.255 needs Apple's multicast entitlement — which is why the games
## list is also swept by unicast instead (see the wifi discovery section).
##
## `NS3_FAKE_IOS=1` forces the false branch on a desktop. Without it the iOS
## room layout can only be looked at on a phone, and the phone is the one place
## this project cannot take a screenshot.
func broadcast_works() -> bool:
	return OS.get_name() != "iOS" and OS.get_environment("NS3_FAKE_IOS") == ""

func _ready() -> void:
	_load_last_ip()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: _fail("Could not reach host"))
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# MARK: host / join / leave

func host_game(player_name: String, kit: String, room_mode := "showdown") -> Error:
	browse_stop()
	var peer := ENetMultiplayerPeer.new()
	mode = room_mode
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	locked = false
	players = {1: {"name": player_name, "kit": kit}}
	_discovery = PacketPeerUDP.new()
	# Checked, because a failure here is SILENT and looks exactly like "iOS
	# blocked discovery": the room hosts fine, the game is joinable by code, and
	# nothing on the wifi can see it. It fails when something else already holds
	# the port — most often a previous instance of this game that did not shut
	# down — and that cost an hour of blaming the sweep for it.
	if _discovery.bind(DISCOVERY_PORT) != OK:
		push_warning("[net] discovery port %d busy — this room will not appear on the wifi (the join code still works)" % DISCOVERY_PORT)
		print("[net] discovery port %d busy; code-only hosting" % DISCOVERY_PORT)
		_discovery = null
	roster_changed.emit()
	return OK

## Host: change the room's mode. Pushed to everyone, because it decides how many
## may sit in the room as well as which match is dealt.
func set_mode(room_mode: String) -> void:
	if not is_host() or mode == room_mode:
		return
	mode = room_mode
	_sync_roster.rpc(players, mode)
	roster_changed.emit()

## `target` is a join code or an IP address; both arrive in the one field.
func join_game(target: String, player_name: String, kit: String) -> void:
	browse_stop()
	var address := resolve_target(target)
	if address == "":
		join_failed.emit("That code doesn't look right")
		return
	var peer := ENetMultiplayerPeer.new()
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
	_rpc_start_game.rpc(mode)

@rpc("authority", "call_local", "reliable")
func _rpc_start_game(room_mode: String) -> void:
	print("[net] match starting (%d players, %s)" % [players.size(), room_mode])
	SaveGame.ensure_loaded()
	Session.kit = Kits.named(SaveGame.selected_kit)
	# The host's mode, not this machine's menu pick. Everything downstream reads
	# Session.mode — the loading screen's title, the arena's map, main.gd's mode
	# branch — so setting it here is the whole of what makes a wifi Cup match a
	# Cup match on every peer.
	Session.mode = room_mode
	mode = room_mode
	get_tree().change_scene_to_file("res://game.tscn")

## The address a peer connected from.
##
## Printed on every join because it is the only place the host learns which
## SUBNET the other machine is on, and that is exactly what decides whether the
## unicast sweep could ever have found this room. A phone one /24 over joins
## perfectly happily by code and then never sees a single game in the list —
## which looks like iOS blocking discovery and is nothing of the sort.
func peer_address(id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return "?"
	var p := enet.get_peer(id)
	return p.get_remote_address() if p != null else "?"

## This machine's address on the network it shares with its friends: what the
## join code is built from, and what the room screen prints.
##
## Searched in preference order rather than "first match wins". A laptop with a
## VPN up, a container bridge, or both wired and wireless has several addresses,
## and the code has to name the one a friend can actually reach. Loopback and
## link-local (169.254.*, the address an interface invents when DHCP failed) are
## never it. Anything else is allowed through, INCLUDING public addresses —
## managed networks like a school's often route real addresses to the client, and
## rejecting those was what left a host there with no code at all.
func local_ip() -> String:
	var private := ""
	var other := ""
	for ip in IP.get_local_addresses():
		var o := ip.split(".")
		if o.size() != 4 or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		if ip.begins_with("192.168."):
			return ip
		if private == "" and (ip.begins_with("10.") \
				or (o[0] == "172" and int(o[1]) >= 16 and int(o[1]) <= 31)):
			private = ip
		elif other == "":
			other = ip
	return private if private != "" else other

# MARK: connection plumbing

func _on_connected_to_server() -> void:
	print("[net] connected to host, registering as %s" % _pending.get("name", "Star"))
	_register.rpc_id(1, _pending.get("name", "Star"), _pending.get("kit", "Nova"))

func _on_peer_connected(id: int) -> void:
	if is_host() and (locked or players.size() >= room_capacity()):
		multiplayer.multiplayer_peer.disconnect_peer(id)

func _on_peer_disconnected(id: int) -> void:
	if is_host() and players.has(id):
		players.erase(id)
		_sync_roster.rpc(players, mode)
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
	var joiner := multiplayer.get_remote_sender_id()
	print("[net] %s joined (peer %d) from %s" % [player_name, joiner, peer_address(joiner)])
	players[joiner] = {"name": player_name, "kit": kit}
	_sync_roster.rpc(players, mode)
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_roster(roster: Dictionary, room_mode: String) -> void:
	players = roster
	mode = room_mode
	roster_changed.emit()

# MARK: wifi discovery
#
# Two ways of asking "anyone hosting?", and a browsing machine uses both.
# BROADCAST is one packet to 255.255.255.255 and is what a desktop on a home
# network uses. A SWEEP is a unicast probe to every address in our own /24 — 254
# eleven-byte packets, spread over a handful of frames — and it exists for iOS,
# where sending to the broadcast address needs Apple's multicast entitlement but
# plain unicast to a LAN neighbour needs only the Local Network permission the
# app already declares (NSLocalNetworkUsageDescription, in export_presets.cfg).
#
# The sweep runs on desktop too rather than being an iOS branch: it costs almost
# nothing, it is the same code path on both platforms — which is the half of this
# that can actually be tested here — and it also finds hosts behind the access
# points that quietly drop broadcast traffic.
#
# WHAT THE SWEEP DOES NOT COVER, and why that is survivable. It walks our own
# /24, which is the whole network on home wifi and a slice of it on a big managed
# one — on a school's flat 10.x.x.x you and the host may sit in different /24s
# and never see each other, and walking a /16 instead would be 65534 probes and
# would read as a port scan to anything watching. So on a large network the games
# list is a convenience that may come up empty, and the JOIN CODE is the path
# that always works, because it carries the full address and needs no discovery
# at all. Neither can help if the network has client isolation switched on, which
# is common on school and guest wifi and blocks device-to-device traffic outright.

## Addresses probed per frame during a sweep. A /24 lands inside a fifth of a
## second at 60fps and the widest sweep below inside a second, both well within
## the cadence they run at.
const SWEEP_PER_FRAME := 32
## Broadcast is one packet, so it goes out every second. A sweep is hundreds, so
## it goes out every three — often enough that a room appears while you are still
## looking at the screen, rarely enough to stay unremarkable on a network with
## someone watching the traffic.
const PROBE_INTERVAL := 1.0
const SWEEP_INTERVAL := 3.0

## How wide the sweep goes, in prefix bits, and this is NOT a guess about the
## network — it is discovered.
##
## Godot cannot read a netmask (IP.get_local_interfaces() does not expose one),
## so the first pass assumes the common /24 and every pass that finds nothing
## widens by a bit until something answers. The floor is /22, which is 1022
## addresses, because that is a real home network: the machine this was written
## on reports netmask 0xfffffc00, so a Mac at 192.168.7.110 and a phone at
## 192.168.5.x are on ONE network and three /24s apart. Sweeping only our own /24
## found nothing there, which looked exactly like iOS blocking the sweep and was
## nothing of the sort — the phone joined by code from the address the sweep was
## never going to reach.
##
## It widens rather than starting wide so the common case stays cheap, and it
## snaps back the moment a game answers.
const SWEEP_NARROW_BITS := 24
const SWEEP_WIDE_BITS := 22

static func _ip_to_int(ip: String) -> int:
	var o := ip.split(".")
	if o.size() != 4:
		return -1
	return (int(o[0]) << 24) | (int(o[1]) << 16) | (int(o[2]) << 8) | int(o[3])

static func _int_to_ip(n: int) -> String:
	return "%d.%d.%d.%d" % [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]

func browse_start() -> void:
	if _probe:
		return
	_probe = PacketPeerUDP.new()
	_probe.bind(0)   # ephemeral port so the host's reply can find us
	if broadcast_works():
		_probe.set_broadcast_enabled(true)
	games = {}
	_next_probe_at = 0.0
	_next_sweep_at = 0.0
	_sweep_at = 0
	_sweep_bits = SWEEP_NARROW_BITS

func browse_stop() -> void:
	if _probe:
		_probe.close()
		_probe = null
	games = {}
	_sweep_at = 0

func _process(_delta: float) -> void:
	var clock := Time.get_ticks_msec() / 1000.0
	# Host: answer "anyone hosting?" probes with our name, count and mode.
	if _discovery:
		while _discovery.get_available_packet_count() > 0:
			var msg := _discovery.get_packet().get_string_from_utf8()
			if msg == PROBE and is_host() and not locked:
				var from := _discovery.get_packet_ip()
				_discovery.set_dest_address(from, _discovery.get_packet_port())
				var me: Dictionary = players.get(1, {"name": "Star"})
				_discovery.put_packet(("%s|%s|%d|%s|%d" % [REPLY, me.name,
						players.size(), mode, room_capacity()]).to_utf8_buffer())
				# NS3_NET_STATS=1: who is looking for a game, and how. This is
				# the ONLY way to answer "can an iPhone actually run the unicast
				# sweep" from this end — the phone cannot be watched, but the
				# host can say whether its probe arrived. A probe from a phone
				# proves the Local Network permission was granted and that the
				# sweep reaches a real host; silence means it did not.
				if _log_probes and from != _last_probe_from:
					_last_probe_from = from
					print("[net] discovery probe from %s (code %s)" % [from, ip_to_code(from)])
	if _probe:
		if broadcast_works() and clock >= _next_probe_at:
			_next_probe_at = clock + PROBE_INTERVAL
			_probe.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_probe.put_packet(PROBE.to_utf8_buffer())
		if _sweep_at <= 0 and clock >= _next_sweep_at:
			_next_sweep_at = clock + SWEEP_INTERVAL
			_sweep_at = 1
		_sweep_tick()
		_collect_replies(clock)

## The unicast half: SWEEP_PER_FRAME addresses of our own /24 per frame, then
## idle until the next probe.
func _sweep_tick() -> void:
	if _sweep_at <= 0:
		return
	var mine := _ip_to_int(local_ip())
	if mine < 0:
		_sweep_at = 0
		return
	var shift: int = 32 - _sweep_bits
	var base: int = (mine >> shift) << shift        # the network address
	var hosts: int = (1 << shift) - 2               # .0 and the broadcast excluded
	var sent := 0
	# Our own address is probed too, rather than skipped. Browsing and hosting
	# cannot both be happening in one process — the room screen stops browsing the
	# moment you are in a room — so this can never list you your own game, and it
	# costs one packet in hundreds. What it buys is a version of this that can be
	# TESTED on one machine: a host and a browser side by side on a desktop, which
	# is the only way to tell "the sweep is broken" from "the sweep never reached".
	while _sweep_at <= hosts and sent < SWEEP_PER_FRAME:
		_probe.set_dest_address(_int_to_ip(base + _sweep_at), DISCOVERY_PORT)
		_probe.put_packet(PROBE.to_utf8_buffer())
		sent += 1
		_sweep_at += 1
	if _sweep_at > hosts:
		_sweep_at = 0
		# A whole pass with nothing on it means the network is probably wider
		# than the pass was. Anything answering means it is not, so snap back.
		if games.is_empty():
			if _sweep_bits > SWEEP_WIDE_BITS:
				_sweep_bits -= 1
				# Straight on to the wider pass rather than waiting out
				# SWEEP_INTERVAL first. Widening a bit per THREE SECONDS meant a
				# /22 was not covered until the ninth second, which is well past
				# the point where an empty list has already been read as "no
				# games here" and the screen left. Widening back to back gets
				# there inside a second; only a settled sweep waits.
				_sweep_at = 1
		elif _sweep_bits != SWEEP_NARROW_BITS:
			_sweep_bits = SWEEP_NARROW_BITS

## Replies in, stale rooms out. A room is keyed on the host's address, so the
## same host answering both a broadcast and a sweep probe is one entry.
func _collect_replies(clock: float) -> void:
	var changed := false
	while _probe.get_available_packet_count() > 0:
		var parts := _probe.get_packet().get_string_from_utf8().split("|")
		if parts.size() >= 3 and parts[0] == REPLY:
			var ip := _probe.get_packet_ip()
			# NS3_NET_STATS=1: the browsing half of the discovery instrument. The
			# host says whose probe arrived; this says whose reply came back, so
			# a discovery failure can be pinned to the direction it failed in
			# rather than guessed at.
			if _log_probes and not games.has(ip):
				print("[net] found game at %s (code %s, %s)" % [ip, ip_to_code(ip),
						parts[3] if parts.size() > 3 else "showdown"])
			games[ip] = {"name": parts[1], "count": int(parts[2]),
					"mode": parts[3] if parts.size() > 3 else "showdown",
					"cap": int(parts[4]) if parts.size() > 4 else MAX_PLAYERS,
					"code": ip_to_code(ip), "seen": clock}
			changed = true
	for ip in games.keys():
		if clock - games[ip].seen > 4.0:
			games.erase(ip)
			changed = true
	if changed:
		games_updated.emit()
