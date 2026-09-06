class_name RoomScreen
extends Control
## "Play with friends" over wifi: host a room or join one, pick the mode, then
## wait in the room until the host starts.
##
## THE JOIN CODE IS THE PRIMARY WAY IN, on every platform. It is four characters
## on home wifi, and it works with no discovery at all — which matters because
## discovery is the half that a network can take away. Broadcast needs Apple's
## multicast entitlement on iOS, the unicast sweep only covers the host's own
## /24, and a school or guest network with client isolation blocks both along
## with everything else. The code carries the address itself, so the only thing
## it needs is a network that lets two devices talk at all.
##
## The games list is still here, below the code field on every platform. It used
## to lead on desktop, on the grounds that when it works it is one tap and no
## typing — but which of the two works is a property of the NETWORK rather than
## of the platform, and putting the fragile one first means the screen reads as
## broken exactly where it is least able to explain itself. Below, an empty list
## sits under a control that already works.

var menu: MenuShell

var _browse_box: VBoxContainer     # discovery + host UI
var _room_box: VBoxContainer       # joined-room UI
var _games_list: VBoxContainer
var _status: Label
var _code_edit: LineEdit
var _players_list: VBoxContainer
var _start_btn: Button
var _room_hint: Label
var _room_code: Label
var _room_ip: Label
var _mode_row: HBoxContainer
var _mode_buttons: Dictionary = {}   # engine mode -> Button
## Which mode a HOST will open the room on. Once in a room the host owns
## `Net.mode` instead, and a client only ever reads it.
var _host_mode := "showdown"

## The modes wifi play can deal, in the order they are offered. Nobles Cup is
## capped at six because it is 3v3 and there is no room for a seventh body;
## Showdown fills whatever is left of its ten with bots.
const NET_MODES := [
	{"id": "showdown", "label": "SHOWDOWN", "sub": "up to 10 · bots fill in"},
	{"id": "cup", "label": "NOBLES CUP", "sub": "3v3 · up to 6"},
]

static func mode_label(id: String) -> String:
	for m in NET_MODES:
		if str(m.id) == id:
			return str(m.label)
	return id.to_upper()

func _ready() -> void:
	SaveGame.ensure_loaded()
	_host_mode = MenuData.engine_mode(SaveGame.selected_mode)
	if _host_mode != "cup":
		_host_mode = "showdown"

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

	_build_mode_row()

	var host_btn := UIKit.button("HOST A GAME", 30, Color(0.16, 0.38, 0.23), Vector2(560, 72))
	host_btn.pressed.connect(func() -> void:
		if Net.host_game(SaveGame.player_name, SaveGame.selected_kit, _host_mode) != OK:
			_status.text = "Could not open the port — already hosting?"
		refresh())
	_browse_box.add_child(host_btn)

	# The code first everywhere. It is the control that always works; the list is
	# the one that sometimes does, so it goes below even on desktop where it is
	# reliable — being one tap is not a reason to put the fragile path first.
	_build_join_block()
	_build_discovery_block()

	_status = UIKit.label("", 18, Color(0.95, 0.5, 0.4))
	_browse_box.add_child(_status)

## The mode the host will open the room on. Shown before HOST A GAME because it
## changes what that button does, and hidden for someone who is only joining —
## a client does not choose, it is told (see Net.mode).
func _build_mode_row() -> void:
	_browse_box.add_child(UIKit.label("MODE", 20, UIKit.MUTED))
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 10)
	_browse_box.add_child(_mode_row)
	for m: Dictionary in NET_MODES:
		var id := str(m.id)
		var b := UIKit.button("%s\n%s" % [str(m.label), str(m.sub)], 20,
				UIKit.NAVY_PANEL, Vector2(275, 66))
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.pressed.connect(func() -> void:
			_host_mode = id
			_paint_mode_row())
		_mode_buttons[id] = b
		_mode_row.add_child(b)
	_paint_mode_row()

func _paint_mode_row() -> void:
	for id in _mode_buttons:
		var b: Button = _mode_buttons[id]
		UIKit.style_button(b, UIKit.NAVY_PANEL, id == _host_mode)
		b.add_theme_color_override("font_color",
				UIKit.GOLD if id == _host_mode else UIKit.MUTED)

func _build_discovery_block() -> void:
	_browse_box.add_child(UIKit.label("OR PICK A GAME ON YOUR WIFI", 20, UIKit.MUTED))
	_games_list = VBoxContainer.new()
	_games_list.add_theme_constant_override("separation", 8)
	_browse_box.add_child(_games_list)

func _build_join_block() -> void:
	_browse_box.add_child(UIKit.label("ENTER JOIN CODE", 20, UIKit.GOLD))
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 10)
	_browse_box.add_child(ip_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "e.g. 6PBA"
	_code_edit.text = Net.last_code()   # same host every time in one house
	_code_edit.custom_minimum_size = Vector2(380, 52)
	_code_edit.add_theme_font_size_override("font_size", 26)
	# Codes carry letters, so this is the full keyboard rather than the numeric
	# pad the IP field used to ask for. The field still takes a typed-out IP —
	# Net.resolve_target accepts either — for anyone reading one off a router.
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	# Codes are printed and spoken in capitals, and the alphabet has no lowercase
	# half, so a lowercase keyboard should not be able to produce a code that
	# fails. Uppercasing as it is typed also leaves an IP untouched.
	_code_edit.text_changed.connect(func(text: String) -> void:
		var upper := text.to_upper()
		if upper != text:
			var caret := _code_edit.caret_column
			_code_edit.text = upper
			_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(text: String) -> void:
		if text.strip_edges() != "":
			_join(text))
	ip_row.add_child(_code_edit)
	var join_btn := UIKit.button("JOIN", 22, Color(0.16, 0.38, 0.23), Vector2(160, 52))
	join_btn.pressed.connect(func() -> void:
		if _code_edit.text.strip_edges() != "":
			_join(_code_edit.text))
	ip_row.add_child(join_btn)

func _build_room_box() -> void:
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 14)
	_room_box.custom_minimum_size = Vector2(560, 0)
	add_child(_room_box)
	_room_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_room_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_room_box.grow_vertical = Control.GROW_DIRECTION_BOTH

	_room_hint = UIKit.label("", 20, UIKit.MUTED)
	_room_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(_room_hint)

	# The host's own join code, big enough to read across a room. On a phone this
	# is the only way anyone gets in, so it is not a footnote — it is the largest
	# thing on the screen.
	_room_code = UIKit.label("", 84, UIKit.GOLD)
	_room_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_code.visible = false
	_room_box.add_child(_room_code)

	# The address, kept underneath and small. It is the fallback for a network
	# whose shape the code cannot help with, and the thing to read out to someone
	# on an older build.
	_room_ip = UIKit.label("", 18, UIKit.FAINT)
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

func _join(target: String) -> void:
	var resolved := Net.resolve_target(target)
	if resolved == "":
		_status.text = "No game with that code — check the letters?"
		return
	_status.text = "Joining %s…" % target.strip_edges().to_upper()
	Net.join_game(target, SaveGame.player_name, SaveGame.selected_kit)

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
			var code := Net.join_code()
			var ip := Net.local_ip()
			_room_code.text = code
			_room_code.visible = code != ""
			_room_ip.text = ip
			_room_ip.visible = ip != ""
			_room_hint.text = "%s  ·  friends join with this code:" % \
					mode_label(Net.mode) if code != "" \
					else "%s  ·  friends on this wifi can join" % mode_label(Net.mode)
		else:
			_room_code.visible = false
			_room_ip.visible = false
			# A client is told the mode rather than choosing it, so the room is
			# where it finds out what it is about to play.
			_room_hint.text = "%s  ·  waiting for the host to start…" % mode_label(Net.mode)
	else:
		_room_code.visible = false
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
	# Cup is 3v3 and turns nobody's slot over to a bot, so how full the room is
	# is information the host needs before pressing START.
	_players_list.add_child(UIKit.label("%d of %d in the room" % [
			Net.players.size(), Net.room_capacity()], 17, UIKit.FAINT))

func _rebuild_games() -> void:
	if not is_visible_in_tree() or _games_list == null:
		return
	for c in _games_list.get_children():
		c.queue_free()
	if Net.games.is_empty():
		# Honest about which of the two searches is actually running. Neither can
		# see through client isolation, which is what a school or guest network
		# usually has on — hence the second line, and hence the code above it.
		_games_list.add_child(UIKit.label("Searching this wifi…", 18, UIKit.FAINT))
		_games_list.add_child(UIKit.label(
				"Nothing here? Use the join code — it works when this doesn't.",
				17, UIKit.FAINT))
		return
	for ip in Net.games:
		var g: Dictionary = Net.games[ip]
		var code := str(g.get("code", ""))
		var row := UIKit.button("%s's game — %s, %d/%d%s  (JOIN)" % [g.name,
				mode_label(str(g.get("mode", "showdown"))), g.count,
				int(g.get("cap", Net.MAX_PLAYERS)),
				"" if code == "" else "  ·  " + code],
				20, UIKit.NAVY_PANEL, Vector2(560, 56))
		row.pressed.connect(_join.bind(String(ip)))
		_games_list.add_child(row)
