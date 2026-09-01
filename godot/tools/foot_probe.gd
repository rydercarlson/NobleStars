extends SceneTree
## Diagnostic: for each character GLB, sample every animation clip and report the
## lowest world-space Y any foot/toe bone reaches, plus the mesh AABB floor. A
## negative number means the feet sink below the arena floor plane at y=0. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --path godot --headless \
##       --script res://tools/foot_probe.gd

const MODELS := ["tony", "henry", "sanjit", "kovacs", "leon"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	for model_name in MODELS:
		var path := "res://assets/%s.glb" % model_name
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		var model: Node3D = scene.instantiate()
		root.add_child(model)
		var skels := model.find_children("*", "Skeleton3D", true, false)
		var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
		if skels.is_empty() or anim == null:
			print("%s: no skeleton/animation" % model_name)
			continue
		var skel: Skeleton3D = skels[0]

		var feet: Array[int] = []
		for b in skel.get_bone_count():
			var bn := skel.get_bone_name(b).to_lower()
			if bn.contains("foot") or bn.contains("toe"):
				feet.append(b)

		# Idle at t=0 is the reference height fighter.gd calibrates against.
		anim.play("Idle")
		anim.seek(0.0, true)
		var rest_y := _lowest_foot(skel, feet)
		print("== %s (%d foot bones, idle rest y = %+.3f)" % [model_name, feet.size(), rest_y])
		for clip in anim.get_animation_list():
			var a: Animation = anim.get_animation(clip)
			var lowest := 1e9
			var steps := 24
			anim.play(clip)
			for i in steps + 1:
				anim.seek(a.length * float(i) / steps, true)
				lowest = minf(lowest, _lowest_foot(skel, feet))
			print("   %-28s lowest foot y = %+.3f   lift applied = %.3f"
					% [clip, lowest, maxf(0.0, rest_y - lowest)])
		model.queue_free()
	quit()
	return true


func _lowest_foot(skel: Skeleton3D, feet: Array[int]) -> float:
	skel.force_update_all_bone_transforms()
	var skel_xform := skel.get_global_transform()
	var lowest := 1e9
	for b in feet:
		lowest = minf(lowest, (skel_xform * skel.get_bone_global_pose(b)).origin.y)
	return lowest
