class_name ClubScreen
extends MenuScreen
## Club — roster on the left, a working chat on the right. Messages you send
## persist in the save (SaveGame.club_chat), same as the web build's localStorage.

const REPLIES: Array = ["gg", "nice one", "who wants to duo?",
	"showdown weekend lets gooo", "someone bring snacks to the auditorium", "W club"]

var _messages: VBoxContainer
var _scroll: ScrollContainer
var _input: LineEdit

func _build() -> void:
	screen_name = "club"
	var club: Dictionary = MenuData.game.get("club", {})
	topbar("Club")
	var columns := MenuUI.hbox(30)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_bottom", 34)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(columns)
	body.add_child(margin)
	content = columns
	columns.add_child(_left(club))
	columns.add_child(_chat(club))

func _left(club: Dictionary) -> VBoxContainer:
	var column := MenuUI.vbox(20)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head: PanelContainer = MenuUI.panel("navy", 16, 7, 24)
	var head_row := MenuUI.hbox(24)
	head.add_child(head_row)
	head_row.add_child(MenuUI.icon("club", 110))
	var lines := MenuUI.vbox(6)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(lines)
	lines.add_child(MenuUI.display(str(club.get("name", "Club")).to_upper(), 48))
	lines.add_child(MenuUI.body("%s · %s · %d/%d members" % [str(club.get("tag", "")),
			str(club.get("type", "")), int(club.get("members", 0)),
			int(club.get("maxMembers", 30))], 22, MenuUI.TEXT_DIM))
	lines.add_child(MenuUI.wrap(MenuUI.body(str(club.get("description", "")), 21, MenuUI.TEXT_SOFT)))
	column.add_child(head)

	var stats := MenuUI.hbox(14)
	column.add_child(stats)
	stats.add_child(_stat("Club trophies", MenuUI.fmt(int(club.get("trophies", 0))), "trophy"))
	stats.add_child(_stat("Required", MenuUI.fmt(int(club.get("required", 0))), "trophy"))
	stats.add_child(_stat("Members", "%d/%d" % [int(club.get("members", 0)),
			int(club.get("maxMembers", 30))], ""))

	column.add_child(MenuUI.display("MEMBERS", 28, MenuUI.TEXT, 4))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := MenuUI.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var roster: Array = []
	for member in club.get("roster", []):
		var entry: Dictionary = member.duplicate()
		if bool(entry.get("isYou", false)):
			entry["name"] = SaveGame.player_name
			entry["trophies"] = SaveGame.total_trophies()
		roster.append(entry)
	roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.trophies) > int(b.trophies))
	for i in roster.size():
		list.add_child(_member_row(roster[i], i))
	return column

func _stat(key: String, value: String, icon_name: String) -> PanelContainer:
	var p: PanelContainer = MenuUI.dark_panel(14, 0.35, 16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := MenuUI.vbox(4)
	p.add_child(column)
	column.add_child(MenuUI.body(key.to_upper(), 18, MenuUI.TEXT_DIM))
	var row := MenuUI.hbox(8)
	if icon_name != "":
		row.add_child(MenuUI.icon(icon_name, 30))
	row.add_child(MenuUI.display(value, 32))
	column.add_child(row)
	return p

func _member_row(member: Dictionary, index: int) -> PanelContainer:
	var plate: PanelContainer = MenuUI.panel("navy", 14, 5, 14)
	var row := MenuUI.hbox(16)
	plate.add_child(row)
	var rank: Label = MenuUI.display("#%d" % (index + 1), 30,
			MenuUI.YELLOW_HI if index < 3 else MenuUI.TEXT_DIM, 4)
	rank.custom_minimum_size = Vector2(56, 0)
	row.add_child(rank)
	var who := MenuUI.vbox(2)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(MenuUI.display(str(member.name).to_upper(), 30, MenuUI.TEXT, 4))
	who.add_child(MenuUI.body(str(member.get("role", "Member")), 20, MenuUI.TEXT_DIM))
	row.add_child(who)
	row.add_child(MenuUI.icon("trophy", 30))
	row.add_child(MenuUI.display(MenuUI.fmt(int(member.trophies)), 30, MenuUI.YELLOW_HI, 4))
	return plate

func _chat(club: Dictionary) -> PanelContainer:
	var plate: PanelContainer = MenuUI.panel("navy", 16, 7, 0)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := MenuUI.vbox(0)
	plate.add_child(column)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll_margin := MarginContainer.new()
	scroll_margin.add_theme_constant_override("margin_left", 16)
	scroll_margin.add_theme_constant_override("margin_right", 16)
	scroll_margin.add_theme_constant_override("margin_top", 16)
	scroll_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_scroll)
	column.add_child(scroll_margin)
	_messages = MenuUI.vbox(10)
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_messages)
	for message in club.get("chat", []):
		_add_message(str(message.who), str(message.text))
	for message in SaveGame.club_chat:
		_add_message(str(message.who), str(message.text))

	var input_row := MenuUI.hbox(12)
	var input_wrap := PanelContainer.new()
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0, 0, 0, 0.25)
	input_style.border_width_top = 3
	input_style.border_color = MenuUI.LINE
	input_style.set_content_margin_all(16)
	input_wrap.add_theme_stylebox_override("panel", input_style)
	input_wrap.add_child(input_row)
	column.add_child(input_wrap)
	_input = LineEdit.new()
	_input.placeholder_text = "Say something to the club…"
	_input.max_length = 120
	_input.custom_minimum_size = Vector2(0, 62)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_override("font", MenuUI.body_font())
	_input.add_theme_font_size_override("font_size", 22)
	_input.text_submitted.connect(func(_t: String) -> void: _send())
	input_row.add_child(_input)
	var send: Button = MenuUI.small_button("SEND", "green")
	send.pressed.connect(_send)
	input_row.add_child(send)
	return plate

func _add_message(who: String, text: String) -> void:
	var mine: bool = who == SaveGame.player_name
	var bubble: PanelContainer = MenuUI.dark_panel(12, 0.35, 14)
	if mine:
		var style: StyleBoxFlat = MenuUI.dark_box(12, 0.0, 14)
		style.bg_color = Color(0.12, 0.31, 0.86, 0.55)
		bubble.add_theme_stylebox_override("panel", style)
	# CSS ".msg { max-width: 85% }": a stretch-ratio pair gives the bubble most
	# of the row and pushes it to whichever side the sender is on.
	var row := MenuUI.hbox(0)
	var gap: Control = MenuUI.spacer()
	gap.size_flags_stretch_ratio = 0.18
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_stretch_ratio = 0.82
	if mine:
		row.add_child(gap)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(gap)
	var column := MenuUI.vbox(4)
	bubble.add_child(column)
	column.add_child(MenuUI.display(who, 22, MenuUI.YELLOW_HI, 0))
	column.add_child(MenuUI.wrap(MenuUI.body(text.to_upper(), 21, MenuUI.TEXT)))
	_messages.add_child(row)
	_scroll_to_bottom()

func _send() -> void:
	var text: String = _input.text.strip_edges()
	if text.is_empty():
		sfx("error")
		return
	SaveGame.club_chat.append({"who": SaveGame.player_name, "text": text})
	SaveGame.save()
	_add_message(SaveGame.player_name, text)
	_input.text = ""
	sfx("click")
	get_tree().create_timer(randf_range(0.9, 2.1)).timeout.connect(func() -> void:
		if is_inside_tree():
			_add_message("Bulldog_Ben", REPLIES[randi() % REPLIES.size()]))

func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
