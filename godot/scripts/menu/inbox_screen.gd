class_name InboxScreen
extends MenuScreen
## Inbox — mail from data/game.json with unread badges and claimable rewards.

var _list: VBoxContainer

func _build() -> void:
	screen_name = "inbox"
	topbar("Inbox")
	var column: VBoxContainer = scroll_content(14)
	_list = MenuUI.vbox(14)
	column.add_child(_list)
	_render()

func _render() -> void:
	for child in _list.get_children():
		child.queue_free()
	for mail in MenuData.game.get("inbox", []):
		_list.add_child(_row(mail))
	stagger_children(_list, 0.05)

func _row(mail: Dictionary) -> Button:
	var id: String = str(mail.id)
	var unread: bool = bool(mail.get("unread", false)) and not bool(SaveGame.read_mail.get(id, false))
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 110)
	for state in ["normal", "hover", "pressed", "focus"]:
		row.add_theme_stylebox_override(state, MenuUI.plate_box("navy", 16, 6, 16))
	MenuUI.press_feedback(row)
	row.pressed.connect(func() -> void:
		sfx("open")
		_open(mail))
	var box := MenuUI.hbox(18)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)
	if unread:
		var dot := Panel.new()
		var dot_style := StyleBoxFlat.new()
		dot_style.bg_color = MenuUI.YELLOW
		dot_style.set_corner_radius_all(8)
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.custom_minimum_size = Vector2(16, 16)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(dot)
		# Unread mail is outlined in yellow, not just dotted.
		var outline := Panel.new()
		var outline_style := StyleBoxFlat.new()
		outline_style.bg_color = Color(0, 0, 0, 0)
		outline_style.set_border_width_all(4)
		outline_style.border_color = MenuUI.YELLOW
		outline_style.set_corner_radius_all(16)
		outline.add_theme_stylebox_override("panel", outline_style)
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outline.offset_bottom = -6
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(outline)
	box.add_child(MenuUI.icon("shield", 62))
	var who := MenuUI.vbox(4)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(MenuUI.display(str(mail.title).to_upper(), 30, MenuUI.TEXT, 4))
	who.add_child(MenuUI.body(str(mail.from), 20, MenuUI.TEXT_DIM))
	box.add_child(who)
	if mail.has("reward") and not SaveGame.is_claimed("mail:" + id):
		var reward: Dictionary = mail.reward
		var pill: PanelContainer = MenuUI.dark_panel(14, 0.35, 12)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pill_row := MenuUI.hbox(10)
		pill.add_child(pill_row)
		pill_row.add_child(MenuUI.icon("gem" if str(reward.kind) == "gems" else "coin", 36))
		pill_row.add_child(MenuUI.display(MenuUI.fmt(int(reward.amount)), 30, MenuUI.YELLOW_HI, 4))
		box.add_child(pill)
	var date: Label = MenuUI.body(str(mail.date), 20, MenuUI.TEXT_DIM)
	date.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(date)
	return row

func _open(mail: Dictionary) -> void:
	var id: String = str(mail.id)
	if not bool(SaveGame.read_mail.get(id, false)):
		SaveGame.read_mail[id] = true
		SaveGame.save()
		menu.home.refresh()
	var popup: MenuPopup = menu.popup("Message", 1000)
	popup.body_box.add_child(MenuUI.body("%s · %s" % [str(mail.from), str(mail.date)],
			22, MenuUI.TEXT_DIM))
	popup.body_box.add_child(MenuUI.wrap(MenuUI.display(str(mail.title), 46)))
	popup.body_box.add_child(MenuUI.wrap(MenuUI.body(str(mail.body), 26, MenuUI.TEXT_SOFT)))
	if mail.has("reward"):
		var reward: Dictionary = mail.reward
		var claimed: bool = SaveGame.is_claimed("mail:" + id)
		var row := MenuUI.hbox(14)
		popup.body_box.add_child(row)
		if claimed:
			row.add_child(MenuUI.disabled_button("CLAIMED"))
		else:
			var claim: Button = MenuUI.button("CLAIM %s" % MenuUI.fmt(int(reward.amount)), "green")
			claim.icon = MenuUI.icon_texture("gem" if str(reward.kind) == "gems" else "coin")
			claim.expand_icon = true
			claim.add_theme_constant_override("icon_max_width", 36)
			claim.pressed.connect(func() -> void:
				SaveGame.claim("mail:" + id)
				SaveGame.grant(str(reward.kind), int(reward.amount))
				menu.refresh_currencies()
				sfx("purchase")
				menu.fly_to(center_of(claim), str(reward.kind), 10)
				toast("+%s %s" % [MenuUI.fmt(int(reward.amount)), str(reward.kind)],
						"gem" if str(reward.kind) == "gems" else "coin")
				popup.close_screen()
				_render())
			row.add_child(claim)
	popup.tree_exited.connect(func() -> void:
		if is_inside_tree():
			_render())
