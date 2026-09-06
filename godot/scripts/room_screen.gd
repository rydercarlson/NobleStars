class_name RoomScreen
extends Control
## "Play with friends" over wifi: host a room, browse LAN games (UDP
## discovery) or join by IP, then wait in the room until the host starts.
##
## The two halves swap places on iOS. Broadcast discovery needs Apple's
## multicast entitlement to receive anything, so on a phone the games list is
## permanently empty — and an empty list where the answer should be reads as a
## broken feature rather than as an unavailable one. There, JOIN BY IP is the
## primary control, prefilled with the last address used, and the list is a
## demoted afterthought carrying the reason it is empty. On desktop the order is
## the other way round, because there discovery does work.

var menu: MenuShell

var _browse_box: VBoxContainer     # discovery + host UI
var _room_box: VBoxContainer       # joined-room UI
var _games_list: VBoxContainer
var _status: Label
var _ip_edit: LineEdit
var _players_list: VBoxContainer
var _start_btn: Button
var _room_hint: Label
var _room_ip: Label

func _ready() -> void:
	var back := UIKit.back_button()
	back.pressed.connect(func() -> void:
		Net.leave()
		Net.browse_stop()
		menu.show_screen("lobby"))
	add_child(back)

	var title := UIKit.label("PLAY WITH FRIENDS", 40, UIKit.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	_build_browse_box()
	_build_room_box()

	Net.roster_changed.connect(refresh)
	Net.games_updated.connect(_rebuild_games)
	Net.join_failed.connect(func(reason: String) -> void:
		_status.text = reason
		refresh())
	Net.host_disconnected.connect(func() -> void:
		if is_visible_in_tree():
			_status.text = "Host left"
			refresh())

func _build_browse_box() -> void:
	_browse_box = VBoxContainer.new()
	_browse_box.add_theme_constant_override("separation", 14)
	_browse_box.custom_minimum_size = Vector2(560, 0)
	add_child(_browse_box)
	_browse_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_browse_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_browse_box.grow_vertical = Control.GROW_DIRECTION_BOTH

	var host_btn := UIKit.button("HOST A GAME", 30, Color(0.16, 0.38, 0.23), Vector2(560, 72))
	host_btn.pressed.connect(func() -> void:
		if Net.host_game(SaveGame.player_name, SaveGame.selected_kit) != OK:
			_status.text = "Could not open the port — already hosting?"
		refresh())
	_browse_box.add_child(host_btn)

	var discovery: bool = Net.discovery_works()
	if discovery:
		_build_discovery_block()
		_build_join_block(false)
	else:
		_build_join_block(true)
		_build_discovery_block()

	_status = UIKit.label("", 18, Color(0.95, 0.5, 0.4))
	_browse_box.add_child(_status)

func _build_discovery_block() -> void:
	_browse_box.add_child(UIKit.label("GAMES ON YOUR WIFI", 20, UIKit.MUTED))
	if not Net.discovery_works():
		# Said plainly, once, where the empty list is: an iPhone cannot hear the
		# replies, and no amount of waiting will change that.
		_browse_box.add_child(UIKit.label(
				"iPhone can't see games on the wifi — join by IP above.",
				17, UIKit.FAINT))
	_games_list = VBoxContainer.new()
	_games_list.add_theme_constant_override("separation", 8)
	_browse_box.add_child(_games_list)

func _build_join_block(primary: bool) -> void:
	_browse_box.add_child(UIKit.label("JOIN BY IP" if primary else "OR JOIN BY IP",
			20, UIKit.GOLD if primary else UIKit.MUTED))
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 10)
	_browse_box.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "the host's IP, e.g. 192.168.1.24"
	_ip_edit.text = Net.last_ip   # same address every time in one house
	_ip_edit.custom_minimum_size = Vector2(380, 52)
	_ip_edit.add_theme_font_size_override("font_size", 20)
	# A numeric pad, not the full keyboard: the field only ever takes an IPv4
	# address, and the phone's default layout hides the dot behind a shift.
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip_edit.text_submitted.connect(func(text: String) -> void:
		if text.strip_edges() != "":
			_join(text))
	ip_row.add_child(_ip_edit)
	var join_btn := UIKit.button("JOIN", 22,
			Color(0.16, 0.38, 0.23) if primary else UIKit.NAVY_PANEL, Vector2(160, 52))
	join_btn.pressed.connect(func() -> void:
		if _ip_edit.text.strip_edges() != "":
			_join(_ip_edit.text))
	ip_row.add_child(join_btn)

func _build_room_box() -> void:
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 16)
	_room_box.custom_minimum_size = Vector2(560, 0)
	add_child(_room_box)
	_room_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_room_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_room_box.grow_vertical = Control.GROW_DIRECTION_BOTH

	_room_hint = UIKit.label("", 20, UIKit.MUTED)
	_room_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(_room_hint)

	# The host's own address, big enough to read across a room and type into a
	# phone. On iOS this is the ONLY way anyone joins, so it is not a footnote.
	_room_ip = UIKit.label("", 34, UIKit.GOLD)
	_room_ip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_ip.visible = false
	_room_box.add_child(_room_ip)

	_players_list = VBoxContainer.new()
	_players_list.add_theme_constant_override("separation", 8)
	_room_box.add_child(_players_list)

	_start_btn = UIKit.button("START MATCH", 32, UIKit.PLAY_YELLOW, Vector2(560, 80))
	for state_color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_start_btn.add_theme_color_override(state_color, UIKit.NAVY)
	_start_btn.pressed.connect(func() -> void: Net.start_game())
	_room_box.add_child(_start_btn)

	var leave_btn := UIKit.button("LEAVE ROOM", 20, UIKit.NAVY_PANEL, Vector2(560, 52))
	leave_btn.pressed.connect(func() -> void:
		Net.leave()
		refresh())
	_room_box.add_child(leave_btn)

func _join(ip: String) -> void:
	_status.text = "Joining %s…" % ip.strip_edges()
	Net.join_game(ip, SaveGame.player_name, SaveGame.selected_kit)

func refresh() -> void:
	if not is_visible_in_tree():
		return
	var in_room := Net.active and not Net.players.is_empty()
	_room_box.visible = in_room
	_browse_box.visible = not in_room
	if in_room:
		Net.browse_stop()
		_rebuild_players()
		_start_btn.visible = Net.is_host()
		if Net.is_host():
			var ip := Net.local_ip()
			_room_ip.text = ip
			_room_ip.visible = ip != ""
			_room_hint.text = "Friends join by typing this address:" if ip != "" \
					else "Friends on this wifi can join"
		else:
			_room_ip.visible = false
			_room_hint.text = "Waiting for the host to start…"
	else:
		_room_ip.visible = false
		Net.browse_start()
		_rebuild_games()

func _rebuild_players() -> void:
	for c in _players_list.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		var tag := "  (host)" if id == 1 else ""
		var pill := UIKit.pill("%s — %s%s" % [p.name, p.kit, tag],
				UIKit.GOLD if id == multiplayer.get_unique_id() else UIKit.FAINT)
		_players_list.add_child(pill)

func _rebuild_games() -> void:
	if not is_visible_in_tree() or _games_list == null:
		return
	for c in _games_list.get_children():
		c.queue_free()
	if Net.games.is_empty():
		# "Searching…" on a phone is a promise the platform will not keep.
		_games_list.add_child(UIKit.label(
				"Searching…" if Net.discovery_works() else "—", 18, UIKit.FAINT))
		return
	for ip in Net.games:
		var g: Dictionary = Net.games[ip]
		var row := UIKit.button("%s's game — %d in room  (JOIN)" % [g.name, g.count],
				22, UIKit.NAVY_PANEL, Vector2(560, 56))
		row.pressed.connect(_join.bind(String(ip)))
		_games_list.add_child(row)
