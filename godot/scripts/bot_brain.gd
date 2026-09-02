class_name BotBrain
extends RefCounted
## Priority-based bot decisions, ported from the SpriteKit BotBrain:
## escape gas > flee > engage > loot > wander, with unstick detours.
## Movement is re-decided on a short timer (not every physics frame) and the
## output vector is smoothed, so boundary conditions (enemy at the edge of
## range, the gas edge, canceling flee vectors) can't flip velocity per frame.

var fighter: Fighter
var _wander_target := Vector3.ZERO
var _repick_at := 0.0
var _next_fire_at := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_check_at := 0.0
var _detour := Vector3.ZERO
var _detour_until := 0.0
var _detour_side := 0.0
var _stuck_streak := 0
var _last_stuck_at := 0.0

var _target: Fighter = null
var _target_seen_at := 0.0
var _think_at := 0.0
var _move_choice := Vector3.ZERO
var _fleeing_gas := false
var _smoothed := Vector3.ZERO
var _last_now := -1.0

var _aim_error_deg := randf_range(3.0, 9.0)
## Set in _init from the kit — see the note there.
var _fire_interval := 1.3
var _engage_range := Kits.TILE * randf_range(5.5, 7.0)
var _think_interval := randf_range(0.15, 0.25)

## How far ahead of a moving target a bot aims, as a fraction of the target's
## travel during the shot's flight. 1.0 is a perfect intercept; 0.0 is aiming
## where the target already stands.
##
## Without any lead, projectile kits simply cannot hit a moving fighter: a
## 17.6 m/s pellet crossing 8.6 m is airborne 0.49s, in which a 4.0 m/s target
## moves 2.0 m — more than its own 1.30 m width. Instant-hit kits (melee,
## shockwave) never miss, so a no-lead sim measures "is this weapon hitscan"
## rather than whether the kit is balanced. Sim bots therefore aim well; match
## bots lead badly on purpose, so shots read as aimed without being hard to
## walk out of. The player's tap-fire leads fully — see main.gd `_aim_lead`.
const LEAD_SIM := 0.85
const LEAD_MATCH_MIN := 0.15
const LEAD_MATCH_MAX := 0.45
const LEAP_FLIGHT := 0.48   # Fighter.begin_leap duration; JUMP_SMASH has no speed

var _lead_skill := randf_range(LEAD_MATCH_MIN, LEAD_MATCH_MAX)

# Nobles Cup. A bot that kicked the instant it touched the ball never carried
# it anywhere, so it settles for a moment first; the roll keeps three bots on
# one team from all releasing on the same frame.
var _carry_until := 0.0
var _had_ball := false
## Where this bot stands off from its team-mates when supporting an attack, so
## a whole team doesn't stack on one tile behind the carrier.
var _support_side := 1.0 if randf() > 0.5 else -1.0

## Aim scatter has to be tightened for the sim for the same reason lead does.
## A fighter is 1.30 m of hittable width, so at a 7 m engagement the match
## spread of 3-9 degrees is 0.37-1.10 m of error: a bot that rolls near the top
## of that can never land a precision weapon for its entire life. Wide melee
## arcs, big AOEs and bouncing projectiles don't care, so leaving match scatter
## in the sim ranks kits by how forgiving they are rather than how strong.
const AIM_ERROR_SIM_MIN := 0.5
const AIM_ERROR_SIM_MAX := 2.0

var _aim_error_sim := randf_range(AIM_ERROR_SIM_MIN, AIM_ERROR_SIM_MAX)

func _init(f: Fighter) -> void:
	fighter = f
	# Fire on the kit's own ammo economy, not a constant. A flat 1.0-1.6s roll
	# meant a Slow-reload bot (Tony, 2.2s) tried to shoot faster than it could
	# reload and just ran dry, while a Fast-reload bot (Sanjit, 1.4s) sat on
	# full ammo — and neither ever bursted, where the player could empty a
	# magazine instantly. Both sides now spend ammo at roughly the rate it
	# arrives, floored at the attack cooldown so a bot can still double-tap.
	var reload: float = float(f.kit.get("reload", Kits.AMMO_RECHARGE_SECONDS))
	_fire_interval = maxf(Kits.attack_cooldown_for(reload), reload * randf_range(0.85, 1.15))

## Returns {move: Vector3, fire_dir: Vector3 or null, fire_dist: float,
## use_super: bool, kick_dir: Vector3 or null, kick_super: bool}. The last two
## are Nobles Cup only, and main.gd reads them instead of fire_dir whenever this
## bot is carrying the ball.
func decide(now: float, game) -> Dictionary:
	var d := {"move": Vector3.ZERO, "fire_dir": null, "fire_dist": 0.0,
			"use_super": false, "kick_dir": null, "kick_super": false}
	_update_target(now, game)
	if game.cup != null:
		_cup_kick(now, game, d)

	if now >= _think_at:
		_think_at = now + _think_interval
		_move_choice = _pick_move(now, game)
	d.move = _move_choice

	if _target and now >= _next_fire_at:
		var use_super := fighter.is_super_ready()
		var weapon: Dictionary = fighter.kit["super"] if use_super else fighter.kit.weapon
		var dist := fighter.global_position.distance_to(_target.global_position)
		var thrown: bool = int(weapon.style) == Kits.Style.LOB \
				or int(weapon.style) == Kits.Style.DISCONNECT \
				or int(weapon.style) == Kits.Style.KEEP_IT_UP
		# Strictly inside range: a projectile deletes itself at weapon.range, so
		# the old "+ half a tile" tolerance meant the opening shot of most
		# engagements expired in mid-air before it could reach anyone.
		if dist <= float(weapon.range) \
				and game.can_see(fighter, _target, thrown):
			_next_fire_at = now + _fire_interval
			var aim := _aim_point(_target, weapon, dist, game)
			var base := _dir_to(aim)
			if base == Vector3.ZERO:   # aim point landed on top of us
				base = _dir_to(_target.global_position)
			# Pop Off is an escape: the spike comes down on the ground he jumped
			# AWAY from, so its aim is the leap, not the target. A bot pointing
			# it at an enemy leaps onto them and spikes empty floor behind it.
			if int(weapon.style) == Kits.Style.POP_OFF:
				base = -base
			if base != Vector3.ZERO:
				var scatter: float = _aim_error_sim if game.sim_active else _aim_error_deg
				var err := deg_to_rad(randf_range(-scatter, scatter))
				d.fire_dir = base.rotated(Vector3.UP, err)
				# Thrown styles land where fire_dist says, so it has to be the
				# distance to the lead point, not to the target.
				d.fire_dist = fighter.global_position.distance_to(aim)
				d.use_super = use_super

	# Nothing to shoot at: crack open the nearest power-cube box instead, the
	# same fallback the player's tap-fire uses. Mutually exclusive with the
	# block above, which only runs while a target is held.
	if _target == null and now >= _next_fire_at:
		_aim_at_box(now, game, d)

	_unstick(now, d)

	var dt := clampf(now - _last_now, 0.0, 0.1) if _last_now >= 0.0 else 0.016
	_last_now = now
	_smoothed = _smoothed.lerp(d.move as Vector3, 1.0 - exp(-8.0 * dt))
	d.move = _smoothed if _smoothed.length() > 0.05 else Vector3.ZERO
	# Ayaan mid-Downhill steers every frame, deliberately after the think timer
	# and the smoothing above: the ride is 11.7 m/s, so a 0.15-0.25s stale
	# heading is two and a half metres of lag and the smoothing adds more. The
	# steering is rate-capped in Fighter.apply_movement anyway, so feeding it a
	# raw chase vector still produces a carve rather than a snap.
	if fighter.is_riding():
		d.move = _dir_to(_target.global_position) if _target != null \
				and is_instance_valid(_target) and not _target.is_dead() else fighter.facing
	return d

## Boxes never move, never hide and never shoot back, so there is no lead and
## no aim scatter here. The Super is deliberately not spent on one — a bot that
## opens a box with its Super arrives at the next fight empty-handed.
func _aim_at_box(now: float, game, d: Dictionary) -> void:
	var weapon: Dictionary = fighter.kit.weapon
	var thrown: bool = int(weapon.style) == Kits.Style.LOB \
			or int(weapon.style) == Kits.Style.DISCONNECT \
			or int(weapon.style) == Kits.Style.KEEP_IT_UP
	var box = game.nearest_visible_lootbox(fighter, float(weapon.range), thrown)
	if box == null:
		return
	var flat: Vector3 = box.global_position - fighter.global_position
	flat.y = 0.0
	var dir := _dir_to(box.global_position)
	if dir == Vector3.ZERO:
		return
	_next_fire_at = now + _fire_interval
	d.fire_dir = dir
	d.fire_dist = flat.length()

## Keep the current target until it dies, gets far out of range, or stays
## unseen too long — re-querying nearest_visible_enemy every frame made bots
## flip-flop when an enemy sat right on the range/visibility boundary.
func _update_target(now: float, game) -> void:
	# Throwers see through walls for targeting because their shot arcs over.
	var lob: bool = int(fighter.kit.weapon.style) == Kits.Style.LOB \
			or int(fighter.kit.weapon.style) == Kits.Style.KEEP_IT_UP
	# Nobles Cup: a carrier only lets go of the ball by going down, so putting
	# damage into whoever has it beats shooting whoever happens to be nearest.
	# It is the whole of the counter-play — without it a carrier simply walks
	# the ball in while the defence shoots at somebody else.
	if game.cup != null:
		var holder: Fighter = game.cup.ball.carrier
		if holder != null and is_instance_valid(holder) and not holder.is_dead() \
				and holder != fighter and not fighter.is_ally(holder) \
				and fighter.global_position.distance_to(holder.global_position) \
					<= _engage_range * 1.3 \
				and game.can_see(fighter, holder, lob):
			_target = holder
			_target_seen_at = now
			return
	if _target != null:
		if not is_instance_valid(_target) or _target.is_dead() \
				or fighter.global_position.distance_to(_target.global_position) > _engage_range * 1.4:
			_target = null
		elif game.can_see(fighter, _target, lob):
			_target_seen_at = now
		elif now - _target_seen_at > 1.5:
			_target = null
	if _target == null:
		_target = game.nearest_visible_enemy(fighter, _engage_range, lob)
		if _target:
			_target_seen_at = now

## Nobles Cup: does this bot want the ball, and where does it go with it? The
## fight itself is unchanged — shooting, fleeing and unsticking all still run —
## this only replaces "loot then wander" with "play the ball".
func _cup_move(game) -> Vector3:
	var cup = game.cup
	var ball: Ball = cup.ball
	var pos := fighter.global_position
	var their_goal: Vector3 = game.arena.goal_centers[1 - fighter.team]

	if ball.carrier == fighter:
		# Around the goal wall, not into it. Steering straight at the mouth
		# walks a carrier into the wall two tiles in front of it and leaves
		# them grinding along it until someone takes the ball off them.
		var route: Vector3 = game.arena.route_to_goal(1 - fighter.team, pos)
		return route if route != Vector3.ZERO else _dir_to(their_goal)

	if ball.carrier != null and not fighter.is_ally(ball.carrier):
		return _dir_to(ball.carrier.global_position)   # tackle the carrier
	if ball.carrier != null:
		# A team-mate has it: get up the pitch and off their line, so there is
		# someone to pass to rather than a queue behind the ball.
		var lane := (their_goal - ball.carrier.global_position).normalized()
		var across := Vector3(-lane.z, 0, lane.x) * _support_side * Kits.TILE * 3.0
		return _dir_to(ball.carrier.global_position + lane * Kits.TILE * 4.0 + across)
	if _closest_to_ball(game, 1):
		return _dir_to(ball.position)
	# Someone else is closer: show for the pass up the pitch rather than
	# crowding the same tile they are running to.
	return _dir_to(ball.position.lerp(their_goal, 0.4))

## Whether this bot is among the `count` nearest on its team to a loose ball.
func _closest_to_ball(game, count: int) -> bool:
	var mine: float = fighter.global_position.distance_to(game.cup.ball.position)
	var nearer := 0
	for f: Fighter in game.fighters:
		if not fighter.is_ally(f) or f.is_dead():
			continue
		if f.global_position.distance_to(game.cup.ball.position) < mine:
			nearer += 1
	return nearer < count

## When to let go of the ball: in range of the goal with a clear sight of it,
## or with an enemy close enough to take it off us. CupMode.kick_aim decides
## whether that is a shot or a pass.
func _cup_kick(now: float, game, d: Dictionary) -> void:
	var cup = game.cup
	if cup.ball.carrier != fighter:
		_had_ball = false
		return
	if not _had_ball:
		_had_ball = true
		_carry_until = now + randf_range(0.5, 1.0)
	if now < _carry_until:
		return
	var goal: Vector3 = game.arena.goal_centers[1 - fighter.team]
	var to_goal: float = fighter.global_position.distance_to(goal)
	# A charged Super is a Super Shot, which reaches twice as far — so a bot
	# holding one will take the shot from outside its normal range.
	var powerful: bool = fighter.is_super_ready()
	var reach: float = CupMode.SHOT_RANGE * (Ball.SUPER_KICK_MULT if powerful else 1.0)
	var in_range: bool = to_goal <= reach \
			and game.has_line_of_sight(fighter.global_position, goal)
	var pressured: bool = game.nearest_visible_enemy(fighter, Kits.TILE * 1.4, true) != null
	if in_range or pressured:
		d.kick_dir = cup.kick_aim(fighter, powerful and in_range)
		# Never on a panic clearance: a Super spent hoofing the ball clear is a
		# Super not spent on the shot it was being saved for.
		d.kick_super = powerful and in_range

func _pick_move(now: float, game) -> Vector3:
	var pos := fighter.global_position
	if not game.gas_contains(pos):
		_fleeing_gas = true
	elif _fleeing_gas and game.gas_depth(pos) > Kits.TILE * 1.5:
		_fleeing_gas = false
	if _fleeing_gas:
		return _dir_to(game.gas_safe_center())

	var enemy := _target
	if enemy and fighter.health < fighter.max_health * 0.3:
		var flee := _dir_from(enemy.global_position) + _dir_to(game.gas_safe_center()) * 0.5
		if flee.length() < 0.3:  # enemy is between us and center; strafe out instead
			var away := _dir_from(enemy.global_position)
			return Vector3(-away.z, 0, away.x)
		return flee.normalized()
	if game.cup != null:
		return _cup_move(game)
	if enemy:
		var dist := pos.distance_to(enemy.global_position)
		# Spread weapons have to hug: at the default 0.7 standoff a shotgun's
		# pellets have already fanned wider than a fighter, so only the centre
		# one lands. Those kits set their own ideal_range_mult (Nova: 0.30).
		var mult: float = fighter.kit.get("ideal_range_mult", 0.7)
		var ideal: float = max(Kits.TILE * 0.9, fighter.kit.weapon.range * mult)
		var toward := _dir_to(enemy.global_position)
		if dist > ideal * 1.2:
			return toward
		elif dist < ideal * 0.7:
			return -toward
		return Vector3(-toward.z, 0, toward.x) * 0.6

	var loot = game.nearest_loot(pos)
	if loot != null:
		return _dir_to(loot)
	if _wander_target == Vector3.ZERO or now >= _repick_at \
			or pos.distance_to(_wander_target) < Kits.TILE:
		_wander_target = game.random_wander_point(pos)
		_repick_at = now + randf_range(2.5, 4.5)
	return _dir_to(_wander_target)

## Detours keep the same side across consecutive stalls (wall-follow) instead
## of re-rolling a random side each time, which made blocked bots ping-pong.
## The side flips only after two failed tries; past four we back out diagonally.
func _unstick(now: float, d: Dictionary) -> void:
	if _detour != Vector3.ZERO and now < _detour_until:
		d.move = _detour
		return
	_detour = Vector3.ZERO
	if d.move.length() < 0.1:
		_stuck_check_at = now + 0.6
		_stuck_pos = fighter.global_position
		return
	if now >= _stuck_check_at:
		if _stuck_check_at > 0.0 and fighter.global_position.distance_to(_stuck_pos) < 0.2:
			if _detour_side == 0.0 or now - _last_stuck_at > 3.0:
				_stuck_streak = 0
				_detour_side = 1.0 if randf() > 0.5 else -1.0
			_stuck_streak += 1
			_last_stuck_at = now
			if _stuck_streak == 3:
				_detour_side = -_detour_side
			var dir := (d.move as Vector3).normalized()
			var side := Vector3(-dir.z, 0, dir.x) * _detour_side
			_detour = side if _stuck_streak <= 4 else (side - dir).normalized()
			_detour_until = now + minf(0.5 + 0.2 * _stuck_streak, 1.5)
		_stuck_pos = fighter.global_position
		_stuck_check_at = now + 0.6

## Where to shoot so the shot and the target arrive in the same place. Melee and
## shockwave resolve instantly, so they always aim straight at the target.
func _aim_point(target: Fighter, weapon: Dictionary, dist: float, game) -> Vector3:
	var speed: float = Kits.aim_speed(weapon, dist)
	var flight := 0.0
	if int(weapon.style) == Kits.Style.JUMP_SMASH:
		flight = LEAP_FLIGHT      # a leap, not a projectile: fixed airtime
	elif speed > 0.1:
		flight = dist / speed     # Lob matches this: _duration = distance / speed
	if flight <= 0.0:
		return target.global_position
	var lead: float = LEAD_SIM if game.sim_active else _lead_skill
	var travel := Vector3(target.velocity.x, 0.0, target.velocity.z) * lead
	var aim := target.global_position + travel * flight
	# One refinement pass: leading moves the aim point, which changes how long
	# the shot is airborne, which moves the aim point again.
	if speed > 0.1:
		flight = fighter.global_position.distance_to(aim) / speed
		aim = target.global_position + travel * flight
	return aim

func _dir_to(p: Vector3) -> Vector3:
	var v := p - fighter.global_position
	v.y = 0
	return v.normalized() if v.length() > 0.001 else Vector3.ZERO

func _dir_from(p: Vector3) -> Vector3:
	return -_dir_to(p)
