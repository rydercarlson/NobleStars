class_name SaveGame
## Persistent player progression (trophies, coins, selections), stored as JSON
## in user://save.json. Statics survive scene changes, same pattern as Session.

const SAVE_PATH := "user://save.json"

## Showdown placement rewards, rank 1..10.
const TROPHY_TABLE: Array[int] = [8, 6, 5, 4, 3, 1, 0, 0, -1, -2]

static var loaded := false
static var coins: int = 0
static var trophies: Dictionary = {}      # kit name -> int
static var selected_kit: String = "Nova"  # always by name, never a kit Dictionary
static var selected_mode: String = "showdown"
static var player_name: String = "Star"
static var music_volume: float = 1.0
static var sfx_volume: float = 1.0

static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	for k in Kits.all():
		trophies[k.name] = 0
	if OS.get_environment("NS3_RESET_SAVE") != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	coins = int(data.get("coins", 0))
	selected_kit = str(data.get("selected_kit", selected_kit))
	selected_mode = str(data.get("selected_mode", selected_mode))
	player_name = str(data.get("player_name", player_name))
	music_volume = clampf(float(data.get("music_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(data.get("sfx_volume", 1.0)), 0.0, 1.0)
	var saved_trophies: Variant = data.get("trophies", {})
	if saved_trophies is Dictionary:
		for kit_name in saved_trophies:
			trophies[str(kit_name)] = int(saved_trophies[kit_name])
	if Kits.named(selected_kit).name.to_lower() != selected_kit.to_lower():
		selected_kit = "Nova"  # saved kit no longer exists

static func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"coins": coins,
		"trophies": trophies,
		"selected_kit": selected_kit,
		"selected_mode": selected_mode,
		"player_name": player_name,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
	}, "\t"))

static func total_trophies() -> int:
	var total := 0
	for kit_name in trophies:
		total += int(trophies[kit_name])
	return total

## Applies end-of-match rewards and persists. rank is 1..10.
static func award_match(kit_name: String, rank: int) -> Dictionary:
	ensure_loaded()
	var delta: int = TROPHY_TABLE[clampi(rank - 1, 0, TROPHY_TABLE.size() - 1)]
	var before: int = int(trophies.get(kit_name, 0))
	trophies[kit_name] = maxi(0, before + delta)
	var earned: int = maxi(2, 22 - 2 * rank)
	coins += earned
	save()
	return {"trophies": int(trophies[kit_name]) - before, "coins": earned}
