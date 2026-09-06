class_name Session
## Carries the menu's choices into the match scene, plus the two helpers both
## scenes need: where a debug screenshot lands, and where it is safe to draw.

static var kit: Dictionary = {}
static var mode: String = "showdown"

## The part of the viewport a CONTROL may use — the whole thing on desktop, and
## on a phone the display's safe area, inset past the notch and the home
## indicator. Lives here rather than in either scene because both need exactly
## these numbers and a second copy is how two answers to one question drift.
##
## Measured on the iPhone 15 this develops against (2556x1179 landscape, 3x):
## the safe area gives up 177 device px on each side and 63 at the bottom, so
## 13.9% of the width is not addressable by chrome. That is a real constraint
## and not a thing to fight — but it applies to CHROME ONLY. The picture itself
## should run edge to edge and under the island; letterboxing everything into
## this rect is what made the menu stop short of the screen (todo 1.2).
static func safe_rect(viewport: Viewport) -> Rect2:
	var visible: Vector2 = viewport.get_visible_rect().size
	var full := Rect2(Vector2.ZERO, visible)
	if not OS.has_feature("mobile"):
		return full
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var window: Vector2i = DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0:
		return full
	# The safe area is reported in WINDOW pixels and the caller works in
	# viewport pixels, which differ by the stretch scale.
	var k := Vector2(visible.x / float(window.x), visible.y / float(window.y))
	var rect: Rect2 = full.intersection(Rect2(Vector2(safe.position) * k,
			Vector2(safe.size) * k))
	# Some platforms report the whole display rather than the window's safe
	# area; anything implausibly small is ignored rather than obeyed.
	if rect.size.x < visible.x * 0.5 or rect.size.y < visible.y * 0.5:
		return full
	return rect

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
