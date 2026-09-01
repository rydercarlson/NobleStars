class_name MenuPopup
extends MenuScreen
## popup() from web-menu/src/ui.js: a centred plate with a title bar and a body
## the caller fills. Tapping the dimmed backdrop closes it.

const MAX_BODY_HEIGHT := 760.0

var title: String = ""
var width: float = 760.0
var body_box: VBoxContainer
var _scroll: ScrollContainer

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			menu.sfx("back")
			close_screen())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var plate: PanelContainer = MenuUI.panel("navy", 18, 7, 0)
	plate.custom_minimum_size = Vector2(width, 0)
	center.add_child(plate)

	var column := MenuUI.vbox(0)
	plate.add_child(column)

	var header := MenuUI.hbox(16)
	var header_wrap := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0, 0, 0, 0.2)
	header_style.border_width_bottom = 3
	header_style.border_color = MenuUI.LINE
	header_style.content_margin_left = 30
	header_style.content_margin_right = 22
	header_style.content_margin_top = 18
	header_style.content_margin_bottom = 18
	header_style.corner_radius_top_left = 16
	header_style.corner_radius_top_right = 16
	header_wrap.add_theme_stylebox_override("panel", header_style)
	header_wrap.add_child(header)
	column.add_child(header_wrap)

	var title_label: Label = MenuUI.display(title.to_upper(), 44, MenuUI.TEXT, 6)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)
	var close := MenuUI.icon_button("close", 62)
	close.pressed.connect(func() -> void:
		menu.sfx("back")
		close_screen())
	header.add_child(close)

	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll_wrap := MarginContainer.new()
	scroll_wrap.add_theme_constant_override("margin_left", 30)
	scroll_wrap.add_theme_constant_override("margin_right", 30)
	scroll_wrap.add_theme_constant_override("margin_top", 24)
	scroll_wrap.add_theme_constant_override("margin_bottom", 30)
	scroll_wrap.add_child(scroll)
	column.add_child(scroll_wrap)

	body_box = MenuUI.vbox(18)
	body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_box)
	content = body_box
	# A ScrollContainer has no minimum height of its own, so the plate would
	# collapse to just its title bar — follow the body until it needs to scroll.
	body_box.minimum_size_changed.connect(_fit_body)
	_fit_body.call_deferred()

func _fit_body() -> void:
	if _scroll == null or body_box == null:
		return
	_scroll.custom_minimum_size.y = minf(body_box.get_combined_minimum_size().y,
			MAX_BODY_HEIGHT)

## A labelled row of the kind the settings and profile popups are made of.
func setting_row(label: String, hint: String, control: Control) -> PanelContainer:
	var row: PanelContainer = MenuUI.dark_panel(14, 0.35, 16)
	var box := MenuUI.hbox(18)
	row.add_child(box)
	var text := MenuUI.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(MenuUI.display(label.to_upper(), 28, MenuUI.TEXT, 0))
	text.add_child(MenuUI.body(hint, 19, MenuUI.TEXT_DIM))
	box.add_child(text)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(control)
	body_box.add_child(row)
	return row
