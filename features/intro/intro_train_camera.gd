class_name IntroTrainCamera
extends RefCounted

## Intro train POV — sway, morph, and look-at (`aNGD_set_camera`).
## `step_logic` advances the look height and the morph by `delta`; `tick` sways and places the
## camera.

## `camera_morph_counter`: 40 ticks from the aisle view onto Rover.
const MORPH_TIME := 40.0 / DecompTime.TICK_HZ
## `camera_move += 0xE20` a tick: the sway's phase in radians a second.
const SWAY_RATE := IntroTrainStage.CAMERA_SWAY_STEP * MathUtil.S16 * DecompTime.TICK_HZ
## `chase_f(&eye_y, max, spd · 0.5)` and `obj_dist_ground` at 0.5 a tick, in GX a second.
const LOOK_Y_RATE_PER_SPEED := 0.5 * DecompTime.TICK_HZ
const GROUND_RATE := 0.5 * DecompTime.TICK_HZ
## `mov_def_cnt[] = { 3, 0 }` indexed by `camera_move_set_counter`.
const _MOV_DEF_CNT: Array[int] = [3, 0]

var lock_camera: bool = false
## `obj_look_type == aNGD_OBJ_LOOK_TYPE_TALK` (first talk → standup, last talk → end).
var look_talk: bool = false
var camera_eyes: bool = false

var _camera: Camera3D
var _eye_gx: Vector3 = IntroTrainStage.CAM_EYE_GX
var _look_gx: Vector3 = IntroTrainStage.CAM_LOOK_GX
## The sway's phase (`camera_move`), radians.
var _camera_move: float = 0.0
var _camera_move_y: float = 0.0
var _camera_move_range: float = 0.0
var _camera_move_cnt: int = 0
var _camera_move_set_counter: int = 1
var _camera_tilt: float = 0.0
var _camera_tilt_goal: float = 0.0
var _camera_tilt_chase: float = IntroTrainStage.CAMERA_TILT_CHASE
## `npc_class.eye_y` — ct sets 30; chases `obj_look_y_max[type]`.
var eye_y_gx: float = IntroTrainStage.OBJ_LOOK_Y_NORMAL_GX
## `guide->obj_dist_ground`, floor-relative (decomp floor is y 40 GX; ours is 0).
var obj_dist_ground_gx: float = 0.0
## Seconds left of `camera_morph_counter`; only counts while Rover's speak demo is active.
var morph_time_left: float = MORPH_TIME
var morphing: bool = false
var _shadow_gx: Vector3 = IntroTrainStage.ROVER_START_GX


func setup(camera: Camera3D, eye_gx: Vector3 = IntroTrainStage.CAM_EYE_GX, look_gx: Vector3 = IntroTrainStage.CAM_LOOK_GX) -> void:
	_camera = camera
	_eye_gx = eye_gx
	_look_gx = look_gx
	if _camera == null:
		return
	_camera.fov = IntroTrainStage.CAM_FOV
	_camera.near = IntroTrainStage.CAM_NEAR_METERS
	_camera.far = IntroTrainStage.CAM_FAR_GX * FieldCatalog.GX_TO_METERS
	_camera_move = 0.0
	_camera_tilt = 0.0
	_camera_tilt_goal = 0.0
	tick(0.0, IntroTrainStage.ROVER_START_GX)


func look_gx() -> Vector3:
	return _look_gx


func set_phone_tilt(active: bool) -> void:
	if active:
		_camera_tilt_goal = IntroTrainStage.CAMERA_TILT_GOAL_PHONE
		_camera_tilt_chase = IntroTrainStage.CAMERA_TILT_CHASE
	else:
		_camera_tilt_goal = 0.0
		_camera_tilt_chase = IntroTrainStage.CAMERA_TILT_RESET_CHASE


## `mDemo_Check(SPEAK)` became true: start the 40-frame default→Rover morph (once).
func begin_speak_morph() -> void:
	if lock_camera or morphing:
		return
	morphing = true
	morph_time_left = MORPH_TIME


## Park locked on Rover (seated preview helpers).
func lock_on_rover(shadow_gx: Vector3, talk: bool) -> void:
	lock_camera = true
	morphing = false
	look_talk = talk
	eye_y_gx = _look_y_max(talk)
	obj_dist_ground_gx = shadow_gx.y if talk else 0.0
	_shadow_gx = shadow_gx


## `delta` seconds of `aNGD_set_camera` state (`chase_f` + morph counter).
func step_logic(delta: float, shadow_gx: Vector3) -> void:
	_shadow_gx = shadow_gx
	## `chase_f(&eye_y, obj_look_y_max[type], obj_look_y_spd[type] * 0.5)`.
	eye_y_gx = move_toward(eye_y_gx, _look_y_max(look_talk), _look_y_speed(look_talk) * LOOK_Y_RATE_PER_SPEED * delta)
	## TALK uses the shadow (root-motion) height; NORMAL uses the BG floor.
	var ground_y: float = shadow_gx.y if look_talk else 0.0
	obj_dist_ground_gx = move_toward(obj_dist_ground_gx, ground_y, GROUND_RATE * delta)
	if morphing and not lock_camera:
		morph_time_left -= delta
		if morph_time_left <= 0.0:
			morph_time_left = 0.0
			morphing = false
			lock_camera = true


func current_look_gx() -> Vector3:
	var ground := Vector3(_shadow_gx.x, obj_dist_ground_gx, _shadow_gx.z)
	if lock_camera:
		return Vector3(ground.x, ground.y + eye_y_gx, ground.z)
	if morphing:
		## `r = (40 − counter) / 40`, `cKF_HermitCalc(r, 1, 0, 1, 3.2, 0)`.
		var r: float = 1.0 - morph_time_left / MORPH_TIME
		var inter: float = hermit_morph(r)
		var to := Vector3(ground.x, ground.y + eye_y_gx, ground.z)
		return (to - _look_gx) * inter + _look_gx
	return _look_gx


func tick(delta: float, shadow_gx: Vector3) -> void:
	_shadow_gx = shadow_gx
	if _camera == null:
		return
	_apply_sway(delta)
	_camera_tilt = rotate_toward(_camera_tilt, _camera_tilt_goal, _camera_tilt_chase * delta * DecompTime.FRAME_HZ)
	var tilt_sin: float = sin(_camera_tilt)
	var move_x_gx: float = cos(_camera_move) * 0.1
	var move_y_gx: float = _camera_move_y
	var eye_gx := Vector3(
		move_x_gx + tilt_sin * 20.0 + _eye_gx.x,
		move_y_gx + tilt_sin * -5.0 + _eye_gx.y,
		_eye_gx.z
	)
	var center_gx: Vector3 = current_look_gx()
	center_gx.x += move_x_gx
	center_gx.y += move_y_gx
	_camera.global_position = IntroTrainStage.gx_to_meters(eye_gx)
	_camera.look_at(IntroTrainStage.gx_to_meters(center_gx), Vector3.UP)


## `cKF_HermitCalc(t, 1, 0, 1, 3.2, 0)` — fast-out ease used by the talk morph.
static func hermit_morph(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	var x2: float = x * x
	var x3: float = x2 * x
	var pos: float = -2.0 * x3 + 3.0 * x2
	var h10: float = x + x3 - 2.0 * x2
	return pos + 3.2 * h10


## `obj_look_y_max[] = { 30, 20 }` (NORMAL, TALK).
static func _look_y_max(talk: bool) -> float:
	return IntroTrainStage.OBJ_LOOK_Y_TALK_GX if talk else IntroTrainStage.OBJ_LOOK_Y_NORMAL_GX


## `obj_look_y_spd[] = { 0.5, 2.5 }` (NORMAL, TALK).
static func _look_y_speed(talk: bool) -> float:
	return 2.5 if talk else 0.5


## `aNGD_set_camera`'s bob: a sine on `camera_move` whose height drops to 0.35× at each
## upward zero crossing, three times, before a fresh 0.3 swing (`mov_def_cnt`).
func _apply_sway(delta: float) -> void:
	if delta <= 0.0:
		return
	_camera_move = fmod(_camera_move + SWAY_RATE * delta, TAU)
	var move_y_gx: float = sin(_camera_move) * _camera_move_range
	if _camera_move_y <= 0.0 and move_y_gx >= 0.0:
		var cnt: int = _camera_move_cnt - 1
		if cnt < 0:
			var set_cnt: int = _camera_move_set_counter - 1
			if set_cnt < 0:
				set_cnt = _MOV_DEF_CNT.size() - 1
			_camera_move_set_counter = set_cnt
			cnt = _MOV_DEF_CNT[set_cnt]
			_camera_move_range = 0.3
		else:
			_camera_move_range *= 0.35
		_camera_move_cnt = cnt
	_camera_move_y = move_y_gx
