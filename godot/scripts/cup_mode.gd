class_name CupMode
extends Node
## Nobles Cup rules: 3v3 on the pitch, first to two goals or ahead when the
## clock runs out. Death is a three-second setback rather than the end of your
## match, and a tie at full time goes to overtime with the walls levelled.
##
## Everything mode-specific lives here so main.gd's match loop stays the
## Showdown one it has always been: main calls build_match(), tick() and
## on_death(), and asks frozen() whether input should be held. Nothing in this
## file runs unless Session.mode is "cup".

const TEAM_SIZE := 3
const GOALS_TO_WIN := 2
const MATCH_SECONDS := 150.0
const OVERTIME_SECONDS := 60.0
const RESPAWN_SECONDS := 3.0
## Kickoff hold, long enough to read the score and see where the ball is.
const KICKOFF_FREEZE := 2.0
## How long the camera stays on the goal that was just conceded. Deliberately
## shorter than KICKOFF_FREEZE, so the view is already back on the player by the
## time input is handed over rather than racing there as play restarts.
const GOAL_CAMERA_HOLD := 1.35
## How far back toward the centre spot the goal shot is framed, 0..1.
const GOAL_CAMERA_INSET := 0.3
## How close a bot gets before it shoots, and the reach a tap-to-kick treats as
## "on goal". Comfortably inside Ball.kick_range() so a shot arrives with pace
## left; a Super Shot multiplies both. A bot that fires the moment the goal is
## merely reachable turns every clearance into a shot on target — the first
## build ran a whole match out in thirteen seconds that way. A shot has to be
## carried into range; anything longer comes out as a pass instead.
const SHOT_RANGE := 6.0

## A knock this hard shakes the ball loose. Above every melee lunge and the
## lightest hits (1.5), below the real knockback Supers deal (9 and up).
const KNOCK_DROP_SPEED := 3.0

## Group on the scoreboard's root node, so a leftover from a previous match can
## be found on main.gd's HUD layer and cleared.
const HUD_GROUP := "cup_hud"

var game                          # main.gd; typed loosely, as BotBrain does
var ball: Ball
var score := [0, 0]
var clock := MATCH_SECONDS
var overtime := false
var finished := false
## Fighters wait out RESPAWN_SECONDS here as {fighter, at}.
var _respawning: Array[Dictionary] = []
var _frozen_until := 0.0
## Parent of the three cup labels. They have to hang off main.gd's HUD layer to
## draw, and that layer outlives a match, so they get one owner that CupMode can
## take down with it — see _build_hud.
var _hud_root: Control
var _score_label: Label
var _clock_label: Label
var _banner: Label

# MARK: setup

## Fills both teams and puts the ball on the centre spot. The arena is already
## built by the time this runs — main.gd sets Arena.map_mode before adding it.
func build_match(now: float) -> void:
	var arena: Arena = game.arena
	var kits: Array = Kits.all()
	for team in 2:
		# Assigned by index, never shuffled: kickoff() hands out the same spots
		# in the same order, and the two MUST agree. When they did not, every
		# fighter was teleported onto a team-mate's tile on the opening frame
		# and the overlapping capsules depenetrated hard enough to fire them
		# off the pitch and several hundred metres into the air.
		var spots: Array = arena.team_spawns[team]
		for i in TEAM_SIZE:
			var spot: Vector3 = spots[i % spots.size()] if not spots.is_empty() \
					else arena.centre()
			var is_you := team == 0 and i == 0
			var kit: Dictionary = game.player_kit() if is_you else kits.pick_random()
			var f: Fighter = game._spawn_fighter(kit, spot, is_you, team)
			f.display_name = "You" if is_you else "%s %d" % [kit.name, team * TEAM_SIZE + i]
			if is_you:
				game.player = f
			else:
				game.brains.append(BotBrain.new(f))

	ball = Ball.new()
	game.add_child(ball)
	ball.place(arena.centre(), now)
	_build_hud()
	kickoff(now, true)

## The scoreboard belongs to the match, but it has to live on main.gd's HUD
## CanvasLayer, which is built once in _ready and survives every rematch. So
## freeing the CupMode node does NOT take these labels with it: PLAY AGAIN
## stacked a second scoreboard on the first, the dead one frozen at the final
## score on top of the live 0 — 0, and a Showdown match started afterwards
## inherited the pile. One root node owns all three, cleared here in case a
## previous one is still on its way out and freed in _exit_tree.
func _build_hud() -> void:
	for stale in game.hud.get_children():
		if stale.is_in_group(HUD_GROUP):
			stale.free()
	_hud_root = Control.new()
	_hud_root.add_to_group(HUD_GROUP)
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the sticks are underneath
	game.hud.add_child(_hud_root)
	_score_label = _cup_label(14, 54, Color(1, 1, 1))
	_clock_label = _cup_label(74, 30, Color(0.85, 0.90, 1.0))
	# Clear of main.gd's centre label, which is still counting the match in.
	_banner = _cup_label(320, 64, Color(1.0, 0.87, 0.25))
	_refresh_hud()

## Centred on the viewport and re-centred when it resizes, unlike main.gd's
## fixed-position debug labels.
func _cup_label(top: float, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_top = top
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud_root.add_child(l)
	return l

func _exit_tree() -> void:
	if is_instance_valid(_hud_root):
		_hud_root.queue_free()

# MARK: flow

## Whether input is held: the kickoff beat, and everything after full time.
func frozen(now: float) -> bool:
	return finished or now < _frozen_until

## Both teams back to their spawns, ball on the centre spot, everyone held for
## a beat. Used for the opening whistle and after every goal.
func kickoff(now: float, opening := false) -> void:
	var arena: Arena = game.arena
	var used := {0: 0, 1: 0}
	for f: Fighter in game.fighters:
		if f.team < 0:
			continue
		var spots: Array = arena.team_spawns[f.team]
		if not spots.is_empty():
			var spot: Vector3 = spots[used[f.team] % spots.size()]
			used[f.team] += 1
			if f.is_dead():
				f.respawn(spot, now)
			else:
				f.position = spot
				f.kickoff_restore(now)
				f.reset_physics_interpolation()
		f.face_direction(_attack_dir(f.team))
	_respawning.clear()
	# A lob or a boomerang thrown a moment before the whistle is still in the
	# air, and the freeze holds everyone still on the centre spot for it to land
	# on. Ahead of ball.place(), which must not be swept up with it.
	game.clear_in_flight()
	ball.place(arena.centre(), now, KICKOFF_FREEZE)
	ball.last_touch = null
	_frozen_until = now + KICKOFF_FREEZE
	# The opening whistle is main.gd's 3-2-1-FIGHT!; only a restart after a
	# goal needs the score put back up, and only that restart is whistled.
	_banner.text = "" if opening else "%d — %d" % [score[0], score[1]]
	if not opening:
		game.sfx_ui("cup_whistle", -2.0)

## Which way a team is attacking: toward the goal it does NOT defend.
func _attack_dir(team: int) -> Vector3:
	var arena: Arena = game.arena
	return (arena.goal_centers[1 - team] - arena.goal_centers[team]).normalized()

func tick(delta: float, now: float) -> void:
	if finished:
		return
	if frozen(now):
		ball.tick(delta, now, game.arena)
		var left := int(ceil(_frozen_until - now))
		if left <= 1 and not overtime:
			_banner.text = "GO!"
		return
	_banner.text = ""
	# Before the ball moves: a carrier who went down this frame must let go
	# where they fell, not have the ball follow a corpse for a frame first.
	_carrier_check(now)
	ball.tick(delta, now, game.arena)
	_pickup_check(now)
	_respawn_check(now)
	if _goal_check(now):
		return
	clock = maxf(0.0, clock - delta)
	_refresh_hud()
	if clock <= 0.0:
		_time_up(now)
	elif overtime:
		_overtime_wipe_check()

## What shakes the ball loose. Brawl Ball's rule is that a carrier drops it
## when stunned, knocked back or defeated; a dash and a jump-smash are added to
## that here, because both are a fighter throwing itself across the pitch and
## carrying the ball through one would make every mobility Super a free run at
## the goal.
func _carrier_check(now: float) -> void:
	var c: Fighter = ball.carrier
	if c == null:
		return
	if not is_instance_valid(c) or c.is_dead():
		ball.place(_free_spot(c.global_position if is_instance_valid(c) else game.arena.centre()),
				now, 0.35)
		return
	if c.is_dashing() or c.is_leaping() or c.knockback_vel.length() > KNOCK_DROP_SPEED:
		# Dropped where they were standing, not where they end up: the ball
		# stays behind and the dash or the knock is what separates them from it.
		ball.place(_free_spot(c.global_position), now, 0.35)

func _pickup_check(now: float) -> void:
	if ball.carrier != null or now < ball.free_at:
		return
	var best: Fighter = null
	var best_d := Ball.PICKUP_RADIUS
	for f: Fighter in game.fighters:
		if f.is_dead():
			continue
		var d: float = Vector2(f.global_position.x - ball.position.x,
				f.global_position.z - ball.position.z).length()
		if d < best_d:
			best = f
			best_d = d
	if best != null:
		if OS.get_environment("NS3_SAVE_LOG") != "":
			var og: Vector3 = game.arena.goal_centers[best.team] if best.team >= 0 else Vector3.ZERO
			var tg: Vector3 = og - ball.position
			print("[cup] pickup %-10s pace %5.2f  dot %+5.2f  own-half %s  opp-touch %s  -> %s" % [
					best.display_name, ball.velocity.length(),
					Vector3(ball.velocity.x, 0, ball.velocity.z).normalized().dot(
						Vector3(tg.x, 0, tg.z).normalized()),
					ball.position.distance_to(og) < ball.position.distance_to(game.arena.centre()),
					is_instance_valid(ball.last_touch) and ball.last_touch.team != best.team,
					"SAVE" if _is_save(best) else "-"])
		if _is_save(best):
			best.stats.saves += 1
		ball.pick_up(best)
		game.feed_label.text = "%s has the ball" % best.display_name

## Whether this pickup was a save, for the results card. Deliberately narrow, so
## the number means something: the ball has to be moving with pace an opponent
## put on it, travelling toward the goal this fighter defends, and caught in
## their own half. Scooping up a loose ball at the halfway line is not a save,
## and neither is collecting your own team's pass back.
##
## A save is genuinely rare, and that is not a bug: measured over a full match
## (NS3_SAVE_LOG=1) the ball changes hands about seven times, and most of those
## are a team collecting its own forward pass — the `dot` is strongly NEGATIVE,
## meaning the ball is running away from the catcher's goal rather than at it.
## The case this counts is the one `_goal_check` already has a rule for: a
## defender scooping a shot off their own line. Thresholds are set just above a
## ball that is merely trickling (Ball.STOP_SPEED is 0.6) rather than tuned for
## frequency, so re-measure before moving them.
const SAVE_SPEED := 2.5
const SAVE_DOT := 0.35

func _is_save(catcher: Fighter) -> bool:
	if catcher.team < 0:
		return false
	var pace: Vector3 = ball.velocity
	if pace.length() < SAVE_SPEED:
		return false
	if not is_instance_valid(ball.last_touch) or ball.last_touch.team == catcher.team:
		return false
	var own_goal: Vector3 = game.arena.goal_centers[catcher.team]
	var to_goal: Vector3 = own_goal - ball.position
	if Vector3(pace.x, 0, pace.z).normalized().dot(Vector3(to_goal.x, 0, to_goal.z).normalized()) < SAVE_DOT:
		return false
	# In their own half: closer to the goal they defend than to the centre spot.
	return ball.position.distance_to(own_goal) < ball.position.distance_to(game.arena.centre())

func _respawn_check(now: float) -> void:
	for entry in _respawning.duplicate():
		if now < float(entry.at):
			continue
		_respawning.erase(entry)
		var f: Fighter = entry.fighter
		if not is_instance_valid(f):
			continue
		f.respawn(_spawn_for(f), now)

## Nobles Cup death: park the fighter and book its return. Overtime is sudden
## death, so a fighter that falls then stays down.
func on_death(f: Fighter, killer: String) -> void:
	if ball.carrier == f:
		ball.place(_free_spot(f.global_position), game.now, 0.35)
	f.knock_out()
	game.feed_label.text = "%s eliminated %s" % [killer, f.display_name] if killer != "" \
			else "%s went down" % f.display_name
	if not overtime:
		_respawning.append({"fighter": f, "at": game.now + RESPAWN_SECONDS})

## A death puts you back in your own goal, not at the kickoff spot. It is the
## one patch of pitch that is always yours, and a fighter standing in the mouth
## is a body in front of the next shot — which is where the mode's defending
## comes from now that no bot is assigned to keep goal. Picks the emptiest of
## the three mouth tiles, so two fighters coming back together are never
## dropped on top of each other.
func _spawn_for(f: Fighter) -> Vector3:
	var mouth: Array = game.arena.goal_mouths[f.team]
	if mouth.is_empty():
		return game.arena.centre()
	var best: Vector3 = mouth[0]
	var best_clear := -1.0
	for spot: Vector3 in mouth:
		var nearest := INF
		for other: Fighter in game.fighters:
			if other == f or other.is_dead():
				continue
			nearest = minf(nearest, other.global_position.distance_to(spot))
		if nearest > best_clear:
			best_clear = nearest
			best = spot
	return best

## Nudges a drop point off a wall, the same way main.gd walks a cube drop back.
func _free_spot(origin: Vector3) -> Vector3:
	if not game.arena.blocks_movement(origin):
		return origin
	for ang in [0.0, PI * 0.5, PI, PI * 1.5, PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var p := origin + Vector3(cos(ang), 0, sin(ang)) * Kits.TILE
		if not game.arena.blocks_movement(p):
			return p
	return game.arena.centre()

## True when a goal was scored this frame and the match state already moved on.
func _goal_check(now: float) -> bool:
	var ch: String = game.arena.raw_tile_at(ball.position)
	if ch != "0" and ch != "1":
		return false
	var conceded := int(ch)          # the goal belongs to the team defending it
	# Holding the ball on your own line is not conceding. A defender who scoops
	# a shot off the goal mouth was otherwise scoring it for the opposition on
	# the same frame they made the save.
	if ball.carrier != null and ball.carrier.team == conceded:
		return false
	var scorer := 1 - conceded
	score[scorer] += 1
	var who: String = ball.last_touch.display_name if is_instance_valid(ball.last_touch) \
			else "Somebody"
	var own := is_instance_valid(ball.last_touch) and ball.last_touch.team == conceded
	if is_instance_valid(ball.last_touch) and not own:
		ball.last_touch.stats.goals += 1
	game.feed_label.text = "%s scored%s" % [who, " (own goal)" if own else ""]
	game.sfx_ui("cup_goal", 2.0)
	# Hold on the goal that was just conceded through most of the kickoff
	# freeze, then hand the camera back in time for play to restart. Ahead of
	# kickoff(), which teleports everyone — the point is not to watch that.
	# Pulled back onto the pitch rather than sat on the goal line: a goal is at
	# the very edge of the map, so framing it dead centre fills the top half of
	# the screen with sky past the end of the arena.
	game.focus_camera(game.arena.goal_centers[conceded].lerp(game.arena.centre(),
			GOAL_CAMERA_INSET), GOAL_CAMERA_HOLD)
	_refresh_hud()
	if score[scorer] >= GOALS_TO_WIN or overtime:
		_finish(now)
	else:
		kickoff(now)
	return true

func _time_up(now: float) -> void:
	if score[0] != score[1]:
		_finish(now)
		return
	if overtime:      # nobody broke the tie
		_finish(now)
		return
	overtime = true
	clock = OVERTIME_SECONDS
	# Overtime opens the pitch up: every breakable wall comes down at once, so
	# the goal that could be defended for two and a half minutes cannot be.
	for w in game.get_tree().get_nodes_in_group("breakable"):
		if is_instance_valid(w):
			game.arena.open_at(w.global_position)
			w.queue_free()
	kickoff(now)
	_banner.text = "OVERTIME"

## Sudden death has no respawns, so a wiped team loses on the spot.
func _overtime_wipe_check() -> void:
	var alive := [0, 0]
	for f: Fighter in game.fighters:
		if f.team >= 0 and not f.is_dead():
			alive[f.team] += 1
	if alive[0] == 0 or alive[1] == 0:
		if alive[0] != alive[1]:
			score[0 if alive[0] > 0 else 1] += 1
		_finish(game.now)

func _finish(_now: float) -> void:
	finished = true
	_banner.text = ""
	game.end_cup_match(score[0], score[1])

func _refresh_hud() -> void:
	if _score_label == null:
		return
	_score_label.text = "%d  —  %d" % [score[0], score[1]]
	_clock_label.text = "%s%d:%02d" % ["OT  " if overtime else "",
			int(clock) / 60, int(clock) % 60]

# MARK: kicking

## The carrier's attack button. Returns false only when this fighter is not
## holding the ball, which is main.gd's signal to fire the weapon instead.
##
## A normal kick spends an ammo bar, as it does in Brawl Ball, and obeys the
## same attack cooldown as a shot — so a carrier cannot machine-gun the ball up
## the pitch, and running dry is a real reason to keep hold of it. Nobody can
## be stranded by it: reload is 1.0-2.6s a pip and you can always walk the ball
## in. The Super Shot spends the Super instead and needs no ammo.
##
## While carrying, the Super never fires the kit's Super — it goes into the
## ball as a Super Shot, twice as fast and twice as far, and is spent doing it.
## A Super with no charge, and a kick with no ammo, are both swallowed rather
## than falling through to an attack the carrier is not allowed to make.
func kick(f: Fighter, dir: Vector3, now: float, use_super := false) -> bool:
	if ball.carrier != f:
		return false
	if use_super:
		if not f.consume_super():
			return true
	elif not f.consume_ammo(now):
		return true
	ball.kick(dir, now, game.arena, Ball.SUPER_KICK_MULT if use_super else 1.0)
	# A Super Shot is twice the ball speed, so it gets the Super's own sound
	# rather than a louder boot.
	game.sfx_at("super_fire" if use_super else "cup_kick", f.global_position,
			3.0 if use_super else 0.0)
	f.face_direction(dir)
	f.play_attack_animation(now, use_super)
	return true

## Where a tap-to-kick sends the ball: at the goal being attacked, unless a
## team-mate is closer to it and in the clear, in which case it is a pass.
## A Super Shot reaches twice as far, so it goes for goal from twice as far out.
func kick_aim(f: Fighter, powerful := false) -> Vector3:
	var goal: Vector3 = game.arena.goal_centers[1 - f.team]
	var to_goal: float = f.global_position.distance_to(goal)
	# SHOT_RANGE, not the ball's full coast: the two have to agree, or a bot
	# that released the ball under pressure from well outside its own shooting
	# range still had this aim it at the goal, and hit.
	var reach: float = SHOT_RANGE * (Ball.SUPER_KICK_MULT if powerful else 1.0)
	if to_goal <= reach and game.has_line_of_sight(f.global_position, goal):
		return goal - f.global_position
	var best: Fighter = null
	var best_d := to_goal
	for mate: Fighter in game.fighters:
		if not f.is_ally(mate) or mate.is_dead():
			continue
		var d: float = mate.global_position.distance_to(goal)
		if d < best_d and game.has_line_of_sight(f.global_position, mate.global_position):
			best = mate
			best_d = d
	if best != null:
		return best.global_position - f.global_position
	return goal - f.global_position
