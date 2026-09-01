class_name BrawlerDetailScreen
extends MenuScreen
## One fighter, up close — the detail half of web-menu/src/screens/brawlers.js:
## a second live 3D view with clip buttons, the stat block, trophy road, the
## attack/super write-ups, upgrade for coins and SELECT.

const PANEL_WIDTH := 640.0

var brawler: Dictionary = {}
var roster: BrawlersScreen

var _view: MenuStage
var _select_button: Button

func _build() -> void:
	screen_name = "brawler-detail"
	topbar(str(brawler.name), str(brawler.title))
	var row := MenuUI.hbox(30)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	body.add_child(margin)
	content = row

	row.add_child(_build_view())
	row.add_child(_build_panel())

func _build_view() -> Control:
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view = MenuStage.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_view)
	_view.show_brawler(brawler)
	_view.tapped.connect(func() -> void: sfx("hit"))

	var clips := MenuUI.hbox(12)
	clips.alignment = BoxContainer.ALIGNMENT_CENTER
	clips.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	clips.offset_top = -80
	clips.offset_bottom = -40
	holder.add_child(clips)
	# The model only exists once the view is in the tree, and which clip
	# buttons make sense depends on what the kit's GLB actually has.
	_view.ready.connect(func() -> void: _build_clip_buttons(clips))
	return holder

func _build_clip_buttons(clips: HBoxContainer) -> void:
	if _view.has_clip("attack"):
		clips.add_child(_clip_button("ATTACK", func() -> void: _view.play_attack()))
	if _view.has_clip("super"):
		clips.add_child(_clip_button("SUPER", func() -> void: _view.play_super()))
	if _view.has_clip("run"):
		clips.add_child(_clip_button("RUN", func() -> void: _view.play_run()))
	clips.add_child(_clip_button("IDLE", func() -> void: _view.play_idle()))

func _clip_button(label: String, action: Callable) -> Button:
	var b: Button = MenuUI.small_button(label, "grey")
	b.pressed.connect(func() -> void:
		sfx("hit")
		action.call())
	return b

func _build_panel() -> Control:
	var id: String = str(brawler.id)
	var stats: Dictionary = brawler.stats
	var rarity: Dictionary = MenuData.rarity_of(brawler)
	var trophies: int = SaveGame.brawler_trophies(id)
	var power: int = SaveGame.brawler_power(id)
	var rank: int = _rank_from_trophies(trophies)
	var goal: int = 4 * rank * rank

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := MenuUI.vbox(18)
	column.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	scroll.add_child(column)

	var head := MenuUI.hbox(16)
	var rarity_chip := PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = MenuUI.hex(rarity.get("color"), MenuUI.GREEN)
	chip_style.set_corner_radius_all(12)
	chip_style.set_border_width_all(3)
	chip_style.border_color = MenuUI.LINE
	chip_style.content_margin_left = 18
	chip_style.content_margin_right = 18
	chip_style.content_margin_top = 8
	chip_style.content_margin_bottom = 8
	rarity_chip.add_theme_stylebox_override("panel", chip_style)
	rarity_chip.add_child(MenuUI.display(str(rarity.get("label", "Rare")), 26, MenuUI.TEXT, 4))
	head.add_child(rarity_chip)
	var role: Label = MenuUI.body(str(brawler.role), 24, MenuUI.TEXT_DIM)
	role.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(role)
	column.add_child(head)
	column.add_child(MenuUI.wrap(MenuUI.body(str(brawler.description), 24, MenuUI.TEXT_SOFT)))

	# trophy road
	var road: PanelContainer = MenuUI.dark_panel(14, 0.35, 16)
	var road_row := MenuUI.hbox(12)
	road.add_child(road_row)
	road_row.add_child(MenuUI.icon("trophy", 44))
	var road_bar: Panel = MenuUI.bar(22, MenuUI.YELLOW, MenuUI.YELLOW_HI)
	road_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	road_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	road_row.add_child(road_bar)
	road_row.add_child(MenuUI.display("%s / %s" % [MenuUI.fmt(trophies), MenuUI.fmt(goal)],
			26, MenuUI.YELLOW_HI, 4))
	road_row.add_child(MenuUI.display("RANK %d" % rank, 26, MenuUI.TEXT, 4))
	column.add_child(road)
	MenuUI.set_bar(road_bar, float(trophies) / maxf(1.0, float(goal)))

	var stat_grid: GridContainer = MenuUI.grid(2, 12)
	stat_grid.add_child(_stat("Health", MenuUI.fmt(int(stats.health))))
	stat_grid.add_child(_stat("Damage", MenuUI.fmt(int(stats.damage))))
	stat_grid.add_child(_stat("Speed", str(stats.speed)))
	stat_grid.add_child(_stat("Range", str(stats.range)))
	stat_grid.add_child(_stat("Reload", str(stats.reload)))
	stat_grid.add_child(_stat("Power", "LVL %d" % power))
	column.add_child(stat_grid)

	column.add_child(_ability("A", Color("#d84a10"), Color("#ff9a5c"), brawler.attack))
	column.add_child(_ability("S", MenuUI.YELLOW_LO, MenuUI.YELLOW_HI, brawler.super))
	column.add_child(MenuUI.spacer())

	var actions := MenuUI.hbox(16)
	var cost: int = 200 * power
	var upgrade: Button = MenuUI.button("UPGRADE  %s" % MenuUI.fmt(cost), "blue")
	upgrade.pressed.connect(func() -> void: _upgrade(cost))
	actions.add_child(upgrade)
	var selected: bool = id == SaveGame.selected_kit.to_lower()
	_select_button = MenuUI.button("SELECTED" if selected else "SELECT",
			"grey" if selected else "yellow", 44)
	_select_button.custom_minimum_size = Vector2(0, 96)
	_select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select_button.disabled = selected
	_select_button.pressed.connect(_select)
	actions.add_child(_select_button)
	column.add_child(actions)
	return scroll

func _stat(key: String, value: String) -> PanelContainer:
	var p: PanelContainer = MenuUI.dark_panel(12, 0.35, 12)
	var row := MenuUI.hbox(10)
	p.add_child(row)
	var k: Label = MenuUI.body(key.to_upper(), 20, MenuUI.TEXT_DIM)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)
	row.add_child(MenuUI.spacer())
	row.add_child(MenuUI.display(value, 30, MenuUI.TEXT, 0))
	return p

func _ability(letter: String, dark: Color, light: Color, ability: Dictionary) -> PanelContainer:
	var p: PanelContainer = MenuUI.dark_panel(14, 0.35, 14)
	var row := MenuUI.hbox(14)
	p.add_child(row)
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = dark
	style.border_width_top = 6
	style.border_color = light
	style.set_corner_radius_all(14)
	style.set_content_margin_all(10)
	badge.add_theme_stylebox_override("panel", style)
	badge.custom_minimum_size = Vector2(78, 78)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var letter_label: Label = MenuUI.display(letter, 40, MenuUI.TEXT, 5)
	letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(letter_label)
	row.add_child(badge)
	var text := MenuUI.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(MenuUI.display(str(ability.name), 28, MenuUI.TEXT, 4))
	text.add_child(MenuUI.wrap(MenuUI.body(str(ability.text), 21, MenuUI.TEXT_SOFT)))
	row.add_child(text)
	return p

func _upgrade(cost: int) -> void:
	var id: String = str(brawler.id)
	if SaveGame.coins < cost:
		sfx("error")
		toast("Need %s coins" % MenuUI.fmt(cost), "coin")
		return
	SaveGame.coins -= cost
	SaveGame.set_brawler_power(id, SaveGame.brawler_power(id) + 1)
	SaveGame.save()
	menu.refresh_currencies()
	sfx("purchase")
	toast("%s is now Power %d!" % [str(brawler.name), SaveGame.brawler_power(id)], "power_point")
	# Rebuild so every number on the panel reflects the new level.
	var again := BrawlerDetailScreen.new()
	again.brawler = brawler
	again.roster = roster
	menu.push_screen(again)
	close_screen()

func _select() -> void:
	menu.select_brawler(str(brawler.id))
	sfx("reward")
	toast("%s is ready to brawl!" % str(brawler.name), "check")
	_select_button.text = "SELECTED"
	_select_button.disabled = true
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(roster):
			roster.close_screen()
		close_screen())

## rankFromTrophies() from the web build.
func _rank_from_trophies(t: int) -> int:
	return clampi(int(floor(sqrt(float(t) / 4.0))) + 1, 1, 35)
