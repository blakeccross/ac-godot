extends CharacterBody3D

## Placeholder player. Analog walk/run ratio from `m_player_main_walk` (4.875 vs 7.5 game units).
## One locked action at a time (`m_player` main index), facing-tile interact (`docs/decomp_notes/interaction.md`).

const WALK_SPEED := 1.8
const SPRINT_SPEED := 2.8

@onready var _mesh: Node3D = $MeshPivot
@onready var _probe: Area3D = $MeshPivot/InteractProbe

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _busy: bool = false
var _focus: Node = null


func _ready() -> void:
	add_to_group("player")


func facing_yaw() -> float:
	return _mesh.rotation.y


func apply_spawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	_mesh.rotation.y = yaw


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var direction := Vector3.ZERO
	if not _busy:
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
		direction = look * -input_dir.y + right * input_dir.x
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
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _update_focus() -> void:
	var next: Node = _nearest_interactable()
	if next == _focus:
		return
	_focus = next
	if _focus != null and _focus.has_method("interact_prompt"):
		Game.set_interact_prompt(str(_focus.call("interact_prompt")))
	else:
		Game.set_interact_prompt("")


func _nearest_interactable() -> Node:
	if _probe == null:
		return null
	var best: Node = null
	var best_d := INF
	for area: Area3D in _probe.get_overlapping_areas():
		var host: Node = area.get_parent()
		if host == null or not host.has_method("try_interact"):
			continue
		var d: float = global_position.distance_squared_to(host.global_position)
		if d < best_d:
			best_d = d
			best = host
	return best


func _try_interact() -> void:
	_update_focus()
	if _focus == null or not _focus.has_method("try_interact"):
		return
	_busy = true
	_focus.call("try_interact")
	_busy = false
	_update_focus()
