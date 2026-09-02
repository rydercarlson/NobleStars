class_name HackySack
extends Area3D
## Anders' rally sack — "Keep It Up".
##
## The sack travels in ARCS, not lines. Each kick is a hop: it lifts, floats
## across, and comes down on a landing spot, and only the landing does damage.
## That is the whole feel of the kit — a flat fast projectile reads as a bullet
## no matter what it is drawn as, and gives the target nothing to react to.
##
## One sack exists at a time. The player THROWS it — every throw is aimed, the
## same as any other kit's attack. It arcs out, damages whatever it lands on,
## and hops home. That hop home is the only automatic one, and it is the catch
## window: the ring on the floor shows where it comes down.
##
## Catching it is worth tempo, not automated damage. It blasts the ground at
## Anders, refunds his pip instantly, and steps his streak up so the NEXT throw
## lands harder. Drop it and he pays the full reload and the streak resets.
##
## It used to rally itself — after the opening kick the sack picked its own
## targets and kicked itself out again for two and a half seconds while the
## player could only walk. That is why it felt bad to play: one aimed input per
## ~3.6s against ~5.5 for everyone else, with the outcome decided by code. No
## Brawl Stars brawler has an automated loop as its BASIC attack; the
## auto-pilot pets are all Supers alongside an attack you still aim.

var weapon: Dictionary
var base_damage := 0
var owner_fighter: Fighter
var game: Node                     # main scene, for the fighter list

var rally := 1
## Uncapped run of consecutive catches, for display only.
var streak := 1
var on_enemy_hit := Callable()     # (Fighter target, HackySack sack)
var on_rally := Callable()         # (HackySack sack) — Anders kicked it again
var on_land := Callable()          # (Fighter or null, HackySack) — diagnostics
var on_box_hit := Callable()       # (Node box, HackySack)

## DAMAGE cap. `rally` is the damage step, seeded from Fighter.sack_streak at
## throw time and clamped here; `streak` is the uncapped count that the player
## actually sees. The number keeps climbing after the damage stops so a long
## run still reads as an achievement.
const MAX_RALLY := 3

## Tints by streak. Runs past the damage cap on purpose — 4+ is where the
## number is bragging rather than scaling, and it should look like it.
const STREAK_TINTS := [
	Color(1.00, 0.97, 0.75),   # 1  pale
	Color(1.00, 0.78, 0.30),   # 2  gold
	Color(1.00, 0.45, 0.20),   # 3  ember — damage caps here
	Color(1.00, 0.24, 0.42),   # 4  hot pink
	Color(0.72, 0.42, 1.00),   # 5  violet
	Color(0.35, 0.95, 1.00),   # 6+ white-blue
]
const LIFETIME := 6.0
const REACH := 7.5                 # too far from Anders to come home -> lost
## How close a landing has to be to connect. Comes from the kit so the aim
## preview ring and the real landing ring are the same circle.
var _land_radius := 1.0
const CATCH_BONUS := 0.3           # Anders is a bigger target: he wants it
const DAMAGE_RAMP := 0.25          # +25% per rally step
## Seconds; even a short hop keeps hang time so the sack reads as an arc rather
## than a teleport.
##
## ANYTHING THAT SHORTENS A RALLY ALSO RAISES ANDERS' FIRE RATE. His pip is
## locked while the sack is alive (`Fighter.ammo_locked`), so rally duration IS
## his reload — and MIN_HOP floors four of the five hops in a full rally, so it
## and `weapon.speed` between them set that duration. Both have bitten:
##
##   MIN_HOP 0.45 -> 0.30      attacks/life 4.3 -> 8.5, win rate 8.6% -> 25.6%
##   sack speed 1.70x -> 3.00x attacks/life 4.3 -> 7.4, win rate 8.6% -> 16.4%
##
## Neither was meant as an uptime change; both were. Measure `atk/spawn` in
## NS3_SIM after touching either, not just his damage. His BURST is capped by
## the one-sack-at-a-time rule, which is a mechanic question — the dials for it
## are `kick_damage_mult` and the damage ramp, not the timing constants.
const MIN_HOP := 0.45

## True once he has caught it, so _exit_tree can tell a catch from a drop.
var caught := false
## True while the sack is on its hop home; that hop is the last one it gets.
var _returning := false

var _age := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _dur := 0.6
var _height := 2.0
var _label: Label3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D

func rally_damage() -> int:
	return int(base_damage * (1.0 + DAMAGE_RAMP * float(rally - 1)))

## Damage of the blast Anders' kick puts out. Scaled by the rally like a
## landing is, so keeping the sack alive raises both halves of his output.
func kick_damage() -> int:
	return int(rally_damage() * float(weapon.get("kick_damage_mult", 0.0)))

## Called by the main scene right after spawning, with the player's aim point.
func launch_at(point: Vector3) -> void:
	_begin_hop(point, null)

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 0          # landings resolve by radius, not by overlap
	monitoring = false
	_land_radius = maxf(float(weapon.get("aoe", 1.0)), 0.6)
	# One pip, and it does not start refilling until the rally is over: the
	# reload is the price of ending a rally, not something that ticks during it.
	if is_instance_valid(owner_fighter):
		owner_fighter.ammo_locked = true

	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = weapon.radius
	mesh.height = weapon.radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.88, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.35, 0.25)
	mesh.material = mat
	visual.mesh = mesh
	add_child(visual)

	_build_marker()

	_label = Label3D.new()
	_label.font_size = 64
	_label.outline_size = 10
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.008
	_label.position.y = weapon.radius + 0.35
	add_child(_label)
	_refresh_rally_visuals()

## Flat ring on the floor at the landing spot. top_level keeps it out of the
## sack's transform so it stays on the ground while the sack arcs above it.
func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.top_level = true
	var ring := TorusMesh.new()
	# The full landing radius, so the circle IS the hit area rather than a
	# smaller decoration sitting inside it.
	ring.inner_radius = _land_radius * 0.86
	ring.outer_radius = _land_radius
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_mat.albedo_color = Color(1.0, 0.92, 0.35, 0.95)
	ring.material = _marker_mat
	_marker.mesh = ring
	# A TorusMesh is a 3D donut. Squash it flat so the ring reads as a decal
	# painted on the floor instead of a tube hovering over it.
	_marker.scale.y = 0.05
	add_child(_marker)

func _refresh_rally_visuals() -> void:
	var tint: Color = STREAK_TINTS[clampi(streak - 1, 0, STREAK_TINTS.size() - 1)]
	_label.text = "x%d" % streak
	_label.modulate = tint
	# Heavier outline and a brighter ring the longer the run goes, so a big
	# streak is legible at a glance without reading the digits.
	_label.outline_size = 10 + mini(streak - 1, 5) * 4
	_label.outline_modulate = Color(0.05, 0.03, 0.10, 0.9)
	_marker_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.95)
	# Punch the number on every step so it pops rather than just recolouring.
	if is_inside_tree():
		_label.scale = Vector3.ONE * (1.5 + 0.12 * float(mini(streak, 6)))
		create_tween().tween_property(_label, "scale", Vector3.ONE, 0.24) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Start an arc to `point`. `at` is the fighter being aimed at, if any, so the
## next hop can refuse to pick them again.
func _begin_hop(point: Vector3, at: Fighter) -> void:
	_from = global_position
	var aim := point
	if at != null and is_instance_valid(at) and at != owner_fighter:
		# Lead a rally hop. The sack floats for the better part of a second, so
		# aiming at where someone stands lands behind them every time.
		#
		# NEVER lead Anders himself. `at` is him on the hop home, and leading
		# threw the catch spot toward wherever he was already running — so
		# chasing his own sack walked him another step toward the enemy on every
		# rally. That feedback loop is why a mid-range skirmisher kept ending up
		# brawling in their face. Aim where he actually stands and let him hold
		# his ground; the rally now maintains its distance instead of collapsing.
		var rough := _from.distance_to(point) / maxf(1.0, float(weapon.speed))
		aim = point + Vector3(at.velocity.x, 0.0, at.velocity.z) * rough * 0.8
	_to = _clamp_to_open_ground(aim)
	_returning = at != null and at == owner_fighter
	_t = 0.0
	var dist := _from.distance_to(_to)
	# Hop time comes from distance, so a long kick genuinely hangs longer.
	_dur = maxf(MIN_HOP, dist / maxf(1.0, float(weapon.speed)))
	_height = clampf(1.3 + dist * 0.16, 1.5, 4.2)
	_marker.global_position = Vector3(_to.x, 0.04, _to.z)

## The sack ARCS, so it flies OVER walls like any thrower's shell — that is the
## point of a lobbed attack and it could not do it before, because this used to
## raycast the whole path and pull the landing up short of the first wall in
## the way. Only the LANDING has to be on open ground now.
func _clamp_to_open_ground(point: Vector3) -> Vector3:
	var b := Vector3(point.x, 0.5, point.z)
	if not _blocked_at(b):
		return b
	# Aimed into a wall: walk the landing back toward the thrower until it
	# clears, so it lands in front of the wall rather than inside it.
	var a := Vector3(global_position.x, 0.5, global_position.z)
	var back := a - b
	back.y = 0.0
	if back.length() < 0.01:
		return b
	back = back.normalized()
	for i in range(1, 15):
		var probe := b + back * (0.5 * float(i))
		if not _blocked_at(probe):
			return probe
	return a

## Is this spot inside wall geometry? Point test, not a path test — the sack is
## allowed to pass over anything on the way.
func _blocked_at(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	q.shape = sphere
	q.collision_mask = 1                    # walls
	q.transform = Transform3D(Basis(), p)
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME or not is_instance_valid(owner_fighter) or owner_fighter.is_dead():
		queue_free()
		return
	_t += delta
	var p: float = clampf(_t / _dur, 0.0, 1.0)
	var flat := _from.lerp(_to, p)
	global_position = Vector3(flat.x, flat.y + sin(PI * p) * _height, flat.z)
	rotate_y(6.0 * delta)
	if p >= 1.0:
		_land()

func _land() -> void:
	# Anders gets first refusal ON THE WAY HOME ONLY, and a wider radius:
	# getting back under it is the point, not a lucky overlap. Catching the
	# OUTBOUND throw would be free tempo for standing still — throw at your own
	# feet, catch instantly, refund the pip, repeat — so the return leg is a
	# precondition. The sack has to do its work before it is worth anything.
	if _returning and is_instance_valid(owner_fighter) and not owner_fighter.is_dead() \
			and _ground_gap(owner_fighter) <= _land_radius + CATCH_BONUS:
		if on_land.is_valid():
			on_land.call(owner_fighter, self)
		_recovered()
		return
	if _returning:
		# It came home and he was not under it. The sack is lost — that costs
		# him the pip and the streak, and is the entire price of a miss.
		if on_land.is_valid():
			on_land.call(null, self)
		queue_free()
		return
	var struck: Fighter = null
	for f in game.fighters:
		if not is_instance_valid(f) or f.is_dead() or f == owner_fighter:
			continue
		if _ground_gap(f) <= _land_radius:
			struck = f
			break
	# Power cube boxes resolve here too. The sack lands by radius rather than by
	# collision, so anything that is not a fighter is invisible unless it is
	# looked for by name.
	var hit_box := false
	for box in get_tree().get_nodes_in_group("lootbox"):
		if not is_instance_valid(box):
			continue
		var v := Vector2(global_position.x - box.global_position.x,
				global_position.z - box.global_position.z)
		if v.length() <= _land_radius + 0.5:
			hit_box = true
			if on_box_hit.is_valid():
				on_box_hit.call(box, self)
			break
	if on_land.is_valid():
		on_land.call(struck, self)
	if struck != null and on_enemy_hit.is_valid():
		on_enemy_hit.call(struck, self)
	# It only comes home if it DID something. A throw that lands on bare ground
	# is gone: no return leg, so no catch, so the full reload and the streak
	# reset. Accuracy is what buys the tempo.
	if struck != null or hit_box:
		_go_home()
	else:
		queue_free()

## Flat direction of the hop that just landed, for knockback.
func travel_dir() -> Vector3:
	var d := _to - _from
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD

func _ground_gap(f: Fighter) -> float:
	return Vector2(global_position.x - f.global_position.x,
			global_position.z - f.global_position.z).length()

## The offensive landing resolved. From here the sack always hops home — that
## return is the player's catch window and the only automatic hop left in the
## kit. It no longer chains on to the nearest fighter, and it no longer kicks
## itself back out: the next throw is an aimed input.
func _go_home() -> void:
	if is_instance_valid(owner_fighter) and not owner_fighter.is_dead() \
			and _ground_gap(owner_fighter) <= REACH:
		_begin_hop(owner_fighter.global_position, owner_fighter)
		return
	queue_free()            # too far from him to come back; the sack is lost

## He got under it. The catch ENDS the sack — it does not kick itself back out
## any more. `on_rally` is where the blast, the pip refund and the streak step
## happen (main.gd `_on_sack_caught`), and the next throw is the player's.
func _recovered() -> void:
	caught = true
	_bounce_pulse()
	if on_rally.is_valid():
		on_rally.call(self)
	queue_free()

func _exit_tree() -> void:
	if not is_instance_valid(owner_fighter):
		return
	owner_fighter.ammo_locked = false
	# Dropping it resets the streak. Catching is what keeps the cycle going, so
	# losing the sack has to cost the thing catching earns.
	if not caught:
		owner_fighter.sack_streak = 0

func _bounce_pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.4, 0.72, 1.4), 0.06)
	tw.tween_property(self, "scale", Vector3.ONE, 0.10)
