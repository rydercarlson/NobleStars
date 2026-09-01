class_name LobbyScreen
extends Control
## Home screen, drawn by the painted assembly-hall artwork (the shell's lobby
## backdrop): invisible hotspots sit over the art's buttons and route into the
## real screens, and the few values the art can't bake — player name, trophies,
## coins, selected fighter, an off-default mode — render as overlays.

var menu: MenuShell

var name_label: Label
var trophy_btn: Button
var coin_pill: PanelContainer
var fighter_label: Label
var mode_pill: PanelContainer
var mode_label: Label
var news_popup: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

func _ready() -> void:
	# Hotspots over the buttons painted into the artwork.
	_hotspot(0.031, 0.062, 0.157, 0.140, func() -> void: menu.show_screen("settings"))
	_hotspot(0.179, 0.055, 0.347, 0.151, func() -> void: news_popup.visible = true)
	_hotspot(0.914, 0.058, 0.970, 0.130, func() -> void: menu.show_screen("settings"))
	_hotspot(0.023, 0.213, 0.108, 0.310, func() -> void: menu.show_screen("shop"))
	_hotspot(0.023, 0.342, 0.108, 0.444, func() -> void: menu.show_screen("fighters"))
	_hotspot(0.023, 0.468, 0.108, 0.593, func() -> void: menu.show_screen("road"))
	_hotspot(0.910, 0.215, 0.992, 0.317, func() -> void: news_popup.visible = true)
	_hotspot(0.910, 0.342, 0.992, 0.444, func() -> void: menu.show_screen("friends"))
	_hotspot(0.910, 0.470, 0.992, 0.572, func() -> void: _show_toast("Club — coming soon"))
	_hotspot(0.910, 0.597, 0.992, 0.699, func() -> void: _show_toast("Inbox — coming soon"))
	_hotspot(0.429, 0.842, 0.683, 0.954, func() -> void: menu.show_screen("modes"))
	_hotspot(0.701, 0.838, 0.916, 0.959, func() -> void: _play())

	# Player name over the art's GUEST chip text plate.
	var name_wrap := PanelContainer.new()
	name_wrap.add_theme_stylebox_override("panel", UIKit.flat(UIKit.NAVY_DEEP, 10))
	name_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchors(name_wrap, 0.072, 0.074, 0.152, 0.128)
	name_label = UIKit.label("", 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_wrap.add_child(name_label)
	add_child(name_wrap)

	# Trophies (tap for Trophy Road) and coins, in the open girder gap.
	trophy_btn = Button.new()
	trophy_btn.add_theme_font_size_override("font_size", 19)
	for state in ["normal", "hover", "pressed", "focus"]:
		trophy_btn.add_theme_stylebox_override(state,
				UIKit.flat(UIKit.NAVY_DEEP, 14, 2, UIKit.GOLD, 8))
	trophy_btn.pressed.connect(func() -> void: menu.show_screen("road"))
	_anchors(trophy_btn, 0.585, 0.062, 0.680, 0.138)
	add_child(trophy_btn)
	coin_pill = UIKit.pill("", UIKit.PLAY_YELLOW)
	coin_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchors(coin_pill, 0.692, 0.062, 0.780, 0.138)
	add_child(coin_pill)

	# Selected fighter's name on the stage boards, under the 3D model.
	fighter_label = UIKit.label("", 26)
	fighter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fighter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fighter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchors(fighter_label, 0.39, 0.728, 0.61, 0.778)
	add_child(fighter_label)

	# The art's chip reads SHOWDOWN — cover its text only when the saved mode
	# says otherwise.
	mode_pill = PanelContainer.new()
	mode_pill.add_theme_stylebox_override("panel", UIKit.flat(Color(0.13, 0.14, 0.18), 12))
	mode_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchors(mode_pill, 0.503, 0.856, 0.676, 0.942)
	mode_label = UIKit.label("", 20)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_pill.add_child(mode_label)
	add_child(mode_pill)

	_build_toast()
	_build_news_popup()
	refresh()

func _play() -> void:
	Session.kit = Kits.named(SaveGame.selected_kit)
	Session.mode = SaveGame.selected_mode
	get_tree().change_scene_to_file("res://game.tscn")

func _anchors(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0

## Invisible button over a painted control, with a soft flash while pressed.
func _hotspot(l: float, t: float, r: float, b: float, action: Callable) -> void:
	var btn := Button.new()
	btn.flat = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, empty)
	_anchors(btn, l, t, r, b)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.16)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.visible = false
	btn.add_child(flash)
	btn.button_down.connect(func() -> void: flash.visible = true)
	btn.button_up.connect(func() -> void: flash.visible = false)
	btn.pressed.connect(action)
	add_child(btn)

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel",
			UIKit.flat(Color(0.10, 0.11, 0.15, 0.92), 14, 2, UIKit.GOLD, 14))
	_toast_label = UIKit.label("", 22)
	_toast.add_child(_toast_label)
	_anchors(_toast, 0.5, 0.66, 0.5, 0.66)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BOTH
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.reset_size()
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)

func _build_news_popup() -> void:
	news_popup = Control.new()
	news_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	news_popup.visible = false
	add_child(news_popup)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	news_popup.add_child(dim)

	var panel := UIKit.panel()
	news_popup.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var head := UIKit.label("SEASON 1 — SHOWDOWN", 30, UIKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var body := UIKit.label("Ten fighters drop into a shrinking arena.\nSmash loot boxes, grab power cubes,\nand be the last star standing.\n\nNew game modes and fighters are on the way!", 18, UIKit.MUTED)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	var ok := UIKit.button("GOT IT", 24, UIKit.PLAY_YELLOW)
	for state_color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ok.add_theme_color_override(state_color, UIKit.NAVY)
	ok.pressed.connect(func() -> void: news_popup.visible = false)
	box.add_child(ok)

func refresh() -> void:
	name_label.text = SaveGame.player_name.to_upper()
	trophy_btn.text = "★ %d" % SaveGame.total_trophies()
	UIKit.set_pill_text(coin_pill, "$ %d" % SaveGame.coins)
	fighter_label.text = SaveGame.selected_kit.to_upper()
	var off_default := SaveGame.selected_mode != "showdown"
	mode_pill.visible = off_default
	if off_default:
		mode_label.text = SaveGame.selected_mode.to_upper().replace("_", " ")
