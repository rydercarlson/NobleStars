class_name PassScreen
extends MenuScreen
## Nobles Pass — web-menu/src/screens/pass.js. Season header with the token
## bar, then the free / premium reward track. Unlike the web build there is no
## "collect tokens" button: playing a match earns the tokens (SaveGame.award_match).

const TIER_WIDTH := 200.0

var _track: ScrollContainer

func _build() -> void:
	screen_name = "pass"
	var season: Dictionary = MenuData.season()
	topbar("Nobles Pass", "Season %d" % int(season.get("number", 1)))
	var column: VBoxContainer = fill_content(18)
	column.add_child(_header(season))

	var lane := MenuUI.hbox(16)
	lane.add_child(MenuUI.display("FREE ↑", 26, MenuUI.TEXT_DIM, 4))
	lane.add_child(MenuUI.spacer())
	lane.add_child(MenuUI.display("PASS ↓", 26, MenuUI.TEXT_DIM, 4))
	column.add_child(lane)

	_track = ScrollContainer.new()
	_track.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_track.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_track)
	var row := MenuUI.hbox(14)
	_track.add_child(row)
	for tier in MenuData.game.get("passRewards", []):
		row.add_child(_tier_column(tier))
	_scroll_to_current()

func _header(season: Dictionary) -> PanelContainer:
	# Owning the Pass recolours the whole plate gold — the season banner is the
	# one place that should look different once you have paid for it.
	var plate: PanelContainer = MenuUI.panel(
			"yellow" if SaveGame.pass_premium else "navy", 16, 7, 24)
	var row := MenuUI.hbox(26)
	plate.add_child(row)
	# On the gold plate every label needs dark ink, not just the title.
	var head_ink: Color = MenuUI.GOLD_INK if SaveGame.pass_premium else MenuUI.TEXT
	var sub_ink: Color = Color(0.23, 0.14, 0.0, 0.85) if SaveGame.pass_premium \
			else MenuUI.TEXT_DIM
	# The season's hero art if it shipped, else the school shield.
	var hero_path := "res://assets/menu/decor/pass_hero.webp"
	if ResourceLoader.exists(hero_path):
		var hero := TextureRect.new()
		hero.texture = load(hero_path)
		hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hero.custom_minimum_size = Vector2(132, 132)
		hero.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hero)
		# a slow float so the hero is not dead weight on the plate
		var bob := hero.create_tween().set_loops()
		bob.tween_property(hero, "position:y", -7.0, 1.7) \
				.as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(hero, "position:y", 7.0, 1.7) \
				.as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		row.add_child(MenuUI.icon("shield", 96))
	var lines := MenuUI.vbox(6)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lines)
	lines.add_child(MenuUI.display("SEASON %d: %s" % [int(season.get("number", 1)),
			str(season.get("name", ""))], 44, head_ink, 6))
	lines.add_child(MenuUI.body("%d days left · %s" % [int(season.get("endsInDays", 30)),
			"Nobles Pass active" if SaveGame.pass_premium else "Free track"],
			22, sub_ink))

	var tokens := MenuUI.vbox(6)
	tokens.custom_minimum_size = Vector2(320, 0)
	tokens.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tokens)
	var per_tier: int = maxi(1, int(season.get("tokensPerTier", 500)))
	var label_row := MenuUI.hbox(8)
	label_row.add_child(MenuUI.body("Tokens to next tier", 19, sub_ink))
	label_row.add_child(MenuUI.spacer())
	label_row.add_child(MenuUI.display("%d / %d" % [SaveGame.pass_tokens, per_tier],
			20, sub_ink, 0))
	tokens.add_child(label_row)
	var token_bar: Panel = MenuUI.bar(26, Color("#1fb8e6"), Color("#9ff4ff"))
	tokens.add_child(token_bar)
	MenuUI.set_bar(token_bar, float(SaveGame.pass_tokens) / float(per_tier))

	var tier := MenuUI.vbox(2)
	tier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tier_key: Label = MenuUI.body("TIER", 18, sub_ink)
	tier_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier.add_child(tier_key)
	var tier_value: Label = MenuUI.display(str(SaveGame.pass_tier), 60,
			MenuUI.GOLD_INK if SaveGame.pass_premium else MenuUI.YELLOW_HI)
	tier_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier.add_child(tier_value)
	row.add_child(tier)

	if SaveGame.pass_premium:
		row.add_child(MenuUI.disabled_button("PASS ACTIVE"))
	else:
		var unlock: Button = MenuUI.button("169 · UNLOCK", "yellow")
		unlock.icon = MenuUI.icon_texture("gem")
		unlock.expand_icon = true
		unlock.add_theme_constant_override("icon_max_width", 38)
		unlock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unlock.pressed.connect(func() -> void: _unlock_premium(unlock))
		row.add_child(unlock)
		_sheen(unlock, 3.4)
	return plate

func _unlock_premium(button: Button) -> void:
	var ok: bool = await menu.confirm("Nobles Pass",
			"Unlock the premium reward lane for this season for 169 gems?",
			"UNLOCK · 169")
	if not ok:
		return
	if SaveGame.gems < 169:
		sfx("error")
		toast("Not enough gems", "gem")
		return
	SaveGame.gems -= 169
	SaveGame.pass_premium = true
	SaveGame.save()
	menu.refresh_currencies()
	sfx("reward")
	menu.burst(center_of(button), "treat_legendary", 18)
	toast("Nobles Pass unlocked!", "shield")
	_reopen()

func _tier_column(tier: Dictionary) -> VBoxContainer:
	var number: int = int(tier.tier)
	var column := MenuUI.vbox(12)
	column.custom_minimum_size = Vector2(TIER_WIDTH, 0)
	# The headers double as the progress track: expanding each one by half the
	# 14px column gap makes them touch, so the row reads as one continuous line
	# that is lit up to the current tier and dark beyond it.
	var current: bool = number == SaveGame.pass_tier
	var reached: bool = number < SaveGame.pass_tier
	var header := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MenuUI.YELLOW if current else \
			(Color("#e07b1a") if reached else Color(0, 0, 0, 0.35))
	style.set_corner_radius_all(10)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.expand_margin_left = 7
	style.expand_margin_right = 7
	if current:
		style.set_border_width_all(3)
		style.border_color = MenuUI.YELLOW_HI
	header.add_theme_stylebox_override("panel", style)
	var ink: Color = MenuUI.GOLD_INK if current \
			else (MenuUI.TEXT if reached else MenuUI.TEXT_DIM)
	var header_row := MenuUI.hbox(6)
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(header_row)
	if reached:
		var tick: TextureRect = MenuUI.icon("check", 22)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header_row.add_child(tick)
	header_row.add_child(MenuUI.display("TIER %d" % number, 26, ink, 0))
	column.add_child(header)
	if current:
		# gentle breathing pulse so the eye lands on where you are
		header.pivot_offset = Vector2(TIER_WIDTH * 0.5, 22)
		var beat := header.create_tween().set_loops()
		beat.tween_property(header, "scale", Vector2(1.06, 1.12), 0.55) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		beat.tween_property(header, "scale", Vector2.ONE, 0.55) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	column.add_child(_reward_cell(tier, "free"))
	column.add_child(_reward_cell(tier, "premium"))
	if number == SaveGame.pass_tier:
		column.set_meta("current", true)
	return column

func _reward_cell(tier: Dictionary, lane: String) -> Control:
	var reward: Dictionary = tier.get(lane, {})
	var id: String = "pass:%d:%s" % [int(tier.tier), lane]
	var claimed: bool = SaveGame.is_claimed(id)
	var lane_locked: bool = lane == "premium" and not SaveGame.pass_premium
	var reachable: bool = int(tier.tier) <= SaveGame.pass_tier
	var claimable: bool = reachable and not claimed and not lane_locked

	var cell := Button.new()
	cell.custom_minimum_size = Vector2(0, 190)
	cell.clip_contents = true
	var variant: String = "card"
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		cell.add_theme_stylebox_override(state, MenuUI.plate_box(variant, 16, 6, 0))
	MenuUI.press_feedback(cell)
	if lane == "premium":
		var tint := ColorRect.new()
		tint.color = Color("#4a3d9c")
		tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tint.offset_bottom = -6
		tint.color.a = 0.55
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(tint)

	var column := MenuUI.vbox(6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_bottom = -6
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(column)
	var art := CenterContainer.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Skins and brawlers are the headline rewards — give them a soft halo so
	# they read as bigger prizes than a stack of coins.
	var kind: String = str(reward.get("kind", ""))
	if kind == "skin" or kind == "brawler":
		var halo := Panel.new()
		var halo_style := StyleBoxFlat.new()
		halo_style.bg_color = Color(MenuUI.YELLOW_HI.r, MenuUI.YELLOW_HI.g, MenuUI.YELLOW_HI.b, 0.16)
		halo_style.set_corner_radius_all(60)
		halo.add_theme_stylebox_override("panel", halo_style)
		halo.custom_minimum_size = Vector2(112, 112)
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(halo)
	art.add_child(MenuUI.icon(_reward_icon(reward), 84))
	column.add_child(art)
	if reward.has("amount"):
		var amount: Label = MenuUI.display("x%d" % int(reward.amount), 30)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(amount)
	var name_label: Label = MenuUI.wrap(MenuUI.body(_reward_name(reward), 18, MenuUI.TEXT_DIM))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	if lane == "premium":
		var tag := PanelContainer.new()
		var tag_style := StyleBoxFlat.new()
		tag_style.bg_color = MenuUI.YELLOW
		tag_style.set_corner_radius_all(6)
		tag_style.content_margin_left = 8
		tag_style.content_margin_right = 8
		tag_style.content_margin_top = 1
		tag_style.content_margin_bottom = 1
		tag.add_theme_stylebox_override("panel", tag_style)
		tag.add_child(MenuUI.display("PASS", 15, MenuUI.GOLD_INK, 0))
		MenuUI.pin(tag, false, false, 8)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(tag)
	# Owning the Pass should show on the premium lane itself, not just the header.
	if lane == "premium" and SaveGame.pass_premium and not claimed:
		var trim := Panel.new()
		var trim_style := StyleBoxFlat.new()
		trim_style.bg_color = Color(0, 0, 0, 0)
		trim_style.set_border_width_all(3)
		trim_style.border_color = Color(MenuUI.YELLOW.r, MenuUI.YELLOW.g, MenuUI.YELLOW.b, 0.75)
		trim_style.set_corner_radius_all(16)
		trim.add_theme_stylebox_override("panel", trim_style)
		trim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		trim.offset_bottom = -6
		trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(trim)

	if claimed or not reachable or lane_locked:
		var veil := ColorRect.new()
		veil.color = Color(0, 0, 0, 0.35 if claimed else 0.45)
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		veil.offset_bottom = -6
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(veil)
		var mark: TextureRect = MenuUI.icon("check" if claimed else "lock", 70)
		mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
		mark.grow_vertical = Control.GROW_DIRECTION_BOTH
		cell.add_child(mark)
	if claimable:
		var glow := Panel.new()
		var glow_style := StyleBoxFlat.new()
		glow_style.bg_color = Color(0, 0, 0, 0)
		glow_style.set_border_width_all(4)
		glow_style.border_color = MenuUI.GREEN
		glow_style.set_corner_radius_all(16)
		glow.add_theme_stylebox_override("panel", glow_style)
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.offset_bottom = -6
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(glow)
		var pulse := glow.create_tween().set_loops()
		pulse.tween_property(glow, "modulate:a", 0.35, 0.6)
		pulse.tween_property(glow, "modulate:a", 1.0, 0.6)
		_sheen(cell)
		cell.pressed.connect(func() -> void: _claim(id, reward, cell))
	elif lane_locked and reachable and not claimed:
		cell.pressed.connect(func() -> void:
			sfx("error")
			toast("Unlock the Nobles Pass to claim", "lock"))
	else:
		cell.disabled = true
	return cell

func _claim(id: String, reward: Dictionary, cell: Control) -> void:
	SaveGame.claim(id)
	var kind: String = str(reward.get("kind", "coins"))
	if kind == "coins" or kind == "gems":
		SaveGame.grant(kind, int(reward.get("amount", 0)))
		menu.refresh_currencies()
	SaveGame.save()
	sfx("reward")
	# Punch the card, then throw the reward at the counter it lands in, so the
	# claim reads as the card handing something over rather than just vanishing.
	var at: Vector2 = center_of(cell)
	cell.pivot_offset = cell.size * 0.5
	var punch := cell.create_tween()
	punch.tween_property(cell, "scale", Vector2(1.12, 1.12), 0.09) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(cell, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	menu.burst(at, _reward_icon(reward), 20)
	if kind == "coins" or kind == "gems":
		menu.fly_to(at, kind, 9)
	toast("Claimed %s" % _reward_name(reward), _reward_icon(reward))
	# A Dawg Treat reward hands over a treat to open, not a silent nothing —
	# before this, claiming one granted no currency and opened no container.
	if kind == "dawg_treat" or kind == "star_drop":
		for i in int(reward.get("amount", 1)):
			get_tree().create_timer(0.4 + i * 0.1).timeout.connect(func() -> void:
				ShopScreen.open_dawg_treat(menu))
	# _reopen rebuilds the track, which would cut the punch off mid-flight
	await get_tree().create_timer(0.3).timeout
	_reopen()

## A slow diagonal highlight sweeping across a claimable card, so the eye is
## drawn to what can actually be taken. The cell clips, so it stays inside.
func _sheen(cell: Control, gap: float = 1.9) -> void:
	var shine := TextureRect.new()
	shine.texture = MenuUI.fade_texture()
	shine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shine.stretch_mode = TextureRect.STRETCH_SCALE
	shine.modulate = Color(1, 1, 1, 0.13)
	shine.rotation_degrees = 18.0
	shine.custom_minimum_size = Vector2(70, 300)
	shine.size = Vector2(70, 300)
	shine.position = Vector2(-90, -60)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(shine)
	var sweep := shine.create_tween().set_loops()
	sweep.tween_property(shine, "position:x", TIER_WIDTH + 40.0, 1.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sweep.tween_interval(gap)
	sweep.tween_callback(func() -> void: shine.position.x = -90)

func _reward_icon(reward: Dictionary) -> String:
	match str(reward.get("kind", "")):
		"coins":
			return "coin"
		"gems":
			return "gem"
		"power_points":
			return "power_point"
		"star_drop":
			return "star_drop"
		"skin":
			return "brawlers"
		"dawg_treat":
			return "dawg_treat"
		"bling":
			return "bling"
		"brawler":
			return "brawlers"
		"pin":
			return "rank_badge"
	return "token"

func _reward_name(reward: Dictionary) -> String:
	if reward.has("name"):
		return str(reward.name)
	match str(reward.get("kind", "")):
		"coins":
			return "Coins"
		"gems":
			return "Gems"
		"power_points":
			return "Power Points"
		"star_drop":
			return "Dawg Treat"
		"dawg_treat":
			return "Dawg Treat"
		"bling":
			return "Bling"
		"brawler":
			return "Brawler"
		"pin":
			return "Pin"
	return str(reward.get("kind", "")).replace("_", " ").capitalize()

func _scroll_to_current() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_track):
		return
	var index: int = maxi(0, SaveGame.pass_tier - 1)
	_track.scroll_horizontal = int(maxf(0.0, index * (TIER_WIDTH + 14.0) - 60.0))

## Rebuilds the screen in place after a claim so every cell restates itself.
func _reopen() -> void:
	var fresh := PassScreen.new()
	menu.push_screen(fresh)
	close_screen()
