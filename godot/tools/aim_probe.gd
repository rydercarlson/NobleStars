extends SceneTree
## Diagnostic: drive the player's aiming code with no hands on the sticks. Run:
##   NS3_MODE=showdown /Applications/Godot.app/Contents/MacOS/Godot --path godot \
##       --headless --script res://tools/aim_probe.gd
##   NS3_MODE=cup ... (same line) — adds the carrier's kick plan
##
## The aiming region is the one part of main.gd that a headless match never
## touches: `_update_aim_indicator` and `_auto_aim_fire` both hang off a touch
## stick, so a match played by bots exercises none of it and a parse-clean run
## proves nothing about it. This calls the entry points directly on a live
## match — the tap plan the indicator and the shot share, the indicator's own
## drawing, and Nobles Cup's kick plan — and prints what each one decided,
## alongside every candidate the picker had to choose between.
##
## It reports, it does not judge: "Kovacs picked the wounded one" is the kind of
## answer only a person can grade. What it DOES catch is the failure this file
## exists for, which is any of them erroring or silently returning nothing.

## Past the 7s pre-match and far enough into PLAYING for the roster to have
## found each other — at spawn everybody is alone and every answer is "nothing
## in reach", which tests nothing. NS3_AIM_AT=<sec> overrides it.
var _settle := float(OS.get_environment("NS3_AIM_AT")) \
		if OS.get_environment("NS3_AIM_AT") != "" else 40.0

var _game: Node = null
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	var packed: PackedScene = load("res://game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)

func _process(delta: float) -> bool:
	if _done:
		return true
	_elapsed += delta
	if _elapsed < _settle:
		return false
	_done = true
	_report()
	quit()
	return true

func _report() -> void:
	var player: Fighter = _game.player
	if player == null or not is_instance_valid(player):
		print("[aim] no player — nothing to probe")
		return
	print("[aim] %s at %s, phase %d, %d fighters"
			% [player.kit.name, _fmt(player.global_position), _game.phase,
			_game.fighters.size()])

	for use_super in [false, true]:
		var weapon: Dictionary = player.kit["super"] if use_super else player.kit.weapon
		var label := "super " if use_super else "attack"
		var plan: Dictionary = _game._tap_plan(weapon, use_super)
		var who := "-"
		if plan.target != null and is_instance_valid(plan.target):
			who = str(plan.target.name)
			if plan.target is Fighter:
				who = "%s %d/%d hp" % [(plan.target as Fighter).kit.name,
						(plan.target as Fighter).health, (plan.target as Fighter).max_health]
		print("[aim] %s tap -> %-6s  target %s  dir %s"
				% [label, plan.kind, who, _fmt(plan.dir)])
		# Every candidate in reach, so a pick can be read rather than guessed at.
		# The rule is nearest-visible, so the answer above should be the closest
		# row below with `seen y` — and a run where every row says `seen n` is a
		# visibility problem rather than a picker one.
		if use_super:
			var reach: float = float(weapon.range) * 1.1
			for f: Fighter in _game.fighters:
				if f == player or f.is_dead() or player.is_ally(f):
					continue
				var d: float = player.global_position.distance_to(f.global_position)
				if d >= reach:
					continue
				print("[aim]    %-8s %5.1f m  %3d%% hp  seen %s"
						% [f.kit.name, d, int(100.0 * f.health / maxf(f.max_health, 1)),
						"y" if _game.can_see(player, f, _game._lobbed(weapon)) else "n"])
		# The indicator's own path, which is where a drawing bug would live. A tap
		# deliberately draws nothing at all now, so this is the DRAG indicator at
		# full deflection along the player's facing — the same thing
		# NS3_AIM_SHOW holds on screen.
		var facing := Vector2(player.facing.x, player.facing.z).normalized()
		_game._draw_weapon_aim(_game.aim_mesh.mesh, facing, use_super)
	print("[aim] indicator drew %d surfaces" % (_game.aim_mesh.mesh as ImmediateMesh).get_surface_count())

	if _game.cup != null:
		var cup = _game.cup
		cup.ball.pick_up(player)
		for powerful in [false, true]:
			var kp: Dictionary = cup.kick_plan(player, powerful)
			print("[aim] kick%s -> %-5s at %s (%.1f m)"
					% ["+super" if powerful else "      ", kp.kind, _fmt(kp.at),
					player.global_position.distance_to(kp.at)])
			_game._draw_kick_aim(_game.aim_mesh.mesh, Vector2.ZERO, powerful, false)
		cup.ball.place(_game.arena.centre(), _game.now)

func _fmt(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [v.x, v.z]
