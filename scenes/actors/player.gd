extends CharacterBody3D

## Placeholder player. Analog walk/run ratio from `m_player_main_walk` (4.875 vs 7.5 game units).

const WALK_SPEED := 1.8
const SPRINT_SPEED := 2.8

@onready var _mesh: Node3D = $MeshPivot

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := get_viewport().get_camera_3d()
	var look := Vector3.FORWARD
	var right := Vector3.RIGHT
	if cam != null:
		look = -cam.global_transform.basis.z
		look.y = 0.0
		if look.length_squared() > 0.0001:
			look = look.normalized()
		right = cam.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()

	var direction := look * -input_dir.y + right * input_dir.x
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if direction.length_squared() > 0.0001:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, atan2(direction.x, direction.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
