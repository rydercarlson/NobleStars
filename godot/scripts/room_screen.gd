class_name RoomScreen
extends Control
## "Play with friends" over wifi: host a room, browse LAN games (UDP
## discovery) or join by IP, then wait in the room until the host starts.

var menu: MenuShell

var _browse_box: VBoxContainer     # discovery + host UI
var _room_box: VBoxContainer       # joined-room UI
var _games_list: VBoxContainer
var _status: Label
var _ip_edit: LineEdit
var _players_list: VBoxContainer
var _start_btn: Button
var _room_hint: Label

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

	_browse_box.add_child(UIKit.label("GAMES ON YOUR WIFI", 20, UIKit.MUTED))
	_games_list = VBoxContainer.new()
	_games_list.add_theme_constant_override("separation", 8)
	_browse_box.add_child(_games_list)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 10)
	_browse_box.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "or type the host's IP…"
	_ip_edit.custom_minimum_size = Vector2(380, 52)
	_ip_edit.add_theme_font_size_override("font_size", 20)
	ip_row.add_child(_ip_edit)
	var join_btn := UIKit.button("JOIN", 22, UIKit.NAVY_PANEL, Vector2(160, 52))
	join_btn.pressed.connect(func() -> void:
		if _ip_edit.text.strip_edges() != "":
			_join(_ip_edit.text))
	ip_row.add_child(join_btn)

	_status = UIKit.label("", 18, Color(0.95, 0.5, 0.4))
	_browse_box.add_child(_status)

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
			_room_hint.text = "Friends on this wifi can join" + (" — or by IP %s" % ip if ip != "" else "")
		else:
			_room_hint.text = "Waiting for the host to start…"
	else:
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
		_games_list.add_child(UIKit.label("Searching…", 18, UIKit.FAINT))
		return
	for ip in Net.games:
		var g: Dictionary = Net.games[ip]
		var row := UIKit.button("%s's game — %d in room  (JOIN)" % [g.name, g.count],
				22, UIKit.NAVY_PANEL, Vector2(560, 56))
		row.pressed.connect(_join.bind(String(ip)))
		_games_list.add_child(row)
