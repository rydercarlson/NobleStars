extends SceneTree
## Diagnostic: render every combat sound in MenuAudio's table and report its
## length and peak. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --path godot --headless \
##       --script res://tools/sfx_probe.gd
##
## This exists because `MenuAudio._render` falls through to "click" for a name
## it does not know, so a typo at a call site does not fail — it plays a menu
## click in the middle of a firefight and is easy to miss. A sound whose buffer
## is exactly the length of "click" never had an entry of its own.
##
## Add a name here whenever you add one to the table.

const NAMES := [
	"shot_shotgun", "shot_single", "shot_lob", "shot_button", "shot_boomerang",
	"shot_sack", "shot_curve", "melee_swing", "shockwave",
	"impact", "melee_hit", "box_break", "wall_break",
	"super_ready", "super_fire", "elimination", "cube_pickup", "gas_tick",
	"low_health", "reload_tick", "empty_click",
	"count_beep", "count_go", "victory", "defeat",
	"cup_kick", "cup_goal", "cup_whistle",
]

## Anything quieter never registers over the music; anything louder clips once
## two of them land on the same frame.
const QUIET := 0.02
const LOUD := 1.6

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var audio := MenuAudio.new()
	root.add_child(audio)
	var click: PackedFloat32Array = audio._render("click")
	var bad := 0
	for sound_name: String in NAMES:
		var buf: PackedFloat32Array = audio._render(sound_name)
		var peak := 0.0
		for v in buf:
			peak = maxf(peak, absf(v))
		var note := ""
		if buf.size() == click.size():
			note = "  <-- NO ENTRY, fell through to click"
		elif buf.is_empty() or peak < QUIET:
			note = "  <-- SILENT"
		elif peak > LOUD:
			note = "  <-- CLIPS"
		if note != "":
			bad += 1
		print("%-15s %6d samples  %5.2fs  peak %.2f%s"
				% [sound_name, buf.size(), float(buf.size()) / MenuAudio.RATE, peak, note])
	print("\n%d of %d sounds have a problem" % [bad, NAMES.size()])
	quit(1 if bad > 0 else 0)
	return true
