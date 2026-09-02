class_name IntroTrainCamera
extends RefCounted

## Intro train POV — sway, morph, and look-at (`aNGD_set_camera`).

const MORPH_TICKS := 40

var lock_camera: bool = false
var obj_look_talk: bool = false
var camera_eyes: bool = false

var _camera: Camera3D
var _eye_gx: Vector3 = IntroTrainStage.CAM_EYE_GX
var _look_gx: Vector3 = IntroTrainStage.CAM_LOOK_GX
var _camera_move: int = 0
var _camera_move_y: float = 0.0
var _camera_move_range: float = 0.3
var _camera_move_cnt: int = 0
var _camera_move_set_counter: int = 1
var _camera_tilt: float = 0.0
var _camera_tilt_goal: float = 0.0
var _camera_tilt_chase: float = IntroTrainStage.CAMERA_TILT_CHASE
var _obj_look_y_gx: float = IntroTrainStage.OBJ_LOOK_Y_NORMAL_GX
var _obj_look_y_target_gx: float = IntroTrainStage.OBJ_LOOK_Y_NORMAL_GX
var _camera_morph_from_gx: Vector3 = IntroTrainStage.CAM_LOOK_GX
var _camera_morph_to_gx: Vector3 = IntroTrainStage.CAM_LOOK_GX
var _camera_morph_tracks_rover: bool = true
var _morph_ticks_left: int = 0
var _morph_t: float = 1.0
var _morph_lock_after: bool = false
var _action: IntroTrainStage.Action = IntroTrainStage.Action.ENTER


func setup(camera: Camera3D, eye_gx: Vector3 = IntroTrainStage.CAM_EYE_GX, look_gx: Vector3 = IntroTrainStage.CAM_LOOK_GX) -> void:
	_camera = camera
	_eye_gx = eye_gx
	_look_gx = look_gx
	if _camera == null:
		return
	_camera.fov = IntroTrainStage.CAM_FOV
	_camera.near = IntroTrainStage.CAM_NEAR_METERS
	_camera.far = IntroTrainStage.CAM_FAR_GX * FieldCatalog.GX_TO_METERS
	_camera_move = 0
	_camera_tilt = 0.0
	_camera_tilt_goal = 0.0
	tick(0.0, IntroTrainStage.ROVER_START_GX, _action)


var camera_morph: int:
	get:
		if _morph_ticks_left <= 0:
			return 0
		return _morph_ticks_left
	set(value):
		if value <= 0:
			_morph_ticks_left = 0
			_morph_t = 1.0
		else:
			_morph_ticks_left = value
			_morph_t = 1.0 - float(value) / float(MORPH_TICKS)


func look_gx() -> Vector3:
	return _look_gx


func set_obj_look_y_target(y_gx: float) -> void:
	_obj_look_y_target_gx = y_gx


func set_obj_look_y(y_gx: float) -> void:
	_obj_look_y_gx = y_gx
	_obj_look_y_target_gx = y_gx


func set_phone_tilt(active: bool) -> void:
	if active:
		_camera_tilt_goal = IntroTrainStage.CAMERA_TILT_GOAL_PHONE
		_camera_tilt_chase = IntroTrainStage.CAMERA_TILT_CHASE
	else:
		_camera_tilt_goal = 0.0
		_camera_tilt_chase = IntroTrainStage.CAMERA_TILT_RESET_CHASE


func begin_morph_to_rover(from_gx: Vector3, lock_after: bool) -> void:
	_begin_morph(from_gx, true, _look_gx, lock_after)


func begin_morph_to_pov(from_gx: Vector3) -> void:
	_begin_morph(from_gx, false, _look_gx, false)


func lock_on_rover() -> void:
	lock_camera = true
	obj_look_talk = true
	_morph_ticks_left = 0
	_morph_t = 1.0


func snap() -> void:
	tick(0.0, IntroTrainStage.ROVER_START_GX, _action)


func current_look_gx(ground_gx: Vector3, action: IntroTrainStage.Action = _action) -> Vector3:
	return _resolve_look_gx(ground_gx, action)


func steady_look_gx(ground_gx: Vector3, action: IntroTrainStage.Action) -> Vector3:
	match action:
		IntroTrainStage.Action.RETURN_APPROACH, IntroTrainStage.Action.SITDOWN, IntroTrainStage.Action.SEATED, IntroTrainStage.Action.TALK, IntroTrainStage.Action.LAST_SIT:
			return Vector3(ground_gx.x, _obj_look_y_gx, ground_gx.z)
		IntroTrainStage.Action.STANDUP, IntroTrainStage.Action.MOVE_AISLE, IntroTrainStage.Action.MOVE_DOOR, IntroTrainStage.Action.MOVE_DECK, IntroTrainStage.Action.KEITAI_ON, IntroTrainStage.Action.KEITAI_TALK, IntroTrainStage.Action.KEITAI_OFF, IntroTrainStage.Action.OPEN_DOOR:
			return _look_gx
		_:
			return _look_gx


func tick(delta: float, rover_pos_gx: Vector3, action: IntroTrainStage.Action, advance_morph: bool = true) -> void:
	_action = action
	if advance_morph:
		_advance_morph()
	if _camera == null:
		return
	_apply_sway(delta)
	_camera_tilt = lerp_angle(
		_camera_tilt, _camera_tilt_goal, _camera_tilt_chase * delta * 30.0
	)
	var tilt_sin: float = sin(_camera_tilt)
	_obj_look_y_gx = lerpf(_obj_look_y_gx, _obj_look_y_target_gx, 0.5 * delta * 30.0)
	var move_x_gx: float = cos(float(_camera_move) / 65536.0 * TAU) * 0.1
	var move_y_gx: float = _camera_move_y
	var eye_gx := Vector3(
		move_x_gx + tilt_sin * 20.0 + _eye_gx.x,
		move_y_gx + tilt_sin * -5.0 + _eye_gx.y,
		_eye_gx.z
	)
	var ground_gx := Vector3(rover_pos_gx.x, 0.0, rover_pos_gx.z)
	var center_gx: Vector3 = _resolve_look_gx(ground_gx, action)
	center_gx.x += move_x_gx
	center_gx.y += move_y_gx
	_camera.global_position = IntroTrainStage.gx_to_meters(eye_gx)
	_camera.look_at(IntroTrainStage.gx_to_meters(center_gx), Vector3.UP)


func _begin_morph(from_gx: Vector3, track_rover: bool, fixed_to_gx: Vector3, lock_after: bool) -> void:
	_camera_morph_from_gx = from_gx
	_camera_morph_to_gx = fixed_to_gx
	_camera_morph_tracks_rover = track_rover
	_morph_lock_after = lock_after
	lock_camera = false
	obj_look_talk = true
	_morph_ticks_left = MORPH_TICKS
	_morph_t = 0.0


func _advance_morph() -> void:
	if _morph_ticks_left <= 0:
		return
	_morph_ticks_left -= 1
	_morph_t = 1.0 - float(_morph_ticks_left) / float(MORPH_TICKS)
	if _morph_ticks_left > 0:
		return
	if _morph_lock_after:
		lock_camera = true


func _resolve_look_gx(ground_gx: Vector3, action: IntroTrainStage.Action) -> Vector3:
	if lock_camera:
		return Vector3(ground_gx.x, _obj_look_y_gx, ground_gx.z)
	if obj_look_talk and _morph_ticks_left > 0:
		return _morph_look_gx(ground_gx, _morph_t)
	if obj_look_talk:
		return steady_look_gx(ground_gx, action)
	return _look_gx


func _morph_look_gx(ground_gx: Vector3, inter: float) -> Vector3:
	var from_gx: Vector3 = _camera_morph_from_gx
	var to_gx: Vector3 = (
		Vector3(ground_gx.x, _obj_look_y_gx, ground_gx.z)
		if _camera_morph_tracks_rover
		else _camera_morph_to_gx
	)
	var eased: float = IntroTrainStage._hermit_morph(inter)
	return Vector3(
		(to_gx.x - from_gx.x) * eased + from_gx.x,
		(to_gx.y - from_gx.y) * eased + from_gx.y,
		(to_gx.z - from_gx.z) * eased + from_gx.z
	)


func _apply_sway(delta: float) -> void:
	_camera_move += int(IntroTrainStage.CAMERA_SWAY_STEP * delta * 30.0)
	var move_x_gx: float = cos(float(_camera_move) / 65536.0 * TAU) * 0.1
	var angle_y: int = _camera_move + IntroTrainStage.CAMERA_SWAY_STEP
	var move_y_gx: float = sin(float(angle_y) / 65536.0 * TAU) * _camera_move_range
	if _camera_move_y <= 0.0 and move_y_gx >= 0.0:
		_camera_move_cnt -= 1
		if _camera_move_cnt < 0:
			_camera_move_set_counter -= 1
			if _camera_move_set_counter < 0:
				_camera_move_set_counter = 1
			_camera_move_cnt = 3 if _camera_move_set_counter == 1 else 0
			_camera_move_range = 0.3
		else:
			_camera_move_range *= 0.35
	_camera_move_y = move_y_gx
