class_name IntroTrainStage
extends RefCounted

## 3D train demo stage for Rover (`ac_npc_guide` + `rom_train_in` / door / window).
## Positions are decomp GX; converted with `FieldCatalog.GX_TO_METERS`.

signal ready_for_talk
signal assets_missing(missing: PackedStringArray)
signal stage_changed(action: StringName)

enum Action {
	ENTER,
	APPROACH,
	TALK,
	MOVE_TO_SEAT,
	SITDOWN,
	SEATED,
	STANDUP,
	MOVE_AISLE,
	MOVE_DOOR,
	MOVE_DECK,
	KEITAI_ON,
	KEITAI_TALK,
	KEITAI_OFF,
	OPEN_DOOR,
	RETURN_APPROACH,
	LAST_SIT,
	DONE,
}

const ANIM_OPEN_D1 := "npc_1_open_d1"
const ANIM_WALK := "npc_1_walk1"
const ANIM_WAIT := "npc_1_wait1"
const ANIM_SITDOWN := "npc_1_sitdown_d1"
const ANIM_SIT_WAIT := "npc_1_sitdown_wait_d1"
const ANIM_STANDUP := "npc_1_standup_d1"
const ANIM_TO_DECK := "npc_1_to_deck_d1"
const ANIM_KEITAI_ON := "npc_1_keitai_on1"
const ANIM_KEITAI_TALK := "npc_1_keitai_talk1"
const ANIM_KEITAI_TALK2 := "npc_1_keitai_talk2"
const ANIM_KEITAI_OFF := "npc_1_keitai_off1"
const ANIM_OPEN_D2 := "npc_1_open_d2"

## `aNGD` GX landmarks. Y is floor-relative: the decomp car floor is y 40 GX, ours is 0.
const DECOMP_FLOOR_Y_GX := 40.0
const ROVER_AISLE_X_GX := 140.0
## `aNGD_actor_ct` z=130 — `open_d1` root motion on `joint_0` carries the mesh from the
## vestibule deck (−82 GX) forward to here; the actor stays at this Z throughout ENTER.
const ROVER_START_GX := Vector3(140.0, 0.0, 130.0)
const ROVER_TALK_GX := Vector3(140.0, 0.0, 290.0)
const ROVER_SIT_GX := Vector3(100.0, 0.0, 280.0)
## `aNGD_move_ready` snap once `standup_d1` ends (its root ends +20 GX in z).
const ROVER_STAND_GX := Vector3(100.0, 0.0, 300.0)
const ROVER_AISLE_GX := Vector3(140.0, 0.0, 290.0)
const ROVER_DOOR_GX := Vector3(140.0, 0.0, 130.0)
## `aNGD_move_to_deck_init` parks the actor at (140, 130); `return_approach` walks from there.
const ROVER_RETURN_START_GX := Vector3(140.0, 0.0, 130.0)
## Vestibule door actor origin (`ac_train_door`). Panel sits ~7.5 GX into the car from here.
const DOOR_GATE_GX := Vector3(140.0, 0.0, 120.0)
## Closed panel sits slightly deck-side of the car-shell jamb sample (GC frame).
const DOOR_PANEL_Z_BIAS_GX := -20.0
## Seated player (the intro POV). Actors that "search" the player turn to this point.
const PLAYER_GX := Vector3(120.0, 0.0, 340.0)
## `aNGD_set_camera`: eye (100, 80, 400), default look (90, 80, 280) — both 40 GX above
## the decomp floor.
const CAM_EYE_GX := Vector3(100.0, 80.0 - DECOMP_FLOOR_Y_GX, 400.0)
const CAM_LOOK_GX := Vector3(90.0, 80.0 - DECOMP_FLOOR_Y_GX, 280.0)
const CAM_FOV := 40.0
const CAM_NEAR_GX := 60.0
const CAM_FAR_GX := 800.0
## Decomp passes near=60 in GX world units. Converted literally (×0.05 → 3 m) the clip
## plane eats the foreground seat; keep ~2 GX for Godot.
const CAM_NEAR_METERS := 2.0 * FieldCatalog.GX_TO_METERS
## `obj_look_y_max[] = { 30, 20 }` — NORMAL looks 30 above the floor, TALK 20 above the
## shadow (root-motion) height.
const OBJ_LOOK_Y_NORMAL_GX := 30.0
const OBJ_LOOK_Y_TALK_GX := 20.0
const CAMERA_SWAY_STEP := 0xE20
## `aNGD_move_to_door`: tilt eye toward vestibule when Rover's shadow z < 140.
const CAMERA_TILT_GOAL_PHONE := PI * 0.5
const CAMERA_TILT_CHASE := deg_to_rad(2.8125) ## DEG2SHORT_ANGLE2(2.8125°)
## `aNGD_open_door` frame 22: `camera_tilt_add = 0x600` → 8.4375°.
const CAMERA_TILT_RESET_CHASE := deg_to_rad(8.4375)
## Vestibule proximity that starts / clears phone tilt (`shadow_pos.z < 140`).
const CAMERA_TILT_Z_GX := 140.0
## `aNGD_set_walk_spd` / `_spd2`: max speed (GX per 1/30 s), accel, decel.
const WALK_SPEED_GX := 1.0
const WALK_ACCEL_GX := 0.1
const WALK_DECEL_GX := 0.2
const WALK_SPEED2_GX := 1.5
const WALK_ACCEL2_GX := 0.15
const WALK_DECEL2_GX := 0.3
const DOOR_OPEN_FRAME := 20.0
const DOOR_DECK_OPEN_FRAME := 9.0
const DOOR_OPEN_D2_FRAME := 22.0
const KEITAI_ON_ANIM_SPEED := 0.5
## cKF `morph_counter = -5` steps +0.5 per 60 Hz frame → 10 frames of blend.
const ANIM_MORPH_BLEND := 10.0 / DecompTime.TICK_HZ
const OPEN_D2_YAW := PI
const OPEN_D2_YAW_CHASE := deg_to_rad(0.703125)
## `chase_angle` steps (per 1/30 s — `chase_angle` is frame-scaled, halved per 60 Hz tick).
const TALK_TURN_STEP := 0x400 * MLib.S16 ## `aNGD_talk_start_wait`
const BODY_TURN_STEP := deg_to_rad(11.25) ## `aNGD_calc_body_angl`
## `aNPC_set_body_angle`: pitch goal `speed * 3640 / 3`, `chase_angle(…, 224)`.
const BODY_LEAN_PER_SPEED := 3640.0 / 3.0 * MLib.S16
const BODY_LEAN_STEP := 224.0 * MLib.S16

var action: Action = Action.ENTER

var _rover: Node3D
var _rover_anim: AnimationPlayer
var _door: Node3D
var _keitai: Node3D
var _cam: IntroTrainCamera
var _stage_sync: Node
var _pos_gx: Vector3 = ROVER_START_GX
var _yaw: float = 0.0
## `actor.speed` (GX per 1/30 s) and `movement.speed` max / accel / decel.
var _speed_gx: float = 0.0
var _max_speed_gx: float = 0.0
var _accel_gx: float = 0.0
var _decel_gx: float = 0.0
## `shape_info.rotation.x` forward lean (`aNPC_set_body_angle`).
var _lean: float = 0.0
var _logic_steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
var _talk_emitted: bool = false
var _clip: String = ""
var _pending_clip: String = ""
var _pending_suffix: String = ""
var _pending_next: Action = Action.DONE
var _pending_ready: bool = false
## Manpu attack → hold (`*1`/`*_d1` then `*2`/`*_d2`), polled in `tick`.
var _manpu_hold_clip: String = ""
var _rover_look: RefCounted
var _phone_dialogue_done: bool = false
var _phone_tilt_reset_armed: bool = false
var _phone_trip_started: bool = false
var _pending_return_sit: bool = false
## `aNGD_keitai_talk`: `keitai_talk1` plays once, then `keitai_talk2` loops.
var _keitai_talk_looping: bool = false


var lock_camera: bool:
	get:
		return _cam.lock_camera if _cam != null else false
	set(value):
		if _cam != null:
			_cam.lock_camera = value


## `obj_look_type == aNGD_OBJ_LOOK_TYPE_TALK`.
var look_talk: bool:
	get:
		return _cam.look_talk if _cam != null else false
	set(value):
		if _cam != null:
			_cam.look_talk = value


var camera_eyes: bool:
	get:
		return _cam.camera_eyes if _cam != null else false
	set(value):
		if _cam != null:
			_cam.camera_eyes = value


static func gx_to_meters(gx: Vector3) -> Vector3:
	return gx * FieldCatalog.GX_TO_METERS


static func required_asset_paths() -> PackedStringArray:
	return PackedStringArray(
		[
			"res://assets/generated/environment/interiors/rom_train_in.glb",
			"res://assets/generated/environment/interiors/rom_train_out.glb",
			"res://assets/generated/environment/obj_romtrain_door.glb",
			"res://assets/generated/characters/villagers/xct_1.glb",
			"res://assets/generated/characters/villagers/kab_1.glb",
			"res://assets/generated/items/tol_keitai_1.glb",
		]
	)


static func missing_assets() -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in required_asset_paths():
		if not ResourceLoader.exists(path):
			out.append(path)
	return out


func bind(
	rover: Node3D,
	rover_anim: AnimationPlayer,
	door: Node3D,
	keitai: Node3D,
	camera_host: Variant,
	rover_look: RefCounted = null,
	stage_sync: Node = null
) -> void:
	_rover = rover
	_rover_anim = rover_anim
	if _rover_anim == null and rover != null and rover.has_method("body_animation_player"):
		_rover_anim = rover.body_animation_player()
	_door = door
	_keitai = keitai
	_rover_look = rover_look
	_stage_sync = stage_sync
	_cam = IntroTrainCamera.new()
	if camera_host != null and camera_host.has_method("eye_gx"):
		_cam.setup(camera_host.camera, camera_host.eye_gx(), camera_host.look_gx())
	elif camera_host is Camera3D:
		_cam.setup(camera_host as Camera3D)
	_pos_gx = ROVER_START_GX
	_yaw = 0.0
	_lean = 0.0
	_set_stop_spd()
	_apply_rover_pose()
	_reset_keitai()
	_phone_dialogue_done = false
	_phone_tilt_reset_armed = false
	_phone_trip_started = false
	_pending_return_sit = false
	_set_action(Action.ENTER)
	_refresh_camera(0.0)


## Dialogue cue: snap to the seat and play `npc_1_sitdown_d1` (decomp `aNGD_ACTION_SITDOWN`).
func cue_sit() -> void:
	if action == Action.SEATED or action == Action.SITDOWN:
		return
	_set_action(Action.SITDOWN)


## Dialogue cue: phone call to Nook — standup, aisle, deck, keitai.
func cue_phone() -> void:
	_phone_trip_started = true
	_set_action(Action.STANDUP)


## Dialogue cue: after phone lines finish — begin keitai-off / return (decomp `mDemo` speak end).
func end_phone_talk() -> void:
	_phone_dialogue_done = true
	match action:
		Action.KEITAI_TALK:
			_set_action(Action.KEITAI_OFF)
		Action.KEITAI_ON, Action.MOVE_DECK, Action.MOVE_DOOR, Action.MOVE_AISLE, Action.STANDUP:
			pass
		Action.KEITAI_OFF, Action.OPEN_DOOR, Action.RETURN_APPROACH, Action.TALK, Action.LAST_SIT, Action.SEATED:
			pass
		_:
			pass


## Dialogue `manpu` / `DEMONPC0` reaction (`aNPC_check_manpu_demoCode`).
func cue_manpu(name: String) -> String:
	var key := _manpu_key(name)
	var clip := NpcManpu.clip_for(key)
	if clip.is_empty():
		return ""
	_manpu_hold_clip = ""
	var loop: bool = NpcManpu.loops(key)
	if loop:
		_play_rover(clip, true)
		return clip
	var hold := _manpu_hold_for(clip)
	if not hold.is_empty() and not resolve_rover_clip(_rover_anim, hold).is_empty():
		_manpu_hold_clip = hold
	_play_rover(clip, false)
	return clip


func _manpu_hold_for(attack_clip: String) -> String:
	## `eff_idx` → `eff_idx2`: smile1→smile2, smile_d1→smile_d2.
	if attack_clip.ends_with("_d1"):
		return attack_clip.trim_suffix("1") + "2"
	if attack_clip.ends_with("1"):
		return attack_clip.trim_suffix("1") + "2"
	return ""


func _manpu_key(name: String) -> String:
	var key := name.strip_edges().to_lower()
	if key.is_empty():
		return String(NpcManpu.RESET_SIT if _is_seated_action() else NpcManpu.RESET)
	if NpcManpu.is_reset(key) or key.begins_with("npc_1_") or key.ends_with("_d1"):
		return key
	if not _is_seated_action():
		return key
	var seated := "npc_1_%s_d1" % key.trim_prefix("npc_1_")
	if not resolve_rover_clip(_rover_anim, seated).is_empty():
		return seated
	return key


func _is_seated_action() -> bool:
	return action == Action.SEATED or action == Action.SITDOWN or action == Action.LAST_SIT


## Dialogue cue: sitdown2 after the phone return (`aNGD_ACTION_SITDOWN2`).
func cue_return_sit() -> void:
	if not _phone_trip_started:
		return
	match action:
		Action.TALK, Action.RETURN_APPROACH:
			_pending_return_sit = false
			_set_action(Action.LAST_SIT)
		Action.SITDOWN, Action.LAST_SIT, Action.SEATED:
			_pending_return_sit = false
		_:
			## Still walking back — sit once return talk starts.
			_pending_return_sit = true


## Decomp `mMsg` LockContinue / demo gating — block Continue until stage catches up.
func can_advance_dialogue(_from_node: StringName, to_node: StringName) -> bool:
	match action:
		Action.SITDOWN, Action.LAST_SIT, Action.STANDUP, Action.KEITAI_ON, Action.KEITAI_OFF, Action.OPEN_DOOR, Action.MOVE_DECK:
			return false
	match to_node:
		&"sit_ok", &"name_prompt":
			return action >= Action.SEATED
		&"phone_call", &"phone_call2":
			return action >= Action.KEITAI_TALK
		&"phone_done_stage":
			return action >= Action.KEITAI_TALK
		&"phone_done", &"phone_done_2", &"farewell":
			return action >= Action.RETURN_APPROACH
		_:
			return true


func stage_wait_met(key: String) -> bool:
	match key:
		"seated":
			return action >= Action.SEATED
		"return_seated":
			## Exact seated after the phone trip — `>= SEATED` is true during standup/walk.
			return _phone_trip_started and action == Action.SEATED
		"keitai_talk":
			return action >= Action.KEITAI_TALK
		"return_approach":
			return action >= Action.RETURN_APPROACH
		"advance_gate":
			return can_advance_dialogue(&"", _dialogue_wait_to)
		_:
			return true


var _dialogue_wait_to: StringName = &""


func set_dialogue_wait_to(node: StringName) -> void:
	_dialogue_wait_to = node


func _dialogue_wait_to_node() -> StringName:
	return _dialogue_wait_to


func _set_action(next: Action) -> void:
	_manpu_hold_clip = ""
	action = next
	stage_changed.emit(_action_name(next))
	match next:
		Action.ENTER:
			_set_stop_spd()
			camera_eyes = false
			_set_rover_eyes(false)
			_play_rover(ANIM_OPEN_D1, false)
			_play_door_sync(IntroTrainStageSync.SYNC_ENTER)
		Action.APPROACH:
			## `aNGD_set_walk_spd`; `enter` sets `camera_eyes_flag`.
			_set_walk_spd(WALK_SPEED_GX, WALK_ACCEL_GX, WALK_DECEL_GX)
			camera_eyes = true
			_set_rover_eyes(true)
			_play_rover(ANIM_WALK, true)
		Action.TALK:
			## `aNGD_talk_start_wait` / `last_talk_start_wait`: stop, request speak with
			## `obj_look_type = TALK`, then chase-turn to the player (see `_step_talk`).
			_set_stop_spd()
			look_talk = true
			_play_rover(ANIM_WAIT, true)
			if _cam != null:
				_cam.begin_speak_morph()
			if not _talk_emitted:
				_talk_emitted = true
				ready_for_talk.emit()
			if _pending_return_sit:
				_pending_return_sit = false
				_set_action(Action.LAST_SIT)
				return
		Action.MOVE_TO_SEAT:
			_set_action(Action.SITDOWN)
			return
		Action.SITDOWN:
			## `aNGD_sitdown` pins (100, 280) yaw 0; `sitdown_d1` (morph 0) carries the
			## body in from the aisle on `joint_0`.
			_pos_gx = ROVER_SIT_GX
			_set_stop_spd()
			_yaw = 0.0
			_apply_rover_pose()
			_disconnect_anim_finished()
			_play_rover(ANIM_SITDOWN, false)
			_await_then(Action.SEATED, ANIM_SITDOWN)
		Action.SEATED:
			_play_rover(ANIM_SIT_WAIT, true)
		Action.STANDUP:
			## `aNGD_standup_start_wait` → NORMAL look; the actor stays on the seat while
			## `standup_d1` (morph −5) plays. `lock_camera_flag` is never cleared.
			look_talk = false
			camera_eyes = false
			_set_rover_eyes(false)
			_play_rover(ANIM_STANDUP, false)
			_await_then(Action.MOVE_AISLE, ANIM_STANDUP)
		Action.MOVE_AISLE:
			## `aNGD_move_ready`: snap to (100, 300) on WAIT1 (morph 0), then
			## `move_to_aisle` starts WALK1 (morph −5) at `walk_spd2` from rest.
			_pos_gx = ROVER_STAND_GX
			_apply_rover_pose()
			_play_rover(ANIM_WAIT, true, 1.0, 0.0)
			_set_walk_spd(WALK_SPEED2_GX, WALK_ACCEL2_GX, WALK_DECEL2_GX)
			_play_rover(ANIM_WALK, true)
		Action.MOVE_DOOR:
			pass
		Action.MOVE_DECK:
			## `aNGD_move_to_deck_init`: stop and pin (140, 130).
			_set_stop_spd()
			_pos_gx = ROVER_DOOR_GX
			_apply_rover_pose()
			_play_rover(ANIM_TO_DECK, false)
			_play_door_sync(IntroTrainStageSync.SYNC_DECK)
			_await_then(Action.KEITAI_ON, ANIM_TO_DECK)
		Action.KEITAI_ON:
			_play_keitai_on()
			_play_rover(ANIM_KEITAI_ON, false, KEITAI_ON_ANIM_SPEED)
			_await_then(Action.KEITAI_TALK, ANIM_KEITAI_ON)
		Action.KEITAI_TALK:
			if _phone_dialogue_done:
				_set_action(Action.KEITAI_OFF)
				return
			## `keitai_talk1` is a STOP clip; `aNGD_keitai_talk` swaps to `keitai_talk2` (loop).
			_keitai_talk_looping = false
			_play_rover(ANIM_KEITAI_TALK, false)
		Action.KEITAI_OFF:
			_keitai_talk_looping = false
			_play_keitai_off()
			_play_rover(ANIM_KEITAI_OFF, false)
			_await_then(Action.OPEN_DOOR, ANIM_KEITAI_OFF)
		Action.OPEN_DOOR:
			_hide_keitai()
			_phone_tilt_reset_armed = true
			_play_rover(ANIM_OPEN_D2, false)
			_play_door_sync(IntroTrainStageSync.SYNC_OPEN_D2)
			_await_then(Action.RETURN_APPROACH, ANIM_OPEN_D2)
		Action.RETURN_APPROACH:
			## `aNGD_return_approach_init`: head look on, `walk_spd2`, WALK1 with morph 0.
			_pos_gx = ROVER_RETURN_START_GX
			_yaw = 0.0
			_apply_rover_pose()
			camera_eyes = true
			_set_rover_eyes(true)
			_set_walk_spd(WALK_SPEED2_GX, WALK_ACCEL2_GX, WALK_DECEL2_GX)
			_play_rover(ANIM_WALK, true, 1.0, 0.0)
		Action.LAST_SIT:
			## `aNGD_sitdown2` — snap to the bench and play sitdown mid-farewell.
			_set_action(Action.SITDOWN)
			return
		_:
			pass
	_refresh_camera(0.0)


func _set_walk_spd(max_speed: float, accel: float, decel: float) -> void:
	_max_speed_gx = max_speed
	_accel_gx = accel
	_decel_gx = decel


## `aNGD_set_stop_spd`: zero speed immediately.
func _set_stop_spd() -> void:
	_speed_gx = 0.0
	_max_speed_gx = 0.0
	_accel_gx = 0.0
	_decel_gx = 0.0


## One decomp frame (1/60 s): `move_before` (position) → `aNGD_*` proc → `move_after`
## (body lean) → `aNGD_set_camera`.
func _logic_step() -> void:
	_step_position()
	match action:
		Action.APPROACH:
			_step_approach()
		Action.TALK:
			_step_talk()
		Action.MOVE_AISLE:
			_step_move_aisle()
		Action.MOVE_DOOR:
			_step_move_door()
		Action.RETURN_APPROACH:
			_step_return_approach()
		Action.OPEN_DOOR:
			_step_open_door()
		_:
			pass
	_step_lean()
	_apply_rover_pose()
	if _cam != null:
		_cam.step_logic(shadow_gx())


## `aNPC_position_move`: `chase_f(speed, max, accel·0.5)` then `pos += 0.5·speed` along yaw.
func _step_position() -> void:
	var accel: float = _accel_gx if _speed_gx < _max_speed_gx else _decel_gx
	_speed_gx = move_toward(_speed_gx, _max_speed_gx, accel * 0.5)
	if _speed_gx == 0.0:
		return
	var step: float = 0.5 * _speed_gx
	_pos_gx.x += sin(_yaw) * step
	_pos_gx.z += cos(_yaw) * step


func _step_approach() -> void:
	## `aNGD_approach`: straight down the aisle (yaw 0) until z reaches 290.
	if _pos_gx.z >= ROVER_TALK_GX.z:
		_pos_gx.z = ROVER_TALK_GX.z
		_set_action(Action.TALK)


func _step_talk() -> void:
	## `chase_angle(&rotation.y, player_angle_y, 0x400)`.
	_yaw = _chase_angle(_yaw, yaw_toward_player(_pos_gx), TALK_TURN_STEP * 0.5)


func _step_move_aisle() -> void:
	_calc_body_angl(ROVER_AISLE_GX)
	if _pos_gx.x > ROVER_AISLE_GX.x:
		_set_action(Action.MOVE_DOOR)


func _step_move_door() -> void:
	_calc_body_angl(ROVER_DOOR_GX)
	if _pos_gx.z < ROVER_DOOR_GX.z:
		_set_action(Action.MOVE_DECK)
		return
	if shadow_gx().z < CAMERA_TILT_Z_GX and _cam != null:
		_cam.set_phone_tilt(true)


func _step_return_approach() -> void:
	## `aNGD_return_approach`: x = 140 and yaw 0 every frame until z passes 290.
	_pos_gx.x = ROVER_AISLE_X_GX
	_yaw = 0.0
	if _pos_gx.z > ROVER_TALK_GX.z:
		_set_action(Action.TALK)


func _step_open_door() -> void:
	## `aNGD_open_door`: chase yaw to −180°; at open_d2 frame 22 clear phone tilt.
	_yaw = _chase_angle(_yaw, OPEN_D2_YAW, OPEN_D2_YAW_CHASE * 0.5)
	if (
		_phone_tilt_reset_armed
		and _rover_anim_frame() >= DOOR_OPEN_D2_FRAME
	):
		_phone_tilt_reset_armed = false
		if shadow_gx().z < CAMERA_TILT_Z_GX and _cam != null:
			_cam.set_phone_tilt(false)


## `aNGD_calc_body_angl`: chase yaw toward a GX point at 11.25° per 1/30 s.
func _calc_body_angl(target_gx: Vector3) -> void:
	var to: Vector3 = target_gx - _pos_gx
	if absf(to.x) < 0.0001 and absf(to.z) < 0.0001:
		return
	_yaw = _chase_angle(_yaw, atan2(to.x, to.z), BODY_TURN_STEP * 0.5)


## `aNPC_set_body_angle`: forward pitch proportional to speed.
func _step_lean() -> void:
	_lean = _chase_angle(_lean, _speed_gx * BODY_LEAN_PER_SPEED, BODY_LEAN_STEP * 0.5)


static func _chase_angle(current: float, target: float, step: float) -> float:
	var diff: float = wrapf(target - current, -PI, PI)
	if absf(diff) <= step:
		return target
	return current + signf(diff) * step


## `draw.shadow_pos`: actor position + `joint_0` root-motion offset
## (`cKF_SkeletonInfo_R_AnimationMove_CulcTransToWorld`). Floor-relative Y.
func shadow_gx() -> Vector3:
	var out: Vector3 = _pos_gx
	if _rover != null and _rover.has_method("root_motion_offset_gx"):
		out += _rover.call("root_motion_offset_gx") as Vector3
	return out


func _apply_rover_pose() -> void:
	if _rover == null:
		return
	_rover.global_position = gx_to_meters(_pos_gx)
	_rover.rotation = Vector3(_lean, _yaw, 0.0)


func _play_door_sync(sync_name: StringName) -> void:
	if _door != null and _door.has_method("reset_door_pulse"):
		_door.call("reset_door_pulse")
	if _stage_sync != null and _stage_sync.has_method("play"):
		_stage_sync.call("play", sync_name)


func _set_rover_eyes(active: bool) -> void:
	if _rover_look != null and _rover_look.has_method("set_camera_eyes"):
		_rover_look.set_camera_eyes(active)


func current_look_gx() -> Vector3:
	if _cam == null:
		return CAM_LOOK_GX
	return _cam.current_look_gx()


func _rover_anim_frame() -> float:
	## cKF frame index at 30 Hz from the active Rover clip.
	if _rover_anim == null:
		return 0.0
	return _rover_anim.current_animation_position * DecompTime.FRAME_HZ


func phone_tilt_goal() -> float:
	if _cam == null:
		return 0.0
	return _cam._camera_tilt_goal


func phone_tilt() -> float:
	if _cam == null:
		return 0.0
	return _cam._camera_tilt


## Body yaw for any actor that turns to the player (`aNPC_act_search_turn` with
## `aNPC_ACT_OBJ_PLAYER`). The player is the seated POV the intro camera looks from.
static func yaw_toward_player(from_gx: Vector3) -> float:
	var to: Vector3 = PLAYER_GX - from_gx
	to.y = 0.0
	if to.length_squared() < 0.001:
		return 0.0
	return atan2(to.x, to.z)


func _play_rover(
	suffix: String, loop: bool, speed_scale: float = 1.0, blend_override: float = -1.0
) -> bool:
	if _rover != null and _rover.has_method("play_intro_clip"):
		var ok: bool = _rover.play_intro_clip(suffix, loop, speed_scale, blend_override)
		if ok and _rover.has_method("current_intro_clip"):
			_clip = _rover.current_intro_clip()
		return ok
	if _rover_anim == null:
		return false
	var clip: String = resolve_rover_clip(_rover_anim, suffix)
	if clip.is_empty():
		return false
	if _clip == clip and _rover_anim.is_playing():
		var anim_check: Animation = _rover_anim.get_animation(clip)
		if anim_check != null:
			var want_loop: int = (
				Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			)
			if anim_check.loop_mode == want_loop:
				return true
	_clip = clip
	var anim: Animation = _rover_anim.get_animation(clip)
	if anim != null:
		anim.loop_mode = (
			Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		)
	_rover_anim.speed_scale = speed_scale
	var blend: float = (
		blend_override if blend_override >= 0.0 else _rover_anim_blend(suffix)
	)
	_rover_anim.play(clip, blend)
	return true


func _reset_keitai() -> void:
	if _keitai == null:
		return
	if _keitai.has_method("hide_phone"):
		_keitai.hide_phone()
	else:
		_keitai.visible = false


func _play_keitai_on() -> void:
	if _keitai == null:
		return
	if _keitai.has_method("play_on"):
		_keitai.play_on(KEITAI_ON_ANIM_SPEED)
	else:
		_keitai.visible = true


func _play_keitai_off() -> void:
	if _keitai == null:
		return
	if _keitai.has_method("play_off"):
		_keitai.play_off()
	else:
		_keitai.visible = true


func _hide_keitai() -> void:
	_reset_keitai()


static func _rover_anim_blend(suffix: String) -> float:
	## Instant cuts for clips that must not crossfade from the prior pose.
	match suffix:
		ANIM_OPEN_D1, ANIM_SITDOWN:
			return 0.0
		_:
			return ANIM_MORPH_BLEND


static func resolve_rover_clip(anim: AnimationPlayer, suffix: String) -> String:
	if anim == null:
		return ""
	if anim.has_animation(suffix):
		return suffix
	var best: String = ""
	for anim_name: String in anim.get_animation_list():
		if not anim_name.ends_with(suffix):
			continue
		if best.is_empty() or anim_name.length() < best.length():
			best = anim_name
	return best


func _resolve_clip(suffix: String) -> String:
	return resolve_rover_clip(_rover_anim, suffix)


func _anim_playing() -> bool:
	if _rover != null and _rover.has_method("intro_clip_playing"):
		return _rover.intro_clip_playing()
	if _rover_anim == null:
		return false
	return _rover_anim.is_playing()


func _await_then(next: Action, wait_suffix: String = "") -> void:
	_pending_next = next
	_pending_suffix = wait_suffix
	_pending_clip = ""
	if wait_suffix != "" and _rover_anim != null:
		_pending_clip = resolve_rover_clip(_rover_anim, wait_suffix)
	if wait_suffix != "" and _pending_clip.is_empty():
		_pending_ready = true
		return
	if wait_suffix != "":
		_connect_anim_finished()
		return
	_pending_ready = true


func _connect_anim_finished() -> void:
	if _rover != null and _rover.has_method("connect_intro_clip_finished"):
		_disconnect_anim_finished()
		_rover.connect_intro_clip_finished(_on_anim_finished)
		return
	if _rover_anim != null:
		if _rover_anim.animation_finished.is_connected(_on_anim_finished):
			_rover_anim.animation_finished.disconnect(_on_anim_finished)
		_rover_anim.animation_finished.connect(_on_anim_finished)


func _disconnect_anim_finished() -> void:
	if _rover != null and _rover.has_method("disconnect_intro_clip_finished"):
		_rover.disconnect_intro_clip_finished(_on_anim_finished)
	if _rover_anim != null and _rover_anim.animation_finished.is_connected(_on_anim_finished):
		_rover_anim.animation_finished.disconnect(_on_anim_finished)


func _flush_pending() -> void:
	if _pending_next == Action.DONE:
		_pending_ready = false
		_pending_clip = ""
		return
	var next: Action = _pending_next
	_pending_next = Action.DONE
	_pending_ready = false
	_pending_clip = ""
	_pending_suffix = ""
	_set_action(next)


func _on_anim_finished(anim_name: StringName) -> void:
	if _pending_clip != "" and not _clip_matches_pending(anim_name):
		return
	_disconnect_anim_finished()
	_flush_pending()


func _clip_matches_pending(anim_name: StringName) -> bool:
	var finished := String(anim_name)
	if _pending_suffix != "" and (
		finished == _pending_suffix or finished.ends_with(_pending_suffix)
	):
		return true
	if _pending_clip == "":
		return true
	if finished == _pending_clip:
		return true
	return finished.ends_with(_pending_clip) or _pending_clip.ends_with(finished)


func tick(delta: float) -> void:
	if _pending_ready:
		_flush_pending()
	if _manpu_hold_clip != "" and not _anim_playing():
		var hold := _manpu_hold_clip
		_manpu_hold_clip = ""
		_play_rover(hold, true)
	if action == Action.ENTER and not _anim_playing():
		## `aNGD_enter`: `open_d1` stopped → APPROACH.
		_set_action(Action.APPROACH)
	if action == Action.KEITAI_TALK and not _keitai_talk_looping and not _anim_playing():
		_keitai_talk_looping = true
		_play_rover(ANIM_KEITAI_TALK2, true)
	_logic_steps.add(delta)
	while _logic_steps.next():
		_logic_step()
	_refresh_camera(delta)


func _refresh_camera(delta: float) -> void:
	if _cam == null:
		return
	_cam.tick(delta, shadow_gx())


func _action_name(act: Action) -> StringName:
	match act:
		Action.ENTER:
			return &"enter"
		Action.APPROACH:
			return &"approach"
		Action.TALK:
			return &"talk"
		Action.MOVE_TO_SEAT:
			return &"move_to_seat"
		Action.SITDOWN:
			return &"sitdown"
		Action.SEATED:
			return &"seated"
		Action.STANDUP:
			return &"standup"
		Action.MOVE_AISLE:
			return &"move_aisle"
		Action.MOVE_DOOR:
			return &"move_door"
		Action.MOVE_DECK:
			return &"move_deck"
		Action.KEITAI_ON:
			return &"keitai_on"
		Action.KEITAI_TALK:
			return &"keitai_talk"
		Action.KEITAI_OFF:
			return &"keitai_off"
		Action.OPEN_DOOR:
			return &"open_door"
		Action.RETURN_APPROACH:
			return &"return_approach"
		Action.LAST_SIT:
			return &"last_sit"
		_:
			return &"done"
