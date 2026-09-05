class_name WifiScreen
extends MenuScreen
## "Play with friends" over wifi, in the programme's own language: host a
## room, browse the games discovered on the LAN or join one by IP, then wait in
## the room until the host starts. The networking is RoomScreen's, unchanged —
## this is the same flow wearing the menu's type, rules and gold, instead of the
## rounded in-match buttons it arrived in.

var _browse: VBoxContainer
var _room: VBoxContainer
var _games: VBoxContainer
var _players: VBoxContainer
var _status: Label
var _ip_edit: LineEdit
var _start_btn: Button
var _room_hint: Label

func _build() -> void:
	screen_name = "wifi"
	var ip: String = Net.local_ip()
	topbar("Wifi", "PLAY WITH FRIENDS" + ("   ·   THIS DEVICE IS %s" % ip if ip != "" else ""))
	var column: VBoxContainer = fill_content(0)
	_browse = MenuUI.vbox(0)
	_room = MenuUI.vbox(0)
	column.add_child(_browse)
	column.add_child(_room)
	_build_browse()
	_build_room()

	Net.roster_changed.connect(refresh)
	Net.games_updated.connect(_rebuild_games)
	Net.join_failed.connect(func(reason: String) -> void:
		_status.text = reason
		refresh())
	Net.host_disconnected.connect(func() -> void:
		if is_visible_in_tree():
			_status.text = "Host left"
			refresh())
	refresh()

func _exit_tree() -> void:
	Net.browse_stop()

## Two columns under the bar: HOST on the left, JOIN on the right.
func _build_browse() -> void:
	var row := MenuUI.hbox(60)
	_browse.add_child(row)

	var host := MenuUI.vbox(18)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(host)
	host.add_child(MenuUI.section("HOST"))
	host.add_child(MenuUI.display("OPEN A ROOM", 44))
	host.add_child(MenuUI.wrap(MenuUI.body(
			"Everyone on this wifi sees your room in their list. You pick the mode; the match starts when you say.",
			22, MenuUI.TEXT_SOFT)))
	host.add_child(MenuUI.gap(6, true))
	var host_btn: Button = MenuUI.button("Host a game", "gold", 34, Vector2(0, 84))
	host_btn.pressed.connect(func() -> void:
		sfx("click")
		if Net.host_game(SaveGame.player_name, SaveGame.selected_kit) != OK:
			_status.text = "Could not open the port — already hosting?"
		refresh())
	host.add_child(host_btn)

	row.add_child(MenuUI.rule(MenuUI.RULE, true))

	var join := MenuUI.vbox(18)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(join)
	join.add_child(MenuUI.section("JOIN   ·   GAMES ON YOUR WIFI"))
	_games = MenuUI.vbox(0)
	join.add_child(_games)
	join.add_child(MenuUI.gap(10, true))
	join.add_child(MenuUI.label("OR BY ADDRESS", 19, MenuUI.TEXT_DIM))
	var ip_row := MenuUI.hbox(14)
	join.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "host's IP…"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size = Vector2(0, 58)
	_ip_edit.add_theme_font_override("font", MenuUI.body_font())
	_ip_edit.add_theme_font_size_override("font_size", 24)
	_ip_edit.add_theme_color_override("font_color", MenuUI.TEXT)
	_ip_edit.add_theme_color_override("font_placeholder_color", MenuUI.TEXT_FAINT)
	for state in ["normal", "focus", "read_only"]:
		_ip_edit.add_theme_stylebox_override(state,
				MenuUI.flat_box(MenuUI.PANEL, MenuUI.RULE_HI if state == "focus" else MenuUI.RULE))
	ip_row.add_child(_ip_edit)
	var join_btn: Button = MenuUI.button("Join", "grey", 24, Vector2(150, 58))
	join_btn.pressed.connect(func() -> void:
		if _ip_edit.text.strip_edges() != "":
			_join(_ip_edit.text))
	ip_row.add_child(join_btn)
	_status = MenuUI.label("", 19, MenuUI.RED)
	join.add_child(_status)

func _build_room() -> void:
	_room.add_child(MenuUI.section("ROOM"))
	_room.add_child(MenuUI.gap(14, true))
	_room_hint = MenuUI.body("", 22, MenuUI.TEXT_SOFT)
	_room.add_child(_room_hint)
	_room.add_child(MenuUI.gap(24, true))
	_players = MenuUI.vbox(0)
	_room.add_child(_players)
	_room.add_child(MenuUI.gap(30, true))
	var actions := MenuUI.hbox(30)
	_room.add_child(actions)
	_start_btn = MenuUI.button("Start match", "gold", 34, Vector2(420, 84))
	_start_btn.pressed.connect(func() -> void:
		sfx("play")
		Net.start_game())
	actions.add_child(_start_btn)
	var leave: Button = MenuUI.link("Leave room", 24)
	leave.pressed.connect(func() -> void:
		Net.leave()
		refresh())
	actions.add_child(leave)

func _join(ip: String) -> void:
	_status.text = "Joining %s…" % ip.strip_edges()
	Net.join_game(ip, SaveGame.player_name, SaveGame.selected_kit)

func refresh() -> void:
	if not is_inside_tree():
		return
	var in_room: bool = Net.active and not Net.players.is_empty()
	_room.visible = in_room
	_browse.visible = not in_room
	if in_room:
		Net.browse_stop()
		_rebuild_players()
		_start_btn.visible = Net.is_host()
		if Net.is_host():
			var ip: String = Net.local_ip()
			_room_hint.text = "Friends on this wifi can join from their list" \
					+ (", or by the address %s." % ip if ip != "" else ".")
		else:
			_room_hint.text = "Waiting for the host to start…"
	else:
		Net.browse_start()
		_rebuild_games()

## One hairline row per player: name, their fighter, HOST / YOU tags.
func _rebuild_players() -> void:
	for c in _players.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		var mine: bool = id == multiplayer.get_unique_id()
		var row := MenuUI.hbox(24)
		row.custom_minimum_size = Vector2(0, 64)
		row.add_child(MenuUI.display(str(p.name).to_upper(), 30, MenuUI.GOLD if mine else MenuUI.TEXT))
		row.add_child(MenuUI.label(str(p.kit).to_upper(), 19, MenuUI.TEXT_DIM))
		row.add_child(MenuUI.spacer())
		if id == 1:
			row.add_child(MenuUI.tag("HOST", MenuUI.PANEL_HI, MenuUI.TEXT_SOFT))
		if mine:
			row.add_child(MenuUI.tag("YOU", MenuUI.GOLD, MenuUI.GOLD_INK))
		_players.add_child(row)
		_players.add_child(MenuUI.rule())

func _rebuild_games() -> void:
	if not is_inside_tree() or _games == null:
		return
	for c in _games.get_children():
		c.queue_free()
	if Net.games.is_empty():
		var searching: Label = MenuUI.body("Searching…", 22, MenuUI.TEXT_FAINT)
		searching.custom_minimum_size = Vector2(0, 64)
		_games.add_child(searching)
		return
	for ip in Net.games:
		var g: Dictionary = Net.games[ip]
		var row := MenuUI.hbox(24)
		row.custom_minimum_size = Vector2(0, 64)
		row.add_child(MenuUI.display("%s'S GAME" % str(g.name).to_upper(), 30))
		row.add_child(MenuUI.label("%d IN ROOM" % int(g.count), 19, MenuUI.TEXT_DIM))
		row.add_child(MenuUI.spacer())
		var join_link: Button = MenuUI.link("Join", 24)
		join_link.pressed.connect(_join.bind(String(ip)))
		row.add_child(join_link)
		_games.add_child(row)
		_games.add_child(MenuUI.rule())
