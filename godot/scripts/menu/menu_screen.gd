class_name MenuScreen
extends Control
## Base for every pushed screen, mirroring ui.js openScreen()/topbar():
## dimmed backdrop, a top bar (back, title, subtitle, currency pills, close)
## and a content area that either scrolls or fills.
##
## Subclasses override _build(); `menu` is assigned before the screen enters
## the tree, so it is safe to use from there.

const PAD := 44

var menu: MenuShell
var screen_name: String = ""
var is_popup: bool = false

var body: VBoxContainer          # top bar + content live here
var content: Control             # what _build() fills

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not is_popup:
		# Opaque, not a translucent wash: MenuShell hides the 3D view behind a
		# pushed screen, so there is nothing to show through, and a screen that
		# half-reveals the stage under it reads as two screens at once.
		var backdrop := ColorRect.new()
		backdrop.color = MenuUI.INK
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(backdrop)
	body = MenuUI.vbox(0)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(body)
	_build()
	_animate_in()

## Subclasses build their screen here.
func _build() -> void:
	pass

func _animate_in() -> void:
	modulate.a = 0.0
	if is_popup:
		pivot_offset = size / 2.0
		scale = Vector2(0.88, 0.88)
		var tw := create_tween()
		tw.set_parallel()
		tw.tween_property(self, "modulate:a", 1.0, 0.18)
		tw.tween_property(self, "scale", Vector2.ONE, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	position.x = 42
	var tw2 := create_tween()
	tw2.set_parallel()
	tw2.tween_property(self, "modulate:a", 1.0, 0.16)
	tw2.tween_property(self, "position:x", 0.0, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# MARK: chrome

## The standard screen header. Returns the bar so callers can add extras.
func topbar(title: String, sub: String = "", currencies: bool = true,
		close: bool = true) -> HBoxContainer:
	var bar := MenuUI.hbox(22)
	bar.custom_minimum_size = Vector2(0, 122)
	bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_child(bar)
	body.add_child(margin)

	var back: Button = MenuUI.link("← BACK", 24)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		menu.sfx("back")
		close_screen())
	bar.add_child(back)
	bar.add_child(MenuUI.gap(18))
	var title_label: Label = MenuUI.display(title.to_upper(), 58)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(title_label)
	if sub != "":
		var sub_label: Label = MenuUI.label(sub, 20, MenuUI.TEXT_DIM)
		sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(sub_label)
	bar.add_child(MenuUI.spacer())
	if currencies:
		var money: HBoxContainer = menu.currency_pills()
		money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(money)
	if close:
		var x: Button = MenuUI.link("CLOSE", 24)
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		x.pressed.connect(func() -> void:
			menu.sfx("back")
			close_screen())
		bar.add_child(MenuUI.gap(10))
		bar.add_child(x)
	# The rule the whole screen hangs off, the same one home uses under its
	# identity block, so a pushed screen and the home screen share a horizon.
	var line: MarginContainer = MarginContainer.new()
	line.add_theme_constant_override("margin_left", 34)
	line.add_theme_constant_override("margin_right", 34)
	line.add_child(MenuUI.rule())
	body.add_child(line)
	return bar

## Scrolling content area (CSS ".content.scroll") — returns the column to fill.
func scroll_content(separation: int = 22) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	body.add_child(margin)
	var column := MenuUI.vbox(separation)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	content = column
	return column

## Non-scrolling content area that fills the rest of the screen.
func fill_content(separation: int = 22) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(margin)
	var column := MenuUI.vbox(separation)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	content = column
	return column

# MARK: helpers subclasses lean on

func close_screen() -> void:
	menu.pop_screen(self)

func sfx(sound: String) -> void:
	menu.sfx(sound)

func toast(text: String, icon_name: String = "") -> void:
	menu.toast(text, icon_name)

## Runs the CSS card "pop-in" once the container has been laid out.
func stagger_children(container: Node, step: float = 0.045) -> void:
	await get_tree().process_frame
	if is_instance_valid(container):
		MenuUI.stagger(container, step)

## Stage-space centre of a control, for particle bursts.
func center_of(c: Control) -> Vector2:
	var p: Vector2 = c.get_global_rect().get_center() - menu.stage.global_position
	return p / maxf(menu.stage.scale.x, 0.0001)
