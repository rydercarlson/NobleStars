class_name TrophyRoadScreen
extends MenuScreen
## Permanent account progression. Total trophies make milestones reachable;
## rewards are claimed once and stored in SaveGame.claimed as road:<trophies>.

const MILESTONE_WIDTH := 230.0

var _track: ScrollContainer

func _build() -> void:
	screen_name = "trophy-road"
	var total: int = SaveGame.total_trophies()
	topbar("Trophy Road", "%s trophies" % MenuUI.fmt(total))
	var column: VBoxContainer = fill_content(18)
	column.add_child(_summary(total))

	_track = ScrollContainer.new()
	_track.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_track.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_track)

	var road_holder := VBoxContainer.new()
	road_holder.add_theme_constant_override("separation", 0)
	_track.add_child(road_holder)
	road_holder.add_child(_rail())
	var row := MenuUI.hbox(16)
	road_holder.add_child(row)
	for reward in MenuData.trophy_road():
		row.add_child(_milestone(reward, total))
	stagger_children(row, 0.035)
	_scroll_to_progress(total)

func _summary(total: int) -> PanelContainer:
	var road: Array = MenuData.trophy_road()
	var last_goal: int = int(road[-1].get("trophies", 1)) if not road.is_empty() else 1
	var next_goal: int = last_goal
	for reward in road:
		var goal: int = int(reward.get("trophies", 0))
		if goal > total:
			next_goal = goal
			break

	var plate: PanelContainer = MenuUI.panel("navy", 16, 7, 22)
	var row := MenuUI.hbox(24)
	plate.add_child(row)
	row.add_child(MenuUI.icon("trophy", 78))
	var text := MenuUI.vbox(4)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	text.add_child(MenuUI.display("YOUR TROPHY ROAD", 34, MenuUI.TEXT, 5))
	text.add_child(MenuUI.body("Win trophies with every brawler to unlock permanent rewards.",
			21, MenuUI.TEXT_DIM))
	var progress := MenuUI.vbox(6)
	progress.custom_minimum_size = Vector2(520, 0)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(progress)
	var labels := MenuUI.hbox(8)
	labels.add_child(MenuUI.body("NEXT MILESTONE", 19, MenuUI.TEXT_DIM))
	labels.add_child(MenuUI.spacer())
	labels.add_child(MenuUI.display("%s / %s" % [MenuUI.fmt(total), MenuUI.fmt(next_goal)],
			24, MenuUI.YELLOW_HI, 0))
	progress.add_child(labels)
	var bar: Panel = MenuUI.bar(28, MenuUI.YELLOW, MenuUI.YELLOW_HI)
	progress.add_child(bar)
	MenuUI.set_bar(bar, float(total) / maxf(1.0, float(next_goal)))
	return plate

## Gold line behind the milestone cards, with a trophy at its beginning.
func _rail() -> Control:
	var road: Array = MenuData.trophy_road()
	var rail := Control.new()
	rail.custom_minimum_size = Vector2(maxf(0.0,
			road.size() * (MILESTONE_WIDTH + 16.0) - 16.0), 60)
	var line := ColorRect.new()
	line.color = MenuUI.YELLOW_LO
	line.position = Vector2(34, 27)
	line.size = Vector2(maxf(0.0, rail.custom_minimum_size.x - 68.0), 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(line)
	return rail

## A milestone's payload. Entries are `{trophies, reward: {kind, ...}}`; the
## older flat `{trophies, kind, ...}` shape is still accepted so a save or a
## hand-edited game.json from before the split keeps working.
static func _payload(entry: Dictionary) -> Dictionary:
	var nested: Variant = entry.get("reward")
	return nested if nested is Dictionary else entry

func _milestone(entry: Dictionary, total: int) -> VBoxContainer:
	var goal: int = int(entry.get("trophies", 0))
	var reward: Dictionary = _payload(entry)
	var claim_id := "road:%d" % goal
	var reached: bool = total >= goal
	var claimed: bool = SaveGame.is_claimed(claim_id)

	var column := MenuUI.vbox(10)
	column.custom_minimum_size = Vector2(MILESTONE_WIDTH, 0)
	var threshold := PanelContainer.new()
	threshold.add_theme_stylebox_override("panel",
			MenuUI.plate_box("yellow" if reached else "grey", 12, 5, 10))
	var threshold_row := MenuUI.hbox(6)
	threshold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	threshold.add_child(threshold_row)
	threshold_row.add_child(MenuUI.icon("trophy", 34))
	threshold_row.add_child(MenuUI.display(MenuUI.fmt(goal), 30,
			MenuUI.GOLD_INK if reached else MenuUI.TEXT, 2))
	column.add_child(threshold)

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(MILESTONE_WIDTH, 300)
	cell.add_theme_stylebox_override("panel", MenuUI.plate_box("card", 16, 7, 14))
	column.add_child(cell)
	var contents := MenuUI.vbox(8)
	contents.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(contents)

	var art := CenterContainer.new()
	art.custom_minimum_size = Vector2(0, 130)
	art.add_child(_reward_art(reward))
	contents.add_child(art)
	var name: Label = MenuUI.wrap(MenuUI.display(_reward_name(reward), 28,
			MenuUI.TEXT if reached else MenuUI.TEXT_DIM, 3))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Reserve two lines so a wrapping name ("50 POWER POINTS") does not make its
	# card taller than its neighbours and leave the row ragged.
	name.custom_minimum_size = Vector2(0, 74)
	name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	contents.add_child(name)
	contents.add_child(MenuUI.spacer())

	if claimed:
		var done: Button = MenuUI.disabled_button("CLAIMED")
		done.custom_minimum_size = Vector2(0, 62)
		contents.add_child(done)
	elif reached:
		var claim: Button = MenuUI.button("CLAIM", "green", 28, Vector2(0, 62))
		claim.pressed.connect(func() -> void: _claim(claim_id, reward, claim))
		contents.add_child(claim)
	else:
		var locked: Button = MenuUI.disabled_button("LOCKED")
		locked.icon = MenuUI.icon_texture("lock")
		locked.expand_icon = true
		locked.add_theme_constant_override("icon_max_width", 28)
		locked.custom_minimum_size = Vector2(0, 62)
		contents.add_child(locked)
		cell.modulate = Color(0.68, 0.68, 0.75)
	return column

func _reward_art(reward: Dictionary) -> Control:
	var kind: String = str(reward.get("kind", "coins"))
	if kind == "brawler":
		var id: String = str(reward.get("id", ""))
		var portrait_texture: Texture2D = MenuData.portrait(id)
		if portrait_texture != null:
			var portrait := TextureRect.new()
			portrait.texture = portrait_texture
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size = Vector2(145, 145)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return portrait
		var b: Dictionary = MenuData.brawler(id)
		var initial: Label = MenuUI.display(str(b.get("name", "?")).substr(0, 1),
				100, b.get("color", MenuUI.TEXT), 6)
		initial.custom_minimum_size = Vector2(130, 130)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return initial
	return MenuUI.icon(_reward_icon(reward), 108)

func _reward_icon(reward: Dictionary) -> String:
	match str(reward.get("kind", "")):
		"coins":
			return "coin"
		"gems":
			return "gem"
		"star_drop":
			return "star_drop"
		"brawler":
			return "brawlers"
		"brawler_drop":
			return "brawlers"
		"power_points":
			return "power_point"
		"dawg_treat":
			return "dawg_treat"
		"bling":
			return "bling"
	return "trophy"

func _reward_name(reward: Dictionary) -> String:
	var kind: String = str(reward.get("kind", ""))
	if kind == "brawler":
		return str(MenuData.brawler(str(reward.get("id", ""))).get("name", "Brawler"))
	if kind == "brawler_drop":
		return "BRAWLER DROP"
	var amount: int = int(reward.get("amount", 1))
	match kind:
		"coins":
			return "%s COINS" % MenuUI.fmt(amount)
		"gems":
			return "%s GEMS" % MenuUI.fmt(amount)
		"star_drop":
			return "%s STAR DROP%s" % [MenuUI.fmt(amount), "S" if amount != 1 else ""]
		"power_points":
			return "%s POWER POINTS" % MenuUI.fmt(amount)
		"bling":
			return "%s BLING" % MenuUI.fmt(amount)
		"dawg_treat":
			return "%s DAWG TREAT%s" % [MenuUI.fmt(amount), "S" if amount != 1 else ""]
	return str(reward.get("name", kind)).replace("_", " ").to_upper()

func _claim(claim_id: String, reward: Dictionary, button: Control) -> void:
	if SaveGame.is_claimed(claim_id):
		return
	SaveGame.claim(claim_id)
	var kind: String = str(reward.get("kind", "coins"))
	var amount: int = int(reward.get("amount", 1))
	var unlocked_brawler: Dictionary = {}
	var unlock_title := "Brawler Drop"
	if kind in ["coins", "gems", "power_points", "bling", "dawg_treat"]:
		SaveGame.grant(kind, amount)
		menu.refresh_currencies()
	elif kind == "brawler":
		var unlock_id: String = str(reward.get("id", ""))
		SaveGame.unlock(unlock_id)
		SaveGame.save()
		# A named road unlock earns the same reveal a random drop gets.
		unlocked_brawler = MenuData.brawler(unlock_id)
		unlock_title = "Brawler Unlocked"
	elif kind == "brawler_drop":
		unlocked_brawler = _unlock_random_brawler()
		SaveGame.save()
		if not unlocked_brawler.is_empty():
			reward = reward.duplicate()
			reward["name"] = "UNLOCKED %s" % str(unlocked_brawler.get("name", "BRAWLER"))
		else:
			reward = reward.duplicate()
			reward["name"] = "500 COINS"
			menu.refresh_currencies()
	SaveGame.save()
	sfx("reward")
	menu.burst(center_of(button), _reward_icon(reward), 14)
	toast(str(reward.get("name", "Claimed %s" % _reward_name(reward))),
			_reward_icon(reward))
	var drops: int = amount if kind == "star_drop" else 0
	_reopen()
	if not unlocked_brawler.is_empty():
		_show_brawler_unlock(unlocked_brawler, unlock_title)
	for i in drops:
		get_tree().create_timer(0.35 + i * 0.12).timeout.connect(func() -> void:
			ShopScreen.open_star_drop(menu))

## Guaranteed random unlock. Common rarities are more likely to arrive early,
## and removing owned brawlers from the pool prevents duplicate drops.
func _unlock_random_brawler() -> Dictionary:
	var candidates: Array = []
	var total_weight := 0.0
	for b in MenuData.brawlers:
		var id: String = str(b.get("id", ""))
		if SaveGame.is_unlocked(id):
			continue
		var weight: float = _rarity_weight(str(b.get("rarity", "rare")))
		candidates.append({"brawler": b, "weight": weight})
		total_weight += weight
	if candidates.is_empty():
		# A legacy/debug save may already own everyone; keep the milestone useful.
		SaveGame.coins += 500
		return {}
	var roll: float = randf() * total_weight
	var pick: Dictionary = candidates[-1].brawler
	for entry in candidates:
		roll -= float(entry.weight)
		if roll <= 0.0:
			pick = entry.brawler
			break
	SaveGame.unlock(str(pick.get("id", "")))
	return pick

func _show_brawler_unlock(brawler: Dictionary, title: String = "Brawler Drop") -> void:
	var popup: MenuPopup = menu.popup(title, 720)
	var column := MenuUI.vbox(10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	popup.body_box.add_child(column)
	var kicker: Label = MenuUI.display("NEW BRAWLER!", 34, MenuUI.YELLOW_HI, 5)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kicker)
	var art := CenterContainer.new()
	art.custom_minimum_size = Vector2(0, 250)
	art.add_child(_reward_art({"kind": "brawler", "id": str(brawler.get("id", ""))}))
	column.add_child(art)
	var name: Label = MenuUI.display(str(brawler.get("name", "BRAWLER")), 58,
			brawler.get("color", MenuUI.TEXT), 8)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name)
	var rarity: Dictionary = MenuData.rarity_of(brawler)
	var rarity_label: Label = MenuUI.body(str(rarity.get("label", "Rare")).to_upper(),
			22, MenuUI.hex(rarity.get("color"), MenuUI.TEXT_DIM))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(rarity_label)
	var awesome: Button = MenuUI.button("AWESOME", "yellow", 34,
			Vector2(300, 76))
	awesome.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	awesome.pressed.connect(popup.close_screen)
	column.add_child(awesome)
	menu.burst(menu.stage.size * 0.5, "star_drop", 20)

func _rarity_weight(rarity: String) -> float:
	match rarity:
		"starting":
			return 10.0
		"rare":
			return 8.0
		"super_rare":
			return 5.0
		"epic":
			return 3.0
		"mythic":
			return 2.0
		"legendary":
			return 1.0
	return 6.0

func _scroll_to_progress(total: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_track):
		return
	var index: int = 0
	var road: Array = MenuData.trophy_road()
	for i in road.size():
		if int(road[i].get("trophies", 0)) <= total:
			index = i
		else:
			break
	_track.scroll_horizontal = int(maxf(0.0,
			index * (MILESTONE_WIDTH + 16.0) - 90.0))

func _reopen() -> void:
	var fresh := TrophyRoadScreen.new()
	menu.push_screen(fresh)
	close_screen()
