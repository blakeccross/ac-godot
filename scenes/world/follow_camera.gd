extends Camera3D

## 3/4 follow camera. Init_Camera2 uses equal Y/Z eye offset (~45°) and 20° FOV.

@export var target_path: NodePath
@export var offset := Vector3(0.0, 12.0, 12.0)

var _target: Node3D


func _ready() -> void:
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
	var destination := _target.global_position + offset
	if snap:
		global_position = destination
	else:
		global_position = global_position.lerp(destination, clampf(12.0 * delta, 0.0, 1.0))
	look_at(_target.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
