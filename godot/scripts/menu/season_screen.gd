class_name SeasonScreen
extends RewardScreen
## The Nobles Pass, and now nothing else.
##
## *The Trophy Road moved out on 7 Sep 2026* (`TrophyRoadScreen`, reached by
## tapping your trophy count on the lobby). The two shared this page because
## they answer the same question — what do I get next, and for doing what — and
## differ only in whether they reset. That is true and it was the wrong call:
## the Road is **permanent**, so it would show the same rail on every season's
## page, above the one thing on it that actually changes. Splitting them gives
## the Pass the whole page, which is what it needed — the rewards were small
## because there were forty of them crammed under another rail, and a skin came
## out as a 26px coat hanger.
##
## What the room bought: art at 118px, so a skin or a pin is a picture of the
## fighter it is for; nine visible tiers instead of eleven; and a premium lane
## you have not bought that is dimmed as a whole rather than wearing the same
## padlock a tier you have not reached wears.

const HEADER_H := 152.0
const BLOCK_PAD := 14
const LANE_W := 196.0
const TIER_W := 232.0
const TIER_LABEL_H := 44.0
const PASS_CELL_H := 258.0
const CARD_ART := 118.0
const LANE_GAP := 8.0

var _rail: ScrollContainer

func _build() -> void:
	screen_name = "season"
	var season: Dictionary = MenuData.season()
	topbar("Season", str(season.get("name", "")))
	var column: VBoxContainer = fill_content(0)
	column.add_child(_header(season))
	column.add_child(MenuUI.gap(10, true))
	column.add_child(_pass_block())

# MARK: header

func _header(season: Dictionary) -> Control:
	var row := MenuUI.hbox(40)
	row.custom_minimum_size = Vector2(0, HEADER_H)

	var left := MenuUI.vbox(2)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	left.add_child(MenuUI.display(str(season.get("name", "")).to_upper(), 64))
	var line := MenuUI.hbox(12)
	left.add_child(line)
	line.add_child(MenuUI.label("SEASON %d" % int(season.get("number", 1)), 26, MenuUI.GOLD))
	line.add_child(MenuUI.label("·", 26, MenuUI.TEXT_FAINT))
	line.add_child(MenuUI.label("%d DAYS LEFT" % int(season.get("endsInDays", 0)), 26,
			MenuUI.TEXT_DIM))
	row.add_child(MenuUI.spacer())

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.card_box(MenuUI.PANEL, MenuUI.RULE_HI, 16))
	card.custom_minimum_size = Vector2(700, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)
	var inner := MenuUI.hbox(22)
	card.add_child(inner)
	inner.add_child(_tier_badge())

	var progress := MenuUI.vbox(6)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(progress)
	# The label sits ON the bar's row, not two gaps above it: it names the bar
	# and had drifted far enough away to read as a heading for the whole card.
	var meter := MenuUI.hbox(14)
	progress.add_child(meter)
	meter.add_child(MenuUI.label("TOKENS TO NEXT", 26, MenuUI.TEXT_SOFT))
	meter.add_child(MenuUI.spacer())
	var per_tier: float = maxf(1.0, float(season.get("tokensPerTier", 500)))
	var figure: Label = MenuUI.display("%s / %s" % [MenuUI.fmt(SaveGame.pass_tokens),
			MenuUI.fmt(int(per_tier))], 32, MenuUI.GOLD)
	meter.add_child(figure)
	var bar: Panel = MenuUI.bar(16, MenuUI.GOLD)
	progress.add_child(bar)
	MenuUI.set_bar(bar, SaveGame.pass_tokens / per_tier)
	progress.add_child(MenuUI.gap(4, true))
	progress.add_child(_pass_state())
	return row

## TIER over the number, in a bordered square. The word used to sit hard against
## the top edge because the box had no padding of its own.
func _tier_badge() -> Control:
	var accent: Color = MenuUI.GOLD if SaveGame.pass_premium else MenuUI.RULE_HI
	var badge := PanelContainer.new()
	var box := MenuUI.flat_box(MenuUI.INK, accent, 14).duplicate()
	box.set_border_width_all(3)
	box.border_color = accent
	badge.add_theme_stylebox_override("panel", box)
	badge.custom_minimum_size = Vector2(126, 116)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var column := MenuUI.vbox(0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(column)
	var word: Label = MenuUI.label("TIER", 24, MenuUI.TEXT_DIM)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(word)
	var number: Label = MenuUI.display(str(SaveGame.pass_tier), 50,
			MenuUI.GOLD if SaveGame.pass_premium else MenuUI.TEXT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(number)
	return badge

func _pass_state() -> Control:
	if SaveGame.pass_premium:
		var row := MenuUI.hbox(10)
		var tick: TextureRect = MenuUI.icon("check", 26)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tick)
		var live: Label = MenuUI.label("PASS ACTIVE", 26, MenuUI.GREEN_HI)
		live.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(live)
		return row
	var unlock: Button = MenuUI.button("UNLOCK — %d GEMS" % PASS_PRICE, "gold", 22,
			Vector2(300, 0), 8)
	unlock.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	unlock.pressed.connect(_unlock_premium)
	return unlock

const PASS_PRICE := 169

## Confirmed, with the price in the question — 169 gems used to leave the save
## on one unlabelled tap.
func _unlock_premium() -> void:
	var ok: bool = await menu.confirm("Nobles Pass",
			"Unlock the premium reward lane for the rest of this season. "
			+ "It costs %d gems and you have %s." % [PASS_PRICE, MenuUI.fmt(SaveGame.gems)],
			"UNLOCK — %d GEMS" % PASS_PRICE)
	if not ok:
		return
	if not SaveGame.spend("gems", PASS_PRICE):
		sfx("error")
		toast("Need %d gems" % PASS_PRICE)
		return
	SaveGame.pass_premium = true
	SaveGame.save()
	menu.refresh_currencies()
	sfx("reward")
	toast("Nobles Pass unlocked")
	reopen()

# MARK: the pass

func _pass_block() -> Control:
	var parts: Array = MenuUI.block("crown", "NOBLES PASS", "ENDS WITH THE SEASON",
			BLOCK_PAD)
	var card: Control = parts[0]
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body: VBoxContainer = parts[1]
	var row := MenuUI.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	row.add_child(_lane_column())
	_rail = ScrollContainer.new()
	_rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	row.add_child(_rail)
	var tiers := MenuUI.hbox(0)
	tiers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_child(tiers)
	for tier in MenuData.game.get("passRewards", []):
		tiers.add_child(_tier_column(tier))
	_scroll_to_tier()
	return card

func _lane_column() -> Control:
	var column := MenuUI.vbox(0)
	column.custom_minimum_size = Vector2(LANE_W, 0)
	column.add_child(MenuUI.gap(TIER_LABEL_H, true))
	column.add_child(_lane_head("ticket", "FREE", MenuUI.TEXT_SOFT, false))
	column.add_child(MenuUI.gap(LANE_GAP, true))
	column.add_child(_lane_head("crown", "PREMIUM", MenuUI.GOLD, true))
	return column

func _lane_head(icon_name: String, title: String, accent: Color, premium: bool) -> Control:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", MenuUI.flat_box(MenuUI.PANEL_HI,
			MenuUI.GOLD if premium else MenuUI.RULE, 12))
	cell.custom_minimum_size = Vector2(LANE_W, PASS_CELL_H)
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = PASS_CELL_H
	var column := MenuUI.vbox(8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(column)
	var glyph: TextureRect = MenuUI.icon(icon_name, 46)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(glyph)
	var name_label: Label = MenuUI.label(title, 26, accent)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var sub: Label = MenuUI.label("REWARDS", 22, MenuUI.TEXT_FAINT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	if premium and not SaveGame.pass_premium:
		var upgrade: Button = MenuUI.button("UPGRADE", "gold", 22, Vector2.ZERO, 6)
		upgrade.pressed.connect(_unlock_premium)
		column.add_child(upgrade)
	return cell

func _tier_column(tier: Dictionary) -> Control:
	var number: int = int(tier.get("tier", 1))
	var reached: bool = number <= SaveGame.pass_tier
	var current: bool = number == SaveGame.pass_tier

	var ring := MenuUI.flat_box(Color(0, 0, 0, 0),
			MenuUI.GOLD if current else Color(0, 0, 0, 0), 0).duplicate()
	if current:
		ring.set_border_width_all(2)
		ring.border_color = MenuUI.GOLD
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ring)
	frame.custom_minimum_size = Vector2(TIER_W, 0)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := MenuUI.vbox(0)
	frame.add_child(column)
	var label: Label = MenuUI.display("TIER %d" % number, 28,
			MenuUI.GOLD if reached else MenuUI.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, TIER_LABEL_H)
	column.add_child(label)
	column.add_child(_pass_cell(tier, "free", number, reached))
	column.add_child(MenuUI.gap(LANE_GAP, true))
	column.add_child(_pass_cell(tier, "premium", number, reached))
	return frame

func _pass_cell(tier: Dictionary, lane: String, number: int, reached: bool) -> Control:
	var reward: Variant = tier.get(lane)
	if not (reward is Dictionary):
		var blank := PanelContainer.new()
		blank.add_theme_stylebox_override("panel",
				MenuUI.flat_box(MenuUI.INK, MenuUI.RULE, 10))
		blank.custom_minimum_size = Vector2(0, PASS_CELL_H)
		blank.size_flags_vertical = Control.SIZE_EXPAND_FILL
		blank.size_flags_stretch_ratio = PASS_CELL_H
		var dash: Label = MenuUI.display("—", 28, MenuUI.TEXT_FAINT)
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		blank.add_child(dash)
		return blank
	var data: Dictionary = reward
	var claim_id: String = "pass:%d:%s" % [number, lane]
	var locked_by_pass: bool = lane == "premium" and not SaveGame.pass_premium
	var card: Control = reward_card(data, claim_id, reached and not locked_by_pass,
			SaveGame.is_claimed(claim_id), TIER_W, PASS_CELL_H, CARD_ART, 26, 36.0, 10, 2,
			"PASS ONLY" if locked_by_pass else "LOCKED", locked_by_pass)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = PASS_CELL_H
	for side in ["margin_left", "margin_right"]:
		(card as MarginContainer).add_theme_constant_override(side, 5)
	return card

func _scroll_to_tier() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_rail):
		_rail.scroll_horizontal = int(maxf(0.0, (SaveGame.pass_tier - 1) * TIER_W))

func reopen() -> void:
	menu.push_screen(SeasonScreen.new())
	close_screen()
