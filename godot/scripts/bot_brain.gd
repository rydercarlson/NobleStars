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

# MARK: terrain state
#
# Bots read the arena for two things only: a wall to break line of sight with
# while they are useless, and a bush to be unseen in. Both are expressed the way
# every other decision here is — a point to walk toward — so they drop into the
# `_pick_move` ladder without disturbing the priorities around them.
#
# Every terrain query is sampled against the ASCII map (`Arena.tile_at`) rather
# than raycast. That is deliberate: it costs no physics, it agrees exactly with
# `blocks_movement` and with a wall that `Arena.open_at` has shot out, and it is
# cheap enough to score a whole window of candidate tiles on one think tick.

## How far out, in tiles, a bot looks for cover and for a bush. Four tiles is
## about two seconds of walking at 4 m/s — far enough to find a wall on an open
## map, near enough that the walk itself is not the thing that kills you.
const COVER_SCAN := 4
const BUSH_SCAN := 5
## Ignore candidates we are already standing on: a "cover" tile half a metre
## away is the tile we are being shot on.
const COVER_MIN_TILES := 1.0
## Below this the search is not worth running: there is no line to break with
## someone standing on top of you, and walking to a wall past them is strictly
## worse than the strafe the caller already falls back to. Measured — a bot at
## point-blank was re-scanning the whole window every COVER_HOLD and finding
## nothing, every time.
const COVER_MIN_ENEMY := Kits.TILE * 1.5
## How long a chosen cover tile is kept before it is re-scored. Re-picking every
## think tick made bots oscillate between two equally good walls.
const COVER_HOLD := 1.2
## How long a bot will sit in a bush with nothing to shoot before it gets bored
## and goes back to wandering, and how long it wanders before it may hide again.
const AMBUSH_HOLD := 6.0
const AMBUSH_REST_MIN := 4.0
const AMBUSH_REST_MAX := 8.0
## How long a hidden bot waits for a target to walk into range before giving up
## and closing the distance itself. Without a cap an ambusher whose target never
## approaches simply stops playing.
const AMBUSH_PATIENCE := 3.0

## NS3_BOT_LOG=1 prints every time a bot takes cover, settles into a bush, holds
## an ambush, flanks a target it is losing to, or closes on one behind cover.
## Terrain use is easy to mistake for missing when it is merely rare, so this is
## how you tell "the rule never matched" from "the situation never arose" — the
## same job NS3_SAVE_LOG does for Nobles Cup saves.
static var _log := OS.get_environment("NS3_BOT_LOG") != ""

var _cover_point := Vector3.ZERO
var _cover_until := 0.0
var _ambush_point := Vector3.ZERO
var _ambush_until := 0.0
var _ambush_ready_at := 0.0
## When the current uninterrupted spell of lurking began; -1 when not lurking.
var _lurk_since := -1.0

# MARK: offensive terrain state
#
# The block above answers "where do I hide". These three answer "where do I
# stand to win the fight I am already in", which is the half of using the map a
# bot had none of: it walked the straight line to its ideal range and strafed
# there for the rest of the engagement, whatever the ground offered.
#
# All three are Showdown-only, and deliberately so — they sit BELOW the
# `game.cup` branch in `_pick_move`, because in Nobles Cup the ball owns a
# bot's movement and a bot that peels off to flank has stopped playing the mode.

## How far out, in tiles, a bot looks for a flanking tile or for a covered step
## on the way in. Deliberately the same window as COVER_SCAN, so all three
## searches cost one understood amount rather than three separate ones.
const FLANK_SCAN := 4
## How far behind on health, as a fraction of max, before a bot resets a fight
## by breaking sight instead of standing in it. About one exchange — under this
## every engagement would reset on the first hit taken and nobody would trade.
const FLANK_DEFICIT := 0.2
## The minimum turn around the target, in degrees, between where we stand now
## and where we come back from. Below this a "flank" is a sidestep the target
## never loses us across, which is the entire point of going.
const FLANK_MIN_TURN := 55.0
## How long a flank is committed to. Longer than COVER_HOLD on purpose: it only
## pays if we are gone long enough for the target to lose us, and it has to
## cover the walk — four tiles is 8 m, about two seconds at 4 m/s.
const FLANK_HOLD := 2.5
## And how long before the same bot may start another. Without a rest a bot
## that is simply outgunned circles the same wall for the rest of the match
## instead of ever committing to the fight or dying in it.
const FLANK_REST := 6.0
## How long a covered approach step is committed to before it is re-scored.
const APPROACH_HOLD := 1.0
## How much nearer the target a covered step has to get us to be worth taking.
## Under a tile it is a sidestep that spends the walk and arrives nowhere.
const APPROACH_GAIN := Kits.TILE
## How close to the gas edge a target has to be before a bot takes the inside
## line on it. Past three tiles the ring is not something it can be herded into
## yet, and the plain strafe reads better than a bot circling for no reason.
const GAS_PRESSURE_DEPTH := Kits.TILE * 3.0

## How long a target is remembered once it goes out of sight, and the longer
## grace that applies while WE are the ones who broke the sight. A flank or a
## covered approach that makes a bot forget the target it went round the wall
## for is a flank that fails — and both take longer than the normal grace.
const TARGET_MEMORY := 1.5
const TARGET_MEMORY_DELIBERATE := 4.0

var _flank_point := Vector3.ZERO
var _flank_until := 0.0
var _flank_ready_at := 0.0
var _approach_point := Vector3.ZERO
var _approach_until := 0.0
## Whether we were already taking the inside line last think. Only used to keep
## NS3_BOT_LOG to one line per press: unlike cover and flanks, gas pressure is
## re-decided every think tick, so logging it unconditionally buries everything
## else the flag is there to show.
var _pressing := false

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
		elif now - _target_seen_at > _target_memory(now):
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
	var hurt: bool = enemy != null and fighter.health < fighter.max_health * 0.3
	# The two moments a bot has nothing to trade and should spend the walk to a
	# wall: nearly dead, or holding an empty magazine in someone's sights.
	if enemy and (hurt or _pinned_without_ammo(game, enemy)):
		var spot := _cover_spot(now, game, enemy)
		if spot != Vector3.ZERO:
			# Standing in it already — hold, rather than jittering on the tile.
			# Reloading behind a wall is the whole point of having walked here.
			if pos.distance_to(spot) <= Kits.TILE * 0.5:
				return Vector3.ZERO
			return _dir_to(spot)
	if hurt:
		# Nothing to hide behind: the open-ground retreat, unchanged.
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
		# Unseen in a bush: let them walk onto us instead of breaking cover to
		# meet them in the open. Holding still is the ambush.
		if _should_lurk(now, game, pos, dist, ideal):
			return Vector3.ZERO
		# Losing the exchange: break their sight and come back on another
		# bearing, rather than standing in a trade that is going the wrong way.
		if _losing_trade(game, enemy):
			var around := _flank_spot(now, game, enemy, ideal)
			if around != Vector3.ZERO:
				if pos.distance_to(around) <= Kits.TILE * 0.5:
					return Vector3.ZERO   # arrived: reload out of their sight
				return _dir_to(around)
		var toward := _dir_to(enemy.global_position)
		if dist > ideal * 1.2:
			# Walk in behind a wall wherever there is one to walk behind. The
			# straight run is the fallback, not the plan — but it is still what
			# most of an open map gives you.
			var step := _approach_spot(now, game, enemy)
			return _dir_to(step) if step != Vector3.ZERO else toward
		elif dist < ideal * 0.7:
			return -toward
		# At fighting distance the only question left is which side of them to
		# stand on, and near a closing ring there is a right answer: the inside.
		var press := _gas_pressure_point(game, enemy, ideal)
		if press != Vector3.ZERO and pos.distance_to(press) > Kits.TILE * 0.6:
			return _dir_to(press)
		return Vector3(-toward.z, 0, toward.x) * 0.6

	var loot = game.nearest_loot(pos)
	if loot != null:
		return _dir_to(loot)
	# Nothing to fight and nothing to collect: wait somewhere that hides us
	# rather than pacing the open. Ranked below loot on purpose — a cube in hand
	# beats a good hiding place.
	var lurk := _ambush_spot(now, game, pos)
	if lurk != Vector3.ZERO:
		if pos.distance_to(lurk) <= Kits.TILE * 0.5:
			return Vector3.ZERO
		return _dir_to(lurk)
	if _wander_target == Vector3.ZERO or now >= _repick_at \
			or pos.distance_to(_wander_target) < Kits.TILE:
		_wander_target = game.random_wander_point(pos)
		_repick_at = now + randf_range(2.5, 4.5)
	return _dir_to(_wander_target)

# MARK: terrain

## Whether an empty magazine is worth walking away from: only while someone who
## can actually see us is close enough to punish it. `ammo_locked` kits (Anders
## mid-rally) are excluded because their ammo will not come back for waiting.
func _pinned_without_ammo(game, enemy: Fighter) -> bool:
	if fighter.ammo >= 1.0 or fighter.ammo_locked:
		return false
	var dist := fighter.global_position.distance_to(enemy.global_position)
	return dist <= float(fighter.kit.weapon.range) * 1.2 and game.can_see(enemy, fighter)

## Where to stand so `enemy` loses sight of us. Vector3.ZERO when there is
## nothing to hide behind, which leaves the caller's own retreat in place.
##
## A chosen tile is kept for COVER_HOLD rather than re-scored every think, and
## is dropped early the moment it stops being cover — an enemy who walks around
## the wall makes the spot we picked worthless, and standing in it is worse than
## having never gone.
func _cover_spot(now: float, game, enemy: Fighter) -> Vector3:
	var eye := enemy.global_position
	if fighter.global_position.distance_to(eye) < COVER_MIN_ENEMY:
		return Vector3.ZERO
	var arena: Arena = game.arena
	# Inside the hold, reuse the last answer — including a failed one. Caching
	# only successes meant a bot with nothing to hide behind rescanned the whole
	# window every think tick for as long as it stayed in trouble, which is
	# exactly the situation it is already losing.
	if now < _cover_until:
		if _cover_point == Vector3.ZERO:
			return Vector3.ZERO
		if game.gas_contains(_cover_point) and _wall_between(arena, _cover_point, eye):
			return _cover_point
	_cover_point = _find_cover(game, arena, fighter.global_position, eye)
	_cover_until = now + COVER_HOLD
	if _log:
		var reach := fighter.global_position.distance_to(eye)
		if _cover_point == Vector3.ZERO:
			print("[bot] %s wanted cover from %.1fm and found none" % [fighter.kit.name, reach])
		else:
			print("[bot] %s takes cover %.1fm away (enemy %.1fm, hp %d%%)" % [fighter.kit.name,
					fighter.global_position.distance_to(_cover_point), reach,
					int(100.0 * fighter.health / fighter.max_health)])
	return _cover_point

## The best tile within COVER_SCAN that has a wall on the line to `eye`.
## Candidates are filtered cheapest-first: the wall test rejects most of an open
## window, and only survivors pay for the walkability check.
func _find_cover(game, arena: Arena, pos: Vector3, eye: Vector3) -> Vector3:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	var best := Vector3.ZERO
	var best_score := -INF
	for dr in range(-COVER_SCAN, COVER_SCAN + 1):
		for dc in range(-COVER_SCAN, COVER_SCAN + 1):
			var c := col + dc
			var r := row + dr
			if c < 0 or c >= arena.columns or r < 0 or r >= arena.row_count:
				continue
			var centre: Vector3 = arena.tile_center(c, r)
			var trip := pos.distance_to(centre)
			if trip < Kits.TILE * COVER_MIN_TILES or trip > Kits.TILE * float(COVER_SCAN):
				continue
			if arena.blocks_movement(centre) or not game.gas_contains(centre):
				continue
			if not _wall_between(arena, centre, eye):
				continue
			if not _walkable_line(arena, pos, centre):
				continue
			# Nearest cover that still leaves us in the fight. The trip is the
			# part that gets us shot, so it dominates; the second term keeps a
			# bot from backing so far out that coming back means re-crossing the
			# same open ground it just fled across.
			var score := -trip - absf(centre.distance_to(eye) - _engage_range) * 0.25
			if score > best_score:
				best_score = score
				best = centre
	return best

## The bush to go and wait in, or Vector3.ZERO to carry on wandering. Lurking is
## time-boxed at both ends: AMBUSH_HOLD in the bush, then a rest spent wandering
## before another one is looked for. Without the rest, a bot that spawns beside
## a bush never leaves it and the match stops converging.
func _ambush_spot(now: float, game, pos: Vector3) -> Vector3:
	if _ambush_point != Vector3.ZERO:
		if now >= _ambush_until or not game.gas_contains(_ambush_point):
			_ambush_point = Vector3.ZERO
			_ambush_ready_at = now + randf_range(AMBUSH_REST_MIN, AMBUSH_REST_MAX)
			return Vector3.ZERO
		return _ambush_point
	if now < _ambush_ready_at:
		return Vector3.ZERO
	var found := _find_bush(game, game.arena, pos)
	if found == Vector3.ZERO:
		# Nothing in reach: don't rescan the same window every think tick.
		_ambush_ready_at = now + 2.0
		return Vector3.ZERO
	_ambush_point = found
	_ambush_until = now + randf_range(AMBUSH_HOLD * 0.7, AMBUSH_HOLD * 1.3)
	if _log:
		print("[bot] %s settles into a bush %.1fm away" % [fighter.kit.name,
				pos.distance_to(_ambush_point)])
	return _ambush_point

## Nearest reachable bush tile still inside the gas.
func _find_bush(game, arena: Arena, pos: Vector3) -> Vector3:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	var best := Vector3.ZERO
	var best_trip := INF
	for dr in range(-BUSH_SCAN, BUSH_SCAN + 1):
		for dc in range(-BUSH_SCAN, BUSH_SCAN + 1):
			var c := col + dc
			var r := row + dr
			if c < 0 or c >= arena.columns or r < 0 or r >= arena.row_count:
				continue
			var centre: Vector3 = arena.tile_center(c, r)
			if arena.tile_at(centre) != "b":
				continue
			var trip := pos.distance_to(centre)
			if trip >= best_trip or not game.gas_contains(centre):
				continue
			if not _walkable_line(arena, pos, centre):
				continue
			best_trip = trip
			best = centre
	return best

## Whether to hold still in a bush rather than close on a target.
##
## `main.gd:can_see` hides a fighter standing on a `b` tile from anyone further
## than `Kits.BUSH_REVEAL`, and it tests the *target's* tile — so a bot in a bush
## sees out while staying unseen. That asymmetry is the whole advantage, and it
## is spent the moment the bot walks into the open to meet someone.
func _should_lurk(now: float, game, pos: Vector3, dist: float, ideal: float) -> bool:
	var arena: Arena = game.arena
	if arena.tile_at(pos) != "b" or dist <= Kits.BUSH_REVEAL:
		_lurk_since = -1.0   # in the open, or already found: fight normally
		return false
	# Hidden and already in range — stand and shoot. `decide` fires from here
	# without any help from the movement vector.
	if dist <= ideal:
		return true
	if _lurk_since < 0.0:
		_lurk_since = now
		if _log:
			print("[bot] %s lurks on %s at %.1fm" % [fighter.kit.name,
					_target.kit.name if _target != null else "?", dist])
	return now - _lurk_since < AMBUSH_PATIENCE

# MARK: offensive terrain

## How long the current target survives out of sight. Longer while a flank or a
## covered approach is committed, because in that case WE broke the sight: a
## reposition that makes a bot forget the fighter it went round the wall for is
## a reposition that fails, and both take longer than the plain grace allows.
## Bounded by the holds themselves, so a stale point can never extend it.
func _target_memory(now: float) -> float:
	if (_flank_point != Vector3.ZERO and now < _flank_until) \
			or (_approach_point != Vector3.ZERO and now < _approach_until):
		return TARGET_MEMORY_DELIBERATE
	return TARGET_MEMORY

## Whether this fight is worth resetting: we are meaningfully behind on health
## and they can see us, so standing here keeps trading on their terms. The
## `hurt` ladder above already owns everything below 30% — this is the band
## between losing and nearly dead, which previously had no play in it at all.
## Fractions rather than raw health, so a cube-loaded opponent is read as
## healthy rather than as an unwinnable fight.
func _losing_trade(game, enemy: Fighter) -> bool:
	var mine: float = float(fighter.health) / float(fighter.max_health)
	var theirs: float = float(enemy.health) / float(enemy.max_health)
	return mine < theirs - FLANK_DEFICIT and game.can_see(enemy, fighter)

## Where to go to break the target's sight of us and come back from somewhere
## else. Vector3.ZERO when there is no such tile, which leaves the straight
## fight in place — on open ground there is nothing to flank around.
func _flank_spot(now: float, game, enemy: Fighter, ideal: float) -> Vector3:
	var eye := enemy.global_position
	var arena: Arena = game.arena
	# A live commitment outranks the rest timer: FLANK_REST governs how often a
	# new run may START, not whether the current one is abandoned half way.
	if now < _flank_until and _flank_point != Vector3.ZERO:
		if game.gas_contains(_flank_point) and _wall_between(arena, _flank_point, eye):
			return _flank_point
		_flank_point = Vector3.ZERO   # they walked round it; it is not cover now
	if now < _flank_ready_at:
		return Vector3.ZERO
	if fighter.global_position.distance_to(eye) < COVER_MIN_ENEMY:
		return Vector3.ZERO   # no line to break with someone on top of us
	_flank_point = _find_flank(game, arena, fighter.global_position, eye, ideal)
	if _flank_point == Vector3.ZERO:
		# Nothing here. Hold the failure, the same lesson `_cover_spot` learned:
		# a bot with nowhere to go must not rescan the window every think tick
		# for as long as it keeps losing, which is exactly when it is busiest.
		_flank_ready_at = now + FLANK_HOLD
		return Vector3.ZERO
	_flank_until = now + FLANK_HOLD
	_flank_ready_at = now + FLANK_HOLD + FLANK_REST
	if _log:
		print("[bot] %s flanks %s %.0f deg around, %.1fm (hp %d%% vs %d%%)" % [
				fighter.kit.name, enemy.kit.name,
				rad_to_deg((fighter.global_position - eye).angle_to(_flank_point - eye)),
				fighter.global_position.distance_to(_flank_point),
				int(100.0 * fighter.health / fighter.max_health),
				int(100.0 * enemy.health / enemy.max_health)])
	return _flank_point

## The best tile within FLANK_SCAN hidden from `eye` that also sits on a
## materially different bearing around the target than we do. That bearing term
## is the whole difference from `_find_cover`, which wants the NEAREST wall and
## would happily pick the one we are already standing behind.
func _find_flank(game, arena: Arena, pos: Vector3, eye: Vector3, ideal: float) -> Vector3:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	var here := pos - eye
	here.y = 0.0
	if here.length() < 0.001:
		return Vector3.ZERO
	var reach: float = float(fighter.kit.weapon.range)
	var best := Vector3.ZERO
	var best_score := -INF
	for dr in range(-FLANK_SCAN, FLANK_SCAN + 1):
		for dc in range(-FLANK_SCAN, FLANK_SCAN + 1):
			var c := col + dc
			var r := row + dr
			if c < 0 or c >= arena.columns or r < 0 or r >= arena.row_count:
				continue
			var centre: Vector3 = arena.tile_center(c, r)
			var trip := pos.distance_to(centre)
			if trip < Kits.TILE * COVER_MIN_TILES or trip > Kits.TILE * float(FLANK_SCAN):
				continue
			if arena.blocks_movement(centre) or not game.gas_contains(centre):
				continue
			# Stay in the fight. A flank that ends outside our own weapon range
			# is a retreat with extra steps, and the `hurt` ladder above is
			# where retreating is supposed to be decided.
			var hold := centre.distance_to(eye)
			if hold < ideal * 0.6 or hold > reach:
				continue
			var there := centre - eye
			there.y = 0.0
			if there.length() < 0.001:
				continue
			var turn := rad_to_deg(here.angle_to(there))
			if turn < FLANK_MIN_TURN:
				continue
			# Cheapest rejects first, exactly as in `_find_cover`: the two line
			# walks below are the expensive part and most of the window is
			# already gone by the time we reach them.
			if not _wall_between(arena, centre, eye):
				continue
			if not _walkable_line(arena, pos, centre):
				continue
			# Come back from as far round as we can get without spending the
			# whole fight walking, and without drifting off our ideal range.
			var score := (turn / 180.0) * 8.0 - trip * 0.6 - absf(hold - ideal) * 0.8
			if score > best_score:
				best_score = score
				best = centre
	return best

## The next step in that keeps a wall between us and the target. Vector3.ZERO
## when the ground in is open, which leaves the straight run in place — most
## approaches on this map have no covered step and should not pay for one.
func _approach_spot(now: float, game, enemy: Fighter) -> Vector3:
	var eye := enemy.global_position
	var arena: Arena = game.arena
	if now < _approach_until:
		if _approach_point == Vector3.ZERO:
			return Vector3.ZERO
		# Arrived, or it stopped being cover: fall through and re-score.
		if fighter.global_position.distance_to(_approach_point) > Kits.TILE * 0.5 \
				and _wall_between(arena, _approach_point, eye):
			return _approach_point
	_approach_point = _find_approach(game, arena, fighter.global_position, eye)
	_approach_until = now + APPROACH_HOLD
	if _log and _approach_point != Vector3.ZERO:
		print("[bot] %s closes on %s behind cover, %.1fm to the next step" % [
				fighter.kit.name, enemy.kit.name,
				fighter.global_position.distance_to(_approach_point)])
	return _approach_point

## The tile within FLANK_SCAN hidden from `eye` that gets us most of the way
## toward it. Distinct from `_find_cover` in the sign of what it wants: cover is
## somewhere to stop, this is somewhere to pass through on the way in.
func _find_approach(game, arena: Arena, pos: Vector3, eye: Vector3) -> Vector3:
	var col := int(floor(pos.x / Kits.TILE))
	var row := int(floor(pos.z / Kits.TILE))
	var mine := pos.distance_to(eye)
	var best := Vector3.ZERO
	var best_score := -INF
	for dr in range(-FLANK_SCAN, FLANK_SCAN + 1):
		for dc in range(-FLANK_SCAN, FLANK_SCAN + 1):
			var c := col + dc
			var r := row + dr
			if c < 0 or c >= arena.columns or r < 0 or r >= arena.row_count:
				continue
			var centre: Vector3 = arena.tile_center(c, r)
			var trip := pos.distance_to(centre)
			if trip < Kits.TILE * COVER_MIN_TILES or trip > Kits.TILE * float(FLANK_SCAN):
				continue
			# The cheapest reject there is, and it kills most of the window
			# before anything walks a line: a step that gains no ground is not
			# an approach whatever else is true of it.
			var gain := mine - centre.distance_to(eye)
			if gain < APPROACH_GAIN:
				continue
			if arena.blocks_movement(centre) or not game.gas_contains(centre):
				continue
			if not _wall_between(arena, centre, eye):
				continue
			if not _walkable_line(arena, pos, centre):
				continue
			var score := gain - trip * 0.5   # ground gained, less what it costs to walk
			if score > best_score:
				best_score = score
				best = centre
	return best

## Where to stand so that every step the target gives up is a step nearer the
## ring. Vector3.ZERO whenever the gas is not yet a threat to them, which leaves
## the plain strafe in place.
##
## This is the one offensive use of terrain that needs no search: the inside
## line is a bearing, not a tile.
func _gas_pressure_point(game, enemy: Fighter, ideal: float) -> Vector3:
	if not game.gas_closing():
		_pressing = false
		return Vector3.ZERO
	var epos := enemy.global_position
	if game.gas_depth(epos) > GAS_PRESSURE_DEPTH:
		_pressing = false
		return Vector3.ZERO
	var outward: Vector3 = epos - game.gas_safe_center()
	outward.y = 0.0
	if outward.length() < 0.001:
		_pressing = false
		return Vector3.ZERO
	# On the safe side of them, at our own ideal range. It has to be somewhere
	# we can stand and somewhere we would survive standing: herding a target
	# into the gas by walking into it ourselves is a trade we always lose.
	var spot: Vector3 = epos - outward.normalized() * ideal
	if game.arena.blocks_movement(spot) or not game.gas_contains(spot):
		_pressing = false
		return Vector3.ZERO
	if _log and not _pressing:
		print("[bot] %s takes the inside line on %s (%.1fm from the gas)" % [
				fighter.kit.name, enemy.kit.name, game.gas_depth(epos)])
	_pressing = true
	return spot

## Whether a wall stands between two points. Sampled against the map rather than
## raycast, so it costs no physics and agrees with a wall that `Arena.open_at`
## has already shot out. Only `#` blocks sight — water and bushes do not.
func _wall_between(arena: Arena, a: Vector3, b: Vector3) -> bool:
	var span := b - a
	span.y = 0.0
	var steps := int(ceil(span.length() / (Kits.TILE * 0.5)))
	for i in range(1, steps):
		if arena.tile_at(a + span * (float(i) / float(steps))) == "#":
			return true
	return false

## Whether a fighter can walk straight from one point to another. Mirrors
## `Arena._clear_line`, kept here so the bot depends only on Arena's public API.
func _walkable_line(arena: Arena, from: Vector3, to: Vector3) -> bool:
	var span := to - from
	span.y = 0.0
	var steps := int(ceil(span.length() / (Kits.TILE * 0.4)))
	for i in range(1, steps + 1):
		if arena.blocks_movement(from + span * (float(i) / float(steps))):
			return false
	return true

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
