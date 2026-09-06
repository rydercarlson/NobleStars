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

var _browse_box: Control           # discovery + host + code entry (two columns)
var _room_box: VBoxContainer       # joined-room UI
var _games_list: VBoxContainer
var _status: Label
var _code_label: Label
var _self_label: Label
var _join_btn: Button
## What has been tapped into the pad so far, uppercase by construction.
var _code := ""
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

	# The menu's square back arrow, in the corner every pushed screen keeps it.
	var back: Button = MenuUI.square_button("back")
	back.position = Vector2(HomeScreen.MARGIN_X, HomeScreen.TOP_Y)
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

## The browse screen is TWO COLUMNS, and that is the whole of what makes the
## keypad usable.
##
## It was one 560-wide strip down the middle, which is a desktop shape on a
## landscape phone: the stage is over 2000 px wide there and all of it either
## side was empty, so the keys came out about 4 mm across against Apple's 7 mm
## minimum tap target. Hosting and browsing go on the left, the code and its pad
## on the right, and the pad gets nearly twice the width it had — which is what
## buys keys you can actually hit rather than a smaller font.
const LEFT_W := 620.0
const RIGHT_W := 1100.0
const KEY_GAP := 10.0
const KEY_H := 84.0

func _build_browse_box() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	_browse_box = row

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(right)

	_build_mode_row(left)
	var host_btn := UIKit.button("HOST A GAME", 30, Color(0.16, 0.38, 0.23), Vector2(LEFT_W, 80))
	host_btn.pressed.connect(func() -> void:
		if Net.host_game(SaveGame.player_name, SaveGame.selected_kit, _host_mode) != OK:
			_status.text = "Could not open the port — already hosting?"
		refresh())
	left.add_child(host_btn)
	_build_discovery_block(left)
	_status = UIKit.label("", 18, Color(0.95, 0.5, 0.4))
	left.add_child(_status)

	_build_join_block(right)

## The mode the host will open the room on. Shown before HOST A GAME because it
## changes what that button does, and irrelevant to someone who is only joining —
## a client does not choose, it is told (see Net.mode).
func _build_mode_row(parent: Control) -> void:
	parent.add_child(UIKit.label("MODE", 20, UIKit.MUTED))
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 10)
	parent.add_child(_mode_row)
	var w: float = (LEFT_W - 10.0) / 2.0
	for m: Dictionary in NET_MODES:
		var id := str(m.id)
		var b := UIKit.button("%s\n%s" % [str(m.label), str(m.sub)], 20,
				UIKit.NAVY_PANEL, Vector2(w, 72))
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

func _build_discovery_block(parent: Control) -> void:
	parent.add_child(UIKit.label("GAMES ON YOUR WIFI", 20, UIKit.MUTED))
	_games_list = VBoxContainer.new()
	_games_list.add_theme_constant_override("separation", 8)
	parent.add_child(_games_list)
	# This device's own address, dim and small. It earns its place twice over:
	# it is the thing to compare against a friend's when the list stays empty
	# (two phones on 192.168.4.x and 192.168.9.x are on one wifi and may not
	# find each other), and it is the only way to see what iOS actually reports
	# as the local address, which cannot be read off a phone any other way.
	_self_label = UIKit.label("", 16, UIKit.FAINT)
	parent.add_child(_self_label)

## The code entry: a display strip and the game's own 32-key pad.
##
## It was a LineEdit, and typing into it on a phone was the worst thing on the
## screen. iOS brings up a lowercase QWERTY, so every character arrived in a case
## the alphabet does not have and got flipped under your thumb as you typed; the
## keyboard covered half the screen; and two thirds of the keys it offered cannot
## appear in a code at all — including the four (`0 O 1 I L`) that were removed
## from the alphabet precisely because people confuse them.
##
## A pad of exactly the 32 legal characters fixes all of it at once. Case cannot
## come up, an invalid character cannot be typed, nothing is covered, and the
## grid is its own documentation: base 32 falls out as eight columns by four
## rows, the digits on the top row and the letters below, so the gaps where I and
## O should be are visible rather than a rule you have to be told.
##
## The keys are sized off RIGHT_W rather than a fixed number, because the first
## pass had them at about 4 mm on a phone — half Apple's minimum tap target — and
## the fix for that was giving the column width, not shrinking the font.
##
## A physical keyboard still works, for desktop play and for testing — see
## _unhandled_key_input.
const CODE_COLUMNS := 8
const CODE_MAX_LEN := 7

func _build_join_block(parent: Control) -> void:
	parent.add_child(UIKit.label("ENTER JOIN CODE", 20, UIKit.GOLD))

	var strip: PanelContainer = UIKit.panel(10, UIKit.NAVY_DEEP)
	strip.custom_minimum_size = Vector2(RIGHT_W, 92)
	parent.add_child(strip)
	_code_label = UIKit.label("", 56, UIKit.GOLD)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip.add_child(_code_label)

	var pad := GridContainer.new()
	pad.columns = CODE_COLUMNS
	pad.add_theme_constant_override("h_separation", int(KEY_GAP))
	pad.add_theme_constant_override("v_separation", int(KEY_GAP))
	parent.add_child(pad)
	var key_w: float = (RIGHT_W - KEY_GAP * (CODE_COLUMNS - 1)) / CODE_COLUMNS
	for i in Net.CODE_ALPHABET.length():
		var ch: String = Net.CODE_ALPHABET[i]
		var key := UIKit.button(ch, 34, UIKit.NAVY_PANEL, Vector2(key_w, KEY_H))
		key.pressed.connect(_code_push.bind(ch))
		pad.add_child(key)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(KEY_GAP))
	parent.add_child(actions)
	var half: float = (RIGHT_W - KEY_GAP) / 2.0
	var del := UIKit.button("DELETE", 26, UIKit.NAVY_PANEL, Vector2(half, 72))
	del.pressed.connect(_code_pop)
	actions.add_child(del)
	_join_btn = UIKit.button("JOIN", 28, Color(0.16, 0.38, 0.23), Vector2(half, 72))
	_join_btn.pressed.connect(_try_join)
	actions.add_child(_join_btn)

	_code = Net.last_code()   # same host every time in one house
	_refresh_code()

func _code_push(ch: String) -> void:
	if _code.length() >= CODE_MAX_LEN:
		return
	_code += ch
	_refresh_code()

func _code_pop() -> void:
	if _code != "":
		_code = _code.substr(0, _code.length() - 1)
		_refresh_code()

## JOIN lights up only when the code actually decodes to an address. That is
## free — the decoder already rejects most mistyped codes rather than handing
## back a stranger's machine — and it turns the rejection into something you can
## see BEFORE you press anything, instead of an error afterwards.
func _refresh_code() -> void:
	if _code_label == null:
		return
	# Letterspaced, because a code is read out one character at a time.
	var shown := ""
	for i in _code.length():
		shown += ("  " if i > 0 else "") + _code[i]
	_code_label.text = shown if _code != "" else "–  –  –  –"
	_code_label.add_theme_color_override("font_color",
			UIKit.GOLD if _code != "" else UIKit.FAINT)
	var ready: bool = Net.resolve_target(_code) != ""
	_join_btn.disabled = not ready
	UIKit.style_button(_join_btn, Color(0.16, 0.38, 0.23) if ready else UIKit.NAVY_PANEL)

func _try_join() -> void:
	if _code != "":
		_join(_code)

## A physical keyboard, for desktop and for testing. Only the alphabet's own
## characters are accepted, so a stray keypress cannot put a character into the
## field that the decoder would then reject.
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _room_box == null or _room_box.visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_BACKSPACE:
		_code_pop()
		accept_event()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_try_join()
		accept_event()
	else:
		var ch := String.chr(key.unicode).to_upper()
		if ch.length() == 1 and Net.CODE_ALPHABET.find(ch) >= 0:
			_code_push(ch)
			accept_event()

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
	if Net.resolve_target(target) == "":
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
	if _self_label != null:
		var mine := Net.local_ip()
		_self_label.text = "This device: %s" % (mine if mine != "" else "no wifi address")
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
				19, UIKit.NAVY_PANEL, Vector2(LEFT_W, 62))
		row.pressed.connect(_join.bind(String(ip)))
		_games_list.add_child(row)
