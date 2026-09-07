class_name SeasonScreen
extends MenuScreen
## Everything you are working towards, on one page: the Trophy Road and the
## Nobles Pass.
##
## They were two screens reached from two different places, and they answer the
## same question — what do I get next, and for doing what. Trophy Road pays out
## against total trophies and never resets; the Pass pays out against tokens and
## ends with the season. Putting them one above the other is what makes that
## difference legible instead of making it two menu items.
##
## Laid out to Jackson's 7 Sep mockup, which changed three things about how the
## two tracks read:
##
##   A REWARD IS A PICTURE OF ITSELF. The rails used to set every reward as
##   words — "250 COINS" in the display face — on the argument that a word reads
##   faster down a rail than a 108px illustration and ships no file. It does not:
##   twenty columns of words is a wall of text, and the thing being scanned for
##   is *which kind* of reward, which is exactly what a glyph answers first. The
##   word stays underneath as the amount.
##
##   THE TRACK IS DRAWN. A row of thresholds with no line between them is a list
##   of numbers; the line with a dot per milestone, lit as far as you have got
##   and dark after, is what makes it a road. It is one of the few places a line
##   IS the content, which is what MenuUI.rule() survives for.
##
##   EACH TRACK IS A BLOCK. Both sit inside a bordered card with its own head —
##   a glyph, a name, and the rule that governs it — so "permanent, never resets"
##   and "ends with the season" are attached to the thing they are true of.
##
## The whole screen lays out to a fixed height between the top bar and the
## shell's nav strip; nothing here scrolls vertically, and the two tracks scroll
## sideways on their own. The heights below add up to that budget on purpose —
## raise one and the Pass's premium lane goes off the bottom.

# MARK: metrics
#
# The screen lays out to a fixed height — nothing scrolls vertically — so these
# add up to what fill_content leaves between the top bar and the shell's nav:
# HEADER_H + ROAD_H + PASS_H + two gaps = 816 stage pixels. Raise one and the
# Pass's premium lane goes off the bottom.

const HEADER_H := 140.0
const ROAD_H := 300.0
const PASS_H := 352.0
const BLOCK_GAP := 10.0
const BLOCK_PAD := 14

## Trophy Road: a column per milestone, its threshold over the track over a card.
const MILESTONE_W := 178.0
const THRESH_H := 44.0
const TRACK_H := 22.0
const ROAD_CARD_H := 148.0
const ROAD_ICON := 42.0

## Nobles Pass: a lane column that stays put, then a column per tier.
const LANE_W := 168.0
const TIER_W := 150.0
const TIER_LABEL_H := 40.0
const PASS_CELL_H := 112.0
const PASS_ICON := 26.0
const LANE_GAP := 6.0

## Cards are inset inside their column so the columns read as separate tiles
## rather than as one continuous strip.
const CARD_INSET := 5.0

var _road_track: ScrollContainer
var _pass_track: ScrollContainer

func _build() -> void:
	screen_name = "season"
	var season: Dictionary = MenuData.season()
	topbar("Season", "%s · %s" % [MenuUI.fmt(SaveGame.total_trophies()) + " TROPHIES",
			str(season.get("name", ""))])
	var column: VBoxContainer = fill_content(0)
	column.add_child(_header(season))
	column.add_child(MenuUI.gap(BLOCK_GAP, true))
	column.add_child(_road_block(SaveGame.total_trophies()))
	column.add_child(MenuUI.gap(BLOCK_GAP, true))
	column.add_child(_pass_block())
	_scroll_to_progress(SaveGame.total_trophies())


# MARK: header

## Season identity on the left, pass progress in a card on the right. The card
## is the only boxed thing up here, because the tier and the token count are the
## two figures that change while you play.
func _header(season: Dictionary) -> Control:
	var row := MenuUI.hbox(40)
	row.custom_minimum_size = Vector2(0, HEADER_H)

	# The number and the countdown share one line under the name. Stacked, the
	# three lines came to 154 stage pixels, and the screen has 816 for the whole
	# page — that overrun is what put the Pass's premium lane under the nav.
	var left := MenuUI.vbox(2)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	left.add_child(MenuUI.display(str(season.get("name", "")).to_upper(), 56))
	var line := MenuUI.hbox(12)
	left.add_child(line)
	line.add_child(MenuUI.label("SEASON %d" % int(season.get("number", 1)), 24, MenuUI.GOLD))
	line.add_child(MenuUI.label("·", 24, MenuUI.TEXT_FAINT))
	line.add_child(MenuUI.label("%d DAYS LEFT" % int(season.get("endsInDays", 0)), 24,
			MenuUI.TEXT_DIM))
	row.add_child(MenuUI.spacer())

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.card_box(MenuUI.PANEL, MenuUI.RULE_HI, 12))
	card.custom_minimum_size = Vector2(720, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)
	var inner := MenuUI.hbox(22)
	card.add_child(inner)
	inner.add_child(_tier_badge())

	var progress := MenuUI.vbox(8)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(progress)
	progress.add_child(MenuUI.label("TOKENS TO NEXT", 22, MenuUI.TEXT_SOFT))
	var per_tier: float = maxf(1.0, float(season.get("tokensPerTier", 500)))
	var meter := MenuUI.hbox(14)
	progress.add_child(meter)
	var bar: Panel = MenuUI.bar(16, MenuUI.GOLD)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_child(bar)
	MenuUI.set_bar(bar, SaveGame.pass_tokens / per_tier)
	var figure: Label = MenuUI.display("%s / %s" % [MenuUI.fmt(SaveGame.pass_tokens),
			MenuUI.fmt(int(per_tier))], 30, MenuUI.GOLD)
	figure.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meter.add_child(figure)
	progress.add_child(_pass_state())
	return row

## TIER over the number, in a bordered square. Gold once the pass is bought.
func _tier_badge() -> Control:
	var accent: Color = MenuUI.GOLD if SaveGame.pass_premium else MenuUI.RULE_HI
	var badge := PanelContainer.new()
	var box := MenuUI.flat_box(MenuUI.INK, accent, 0).duplicate()
	box.set_border_width_all(3)
	box.border_color = accent
	badge.add_theme_stylebox_override("panel", box)
	badge.custom_minimum_size = Vector2(112, 94)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var column := MenuUI.vbox(0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(column)
	var word: Label = MenuUI.label("TIER", 22, MenuUI.TEXT_DIM)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(word)
	var number: Label = MenuUI.display(str(SaveGame.pass_tier), 46,
			MenuUI.GOLD if SaveGame.pass_premium else MenuUI.TEXT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(number)
	return badge

## Either the green tick that says the pass is live, or the button that buys it.
func _pass_state() -> Control:
	if SaveGame.pass_premium:
		var row := MenuUI.hbox(10)
		var tick: TextureRect = MenuUI.icon("check", 22)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tick)
		var live: Label = MenuUI.label("PASS ACTIVE", 22, MenuUI.GREEN_HI)
		live.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(live)
		return row
	var unlock: Button = MenuUI.button("UNLOCK — 169 GEMS", "gold", 20, Vector2(268, 0), 8)
	unlock.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	unlock.pressed.connect(_unlock_premium)
	return unlock

func _unlock_premium() -> void:
	if not SaveGame.spend("gems", 169):
		sfx("error")
		toast("Need 169 gems")
		return
	SaveGame.pass_premium = true
	SaveGame.save()
	menu.refresh_currencies()
	sfx("reward")
	toast("Nobles Pass unlocked")
	_reopen()

# MARK: blocks

## A bordered card with a head — glyph, name, and the rule that governs it —
## and a body the caller fills. Returns [card, body].
func _block(icon_name: String, title: String, rule_text: String,
		height: float) -> Array:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			MenuUI.card_box(MenuUI.PANEL, MenuUI.RULE_HI, BLOCK_PAD))
	card.custom_minimum_size = Vector2(0, height)
	var column := MenuUI.vbox(0)
	card.add_child(column)

	var head := MenuUI.hbox(12)
	head.custom_minimum_size = Vector2(0, 36)
	column.add_child(head)
	var glyph: TextureRect = MenuUI.icon(icon_name, 30)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(glyph)
	var name_label: Label = MenuUI.label(title, 26, MenuUI.TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	var dot: Label = MenuUI.label("·", 26, MenuUI.TEXT_FAINT)
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(dot)
	var rule_label: Label = MenuUI.label(rule_text, 22, MenuUI.TEXT_DIM)
	rule_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(rule_label)
	head.add_child(MenuUI.spacer())
	column.add_child(MenuUI.gap(8, true))
	return [card, column]

## A sideways rail. SHOW_NEVER rather than AUTO: an auto scrollbar reserves its
## own 18px under the cards whether or not it is drawn, which came off the
## bottom of both blocks and pushed the Pass's premium lane under the nav. The
## rail is dragged, and its position is what the lit part of the track says.
##
## EXPAND_FILL horizontally is load-bearing for the Pass, whose rail sits in a
## row beside the lane column: a ScrollContainer's minimum width does not count
## its contents, so without this the row hands it nothing and forty tiers of
## rewards lay out correctly inside a zero-width box.
## A control that takes a share of whatever height is left over. The two blocks
## share it in proportion to their own heights, and inside them the cards do —
## the stage covers a 16:10 display, which hands this screen ~180 stage pixels
## it does not have on 16:9, and parked at the bottom that reads as a band of
## nothing between the Pass and the nav.
func _grow(c: Control, ratio: float) -> void:
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio

func _rail(height: float) -> ScrollContainer:
	var track := ScrollContainer.new()
	track.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	track.custom_minimum_size = Vector2(0, height)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	track.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	return track

# MARK: trophy road

func _road_block(total: int) -> Control:
	var parts: Array = _block("trophy", "TROPHY ROAD", "PERMANENT, NEVER RESETS", ROAD_H)
	_grow(parts[0], ROAD_H)
	var body: VBoxContainer = parts[1]
	_road_track = _rail(THRESH_H + TRACK_H + 4 + ROAD_CARD_H)
	body.add_child(_road_track)
	var row := MenuUI.hbox(0)
	# A ScrollContainer stretches its child on the disabled axis only when the
	# CHILD asks to expand; without this the rail grows on a taller stage and
	# the row of cards stays at its minimum, parked at the top of it.
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_road_track.add_child(row)
	var road: Array = MenuData.trophy_road()
	for i in road.size():
		row.add_child(_milestone(road[i], i, road, total))
	return parts[0]

## Entries are `{trophies, reward: {kind, ...}}`; the older flat
## `{trophies, kind, ...}` shape is still accepted so a hand-edited game.json
## from before the split keeps working.
static func _payload(entry: Dictionary) -> Dictionary:
	var nested: Variant = entry.get("reward")
	return nested if nested is Dictionary else entry

func _milestone(entry: Dictionary, index: int, road: Array, total: int) -> Control:
	var goal: int = int(entry.get("trophies", 0))
	var reward: Dictionary = _payload(entry)
	var claim_id := "road:%d" % goal
	var reached: bool = total >= goal
	var claimed: bool = SaveGame.is_claimed(claim_id)
	var next_reached: bool = index + 1 < road.size() \
			and total >= int(road[index + 1].get("trophies", 0))

	var column := MenuUI.vbox(0)
	column.custom_minimum_size = Vector2(MILESTONE_W, 0)
	_grow(column, 1.0)
	var goal_label: Label = MenuUI.display(MenuUI.fmt(goal), 26,
			MenuUI.GOLD if reached else MenuUI.TEXT_DIM)
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal_label.custom_minimum_size = Vector2(MILESTONE_W, THRESH_H)
	column.add_child(goal_label)
	column.add_child(_track_cell(reached, next_reached, index == 0, index == road.size() - 1))
	column.add_child(MenuUI.gap(4, true))
	column.add_child(_reward_card(reward, claim_id, reached, claimed, MILESTONE_W,
			ROAD_CARD_H, ROAD_ICON, 24, 36.0, 10, 2))
	return column

## One span of the road: the line through this column, and the dot on it. The
## dot is lit once the milestone is reached and the line is lit as far as the
## next one you have got to, so the far end of the rail is visibly dark.
func _track_cell(lit: bool, lit_right: bool, first: bool, last: bool) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(MILESTONE_W, TRACK_H)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not first:
		cell.add_child(_track_line(0.0, 0.5, lit))
	if not last:
		cell.add_child(_track_line(0.5, 1.0, lit_right))
	var dot := Panel.new()
	var dot_size := 22.0
	dot.add_theme_stylebox_override("panel", MenuUI.flat_box(
			MenuUI.GOLD if lit else MenuUI.INK,
			MenuUI.GOLD if lit else MenuUI.RULE_HI, 0, int(dot_size / 2.0)))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 0.5
	dot.anchor_right = 0.5
	dot.anchor_top = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_left = -dot_size / 2.0
	dot.offset_right = dot_size / 2.0
	dot.offset_top = -dot_size / 2.0
	dot.offset_bottom = dot_size / 2.0
	cell.add_child(dot)
	return cell

func _track_line(from: float, to: float, lit: bool) -> ColorRect:
	var line := ColorRect.new()
	line.color = MenuUI.GOLD if lit else MenuUI.RULE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_left = from
	line.anchor_right = to
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_top = -2
	line.offset_bottom = 2
	return line

# MARK: nobles pass

func _pass_block() -> Control:
	var parts: Array = _block("crown", "NOBLES PASS", "ENDS WITH THE SEASON", PASS_H)
	_grow(parts[0], PASS_H)
	var body: VBoxContainer = parts[1]
	var row := MenuUI.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	row.add_child(_lane_column())
	_pass_track = _rail(TIER_LABEL_H + PASS_CELL_H * 2.0 + LANE_GAP)
	row.add_child(_pass_track)
	var tiers := MenuUI.hbox(0)
	tiers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pass_track.add_child(tiers)
	for tier in MenuData.game.get("passRewards", []):
		tiers.add_child(_tier_column(tier))
	return parts[0]

## The two lane names, pinned left while the tiers scroll past them. Without
## this the lanes are only identifiable by which row a cell is in.
func _lane_column() -> Control:
	var column := MenuUI.vbox(0)
	column.custom_minimum_size = Vector2(LANE_W, 0)
	column.add_child(MenuUI.gap(TIER_LABEL_H, true))
	column.add_child(_lane_head("ticket", "FREE", MenuUI.TEXT_SOFT, false))
	column.add_child(MenuUI.gap(LANE_GAP, true))
	column.add_child(_lane_head("crown", "PREMIUM", MenuUI.GOLD, true))
	return column

## Icon and lane name on one line, and under it either the word REWARDS or, on
## the premium lane you have not bought, the chip that buys it. One or the
## other: a button UNDER the word made the lane column taller than the tier
## columns beside it, and the whole block slid under the nav.
func _lane_head(icon_name: String, title: String, accent: Color, premium: bool) -> Control:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", MenuUI.flat_box(MenuUI.PANEL_HI,
			MenuUI.GOLD if premium else MenuUI.RULE, 12))
	cell.custom_minimum_size = Vector2(LANE_W, PASS_CELL_H)
	_grow(cell, PASS_CELL_H)
	var column := MenuUI.vbox(4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(column)
	var head := MenuUI.hbox(8)
	column.add_child(head)
	var glyph: TextureRect = MenuUI.icon(icon_name, 26)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(glyph)
	var name_label: Label = MenuUI.label(title, 24, accent)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	if premium and not SaveGame.pass_premium:
		var upgrade: Button = MenuUI.button("UPGRADE", "gold", 20, Vector2.ZERO, 6)
		upgrade.pressed.connect(_unlock_premium)
		column.add_child(upgrade)
	else:
		column.add_child(MenuUI.label("REWARDS", 20, MenuUI.TEXT_FAINT))
	return cell

## One tier: its number over the free cell over the premium cell. The tier you
## are on is ringed in gold, which is the only "you are here" on the grid.
func _tier_column(tier: Dictionary) -> Control:
	var number: int = int(tier.get("tier", 1))
	var reached: bool = number <= SaveGame.pass_tier
	var current: bool = number == SaveGame.pass_tier

	# No content margin on the ring: a PanelContainer adds its stylebox margins
	# to the child's width, so a 3px inset here made every column TIER_W + 6 and
	# walked the scroll-to-tier offset off by a column and a half down the rail.
	var ring := MenuUI.flat_box(Color(0, 0, 0, 0),
			MenuUI.GOLD if current else Color(0, 0, 0, 0), 0).duplicate()
	if current:
		ring.set_border_width_all(2)
		ring.border_color = MenuUI.GOLD
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ring)
	frame.custom_minimum_size = Vector2(TIER_W, 0)
	_grow(frame, 1.0)
	var column := MenuUI.vbox(0)
	frame.add_child(column)
	var label: Label = MenuUI.display("T%d" % number, 24,
			MenuUI.GOLD if reached else MenuUI.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, TIER_LABEL_H)
	column.add_child(label)
	column.add_child(_pass_cell(tier, "free", number, reached))
	column.add_child(MenuUI.gap(LANE_GAP, true))
	column.add_child(_pass_cell(tier, "premium", number, reached))
	return frame

## One lane of one tier. The premium lane is gated on the pass being bought, and
## says so in the cell rather than behind a padlock on the reward.
func _pass_cell(tier: Dictionary, lane: String, number: int, reached: bool) -> Control:
	var reward: Variant = tier.get(lane)
	if not (reward is Dictionary):
		var blank := PanelContainer.new()
		blank.add_theme_stylebox_override("panel",
				MenuUI.flat_box(MenuUI.INK, MenuUI.RULE, 10))
		blank.custom_minimum_size = Vector2(0, PASS_CELL_H)
		_grow(blank, PASS_CELL_H)
		var dash: Label = MenuUI.display("—", 26, MenuUI.TEXT_FAINT)
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		blank.add_child(dash)
		return blank
	var data: Dictionary = reward
	var claim_id: String = "pass:%d:%s" % [number, lane]
	var locked_by_pass: bool = lane == "premium" and not SaveGame.pass_premium
	return _reward_card(data, claim_id, reached and not locked_by_pass,
			SaveGame.is_claimed(claim_id), TIER_W, PASS_CELL_H, PASS_ICON, 20, 28.0, 8, 1,
			"PASS ONLY" if locked_by_pass else "LOCKED")

# MARK: reward cards

## The tile both tracks are made of: the reward's own glyph, its name, and what
## you can do about it. Three states, and the edge carries which one — green for
## banked, gold for claimable, hairline for out of reach — so a rail reads as a
## progress bar before a single word is read.
##
## `lines` is 2 on the road, where a card is tall enough for "RANDOM FIGHTER" to
## wrap, and 1 in the Pass, where it is not: a pass cell trims to an ellipsis
## instead, and the portrait beside a trimmed skin name says whose it is.
func _reward_card(reward: Dictionary, claim_id: String, unlocked: bool, claimed: bool,
		width: float, height: float, icon_size: float, name_size: int,
		state_h: float, pad: int, lines: int, locked_text: String = "LOCKED") -> Control:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_left", int(CARD_INSET))
	holder.add_theme_constant_override("margin_right", int(CARD_INSET))
	holder.custom_minimum_size = Vector2(width, height)
	_grow(holder, height)

	var claimable: bool = unlocked and not claimed
	var edge: Color = MenuUI.RULE
	var fill: Color = MenuUI.INK
	if claimed:
		edge = MenuUI.GREEN_LO
		fill = Color("#0e1a12")
	elif claimable:
		edge = MenuUI.GOLD
		fill = MenuUI.PANEL_HI

	var column := MenuUI.vbox(4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art: Control = _reward_icon(reward, icon_size)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(art)
	column.add_child(_name_label(_reward_name(reward), name_size, lines,
			MenuUI.TEXT if (unlocked or claimed) else MenuUI.TEXT_DIM))

	# A CLAIMABLE CARD IS THE BUTTON. A gold CLAIM button inside the card was
	# the obvious build and it does not fit: MenuUI.button carries 16px of
	# content margin, so at the card's own type size its minimum height is 71 —
	# half the tile — and every claimable column grew 20px taller than its
	# neighbours and pushed the rail out of its block. Pressing the tile is also
	# the bigger target on a phone, and it is what the mockup draws: the state
	# line is a word, in all three states.
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
		b.pressed.connect(func() -> void: _claim(claim_id, reward, b))
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
	column.add_child(_state_row(claimable, claimed, name_size, state_h, locked_text))
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
## says pressing the tile will pay out. One height in all three states, so a
## rail of cards has one baseline.
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

# MARK: rewards

## The glyph for a reward kind. A fighter, a skin or a pin is a picture of the
## fighter — the roster's own render, not a second illustration of them.
func _reward_icon(reward: Dictionary, size: float) -> Control:
	var kind: String = str(reward.get("kind", ""))
	match kind:
		"brawler":
			return _portrait_tile(str(reward.get("id", "")), size)
		"skin":
			return _portrait_tile(str(reward.get("brawler", "")), size)
		"pin":
			return _portrait_tile(_named_fighter(str(reward.get("name", ""))), size)
		"brawler_drop":
			return MenuUI.icon("shield", size)
	var glyph: String = {
		"coins": "coin", "gems": "gem", "power_points": "power_point",
		"bling": "bling", "dawg_treat": "dawg_treat", "star_drop": "dawg_treat",
	}.get(kind, "token")
	return MenuUI.icon(glyph, size)

## The fighter a "Sanjit Pin" is of. Reward names carry the fighter's name and
## nothing machine-readable, so this matches the roster against the string.
func _named_fighter(text: String) -> String:
	var lower: String = text.to_lower()
	for b in MenuData.brawlers:
		var id: String = str(b.get("id", ""))
		if id != "" and lower.contains(id):
			return id
	return ""

## A portrait in a rounded tile of the fighter's own colour. Falls back to the
## roster glyph for a kit with no render yet (Nova).
func _portrait_tile(id: String, size: float) -> Control:
	var art: Texture2D = MenuData.portrait(id)
	if art == null:
		return MenuUI.icon("shield", size)
	var tint: Color = MenuUI.hex(MenuData.brawler(id).get("color", MenuUI.BLUE), MenuUI.BLUE)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", MenuUI.flat_box(
			MenuUI.INK.lerp(tint, 0.45), tint, 0, MenuUI.RADIUS_SMALL))
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

func _reward_name(reward: Dictionary) -> String:
	var kind: String = str(reward.get("kind", ""))
	if kind == "brawler":
		return str(MenuData.brawler(str(reward.get("id", ""))).get("name", "Fighter")).to_upper()
	if kind == "brawler_drop":
		return "RANDOM FIGHTER"
	if kind == "skin":
		return str(reward.get("name", "SKIN")).to_upper()
	var amount: int = int(reward.get("amount", 1))
	match kind:
		"coins":
			return "%s COINS" % MenuUI.fmt(amount)
		"gems":
			return "%s GEMS" % MenuUI.fmt(amount)
		"star_drop", "dawg_treat":
			return "%s DAWG TREAT%s" % [MenuUI.fmt(amount), "S" if amount != 1 else ""]
		"power_points":
			return "%s POWER PTS" % MenuUI.fmt(amount)
		"bling":
			return "%s BLING" % MenuUI.fmt(amount)
	return str(reward.get("name", kind)).replace("_", " ").to_upper()

func _claim(claim_id: String, reward: Dictionary, button: Control) -> void:
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
	toast("Claimed %s" % _reward_name(reward))
	var drops: int = amount if (kind == "star_drop" or kind == "dawg_treat") else 0
	_reopen()
	if not unlocked_fighter.is_empty():
		_show_unlock(unlocked_fighter)
	for i in drops:
		get_tree().create_timer(0.35 + i * 0.12).timeout.connect(func() -> void:
			ShopScreen.open_dawg_treat(menu))

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
	column.add_child(MenuUI.label("JOINS THE ROSTER", 20, MenuUI.GOLD))
	var name_label: Label = MenuUI.display(str(fighter.get("name", "FIGHTER")).to_upper(), 88)
	column.add_child(name_label)
	column.add_child(MenuUI.label(str(fighter.get("title", "")), 21, MenuUI.TEXT_DIM))
	column.add_child(MenuUI.gap(10, true))
	column.add_child(MenuUI.rule())
	column.add_child(MenuUI.gap(10, true))
	var play: Button = MenuUI.button("PLAY AS %s" % str(fighter.get("name", "")), "gold",
			30, Vector2(0, 72))
	play.pressed.connect(func() -> void:
		menu.select_brawler(str(fighter.get("id", "")))
		popup.close_screen())
	column.add_child(play)

# MARK: position

func _scroll_to_progress(total: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# Snapped to a column boundary, not offset back by a margin. Offsetting put
	# the rail's left edge partway through a milestone, so the first thing on
	# both rails was a sliced column showing "PTS" and half a CLAIM button.
	if is_instance_valid(_road_track):
		var index: int = 0
		var road: Array = MenuData.trophy_road()
		for i in road.size():
			if int(road[i].get("trophies", 0)) <= total:
				index = i
			else:
				break
		_road_track.scroll_horizontal = int(maxf(0.0, index * MILESTONE_W))
	if is_instance_valid(_pass_track):
		_pass_track.scroll_horizontal = int(maxf(0.0,
				(SaveGame.pass_tier - 1) * TIER_W))

func _reopen() -> void:
	menu.push_screen(SeasonScreen.new())
	close_screen()
