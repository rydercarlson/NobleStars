class_name MenuData
## Content for the menu, read from the web menu's own data files:
## res://data/brawlers.json and res://data/game.json are byte-for-byte the
## files in web-menu/data/, so copy, modes, shop, news, club and pass rewards
## are edited in one place and both builds follow.
##
## The one thing the JSON is NOT trusted for is balance: every brawler entry is
## merged with its live Kits dictionary, so health/damage/speed/range on the
## detail screen are whatever kits.gd says today. A kit with no JSON entry
## (currently Nova) still shows up — its card is synthesised from kits.gd.

const BRAWLERS_PATH := "res://data/brawlers.json"
const GAME_PATH := "res://data/game.json"
const PORTRAIT_DIR := "res://assets/menu/portraits/"
const CARD_DIR := "res://assets/menu/cards/"
const DECOR_DIR := "res://assets/menu/decor/"

static var loaded := false
static var brawlers: Array = []        # merged entries, roster order
static var rarities: Dictionary = {}
static var game: Dictionary = {}

static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	var bd: Dictionary = _read(BRAWLERS_PATH)
	game = _read(GAME_PATH)
	rarities = bd.get("rarities", {})
	if rarities.is_empty():
		rarities = {"rare": {"label": "Rare", "color": "#6df26a", "dark": "#1f7a2c"}}
	var by_id: Dictionary = {}
	var entries: Array = bd.get("brawlers", [])
	for e in entries:
		if e is Dictionary and e.has("id"):
			by_id[str(e.id)] = e
	# Roster order follows Kits.all(): the menu lists what the game can play.
	for kit in Kits.all():
		var id: String = str(kit.name).to_lower()
		brawlers.append(_merge(by_id.get(id, {}), kit, id))

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("MenuData: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## One brawler card/detail entry: JSON copy where there is any, kits.gd for
## everything the game actually simulates.
static func _merge(entry: Dictionary, kit: Dictionary, id: String) -> Dictionary:
	var weapon: Dictionary = kit.get("weapon", {})
	var hint_value: Variant = entry.get("unlockHint", "")
	var out: Dictionary = {
		"id": id,
		"kit_name": str(kit.name),
		"name": str(entry.get("name", str(kit.name).to_upper())),
		"title": str(entry.get("title", str(kit.get("role", "Brawler")))),
		"rarity": str(entry.get("rarity", "rare")),
		"role": str(entry.get("role", kit.get("role", ""))),
		"description": str(entry.get("description", kit.get("desc", ""))),
		"pins": int(entry.get("pins", 0)),
		"unlock_hint": "" if hint_value == null else str(hint_value),
		"color": kit.get("color", Color.WHITE),
		"has_model": kit.has("model"),
		"stats": {
			"health": int(kit.get("max_health", Kits.HEALTH_NORMAL)),
			"damage": int(weapon.get("damage", 0)),
			"speed": speed_label(float(kit.get("move_speed", Kits.SPEED_NORMAL))),
			"range": range_label(float(weapon.get("range", 4.5 * Kits.TILE))),
			"reload": reload_label(float(kit.get("reload", Kits.RELOAD_NORMAL))),
		},
	}
	# v0.5 loadout copy, straight from the JSON — there is no Kits counterpart
	# because the game does not simulate gadgets, gears, Star Powers or
	# Hypercharges yet. A kit with no JSON entry (Nova, Ayaan) gets four empty
	# strings, and the detail screen draws only the rows that are filled.
	out["loadout"] = {
		"gadget": str(entry.get("gadget", "")),
		"star_power": str(entry.get("starPower", "")),
		"gear": str(entry.get("gear", "")),
		"hypercharge": str(entry.get("hypercharge", "")),
	}
	var atk: Dictionary = entry.get("attack", {})
	out["attack"] = {
		"name": str(atk.get("name", out.role if out.role != "" else "Attack")),
		"text": str(atk.get("text", kit.get("desc", ""))),
	}
	var sup: Dictionary = entry.get("super", {})
	out["super"] = {
		"name": str(sup.get("name", "Super")),
		"text": str(sup.get("text", kit.get("super_desc", ""))),
	}
	if out.unlock_hint == "" and not starting_brawlers().has(id):
		out.unlock_hint = "Found in Brawler Drops"
	return out

static func brawler(id: String) -> Dictionary:
	ensure_loaded()
	for b in brawlers:
		if str(b.id) == id.to_lower():
			return b
	return brawlers[0] if brawlers.size() > 0 else {}

static func rarity_of(b: Dictionary) -> Dictionary:
	ensure_loaded()
	var r: Variant = rarities.get(str(b.get("rarity", "rare")))
	if r is Dictionary:
		return r
	return {"label": "Rare", "color": "#6df26a", "dark": "#1f7a2c"}

## Portrait texture rendered from the GLB (web-menu/tools/portraits.mjs), or
## null for a kit that has no model yet — callers draw a colour chip instead.
static func portrait(id: String) -> Texture2D:
	var path: String = PORTRAIT_DIR + id + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## Full-body card art, resolved by id the way portraits are; null for a kit
## that has none yet so callers can fall back to the portrait.
static func card_art(id: String) -> Texture2D:
	var path: String = CARD_DIR + id + ".webp"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## A shop skin's own illustration, named by its `art` key in game.json and
## drawn from the decor folder. Only two of the five skins have been drawn, so
## this falls back to the brawler's plain portrait — which is what the card used
## to show unconditionally, art or no art. Give a skin an `art` key the moment
## its file lands and the card picks it up.
static func skin_art(skin: Dictionary) -> Texture2D:
	var art: String = str(skin.get("art", ""))
	if art != "":
		var path: String = DECOR_DIR + art + ".webp"
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return portrait(str(skin.get("brawler", "")))

## Whether this skin has art of its own rather than a portrait standing in —
## the card frames the two differently.
static func has_skin_art(skin: Dictionary) -> bool:
	var art: String = str(skin.get("art", ""))
	return art != "" and ResourceLoader.exists(DECOR_DIR + art + ".webp")

static func modes() -> Array:
	ensure_loaded()
	return game.get("modes", [])

static func mode(id: String) -> Dictionary:
	for m in modes():
		if str(m.id) == id:
			return m
	var all: Array = modes()
	return all[0] if all.size() > 0 else {}

static func season() -> Dictionary:
	ensure_loaded()
	return game.get("season", {"number": 1, "name": "SEASON", "tokensPerTier": 500, "maxTier": 60, "endsInDays": 30})

static func trophy_road() -> Array:
	ensure_loaded()
	return game.get("trophyRoad", [])

static func starting_brawlers() -> Array:
	ensure_loaded()
	return game.get("startingBrawlers", ["nova"])

## Showdown and Nobles Cup are built; every other mode selects fine but says so
## on PLAY.
static func mode_playable(id: String) -> bool:
	return id == "showdown_solo" or id == "nobles_cup"

## Menu mode id -> the string main.gd's start_match hook branches on.
static func engine_mode(id: String) -> String:
	if id.begins_with("showdown"):
		return "showdown"
	return "cup" if id == "nobles_cup" else id

static func speed_label(v: float) -> String:
	if v <= Kits.SPEED_VERY_SLOW + 0.01:
		return "Very Slow"
	if v <= Kits.SPEED_SLOW + 0.01:
		return "Slow"
	if v <= Kits.SPEED_NORMAL + 0.01:
		return "Normal"
	if v <= Kits.SPEED_FAST + 0.01:
		return "Fast"
	return "Very Fast"

static func reload_label(v: float) -> String:
	if v >= Kits.RELOAD_VERY_SLOW - 0.01:
		return "Very Slow"
	if v >= Kits.RELOAD_SLOW - 0.01:
		return "Slow"
	if v >= Kits.RELOAD_NORMAL - 0.01:
		return "Normal"
	if v >= Kits.RELOAD_FAST - 0.01:
		return "Fast"
	return "Very Fast"

## Range tiers as CHARACTER_BUILDING.md names them, from metres.
static func range_label(metres: float) -> String:
	var tiles: float = metres / Kits.TILE
	if tiles < 2.0:
		return "Very Short"
	if tiles < 3.0:
		return "Short"
	if tiles < 4.8:
		return "Medium"
	if tiles <= 5.5:
		return "Long"
	return "Very Long"
