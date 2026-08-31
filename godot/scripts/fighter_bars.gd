class_name FighterBars
extends Control
## Screen-space health + ammo bars for every fighter, drawn as flat 2D over
## the 3D view (no billboards — nothing rotates or overlaps in 3D).

const BAR_W := 56.0
const BAR_H := 7.0
const PIP_H := 4.0
const PIP_GAP := 2.0
const HEAD_OFFSET := Vector3(0, 2.15, 0)

var game: Node3D   # main scene; provides fighters + cam

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if game == null or game.cam == null:
		return
	var cam: Camera3D = game.cam
	for f in game.fighters:
		if not is_instance_valid(f) or f.is_dead() or not f.visible:
			continue
		var world: Vector3 = f.global_position + HEAD_OFFSET
		if cam.is_position_behind(world):
			continue
		var p: Vector2 = cam.unproject_position(world)
		var left := p.x - BAR_W / 2.0

		# Health bar: dark back, kit-colored fill draining from the right.
		draw_rect(Rect2(left - 1, p.y - 1, BAR_W + 2, BAR_H + 2), Color(0.08, 0.08, 0.08, 0.85))
		var frac: float = clamp(float(f.health) / float(f.max_health), 0.0, 1.0)
		draw_rect(Rect2(left, p.y, BAR_W * frac, BAR_H), f.kit.color)

		# Ammo pips underneath, each filling left-to-right.
		var pip_w := (BAR_W - 2.0 * PIP_GAP) / 3.0
		var pip_y := p.y + BAR_H + 3.0
		for i in 3:
			var px := left + i * (pip_w + PIP_GAP)
			draw_rect(Rect2(px, pip_y, pip_w, PIP_H), Color(0.08, 0.08, 0.08, 0.7))
			var pf: float = clamp(f.ammo - i, 0.0, 1.0)
			if pf > 0.02:
				draw_rect(Rect2(px, pip_y, pip_w * pf, PIP_H), Color(1.0, 0.65, 0.1, 0.95))
