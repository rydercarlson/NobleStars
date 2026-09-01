class_name NewsScreen
extends MenuScreen
## News — the cards from data/game.json, accent-striped like the web build.

func _build() -> void:
	screen_name = "news"
	topbar("News")
	var column: VBoxContainer = scroll_content()
	var grid: GridContainer = MenuUI.grid(2)
	column.add_child(grid)
	for item in MenuData.game.get("news", []):
		grid.add_child(_card(item))
	stagger_children(grid, 0.06)

func _card(item: Dictionary) -> Panel:
	var accent: Color = MenuUI.hex(item.get("accent"), MenuUI.YELLOW)
	var card: Panel = MenuUI.card()
	card.custom_minimum_size = Vector2(0, 240)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_right = 14
	stripe.offset_bottom = -7
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stripe)
	var column := MenuUI.vbox(10)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 34
	column.offset_right = -26
	column.offset_top = 22
	column.offset_bottom = -29
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var tag := PanelContainer.new()
	var tag_style := StyleBoxFlat.new()
	tag_style.bg_color = accent
	tag_style.set_corner_radius_all(8)
	tag_style.set_border_width_all(2)
	tag_style.border_color = MenuUI.LINE
	tag_style.content_margin_left = 12
	tag_style.content_margin_right = 12
	tag_style.content_margin_top = 5
	tag_style.content_margin_bottom = 5
	tag.add_theme_stylebox_override("panel", tag_style)
	tag.add_child(MenuUI.display(str(item.tag), 20, MenuUI.INK, 0))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(tag)
	column.add_child(MenuUI.wrap(MenuUI.display(str(item.title), 38, MenuUI.TEXT, 6)))
	column.add_child(MenuUI.wrap(MenuUI.body(str(item.body), 22, MenuUI.TEXT_SOFT)))
	column.add_child(MenuUI.spacer())
	column.add_child(MenuUI.body(str(item.date), 19, MenuUI.TEXT_DIM))
	return card
