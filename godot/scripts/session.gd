class_name Session
## Carries the menu's choices into the match scene, and the one debug helper
## both scenes need.

static var kit: Dictionary = {}
static var mode: String = "showdown"

## Where a debug screenshot actually lands. NS3_SHOTS and NS3_MENU_SHOT both
## take a path from the environment and hand it straight to save_png, and a
## RELATIVE path resolves against res:// — so `NS3_SHOTS=shot:1` wrote
## shot_1.png into the PROJECT, where the next --import swept it up as a game
## asset that then had to be hunted down before committing. An absolute path
## (or an explicit user://) is honoured as given; anything else is sent to
## user:// instead, which is never scanned by the importer.
static func shot_path(path: String) -> String:
	if path.begins_with("/") or path.begins_with("user://") or path.begins_with("res://"):
		return path
	return "user://" + path
