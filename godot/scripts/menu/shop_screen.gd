class_name ShopScreen
extends MenuScreen
## Where what you earn gets spent. Not a store.
##
## The previous version was a storefront: gem bundles priced in dollars, three
## SPECIAL OFFERS with NEW and BEST VALUE flashes, and a row of daily tiles that
## all read PURCHASED. None of it could be bought with anything a match pays
## out, and none of it was ever going to be, because nothing here charges money.
##
## What is left is the loop that was already real. `SaveGame.award_match` grants
## coins for every match played and the Trophy Road grants more; without
## somewhere to spend them, coins are a number that only counts up. So: power
## levels for your fighters, Dawg Treats, and the resource swaps — and the
## Treat's odds are printed, because a box whose contents you cannot reason
## about is the part of a shop this game has no reason to imitate.

func _build() -> void:
	screen_name = "shop"
	topbar("Shop")
	var column: VBoxContainer = scroll_content(0)

	column.add_child(MenuUI.section("POWER UP   ·   %s COINS" % MenuUI.fmt(SaveGame.coins)))
	column.add_child(MenuUI.gap(10, true))
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.id)):
			column.add_child(_power_row(b))
			column.add_child(MenuUI.rule())
	column.add_child(MenuUI.gap(46, true))

	column.add_child(MenuUI.section("DAWG TREATS"))
	column.add_child(MenuUI.gap(10, true))
	column.add_child(_treat_block())
	column.add_child(MenuUI.gap(46, true))

	var deals: Array = _affordable_deals()
	if not deals.is_empty():
		column.add_child(MenuUI.section("DEALS   ·   RESETS IN %s" % _reset_time()))
		column.add_child(MenuUI.gap(10, true))
		for item: Dictionary in deals:
			column.add_child(_deal_row(item))
			column.add_child(MenuUI.rule())
	column.add_child(MenuUI.gap(40, true))

# MARK: power levels

## One row per owned fighter: what level they are and what the next one costs.
## This is the coin sink the deleted detail screen used to own.
func _power_row(b: Dictionary) -> Control:
	var id: String = str(b.id)
	var power: int = SaveGame.brawler_power(id)
	var cost: int = 200 * power
	var row := MenuUI.hbox(0)
	row.custom_minimum_size = Vector2(0, 76)

	var block := ColorRect.new()
	block.color = MenuUI.hex(b.get("color"), MenuUI.BLUE)
	block.custom_minimum_size = Vector2(7, 0)
	row.add_child(block)
	row.add_child(MenuUI.gap(16))
	var name_label: Label = MenuUI.display(str(b.name).to_upper(), 38)
	name_label.custom_minimum_size = Vector2(360, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var level: Label = MenuUI.label("POWER %d" % power, 19, MenuUI.TEXT_DIM)
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(level)
	row.add_child(MenuUI.spacer())
	var price: Label = MenuUI.display(MenuUI.fmt(cost), 32,
			MenuUI.GOLD if SaveGame.coins >= cost else MenuUI.TEXT_FAINT)
	price.custom_minimum_size = Vector2(160, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(price)
	row.add_child(MenuUI.gap(20))
	var buy: Button = MenuUI.button("UPGRADE", "gold" if SaveGame.coins >= cost else "grey",
			22, Vector2(180, 54))
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = SaveGame.coins < cost
	buy.pressed.connect(func() -> void: _upgrade(b, cost, buy))
	row.add_child(buy)
	return row

func _upgrade(b: Dictionary, cost: int, button: Control) -> void:
	var id: String = str(b.id)
	if not SaveGame.spend("coins", cost):
		sfx("error")
		toast("Need %s coins" % MenuUI.fmt(cost))
		return
	SaveGame.set_brawler_power(id, SaveGame.brawler_power(id) + 1)
	SaveGame.save()
	menu.refresh_currencies()
	sfx("purchase")
	menu.burst(center_of(button), "coin", 10)
	toast("%s is now Power %d" % [str(b.name), SaveGame.brawler_power(id)])
	if menu.home:
		menu.home.refresh()
	_reopen()

# MARK: dawg treats

const TREAT_PRICE := 1000

## The treat, its price, and the odds. The odds table is the point: it is the
## same figures `_roll_tier` runs on, printed, so the rarest tier being a real
## 0.5% is something you can read rather than something you have to feel.
func _treat_block() -> Control:
	var row := MenuUI.hbox(60)
	var left := MenuUI.vbox(10)
	left.custom_minimum_size = Vector2(460, 0)
	row.add_child(left)
	left.add_child(MenuUI.display("DAWG TREAT", 52))
	left.add_child(MenuUI.wrap(MenuUI.body(
			"One pull from the table on the right. A fighter you do not own yet "
			+ "can come out of Mythic or better.", 23, MenuUI.TEXT_DIM)))
	left.add_child(MenuUI.gap(8, true))
	var buy: Button = MenuUI.button("OPEN — %s COINS" % MenuUI.fmt(TREAT_PRICE),
			"gold" if SaveGame.coins >= TREAT_PRICE else "grey", 26, Vector2(360, 66))
	buy.disabled = SaveGame.coins < TREAT_PRICE
	buy.pressed.connect(func() -> void:
		if not SaveGame.spend("coins", TREAT_PRICE):
			sfx("error")
			toast("Need %s coins" % MenuUI.fmt(TREAT_PRICE))
			return
		SaveGame.save()
		menu.refresh_currencies()
		open_dawg_treat(menu)
		_reopen())
	left.add_child(buy)

	var odds := MenuUI.vbox(0)
	odds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(odds)
	odds.add_child(MenuUI.label("ODDS", 18, MenuUI.TEXT_FAINT))
	odds.add_child(MenuUI.rule())
	odds.add_child(MenuUI.gap(6, true))
	for tier: Dictionary in TREAT_TIERS:
		var line := MenuUI.hbox(12)
		line.custom_minimum_size = Vector2(0, 38)
		var swatch := ColorRect.new()
		swatch.color = MenuUI.hex(tier.color)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(swatch)
		var name_label: Label = MenuUI.label(str(tier.label), 20, MenuUI.TEXT_SOFT)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name_label)
		line.add_child(MenuUI.spacer())
		var pct: Label = MenuUI.display("%.1f%%" % (float(tier.p) * 100.0), 24)
		pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(pct)
		odds.add_child(line)
	return row

# MARK: deals

## Only what a match can actually pay for. The gem packs priced in dollars and
## the bundles that went with them are gone, so this reads whatever survives
## that filter rather than a hardcoded list.
func _affordable_deals() -> Array:
	var out: Array = []
	var shop: Dictionary = MenuData.game.get("shop", {})
	for group: String in ["daily", "resources"]:
		for item: Dictionary in shop.get(group, []):
			var currency: String = str(item.get("currency", "coins"))
			if currency in ["coins", "gems", "bling", "free"]:
				out.append(item)
	return out

func _deal_row(item: Dictionary) -> Control:
	var kind: String = str(item.get("kind", "coins"))
	var amount: int = int(item.get("amount", 0))
	var currency: String = str(item.get("currency", "coins"))
	var price: int = int(item.get("price", 0))
	var free: bool = currency == "free" or price <= 0
	var bought: bool = SaveGame.is_claimed("shop:%s" % str(item.get("id", "")))

	var row := MenuUI.hbox(0)
	row.custom_minimum_size = Vector2(0, 72)
	var name_label: Label = MenuUI.display(_item_name(kind, amount), 34,
			MenuUI.TEXT if not bought else MenuUI.TEXT_FAINT)
	name_label.custom_minimum_size = Vector2(460, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	if str(item.get("brawler", "")) != "":
		var who: Label = MenuUI.label(
				str(MenuData.brawler(str(item.brawler)).get("name", "")), 19, MenuUI.TEXT_DIM)
		who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(who)
	row.add_child(MenuUI.spacer())
	if bought:
		var done: Label = MenuUI.label("TAKEN", 19, MenuUI.TEXT_FAINT)
		done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(done)
		return row
	var affordable: bool = free or SaveGame.can_afford(currency, price)
	var label_text: String = "FREE" if free else "%s %s" % [MenuUI.fmt(price),
			currency.to_upper()]
	var buy: Button = MenuUI.button(label_text, "gold" if affordable else "grey", 22,
			Vector2(230, 54))
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = not affordable
	buy.pressed.connect(func() -> void: _take(item, free, currency, price, buy))
	row.add_child(buy)
	return row

func _take(item: Dictionary, free: bool, currency: String, price: int,
		button: Control) -> void:
	if not free and not SaveGame.spend(currency, price):
		sfx("error")
		toast("Not enough %s" % currency)
		return
	var kind: String = str(item.get("kind", "coins"))
	var amount: int = int(item.get("amount", 0))
	SaveGame.claim("shop:%s" % str(item.get("id", "")))
	if kind == "dawg_treat" or kind == "star_drop":
		SaveGame.save()
		menu.refresh_currencies()
		sfx("reward")
		open_dawg_treat(menu)
		_reopen()
		return
	SaveGame.grant(kind, amount)
	SaveGame.save()
	menu.refresh_currencies()
	sfx("purchase")
	menu.burst(center_of(button), "coin", 10)
	toast("+%s" % _item_name(kind, amount))
	_reopen()

func _item_name(kind: String, amount: int) -> String:
	match kind:
		"coins":
			return "%s COINS" % MenuUI.fmt(amount)
		"gems":
			return "%s GEMS" % MenuUI.fmt(amount)
		"power_points":
			return "%s POWER POINTS" % MenuUI.fmt(amount)
		"bling":
			return "%s BLING" % MenuUI.fmt(amount)
		"dawg_treat", "star_drop":
			return "%s DAWG TREAT%s" % [MenuUI.fmt(amount), "S" if amount != 1 else ""]
	return kind.replace("_", " ").to_upper()

func _reset_time() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var left: int = (24 - int(now.hour)) * 60 - int(now.minute)
	return "%dH %dM" % [left / 60, left % 60]

func _reopen() -> void:
	menu.push_screen(ShopScreen.new())
	close_screen()

# MARK: the treat itself
#
# A Dawg Treat rolls a rarity first and then pulls a reward from that rarity's
# pool, so the colour you see tells you how good the prize can be before you
# open it. Probabilities carry on the common tiers; Legendary and Ultra are the
# rare thrill. These are the figures the odds table above prints.

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
			{"kind": "gems", "amount": 25, "w": 2}],
	"mythic": [{"kind": "gems", "amount": 55, "w": 2}, {"kind": "bling", "amount": 260, "w": 2},
			{"kind": "brawler", "w": 3}],
	"legendary": [{"kind": "brawler", "w": 4}, {"kind": "gems", "amount": 120, "w": 2}],
	"ultra": [{"kind": "brawler", "w": 3}, {"kind": "gems", "amount": 220, "w": 2}],
}

static func _roll_tier() -> Dictionary:
	var roll: float = randf()
	for tier in TREAT_TIERS:
		if roll < float(tier.p):
			return tier
		roll -= float(tier.p)
	return TREAT_TIERS[0]

## Pick a reward from a tier's pool, then resolve it against what the player
## already owns — a fighter pull with nothing left to unlock becomes gems
## rather than a dud.
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

## The opening. The treat is a solid block of its rarity colour rather than an
## illustration of a box: the rarity IS the information, and printing it as a
## colour and a word says it without shipping seven pieces of art.
static func open_dawg_treat(shell: MenuShell) -> void:
	var tier: Dictionary = _roll_tier()
	var reward: Dictionary = _roll_reward(str(tier.id))
	var accent: Color = MenuUI.hex(tier.color)

	var popup: MenuPopup = shell.popup("Dawg Treat")
	var box := MenuUI.vbox(18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	popup.body_box.add_child(box)
	var slab := ColorRect.new()
	slab.color = accent
	slab.custom_minimum_size = Vector2(0, 180)
	box.add_child(slab)
	var label: Label = MenuUI.display("TAP TO OPEN", 48, accent)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var pulse := slab.create_tween().set_loops()
	pulse.tween_property(slab, "modulate:a", 0.55, 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(slab, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

	var opened: Array = [false]
	var open := func(event: InputEvent) -> void:
		if opened[0] or not (event is InputEventMouseButton and event.pressed):
			return
		opened[0] = true
		shell.sfx("reward")
		pulse.kill()
		slab.modulate.a = 1.0
		label.text = str(tier.label)
		label.add_theme_color_override("font_color", accent)
		var prize := MenuUI.vbox(6)
		prize.alignment = BoxContainer.ALIGNMENT_CENTER
		slab.add_child(prize)
		prize.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var kind: String = str(reward.get("kind", "coins"))
		var headline: String = ""
		var caption: String = ""
		if kind == "brawler":
			var b: Dictionary = MenuData.brawler(str(reward.id))
			SaveGame.unlock(str(reward.id))
			headline = str(b.get("name", "FIGHTER")).to_upper()
			caption = "NEW FIGHTER"
		else:
			var amount: int = int(reward.get("amount", 0))
			SaveGame.grant(kind, amount)
			shell.refresh_currencies()
			headline = "+%s" % MenuUI.fmt(amount)
			caption = str(kind).replace("_", " ").to_upper()
		SaveGame.save()
		var caption_label: Label = MenuUI.label(caption, 20, MenuUI.GOLD_INK)
		caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prize.add_child(caption_label)
		var headline_label: Label = MenuUI.display(headline, 76, MenuUI.INK)
		headline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prize.add_child(headline_label)
		var done: Button = MenuUI.button("DONE", "gold")
		done.pressed.connect(popup.close_screen)
		box.add_child(done)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(open)

## Kept so older call sites keep working; Dawg Treats are the only container.
static func open_star_drop(shell: MenuShell) -> void:
	open_dawg_treat(shell)
