class_name LobbyScreen
extends Control
## Home screen: top bar (name/trophies/coins), left nav column + news banner,
## selected fighter center-stage (drawn by the shell's MenuStage), mode + PLAY.

var menu: MenuShell

var name_pill: PanelContainer
var trophy_btn: Button
var coin_pill: PanelContainer
var fighter_label: Label
var mode_btn: Button
var news_popup: Control

func _ready() -> void:
	var title := UIKit.label("NOBLE STARS", 40, UIKit.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	# Top-left: player name + trophy count (tap trophies for Trophy Road).
	var top_left := HBoxContainer.new()
	top_left.add_theme_constant_override("separation", 12)
	top_left.position = Vector2(24, 16)
	add_child(top_left)
	name_pill = UIKit.pill(SaveGame.player_name, UIKit.FAINT)
	top_left.add_child(name_pill)
	trophy_btn = Button.new()
	trophy_btn.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "focus"]:
		trophy_btn.add_theme_stylebox_override(state, UIKit.flat(UIKit.NAVY_DEEP, 18, 2, UIKit.GOLD, 8))
	trophy_btn.pressed.connect(func() -> void: menu.show_screen("road"))
	top_left.add_child(trophy_btn)

	# Top-right: coins.
	coin_pill = UIKit.pill("", UIKit.PLAY_YELLOW)
	coin_pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	coin_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(coin_pill)

	# Left column: shop, fighters, news/event banner.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	col.grow_vertical = Control.GROW_DIRECTION_BOTH

	var shop_btn := UIKit.button("SHOP", 26, UIKit.NAVY_PANEL, Vector2(280, 64))
	shop_btn.pressed.connect(func() -> void: menu.show_screen("shop"))
	col.add_child(shop_btn)

	var fighters_btn := UIKit.button("FIGHTERS", 26, UIKit.NAVY_PANEL, Vector2(280, 64))
	fighters_btn.pressed.connect(func() -> void: menu.show_screen("fighters"))
	col.add_child(fighters_btn)

	var news_btn := Button.new()
	news_btn.custom_minimum_size = Vector2(280, 92)
	UIKit.style_button(news_btn, Color(0.22, 0.16, 0.32))
	var news_box := VBoxContainer.new()
	news_box.set_anchors_preset(Control.PRESET_CENTER)
	news_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	news_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	news_box.alignment = BoxContainer.ALIGNMENT_CENTER
	news_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var news_head := UIKit.label("SEASON 1 — SHOWDOWN", 20, UIKit.GOLD)
	news_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	news_box.add_child(news_head)
	var news_sub := UIKit.label("New fighters incoming", 15, UIKit.MUTED)
	news_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	news_box.add_child(news_sub)
	news_btn.add_child(news_box)
	news_btn.pressed.connect(func() -> void: news_popup.visible = true)
	col.add_child(news_btn)

	# Bottom-left: settings.
	var settings_btn := UIKit.button("SETTINGS", 20, UIKit.NAVY_PANEL)
	settings_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	settings_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	settings_btn.pressed.connect(func() -> void: menu.show_screen("settings"))
	add_child(settings_btn)

	# Bottom-center: selected fighter's name, under the 3D stage.
	fighter_label = UIKit.label("", 26, Color.WHITE)
	fighter_label.anchor_left = 0.5
	fighter_label.anchor_right = 0.5
	fighter_label.anchor_top = 1.0
	fighter_label.anchor_bottom = 1.0
	fighter_label.offset_left = -180
	fighter_label.offset_right = 180
	fighter_label.offset_top = -158
	fighter_label.offset_bottom = -118
	fighter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fighter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(fighter_label)

	# Bottom-right: mode selector + PLAY.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var friends_btn := UIKit.button("WIFI\nMATCH", 20, Color(0.30, 0.20, 0.48), Vector2(150, 96))
	friends_btn.pressed.connect(func() -> void: menu.show_screen("friends"))
	row.add_child(friends_btn)

	mode_btn = UIKit.button("", 22, Color(0.16, 0.38, 0.23), Vector2(200, 96))
	mode_btn.pressed.connect(func() -> void: menu.show_screen("modes"))
	row.add_child(mode_btn)

	var play := UIKit.button("PLAY", 42, UIKit.PLAY_YELLOW, Vector2(260, 96))
	for state_color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		play.add_theme_color_override(state_color, UIKit.NAVY)
	play.pressed.connect(func() -> void:
		Session.kit = Kits.named(SaveGame.selected_kit)
		Session.mode = SaveGame.selected_mode
		get_tree().change_scene_to_file("res://game.tscn"))
	row.add_child(play)

	_build_news_popup()
	refresh()

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
	UIKit.set_pill_text(name_pill, SaveGame.player_name)
	trophy_btn.text = "★ %d" % SaveGame.total_trophies()
	UIKit.set_pill_text(coin_pill, "$ %d" % SaveGame.coins)
	fighter_label.text = SaveGame.selected_kit.to_upper()
	mode_btn.text = SaveGame.selected_mode.to_upper().replace("_", " ")
