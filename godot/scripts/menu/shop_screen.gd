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
##
## *Relaid out 7 Sep 2026, into the same blocks Season is built from.* It was
## three lists: nine near-identical POWER UP rows with an UPGRADE button each,
## filling the screen top to bottom, and the Dawg Treat — the one thing on this
## page with any occasion to it — pushed below the fold underneath them. Now the
## Treat is the first block and the fighters are cards with their own faces on
## them, so the page opens on the thing worth opening and a fighter is
## recognised rather than read.

const BLOCK_GAP := 12.0
const CARD_GAP := 12
const POWER_COLUMNS := 5
const DEAL_COLUMNS := 4
const POWER_CARD_H := 152.0
const DEAL_CARD_H := 210.0
const FACE := 84.0

func _build() -> void:
	screen_name = "shop"
	topbar("Shop")
	var column: VBoxContainer = scroll_content(0)

	# The Treat first. It used to be third, under nine rows of UPGRADE, which
	# put the only thing on this page with an occasion to it below the fold.
	var treats: Array = MenuUI.block("dawg_treat", "DAWG TREATS",
			"ONE PULL, ODDS PRINTED")
	(treats[1] as VBoxContainer).add_child(_treat_block())
	column.add_child(treats[0])
	column.add_child(MenuUI.gap(BLOCK_GAP, true))

	var power: Array = MenuUI.block("power", "POWER UP",
			"%s COINS IN HAND" % MenuUI.fmt(SaveGame.coins))
	var grid: GridContainer = MenuUI.grid(POWER_COLUMNS, CARD_GAP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(power[1] as VBoxContainer).add_child(grid)
	for b in MenuData.brawlers:
		if SaveGame.is_unlocked(str(b.id)):
			grid.add_child(_power_card(b))
	column.add_child(power[0])

	var deals: Array = _affordable_deals()
	if not deals.is_empty():
		column.add_child(MenuUI.gap(BLOCK_GAP, true))
		var block: Array = MenuUI.block("coin", "DEALS",
				"RESETS IN %s" % _reset_time())
		var deal_grid: GridContainer = MenuUI.grid(DEAL_COLUMNS, CARD_GAP)
		deal_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(block[1] as VBoxContainer).add_child(deal_grid)
		for item: Dictionary in deals:
			deal_grid.add_child(_deal_card(item))
		column.add_child(block[0])
	column.add_child(MenuUI.gap(40, true))
# MARK: power levels

## One card per owned fighter: their face, what level they are, and what the
## next one costs. This is the coin sink the deleted detail screen used to own.
##
## The card is NOT the button — the gold chip in it is. Everywhere else in the
## menu a whole tile is pressable, and here it must not be: claiming a Trophy
## Road reward is free and reversible-by-not-mattering, and this spends 200
## coins a tap. A cost is the one thing worth an explicit control.
func _power_card(b: Dictionary) -> Control:
	var id: String = str(b.id)
	var power: int = SaveGame.brawler_power(id)
	var cost: int = 200 * power
	var affordable: bool = SaveGame.coins >= cost
	var color: Color = MenuUI.hex(b.get("color"), MenuUI.BLUE)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.flat_box(MenuUI.INK,
			MenuUI.GOLD if affordable else MenuUI.RULE, 12))
	card.custom_minimum_size = Vector2(0, POWER_CARD_H)
	# A GridContainer only splits its width evenly between columns whose
	# children ask to expand; without this the cards sit at their natural
	# widths and the last row stops halfway across the block.
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := MenuUI.vbox(8)
	card.add_child(column)

	var head := MenuUI.hbox(14)
	column.add_child(head)
	head.add_child(_face(b, color))
	var who := MenuUI.vbox(2)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# EXPAND_FILL or the row hands this column only what "POWER 1" needs, and a
	# name set to clip has a minimum width of zero — KOVACS came out "KOVAC".
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	var name_label: Label = MenuUI.display(str(b.name).to_upper(), 34)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(name_label)
	who.add_child(MenuUI.label("POWER %d" % power, 26, MenuUI.TEXT_DIM))

	var foot := MenuUI.hbox(8)
	column.add_child(foot)
	var coin: TextureRect = MenuUI.icon("coin", 26)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(coin)
	var price: Label = MenuUI.display(MenuUI.fmt(cost), 30,
			MenuUI.GOLD if affordable else MenuUI.TEXT_FAINT)
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(price)
	foot.add_child(MenuUI.spacer())
	var buy: Button = MenuUI.button("UPGRADE", "gold" if affordable else "grey",
			22, Vector2(148, 44), 6)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = not affordable
	buy.pressed.connect(func() -> void: _upgrade(b, cost, buy))
	foot.add_child(buy)
	return card

## The roster tile's face, small: the portrait on a square of the kit's colour,
## or the initial for a fighter with no render yet (Nova, `todo 4.1`).
func _face(b: Dictionary, color: Color) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", MenuUI.flat_box(
			MenuUI.INK.lerp(color, 0.42), color, 0, MenuUI.RADIUS_SMALL))
	tile.custom_minimum_size = Vector2(FACE, FACE)
	tile.clip_contents = true
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art: Texture2D = MenuData.portrait(str(b.id))
	if art == null:
		var initial: Label = MenuUI.display(str(b.get("name", "?")).substr(0, 1).to_upper(),
				48, MenuUI.INK.lerp(MenuUI.TEXT, 0.35))
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_child(initial)
		return tile
	var face := TextureRect.new()
	face.texture = art
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.custom_minimum_size = Vector2(FACE, FACE)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(face)
	return tile

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

## The treat, its price, and the odds. The odds are the point: they are the
## same figures `_roll_tier` runs on, printed, so the rarest tier being a real
## 0.5% is something you can read rather than something you have to feel. They
## used to be a seven-line table with a colour swatch per row; as a row of
## chips they take a third of the height and the colours line up as a scale.
func _treat_block() -> Control:
	var row := MenuUI.hbox(28)
	var left := MenuUI.hbox(18)
	# 540, not 620: seven rarity chips share whatever the copy leaves, and at
	# the 26px utility tier "LEGENDARY" plus its tracking needs ~135px of text
	# inside a chip. At 620 the chips came out 151 wide and broke the word
	# across two lines mid-letter.
	left.custom_minimum_size = Vector2(540, 0)
	row.add_child(left)
	var bone: TextureRect = MenuUI.icon("dawg_treat", 96)
	bone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(bone)
	var copy := MenuUI.vbox(4)
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(copy)
	copy.add_child(MenuUI.display("DAWG TREAT", 44))
	copy.add_child(MenuUI.wrap(MenuUI.body(
			"One pull. A fighter you do not own yet can come out of Mythic or "
			+ "better.", 26, MenuUI.TEXT_DIM)))
	copy.add_child(MenuUI.gap(6, true))
	var affordable: bool = SaveGame.coins >= TREAT_PRICE
	var buy: Button = MenuUI.button("OPEN — %s COINS" % MenuUI.fmt(TREAT_PRICE),
			"gold" if affordable else "grey", 24, Vector2(320, 56), 10)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	buy.disabled = not affordable
	buy.pressed.connect(func() -> void:
		if not SaveGame.spend("coins", TREAT_PRICE):
			sfx("error")
			toast("Need %s coins" % MenuUI.fmt(TREAT_PRICE))
			return
		SaveGame.save()
		menu.refresh_currencies()
		# _reopen() FIRST. It calls push_screen, which hides `_stack[-1]` —
		# and with the popup opened first, `_stack[-1]` IS the popup, so the
		# treat was hidden on the frame it opened and the reward, which is
		# only granted when the slab is tapped, never landed. 1,000 coins for
		# nothing. `season_screen.gd:_claim` has always done it in this order.
		_reopen()
		open_dawg_treat(menu))
	copy.add_child(buy)

	var odds := MenuUI.vbox(8)
	odds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	odds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(odds)
	odds.add_child(MenuUI.label("ODDS", 26, MenuUI.TEXT_FAINT))
	var chips := MenuUI.hbox(8)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	odds.add_child(chips)
	for tier: Dictionary in TREAT_TIERS:
		chips.add_child(_odds_chip(tier))
	return row

## One rarity: a bar of its colour over the chance of drawing it. The bar is
## the swatch and the divider at once.
func _odds_chip(tier: Dictionary) -> Control:
	var accent: Color = MenuUI.hex(tier.color)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
			MenuUI.flat_box(MenuUI.INK, MenuUI.RULE, 8))
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := MenuUI.vbox(6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(column)
	var band := ColorRect.new()
	band.color = accent
	band.custom_minimum_size = Vector2(0, 5)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(band)
	var pct: Label = MenuUI.display("%.1f%%" % (float(tier.p) * 100.0), 28, accent)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(pct)
	var name_label: Label = MenuUI.wrap(MenuUI.label(str(tier.label), 26,
			MenuUI.TEXT_DIM))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	return chip

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

## A deal, as the same tile Season pays out on: the glyph for what it is, what
## you get, and the price as the control. Naming a reward the same way on both
## screens is the whole reason `MenuUI.reward_glyph` exists.
func _deal_card(item: Dictionary) -> Control:
	var kind: String = str(item.get("kind", "coins"))
	var amount: int = int(item.get("amount", 0))
	var currency: String = str(item.get("currency", "coins"))
	var price: int = int(item.get("price", 0))
	var free: bool = currency == "free" or price <= 0
	var bought: bool = SaveGame.is_claimed("shop:%s" % str(item.get("id", "")))
	var affordable: bool = free or SaveGame.can_afford(currency, price)

	var card := PanelContainer.new()
	var edge: Color = MenuUI.RULE
	if bought:
		edge = MenuUI.GREEN_LO
	elif affordable:
		edge = MenuUI.GOLD
	card.add_theme_stylebox_override("panel", MenuUI.flat_box(
			Color("#0e1a12") if bought else MenuUI.INK, edge, 12))
	card.custom_minimum_size = Vector2(0, DEAL_CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := MenuUI.vbox(6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)

	var glyph: TextureRect = MenuUI.icon(MenuUI.reward_glyph(kind), 52)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(glyph)
	var name_label: Label = MenuUI.display(_item_name(kind, amount), 26,
			MenuUI.TEXT_DIM if bought else MenuUI.TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	if str(item.get("brawler", "")) != "":
		var who: Label = MenuUI.label(
				str(MenuData.brawler(str(item.brawler)).get("name", "")), 26,
				MenuUI.TEXT_FAINT)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(who)
	column.add_child(MenuUI.gap(2, true))

	if bought:
		var done := MenuUI.hbox(6)
		done.alignment = BoxContainer.ALIGNMENT_CENTER
		done.custom_minimum_size = Vector2(0, 44)
		var tick: TextureRect = MenuUI.icon("check", 24)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		done.add_child(tick)
		var word: Label = MenuUI.label("TAKEN", 26, MenuUI.GREEN_HI)
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		done.add_child(word)
		column.add_child(done)
		return card
	var label_text: String = "FREE" if free else "%s %s" % [MenuUI.fmt(price),
			currency.to_upper()]
	var buy: Button = MenuUI.button(label_text, "gold" if affordable else "grey", 22,
			Vector2(0, 44), 6)
	buy.disabled = not affordable
	buy.pressed.connect(func() -> void: _take(item, free, currency, price, buy))
	column.add_child(buy)
	return card

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
		# Same order as the OPEN button above: reopen, then raise the treat.
		_reopen()
		open_dawg_treat(menu)
		return
	SaveGame.grant(kind, amount)
	SaveGame.save()
	menu.refresh_currencies()
	sfx("purchase")
	menu.burst(center_of(button), "coin", 10)
	toast("+%s" % _item_name(kind, amount))
	_reopen()

func _item_name(kind: String, amount: int) -> String:
	var named: String = MenuUI.reward_name(kind, amount)
	return named if named != "" else kind.replace("_", " ").to_upper()

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
		var caption_label: Label = MenuUI.label(caption, 26, MenuUI.GOLD_INK)
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
