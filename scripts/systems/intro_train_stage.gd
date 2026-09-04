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

## `aNGD` GX landmarks.
const ROVER_AISLE_X_GX := 140.0
## Decomp enter landmark — `open_d1` root motion on `joint_0` carries the mesh from the
## vestibule deck (~48 GX) forward to here; keep the host at this Z throughout ENTER.
const ROVER_START_GX := Vector3(140.0, 0.0, 130.0)
const ROVER_TALK_GX := Vector3(140.0, 0.0, 290.0)
const ROVER_SIT_GX := Vector3(100.0, 0.0, 280.0)
const ROVER_STAND_GX := Vector3(100.0, 0.0, 300.0)
const ROVER_AISLE_GX := Vector3(140.0, 0.0, 290.0)
const ROVER_DOOR_GX := Vector3(140.0, 0.0, 130.0)
const ROVER_RETURN_START_GX := Vector3(140.0, 0.0, 140.0)
## Vestibule door actor origin (`ac_train_door`). Panel sits ~7.5 GX into the car from here.
const DOOR_GATE_GX := Vector3(140.0, 0.0, 120.0)
## Closed panel sits slightly deck-side of the car-shell jamb sample (GC frame).
const DOOR_PANEL_Z_BIAS_GX := -20.0
## Seated player (the intro POV). Actors that "search" the player turn to this point.
const PLAYER_GX := Vector3(120.0, 0.0, 340.0)
## Decomp literals are eye/look Y=80 GX (`aNGD_set_camera`). The GC intro frame reads as
## a seated POV — eye ~52 GX, look ~34 GX (down the aisle at cushion height).
const CAM_EYE_GX := Vector3(100.0, 52.0, 400.0)
const CAM_LOOK_GX := Vector3(90.0, 34.0, 280.0)
const CAM_FOV := 40.0
const CAM_NEAR_GX := 60.0
const CAM_FAR_GX := 800.0
## Decomp passes near=60 in GX world units. Converted literally (×0.05 → 3 m) the clip
## plane eats the foreground seat; keep ~1 GX for Godot.
const CAM_NEAR_METERS := 2.0 * FieldCatalog.GX_TO_METERS
const OBJ_LOOK_Y_TALK_GX := 30.0
const OBJ_LOOK_Y_NORMAL_GX := 20.0
const CAMERA_SWAY_STEP := 0xE20
## `aNGD_move_to_door`: tilt eye toward vestibule when Rover's shadow z < 140.
const CAMERA_TILT_GOAL_PHONE := PI * 0.5
const CAMERA_TILT_CHASE := deg_to_rad(2.8125) ## DEG2SHORT_ANGLE2(2.8125°)
## `aNGD_open_door` frame 22: `camera_tilt_add = 0x600` → 8.4375°.
const CAMERA_TILT_RESET_CHASE := deg_to_rad(8.4375)
## Vestibule proximity that starts / clears phone tilt (`shadow_pos.z < 140`).
const CAMERA_TILT_Z_GX := 140.0
const WALK_SPEED_GX := 1.0 ## GX per frame @ 30 Hz (`aNGD_set_walk_spd`)
const WALK_SPEED2_GX := 1.5 ## `aNGD_set_walk_spd2`
const DOOR_OPEN_FRAME := 20.0
const DOOR_DECK_OPEN_FRAME := 9.0
const DOOR_OPEN_D2_FRAME := 22.0
const KEITAI_ON_ANIM_SPEED := 0.5
## Decomp `morph_counter = -5` → ~10 frames of blend at 30 Hz when switching clips.
const ANIM_MORPH_BLEND := 10.0 / 30.0
const OPEN_D2_YAW := PI
const OPEN_D2_YAW_CHASE := deg_to_rad(0.703125)

var action: Action = Action.ENTER

var _rover: Node3D
var _rover_anim: AnimationPlayer
var _door: Node3D
var _keitai: Node3D
var _cam
var _stage_sync: Node
var _target_gx: Vector3 = ROVER_TALK_GX
var _speed_gx: float = WALK_SPEED_GX
var _pos_gx: Vector3 = ROVER_START_GX
var _yaw: float = 0.0
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
var _aisle_yaw_from: float = 0.0
var _aisle_yaw_to: float = 0.0
var _aisle_turn_t: float = 1.0
var _aisle_walk_started: bool = false


var lock_camera: bool:
	get:
		return _cam.lock_camera if _cam != null else false
	set(value):
		if _cam != null:
			_cam.lock_camera = value


var camera_morph: int:
	get:
		return _cam.camera_morph if _cam != null else 0
	set(value):
		if _cam != null:
			_cam.camera_morph = value


var obj_look_talk: bool:
	get:
		return _cam.obj_look_talk if _cam != null else false
	set(value):
		if _cam != null:
			_cam.obj_look_talk = value


var camera_eyes: bool:
	get:
		return _cam.camera_eyes if _cam != null else false
	set(value):
		if _cam != null:
			_cam.camera_eyes = value


var _obj_look_y_gx: float:
	get:
		return _cam._obj_look_y_gx if _cam != null else OBJ_LOOK_Y_NORMAL_GX
	set(value):
		if _cam != null:
			_cam._obj_look_y_gx = value


var _obj_look_y_target_gx: float:
	get:
		return _cam._obj_look_y_target_gx if _cam != null else OBJ_LOOK_Y_NORMAL_GX
	set(value):
		if _cam != null:
			_cam._obj_look_y_target_gx = value


var _camera_morph_from_gx: Vector3:
	get:
		return _cam._camera_morph_from_gx if _cam != null else CAM_LOOK_GX


var _camera_morph_to_gx: Vector3:
	get:
		return _cam._camera_morph_to_gx if _cam != null else CAM_LOOK_GX


var _camera_morph_tracks_rover: bool:
	get:
		return _cam._camera_morph_tracks_rover if _cam != null else true


const _CAMERA_SCRIPT := preload("res://scripts/systems/intro_train_camera.gd")

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
	_cam = _CAMERA_SCRIPT.new()
	if camera_host != null and camera_host.has_method("eye_gx"):
		_cam.setup(camera_host.camera, camera_host.eye_gx(), camera_host.look_gx())
	elif camera_host is Camera3D:
		_cam.setup(camera_host as Camera3D)
	_pos_gx = ROVER_START_GX
	_yaw = 0.0
	_apply_rover_pose()
	_reset_keitai()
	_phone_dialogue_done = false
	_phone_tilt_reset_armed = false
	_phone_trip_started = false
	_pending_return_sit = false
	_set_action(Action.ENTER)
	_refresh_camera(0.0)


static func _hermit_morph(t: float) -> float:
	## `cKF_HermitCalc(r, 1, 0, 1, 3.2, 0)` — smooth ease for camera morph.
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


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
	var morph_from_gx: Vector3 = _current_camera_look_gx(_pos_gx)
	action = next
	stage_changed.emit(_action_name(next))
	match next:
		Action.ENTER:
			_speed_gx = WALK_SPEED_GX
			camera_eyes = false
			_set_rover_eyes(false)
			_play_rover(ANIM_OPEN_D1, false)
			_play_door_sync(IntroTrainStageSync.SYNC_ENTER)
		Action.APPROACH:
			_speed_gx = WALK_SPEED_GX
			_target_gx = ROVER_TALK_GX
			camera_eyes = true
			_set_rover_eyes(true)
			_play_rover(ANIM_WALK, true)
		Action.TALK:
			camera_eyes = false
			_set_rover_eyes(false)
			_yaw = yaw_toward_player(_pos_gx)
			_apply_rover_pose()
			_play_rover(ANIM_WAIT, true)
			_obj_look_y_target_gx = OBJ_LOOK_Y_TALK_GX
			## First talk morphs aisle POV → Rover then locks. Return talk stays locked
			## (`lock_camera_flag` is never cleared), so skip a no-op remorph.
			if _cam != null and not lock_camera:
				_cam.begin_morph_to_rover(morph_from_gx, true)
			if not _talk_emitted:
				_talk_emitted = true
				ready_for_talk.emit()
			if _pending_return_sit:
				_pending_return_sit = false
				_set_action(Action.LAST_SIT)
				return
		Action.MOVE_TO_SEAT:
			_set_action(Action.SITDOWN)
		Action.SITDOWN:
			_pos_gx = ROVER_SIT_GX
			_speed_gx = 0.0
			_yaw = 0.0
			_apply_rover_pose()
			_disconnect_anim_finished()
			## Re-morph from the aisle talk aim to the bench — not from `CAM_LOOK_GX`, which
			## would snap the POV and hide the right-bench sleep NPC.
			_obj_look_y_target_gx = OBJ_LOOK_Y_TALK_GX
			if _cam != null:
				_cam.begin_morph_to_rover(morph_from_gx, true)
			_play_rover(ANIM_SITDOWN, false)
			_await_then(Action.SEATED, ANIM_SITDOWN)
		Action.SEATED:
			if _cam != null:
				_cam.lock_on_rover()
				_cam.set_obj_look_y(OBJ_LOOK_Y_TALK_GX)
			_play_rover(ANIM_SIT_WAIT, true)
		Action.STANDUP:
			## Decomp never clears `lock_camera_flag` after first talk — look stays on Rover
			## through standup / aisle / phone (`aNGD_standup_start_wait` only drops look Y).
			_pos_gx = ROVER_STAND_GX
			_apply_rover_pose()
			_obj_look_y_target_gx = OBJ_LOOK_Y_NORMAL_GX
			camera_eyes = false
			_set_rover_eyes(false)
			_play_rover(ANIM_STANDUP, false)
			_await_then(Action.MOVE_AISLE, ANIM_STANDUP)
		Action.MOVE_AISLE:
			_begin_aisle_turn()
			_speed_gx = WALK_SPEED2_GX
			_target_gx = ROVER_AISLE_GX
			_aisle_walk_started = false
			_play_rover(ANIM_WAIT, true)
		Action.MOVE_DOOR:
			_speed_gx = WALK_SPEED2_GX
			_target_gx = ROVER_DOOR_GX
			_play_rover(ANIM_WALK, true)
		Action.MOVE_DECK:
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
			_play_rover(ANIM_KEITAI_TALK, true)
			if _phone_dialogue_done:
				_set_action(Action.KEITAI_OFF)
		Action.KEITAI_OFF:
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
			## Lock still on Rover; `aNGD_return_approach_init` only re-enables head look-at.
			_speed_gx = WALK_SPEED2_GX
			_pos_gx = ROVER_RETURN_START_GX
			_yaw = 0.0
			_apply_rover_pose()
			camera_eyes = true
			_set_rover_eyes(true)
			_play_rover(ANIM_WALK, true)
		Action.LAST_SIT:
			## `aNGD_sitdown2` — snap to the bench and play sitdown mid-farewell.
			_set_action(Action.SITDOWN)
		_:
			pass
	_refresh_camera(0.0, false)


func _tick_enter(_delta: float) -> void:
	if not _anim_playing():
		_set_action(Action.APPROACH)


func _tick_approach(delta: float) -> void:
	## `aNGD_approach`: walk the aisle at x=140 until z reaches 290.
	_tick_move_axis_z(delta, ROVER_TALK_GX.z, Action.TALK, ROVER_AISLE_X_GX, 1.0)


func _tick_move_aisle(delta: float) -> void:
	## `aNGD_move_to_aisle`: ease yaw toward the aisle, then step with walk.
	_aisle_turn_t = minf(_aisle_turn_t + delta / ANIM_MORPH_BLEND, 1.0)
	_yaw = lerp_angle(_aisle_yaw_from, _aisle_yaw_to, _hermit_morph(_aisle_turn_t))
	_apply_rover_pose()
	if not _aisle_walk_started:
		if _aisle_turn_t < 1.0:
			return
		_aisle_walk_started = true
		_play_rover(ANIM_WALK, true)
	_tick_move_until_x_reached(delta, ROVER_AISLE_GX.x, Action.MOVE_DOOR)


func _tick_move_door(delta: float) -> void:
	## `aNGD_move_to_door`: aisle at x=140, walk toward the vestibule.
	## Phone tilt starts when shadow z < 140 — checked after the step (decomp order).
	_face_toward_gx(ROVER_DOOR_GX)
	_tick_move_axis_z(delta, ROVER_DOOR_GX.z, Action.MOVE_DECK, ROVER_AISLE_X_GX, -1.0)
	if _pos_gx.z < CAMERA_TILT_Z_GX and _cam != null:
		_cam.set_phone_tilt(true)


func _tick_return_approach(delta: float) -> void:
	## `aNGD_return_approach`: x=140 fixed, walk back toward the player.
	_tick_move_axis_z(delta, ROVER_TALK_GX.z, Action.TALK, ROVER_AISLE_X_GX, 1.0)


func _tick_move_to_seat(delta: float) -> void:
	## Walk from the aisle talk spot to the facing seat before `npc_1_sitdown_d1`.
	_face_toward_gx(ROVER_SIT_GX)
	var step: float = _speed_gx * 30.0 * delta
	var to_seat: Vector3 = ROVER_SIT_GX - _pos_gx
	to_seat.y = 0.0
	var dist: float = to_seat.length()
	if dist <= maxf(step, 0.001):
		_pos_gx = ROVER_SIT_GX
		_yaw = 0.0
		_apply_rover_pose()
		_set_action(Action.SITDOWN)
		return
	_pos_gx += to_seat.normalized() * step
	_apply_rover_pose()


func _tick_move_deck(_delta: float) -> void:
	pass


func _tick_open_door(_delta: float) -> void:
	## `aNGD_open_door`: ease yaw to face the car; at open_d2 frame 22 clear phone tilt.
	if _pos_gx.z < CAMERA_TILT_Z_GX:
		_yaw = lerp_angle(_yaw, OPEN_D2_YAW, OPEN_D2_YAW_CHASE * _delta * 30.0)
		_apply_rover_pose()
	if (
		_phone_tilt_reset_armed
		and _pos_gx.z < CAMERA_TILT_Z_GX
		and _rover_anim_frame() >= DOOR_OPEN_D2_FRAME
	):
		_phone_tilt_reset_armed = false
		if _cam != null:
			_cam.set_phone_tilt(false)


func _tick_move_axis_z(
	delta: float, target_z: float, arrive: Action, x_gx: float, direction: float
) -> void:
	_pos_gx.x = x_gx
	var step: float = _speed_gx * 30.0 * delta
	if direction >= 0.0:
		_yaw = 0.0
		if _pos_gx.z + step >= target_z:
			_pos_gx.z = target_z
			_apply_rover_pose()
			_set_action(arrive)
			return
		_pos_gx.z += step
	else:
		_yaw = PI
		if _pos_gx.z - step <= target_z:
			_pos_gx.z = target_z
			_apply_rover_pose()
			_set_action(arrive)
			return
		_pos_gx.z -= step
	_apply_rover_pose()


func _tick_move_until_x_reached(delta: float, target_x: float, arrive: Action) -> void:
	var step: float = _speed_gx * 30.0 * delta
	if _pos_gx.x + step >= target_x:
		_pos_gx.x = target_x
		_apply_rover_pose()
		_set_action(arrive)
		return
	var dir: Vector3 = ROVER_AISLE_GX - _pos_gx
	dir.y = 0.0
	dir = dir.normalized()
	_pos_gx += dir * step
	_apply_rover_pose()


func _face_toward_gx(target_gx: Vector3) -> void:
	var to: Vector3 = target_gx - _pos_gx
	to.y = 0.0
	if to.length_squared() > 0.001:
		_yaw = atan2(to.x, to.z)


func _begin_aisle_turn() -> void:
	_aisle_yaw_from = _yaw
	var to: Vector3 = ROVER_AISLE_GX - _pos_gx
	to.y = 0.0
	if to.length_squared() > 0.001:
		_aisle_yaw_to = atan2(to.x, to.z)
	else:
		_aisle_yaw_to = _yaw
	_aisle_turn_t = 0.0


func _apply_rover_pose() -> void:
	if _rover == null:
		return
	_rover.global_position = gx_to_meters(_pos_gx)
	_rover.rotation.y = _yaw


func _play_door_sync(sync_name: StringName) -> void:
	if _door != null and _door.has_method("reset_door_pulse"):
		_door.call("reset_door_pulse")
	if _stage_sync != null and _stage_sync.has_method("play"):
		_stage_sync.call("play", sync_name)


func _set_rover_eyes(active: bool) -> void:
	if _rover_look != null and _rover_look.has_method("set_camera_eyes"):
		_rover_look.set_camera_eyes(active)


func _current_camera_look_gx(ground_gx: Vector3) -> Vector3:
	if _cam == null:
		return CAM_LOOK_GX
	return _cam.current_look_gx(ground_gx, action)


func _steady_camera_look_gx(ground_gx: Vector3) -> Vector3:
	if _cam == null:
		return CAM_LOOK_GX
	return _cam.steady_look_gx(ground_gx, action)


func _rover_anim_frame() -> float:
	## cKF frame index at 30 Hz from the active Rover clip.
	if _rover_anim == null:
		return 0.0
	return _rover_anim.current_animation_position * 30.0


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
		ANIM_OPEN_D1, ANIM_SITDOWN, ANIM_STANDUP:
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
	match action:
		Action.ENTER:
			_tick_enter(delta)
		Action.APPROACH:
			_tick_approach(delta)
		Action.MOVE_AISLE:
			_tick_move_aisle(delta)
		Action.MOVE_DOOR:
			_tick_move_door(delta)
		Action.RETURN_APPROACH:
			_tick_return_approach(delta)
		Action.MOVE_TO_SEAT:
			_tick_move_to_seat(delta)
		Action.MOVE_DECK:
			_tick_move_deck(delta)
		Action.OPEN_DOOR:
			_tick_open_door(delta)
		Action.SITDOWN, Action.STANDUP, Action.KEITAI_ON, Action.KEITAI_OFF:
			pass
		_:
			pass
	_refresh_camera(delta)


func _refresh_camera(delta: float, advance_morph: bool = true) -> void:
	if _cam == null:
		return
	_cam.tick(delta, _pos_gx, action, advance_morph)


func _update_camera(delta: float) -> void:
	_refresh_camera(delta)


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
