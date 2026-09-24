extends Camera3D

## 3/4 follow camera. `Init_Camera2`: 20° FOV, distance 620, equal Y/Z (~45°).
## 620 original units × (2 m / 40) = 31 m.
## Talk uses `CAMERA2_PROCESS_TALK` framing (closer, flatter pitch).

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
## `Camera2_MoveDistancePosAndSpeed` / center morph (~0.134 per 60 Hz frame).
@export var talk_rate := 8.0

var _target: Node3D
var _locked: bool = false
var _lock_point := Vector3.ZERO
var _talk_active: bool = false
var _talk_speaker: Node3D
var _talk_listener: Node3D
var _door_active: bool = false
var _door_look := Vector3.ZERO
var _look_current := Vector3.ZERO
var _has_look: bool = false
## Intro / cutscene owns the eye; skip `_follow` until `resume`.
var _suspended: bool = false
## Outdoor town (`AcreCamera`): look-at centre in GX, held inside the player's acre.
var _acre_active: bool = false
var _acre_center := Vector3.ZERO
## `Camera2` `direction.x` relative to the 45° base: the rail-row swing, eased.
var _acre_pitch: float = 0.0
var _acre_accum: float = 0.0
## `Camera2_main_Wade`: `{start, goal, t}` in GX while the player wades.
var _acre_wade: Dictionary = {}


func _ready() -> void:
	add_to_group("follow_camera")
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


## `CAMERA2_PROCESS_DOOR` — morph look-at to the door stand at distance 620.
func begin_door(look_at: Vector3) -> void:
	_door_active = true
	_talk_active = false
	_door_look = look_at
	if not _has_look:
		_look_current = look_at + Vector3(0.0, 0.85, 0.0)
		_has_look = true


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
		var look := _door_look + Vector3(0.0, 0.85, 0.0)
		## Same 620 eye offset as normal follow; center is the door stand.
		var destination := _door_look + offset
		_move_camera(destination, look, snap, delta, follow_rate)
		return
	if _locked:
		_acre_active = false
		var look := _lock_point + Vector3(0.0, 0.85, 0.0)
		var destination := _lock_point + offset
		_move_camera(destination, look, snap, delta, follow_rate)
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


## `Camera2_main_Normal` / `Camera2_main_Wade` outdoors, ticked at 30 Hz like the decomp.
func _follow_acre(snap: bool, delta: float) -> void:
	var look_w: Vector3 = _look_point()
	var eye_gx: Vector3 = TownSpace.world_to_gx(look_w)
	var player_gx: Vector3 = TownSpace.world_to_gx(_target.global_position)
	if snap or not _acre_active:
		_acre_active = true
		_acre_accum = 0.0
		_acre_wade = {}
		if snap or not _has_look:
			_acre_center = AcreCamera.goal(eye_gx, player_gx)
			_acre_pitch = AcreCamera.swing(eye_gx, player_gx)
		else:
			_acre_center = TownSpace.world_to_gx(_look_current)
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
		_acre_accum += delta * AcreWade.TICK_HZ
		while _acre_accum >= 1.0:
			_acre_accum -= 1.0
			_acre_tick(eye_gx, player_gx)
	var center_w: Vector3 = TownSpace.gx_to_world(_acre_center)
	global_position = center_w + _swung_offset(_acre_pitch)
	_look_current = center_w
	_has_look = true
	look_at(center_w, Vector3.UP)


func _acre_tick(eye_gx: Vector3, player_gx: Vector3) -> void:
	var pitch_goal: float = AcreCamera.swing(eye_gx, player_gx)
	if _acre_wade.is_empty():
		_acre_center = AcreCamera.ease(_acre_center, AcreCamera.goal(eye_gx, player_gx))
		_acre_pitch = AcreCamera.ease_pitch(_acre_pitch, pitch_goal)
		return
	var t: float = float(_acre_wade["t"])
	var start: Vector3 = _acre_wade["start"]
	var goal: Vector3 = _acre_wade["goal"]
	_acre_center = start.lerp(goal, AcreWade.percent(t))
	_acre_pitch = AcreCamera.morph_pitch(_acre_pitch, pitch_goal, AcreWade.TICKS - t)
	t += 1.0
	_acre_wade["t"] = t
	if t > AcreWade.TICKS:
		_acre_wade = {}


## `offset` tilted by the `Camera2_Normal_Swing` pitch.
func _swung_offset(pitch: float) -> Vector3:
	if is_zero_approx(pitch):
		return offset
	var dist: float = Vector2(offset.y, offset.z).length()
	var elevation: float = atan2(offset.y, offset.z) + pitch
	return Vector3(offset.x, dist * sin(elevation), dist * cos(elevation))


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


func _look_point() -> Vector3:
	if _target.has_method("camera_look_position"):
		return _target.call("camera_look_position") as Vector3
	return _target.global_position + Vector3(0.0, 0.85, 0.0)
