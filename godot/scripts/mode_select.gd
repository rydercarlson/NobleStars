class_name ModeSelect
extends Control
## Event/game-mode selection: Showdown is playable, the rest are teasers.

const MODES: Array = [
	{"id": "showdown", "name": "SHOWDOWN", "desc": "10 fighters.\nLast star standing.",
	 "color": Color(0.16, 0.42, 0.24), "locked": false},
	{"id": "gem_grab", "name": "GEM GRAB", "desc": "Collect 10 gems\nand hold them.",
	 "color": Color(0.36, 0.20, 0.52), "locked": true},
	{"id": "brawl_ball", "name": "BRAWL BALL", "desc": "Score two goals\nto win.",
	 "color": Color(0.15, 0.30, 0.55), "locked": true},
	{"id": "heist", "name": "HEIST", "desc": "Crack the\nenemy safe.",
	 "color": Color(0.52, 0.18, 0.18), "locked": true},
]

var menu: MenuShell
var cards: Array[Button] = []

func _ready() -> void:
	var back := UIKit.back_button()
	back.pressed.connect(func() -> void: menu.show_screen("lobby"))
	add_child(back)

	var title := UIKit.label("EVENTS", 40, UIKit.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH

	for i in MODES.size():
		var mode: Dictionary = MODES[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(250, 320)
		card.add_theme_font_size_override("font_size", 22)
		if mode.locked:
			card.text = "%s\n\n%s\n\n\nLOCKED\nCOMING SOON" % [mode.name, mode.desc]
			card.disabled = true
		else:
			card.text = "%s\n\n%s" % [mode.name, mode.desc]
			card.pressed.connect(func() -> void:
				SaveGame.selected_mode = mode.id
				SaveGame.save()
				menu.show_screen("lobby"))
		row.add_child(card)
		cards.append(card)

func refresh() -> void:
	for i in cards.size():
		var mode: Dictionary = MODES[i]
		var selected: bool = not mode.locked and SaveGame.selected_mode == str(mode.id)
		var bg: Color = mode.color
		if mode.locked:
			bg = bg.darkened(0.55)
			for state_color in ["font_color", "font_disabled_color"]:
				cards[i].add_theme_color_override(state_color, UIKit.MUTED)
		UIKit.style_button(cards[i], bg, selected)
		cards[i].add_theme_stylebox_override("disabled", UIKit.flat(bg, 14, 1, UIKit.FAINT))
