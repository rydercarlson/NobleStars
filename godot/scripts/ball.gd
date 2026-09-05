class_name Ball
extends Node3D
## The Nobles Cup ball. Moves itself along the ground, bounces off walls and
## reports where it is; every rule about it (who may pick it up, what a goal
## is, when it resets) lives in cup_mode.gd.
##
## It is deliberately not a physics body. The arena is a tile grid, so
## reflecting off `Arena.blocks_movement` gives exact, predictable bounces —
## a RigidBody3D would let the ball creep into wall seams or squeeze through
## the goal posts, and a ball that resolves differently on host and client
## would be the worst possible thing to replicate later.

const RADIUS := 0.42
const BALL_MODEL := "res://assets/soccer_ball.glb"
const CARRY_HEIGHT := 1.25      # rides at chest height in front of the carrier
const CARRY_AHEAD := 0.85
## How far in the carry can be pulled, and the step it is walked back by. See
## _carry_point: a carrier pressed against a wall would otherwise hold the ball
## inside it.
const CARRY_MIN := 0.15
const CARRY_STEP := 0.05
const LOOSE_HEIGHT := RADIUS
## A kick leaves at KICK_SPEED and decays as v *= e^(-DRAG*t), so it runs out
## after (KICK_SPEED - STOP_SPEED) / DRAG metres: about 15 m, seven and a half
## tiles.
##
## This is halfway between the original 21 m/s launch and the slower 7 m/s
## tuning, keeping the ball readable without making every kick feel sluggish.
const KICK_SPEED := 14.0
const DRAG := 0.875

## The Super Shot. Brawl Ball's rule is that spending your Super on the ball
## "shoots it further and faster", and because drag is constant, one multiplier
## on the launch speed gives both at once: twice as fast, and twice as far —
## about 31 m, or fifteen and a half tiles.
const SUPER_KICK_MULT := 2.0
const STOP_SPEED := 0.6
## Walls take the sting out of a rebound rather than returning it.
const BOUNCE := 0.62
## How close a fighter must be to scoop up a loose ball.
const PICKUP_RADIUS := 1.25

## How far a kick of this power actually runs before it stops.
static func kick_range(speed_mult := 1.0) -> float:
	return (KICK_SPEED * speed_mult - STOP_SPEED) / DRAG

var velocity := Vector3.ZERO
var carrier: Fighter = null
## Nobody may pick the ball up before this — it gives a kick time to leave the
## kicker, so a shot isn't instantly re-caught by the fighter who took it.
var free_at := -1.0
## Who touched it last, for the "own goal" case and for goal credit.
var last_touch: Fighter = null

var _mesh: MeshInstance3D
var _shadow: MeshInstance3D

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.97, 0.94)
	mat.emission_enabled = true          # keeps it readable inside a bush
	mat.emission = Color(0.55, 0.55, 0.5)
	mat.emission_energy_multiplier = 0.35
	sphere.material = mat
	_mesh.mesh = sphere
	# The Meshy soccer ball when it shipped, else the plain sphere. Only the
	# mesh is swapped, so the rolling in _process keeps turning the same node.
	if ResourceLoader.exists(BALL_MODEL):
		var scene: PackedScene = load(BALL_MODEL)
		var root: Node3D = scene.instantiate() if scene != null else null
		if root != null:
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				if mi.mesh == null:
					continue
				_mesh.mesh = mi.mesh
				var aabb: AABB = mi.mesh.get_aabb()
				var span: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
				_mesh.scale = Vector3.ONE * (RADIUS * 2.0 / maxf(span, 0.01))
				for si in mi.mesh.get_surface_count():
					var m = mi.mesh.surface_get_material(si)
					if m is BaseMaterial3D:
						m.metallic = 0.0
						m.albedo_color = Color(1.0, 1.0, 1.0)
						m.emission_enabled = true      # same bush-readability trick, and
						m.emission = Color(0.6, 0.6, 0.56)   # a match ball reads bright
						m.emission_energy_multiplier = 0.45
				break
			root.queue_free()
	add_child(_mesh)

	# A flat disc under the ball: with the steep match camera a ball in the air
	# is otherwise impossible to place on the ground.
	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS * 0.9
	disc.bottom_radius = RADIUS * 0.9
	disc.height = 0.02
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0, 0, 0, 0.28)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = smat
	_shadow.mesh = disc
	add_child(_shadow)

func is_loose() -> bool:
	return carrier == null

func is_rolling() -> bool:
	return carrier == null and velocity.length() > STOP_SPEED

## Drops the ball at `pos` dead still — the kickoff, and where a carrier died.
func place(pos: Vector3, now: float, hold := 0.0) -> void:
	carrier = null
	velocity = Vector3.ZERO
	free_at = now + hold
	position = Vector3(pos.x, LOOSE_HEIGHT, pos.z)

func pick_up(f: Fighter) -> void:
	carrier = f
	last_touch = f
	velocity = Vector3.ZERO

func kick(dir: Vector3, now: float, arena: Arena, speed_mult := 1.0) -> void:
	var unit := Vector3(dir.x, 0, dir.z).normalized()
	if unit == Vector3.ZERO:
		return
	if carrier != null:
		# Launched from where the ball is actually being held, wall included:
		# a kick straight into a wall from point-blank used to start the ball
		# inside that tile, where _advance reverses it on both axes every frame
		# and it never gets out again.
		position = _carry_point(carrier, unit, arena)
		last_touch = carrier
	carrier = null
	position.y = LOOSE_HEIGHT
	velocity = unit * KICK_SPEED * speed_mult
	free_at = now + 0.28

## `_now` is unused: the ball's only clock is `free_at`, which kick() stamps and
## cup_mode reads. The parameter stays so both call sites there read alike.
func tick(delta: float, _now: float, arena: Arena) -> void:
	if carrier != null:
		if not is_instance_valid(carrier) or carrier.is_dead():
			# cup_mode drops it properly; this is only the safety net.
			carrier = null
		else:
			position = _carry_point(carrier, carrier.facing, arena)
			_spin_by(carrier.velocity * delta)
			_drop_shadow()
			return
	if velocity.length() <= STOP_SPEED:
		velocity = Vector3.ZERO
	else:
		_advance(delta, arena)
		velocity *= pow(exp(-DRAG), delta)
	position.y = LOOSE_HEIGHT
	_drop_shadow()

## Where a carrier facing `dir` holds the ball: CARRY_AHEAD in front, pulled in
## until the ball itself is clear of anything solid.
##
## A fighter's capsule is Kits.FIGHTER_RADIUS (0.65 m), so one pressed against a
## wall stands closer to it than the carry offset — the ball was held 0.2 m
## *inside* the wall tile, and since it rides at chest height its top
## (CARRY_HEIGHT + RADIUS = 1.67 m) is above Arena.WALL_HEIGHT, so it surfaced
## through the top of the wall and read as sitting on top of it. Pulling the
## carry in keeps the ball on the fighter's side of the wall; the alternative,
## carrying it lower, would only bury it instead.
##
## Stepped rather than solved: the probe is a tile lookup, and walking the reach
## back 5 cm at a time is a dozen of them at most on the frames it fires at all.
## The ball can never end up further in than the fighter's own chest, which is
## the CARRY_MIN floor, and a fighter is never inside a wall.
func _carry_point(who: Fighter, dir: Vector3, arena: Arena) -> Vector3:
	var from := who.global_position
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var reach := CARRY_AHEAD
	if arena != null and flat != Vector3.ZERO:
		# The far edge of the ball, not its centre: half a ball through a wall
		# face is just as visible as all of it.
		while reach > CARRY_MIN and arena.blocks_movement(from + flat * (reach + RADIUS)):
			reach -= CARRY_STEP
	return from + flat * reach + Vector3(0, CARRY_HEIGHT, 0)

## The shadow is a child of the ball, so it has to be pushed back down to the
## floor by however high the ball is riding. Only the mesh ever spins, so the
## disc stays flat without any counter-rotation.
func _drop_shadow() -> void:
	_shadow.position = Vector3(0, 0.03 - position.y, 0)

## Axis-separated so a glancing hit on a corner reflects on one axis only,
## which is what keeps the ball running along a wall instead of stalling in it.
func _advance(delta: float, arena: Arena) -> void:
	var step := velocity * delta
	var next := position + step
	if arena.blocks_movement(Vector3(next.x, 0, position.z)):
		velocity.x = -velocity.x * BOUNCE
		next.x = position.x
	if arena.blocks_movement(Vector3(position.x, 0, next.z)):
		velocity.z = -velocity.z * BOUNCE
		next.z = position.z
	# Diagonal into an inside corner: both axes were clear alone but the
	# destination is not, so back the ball straight off.
	if arena.blocks_movement(Vector3(next.x, 0, next.z)):
		velocity.x = -velocity.x * BOUNCE
		velocity.z = -velocity.z * BOUNCE
		next = position
	_spin_by(next - position)
	position = Vector3(next.x, LOOSE_HEIGHT, next.z)

## Rolls the mesh by however far the ball travelled, so it reads as rolling
## rather than sliding. Rotating the ball node would drag the shadow with it.
func _spin_by(travel: Vector3) -> void:
	var flat := Vector3(travel.x, 0, travel.z)
	if flat.length() < 0.0001:
		return
	var axis := Vector3.UP.cross(flat.normalized())
	if axis.length() < 0.0001:
		return
	_mesh.rotate(axis.normalized(), flat.length() / RADIUS)
