extends Control
## Title screen + character select, mirroring the 2D game's menu.

var selected := 0
var cards: Array[Button] = []

func _ready() -> void:
	# Debug: NS3_MENU_SHOT=/path.png screenshots the menu and quits.
	if OS.get_environment("NS3_MENU_SHOT") != "":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("NS3_MENU_SHOT"))
			get_tree().quit())
	# Debug hooks jump straight into a match.
	elif OS.get_environment("NS3_KIT") != "" or OS.get_environment("NS3_AUTOFIRE") != "":
		Session.kit = Kits.named(OS.get_environment("NS3_KIT"))
		get_tree().change_scene_to_file.call_deferred("res://game.tscn")
		return

	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.16, 0.24)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 26)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	var title := Label.new()
	title.text = "NOBLE STARS"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "SHOWDOWN — last star standing"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	for i in Kits.all().size():
		var kit: Dictionary = Kits.all()[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(220, 150)
		card.text = "%s" % kit.name
		card.add_theme_font_size_override("font_size", 28)
		card.pressed.connect(func() -> void:
			selected = i
			_restyle())
		row.add_child(card)
		cards.append(card)

	var play := Button.new()
	play.text = "  PLAY  "
	play.add_theme_font_size_override("font_size", 34)
	play.pressed.connect(func() -> void:
		Session.kit = Kits.all()[selected]
		get_tree().change_scene_to_file("res://game.tscn"))
	vbox.add_child(play)
	_restyle()

func _restyle() -> void:
	for i in cards.size():
		var kit: Dictionary = Kits.all()[i]
		var style := StyleBoxFlat.new()
		style.bg_color = kit.color.darkened(0.55) if i != selected else kit.color.darkened(0.25)
		style.set_corner_radius_all(14)
		style.set_border_width_all(4 if i == selected else 1)
		style.border_color = Color(1.0, 0.85, 0.25) if i == selected else Color(1, 1, 1, 0.25)
		style.set_content_margin_all(12)
		for state in ["normal", "hover", "pressed", "focus"]:
			cards[i].add_theme_stylebox_override(state, style)
