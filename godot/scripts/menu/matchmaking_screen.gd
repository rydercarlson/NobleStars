class_name MatchmakingScreen
extends MenuScreen
## PLAY — web-menu/src/screens/play.js. The lobby fills with players one at a
## time, calls MATCH FOUND, then hands off to the match. Where the web build
## had to ask a local server to start Godot, this one just loads game.tscn.

const BOT_NAMES: Array = ["Bulldog_Ben", "CoachK", "TennisTessa", "CastleGhost",
	"Dorm_Dan", "QuadKing", "LateForChapel", "PianoMan", "SnackRaider",
	"HallMonitor", "DeanOfBrawl", "FieldDayFury"]

var _mode: Dictionary = {}
var _slots: Array = []
var _title: Label
var _status: Label
var _cancel: Button
var _cancelled := false
var _filled := 1
var _names: Array = []

func _build() -> void:
	screen_name = "matchmaking"
	_mode = menu.selected_mode()
	topbar(str(_mode.name), "%s · %s" % [str(_mode.sub), str(_mode.map)], false, false)
	var column: VBoxContainer = fill_content(26)
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	_title = MenuUI.display("SEARCHING FOR PLAYERS", 62)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	var row := MenuUI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var total: int = _player_count()
	for i in total:
		var slot: Control = _slot(str(SaveGame.player_name) if i == 0 else "",
				menu.selected_brawler() if i == 0 else {}, i == 0)
		_slots.append(slot)
		row.add_child(slot)

	_status = MenuUI.body("Estimated wait: a few seconds", 26, MenuUI.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	var cancel_row := MenuUI.hbox(0)
	cancel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(cancel_row)
	_cancel = MenuUI.button("CANCEL", "red")
	_cancel.pressed.connect(func() -> void:
		_cancelled = true
		sfx("back")
		close_screen())
	cancel_row.add_child(_cancel)

	_names = BOT_NAMES.duplicate()
	_names.shuffle()
	_dots()
	get_tree().create_timer(0.5).timeout.connect(_fill_next)

func _player_count() -> int:
	var id: String = str(_mode.get("id", "showdown_solo"))
	return 10 if id.begins_with("showdown") else 6

## One lobby slot: a portrait plate with the player's name under it.
func _slot(player: String, brawler: Dictionary, mine: bool) -> Control:
	var plate: PanelContainer = MenuUI.panel("navy", 14, 6, 0)
	plate.custom_minimum_size = Vector2(150, 190)
	plate.clip_contents = true
	var column := MenuUI.vbox(0)
	plate.add_child(column)
	var art := Control.new()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.clip_contents = true
	column.add_child(art)
	art.add_child(MenuUI.card_backdrop(Color("#3a4160")))
	if player == "":
		var question: Label = MenuUI.display("?", 80, Color(1, 1, 1, 0.25), 0)
		question.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art.add_child(question)
	else:
		var portrait := TextureRect.new()
		portrait.texture = MenuData.portrait(str(brawler.get("id", "")))
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Oversized and bottom-anchored like the roster cards, so the head fills
		# the plate instead of floating small in the middle of it.
		portrait.offset_left = -22
		portrait.offset_right = 22
		portrait.offset_top = 2
		portrait.offset_bottom = 30
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if portrait.texture == null:
			var initial: Label = MenuUI.display(str(brawler.get("name", "?")).substr(0, 1), 72,
					brawler.get("color", Color.WHITE), 8)
			initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			art.add_child(initial)
		else:
			art.add_child(portrait)
	var name_bar := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MenuUI.YELLOW if mine else (MenuUI.BLUE if player != "" else Color("#4b5270"))
	style.border_width_top = 3
	style.border_color = MenuUI.LINE
	name_bar.add_theme_stylebox_override("panel", style)
	name_bar.custom_minimum_size = Vector2(0, 44)
	column.add_child(name_bar)
	var label: Label = MenuUI.display(player if player != "" else "…", 22,
			MenuUI.GOLD_INK if mine else MenuUI.TEXT, 0)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	name_bar.add_child(label)
	if mine:
		var outline := Panel.new()
		var outline_style := StyleBoxFlat.new()
		outline_style.bg_color = Color(0, 0, 0, 0)
		outline_style.set_border_width_all(4)
		outline_style.border_color = MenuUI.YELLOW
		outline_style.set_corner_radius_all(14)
		outline.add_theme_stylebox_override("panel", outline_style)
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outline.offset_bottom = -6
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(outline)
	return plate

func _fill_next() -> void:
	if _cancelled or not is_inside_tree():
		return
	var total: int = _player_count()
	if _filled >= total:
		_found()
		return
	# Bots only wear fighters that have portrait art, so no lobby slot fills
	# with an empty plate.
	var roster: Array = []
	for b in MenuData.brawlers:
		if MenuData.portrait(str(b.id)) != null:
			roster.append(b)
	if roster.is_empty():
		roster = MenuData.brawlers
	var slot: Control = _slot(str(_names[_filled % _names.size()]),
			roster[randi() % roster.size()], false)
	var old: Control = _slots[_filled]
	old.add_sibling(slot)
	old.queue_free()
	_slots[_filled] = slot
	_filled += 1
	sfx("tick")
	await get_tree().process_frame
	if is_instance_valid(slot):
		MenuUI.pop_in(slot)
	get_tree().create_timer(randf_range(0.26, 0.68)).timeout.connect(_fill_next)

func _found() -> void:
	if _cancelled:
		return
	sfx("found")
	_title.text = "MATCH FOUND!"
	_title.add_theme_color_override("font_color", MenuUI.GREEN)
	_title.add_theme_font_size_override("font_size", 90)
	_status.text = "Loading %s…" % str(_mode.map)
	_cancel.hide()
	if not MenuData.mode_playable(str(_mode.get("id", ""))):
		_status.text = "%s isn't built yet — dropping into Showdown." % str(_mode.name)
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if _cancelled or not is_inside_tree():
			return
		menu.start_match())

## The animated "…" after SEARCHING FOR PLAYERS.
func _dots() -> void:
	var base: String = "SEARCHING FOR PLAYERS"
	var step: int = 0
	var timer := Timer.new()
	timer.wait_time = 0.3
	timer.timeout.connect(func() -> void:
		if _title.text.begins_with(base):
			step = (step + 1) % 4
			_title.text = base + ".".repeat(step))
	add_child(timer)
	timer.start()
