class_name RewardScreen
extends MenuScreen
## What the Nobles Pass and the Trophy Road have in common: a reward, drawn and
## named the same way, in one of three states, and what happens when you take
## it.
##
## The two were one screen until 7 Sep 2026 and are two now — the Road is
## permanent and the Pass ends with the season, so putting them on one page
## made the season's page mostly not about the season. Splitting them without a
## shared base would have meant two copies of `_claim`, which is the function
## that hands out fighters: the place two copies would hurt most.

## Entries are `{trophies, reward: {kind, ...}}`; the older flat
## `{trophies, kind, ...}` shape is still accepted so a hand-edited game.json
## from before the split keeps working.
static func payload(entry: Dictionary) -> Dictionary:
	var nested: Variant = entry.get("reward")
	return nested if nested is Dictionary else entry

# MARK: the card

## The tile both screens are made of: what the reward looks like, what it is
## called, and what you can do about it. Three states, and the edge carries
## which one — green for banked, gold for claimable, hairline for out of reach.
##
## A CLAIMABLE CARD IS THE BUTTON. A gold CLAIM button inside the card was the
## obvious build and does not fit: `MenuUI.button` carries content margin and
## the display face's line box is 1.64x its size, so a small CLAIM cannot be
## short enough, and every claimable column grew taller than its neighbours and
## pushed the rail out of its block. The tile is also the bigger tap target.
func reward_card(reward: Dictionary, claim_id: String, unlocked: bool, claimed: bool,
		width: float, height: float, art: float, name_size: int,
		state_h: float, pad: int, lines: int, locked_text: String = "LOCKED",
		dim: bool = false) -> Control:
	var holder := MarginContainer.new()
	holder.custom_minimum_size = Vector2(width, height)

	var claimable: bool = unlocked and not claimed
	var edge: Color = MenuUI.RULE
	var fill: Color = MenuUI.INK
	if claimed:
		edge = MenuUI.GREEN_LO
		fill = Color("#0e1a12")
	elif claimable:
		edge = MenuUI.GOLD
		fill = MenuUI.PANEL_HI

	var column := MenuUI.vbox(6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture: Control = reward_art(reward, art)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(picture)
	column.add_child(_name_label(reward_name(reward), name_size, lines,
			MenuUI.TEXT if (unlocked or claimed) else MenuUI.TEXT_DIM))
	column.add_child(_state_row(claimable, claimed, name_size, state_h, locked_text))
	# A reward you cannot take because you have not bought the pass is dimmed
	# as a whole, not marked with the same padlock a not-yet-reached tier gets.
	# Those are different situations and they looked identical.
	if dim:
		column.modulate = Color(1, 1, 1, 0.42)

	var card: Control
	if claimable:
		var b := Button.new()
		for state in ["normal", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, MenuUI.flat_box(fill, edge, pad))
		b.add_theme_stylebox_override("hover",
				MenuUI.flat_box(fill.lerp(MenuUI.GOLD, 0.14), MenuUI.GOLD_HI, pad))
		b.add_theme_stylebox_override("pressed",
				MenuUI.flat_box(fill.lerp(MenuUI.INK, 0.3), MenuUI.GOLD, pad))
		MenuUI.press_feedback(b)
		b.pressed.connect(func() -> void: claim(claim_id, reward, b))
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = pad
		column.offset_right = -pad
		column.offset_top = pad
		column.offset_bottom = -pad
		b.add_child(column)
		card = b
	else:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", MenuUI.flat_box(fill, edge, pad))
		p.add_child(column)
		card = p
	holder.add_child(card)
	return holder

func _name_label(text: String, size: int, lines: int, color: Color) -> Label:
	var l: Label = MenuUI.display(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if lines > 1:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.max_lines_visible = lines
	else:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
	return l

## The line at the foot of a card: a green tick, a padlock, or the word that
## says pressing the tile will pay out.
func _state_row(claimable: bool, claimed: bool, size: int, state_h: float,
		locked_text: String) -> Control:
	var row := MenuUI.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(0, state_h)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if claimable:
		var take: Label = MenuUI.display("CLAIM", size + 2, MenuUI.GOLD)
		take.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(take)
		return row
	var glyph: TextureRect = MenuUI.icon("check" if claimed else "lock", size)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	var word: Label = MenuUI.label("CLAIMED" if claimed else locked_text, size - 2,
			MenuUI.GREEN_HI if claimed else MenuUI.TEXT_FAINT)
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(word)
	return row

# MARK: what a reward looks like

## A fighter, a skin or a pin is a picture of that fighter, at whatever size the
## card can give it — the notes called a 26px glyph on a skin "hard to see", and
## they were right: those three kinds are the only rewards where *which one*
## matters, and a hanger glyph answers a question nobody asked.
func reward_art(reward: Dictionary, size: float) -> Control:
	var kind: String = str(reward.get("kind", ""))
	match kind:
		"brawler":
			return portrait_tile(str(reward.get("id", "")), size)
		"skin":
			return portrait_tile(str(reward.get("brawler", "")), size, MenuUI.GOLD)
		"pin":
			return portrait_tile(named_fighter(str(reward.get("name", ""))), size)
		"brawler_drop":
			return MenuUI.pack_icon("shield", size)
	# pack_icon, not icon: coin, gem and trophy exist as painted pack art and
	# that is what the currency readout in every top bar draws. Everything else
	# falls through to the svg of the same name, so this is one call.
	return MenuUI.pack_icon(MenuUI.reward_glyph(kind), size)

## The fighter a "Sanjit Pin" is of. Reward names carry the fighter's name and
## nothing machine-readable, so this matches the roster against the string.
func named_fighter(text: String) -> String:
	var lower: String = text.to_lower()
	for b in MenuData.brawlers:
		var id: String = str(b.get("id", ""))
		if id != "" and lower.contains(id):
			return id
	return ""

## A portrait in a rounded tile of the fighter's own colour. Falls back to the
## roster glyph for a kit with no render yet (Nova).
func portrait_tile(id: String, size: float, edge: Color = Color(0, 0, 0, 0)) -> Control:
	var art: Texture2D = MenuData.portrait(id)
	if art == null:
		return MenuUI.icon("shield", size)
	var tint: Color = MenuUI.hex(MenuData.brawler(id).get("color", MenuUI.BLUE), MenuUI.BLUE)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", MenuUI.flat_box(
			MenuUI.INK.lerp(tint, 0.45), tint if edge.a == 0.0 else edge, 0,
			MenuUI.RADIUS_SMALL))
	tile.custom_minimum_size = Vector2(size, size)
	tile.clip_contents = true
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := TextureRect.new()
	face.texture = art
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.custom_minimum_size = Vector2(size, size)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(face)
	return tile

func reward_name(reward: Dictionary) -> String:
	var kind: String = str(reward.get("kind", ""))
	if kind == "brawler":
		return str(MenuData.brawler(str(reward.get("id", ""))).get("name", "Fighter")).to_upper()
	if kind == "brawler_drop":
		return "RANDOM FIGHTER"
	if kind == "skin":
		return str(reward.get("name", "SKIN")).to_upper()
	var named: String = MenuUI.reward_name(kind, int(reward.get("amount", 1)))
	if named != "":
		return named
	return str(reward.get("name", kind)).replace("_", " ").to_upper()

# MARK: taking one

func claim(claim_id: String, reward: Dictionary, button: Control) -> void:
	if SaveGame.is_claimed(claim_id):
		return
	SaveGame.claim(claim_id)
	var kind: String = str(reward.get("kind", "coins"))
	var amount: int = int(reward.get("amount", 1))
	var unlocked_fighter: Dictionary = {}
	if kind in ["coins", "gems", "power_points", "bling", "dawg_treat"]:
		SaveGame.grant(kind, amount)
		menu.refresh_currencies()
	elif kind == "brawler":
		SaveGame.unlock(str(reward.get("id", "")))
		unlocked_fighter = MenuData.brawler(str(reward.get("id", "")))
	elif kind == "brawler_drop":
		unlocked_fighter = _unlock_random_fighter()
		if unlocked_fighter.is_empty():
			menu.refresh_currencies()
	SaveGame.save()
	sfx("reward")
	menu.burst(center_of(button), "trophy", 12)
	toast("Claimed %s" % reward_name(reward))
	var drops: int = amount if (kind == "star_drop" or kind == "dawg_treat") else 0
	reopen()
	if not unlocked_fighter.is_empty():
		_show_unlock(unlocked_fighter)
	for i in drops:
		get_tree().create_timer(0.35 + i * 0.12).timeout.connect(func() -> void:
			ShopScreen.open_dawg_treat(menu))

## Subclasses rebuild themselves after a claim; the base does not know which.
func reopen() -> void:
	pass

## Guaranteed random unlock. Common rarities are more likely to arrive early,
## and removing owned fighters from the pool prevents duplicate drops.
func _unlock_random_fighter() -> Dictionary:
	var candidates: Array = []
	var total_weight := 0.0
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.get("id", ""))):
			continue
		var weight: float = _rarity_weight(str(b.get("rarity", "rare")))
		candidates.append({"brawler": b, "weight": weight})
		total_weight += weight
	if candidates.is_empty():
		# A legacy or developer save may already own everyone; keep it useful.
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

func _show_unlock(fighter: Dictionary) -> void:
	var popup: MenuPopup = menu.popup("New Fighter", 680)
	var column := MenuUI.vbox(10)
	popup.body_box.add_child(column)
	column.add_child(MenuUI.label("JOINS THE ROSTER", 26, MenuUI.GOLD))
	var name_label: Label = MenuUI.display(str(fighter.get("name", "FIGHTER")).to_upper(), 88)
	column.add_child(name_label)
	column.add_child(MenuUI.label(str(fighter.get("title", "")), 26, MenuUI.TEXT_DIM))
	column.add_child(MenuUI.gap(10, true))
	var play: Button = MenuUI.button("PLAY AS %s" % str(fighter.get("name", "")), "gold",
			30, Vector2(0, 72))
	play.pressed.connect(func() -> void:
		menu.select_brawler(str(fighter.get("id", "")))
		popup.close_screen())
	column.add_child(play)
