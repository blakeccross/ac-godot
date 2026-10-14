class_name HouseClock
extends Node3D

## A building's wall or floor clock (`ac_house_clock`, `HOUSE_CLOCK`): the post office's
## (`obj_clock_yub`) and the police box's (`obj_clock_koban`). The hands are the model's
## `*_short_model` / `*_long_model` joints, turned to the clock (`aHC_DrawClockAfter`:
## `RotateZ(90° − rad_hour / rad_min)`); a pendulum clip plays at half speed.

## `aHC_position_data`, GX.
const POST_OFFICE_GX := Vector3(120.0, 55.0, 135.0)
const POLICE_BOX_GX := Vector3(200.0, 0.0, 30.0)

@export var visual: StringName = &"obj_clock_yub"

var _skeleton: Skeleton3D
var _hour_bone: int = -1
var _min_bone: int = -1
var _hour_rest := Quaternion.IDENTITY
var _min_rest := Quaternion.IDENTITY
var _stamp: int = -1


func _ready() -> void:
	if get_node_or_null("GeneratedVisual") == null:
		var pivot: Node3D = GeneratedVisual.attach(self, visual)
		if pivot != null:
			VisualFit.disable_shadows(pivot)
	_skeleton = _find_skeleton(self)
	if _skeleton != null:
		for i: int in _skeleton.get_bone_count():
			var bone: String = _skeleton.get_bone_name(i)
			if bone.ends_with("_short_model"):
				_hour_bone = i
				_hour_rest = _skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
			elif bone.ends_with("_long_model"):
				_min_bone = i
				_min_rest = _skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(self)
	if anim != null and not anim.get_animation_list().is_empty():
		var clip: String = anim.get_animation_list()[0]
		anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		anim.speed_scale = 0.5
		anim.play(clip)
	_turn_hands()


func _process(_delta: float) -> void:
	var stamp: int = Clock.hour * 60 + Clock.minute
	if stamp != _stamp:
		_turn_hands()


## `Common_Get(time).rad_hour` / `rad_min`.
static func hand_angles(hour: int, minute: int) -> Vector2:
	var h: float = float(hour % 12) + float(minute) / 60.0
	return Vector2(h * TAU / 12.0, float(minute) * TAU / 60.0)


func _turn_hands() -> void:
	_stamp = Clock.hour * 60 + Clock.minute
	if _skeleton == null:
		return
	var a: Vector2 = hand_angles(Clock.hour, Clock.minute)
	if _hour_bone >= 0:
		_skeleton.set_bone_pose_rotation(_hour_bone, _hour_rest * Quaternion(Vector3.BACK, -a.x))
	if _min_bone >= 0:
		_skeleton.set_bone_pose_rotation(_min_bone, _min_rest * Quaternion(Vector3.BACK, -a.y))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var s: Skeleton3D = _find_skeleton(child)
		if s != null:
			return s
	return null
