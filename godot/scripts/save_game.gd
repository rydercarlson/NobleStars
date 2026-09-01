class_name SaveGame
## Persistent player progression, stored as JSON in user://save.json. Statics
## survive scene changes, same pattern as Session.
##
## This is the native version of the web menu's localStorage save (web-menu/
## src/state.js): same fields, same defaults, but per-fighter trophies come
## from real matches rather than a demo number, and pass tokens are earned by
## playing instead of a "collect tokens" button.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3

## Showdown placement rewards, rank 1..10.
const TROPHY_TABLE: Array[int] = [8, 6, 5, 4, 3, 1, 0, 0, -1, -2]

## One-off starting grant, matching web-menu/src/state.js defaults, so the shop
## and the pass are not dead on a brand-new save.
const START_COINS := 1250
const START_GEMS := 90
const START_STAR_POINTS := 120

static var loaded := false
static var coins: int = 0
static var gems: int = 0
static var star_points: int = 0
static var power_points: int = 0
static var bling: int = 0
static var dawg_treats: int = 0
static var level: int = 6
static var matches: int = 0
static var trophies: Dictionary = {}      # kit name -> int
static var power: Dictionary = {}         # brawler id -> power level (1+)
static var unlocked: Dictionary = {}      # brawler id -> bool
static var claimed: Dictionary = {}       # shop / pass / mail reward id -> true
static var read_mail: Dictionary = {}     # inbox id -> true
static var club_chat: Array = []          # [{who, text}, ...]
static var pass_tier: int = 1
static var pass_tokens: int = 0
static var pass_premium: bool = false
static var selected_kit: String = "Tony"  # always by name, never a kit Dictionary
static var selected_mode: String = "showdown_solo"
static var player_name: String = "GUEST"
static var music_on: bool = true
static var sfx_on: bool = true
static var hints_on: bool = true
static var first_run: bool = true

static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	MenuData.ensure_loaded()
	var starters: Array = MenuData.starting_brawlers()
	for k in Kits.all():
		trophies[k.name] = 0
		var id: String = str(k.name).to_lower()
		unlocked[id] = starters.has(id)
		power[id] = 1
	if OS.get_environment("NS3_RESET_SAVE") != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		_grant_start()
		_ensure_selected_unlocked()
		return
	if not FileAccess.file_exists(SAVE_PATH):
		_grant_start()
		_ensure_selected_unlocked()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var save_version: int = int(data.get("version", 1))
	coins = int(data.get("coins", 0))
	gems = int(data.get("gems", 0))
	star_points = int(data.get("star_points", 0))
	power_points = int(data.get("power_points", 0))
	bling = int(data.get("bling", 0))
	dawg_treats = int(data.get("dawg_treats", 0))
	level = int(data.get("level", level))
	matches = int(data.get("matches", 0))
	selected_kit = str(data.get("selected_kit", selected_kit))
	selected_mode = str(data.get("selected_mode", selected_mode))
	player_name = str(data.get("player_name", player_name))
	pass_tier = maxi(1, int(data.get("pass_tier", 1)))
	pass_tokens = maxi(0, int(data.get("pass_tokens", 0)))
	pass_premium = bool(data.get("pass_premium", false))
	music_on = bool(data.get("music_on", true))
	sfx_on = bool(data.get("sfx_on", true))
	hints_on = bool(data.get("hints_on", true))
	first_run = bool(data.get("first_run", true))
	_merge_ints(trophies, data.get("trophies", {}))
	_merge_ints(power, data.get("power", {}))
	_merge_bools(unlocked, data.get("unlocked", {}))
	_merge_bools(claimed, data.get("claimed", {}))
	_merge_bools(read_mail, data.get("read_mail", {}))
	var chat: Variant = data.get("club_chat", [])
	if chat is Array:
		club_chat = chat
	# v1 saves predate the menu economy and used the engine's mode id.
	if save_version < 2:
		_grant_start()
		if selected_mode == "showdown":
			selected_mode = "showdown_solo"
	# Before Trophy Road, native saves gave every fighter away at startup.
	# Migrate once so those saves participate in the new unlock progression.
	if save_version < 3:
		for id in unlocked:
			unlocked[id] = starters.has(str(id))
		selected_kit = "Tony"
	_ensure_selected_unlocked()
	if save_version < SAVE_VERSION:
		save()

static func _merge_ints(dst: Dictionary, src: Variant) -> void:
	if not src is Dictionary:
		return
	var d: Dictionary = src
	for k in d:
		dst[str(k)] = int(d[k])

static func _merge_bools(dst: Dictionary, src: Variant) -> void:
	if not src is Dictionary:
		return
	var d: Dictionary = src
	for k in d:
		dst[str(k)] = bool(d[k])

## Keeps `selected_kit` on a fighter that exists and is actually owned. The
## fallback has to be resolved, never a hardcoded name: whoever it named would
## itself be locked on a fresh save, which is how the lobby ended up opening on
## a padlocked Tony while Nova — the only starter — sat unselected.
static func _ensure_selected_unlocked() -> void:
	if Kits.named(selected_kit).name.to_lower() == selected_kit.to_lower() \
			and is_unlocked(selected_kit):
		return
	for k in Kits.all():
		if is_unlocked(str(k.name)):
			selected_kit = str(k.name)
			return
	selected_kit = str(Kits.all()[0].name)  # nothing owned: fail to the roster head

static func _grant_start() -> void:
	coins = maxi(coins, START_COINS)
	gems = maxi(gems, START_GEMS)
	star_points = maxi(star_points, START_STAR_POINTS)

static func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"coins": coins,
		"gems": gems,
		"star_points": star_points,
		"power_points": power_points,
		"bling": bling,
		"dawg_treats": dawg_treats,
		"level": level,
		"matches": matches,
		"trophies": trophies,
		"power": power,
		"unlocked": unlocked,
		"claimed": claimed,
		"read_mail": read_mail,
		"club_chat": club_chat,
		"pass_tier": pass_tier,
		"pass_tokens": pass_tokens,
		"pass_premium": pass_premium,
		"selected_kit": selected_kit,
		"selected_mode": selected_mode,
		"player_name": player_name,
		"music_on": music_on,
		"sfx_on": sfx_on,
		"hints_on": hints_on,
		"first_run": first_run,
	}, "\t"))

static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	loaded = false
	coins = 0
	gems = 0
	star_points = 0
	power_points = 0
	bling = 0
	dawg_treats = 0
	matches = 0
	trophies = {}
	power = {}
	unlocked = {}
	claimed = {}
	read_mail = {}
	club_chat = []
	pass_tier = 1
	pass_tokens = 0
	pass_premium = false
	selected_kit = "Tony"
	selected_mode = "showdown_solo"
	player_name = "GUEST"
	music_on = true
	sfx_on = true
	hints_on = true
	first_run = true
	ensure_loaded()
	save()

static func total_trophies() -> int:
	var total := 0
	for kit_name in trophies:
		total += int(trophies[kit_name])
	return total

# MARK: brawler-id helpers (the menu addresses fighters by lowercase id)

static func brawler_trophies(id: String) -> int:
	return int(trophies.get(Kits.named(id).name, 0))

static func brawler_power(id: String) -> int:
	return maxi(1, int(power.get(id.to_lower(), 1)))

static func set_brawler_power(id: String, value: int) -> void:
	power[id.to_lower()] = maxi(1, value)

static func is_unlocked(id: String) -> bool:
	return bool(unlocked.get(id.to_lower(), false))

static func unlock(id: String) -> void:
	unlocked[id.to_lower()] = true

static func unlock_all_brawlers() -> void:
	for brawler in MenuData.brawlers:
		unlocked[str(brawler.get("id", "")).to_lower()] = true
	save()

static func all_brawlers_unlocked() -> bool:
	for brawler in MenuData.brawlers:
		if not is_unlocked(str(brawler.get("id", ""))):
			return false
	return true

static func is_claimed(id: String) -> bool:
	return bool(claimed.get(id, false))

static func claim(id: String) -> void:
	claimed[id] = true

static func unread_mail() -> int:
	var n := 0
	for m in MenuData.game.get("inbox", []):
		if bool(m.get("unread", false)) and not bool(read_mail.get(str(m.id), false)):
			n += 1
	return n

static func spend(currency: String, price: int) -> bool:
	if currency == "free" or price <= 0:
		return true
	if not can_afford(currency, price):
		return false
	if currency == "coins":
		coins -= price
	elif currency == "gems":
		gems -= price
	save()
	return true

static func can_afford(currency: String, price: int) -> bool:
	if currency == "free" or price <= 0:
		return true
	if currency == "coins":
		return coins >= price
	if currency == "gems":
		return gems >= price
	return true

static func grant(kind: String, amount: int) -> void:
	match kind:
		"coins":
			coins += amount
		"gems":
			gems += amount
		"star_points":
			star_points += amount
		"power_points":
			power_points += amount
		"bling":
			bling += amount
		"dawg_treat":
			dawg_treats += amount
	save()

## Adds pass tokens, rolling tiers over. Returns how many tiers were gained.
static func add_pass_tokens(amount: int) -> int:
	var season: Dictionary = MenuData.season()
	var per_tier: int = maxi(1, int(season.get("tokensPerTier", 500)))
	var max_tier: int = int(season.get("maxTier", 60))
	pass_tokens += amount
	var gained := 0
	while pass_tokens >= per_tier and pass_tier < max_tier:
		pass_tokens -= per_tier
		pass_tier += 1
		gained += 1
	if pass_tier >= max_tier:
		pass_tokens = mini(pass_tokens, per_tier)
	return gained

## Applies end-of-match rewards and persists. rank is 1..10.
static func award_match(kit_name: String, rank: int) -> Dictionary:
	ensure_loaded()
	var delta: int = TROPHY_TABLE[clampi(rank - 1, 0, TROPHY_TABLE.size() - 1)]
	var before: int = int(trophies.get(kit_name, 0))
	trophies[kit_name] = maxi(0, before + delta)
	var earned: int = maxi(2, 22 - 2 * rank)
	coins += earned
	matches += 1
	# A match is worth tokens on the Nobles Pass — placing well is worth more.
	var tokens: int = maxi(40, 180 - 12 * rank)
	var tiers: int = add_pass_tokens(tokens)
	save()
	return {
		"trophies": int(trophies[kit_name]) - before,
		"coins": earned,
		"tokens": tokens,
		"tiers": tiers,
	}
