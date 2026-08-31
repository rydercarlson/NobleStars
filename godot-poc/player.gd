extends CharacterBody3D
# WASD movement (physical keys, no input-map setup needed) driving a rigged
# animated GLB model — the pipeline a Meshy character would use.

const SPEED := 7.0

@onready var anim_player: AnimationPlayer = get_node_or_null("Fox/AnimationPlayer")

func _physics_process(_delta: float) -> void:
	var dir := Vector3.ZERO
	if OS.get_environment("POC_AUTOWALK") != "":
		dir = Vector3(0.8, 0, -0.5)
	else:
		if Input.is_physical_key_pressed(KEY_W): dir.z -= 1
		if Input.is_physical_key_pressed(KEY_S): dir.z += 1
		if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): dir.x += 1
	dir = dir.normalized()

	velocity = dir * SPEED
	move_and_slide()

	if dir != Vector3.ZERO:
		rotation.y = atan2(-dir.x, -dir.z) + PI
		if anim_player and anim_player.current_animation != "Run":
			anim_player.play("Run")
	elif anim_player and anim_player.current_animation != "Survey":
		anim_player.play("Survey")
