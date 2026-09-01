class_name BrawlersScreen
extends MenuScreen
## The roster grid — web-menu/src/screens/brawlers.js. Rarity-coloured cards
## with the GLB-rendered portrait, trophies and power level; tapping one opens
## the detail view, and a locked fighter says how to get them.

const COLUMNS := 6

func _build() -> void:
	screen_name = "brawlers"
	var unlocked: int = 0
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.id)):
			unlocked += 1
	topbar("Brawlers", "%d/%d unlocked" % [unlocked, MenuData.brawlers.size()])
	var column: VBoxContainer = scroll_content()
	var grid: GridContainer = MenuUI.grid(COLUMNS)
	column.add_child(grid)
	for b in MenuData.brawlers:
		grid.add_child(_card(b))
	stagger_children(grid)

func _card(b: Dictionary) -> Button:
	var id: String = str(b.id)
	var rarity: Dictionary = MenuData.rarity_of(b)
	var unlocked: bool = SaveGame.is_unlocked(id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 300)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	var box: StyleBoxTexture = MenuUI.plate_box("card", 18, 7, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, box)
	MenuUI.press_feedback(card)
	card.pressed.connect(func() -> void:
		if unlocked:
			sfx("click")
			open_detail(b)
		else:
			sfx("error")
			toast(str(b.unlock_hint) if str(b.unlock_hint) != "" else "Locked", "lock"))

	var art := Control.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_bottom = -69
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	art.add_child(MenuUI.card_backdrop(MenuUI.hex(rarity.get("dark"), Color("#3a4160"))))
	art.add_child(_portrait(b, unlocked))

	if not unlocked:
		var lock: TextureRect = MenuUI.icon("lock", 90)
		lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		lock.grow_horizontal = Control.GROW_DIRECTION_BOTH
		lock.grow_vertical = Control.GROW_DIRECTION_BOTH
		art.add_child(lock)
	else:
		var trophies: PanelContainer = MenuUI.chip(MenuUI.fmt(SaveGame.brawler_trophies(id)), "trophy")
		MenuUI.pin(trophies, false, false, 10)
		art.add_child(trophies)
		var power := PanelContainer.new()
		var power_style := StyleBoxFlat.new()
		power_style.bg_color = Color("#c8188f")
		power_style.set_corner_radius_all(10)
		power_style.set_border_width_all(2)
		power_style.border_color = MenuUI.LINE
		power_style.set_content_margin_all(6)
		power.add_theme_stylebox_override("panel", power_style)
		power.add_child(MenuUI.display("P%d" % SaveGame.brawler_power(id), 22, MenuUI.TEXT, 0))
		MenuUI.pin(power, true, false, 10)
		art.add_child(power)

	var name_bar := Panel.new()
	var name_style := StyleBoxFlat.new()
	name_style.bg_color = MenuUI.hex(rarity.get("color"), Color("#59c1ff")) if unlocked else Color("#4b5270")
	name_style.border_width_top = 3
	name_style.border_color = MenuUI.LINE
	name_bar.add_theme_stylebox_override("panel", name_style)
	name_bar.anchor_top = 1.0
	name_bar.anchor_right = 1.0
	name_bar.anchor_bottom = 1.0
	name_bar.offset_top = -69
	name_bar.offset_bottom = -7
	name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_bar)
	var name_label: Label = MenuUI.display(str(b.name), 30,
			MenuUI.TEXT if unlocked else MenuUI.TEXT_DIM, 4)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_bar.add_child(name_label)

	if str(b.id) == SaveGame.selected_kit.to_lower():
		var outline := Panel.new()
		var outline_style := StyleBoxFlat.new()
		outline_style.bg_color = Color(0, 0, 0, 0)
		outline_style.set_border_width_all(5)
		outline_style.border_color = MenuUI.YELLOW
		outline_style.set_corner_radius_all(18)
		outline.add_theme_stylebox_override("panel", outline_style)
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outline.offset_bottom = -7
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(outline)
		var tag := PanelContainer.new()
		var tag_style := StyleBoxFlat.new()
		tag_style.bg_color = MenuUI.YELLOW
		tag_style.corner_radius_bottom_left = 10
		tag_style.corner_radius_bottom_right = 10
		tag_style.set_border_width_all(3)
		tag_style.border_width_top = 0
		tag_style.border_color = MenuUI.LINE
		tag_style.content_margin_left = 14
		tag_style.content_margin_right = 14
		tag_style.content_margin_bottom = 4
		tag.add_theme_stylebox_override("panel", tag_style)
		tag.add_child(MenuUI.display("SELECTED", 20, MenuUI.GOLD_INK, 0))
		tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
		tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tag)
	return card

## The rendered portrait, bottom-anchored and slightly oversized like the CSS.
## Fighters without a model yet fall back to their kit colour and initial.
func _portrait(b: Dictionary, unlocked: bool) -> Control:
	var texture: Texture2D = MenuData.portrait(str(b.id))
	if texture == null:
		var initial: Label = MenuUI.display(str(b.name).substr(0, 1), 150,
				b.get("color", Color.WHITE), 10)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return initial
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = -18
	art.offset_right = 18
	art.offset_top = 10
	art.offset_bottom = 18
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		art.modulate = Color(0, 0, 0, 0.75)
	return art

func open_detail(b: Dictionary) -> void:
	var detail := BrawlerDetailScreen.new()
	detail.brawler = b
	detail.roster = self
	menu.push_screen(detail)
