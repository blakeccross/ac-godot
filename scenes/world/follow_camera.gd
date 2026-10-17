class_name FollowCamera
extends Camera3D

## 3/4 follow camera. `Init_Camera2`: 20° FOV, distance 620, equal Y/Z (~45°).
## 620 original units × (2 m / 40) = 31 m.
## Talk uses `CAMERA2_PROCESS_TALK` framing (closer, flatter pitch).

const GROUP := &"follow_camera"

const ORIG_DISTANCE := 620.0
const FOLLOW_DISTANCE := ORIG_DISTANCE * PlayerLocomotion.UNIT_METERS
const ISO := 0.70710678
const DEFAULT_OFFSET := Vector3(0.0, FOLLOW_DISTANCE * ISO, FOLLOW_DISTANCE * ISO)
## Extra distance so the near wall stays inside the 20° frustum. 1.2 left that
## edge under the look-at (the 45° camera sits closer to +Z than to the far wall).
const FRAME_PADDING := 1.6
## Pinned rooms look this far over the floor. Not the decomp's 73 GX: its rooms sit in a
## block whose extent we do not model, and 73 here pushes the door row off the screen.
const ROOM_LOOK_HEIGHT := 0.85
## `Camera2_Door_SetEyePos`: 350 GX out at `-0x7194` (3692 short angles, about 20.3°, above
## the horizontal), toward the south.
const DOOR_DISTANCE := 350.0 * PlayerLocomotion.UNIT_METERS
const DOOR_ELEVATION := 3692.0 * MathUtil.S16
## `Camera2_setup_main_Door`: going in (`flags & 1`) morphs over 140 ticks; coming out snaps.
const DOOR_MORPH_SECONDS := 140.0 / 60.0
## `Camera2_SetPos_Item` (the player's report demos): the centre a little over and in front of
## the player, 250 GX closer than the normal 620 and 1400 short angles lower (about 37.3°),
## all on the normal camera's eases.
const ITEM_CENTER_GX := Vector3(3.167068, 28.884293 - 15.0, 17.341202)
const ITEM_DISTANCE_GX := ORIG_DISTANCE - 250.0
const ITEM_PITCH := -1400.0 * MathUtil.S16
## `Camera2_request_main_simple_fishing`: asked for again every tick of `relax_rod` /
## `vib_rod`, so each tick closes 1/40 of the way to a centre 35% of the way from the
## player's eye to the bobber (45% and 1.15× the distance when the bobber is more than 70 GX
## below). `simple_fishing_return` then closes 1/30 a tick back for the line coming in.
const FISHING_STEP := 1.0 / 40.0
const FISHING_RETURN_STEP := 1.0 / 30.0
const FISHING_RETURN_SECONDS := 30.0 / 60.0
const FISHING_DROP_GX := 70.0

@export var target_path: NodePath
@export var offset := DEFAULT_OFFSET
@export var follow_rate := 6.0
## `Camera2_MoveDistancePosAndSpeed` / center morph (~0.134 per 60 Hz frame).
@export var talk_rate := 8.0

var _target: Node3D
var _locked: bool = false
var _lock_point := Vector3.ZERO
var _talk_active: bool = false
var _talk_speaker: Node3D
var _talk_listener: Node3D
var _door_active: bool = false
## The player's eye when the door was requested, and the seconds of morph left.
var _door_center := Vector3.ZERO
var _door_left: float = 0.0
## The door eye as distance (m), elevation and yaw (radians, 0 = due south of the centre).
var _door_distance: float = DOOR_DISTANCE
var _door_elevation: float = DOOR_ELEVATION
var _door_yaw: float = 0.0
var _look_current := Vector3.ZERO
var _has_look: bool = false
## Intro / cutscene owns the eye; skip `_follow` until `resume`.
var _suspended: bool = false
## Outdoor town (`AcreCamera`): look-at centre in GX, held inside the player's acre.
var _acre_active: bool = false
var _acre_center := Vector3.ZERO
## `Camera2` `direction.x` relative to the 45° base: the rail-row swing, eased.
var _acre_pitch: float = 0.0
## `focus_distance` (GX) and `direction.y` (radians off due south). 620 and 0 in plain
## following; another camera (a talk, a door) hands them back off-target, and they ease home.
var _acre_distance: float = ORIG_DISTANCE
var _acre_yaw: float = 0.0
## `Camera2_main_Wade`: `{start, goal, t}` (GX, seconds) while the player wades.
var _acre_wade: Dictionary = {}
## The item (report) camera on `_item_target`, and the eye it eases: centre (m), distance
## (m), elevation and yaw.
var _item_active: bool = false
var _item_target: Node3D = null
var _shot_center := Vector3.ZERO
var _shot_distance: float = 0.0
var _shot_elevation: float = 0.0
var _shot_yaw: float = 0.0
## The fishing camera: on while the line is out, then easing back for `_fishing_return`.
var _fishing_active: bool = false
var _fishing_return: float = 0.0


## The one in `tree`, or null.
static func find(tree: SceneTree) -> FollowCamera:
	return tree.get_first_node_in_group(GROUP) as FollowCamera if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	## After CharacterBody3D `move_and_slide` so look-at matches this tick.
	process_physics_priority = 100
	fov = 20.0
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	_follow(true)


func set_target(node: Node3D) -> void:
	_locked = false
	_talk_active = false
	_door_active = false
	_target = node
	## Do not clear `suspend` — intro demo owns the eye until `resume`.
	if not _suspended:
		_follow(true)


func suspend() -> void:
	## Demo / intro camera drives `global_position` directly.
	_suspended = true
	_talk_active = false
	_door_active = false


func resume(snap: bool = true) -> void:
	## `snap` matches `Camera2` morph_counter 0; false eases from the current eye
	## (station DEMO → NORMAL after Porter).
	_suspended = false
	if snap:
		_follow(true)
		return
	## Keep the demo eye; seed look so `_physics_process` lerps toward the player.
	if _target != null and is_instance_valid(_target):
		_look_current = _look_point()
		_has_look = true


func lock_at(point: Vector3) -> void:
	## Small indoor fields pin the look-at to the room (`Camera2` border invert).
	_locked = true
	_talk_active = false
	_door_active = false
	_target = null
	_lock_point = point
	_follow(true)


## `Camera2_request_main_talk` — ease toward speaker + listener until `end_talk`.
func begin_talk(speaker: Node3D, listener: Node3D) -> void:
	if speaker == null or listener == null:
		return
	_talk_active = true
	_door_active = false
	_talk_speaker = speaker
	_talk_listener = listener
	## Keep the current eye / look and morph on the physics tick (no snap).
	if not _has_look:
		_look_current = global_position - basis.z * 8.0
		_has_look = true


func end_talk() -> void:
	if not _talk_active:
		return
	_talk_active = false
	_talk_speaker = null
	_talk_listener = null
	## Ease back to follow / lock; do not snap.


## `CAMERA2_PROCESS_DOOR`: frame `center` (the player's eye at the request) from 350 GX at
## 20.3°. `morph` eases there over `DOOR_MORPH_SECONDS` (going in); otherwise it snaps.
func begin_door(center: Vector3, morph: bool = true) -> void:
	_door_active = true
	_talk_active = false
	_door_center = center
	_door_left = DOOR_MORPH_SECONDS if morph and _has_look else 0.0
	if _door_left > 0.0:
		var arm: Vector3 = global_position - _look_current
		_door_distance = arm.length()
		_door_elevation = atan2(arm.y, Vector2(arm.x, arm.z).length())
		_door_yaw = atan2(arm.x, arm.z)
	else:
		_look_current = center
		_door_distance = DOOR_DISTANCE
		_door_elevation = DOOR_ELEVATION
		_door_yaw = 0.0
	_has_look = true


## `Camera2_request_main_item`: frame `target`'s report (a catch, a find, the loan paid off).
func begin_item(target: Node3D) -> void:
	if target == null:
		return
	_take_shot()
	_item_active = true
	_item_target = target


func end_item() -> void:
	_item_active = false
	_item_target = null


func is_item() -> bool:
	return _item_active


## Start a shot from wherever the camera is now.
func _take_shot() -> void:
	if not _has_look:
		_look_current = global_position - basis.z * FOLLOW_DISTANCE
		_has_look = true
	var arm: Vector3 = global_position - _look_current
	_shot_center = _look_current
	_shot_distance = arm.length()
	_shot_elevation = atan2(arm.y, Vector2(arm.x, arm.z).length())
	_shot_yaw = atan2(arm.x, arm.z)


func end_door() -> void:
	if not _door_active:
		return
	_door_active = false


func is_talking() -> bool:
	return _talk_active


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


func _physics_process(delta: float) -> void:
	## Same tick as the player. Following in `_process` while the body moves in
	## `_physics_process` makes the character stutter against a smooth world.
	if _suspended:
		return
	_follow(false, delta)


func _follow(snap: bool, delta: float = 0.0) -> void:
	if _talk_active and is_instance_valid(_talk_speaker) and is_instance_valid(_talk_listener):
		_acre_active = false
		_follow_talk(snap, delta)
		return
	if _door_active:
		_acre_active = false
		_follow_door(snap, delta)
		return
	if _item_active and is_instance_valid(_item_target):
		_acre_active = false
		_follow_item(delta)
		return
	if _target != null and _follow_fishing(delta):
		_acre_active = false
		return
	if _locked:
		_acre_active = false
		var look := _lock_point + Vector3(0.0, ROOM_LOOK_HEIGHT, 0.0)
		_move_camera(_lock_point + offset, look, snap, delta, follow_rate)
		return
	if _target == null:
		return
	if _target.has_method("wade_state") and TownSpace.is_outdoor_town():
		_follow_acre(snap, delta)
		return
	_acre_active = false
	var look_at_point := _look_point()
	var destination := _target.global_position + offset
	_move_camera(destination, look_at_point, snap, delta, follow_rate)


## `Camera2_main_Normal` / `Camera2_main_Wade` outdoors.
func _follow_acre(snap: bool, delta: float) -> void:
	var look_w: Vector3 = _look_point()
	var eye_gx: Vector3 = TownSpace.world_to_gx(look_w)
	var player_gx: Vector3 = TownSpace.world_to_gx(_target.global_position)
	if snap or not _acre_active:
		_acre_active = true
		_acre_wade = {}
		if snap or not _has_look:
			_acre_center = AcreCamera.goal(eye_gx, player_gx)
			_acre_pitch = AcreCamera.swing(eye_gx, player_gx)
			_acre_distance = ORIG_DISTANCE
			_acre_yaw = 0.0
		else:
			## Take over from wherever the last camera left the eye and ease home from
			## there (`Camera2_MoveDistancePosAndSpeed`, `MoveDirectionAngleXYZ`).
			_acre_center = TownSpace.world_to_gx(_look_current)
			var arm: Vector3 = global_position - _look_current
			_acre_distance = arm.length() / PlayerLocomotion.UNIT_METERS
			_acre_pitch = atan2(arm.y, Vector2(arm.x, arm.z).length()) - atan2(offset.y, offset.z)
			_acre_yaw = atan2(arm.x, arm.z)
	var wade: Dictionary = _target.call("wade_state") as Dictionary
	if not wade.is_empty() and _acre_wade.is_empty():
		## `Camera2_request_main_wade(end eye, 9, 36)` with the acre still being left.
		var end_eye: Vector3 = (wade["end"] as Vector3) + (look_w - _target.global_position)
		_acre_wade = {
			"start": _acre_center,
			"goal": AcreCamera.wade_goal(TownSpace.world_to_gx(end_eye), player_gx),
			"t": 0.0,
		}
	if not snap:
		_acre_step(eye_gx, player_gx, delta)
	var center_w: Vector3 = TownSpace.gx_to_world(_acre_center)
	global_position = center_w + _arm(_acre_distance * PlayerLocomotion.UNIT_METERS, atan2(offset.y, offset.z) + _acre_pitch, _acre_yaw)
	_look_current = center_w
	_has_look = true
	look_at(center_w, Vector3.UP)


func _acre_step(eye_gx: Vector3, player_gx: Vector3, delta: float) -> void:
	var pitch_goal: float = AcreCamera.swing(eye_gx, player_gx)
	_acre_distance = AcreCamera.follow_distance(_acre_distance, ORIG_DISTANCE, delta)
	_acre_yaw = AcreCamera.follow_pitch(_acre_yaw, 0.0, delta)
	if _acre_wade.is_empty():
		_acre_center = AcreCamera.follow(_acre_center, AcreCamera.goal(eye_gx, player_gx), delta)
		_acre_pitch = AcreCamera.follow_pitch(_acre_pitch, pitch_goal, delta)
		return
	var t: float = float(_acre_wade["t"])
	var start: Vector3 = _acre_wade["start"]
	var goal: Vector3 = _acre_wade["goal"]
	_acre_pitch = AcreCamera.morph_pitch(_acre_pitch, pitch_goal, AcreWade.DURATION - t, delta)
	t += delta
	_acre_center = start.lerp(goal, AcreWade.progress(t))
	_acre_wade["t"] = t
	if t >= AcreWade.DURATION:
		_acre_wade = {}


## `Camera2_SetPos_Item`: centre, distance and angles each on the normal camera's ease.
func _follow_item(delta: float) -> void:
	var u: float = PlayerLocomotion.UNIT_METERS
	var goal: Vector3 = _item_target.global_position + ITEM_CENTER_GX * u
	_shot_center = AcreCamera.follow(_shot_center / u, goal / u, delta) * u
	_shot_distance = AcreCamera.follow_distance(_shot_distance / u, ITEM_DISTANCE_GX, delta) * u
	_shot_elevation = AcreCamera.follow_pitch(_shot_elevation, atan2(offset.y, offset.z) + ITEM_PITCH, delta)
	_shot_yaw = AcreCamera.follow_pitch(_shot_yaw, 0.0, delta)
	_place_shot()


## The fishing camera while `Fishing` holds the target (and briefly after). False when it is
## not in play.
func _follow_fishing(delta: float) -> bool:
	var fishing: bool = Fishing.faces_bobber(_target)
	if fishing and not _fishing_active:
		_take_shot()
		_fishing_active = true
	elif not fishing and _fishing_active:
		_fishing_active = false
		_fishing_return = FISHING_RETURN_SECONDS
	elif not fishing and _fishing_return <= 0.0:
		return false
	var step: float = FISHING_STEP
	var center: Vector3
	var distance: float = FOLLOW_DISTANCE
	if fishing:
		var eye: Vector3 = _look_point()
		var bobber: Vector3 = Fishing.anchor()
		var share: float = 0.35
		if (eye.y - bobber.y) / PlayerLocomotion.UNIT_METERS > FISHING_DROP_GX:
			share = 0.45
			distance *= 1.15
		center = eye.lerp(bobber, share)
	else:
		step = FISHING_RETURN_STEP
		_fishing_return -= delta
		center = _normal_center()
	var f: float = 1.0 - pow(1.0 - step, delta * 60.0)
	_shot_center = _shot_center.lerp(center, f)
	_shot_distance = lerpf(_shot_distance, distance, f)
	_shot_elevation = lerp_angle(_shot_elevation, atan2(offset.y, offset.z), f)
	_shot_yaw = lerp_angle(_shot_yaw, 0.0, f)
	_place_shot()
	return true


## Where the normal camera would centre now (`Camera2_main_Normal_SetEndCenterPos_fromPlayer`).
func _normal_center() -> Vector3:
	if _locked:
		return _lock_point + Vector3(0.0, ROOM_LOOK_HEIGHT, 0.0)
	var look_w: Vector3 = _look_point()
	if TownSpace.is_outdoor_town():
		return TownSpace.gx_to_world(AcreCamera.goal(TownSpace.world_to_gx(look_w), TownSpace.world_to_gx(_target.global_position)))
	return look_w


func _place_shot() -> void:
	_look_current = _shot_center
	_has_look = true
	global_position = _shot_center + _arm(_shot_distance, _shot_elevation, _shot_yaw)
	look_at(_shot_center, Vector3.UP)


## `Camera2_PolaPosCalc`: the eye `distance` from the centre at `elevation` above the
## horizontal, `yaw` round from due south.
static func _arm(distance: float, elevation: float, yaw: float) -> Vector3:
	var flat: float = distance * cos(elevation)
	return Vector3(flat * sin(yaw), distance * sin(elevation), flat * cos(yaw))


## `Camera2_SetPos_Door`: `inter_float` closes `delta / time_left` of the centre and distance
## gap, `subRotInterpolation(1.5 / step)` half again as much of the angles, so everything
## lands as the morph runs out.
func _follow_door(snap: bool, delta: float) -> void:
	if snap or _door_left <= delta:
		_door_left = 0.0
		_look_current = _door_center
		_door_distance = DOOR_DISTANCE
		_door_elevation = DOOR_ELEVATION
		_door_yaw = 0.0
	else:
		var f: float = delta / _door_left
		var turn: float = minf(1.5 * f, 1.0)
		_look_current = _look_current.lerp(_door_center, f)
		_door_distance = lerpf(_door_distance, DOOR_DISTANCE, f)
		_door_elevation = lerp_angle(_door_elevation, DOOR_ELEVATION, turn)
		_door_yaw = lerp_angle(_door_yaw, 0.0, turn)
		_door_left -= delta
	_has_look = true
	global_position = _look_current + _arm(_door_distance, _door_elevation, _door_yaw)
	look_at(_look_current, Vector3.UP)


func _follow_talk(snap: bool, delta: float) -> void:
	var framed: Dictionary = TalkCamera.frame(_talk_speaker, _talk_listener)
	_move_camera(framed["eye"] as Vector3, framed["center"] as Vector3, snap, delta, talk_rate)


func _move_camera(eye: Vector3, look: Vector3, snap: bool, delta: float, rate: float) -> void:
	if snap or delta <= 0.0:
		global_position = eye
		_look_current = look
		_has_look = true
	else:
		var t: float = clampf(rate * delta, 0.0, 1.0)
		global_position = global_position.lerp(eye, t)
		if not _has_look:
			_look_current = look
			_has_look = true
		else:
			_look_current = _look_current.lerp(look, t)
	look_at(_look_current, Vector3.UP)


## `Camera2_getCenterPos_p` — the look-at the eye is easing toward (acre clamp, talk,
## door, lag). Weather spawn boxes use this, not the player's marker.
func look_center() -> Vector3:
	if _has_look:
		return _look_current
	if _target != null and is_instance_valid(_target):
		return _look_point()
	return global_position - global_transform.basis.z * 8.0


func _look_point() -> Vector3:
	if _target.has_method("camera_look_position"):
		return _target.call("camera_look_position") as Vector3
	return _target.global_position + Vector3(0.0, Player.LOOK_HEIGHT, 0.0)
