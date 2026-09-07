extends SceneTree
## Does a fighter actually FIT through the gaps in a map?
##
##   Godot --path godot --headless --script res://tools/fit_probe.gd
##   NS3_MAP=cup  Godot --path godot --headless --script res://tools/fit_probe.gd
##
## Since Kits.TILE == 2 * Kits.FIGHTER_RADIUS, a one-tile corridor is exactly as
## wide as a fighter, so whether one is passable rests entirely on
## Arena.TILE_COLLISION_SHRINK. That is invisible to NS3_SIM — bots path on the
## ASCII grid and slide along walls, so they route around a gap they cannot fit
## through and the balance table looks perfectly healthy while a player driving
## a stick straight at it jams. This probe is the check that sim cannot be.
##
## It is a STATIC fit test: place the fighter's own capsule at a tile centre and
## ask the physics server whether anything overlaps. No stepping, no bots.

func _initialize() -> void:
	var mode := OS.get_environment("NS3_MAP")
	if mode == "": mode = "showdown"
	var arena := Arena.new()
	arena.map_mode = mode
	root.add_child(arena)
	await process_frame
	await physics_frame

	var shape := CapsuleShape3D.new()
	shape.radius = Kits.FIGHTER_RADIUS
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = (1 << 0) | (1 << 1)      # walls | water, as Fighter uses
	# The ground slab is on the WALLS layer with its top at y = 0, which is
	# exactly where a fighter's capsule bottoms out — so without excluding it
	# every single open tile reports as blocked and the probe says the whole map
	# is unwalkable. Exclude it rather than lifting the capsule, so the test
	# stays at the height a fighter actually stands at.
	var ground := arena.get_node_or_null("Ground")
	if ground is CollisionObject3D:
		q.exclude = [(ground as CollisionObject3D).get_rid()]
	else:
		push_warning("no Ground body found - results will be meaningless")
	var space := arena.get_world_3d().direct_space_state

	var blocked_at := func(col: int, row: int) -> int:
		q.transform = Transform3D(Basis(), arena.tile_center(col, row) + Vector3(0, 0.8, 0))
		return space.intersect_shape(q, 8).size()

	var narrow: Array = []
	var open_tiles := 0
	for row in arena.row_count:
		for col in arena.columns:
			if arena.blocks_movement(arena.tile_center(col, row)): continue
			open_tiles += 1
			var h: bool = arena.blocks_movement(arena.tile_center(col - 1, row)) \
					and arena.blocks_movement(arena.tile_center(col + 1, row))
			var v: bool = arena.blocks_movement(arena.tile_center(col, row - 1)) \
					and arena.blocks_movement(arena.tile_center(col, row + 1))
			if h or v: narrow.append(Vector2i(col, row))

	var stuck := 0
	var worst: Array = []
	for t in narrow:
		var n: int = blocked_at.call(t.x, t.y)
		if n > 0:
			stuck += 1
			if worst.size() < 8: worst.append("%s(%d)" % [t, n])

	var jammed_anywhere := 0
	for row in arena.row_count:
		for col in arena.columns:
			if arena.blocks_movement(arena.tile_center(col, row)): continue
			if blocked_at.call(col, row) > 0: jammed_anywhere += 1

	print("map %s  %dx%d  TILE %.2f  fighter %.2f m wide  shrink %.2f"
			% [mode, arena.columns, arena.row_count, Kits.TILE,
			   Kits.FIGHTER_RADIUS * 2.0, Arena.TILE_COLLISION_SHRINK])
	print("  open tiles                  %d" % open_tiles)
	print("  one-tile-wide passages      %d" % narrow.size())
	print("  ...of those, UNFITTABLE     %d" % stuck)
	print("  unfittable open tiles (any) %d" % jammed_anywhere)
	if stuck > 0: print("  examples: %s" % ", ".join(worst))
	print("  VERDICT: %s" % ("every open tile fits a fighter"
			if jammed_anywhere == 0 else "FIGHTERS WILL GET STUCK"))
	quit(0 if jammed_anywhere == 0 else 1)
