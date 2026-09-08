class_name TrophyRoadScreen
extends RewardScreen
## The Trophy Road, on its own page, reached by tapping your trophy count.
##
## *Split out of Season on 7 Sep 2026.* It shared a page with the Nobles Pass
## on the argument that they answer the same question — what do I get next, and
## for doing what — and differ only in whether they reset. True, and it made the
## season's page mostly not about the season: the Road is **permanent**, so
## every season would show the same rail above the one thing that changes.
## Hanging it off the trophy figure instead puts it where the number that drives
## it lives, and gives the Pass the whole page.

const MILESTONE_W := 232.0
const THRESH_H := 44.0
const TRACK_H := 26.0
## Big enough that a fighter reward is a face you recognise rather than a
## thumbnail, which is the whole reason the Road got its own page.
const CARD_ART := 150.0
const CARD_H := 372.0

var _rail: ScrollContainer

func _build() -> void:
	screen_name = "road"
	var total: int = SaveGame.total_trophies()
	topbar("Trophy Road", "%s TROPHIES · PERMANENT, NEVER RESETS" % MenuUI.fmt(total))

	var column: VBoxContainer = fill_content(0)
	column.add_child(_next_up(total))
	column.add_child(MenuUI.gap(10, true))
	var rail := ScrollContainer.new()
	rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.add_child(rail)
	_rail = rail
	var row := MenuUI.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var road: Array = MenuData.trophy_road()
	for i in road.size():
		row.add_child(_milestone(road[i], i, road, total))
	_scroll_to_progress(total)

## What you are actually working towards, over the bar that says how close you
## are. The rail below is the whole road; this is the next rung of it, and it is
## the same reading the lobby gives under your trophy count.
func _next_up(total: int) -> Control:
	var lo: int = 0
	var goal: int = -1
	var reward: Dictionary = {}
	for entry in MenuData.trophy_road():
		var at: int = int(entry.get("trophies", 0))
		if at > total:
			goal = at
			reward = RewardScreen.payload(entry)
			break
		lo = at
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.card_box(MenuUI.PANEL, MenuUI.RULE_HI, 18))
	var row := MenuUI.hbox(20)
	card.add_child(row)
	if goal < 0:
		row.add_child(MenuUI.display("EVERY MILESTONE CLAIMED", 34, MenuUI.GOLD))
		return card
	var art: Control = reward_art(reward, 72)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var text := MenuUI.vbox(6)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var head := MenuUI.hbox(12)
	text.add_child(head)
	head.add_child(MenuUI.label("NEXT ON THE ROAD", 26, MenuUI.TEXT_DIM))
	var name_label: Label = MenuUI.display(reward_name(reward), 30, MenuUI.TEXT)
	head.add_child(name_label)
	head.add_child(MenuUI.spacer())
	var figure: Label = MenuUI.display("%s / %s" % [MenuUI.fmt(total), MenuUI.fmt(goal)],
			32, MenuUI.GOLD)
	head.add_child(figure)
	var bar: Panel = MenuUI.bar(14, MenuUI.GOLD)
	text.add_child(bar)
	MenuUI.set_bar(bar, float(total - lo) / maxf(1.0, float(goal - lo)))
	text.add_child(MenuUI.label("%s TROPHIES TO GO" % MenuUI.fmt(goal - total), 22,
			MenuUI.TEXT_FAINT))
	return card

func _milestone(entry: Dictionary, index: int, road: Array, total: int) -> Control:
	var goal: int = int(entry.get("trophies", 0))
	var reward: Dictionary = RewardScreen.payload(entry)
	var claim_id := "road:%d" % goal
	var reached: bool = total >= goal
	var claimed: bool = SaveGame.is_claimed(claim_id)
	var next_reached: bool = index + 1 < road.size() \
			and total >= int(road[index + 1].get("trophies", 0))

	var column := MenuUI.vbox(0)
	column.custom_minimum_size = Vector2(MILESTONE_W, 0)
	# Centred in the rail rather than stretched down it: the road is one row of
	# cards, and an EXPAND_FILL column left each card marooned at the top of a
	# 600px lane.
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := MenuUI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(MILESTONE_W, THRESH_H)
	column.add_child(row)
	var cup: TextureRect = MenuUI.pack_icon("trophy", 30)
	cup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cup.modulate = Color.WHITE if reached else Color(1, 1, 1, 0.4)
	row.add_child(cup)
	var goal_label: Label = MenuUI.display(MenuUI.fmt(goal), 30,
			MenuUI.GOLD if reached else MenuUI.TEXT_DIM)
	goal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(goal_label)

	column.add_child(_track_cell(reached, next_reached, index == 0, index == road.size() - 1))
	column.add_child(MenuUI.gap(6, true))
	var card: Control = reward_card(reward, claim_id, reached, claimed, MILESTONE_W,
			CARD_H, CARD_ART, 26, 40.0, 12, 2)
	for side in ["margin_left", "margin_right"]:
		(card as MarginContainer).add_theme_constant_override(side, 6)
	column.add_child(card)
	return column

## One span of the road: the line through this column, and the dot on it. Lit
## as far as you have got, so the far end of the rail is visibly dark.
func _track_cell(lit: bool, lit_right: bool, first: bool, last: bool) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(MILESTONE_W, TRACK_H)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not first:
		cell.add_child(_track_line(0.0, 0.5, lit))
	if not last:
		cell.add_child(_track_line(0.5, 1.0, lit_right))
	var dot := Panel.new()
	var dot_size := 24.0
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

func _scroll_to_progress(total: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_rail):
		return
	var index: int = 0
	var road: Array = MenuData.trophy_road()
	for i in road.size():
		if int(road[i].get("trophies", 0)) <= total:
			index = i
		else:
			break
	_rail.scroll_horizontal = int(maxf(0.0, index * MILESTONE_W))

func reopen() -> void:
	menu.push_screen(TrophyRoadScreen.new())
	close_screen()
