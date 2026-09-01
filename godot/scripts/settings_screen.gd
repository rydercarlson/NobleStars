class_name SettingsScreen
extends Control
## Settings: volume sliders (stored in the save; applied to the master bus),
## controls reference, and a two-tap save reset.

var menu: MenuShell
var reset_btn: Button
var reset_armed := false

func _ready() -> void:
	var back := UIKit.back_button()
	back.pressed.connect(func() -> void: menu.show_screen("lobby"))
	add_child(back)

	var title := UIKit.label("SETTINGS", 40, UIKit.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(520, 0)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH

	box.add_child(_slider_row("MUSIC", SaveGame.music_volume, func(v: float) -> void:
		SaveGame.music_volume = v))
	box.add_child(_slider_row("SOUND FX", SaveGame.sfx_volume, func(v: float) -> void:
		SaveGame.sfx_volume = v
		# No dedicated buses yet — SFX drives the master bus until audio lands.
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))))

	var controls := UIKit.panel()
	box.add_child(controls)
	var controls_label := UIKit.label(
		"CONTROLS\n\nTouch:  left stick moves, right stick aims —\nrelease to fire, tap to auto-aim. Star button fires your Super.\n\nDesktop:  WASD moves, Space auto-aims, E fires your Super.",
		16, UIKit.MUTED)
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(controls_label)

	reset_btn = UIKit.button("RESET SAVE", 18, Color(0.45, 0.15, 0.15))
	reset_btn.pressed.connect(_on_reset_pressed)
	box.add_child(reset_btn)

func _slider_row(text: String, initial: float, apply: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UIKit.label(text, 20, Color.WHITE)
	l.custom_minimum_size = Vector2(140, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.custom_minimum_size = Vector2(320, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(apply)
	slider.drag_ended.connect(func(_changed: bool) -> void: SaveGame.save())
	row.add_child(slider)
	return row

func _on_reset_pressed() -> void:
	if not reset_armed:
		reset_armed = true
		reset_btn.text = "TAP AGAIN TO WIPE PROGRESS"
		return
	reset_armed = false
	reset_btn.text = "RESET SAVE"
	SaveGame.coins = 0
	for kit in Kits.all():
		SaveGame.trophies[kit.name] = 0
	SaveGame.selected_kit = "Nova"
	SaveGame.selected_mode = "showdown"
	SaveGame.save()

func refresh() -> void:
	reset_armed = false
	reset_btn.text = "RESET SAVE"
