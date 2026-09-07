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
##
## OVER WIFI this object exists on every peer, but only the HOST runs the rules.
## A client's copy is a presentation layer: `authoritative` is false, so tick()
## takes the branch that writes the score, the clock and the ball straight out of
## the snapshot stream and returns, and every rule below it — pickups, goals,
## carrier checks, the clock, respawns — is skipped. That is the same split
## GasRing already uses, where a client builds the node and never calls start().
## Everything a client cannot infer from state (a goal, a knock-out, a kickoff, a
## kick's sound) arrives instead as a reliable RPC from main.gd's net section.

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
## 6 m is 4.6 tiles on the 21x33 pitch, about a seventh of its length — the
## same share it was before the tile rescale (3 tiles of 2 m on a 23-row
## pitch), so this did not need retuning when the unit changed.
const SHOT_RANGE := 6.0

## A Super's knock this hard or harder shakes the ball loose. It is a floor, not
## the rule — see _carrier_check and _knock_was_super for what actually decides.
const KNOCK_DROP_SPEED := 3.0

## What a Super that strips the ball does to it. A strip is not a pass: the ball
## keeps some of the shove so it reads as knocked away rather than put down, but
## it is capped well inside a kick, because a ball that outran a kick would make
## "have a team-mate hit you" the fastest way up the pitch. The hardest Super in
## the roster (Anders, 14) gets KNOCK_BALL_MAX, which coasts about 6 m (4.6
## tiles) against a normal kick's 15 m (11.8 tiles) — so a strip can never be a
## shot from anywhere a kick could not already have been taken.
## Derived from the same dial as Ball's own constants, so a strip still coasts
## ~6 m at any speed setting.
## Re-tuned alongside Ball.STOP_SPEED: these are LAUNCH speeds fed into the same
## drag, so raising the speed the ball stops at shortens every one of them. Set
## so the hardest Super in the roster (Anders, 14) clamps at MAX and coasts ~3.5
## tiles, against a kick's 8 — knocked away, never a shot.
const KNOCK_BALL_PER_STRENGTH: float = Kits.SPEED_NORMAL * 0.15
const KNOCK_BALL_MIN: float = Kits.SPEED_NORMAL * 0.802
const KNOCK_BALL_MAX: float = Kits.SPEED_NORMAL * 1.765
## How long the ball cannot be picked up after it is shaken loose. Long enough
## that the shove actually separates the carrier from it.
const KNOCK_BALL_HOLD := 0.35

## Group on the scoreboard's root node, so a leftover from a previous match can
## be found on main.gd's HUD layer and cleared.
const HUD_GROUP := "cup_hud"

var game                          # main.gd; typed loosely, as BotBrain does
## False on a wifi client, where every rule in this file belongs to the host.
## Mirrors main.gd's own flag rather than being a second source of truth.
var authoritative := true
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
## Every fighter's own kickoff tile, decided once when the match is built and
## read by every kickoff after it.
##
## This used to be two arrays of spots that build_match and kickoff each walked
## with their own counter, and when those two counters disagreed every fighter
## was teleported onto a team-mate's tile on the opening frame, where the
## overlapping capsules depenetrated hard enough to fire them off the pitch and
## several hundred metres into the air. Storing the answer per fighter instead of
## the recipe for computing it twice is what makes that impossible — and it is
## also what lets a wifi client agree with the host, since the host simply sends
## each fighter's spot index in the match roster.
var _kick_spot: Dictionary = {}   # Fighter -> Vector3
var _score_label: Label
var _clock_label: Label
var _banner: Label

## NS3_BALL_LOG=1: every time the ball leaves a pair of hands, and how far it
## then ran before it stopped or was collected. The two complaints this exists to
## settle — "a knock sends the ball further than a kick" and "a tap does one of
## two different things" — are both claims about a DISTANCE, which is exactly
## what a screenshot cannot show and what one match cannot average. Same
## instrument as NS3_SAVE_LOG and NS3_BOT_LOG: it tells "the rule never matched"
## apart from "the situation never arose".
var _ball_log := OS.get_environment("NS3_BALL_LOG") != ""
var _loose_from := Vector3.ZERO
var _loose_why := ""
var _loose_open := false
var _loose_rest := -1.0

func _log_loose(why: String, from: Vector3) -> void:
	if not _ball_log:
		return
	if _loose_open:
		_log_settled("taken again")
	_loose_from = from
	_loose_why = why
	_loose_open = true
	_loose_rest = -1.0

## Flat distance: the ball's y never changes while it is loose, and the drop
## point is read off a fighter whose own y is not the ball's, so the straight
## distance carries a constant offset that hides exactly the number being
## measured — a dead-still drop reported 0.42 m of travel.
func _flat_from_loose() -> float:
	return Vector2(ball.position.x - _loose_from.x, ball.position.z - _loose_from.z).length()

func _log_settled(how: String) -> void:
	if not _ball_log or not _loose_open:
		return
	_loose_open = false
	print("[ball] %6.1fs %-26s ran %6.2f m%s -> %s" % [
			MATCH_SECONDS - clock, _loose_why, _flat_from_loose(),
			"" if _loose_rest < 0.0 else " (rest %5.2f)" % _loose_rest, how])

# MARK: setup

## Fills both teams and puts the ball on the centre spot. The arena is already
## built by the time this runs — main.gd sets Arena.map_mode before adding it.
##
## Single-player only. Over wifi the host deals the roster instead and main.gd
## spawns from it on every peer, then calls adopt_net_match() — see there.
func build_match(now: float) -> void:
	var arena: Arena = game.arena
	for team in 2:
		# Shuffled so the player, who is always team 0 slot 0, does not open every
		# single match on the same tile at the left end of the kickoff row.
		var spots: Array = arena.team_spawns[team].duplicate()
		spots.shuffle()
		# One lineup PER SIDE: no character appears twice on a team, and the two
		# sides are dealt independently, so the same character may well line up
		# opposite themselves. That is Brawl Ball's own rule and it is deliberate
		# — a mirror is a legitimate matchup, and forbidding it would quietly
		# shrink the pool the second team draws from.
		var roster: Array = game.lineup_kits(TEAM_SIZE,
				game.player_kit() if team == 0 else {})
		for i in TEAM_SIZE:
			var spot: Vector3 = spots[i % spots.size()] if not spots.is_empty() \
					else arena.centre()
			var is_you := team == 0 and i == 0
			var kit: Dictionary = roster[i]
			var f: Fighter = game._spawn_fighter(kit, spot, is_you, team)
			f.display_name = "You" if is_you else game.next_bot_name()
			_kick_spot[f] = spot
			if is_you:
				game.player = f
			# NS3_AUTOPLAY hands the player's own slot to a brain as well, so a
			# match run from the command line is 3v3 rather than a 2v3 against
			# somebody standing on the kickoff spot. main.gd skips its own input
			# block in the same breath, so the fighter is only moved once a frame.
			if not is_you or game.autoplay:
				game.brains.append(BotBrain.new(f))

	if _ball_log:
		for team in 2:
			var names: Array = []
			for f: Fighter in game.fighters:
				if f.team == team:
					names.append(f.kit.name)
			print("[ball] team %d: %s" % [team, ", ".join(names)])
	ball = Ball.new()
	game.add_child(ball)
	ball.place(arena.centre(), now)
	_build_hud()
	kickoff(now, true)

## Wifi play: the fighters already exist. main.gd spawned them from the host's
## roster on every peer — same kits, same teams, same order, same indices — so
## all this has left to do is remember where each one kicks off from and start
## the match the way build_match ends.
##
## `spots` is parallel to `game.fighters`, which is safe here in a way it is not
## in Showdown: a Cup death parks a fighter rather than freeing it, so that array
## never shrinks and index i means the same fighter on both machines for the
## whole match. It comes from the host so that both sides teleport everyone to
## the SAME tiles on every kickoff; deriving it locally from a shuffle would put
## two fighters on one tile the moment the two shuffles disagreed.
func adopt_net_match(now: float, spots: Array) -> void:
	for i in game.fighters.size():
		if i < spots.size():
			_kick_spot[game.fighters[i]] = spots[i]
	ball = Ball.new()
	game.add_child(ball)
	ball.place(game.arena.centre(), now)
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

## How much of the kickoff hold is left, for the snapshot. Sent as a remaining
## duration rather than as `_frozen_until`, which is a point on the host's clock
## and means nothing on anyone else's.
func frozen_left(now: float) -> float:
	return maxf(0.0, _frozen_until - now)

## Both teams back to their spawns, ball on the centre spot, everyone held for
## a beat. Used for the opening whistle and after every goal.
func kickoff(now: float, opening := false) -> void:
	var arena: Arena = game.arena
	for f: Fighter in game.fighters:
		if f.team < 0:
			continue
		var spot: Vector3 = _kick_spot.get(f, arena.centre())
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
	_log_settled("kickoff reset")
	ball.place(arena.centre(), now, KICKOFF_FREEZE)
	ball.last_touch = null
	_frozen_until = now + KICKOFF_FREEZE
	# The opening whistle is main.gd's 3-2-1-FIGHT!; only a restart after a
	# goal needs the score put back up, and only that restart is whistled.
	_banner.text = "" if opening else "%d — %d" % [score[0], score[1]]
	if not opening:
		game.sfx_ui("cup_whistle", -2.0)
	# Announced from HERE rather than from each of the three callers, so a
	# restart can never reach one machine and not the other. A client runs this
	# same function on receipt: every fighter's kickoff tile is in _kick_spot on
	# both sides, so the two teleport everyone to the same places.
	if authoritative:
		game.net_cup_kickoff(opening)

## A wifi client's tick. No rule runs: the score, the clock, the freeze and who
## is holding the ball all came down in the last snapshot, and everything else a
## client needs to know arrived as an event.
##
## The ball is ticked ONLY while it is carried. That path reads the carrier's
## position and facing and writes nothing else, so it costs nothing and it is
## right on both halves of the split — the carrier is either this client's own
## predicted fighter, where the ball tracking it immediately is the whole point,
## or an interpolated puppet already drawn where the host had it. A LOOSE ball is
## not simulated at all; it is interpolated straight from the stream by
## main.gd:_net_render_puppets, because its path is decided by wall bounces that
## a client would have to reproduce exactly, and exact reproduction is the one
## thing an unreliable stream cannot promise.
func _client_tick(delta: float, now: float) -> void:
	if ball.carrier != null:
		ball.tick(delta, now, game.arena)
	# Mirrors the host's own banner rule rather than being pushed over the wire:
	# it is a pure function of the freeze clock and the overtime flag, both of
	# which are already in the snapshot.
	if frozen(now):
		if int(ceil(_frozen_until - now)) <= 1 and not overtime:
			_banner.text = "GO!"
	else:
		_banner.text = ""
	_refresh_hud()

## Client: attach or release the ball for the LOCAL player only, from the newest
## snapshot rather than the delayed one.
##
## Everything else about the ball can afford the interpolation delay, because
## everything else about it is something you are watching. This is the one part
## you are doing, and 85 ms between running over a ball and holding it is the
## difference between the mode feeling responsive and feeling remote.
func apply_local_carry(carrier_idx: int, my_idx: int) -> void:
	if my_idx < 0:
		return
	var me: Fighter = game.player
	if not is_instance_valid(me):
		return
	if carrier_idx == my_idx:
		if ball.carrier != me and not me.is_dead():
			ball.pick_up(me)
	elif ball.carrier == me:
		# Somebody took it off me. Released here and left loose; the real
		# carrier is attached by apply_net_state when the delayed clock reaches
		# the packet that says who.
		ball.carrier = null

## Client: take the match state out of a snapshot. Called from main.gd at the
## same delayed instant the puppets are drawn at, so the score changes on the
## frame the goal is drawn rather than a fifteenth of a second before it.
func apply_net_state(now: float, st: Dictionary) -> void:
	score[0] = int(st.s0)
	score[1] = int(st.s1)
	clock = float(st.clock)
	overtime = bool(st.overtime)
	finished = bool(st.finished)
	# Sent as time REMAINING rather than as an absolute deadline: the two clocks
	# are minutes apart and only the difference means anything.
	_frozen_until = now + float(st.freeze)
	var idx := int(st.carrier)
	# My own carry is owned by apply_local_carry, off the newest packet. This
	# runs on OLDER ones, so letting it near the local case would walk that
	# straight back: the ball would stick, then come loose again a frame later
	# when a stale packet said it was still on the grass.
	if idx == game._my_idx or ball.carrier == game.player:
		return
	var who: Fighter = null
	if idx >= 0 and idx < game.net_fighters.size():
		var cand = game.net_fighters[idx]
		if cand != null and is_instance_valid(cand) and not cand.is_dead():
			who = cand
	if who == null:
		ball.carrier = null
	elif ball.carrier != who:
		ball.pick_up(who)

## Which way a team is attacking: toward the goal it does NOT defend.
func _attack_dir(team: int) -> Vector3:
	var arena: Arena = game.arena
	return (arena.goal_centers[1 - team] - arena.goal_centers[team]).normalized()

func tick(delta: float, now: float) -> void:
	if finished:
		return
	if not authoritative:
		_client_tick(delta, now)
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
	# Where it came to rest is noted rather than reported: the entry stays open so
	# the line that eventually prints says who collected it, which is the half of
	# a turnover that matters.
	if _loose_open and _loose_rest < 0.0 and ball.carrier == null \
			and ball.velocity == Vector3.ZERO:
		_loose_rest = _flat_from_loose()
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

## What shakes the ball loose. Brawl Ball's rule is that a carrier drops it when
## stunned, knocked back or defeated; a dash and a jump-smash are added to that
## here, because both are a fighter throwing itself across the pitch and carrying
## the ball through one would make every mobility Super a free run at the goal.
##
## A knock only counts when it came from a SUPER, and that is the whole of this
## rule's history. It used to be a bare speed threshold on `knockback_vel`, and
## measured over a full match (NS3_BALL_LOG=1) what that actually did was let
## **Kovacs' clap** strip the carrier every time it landed — a basic attack, on a
## normal reload, across a 2.4-tile 78-degree cone. Nothing else in the roster
## takes the ball off you with its regular attack, and nothing should.
##
## No number can separate the two, which is why the fix is not a bigger
## threshold: his clap shoves at 4.0, exactly as hard as Sanjit's Super does.
## What separates them is where the shove came from, so main.gd's deal_damage
## sends the attacker along with the impulse and `_knock_was_super` asks whether
## it was harder than that attacker's own weapon.
func _carrier_check(now: float) -> void:
	var c: Fighter = ball.carrier
	if c == null:
		return
	if not is_instance_valid(c) or c.is_dead():
		var where := _free_spot(c.global_position if is_instance_valid(c) else game.arena.centre())
		_log_loose("death", where)
		ball.place(where, now, 0.35)
		return
	if c.is_dashing() or c.is_leaping():
		# Dropped where they were standing, not where they end up: the ball
		# stays behind and the dash or the leap is what separates them from it.
		var where := _free_spot(c.global_position)
		_log_loose("dash/leap %s" % c.kit.name, where)
		ball.place(where, now, 0.35)
		return
	if _knock_was_super(c) and c.knock_strength > KNOCK_DROP_SPEED:
		# Knocked away rather than put down, and in the direction of the shove.
		# `knock_strength` is the impulse as DEALT: `knockback_vel` has already
		# decayed by the time this runs, and how hard the Super hit is the whole
		# input to how far the ball goes.
		var where := _free_spot(c.global_position)
		_log_loose("knock %s %.1f by %s" % [c.kit.name, c.knock_strength,
				c.knock_from.kit.name], where)
		ball.knock_loose(where, c.knock_dir,
				clampf(c.knock_strength * KNOCK_BALL_PER_STRENGTH,
						KNOCK_BALL_MIN, KNOCK_BALL_MAX),
				now, KNOCK_BALL_HOLD)
		# The shove is spent the moment it takes the ball. It outlives the ball's
		# own pickup hold by a wide margin — 0.58s against 0.35s for a 10 m/s
		# knock — so without this the carrier re-collects while still carrying a
		# live knock record and is stripped again on the next frame, and again:
		# three strips off one Kovacs Super, measured.
		c.forget_knock()

## Whether the shove currently on `f` came from a Super rather than from someone's
## regular attack. Measured against the attacker's OWN weapon rather than against
## a constant, because a constant cannot tell them apart — Kovacs' clap and
## Sanjit's Super both shove at 4.0. Every kit gives its Super more knockback
## than its weapon (Kovacs 10 against 4, Leon 5 against 1.5, Anders 14 against 3,
## and the other six put no knockback on the weapon at all), so "harder than
## their own attack" IS "their Super", and it stays true for a kit added later
## without anything here being retuned.
##
## `knock_from` is cleared the moment the shove decays (Fighter._forget_knock),
## so this can never read a stale attacker from an exchange that is already over.
static func _knock_was_super(f: Fighter) -> bool:
	var from: Fighter = f.knock_from
	if not is_instance_valid(from):
		return false
	return f.knock_strength > float(from.kit.weapon.get("knockback", 0.0))

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
		if best == game.player:
			Haptics.fire("ball_get")
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
		_log_settled("%s (%s)" % [best.kit.name,
				"same team" if is_instance_valid(ball.last_touch) and ball.last_touch.team == best.team
				else "turnover"])
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
## A ball still travelling with purpose — about 31% of a kick's launch speed.
## Raised with Ball.STOP_SPEED, which the ball now stops at 0.42x a run: a
## threshold below that would have counted every dribble as a save.
const SAVE_SPEED: float = Kits.SPEED_NORMAL * 1.1
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
		# Which mouth tile is emptiest is decided by positions the client only
		# has a delayed copy of, so the spot is chosen HERE and sent, never
		# recomputed at the other end.
		var spot := _spawn_for(f)
		f.respawn(spot, now)
		game.net_cup_respawned(f, spot)

## Nobles Cup death: park the fighter and book its return. Overtime is sudden
## death, so a fighter that falls then stays down.
## Runs on every peer: a client is told about a knock-out by _net_cup_down and
## comes through here too, because parking the body, the feed line and the health
## bar going away are all things it has to do for itself. What a client does NOT
## do is decide anything — where the ball ends up comes down in the stream, and
## the return is booked by the host and announced by _net_cup_respawn. Ball.tick
## drops a dead carrier on its own, so the client needs no placement here.
func on_death(f: Fighter, killer: String) -> void:
	if authoritative and ball.carrier == f:
		ball.place(_free_spot(f.global_position), game.now, 0.35)
	f.knock_out()
	game.feed_label.text = "%s eliminated %s" % [killer, f.display_name] if killer != "" \
			else "%s went down" % f.display_name
	if authoritative and not overtime:
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
		var p := origin + Vector3(cos(ang), 0, sin(ang)) * Kits.TILE * 1.54
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
	_log_settled("GOAL for team %d" % scorer)
	score[scorer] += 1
	var who: String = ball.last_touch.display_name if is_instance_valid(ball.last_touch) \
			else "Somebody"
	var own := is_instance_valid(ball.last_touch) and ball.last_touch.team == conceded
	if is_instance_valid(ball.last_touch) and not own:
		ball.last_touch.stats.goals += 1
	goal_effects(conceded, who, own)
	game.net_cup_goal(conceded, who, own)
	_refresh_hud()
	if score[scorer] >= GOALS_TO_WIN or overtime:
		_finish(now)
	else:
		kickoff(now)
	return true

## Everything a goal LOOKS like, kept apart from everything it decides. A wifi
## client is handed the three facts it cannot work out for itself — which end was
## conceded, who put it in, and whether they meant to — and runs this; the host
## runs it too, on its way through _goal_check. One body of code, so the goal
## that a client sees cannot drift from the goal the host scored.
func goal_effects(conceded: int, who: String, own: bool) -> void:
	game.feed_label.text = "%s scored%s" % [who, " (own goal)" if own else ""]
	game.sfx_ui("cup_goal", 2.0)
	# Scored FOR your side, whoever put it in — an own goal by the opposition is
	# still your goal, which is why this reads the conceding team and not the
	# last touch. A spectating net client has no side and gets nothing.
	if is_instance_valid(game.player) and game.player.team >= 0:
		Haptics.fire("goal_against" if game.player.team == conceded else "goal_for")
	# Hold on the goal that was just conceded through most of the kickoff
	# freeze, then hand the camera back in time for play to restart. Ahead of
	# kickoff(), which teleports everyone — the point is not to watch that.
	# Pulled back onto the pitch rather than sat on the goal line: a goal is at
	# the very edge of the map, so framing it dead centre fills the top half of
	# the screen with sky past the end of the arena.
	game.focus_camera(game.arena.goal_centers[conceded].lerp(game.arena.centre(),
			GOAL_CAMERA_INSET), GOAL_CAMERA_HOLD)
	_refresh_hud()

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
	if _ball_log:
		# Quits at the whistle on purpose, the way NS3_SHOTS does: a Cup match can
		# be over in twenty seconds and the results card holds the process open
		# for the other two minutes, so without this a batch of matches is mostly
		# spent waiting on nothing.
		print("[ball] full time %d — %d" % [score[0], score[1]])
		game.get_tree().quit()
		return
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
	_log_loose("%s %s" % ["super kick" if use_super else "kick", f.kit.name], ball.position)
	# A Super Shot is twice the ball speed, so it gets the Super's own sound
	# rather than a louder boot.
	game.sfx_at("super_fire" if use_super else "cup_kick", f.global_position,
			3.0 if use_super else 0.0)
	# A kick never reaches perform_attack — main.gd:_fire_player returns as soon
	# as this claims the input — so the Super Shot had no haptic at all, and the
	# plain kick, the thing you do all match, had none either. Both come from
	# here for the same reason their sounds do.
	# A Super Shot is its own entry rather than the kit's Super, because it is a
	# ball launch whatever the kit would otherwise have done — routing it
	# through super_fired would put a dash's rumble bed under a kick.
	if f == game.player:
		Haptics.fire("super_shot" if use_super else "kick")
	f.face_direction(dir)
	f.play_attack_animation(now, use_super)
	# Announced from HERE, not from main.gd's _net_fire handler, because that
	# only ever sees a REMOTE PLAYER's kick — and most of the kicking in a Cup
	# match is done by bots, whose kicks come through the brain loop and would
	# have reached the other machines silently. Every kick in the game funnels
	# through this one call, which is the only place that covers all three.
	game.net_cup_kick(f, use_super)
	return true

## Where a tap-to-kick sends the ball, AND what it is doing with it: a shot at
## the goal being attacked, a pass to a team-mate better placed than you, or a
## clearance upfield when there is neither. A Super Shot reaches twice as far, so
## it goes for goal from twice as far out.
##
## The three cases were always here; what is new is saying which one out loud.
## main.gd's aim indicator draws `at` as a ring under the player's thumb, because
## the rule turns on a distance that appears nowhere on screen — so a tap did one
## of two quite different things and there was no way to know which in advance.
## Returned as a plan rather than computed twice: the drawing and the kick have
## to agree, and a second copy of this is how they would stop agreeing.
##
## `kind` is "shot", "pass" or "clear". A clearance is aimed at the goal like a
## shot but by definition cannot reach it, which is why it is named separately.
## `allow_pass` is FALSE for the player's own tap and true for bots. A tapped
## kick used to hunt for the team-mate nearest the goal and lock onto them,
## which is a lock-on: it picks a receiver for you, and the ball leaves in a
## direction you did not choose and cannot read off your own facing. It is the
## same objection CLAUDE.md already records against the attack indicator
## previewing auto-aim's pick — aiming is meant to be the thing you get good at.
## So the player gets exactly two outcomes: **in range of the goal it locks onto
## the goal, and otherwise it goes where you are facing.** Bots keep the pass
## search, because a bot has no drag to fall back on and a 3v3 where nobody
## passes is not the mode.
func kick_plan(f: Fighter, powerful := false, allow_pass := true) -> Dictionary:
	var goal: Vector3 = game.arena.goal_centers[1 - f.team]
	var to_goal: float = f.global_position.distance_to(goal)
	# SHOT_RANGE, not the ball's full coast: the two have to agree, or a bot
	# that released the ball under pressure from well outside its own shooting
	# range still had this aim it at the goal, and hit.
	var reach: float = SHOT_RANGE * (Ball.SUPER_KICK_MULT if powerful else 1.0)
	if to_goal <= reach and game.has_line_of_sight(f.global_position, goal):
		return {"kind": "shot", "at": goal, "dir": goal - f.global_position}
	# Everything past here is the pass search, which the player's tap skips.
	if not allow_pass:
		return {"kind": "clear", "at": f.global_position + f.facing * Ball.kick_range(
				Ball.SUPER_KICK_MULT if powerful else 1.0), "dir": f.facing}
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
		return {"kind": "pass", "at": best.global_position,
				"dir": best.global_position - f.global_position}
	return {"kind": "clear", "at": goal, "dir": goal - f.global_position}

## The direction half of kick_plan, for the callers that only kick with it.
func kick_aim(f: Fighter, powerful := false, allow_pass := true) -> Vector3:
	return kick_plan(f, powerful, allow_pass).dir
