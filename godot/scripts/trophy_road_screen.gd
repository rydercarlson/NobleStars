class_name TrophyRoadScreen
extends Control
## Trophy Road: milestone track driven by total trophies. Rewards are
## display-only teasers for now.

const MILESTONES: Array = [
	{"at": 0, "reward": "WELCOME!"},
	{"at": 25, "reward": "COINS +50"},
	{"at": 50, "reward": "MEGA BOX"},
	{"at": 100, "reward": "NEW FIGHTER?"},
	{"at": 200, "reward": "COINS +200"},
	{"at": 400, "reward": "EPIC SKIN"},
	{"at": 800, "reward": "LEGEND STATUS"},
]

var menu: MenuShell
var header: Label
var progress: ProgressBar
var track: HBoxContainer

func _ready() -> void:
	var back := UIKit.back_button()
	back.pressed.connect(func() -> void: menu.show_screen("lobby"))
	add_child(back)

	header = UIKit.label("", 40, UIKit.GOLD)
	header.anchor_right = 1.0
	header.offset_top = 16
	header.offset_bottom = 72
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(header)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 20)
	add_child(mid)
	mid.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	mid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mid.grow_vertical = Control.GROW_DIRECTION_BOTH

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = MILESTONES[MILESTONES.size() - 1].at
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 14)
	progress.add_theme_stylebox_override("background", UIKit.flat(UIKit.NAVY_DEEP, 7, 0, UIKit.FAINT, 2))
	progress.add_theme_stylebox_override("fill", UIKit.flat(UIKit.GOLD, 7, 0, UIKit.FAINT, 2))
	mid.add_child(progress)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1140, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)

	track = HBoxContainer.new()
	track.add_theme_constant_override("separation", 12)
	scroll.add_child(track)

func refresh() -> void:
	var total: int = SaveGame.total_trophies()
	header.text = "TROPHY ROAD — ★ %d" % total
	progress.value = total
	for child in track.get_children():
		child.queue_free()
	for m in MILESTONES:
		var reached: bool = total >= int(m.at)
		var panel := PanelContainer.new()
		var border: Color = UIKit.GOLD if reached else UIKit.FAINT
		var bg: Color = UIKit.NAVY_PANEL if reached else UIKit.NAVY_DEEP
		panel.add_theme_stylebox_override("panel", UIKit.flat(bg, 14, 3 if reached else 1, border))
		track.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		box.custom_minimum_size = Vector2(128, 180)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(box)
		var at := UIKit.label("★ %d" % int(m.at), 24, UIKit.GOLD if reached else UIKit.MUTED)
		at.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(at)
		var reward := UIKit.label(str(m.reward), 16, Color.WHITE if reached else UIKit.MUTED)
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward.custom_minimum_size = Vector2(118, 0)
		box.add_child(reward)
		var state := UIKit.label("REACHED" if reached else "LOCKED", 13, UIKit.GOLD if reached else UIKit.FAINT)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(state)
