class_name FighterSelect
extends Control
## "Fighters" screen: card grid, plus a detail view with stat bars and the
## shared 3D stage showing the inspected fighter.

var menu: MenuShell

var grid_view: Control
var detail_view: Control
var cards: Array[Button] = []

var detail_index: int = -1
var detail_name: Label
var detail_role: Label
var detail_trophies: Label
var detail_desc: Label
var detail_super: Label
var select_btn: Button
var stat_fills: Array[ColorRect] = []
var stat_values: Array[Label] = []

const STAT_BAR_W := 240.0

func _ready() -> void:
	_build_grid_view()
	_build_detail_view()

func _build_grid_view() -> void:
	grid_view = Control.new()
	grid_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grid_view)

	var back := UIKit.back_button()
	back.pressed.connect(func() -> void: menu.show_screen("lobby"))
	grid_view.add_child(back)

	var title := UIKit.label("FIGHTERS", 40, UIKit.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	grid_view.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 100
	scroll.offset_bottom = -30
	scroll.offset_left = 60
	scroll.offset_right = -60
	grid_view.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	scroll.add_child(grid)

	for i in Kits.all().size():
		var kit: Dictionary = Kits.all()[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(220, 170)
		card.add_theme_font_size_override("font_size", 26)
		card.pressed.connect(func() -> void: _open_detail(i))
		grid.add_child(card)
		cards.append(card)

func _build_detail_view() -> void:
	detail_view = Control.new()
	detail_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_view.visible = false
	add_child(detail_view)

	var back := UIKit.back_button()
	back.pressed.connect(func() -> void: _show_grid())
	detail_view.add_child(back)

	# Right half: stats panel (left half is the shared 3D stage).
	var panel := UIKit.panel()
	detail_view.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 50)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(480, 0)
	panel.add_child(box)

	detail_name = UIKit.label("", 36, UIKit.GOLD)
	box.add_child(detail_name)
	detail_role = UIKit.label("", 17, UIKit.MUTED)
	box.add_child(detail_role)
	detail_trophies = UIKit.label("", 20, Color.WHITE)
	box.add_child(detail_trophies)
	box.add_child(HSeparator.new())

	for stat_name in ["HEALTH", "DAMAGE", "RANGE", "SPEED", "RELOAD"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var l := UIKit.label(stat_name, 16, UIKit.MUTED)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		var bar_bg := ColorRect.new()
		bar_bg.color = UIKit.NAVY_DEEP
		bar_bg.custom_minimum_size = Vector2(STAT_BAR_W, 16)
		bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar_bg)
		var fill := ColorRect.new()
		fill.color = UIKit.GOLD
		fill.position = Vector2.ZERO
		fill.size = Vector2(0, 16)
		bar_bg.add_child(fill)
		stat_fills.append(fill)
		var v := UIKit.label("", 16, Color.WHITE)
		row.add_child(v)
		stat_values.append(v)

	box.add_child(HSeparator.new())
	detail_desc = UIKit.label("", 17, Color.WHITE)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_desc)
	detail_super = UIKit.label("", 17, UIKit.GOLD)
	detail_super.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_super)

	select_btn = UIKit.button("SELECT", 28, UIKit.PLAY_YELLOW, Vector2(0, 60))
	for state_color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		select_btn.add_theme_color_override(state_color, UIKit.NAVY)
	select_btn.pressed.connect(func() -> void:
		var kit: Dictionary = Kits.all()[detail_index]
		SaveGame.selected_kit = kit.name
		SaveGame.save()
		menu.show_screen("lobby"))
	box.add_child(select_btn)

func _open_detail(i: int) -> void:
	detail_index = i
	var kit: Dictionary = Kits.all()[i]
	grid_view.visible = false
	detail_view.visible = true
	menu.place_stage_left()
	menu.stage.visible = true
	menu.stage.show_kit(kit)

	detail_name.text = kit.name.to_upper()
	detail_role.text = str(kit.get("role", "FIGHTER")).to_upper()
	detail_trophies.text = "★ %d" % int(SaveGame.trophies.get(kit.name, 0))
	detail_desc.text = str(kit.get("desc", ""))
	detail_super.text = "SUPER: %s" % str(kit.get("super_desc", ""))

	# Normalize each stat bar against the max across all kits.
	var damages: Array[float] = []
	var ranges: Array[float] = []
	var speeds: Array[float] = []
	var healths: Array[float] = []
	var reloads: Array[float] = []
	for k in Kits.all():
		healths.append(float(k.get("max_health", Kits.BASE_MAX_HEALTH)))
		damages.append(float(k.weapon.damage) * float(k.weapon.pellets))
		ranges.append(float(k.weapon.range))
		speeds.append(float(k.get("move_speed", Kits.MOVE_SPEED)))
		reloads.append(float(k.get("reload", Kits.AMMO_RECHARGE_SECONDS)))
	var damage: float = float(kit.weapon.damage) * float(kit.weapon.pellets)
	# Reload is the one stat where lower is better, so the bar fills against the
	# fastest kit rather than the largest value — a full bar always means "best".
	var reload: float = kit.get("reload", Kits.AMMO_RECHARGE_SECONDS)
	var stats: Array = [
		[float(kit.get("max_health", Kits.BASE_MAX_HEALTH)), healths.max(),
			"%d" % int(kit.get("max_health", Kits.BASE_MAX_HEALTH))],
		[damage, damages.max(), "%d" % int(damage)],
		[float(kit.weapon.range), ranges.max(), "%.1f" % kit.weapon.range],
		[float(kit.get("move_speed", Kits.MOVE_SPEED)), speeds.max(), "%.1f" % kit.get("move_speed", Kits.MOVE_SPEED)],
		[reloads.min(), reload, "%.1fs" % reload],
	]
	for s in stats.size():
		var frac: float = float(stats[s][0]) / float(stats[s][1])
		stat_fills[s].size = Vector2(STAT_BAR_W * frac, 16)
		stat_values[s].text = stats[s][2]

func _show_grid() -> void:
	grid_view.visible = true
	detail_view.visible = false
	menu.stage.visible = false
	_restyle_cards()

func refresh() -> void:
	_show_grid()
	# Debug: NS3_MENU_DETAIL=<kit name> (with NS3_MENU_SCREEN=fighters) opens
	# that fighter's detail view for screenshots.
	var detail_env: String = OS.get_environment("NS3_MENU_DETAIL")
	if detail_env != "":
		for i in Kits.all().size():
			if Kits.all()[i].name.to_lower() == detail_env.to_lower():
				_open_detail(i)
				break

func _restyle_cards() -> void:
	for i in cards.size():
		var kit: Dictionary = Kits.all()[i]
		var selected: bool = kit.name == SaveGame.selected_kit
		cards[i].text = "%s\n★ %d" % [kit.name, int(SaveGame.trophies.get(kit.name, 0))]
		var bg: Color = kit.color.darkened(0.25) if selected else kit.color.darkened(0.55)
		UIKit.style_button(cards[i], bg, selected)
