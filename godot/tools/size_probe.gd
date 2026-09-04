extends SceneTree
## Diagnostic: per character GLB, the visual bounding box at Kits.MODEL_SCALE,
## against the capsule every fighter actually collides with. Run:
##   Godot --path godot --headless --script res://tools/size_probe.gd

const MODELS := ["tony", "henry", "sanjit", "kovacs", "leon", "anders", "hammy"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	print("capsule: radius %.2f  height %.2f (scale %.2f)"
			% [Kits.FIGHTER_RADIUS, 1.6, Kits.MODEL_SCALE])
	for model_name in MODELS:
		var path := "res://assets/%s.glb" % model_name
		if not ResourceLoader.exists(path):
			continue
		var model: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(model)
		var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
		if anim and anim.has_animation("Idle"):
			anim.play("Idle")
			anim.seek(0.0, true)
		# A skinned mesh's own AABB is authored in bind space and comes out
		# meaningless; the bone poses are what the silhouette actually follows.
		var box := AABB()
		var first := true
		var skels := model.find_children("*", "Skeleton3D", true, false)
		if not skels.is_empty():
			var skel: Skeleton3D = skels[0]
			skel.force_update_all_bone_transforms()
			for b in skel.get_bone_count():
				var o: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b)).origin
				if first:
					box = AABB(o, Vector3.ZERO)
					first = false
				else:
					box = box.expand(o)
		var s := Kits.MODEL_SCALE
		print("%-8s w %.2f  d %.2f  h %.2f   -> at scale: w %.2f  d %.2f  h %.2f  (r %.2f)"
				% [model_name, box.size.x, box.size.z, box.size.y,
				box.size.x * s, box.size.z * s, box.size.y * s,
				maxf(box.size.x, box.size.z) * s * 0.5])
		model.queue_free()
	quit()
	return true
