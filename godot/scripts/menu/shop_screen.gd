class_name ShopScreen
extends MenuScreen
## Shop — web-menu/src/screens/shop.js: special offers, daily deals (free
## claims and coin/gem buys with flying currency), gem packs, and the Star Drop
## opening with its rarity roll. Every item comes from data/game.json.

const KIND_ICON := {
	"coins": "coin", "gems": "gem", "power_points": "power_point",
	"star_drop": "treat_legendary", "gadget": "gadget", "skin": "star_drop",
	"pin": "rank_badge", "bundle": "treat_epic",
	"dawg_treat": "dawg_treat", "bling": "bling", "brawler": "brawlers",
}
const KIND_LABEL := {
	"coins": "Coins", "gems": "Gems", "power_points": "Power Points",
	"star_drop": "Dawg Treat", "gadget": "Gadget", "skin": "Skin", "pin": "Pin",
	"dawg_treat": "Dawg Treat", "bling": "Bling", "brawler": "Brawler",
}

func _build() -> void:
	screen_name = "shop"
	topbar("Shop")
	var column: VBoxContainer = scroll_content(30)
	var shop: Dictionary = MenuData.game.get("shop", {})

	column.add_child(_heading("Special Offers"))
	var offers: GridContainer = MenuUI.grid(3)
	column.add_child(offers)
	for o in shop.get("offers", []):
		offers.add_child(_offer_card(o))
	stagger_children(offers, 0.06)

	column.add_child(_heading("Daily Deals", "Resets in %s" % _reset_time()))
	var daily: GridContainer = MenuUI.grid(6)
	column.add_child(daily)
	for item in shop.get("daily", []):
		daily.add_child(_daily_card(item))
	stagger_children(daily)

	var skins_data: Array = shop.get("skins", [])
	if not skins_data.is_empty():
		column.add_child(_heading("Skins"))
		var skins: GridContainer = MenuUI.grid(5)
		column.add_child(skins)
		for skin in skins_data:
			skins.add_child(_skin_card(skin))
		stagger_children(skins)

	var resources_data: Array = shop.get("resources", [])
	if not resources_data.is_empty():
		column.add_child(_heading("Resources"))
		var resources: GridContainer = MenuUI.grid(6)
		column.add_child(resources)
		for item in resources_data:
			resources.add_child(_resource_card(item))
		stagger_children(resources)

	column.add_child(_heading("Gems"))
	var gems: GridContainer = MenuUI.grid(4)
	column.add_child(gems)
	for pack in shop.get("gems", []):
		gems.add_child(_gem_card(pack))
	stagger_children(gems)

func _heading(text: String, note: String = "") -> HBoxContainer:
	var row := MenuUI.hbox(16)
	row.add_child(MenuUI.display(text, 40, MenuUI.TEXT, 6))
	if note != "":
		var n: Label = MenuUI.body(note, 22, MenuUI.TEXT_DIM)
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(n)
	return row

func _card(height: float) -> Panel:
	var card: Panel = MenuUI.card()
	card.custom_minimum_size = Vector2(0, height)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card

# MARK: offers

func _offer_card(o: Dictionary) -> Panel:
	var card: Panel = _card(330)
	var accent: Color = MenuUI.hex(o.get("accent"), MenuUI.YELLOW)
	var tint := TextureRect.new()
	tint.texture = MenuUI.fade_texture()
	tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tint.stretch_mode = TextureRect.STRETCH_SCALE
	tint.modulate = Color(accent.r, accent.g, accent.b, 0.42)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.offset_bottom = -7
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tint)

	var row := MenuUI.hbox(22)
	MenuUI.card_body(card, 22).add_child(row)
	var left := MenuUI.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(MenuUI.wrap(MenuUI.display(str(o.name), 32, MenuUI.TEXT, 6)))
	for line in o.get("contents", []):
		left.add_child(MenuUI.body("✓  %s" % str(line), 22, MenuUI.TEXT_SOFT))
	left.add_child(MenuUI.spacer())
	var buy_row := MenuUI.hbox(0)
	buy_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	left.add_child(buy_row)
	var on_buy := func(button: Button) -> void:
		_buy(o, button, func() -> void:
			if str(o.get("kind", "")) == "bundle":
				SaveGame.coins += 2000
				SaveGame.star_points += 100)
	var buy_button: Button = _price_button(o, on_buy)
	buy_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	buy_row.add_child(buy_button)
	var art: TextureRect = MenuUI.icon("star_drop", 160)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)

	if str(o.get("badge", "")) != "":
		var badge := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = MenuUI.RED
		style.set_corner_radius_all(10)
		style.set_border_width_all(3)
		style.border_color = MenuUI.LINE
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		badge.add_theme_stylebox_override("panel", style)
		badge.add_child(MenuUI.display(str(o.badge), 22, MenuUI.TEXT, 4))
		MenuUI.pin(badge, true, false, 12)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)
	return card

# MARK: daily deals

func _daily_card(item: Dictionary) -> Panel:
	var card: Panel = _card(320)
	var column := MenuUI.vbox(6)
	MenuUI.card_body(card, 16).add_child(column)
	var kind: String = str(item.get("kind", "coins"))
	var brawler_id: String = str(item.get("brawler", ""))
	var is_portrait: bool = kind == "skin" or kind == "gadget"

	var art_holder := CenterContainer.new()
	art_holder.custom_minimum_size = Vector2(0, 120)
	column.add_child(art_holder)
	if is_portrait and brawler_id != "":
		var portrait := TextureRect.new()
		portrait.texture = MenuData.portrait(brawler_id)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(120, 120)
		art_holder.add_child(portrait)
	else:
		art_holder.add_child(MenuUI.icon(str(KIND_ICON.get(kind, "token")), 116))

	var amount_text: String = MenuUI.fmt(int(item.amount)) if item.has("amount") \
			else str(item.get("name", ""))
	var amount: Label = MenuUI.wrap(MenuUI.display(amount_text, 36, MenuUI.TEXT, 6))
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(amount)
	var what: String = str(KIND_LABEL.get(kind, kind)).to_upper()
	if brawler_id != "":
		what = "%s · %s" % [str(MenuData.brawler(brawler_id).name), what]
	var what_label: Label = MenuUI.body(what, 20, MenuUI.TEXT_DIM)
	what_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(what_label)
	column.add_child(MenuUI.spacer())
	column.add_child(_price_button(item, func(button: Button) -> void:
		_buy(item, button, func() -> void: _apply_item(item))))
	return card

# MARK: skins

## Skin card: the brawler's portrait over the skin's accent, priced in Bling.
func _skin_card(skin: Dictionary) -> Panel:
	var card: Panel = _card(330)
	var accent: Color = MenuUI.hex(skin.get("accent"), MenuUI.YELLOW)
	var tint := TextureRect.new()
	tint.texture = MenuUI.fade_texture()
	tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tint.stretch_mode = TextureRect.STRETCH_SCALE
	tint.modulate = Color(accent.r, accent.g, accent.b, 0.38)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.offset_bottom = -7
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tint)

	var column := MenuUI.vbox(6)
	MenuUI.card_body(card, 16).add_child(column)
	var brawler_id: String = str(skin.get("brawler", ""))
	var art_holder := CenterContainer.new()
	art_holder.custom_minimum_size = Vector2(0, 132)
	column.add_child(art_holder)
	var art := TextureRect.new()
	art.texture = MenuData.portrait(brawler_id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(132, 132)
	art_holder.add_child(art)

	var name_label: Label = MenuUI.wrap(MenuUI.display(str(skin.get("name", "")), 26, MenuUI.TEXT, 5))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	# rarity_of() keys off the dict's own "rarity" field, so the skin entry works
	var rarity: Dictionary = MenuData.rarity_of(skin)
	var rarity_label: Label = MenuUI.body(str(rarity.get("label", "")).to_upper(), 19,
			MenuUI.hex(rarity.get("color"), MenuUI.TEXT_DIM))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(rarity_label)
	column.add_child(MenuUI.spacer())
	column.add_child(_price_button(skin, func(button: Button) -> void:
		_buy(skin, button, func() -> void: _apply_item(skin))))
	return card

# MARK: resources

## Resource card: a stack of coins, power points or treats bought with gems.
func _resource_card(item: Dictionary) -> Panel:
	var card: Panel = _card(300)
	var column := MenuUI.vbox(6)
	MenuUI.card_body(card, 16).add_child(column)
	var kind: String = str(item.get("kind", "coins"))
	var art := CenterContainer.new()
	art.custom_minimum_size = Vector2(0, 112)
	column.add_child(art)
	art.add_child(MenuUI.icon(str(KIND_ICON.get(kind, "token")), 108))

	var amount: Label = MenuUI.display(MenuUI.fmt(int(item.get("amount", 1))), 34, MenuUI.TEXT, 6)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(amount)
	var what: String = str(item.get("label", KIND_LABEL.get(kind, kind))).to_upper()
	var what_label: Label = MenuUI.wrap(MenuUI.body(what, 19, MenuUI.TEXT_DIM))
	what_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(what_label)
	if str(item.get("value", "")) != "":
		var bonus: Label = MenuUI.display(str(item.value), 20, MenuUI.GREEN, 4)
		bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(bonus)
	column.add_child(MenuUI.spacer())
	column.add_child(_price_button(item, func(button: Button) -> void:
		_buy(item, button, func() -> void: _apply_item(item))))
	return card

func _gem_card(pack: Dictionary) -> Panel:
	var card: Panel = _card(240)
	var column := MenuUI.vbox(8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	MenuUI.card_body(card, 16).add_child(column)
	var art := CenterContainer.new()
	art.add_child(MenuUI.icon("gem", 96))
	column.add_child(art)
	var amount: Label = MenuUI.display(MenuUI.fmt(int(pack.amount)), 44, MenuUI.TEXT, 6)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(amount)
	var buy: Button = MenuUI.button(str(pack.price), "green")
	buy.pressed.connect(func() -> void: _buy_gems(pack, buy))
	column.add_child(buy)
	return card

func _buy_gems(pack: Dictionary, button: Button) -> void:
	var amount: int = int(pack.amount)
	var ok: bool = await menu.confirm("Get Gems",
			"This is a demo build — no real purchases. Add %d gems to your account?" % amount,
			"ADD GEMS", "green")
	if not ok:
		return
	SaveGame.gems += amount
	SaveGame.save()
	sfx("purchase")
	menu.fly_to(center_of(button), "gems", 10)
	toast("+%d gems" % amount, "gem")

# MARK: buying

func _price_button(item: Dictionary, on_buy: Callable) -> Button:
	if SaveGame.is_claimed(str(item.id)):
		var done: Button = MenuUI.disabled_button(str(item.get("claimedLabel", "PURCHASED")))
		done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return done
	var currency: String = str(item.get("currency", "coins"))
	var free: bool = currency == "free"
	var variant: String = "green" if free else ("blue" if currency == "gems" else "yellow")
	# Bling is the skin currency; it has its own icon rather than the coin.
	const CURRENCY_ICON := {"gems": "gem", "bling": "bling", "coins": "coin"}
	var label: String = str(item.get("label", "FREE")) if free \
			else MenuUI.fmt(int(item.get("price", 0)))
	var button: Button = MenuUI.button(label, variant, 30)
	if not free:
		button.icon = MenuUI.icon_texture(str(CURRENCY_ICON.get(currency, "coin")))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 34)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: on_buy.call(button))
	return button

func _buy(item: Dictionary, button: Button, apply: Callable) -> void:
	var currency: String = str(item.get("currency", "coins"))
	var price: int = int(item.get("price", 0))
	if not SaveGame.can_afford(currency, price):
		sfx("error")
		toast("Not enough %s" % currency, "gem" if currency == "gems" else "coin")
		var shake := button.create_tween()
		shake.tween_property(button, "position:x", button.position.x - 8, 0.06)
		shake.tween_property(button, "position:x", button.position.x + 8, 0.06)
		shake.tween_property(button, "position:x", button.position.x, 0.06)
		return
	SaveGame.spend(currency, price)
	SaveGame.claim(str(item.id))
	apply.call()
	SaveGame.save()
	menu.refresh_currencies()
	var kind: String = str(item.get("kind", "coins"))
	sfx("reward" if (kind == "star_drop" or kind == "dawg_treat") else "purchase")
	var at: Vector2 = center_of(button)
	if kind == "coins":
		menu.fly_to(at, "coins", 10)
	else:
		menu.burst(at - Vector2(0, 60), str(KIND_ICON.get(kind, "star_drop")), 12)
	var done: Button = MenuUI.disabled_button(str(item.get("claimedLabel", "PURCHASED")))
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_sibling(done)
	button.queue_free()
	if kind == "star_drop" or kind == "dawg_treat":
		open_dawg_treat(menu)

func _apply_item(item: Dictionary) -> void:
	if str(item.get("kind", "")) == "coins":
		SaveGame.coins += int(item.get("amount", 0))

func _reset_time() -> String:
	var now: Dictionary = Time.get_time_dict_from_system()
	var seconds: int = 86400 - (int(now.hour) * 3600 + int(now.minute) * 60 + int(now.second))
	return "%dh %dm" % [seconds / 3600, (seconds % 3600) / 60]

# MARK: star drop

## Dawg Treats — our Starr Drop. A Starr Drop rolls a rarity first and then
## pulls a reward from that rarity's pool, so the colour you see tells you how
## good the prize can be before you open it; that is the mechanic reproduced
## here, across the seven treat rarities we have art for. Probabilities are
## shaped like Brawl Stars': the common tiers carry the draw, Legendary and
## Ultra are the rare thrill.
const TREAT_TIERS := [
	{"id": "common", "label": "COMMON", "color": "#cfcfcf", "p": 0.40},
	{"id": "rare", "label": "RARE", "color": "#6df26a", "p": 0.26},
	{"id": "super_rare", "label": "SUPER RARE", "color": "#4f8dff", "p": 0.16},
	{"id": "epic", "label": "EPIC", "color": "#c56cff", "p": 0.10},
	{"id": "mythic", "label": "MYTHIC", "color": "#ff5f5f", "p": 0.055},
	{"id": "legendary", "label": "LEGENDARY", "color": "#ffe14f", "p": 0.02},
	{"id": "ultra", "label": "ULTRA", "color": "#ff8ae0", "p": 0.005},
]

## What each rarity can hold. Entries are weighted so a tier can still surprise
## inside itself, and the value climbs steeply with rarity.
const TREAT_POOL := {
	"common": [{"kind": "coins", "amount": 120, "w": 3}, {"kind": "power_points", "amount": 25, "w": 2}],
	"rare": [{"kind": "coins", "amount": 260, "w": 3}, {"kind": "power_points", "amount": 60, "w": 2},
			{"kind": "bling", "amount": 20, "w": 1}],
	"super_rare": [{"kind": "coins", "amount": 520, "w": 3}, {"kind": "power_points", "amount": 130, "w": 2},
			{"kind": "bling", "amount": 45, "w": 2}, {"kind": "gems", "amount": 10, "w": 1}],
	"epic": [{"kind": "power_points", "amount": 280, "w": 2}, {"kind": "bling", "amount": 110, "w": 2},
			{"kind": "gems", "amount": 25, "w": 2}, {"kind": "pin", "w": 1}],
	"mythic": [{"kind": "gems", "amount": 55, "w": 2}, {"kind": "bling", "amount": 260, "w": 2},
			{"kind": "brawler", "w": 3}],
	"legendary": [{"kind": "brawler", "w": 4}, {"kind": "gems", "amount": 120, "w": 2},
			{"kind": "skin", "w": 2}],
	"ultra": [{"kind": "brawler", "w": 3}, {"kind": "skin", "w": 3}, {"kind": "gems", "amount": 220, "w": 2}],
}

static func _roll_tier() -> Dictionary:
	var roll: float = randf()
	for tier in TREAT_TIERS:
		if roll < float(tier.p):
			return tier
		roll -= float(tier.p)
	return TREAT_TIERS[0]

## Pick a reward from a tier's pool, then resolve it against what the player
## already owns — a brawler pull with nothing left to unlock becomes gems
## rather than a dud, the way Starr Drops substitute duplicates out.
static func _roll_reward(tier_id: String) -> Dictionary:
	var pool: Array = TREAT_POOL.get(tier_id, TREAT_POOL["common"])
	var total: float = 0.0
	for entry in pool:
		total += float(entry.get("w", 1))
	var pick: float = randf() * total
	var chosen: Dictionary = pool[0]
	for entry in pool:
		pick -= float(entry.get("w", 1))
		if pick <= 0.0:
			chosen = entry
			break
	var reward: Dictionary = chosen.duplicate()
	if str(reward.get("kind", "")) == "brawler":
		var locked: Array = []
		for b in MenuData.brawlers:
			if not SaveGame.is_unlocked(str(b.id)):
				locked.append(str(b.id))
		if locked.is_empty():
			return {"kind": "gems", "amount": 80}
		reward["id"] = locked[randi() % locked.size()]
	return reward

static func treat_icon(tier_id: String) -> String:
	return "treat_%s" % tier_id

## The opening: the treat drops in at its rarity colour, you tap, it reveals.
static func open_dawg_treat(shell: MenuShell) -> void:
	var tier: Dictionary = _roll_tier()
	var reward: Dictionary = _roll_reward(str(tier.id))
	var accent: Color = MenuUI.hex(tier.color)

	var popup: MenuPopup = shell.popup("Dawg Treat")
	var box := MenuUI.vbox(18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	popup.body_box.add_child(box)
	var treat_holder := CenterContainer.new()
	treat_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var treat: TextureRect = MenuUI.icon(treat_icon(str(tier.id)), 210)
	treat_holder.add_child(treat)
	box.add_child(treat_holder)
	var label: Label = MenuUI.display("TAP TO OPEN", 54, accent, 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var bob := treat.create_tween().set_loops()
	bob.tween_property(treat, "position:y", -12.0, 0.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(treat, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)

	var opened: Array = [false]
	var open := func(event: InputEvent) -> void:
		if opened[0] or not (event is InputEventMouseButton and event.pressed):
			return
		opened[0] = true
		shell.sfx("reward")
		bob.kill()
		# the treat pops before it hands the prize over
		treat.pivot_offset = treat.size * 0.5
		var pop := treat.create_tween()
		pop.tween_property(treat, "scale", Vector2(1.3, 1.3), 0.12) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(treat, "modulate:a", 0.0, 0.14)
		pop.tween_callback(treat.queue_free)
		shell.burst(shell.stage.size * 0.5, treat_icon(str(tier.id)), 22)
		label.text = str(tier.label)
		var slot := CenterContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(slot)
		box.move_child(slot, 0)
		var kind: String = str(reward.get("kind", "coins"))
		if kind == "brawler":
			var b: Dictionary = MenuData.brawler(str(reward.id))
			SaveGame.unlock(str(reward.id))
			SaveGame.save()
			var column := MenuUI.vbox(10)
			var portrait := TextureRect.new()
			portrait.texture = MenuData.portrait(str(reward.id))
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size = Vector2(220, 220)
			column.add_child(portrait)
			var caption: Label = MenuUI.display("NEW BRAWLER: %s" % str(b.name), 40)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(caption)
			slot.add_child(column)
		elif kind == "skin" or kind == "pin":
			var column2 := MenuUI.vbox(10)
			column2.add_child(MenuUI.icon("brawlers" if kind == "skin" else "rank_badge", 170))
			var caption2: Label = MenuUI.display(
					"NEW SKIN" if kind == "skin" else "NEW PIN", 40, accent, 6)
			caption2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column2.add_child(caption2)
			slot.add_child(column2)
		else:
			SaveGame.grant(kind, int(reward.get("amount", 0)))
			shell.refresh_currencies()
			var row := MenuUI.hbox(16)
			row.add_child(MenuUI.icon(str(KIND_ICON.get(kind, "coin")), 90))
			row.add_child(MenuUI.display("+%s" % MenuUI.fmt(int(reward.get("amount", 0))), 70))
			slot.add_child(row)
		var awesome: Button = MenuUI.button("AWESOME", "yellow")
		awesome.pressed.connect(popup.close_screen)
		box.add_child(awesome)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(open)

## Kept so older call sites keep working; Dawg Treats are the only container.
static func open_star_drop(shell: MenuShell) -> void:
	open_dawg_treat(shell)
