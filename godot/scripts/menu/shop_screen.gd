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
const DEAL_W := 234.0
const DEAL_H := 320.0
const DEAL_ART := 116.0

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

	# Two groups, each a rail, because a shelf you scroll sideways shows a few
	# things at a time and a grid shows all of them at once. Power levels are
	# NOT here any more: they belong to a fighter, so they are bought on that
	# fighter's page, where you can see what you are powering up.
	for group: Array in [["TODAY", "RESETS IN %s" % _reset_time(), "coin", "daily"],
			["RESOURCES", "SPEND GEMS", "gem", "resources"]]:
		var items: Array = _affordable(str(group[3]))
		if items.is_empty():
			continue
		column.add_child(MenuUI.gap(BLOCK_GAP, true))
		var block: Array = MenuUI.block(str(group[2]), str(group[0]), str(group[1]))
		var rail := ScrollContainer.new()
		rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		rail.custom_minimum_size = Vector2(0, DEAL_H)
		rail.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		(block[1] as VBoxContainer).add_child(rail)
		var row := MenuUI.hbox(CARD_GAP)
		rail.add_child(row)
		for item: Dictionary in items:
			row.add_child(_deal_card(item))
		column.add_child(block[0])
	column.add_child(MenuUI.gap(40, true))
	_open_at_top(column)

## The rails are ScrollContainers inside a ScrollContainer, and the outer one
## came up scrolled past the Dawg Treat — the one block this page opens on.
func _open_at_top(column: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: Node = column.get_parent()
	if scroll is ScrollContainer:
		(scroll as ScrollContainer).scroll_vertical = 0

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
		open_dawg_treat(menu)
		_reopen())
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
func _affordable(group: String) -> Array:
	var out: Array = []
	for item: Dictionary in MenuData.game.get("shop", {}).get(group, []):
		if str(item.get("currency", "coins")) in ["coins", "gems", "bling", "free"]:
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
	var who: String = str(item.get("brawler", ""))

	var card := PanelContainer.new()
	var edge: Color = MenuUI.RULE
	if bought:
		edge = MenuUI.GREEN_LO
	elif affordable:
		edge = MenuUI.GOLD
	card.add_theme_stylebox_override("panel", MenuUI.flat_box(
			Color("#0e1a12") if bought else MenuUI.INK, edge, 12))
	card.custom_minimum_size = Vector2(DEAL_W, DEAL_H)
	var column := MenuUI.vbox(6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	column.add_child(_deal_art(kind, who))

	var title: String = str(item.get("name", ""))
	if title == "":
		title = _item_name(kind, amount)
	var name_label: Label = MenuUI.display(title.to_upper(), 28,
			MenuUI.TEXT_DIM if bought else MenuUI.TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	var line: String = str(item.get("label", ""))
	if who != "":
		line = "FOR %s" % str(MenuData.brawler(who).get("name", "")).to_upper()
	elif str(item.get("value", "")) != "":
		line = "%s VALUE" % str(item.value)
	var sub: Label = MenuUI.label(line, 24, MenuUI.TEXT_FAINT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size = Vector2(0, 30)
	column.add_child(sub)

	if bought:
		var done := MenuUI.hbox(6)
		done.alignment = BoxContainer.ALIGNMENT_CENTER
		done.custom_minimum_size = Vector2(0, 52)
		var tick: TextureRect = MenuUI.icon("check", 26)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		done.add_child(tick)
		var word: Label = MenuUI.label(str(item.get("claimedLabel", "TAKEN")), 26,
				MenuUI.GREEN_HI)
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		done.add_child(word)
		column.add_child(done)
		return card
	var buy: Button = MenuUI.button("", "gold" if affordable else "grey", 26,
			Vector2(0, 52), 6)
	buy.disabled = not affordable
	# The price wears the currency's own picture rather than spelling it, which
	# is the same coin and gem the top bar shows.
	var price_row := MenuUI.hbox(6)
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buy.add_child(price_row)
	if free:
		var word2: Label = MenuUI.display("FREE", 28, MenuUI.GOLD_INK)
		word2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price_row.add_child(word2)
	else:
		var coin: TextureRect = MenuUI.pack_icon(currency, 30)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		price_row.add_child(coin)
		var figure: Label = MenuUI.display(MenuUI.fmt(price), 28,
				MenuUI.GOLD_INK if affordable else MenuUI.TEXT)
		figure.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price_row.add_child(figure)
	buy.pressed.connect(func() -> void: _take(item, free, currency, price, buy))
	column.add_child(buy)
	return card

## What you are buying, as a picture. A deal that is FOR a fighter carries that
## fighter's face in the corner of it — "50 power points" and "50 power points
## for Leon" were the same tile with a different word underneath, and the notes
## asked for the two icons together.
func _deal_art(kind: String, who: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(DEAL_ART, DEAL_ART)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph: TextureRect = MenuUI.pack_icon(MenuUI.reward_glyph(kind), DEAL_ART)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(glyph)
	if who == "":
		return holder
	var art: Texture2D = MenuData.portrait(who)
	if art == null:
		return holder
	var tint: Color = MenuUI.hex(MenuData.brawler(who).get("color", MenuUI.BLUE),
			MenuUI.BLUE)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", MenuUI.flat_box(
			MenuUI.INK.lerp(tint, 0.45), tint, 0, MenuUI.RADIUS_SMALL))
	tile.custom_minimum_size = Vector2(56, 56)
	tile.clip_contents = true
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := TextureRect.new()
	face.texture = art
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.custom_minimum_size = Vector2(56, 56)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(face)
	MenuUI.pin(tile, true, true, 0.0)
	holder.add_child(tile)
	return holder

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
		# Rebuild the shop FIRST and open the Treat over it. The other way round
		# pushed a fresh ShopScreen on top of the Treat, so the thing you just
		# bought only appeared once you backed out of the shop — which is
		# exactly what it looked like: a purchase that did nothing.
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
## Opening one. The treat is a bone that bobs until you tap it, and then the
## prize arrives: the bone flies apart, the rarity band lights in that tier's
## colour, and what you won scales in wearing its own picture.
##
## It used to be a coloured rectangle that said TAP TO OPEN and then said a
## number. The odds are the honest part of this feature and they are printed on
## the shop page; the opening is the part that is supposed to be worth doing,
## and text does not carry that.
static func open_dawg_treat(shell: MenuShell) -> void:
	var tier: Dictionary = _roll_tier()
	var reward: Dictionary = _roll_reward(str(tier.id))
	var accent: Color = MenuUI.hex(tier.color)

	var popup: MenuPopup = shell.popup("Dawg Treat", 720)
	var box := MenuUI.vbox(14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	popup.body_box.add_child(box)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 300)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stage)

	# The rarity's colour as a soft pool behind everything, lit on the reveal.
	var pool := TextureRect.new()
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(accent.r, accent.g, accent.b, 0.55))
	g.set_color(1, Color(accent.r, accent.g, accent.b, 0.0))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	pool.texture = tex
	pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pool.stretch_mode = TextureRect.STRETCH_SCALE
	pool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool.modulate.a = 0.0
	stage.add_child(pool)

	var bone: TextureRect = MenuUI.pack_icon("dawg_treat", 190)
	bone.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bone.offset_left = -95
	bone.offset_right = 95
	bone.offset_top = -95
	bone.offset_bottom = 95
	bone.pivot_offset = Vector2(95, 95)
	stage.add_child(bone)

	var prompt: Label = MenuUI.display("TAP TO OPEN", 44, accent)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prompt)

	# Bob and tilt, so the unopened treat is alive without flashing.
	var bob := bone.create_tween().set_loops()
	bob.set_parallel()
	bob.tween_property(bone, "position:y", -14.0, 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(bone, "rotation", 0.10, 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.chain().set_parallel()
	bob.tween_property(bone, "position:y", 0.0, 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(bone, "rotation", -0.10, 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var opened: Array = [false]
	var open := func(event: InputEvent) -> void:
		if opened[0] or not (event is InputEventMouseButton and event.pressed):
			return
		opened[0] = true
		shell.sfx("reward")
		Haptics.fire("ui_reward")
		bob.kill()

		# The bone throws itself open and the pool lights behind it.
		var burst := bone.create_tween()
		burst.set_parallel()
		burst.tween_property(bone, "scale", Vector2(1.7, 1.7), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		burst.tween_property(bone, "rotation", 0.9, 0.28)
		burst.tween_property(bone, "modulate:a", 0.0, 0.26).set_delay(0.06)
		var light := pool.create_tween()
		light.tween_property(pool, "modulate:a", 1.0, 0.3)
		shell.burst(shell.stage.size / shell.stage.scale * 0.5, "trophy", 16)

		var kind: String = str(reward.get("kind", "coins"))
		var headline: String = ""
		var caption: String = str(tier.label).to_upper()
		var art: Control
		if kind == "brawler":
			var b: Dictionary = MenuData.brawler(str(reward.id))
			SaveGame.unlock(str(reward.id))
			headline = str(b.get("name", "FIGHTER")).to_upper()
			caption = "NEW FIGHTER · %s" % str(tier.label).to_upper()
			art = _prize_portrait(str(reward.id), 170)
		else:
			var amount: int = int(reward.get("amount", 0))
			SaveGame.grant(kind, amount)
			shell.refresh_currencies()
			headline = MenuUI.reward_name(kind, amount)
			if headline == "":
				headline = "+%s" % MenuUI.fmt(amount)
			art = MenuUI.pack_icon(MenuUI.reward_glyph(kind), 170)
		SaveGame.save()

		var prize := MenuUI.vbox(4)
		prize.alignment = BoxContainer.ALIGNMENT_CENTER
		prize.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		prize.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(prize)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		prize.add_child(art)
		var headline_label: Label = MenuUI.display(headline, 58, MenuUI.TEXT)
		headline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prize.add_child(headline_label)
		prize.pivot_offset = Vector2(popup.width * 0.5, 150)
		prize.scale = Vector2(0.4, 0.4)
		prize.modulate.a = 0.0
		var land := prize.create_tween()
		land.set_parallel()
		land.tween_property(prize, "scale", Vector2.ONE, 0.42).set_delay(0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		land.tween_property(prize, "modulate:a", 1.0, 0.24).set_delay(0.16)

		prompt.text = caption
		prompt.add_theme_color_override("font_color", accent)
		var done: Button = MenuUI.button("DONE", "gold")
		done.pressed.connect(popup.close_screen)
		box.add_child(done)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(open)

## A won fighter, in a rounded tile of their own colour.
static func _prize_portrait(id: String, size: float) -> Control:
	var art: Texture2D = MenuData.portrait(id)
	if art == null:
		return MenuUI.pack_icon("shield", size)
	var tint: Color = MenuUI.hex(MenuData.brawler(id).get("color", MenuUI.BLUE), MenuUI.BLUE)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel",
			MenuUI.flat_box(MenuUI.INK.lerp(tint, 0.45), tint, 0, MenuUI.RADIUS))
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

## Kept so older call sites keep working; Dawg Treats are the only container.
static func open_star_drop(shell: MenuShell) -> void:
	open_dawg_treat(shell)
