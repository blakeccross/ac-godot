extends Camera3D

## 3/4 follow camera. `Init_Camera2`: 20° FOV, distance 620, equal Y/Z (~45°).
## 620 original units × (2 m / 40) = 31 m.

const ORIG_DISTANCE := 620.0
const FOLLOW_DISTANCE := ORIG_DISTANCE * PlayerLocomotion.UNIT_METERS
const DEFAULT_OFFSET := Vector3(0.0, FOLLOW_DISTANCE * 0.70710678, FOLLOW_DISTANCE * 0.70710678)

@export var target_path: NodePath
@export var offset := DEFAULT_OFFSET
@export var follow_rate := 6.0

var _target: Node3D


func _ready() -> void:
	fov = 20.0
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	_follow(true)


func set_target(node: Node3D) -> void:
	_target = node
	_follow(true)


func _process(delta: float) -> void:
	_follow(false, delta)


func _follow(snap: bool, delta: float = 0.0) -> void:
	if _target == null:
		return
	var look_at_point := _look_point()
	var destination := _target.global_position + offset
	if snap:
		global_position = destination
	else:
		global_position = global_position.lerp(destination, clampf(follow_rate * delta, 0.0, 1.0))
	look_at(look_at_point, Vector3.UP)


func _look_point() -> Vector3:
	if _target.has_method("camera_look_position"):
		return _target.call("camera_look_position") as Vector3
	return _target.global_position + Vector3(0.0, 0.85, 0.0)
