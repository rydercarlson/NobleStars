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
## Rewards are words, not icons. The old rails drew a 108px illustration per
## milestone from a folder of generated art; "250 COINS" set in the display face
## says the same thing, reads at a glance down a rail, and ships no file.

const MILESTONE_W := 190.0
const TIER_W := 152.0
## Both rails plus the header have to clear 1080 stage pixels between the top
## bar and the bottom of the screen, and the Pass rail carries two lanes to the
## Road's one. Raise either and the Pass's premium lane goes off the bottom.
const RAIL_ROAD_H := 208.0
const RAIL_PASS_H := 296.0
const PASS_CELL_H := 104.0

var _road_track: ScrollContainer
var _pass_track: ScrollContainer

func _build() -> void:
	screen_name = "season"
	var season: Dictionary = MenuData.season()
	topbar("Season", "%s · %s" % [MenuUI.fmt(SaveGame.total_trophies()) + " TROPHIES",
			str(season.get("name", ""))])
	var column: VBoxContainer = fill_content(0)
	column.add_child(_header(season))
	column.add_child(MenuUI.gap(40, true))

	var total: int = SaveGame.total_trophies()
	column.add_child(MenuUI.section("TROPHY ROAD   ·   PERMANENT, NEVER RESETS"))
	column.add_child(MenuUI.gap(14, true))
	_road_track = _rail(column, RAIL_ROAD_H)
	var road_row := MenuUI.hbox(0)
	_road_track.add_child(road_row)
	for entry in MenuData.trophy_road():
		road_row.add_child(_milestone(entry, total))
	column.add_child(MenuUI.gap(46, true))

	column.add_child(MenuUI.section("NOBLES PASS   ·   ENDS WITH THE SEASON"))
	column.add_child(MenuUI.gap(14, true))
	_pass_track = _rail(column, RAIL_PASS_H)
	var pass_row := MenuUI.hbox(0)
	_pass_track.add_child(pass_row)
	for tier in MenuData.game.get("passRewards", []):
		pass_row.add_child(_tier_column(tier))
	column.add_child(MenuUI.spacer())
	_scroll_to_progress(total)

func _rail(column: VBoxContainer, height: float) -> ScrollContainer:
	var track := ScrollContainer.new()
	track.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	track.custom_minimum_size = Vector2(0, height)
	track.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.add_child(track)
	return track

# MARK: header

func _header(season: Dictionary) -> HBoxContainer:
	var row := MenuUI.hbox(60)
	var left := MenuUI.vbox(2)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	left.add_child(MenuUI.label("SEASON %d" % int(season.get("number", 1)), 20, MenuUI.GOLD))
	left.add_child(MenuUI.display(str(season.get("name", "")).to_upper(), 56))
	left.add_child(MenuUI.label("%d DAYS LEFT" % int(season.get("endsInDays", 0)), 19,
			MenuUI.TEXT_DIM))
	row.add_child(MenuUI.spacer())

	var per_tier: float = maxf(1.0, float(season.get("tokensPerTier", 500)))
	var progress := MenuUI.vbox(8)
	progress.custom_minimum_size = Vector2(560, 0)
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(progress)
	var head := MenuUI.hbox(10)
	head.add_child(MenuUI.label("TIER %d — TOKENS TO NEXT" % SaveGame.pass_tier, 19,
			MenuUI.TEXT_DIM))
	head.add_child(MenuUI.spacer())
	head.add_child(MenuUI.display("%s / %s" % [MenuUI.fmt(SaveGame.pass_tokens),
			MenuUI.fmt(int(per_tier))], 28, MenuUI.GOLD))
	progress.add_child(head)
	var bar: Panel = MenuUI.bar(16, MenuUI.GOLD)
	progress.add_child(bar)
	MenuUI.set_bar(bar, SaveGame.pass_tokens / per_tier)

	if not SaveGame.pass_premium:
		var unlock: Button = MenuUI.button("UNLOCK PASS", "gold", 28, Vector2(230, 68))
		unlock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unlock.pressed.connect(_unlock_premium)
		row.add_child(unlock)
	else:
		var active: Label = MenuUI.label("PASS ACTIVE", 20, MenuUI.GOLD)
		active.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(active)
	return row

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

# MARK: trophy road

## Entries are `{trophies, reward: {kind, ...}}`; the older flat
## `{trophies, kind, ...}` shape is still accepted so a hand-edited game.json
## from before the split keeps working.
static func _payload(entry: Dictionary) -> Dictionary:
	var nested: Variant = entry.get("reward")
	return nested if nested is Dictionary else entry

func _milestone(entry: Dictionary, total: int) -> Control:
	var goal: int = int(entry.get("trophies", 0))
	var reward: Dictionary = _payload(entry)
	var claim_id := "road:%d" % goal
	var reached: bool = total >= goal
	var claimed: bool = SaveGame.is_claimed(claim_id)

	var cell := MenuUI.vbox(0)
	cell.custom_minimum_size = Vector2(MILESTONE_W, 0)
	cell.add_child(_threshold(MenuUI.fmt(goal), reached))
	cell.add_child(MenuUI.gap(14, true))
	cell.add_child(_reward_label(reward, reached))
	cell.add_child(MenuUI.spacer())
	cell.add_child(_state_control(claimed, reached, func(b: Control) -> void:
		_claim(claim_id, reward, b)))
	cell.add_child(MenuUI.gap(10, true))
	# The rail's own separator: a column rule between milestones, not a box
	# around each one.
	var wrapper := MenuUI.hbox(0)
	wrapper.add_child(cell)
	wrapper.add_child(MenuUI.rule(MenuUI.RULE, true))
	return wrapper

## The number that gates a reward, over the hairline it hangs from. Lit gold
## once it is reached — this is the only thing on the rail that changes colour,
## so a glance down it tells you exactly how far you have got.
func _threshold(text: String, reached: bool) -> VBoxContainer:
	var column := MenuUI.vbox(6)
	var value: Label = MenuUI.display(text, 32, MenuUI.GOLD if reached else MenuUI.TEXT_FAINT)
	column.add_child(value)
	column.add_child(MenuUI.rule(MenuUI.GOLD if reached else MenuUI.RULE))
	return column

func _reward_label(reward: Dictionary, reached: bool) -> Label:
	var l: Label = MenuUI.wrap(MenuUI.display(_reward_name(reward), 26,
			MenuUI.TEXT if reached else MenuUI.TEXT_FAINT))
	l.custom_minimum_size = Vector2(MILESTONE_W - 22, 78)
	return l

func _state_control(claimed: bool, reached: bool, action: Callable) -> Control:
	if claimed:
		return MenuUI.label("CLAIMED", 18, MenuUI.TEXT_FAINT)
	if not reached:
		return MenuUI.label("LOCKED", 18, MenuUI.TEXT_FAINT)
	var claim: Button = MenuUI.button("CLAIM", "gold", 24, Vector2(MILESTONE_W - 30, 54))
	claim.pressed.connect(func() -> void: action.call(claim))
	return claim

# MARK: nobles pass

func _tier_column(tier: Dictionary) -> Control:
	var number: int = int(tier.get("tier", 1))
	var reached: bool = number <= SaveGame.pass_tier
	var cell := MenuUI.vbox(0)
	cell.custom_minimum_size = Vector2(TIER_W, 0)
	cell.add_child(_threshold("T%d" % number, reached))
	cell.add_child(MenuUI.gap(12, true))
	cell.add_child(_pass_cell(tier, "free", number, reached))
	cell.add_child(MenuUI.gap(12, true))
	cell.add_child(_pass_cell(tier, "premium", number, reached))
	cell.add_child(MenuUI.spacer())
	var wrapper := MenuUI.hbox(0)
	wrapper.add_child(cell)
	wrapper.add_child(MenuUI.rule(MenuUI.RULE, true))
	return wrapper

## One lane of one tier. The premium lane is gated on the pass being bought, and
## says so in the lane rather than behind a padlock on the reward.
func _pass_cell(tier: Dictionary, lane: String, number: int, reached: bool) -> Control:
	var reward: Variant = tier.get(lane)
	var column := MenuUI.vbox(4)
	column.custom_minimum_size = Vector2(TIER_W - 20, PASS_CELL_H)
	column.add_child(MenuUI.label(lane, 16,
			MenuUI.GOLD if lane == "premium" else MenuUI.TEXT_FAINT))
	if not (reward is Dictionary):
		column.add_child(MenuUI.label("—", 22, MenuUI.TEXT_FAINT))
		return column
	var data: Dictionary = reward
	var claim_id: String = "pass:%d:%s" % [number, lane]
	var claimed: bool = SaveGame.is_claimed(claim_id)
	var locked: bool = lane == "premium" and not SaveGame.pass_premium
	var live: bool = reached and not locked
	var name_label: Label = MenuUI.wrap(MenuUI.display(_reward_name(data), 22,
			MenuUI.TEXT if live else MenuUI.TEXT_FAINT))
	name_label.custom_minimum_size = Vector2(TIER_W - 24, 56)
	column.add_child(name_label)
	column.add_child(MenuUI.spacer())
	if claimed:
		column.add_child(MenuUI.label("CLAIMED", 16, MenuUI.TEXT_FAINT))
	elif locked:
		column.add_child(MenuUI.label("PASS ONLY", 16, MenuUI.TEXT_FAINT))
	elif reached:
		var claim: Button = MenuUI.button("CLAIM", "gold", 20, Vector2(0, 44))
		claim.pressed.connect(func() -> void: _claim(claim_id, data, claim))
		column.add_child(claim)
	else:
		column.add_child(MenuUI.label("LOCKED", 16, MenuUI.TEXT_FAINT))
	return column

# MARK: rewards

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
		_road_track.scroll_horizontal = int(maxf(0.0, index * (MILESTONE_W + 1.0)))
	if is_instance_valid(_pass_track):
		_pass_track.scroll_horizontal = int(maxf(0.0,
				(SaveGame.pass_tier - 1) * (TIER_W + 1.0)))

func _reopen() -> void:
	menu.push_screen(SeasonScreen.new())
	close_screen()
