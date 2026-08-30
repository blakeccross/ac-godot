extends Camera3D

## 3/4 follow camera. `Init_Camera2`: 20° FOV, distance 620, equal Y/Z (~45°).
## 620 original units × (2 m / 40) = 31 m.

const ORIG_DISTANCE := 620.0
const FOLLOW_DISTANCE := ORIG_DISTANCE * PlayerLocomotion.UNIT_METERS
const ISO := 0.70710678
const DEFAULT_OFFSET := Vector3(0.0, FOLLOW_DISTANCE * ISO, FOLLOW_DISTANCE * ISO)
## Extra distance so the near wall stays inside the 20° frustum. 1.2 left that
## edge under the look-at (the 45° camera sits closer to +Z than to the far wall).
const FRAME_PADDING := 1.6

@export var target_path: NodePath
@export var offset := DEFAULT_OFFSET
@export var follow_rate := 6.0

var _target: Node3D
var _locked: bool = false
var _lock_point := Vector3.ZERO


func _ready() -> void:
	fov = 20.0
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	_follow(true)


func set_target(node: Node3D) -> void:
	_locked = false
	_target = node
	_follow(true)


func lock_at(point: Vector3) -> void:
	## Small indoor fields pin the look-at to the room (`Camera2` border invert).
	_locked = true
	_target = null
	_lock_point = point
	_follow(true)


## 45° 3/4 offset that fits a square of `span` meters on the floor at this FOV.
func offset_for_ground_span(span: float) -> Vector3:
	var half_fov: float = deg_to_rad(fov * 0.5)
	var dist: float = maxf(span, 1.0) * ISO / (2.0 * tan(half_fov))
	var axis: float = dist * FRAME_PADDING * ISO
	return Vector3(0.0, axis, axis)


## Indoor houses never sit closer than Camera2 620 (31 m). Small rooms would
## otherwise zoom in until the door wall clips off the bottom of the screen.
func offset_to_frame_span(span: float) -> Vector3:
	var framed: Vector3 = offset_for_ground_span(span)
	if framed.y < DEFAULT_OFFSET.y:
		return DEFAULT_OFFSET
	return framed


func _process(delta: float) -> void:
	_follow(false, delta)


func _follow(snap: bool, delta: float = 0.0) -> void:
	if _locked:
		var destination := _lock_point + offset
		if snap:
			global_position = destination
		else:
			global_position = global_position.lerp(destination, clampf(follow_rate * delta, 0.0, 1.0))
		look_at(_lock_point + Vector3(0.0, 0.85, 0.0), Vector3.UP)
		return
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
