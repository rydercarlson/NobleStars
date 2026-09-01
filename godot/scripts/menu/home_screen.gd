class_name HomeScreen
extends Control
## The home HUD, rebuilt from web-menu/index.html + the #home rules in
## styles.css: profile plate and season plate top-left, currencies and the menu
## button top-right, the painted button columns down each side, and the mode
## plate + PLAY on the bottom right. Every offset below is the CSS one.

var menu: MenuShell
var floor_y: float = 780.0

var _name_label: Label
var _trophy_label: Label
var _season_line1: Label
var _season_line2: Label
var _season_bar: Panel
var _mode_icon: TextureRect
var _mode_name: Label
var _mode_sub: Label
var _mode_tab: Panel
var _friends_dot: Control
var _inbox_dot: Control
var _hint: Label
var _intro_done := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_profile()
	_build_season()
	_build_currency()
	_build_menu_button()
	_build_side_columns()
	_build_bottom()
	_build_hint()
	refresh()
	menu.brawler_view.tapped.connect(_on_brawler_tapped)
	_play_intro()

# MARK: top-left

func _build_profile() -> void:
	var b: Button = _plate_button(300, 106, "navy")
	_place(b, 40, 44)
	b.pressed.connect(func() -> void:
		menu.sfx("click")
		menu.push_screen(TrophyRoadScreen.new()))
	var row := _inner_row(b, 14, 14, 20)
	row.add_child(MenuUI.icon("shield", 84))
	var lines := MenuUI.vbox(2)
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# clip_text zeroes the label's minimum width, so the column has to claim the
	# rest of the plate or the name gets clipped to the trophy row underneath.
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lines)
	_name_label = MenuUI.display("GUEST", 36)
	_name_label.clip_text = true
	lines.add_child(_name_label)
	var trophies := MenuUI.hbox(6)
	trophies.add_child(MenuUI.icon("trophy", 26))
	_trophy_label = MenuUI.display("0", 24, MenuUI.YELLOW_HI, 5)
	trophies.add_child(_trophy_label)
	lines.add_child(trophies)

func _build_season() -> void:
	var b: Button = _plate_button(420, 106, "yellow")
	_place(b, 356, 44)
	b.pressed.connect(func() -> void:
		menu.sfx("click")
		menu.push_screen(PassScreen.new()))
	var row := _inner_row(b, 14, 12, 26)
	row.add_child(MenuUI.icon("shield", 84))
	var lines := MenuUI.vbox(3)
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lines)
	_season_line1 = MenuUI.display("SEASON 1", 34, MenuUI.TEXT, 6)
	_season_line2 = MenuUI.display("BACK TO SCHOOL", 28, MenuUI.TEXT, 6)
	lines.add_child(_season_line1)
	lines.add_child(_season_line2)
	# The token bar straddles the bottom edge of the plate, as in the CSS.
	_season_bar = MenuUI.bar(18, MenuUI.GREEN, MenuUI.GREEN_HI)
	_place(_season_bar, 370, 137, 392, 18)

func _build_currency() -> void:
	var pills: HBoxContainer = menu.currency_pills()
	pills.anchor_left = 1.0
	pills.anchor_right = 1.0
	pills.offset_left = -570
	pills.offset_right = -210
	pills.offset_top = 50
	pills.offset_bottom = 112
	add_child(pills)

func _build_menu_button() -> void:
	var b: TextureButton = MenuUI.art_button(load("res://assets/menu/btn_menu.png"), 92)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -40 - b.custom_minimum_size.x
	b.offset_right = -40
	b.offset_top = 44
	b.offset_bottom = 44 + 92
	b.pressed.connect(func() -> void:
		menu.sfx("click")
		MenuPopups.settings(menu))
	add_child(b)

# MARK: side columns

func _build_side_columns() -> void:
	var left := MenuUI.vbox(14)
	left.alignment = BoxContainer.ALIGNMENT_BEGIN
	_place(left, 34, 208, 220, 520)
	var shop_btn: TextureButton = _side_button("shop", 128, func() -> void:
		menu.push_screen(ShopScreen.new()))
	var roster_btn: TextureButton = _side_button("brawlers", 128, func() -> void:
		menu.push_screen(BrawlersScreen.new()))
	var pass_btn: TextureButton = _side_button("nobles_pass", 150, func() -> void:
		menu.push_screen(PassScreen.new()))
	for b in [shop_btn, roster_btn, pass_btn]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		left.add_child(b)

	var right := MenuUI.vbox(14)
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -34 - 220
	right.offset_right = -34
	right.offset_top = 208
	right.offset_bottom = 208 + 600
	add_child(right)
	var news: TextureButton = _side_button("news", 128, func() -> void:
		menu.push_screen(NewsScreen.new()))
	var friends: TextureButton = _side_button("friends", 128, func() -> void:
		menu.push_screen(FriendsScreen.new()))
	var club: TextureButton = _side_button("club", 128, func() -> void:
		menu.push_screen(ClubScreen.new()))
	var inbox: TextureButton = _side_button("inbox", 128, func() -> void:
		menu.push_screen(InboxScreen.new()))
	for b in [news, friends, club, inbox]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		right.add_child(b)
	_friends_dot = _badge(friends, MenuUI.GREEN)
	_inbox_dot = _badge(inbox, MenuUI.RED)

func _side_button(art: String, height: float, action: Callable) -> TextureButton:
	var b: TextureButton = MenuUI.art_button(load("res://assets/menu/btn_%s.png" % art), height)
	b.pressed.connect(func() -> void:
		menu.sfx("click")
		action.call())
	return b

## The unread / online count that rides on the corner of a side button.
func _badge(host: Control, color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(17)
	style.set_border_width_all(3)
	style.border_color = MenuUI.LINE
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 1
	style.content_margin_bottom = 3
	badge.add_theme_stylebox_override("panel", style)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -40
	badge.offset_top = -8
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = MenuUI.display("0", 22, MenuUI.TEXT, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(label)
	badge.set_meta("label", label)
	host.add_child(badge)
	return badge

# MARK: bottom row

func _build_bottom() -> void:
	var row := MenuUI.hbox(30)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 44
	row.offset_right = -44
	row.offset_top = -176
	row.offset_bottom = -42
	add_child(row)

	var mode: Button = _plate_button(470, 130, "navy")
	mode.size_flags_vertical = Control.SIZE_SHRINK_END
	mode.pressed.connect(func() -> void:
		menu.sfx("click")
		menu.push_screen(ModesScreen.new()))
	row.add_child(mode)
	var mode_row := _inner_row(mode, 14, 12, 90)
	_mode_icon = MenuUI.icon("bulldog", 116)
	mode_row.add_child(_mode_icon)
	var text := MenuUI.vbox(6)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_row.add_child(text)
	_mode_name = MenuUI.display("SHOWDOWN", 42, MenuUI.TEXT, 6)
	_mode_sub = MenuUI.display("SOLO", 28, MenuUI.GREEN, 5)
	text.add_child(_mode_name)
	text.add_child(_mode_sub)
	_mode_tab = Panel.new()
	_mode_tab.anchor_left = 1.0
	_mode_tab.anchor_right = 1.0
	_mode_tab.anchor_bottom = 1.0
	_mode_tab.offset_left = -78
	_mode_tab.offset_right = 0
	_mode_tab.offset_top = 0
	_mode_tab.offset_bottom = -7
	_mode_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode.add_child(_mode_tab)
	var chevron: TextureRect = MenuUI.icon("back", 34)
	chevron.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	chevron.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chevron.grow_vertical = Control.GROW_DIRECTION_BOTH
	chevron.scale = Vector2(-1, 1)
	chevron.pivot_offset = Vector2(17, 17)
	_mode_tab.add_child(chevron)

	var play: TextureButton = MenuUI.art_button(load("res://assets/menu/btn_play.png"), 134)
	play.size_flags_vertical = Control.SIZE_SHRINK_END
	play.pressed.connect(func() -> void:
		menu.sfx("play")
		menu.push_screen(MatchmakingScreen.new()))
	row.add_child(play)

func _build_hint() -> void:
	_hint = MenuUI.display("TAP TO ATTACK  ·  DRAG TO SPIN", 20, MenuUI.TEXT, 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.offset_left = -240
	_hint.offset_right = 240
	_hint.offset_top = 800
	_hint.offset_bottom = 830
	_hint.modulate.a = 0.0
	add_child(_hint)

func _on_brawler_tapped() -> void:
	menu.sfx("hit")
	if SaveGame.first_run:
		SaveGame.first_run = false
		SaveGame.save()
	_hint.modulate.a = 0.0

# MARK: state

func refresh() -> void:
	var season: Dictionary = MenuData.season()
	_name_label.text = SaveGame.player_name.to_upper()
	_trophy_label.text = MenuUI.fmt(SaveGame.total_trophies())
	_season_line1.text = "SEASON %d" % int(season.get("number", 1))
	_season_line2.text = str(season.get("name", "")).to_upper()
	var per_tier: float = maxf(1.0, float(season.get("tokensPerTier", 500)))
	MenuUI.set_bar(_season_bar, SaveGame.pass_tokens / per_tier)

	var mode: Dictionary = menu.selected_mode()
	if not mode.is_empty():
		var color := Color(str(mode.get("color", "#57c81e")))
		_mode_icon.texture = MenuUI.icon_texture(str(mode.get("icon", "bulldog")))
		_mode_name.text = str(mode.get("name", "SHOWDOWN"))
		_mode_sub.text = str(mode.get("sub", "")).to_upper()
		_mode_sub.add_theme_color_override("font_color", color)
		var tab := StyleBoxFlat.new()
		tab.bg_color = color
		tab.border_width_left = 3
		tab.border_color = MenuUI.LINE
		tab.corner_radius_top_right = 14
		tab.corner_radius_bottom_right = 14
		_mode_tab.add_theme_stylebox_override("panel", tab)

	var online: int = 0
	for f in MenuData.game.get("friends", []):
		if str(f.get("status", "")) == "online":
			online += 1
	_set_badge(_friends_dot, online)
	_set_badge(_inbox_dot, SaveGame.unread_mail())
	_hint.modulate.a = 0.85 if (SaveGame.hints_on and SaveGame.first_run) else 0.0
	_hint.offset_top = floor_y + 44.0
	_hint.offset_bottom = floor_y + 78.0

func _set_badge(badge: Control, count: int) -> void:
	badge.visible = count > 0
	if count > 0:
		var label: Label = badge.get_meta("label")
		label.text = str(count)

# MARK: layout helpers

## Position a control in stage pixels, anchored to the stage's top-left.
func _place(c: Control, x: float, y: float, w: float = -1.0, h: float = -1.0) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + (w if w > 0.0 else c.custom_minimum_size.x)
	c.offset_bottom = y + (h if h > 0.0 else c.custom_minimum_size.y)
	if c.get_parent() == null:
		add_child(c)

## A plate that is also a button — Button is not a container, so contents go in
## an anchored row (_inner_row) rather than as managed children.
func _plate_button(w: float, h: float, variant: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	var box: StyleBoxTexture = MenuUI.plate_box(variant, 16, 7, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, box)
	MenuUI.press_feedback(b)
	return b

func _inner_row(host: Control, left: float, gap: float, right: float) -> HBoxContainer:
	var row := MenuUI.hbox(int(gap))
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = left
	row.offset_right = -right
	row.offset_bottom = -7   # the plate's baked drop shadow
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(row)
	return row

## The CSS "hud-in" intro: every plate pops in once, staggered.
func _play_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	await get_tree().process_frame
	var i: int = 0
	for child in get_children():
		if child is Control and child != _hint:
			MenuUI.pop_in(child, 0.04 * i)
			i += 1
