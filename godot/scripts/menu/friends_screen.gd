class_name FriendsScreen
extends MenuScreen
## Friends — the roster from data/game.json, plus the one thing the web build
## could never offer: WIFI MATCH, which opens the LAN room (room_screen.gd) so
## two phones on the same network can actually play together.

func _build() -> void:
	screen_name = "friends"
	var friends: Array = MenuData.game.get("friends", [])
	var online: int = 0
	for f in friends:
		if str(f.status) == "online":
			online += 1
	topbar("Friends", "%d online" % online)
	var column: VBoxContainer = scroll_content(14)

	var sorted: Array = friends.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _order(str(a.status)) < _order(str(b.status)))
	var list := MenuUI.vbox(14)
	column.add_child(list)
	for f in sorted:
		list.add_child(_row(f))
	stagger_children(list, 0.05)

	var actions := MenuUI.hbox(16)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	var wifi: Button = MenuUI.button("WIFI MATCH", "green")
	wifi.pressed.connect(func() -> void:
		sfx("open")
		menu.show_screen("wifi"))
	actions.add_child(wifi)
	var add: Button = MenuUI.button("ADD FRIEND", "blue")
	add.pressed.connect(_add_friend)
	actions.add_child(add)

func _order(status: String) -> int:
	match status:
		"online":
			return 0
		"away":
			return 1
	return 2

func _row(f: Dictionary) -> PanelContainer:
	var status: String = str(f.status)
	var plate: PanelContainer = MenuUI.panel("navy", 16, 6, 16)
	var row := MenuUI.hbox(18)
	plate.add_child(row)
	row.add_child(_avatar(MenuData.portrait(str(f.get("brawler", ""))), status))
	var who := MenuUI.vbox(4)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(MenuUI.display(str(f.name), 30, MenuUI.TEXT, 4))
	who.add_child(MenuUI.body(str(f.activity), 20,
			MenuUI.GREEN if status == "online" else MenuUI.TEXT_DIM))
	row.add_child(who)
	var trophies := MenuUI.hbox(8)
	trophies.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trophies.add_child(MenuUI.icon("trophy", 32))
	trophies.add_child(MenuUI.display(MenuUI.fmt(int(f.trophies)), 30, MenuUI.YELLOW_HI, 4))
	row.add_child(trophies)
	if status == "online":
		var invite: Button = MenuUI.small_button("INVITE", "green")
		invite.pressed.connect(func() -> void:
			sfx("open")
			toast("Invite sent to %s" % str(f.name), "friends"))
		row.add_child(invite)
	else:
		var profile: Button = MenuUI.small_button("PROFILE", "grey")
		profile.pressed.connect(func() -> void:
			toast("%s is %s" % [str(f.name), status]))
		row.add_child(profile)
	return plate

## Portrait tile with the online/away/offline dot on its corner.
func _avatar(texture: Texture2D, status: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(78, 78)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MenuUI.INK
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = MenuUI.LINE
	frame.add_theme_stylebox_override("panel", style)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.clip_contents = true
	holder.add_child(frame)
	if texture:
		var art := TextureRect.new()
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.offset_top = 6
		frame.add_child(art)
	var dot := Panel.new()
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = MenuUI.GREEN if status == "online" else \
			(MenuUI.YELLOW if status == "away" else Color("#5a6280"))
	dot_style.set_corner_radius_all(13)
	dot_style.set_border_width_all(3)
	dot_style.border_color = MenuUI.LINE
	dot.add_theme_stylebox_override("panel", dot_style)
	dot.custom_minimum_size = Vector2(26, 26)
	MenuUI.pin(dot, true, true, -6)
	holder.add_child(dot)
	return holder

func _add_friend() -> void:
	var popup: MenuPopup = menu.popup("Add Friend")
	var input := LineEdit.new()
	input.placeholder_text = "Enter a player tag, e.g. #NOBLES"
	input.add_theme_font_override("font", MenuUI.body_font())
	input.add_theme_font_size_override("font_size", 26)
	input.custom_minimum_size = Vector2(0, 66)
	popup.body_box.add_child(input)
	var send: Button = MenuUI.button("SEND REQUEST", "green")
	send.pressed.connect(func() -> void:
		if input.text.strip_edges().is_empty():
			sfx("error")
			return
		toast("Friend request sent to %s" % input.text.strip_edges(), "check")
		popup.close_screen())
	popup.body_box.add_child(send)
	input.grab_focus()
