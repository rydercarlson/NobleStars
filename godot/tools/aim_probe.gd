extends SceneTree
## Diagnostic: drive the player's aiming code with no hands on the sticks. Run:
##   NS3_MODE=showdown /Applications/Godot.app/Contents/MacOS/Godot --path godot \
##       --headless --script res://tools/aim_probe.gd
##   NS3_MODE=cup ... (same line) — adds the carrier's kick plan
##
## The aiming region is the one part of main.gd that a headless match never
## touches: `_update_aim_indicator` and `_auto_aim_fire` both hang off a touch
## stick, so a match played by bots exercises none of it and a parse-clean run
## proves nothing about it. This calls the four entry points directly on a live
## match — the Super's scored picker, the tap plan the indicator and the shot
## share, the indicator's own drawing, and Nobles Cup's kick plan — and prints
## what each one decided.
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
		# Every candidate the Super picker considered, with its score, so a bad
		# pick can be read rather than guessed at.
		if use_super:
			var reach: float = float(weapon.range) * 1.1
			for f: Fighter in _game.fighters:
				if f == player or f.is_dead() or player.is_ally(f):
					continue
				var d: float = player.global_position.distance_to(f.global_position)
				if d >= reach:
					continue
				print("[aim]    %-8s %5.1f m  %3d%% hp  seen %s  odds %.2f  score %.3f"
						% [f.kit.name, d, int(100.0 * f.health / maxf(f.max_health, 1)),
						"y" if _game.can_see(player, f, _game._lobbed(weapon)) else "n",
						_game._connect_odds(weapon, f, d),
						_game._super_target_score(weapon, f, d, reach)])
		# The indicator's own path, which is where a drawing bug would live.
		_game._draw_tap_aim(_game.aim_mesh.mesh, use_super)
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

	_scenarios(player)

## Staged comparisons against the rule that was there before. A live match can be
## read but it cannot be arranged, and the whole claim being tested is about the
## cases where nearest and best DISAGREE — a bystander who drifted a metre closer
## than the fighter you have been trading with, or a sprinter at the far end of
## the range that a thin projectile will never catch. Both are arranged here.
func _scenarios(player: Fighter) -> void:
	var weapon: Dictionary = player.kit["super"]
	var others: Array = []
	for f: Fighter in _game.fighters:
		if f != player and not f.is_dead() and not player.is_ally(f):
			others.append(f)
	if others.size() < 2:
		print("[aim] fewer than two live opponents — no staged comparison")
		return
	var near: Fighter = others[0]
	var far: Fighter = others[1]
	var lane := _open_lane(player)
	if lane == Vector3.ZERO:
		print("[aim] no open lane at the player — no staged comparison")
		return

	_stage(player, near, lane, 4.0, 1.0)
	_stage(player, far, lane, 6.5, 0.22)
	player.note_engagement(far, _game.now)
	_compare("wounded + engaged at 6.5 m vs full health at 4.0 m", player, weapon)

	player.engaged_with = null
	_stage(player, near, lane, 4.0, 1.0)
	_stage(player, far, lane, float(weapon.range) * 1.05, 0.22)
	far.velocity = lane.cross(Vector3.UP) * 6.0     # sprinting across the lane
	_compare("wounded sprinter at max range vs full health at 4.0 m", player, weapon)

func _stage(player: Fighter, f: Fighter, lane: Vector3, at: float, hp: float) -> void:
	f.global_position = player.global_position + lane * at
	f.health = maxi(1, int(f.max_health * hp))
	f.velocity = Vector3.ZERO
	f.force_update_transform()

func _compare(title: String, player: Fighter, weapon: Dictionary) -> void:
	var nearest: Fighter = _game.nearest_visible_enemy(player,
			float(weapon.range) * 1.1, _game._lobbed(weapon))
	var scored: Fighter = _game._super_target(weapon)
	print("[aim] %s" % title)
	print("[aim]    nearest picks %s   scored picks %s"
			% [_who(player, nearest), _who(player, scored)])

func _who(player: Fighter, f: Fighter) -> String:
	if f == null:
		return "nobody"
	return "%s (%.1f m, %d%% hp)" % [f.kit.name,
			player.global_position.distance_to(f.global_position),
			int(100.0 * f.health / maxf(f.max_health, 1))]

## A direction out of the player's tile with nothing solid in it for a dozen
## metres, so a staged fighter is neither inside a wall nor behind one.
func _open_lane(player: Fighter) -> Vector3:
	for i in 16:
		var a := TAU * i / 16.0
		var dir := Vector3(cos(a), 0, sin(a))
		var clear := true
		for step in range(1, 13):
			if _game.arena.blocks_movement(player.global_position + dir * float(step)):
				clear = false
				break
		if clear:
			return dir
	return Vector3.ZERO

func _fmt(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [v.x, v.z]
