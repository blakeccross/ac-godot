class_name IntroStationStage
extends RefCounted

## Outdoor station arrival (`ac_intro_demo` + `m_train_control` demo path + Porter / Nook).
## Coordinates are GX relative to station-acre block origin (decomp block 3,1 → world 1920,640).

signal stage_changed(action: StringName)
signal porter_talk_requested
signal nook_call_requested
signal nook_introduce_requested
signal nook_show_houses_requested
signal nook_debt_requested
signal nook_job_requested
signal house_pick_enabled(enabled: bool)
signal enter_house_requested(house_idx: int)
signal leave_house_requested
signal finished
signal assets_missing(missing: PackedStringArray)

enum Action {
	ARRIVE_SETUP,
	TRAIN_APPROACH,
	DOOR_OPEN,
	GET_OFF,
	PORTER_TALK,
	PLAYER_CONTROL,
	NOOK_BIRTH,
	NOOK_CALL,
	NOOK_APPROACH,
	NOOK_INTRODUCE,
	NOOK_LEAD,
	NOOK_EXPLAIN,
	PLAYER_PICK,
	IN_HOUSE,
	NOOK_DEBT,
	NOOK_JOB,
	DONE,
}

const BGM_ID := &"intro_arrive"
const TICK_HZ := 30.0

## Block-local GX (`aID_*` / `mTRC_demo_init` minus block origin).
const TRACK_Z_GX := 100.0
const TRAIN_START_X_GX := 117.0 ## 2037 − 1920
const TRAIN_SLOW_X_GX := 245.0 ## 2165 − 1920
const CABOOSE_GAP_GX := 125.0 ## mid-car X = loco.x − 125 (`train0->arg0_f` in title demo)
## Passenger car (`TRAIN1`) sits another 125 behind the mid: loco.x − 250.
const PASSENGER_GAP_GX := 250.0
const ENGINEER_OFF_GX := Vector3(-40.0, 47.0, 20.0)
const RIDE_OFF_GX := Vector3(60.0, 20.0, 20.0) ## `aTR1_passenger_ctrl` on TRAIN1
const DOORWAY_GX := Vector3(260.0, 0.0, 180.0) ## 2180, 820
const OFF_UT_GX := Vector3(300.0, 0.0, 200.0) ## 2220, 840
const OUT_STATION_Z_GX := 330.0 ## 970 − 640
const STATION_GX := Vector3(320.0, 0.0, 220.0) ## unit (8,5) −20 X
const PORTER_GX := Vector3(220.0, 0.0, 180.0) ## unit (5,4)
const NOOK_SPAWN_GX := Vector3(340.0, 0.0, 620.0) ## unit (8,15)
const NOOK_FACE_GX := Vector3(400.0, 0.0, 340.0) ## toward (2320, 980) absolute
## Meet point before the vacant plots (`aNRG_take_with` → absolute ~2240,1300).
## Generated towns override this with the real `player_house*` cluster.
const NOOK_EXPLAIN_GX := Vector3(220.0, 0.0, 400.0)
const HOUSE_GX: Array[Vector3] = [
	Vector3(140.0, 0.0, 460.0),
	Vector3(280.0, 0.0, 460.0),
	Vector3(140.0, 0.0, 560.0),
	Vector3(280.0, 0.0, 560.0),
]

## `grd_s_t_st1_1` center counts → GX via `FieldCatalog.counts_to_y` (elev 0).
## Track row ≈ count 6; platform ≈ count 8; south lawn ≈ count 4.
const TRACK_Y_GX := 20.0
const PLATFORM_Y_GX := 40.0
const LAND_Y_GX := 0.0

## Train speeds (`m_train_control` non-GAFU).
const TRAIN_SLOW_SPEED := 2.0
const TRAIN_STOP_RATE := 0.005
const SIGNAL_STOP_FRAMES := 48
const NOOK_RUN_SPEED_GX := 4.0
## `aID_walk_after_rcn_guide` rates vs Nook speed when xz distance < 80 GX.
const DEMO_FOLLOW_NEAR_GX := 80.0
const DEMO_FOLLOW_NEAR_RATE := 0.6
const DEMO_FOLLOW_FAR_RATE := 1.0
const GETOFF_DURATION := 1.15
## Ride facing is 0 (`aTR1_passenger_ctrl` ZeroSVec), not caboose actor yaw.
const RIDE_YAW := 0.0

## `Camera2_request_main_demo_fromNowPos2`: look doorway, dist 620, dir −135/−180 →
## eye = look + (0, 620·√½, 620·√½). Outdoor FOV matches `FollowCamera` (20°).
const CAM_DIST_GX := 620.0
const CAM_ISO := 0.70710678
const CAM_LOOK_Y_OFF_GX := -35.0 ## `mCoBG_GetBgY_OnlyCenter_FromWpos2(..., -35)`
const CAM_FOV := 20.0
const CAM_NEAR_METERS := 0.1
const CAM_FAR_METERS := 80.0

## Track runs along +X. Anim-bind + `ckf_basis` puts loco / mid / caboose all long on +X
## (decomp actor yaw 90° is N64/cKF space — not Godot mesh yaw).
const LOCO_YAW := 0.0
const MID_YAW := 0.0
const CABOOSE_YAW := 0.0
## Unscaled mesh AABB centers (GX / pipeline units) at yaw 0 — applied on the
## GeneratedVisual child so the car body sits on the track actor point.
const LOCO_MESH_CENTER_GX := Vector3(0.25, 0.0, 0.0)
const MID_MESH_CENTER_GX := Vector3(0.75, 0.0, 0.0)
const CABOOSE_MESH_CENTER_GX := Vector3(0.0, 0.0, 0.98)

const REQUIRED_PATHS: PackedStringArray = [
	"res://assets/generated/environment/obj_train1_1.glb",
	"res://assets/generated/environment/obj_train1_2.glb",
	"res://assets/generated/environment/obj_train1_3.glb",
	"res://assets/generated/characters/villagers/mnk_1.glb",
	"res://assets/generated/characters/villagers/rcn_1.glb",
]

var action: Action = Action.ARRIVE_SETUP
## When false, the real player CharacterBody3D / FollowCamera own movement & follow.
var drive_player: bool = true
var drive_camera: bool = true

var _loco: Node3D
var _mid: Node3D
var _caboose: Node3D
var _engineer: Node3D
var _porter: Node3D
var _nook: Node3D
var _player: Node3D
var _camera: Camera3D
var _caboose_anim: AnimationPlayer
var _player_anim: AnimationPlayer
var _porter_anim: AnimationPlayer
var _nook_anim: AnimationPlayer
var _engineer_anim: AnimationPlayer

var _origin_meters: Vector3 = Vector3.ZERO
var _world_data: WorldData
var _world_grid: WorldGrid
var _out_station_z_gx: float = OUT_STATION_Z_GX
var _nook_spawn_gx: Vector3 = NOOK_SPAWN_GX
var _nook_face_gx: Vector3 = NOOK_FACE_GX
var _nook_explain_gx: Vector3 = NOOK_EXPLAIN_GX
var _house_gx: Array[Vector3] = []

var _loco_x_gx: float = TRAIN_START_X_GX
var _train_speed: float = TRAIN_SLOW_SPEED
var _signal_timer: float = 0.0
var _getoff_t: float = 0.0
var _getoff_from_gx: Vector3 = Vector3.ZERO
var _nook_goal_gx: Vector3 = Vector3.ZERO
var _awaiting_dialogue: bool = false
var _tick_accum: float = 0.0
var _unit_centers: PackedByteArray = PackedByteArray()
var _motor: PlayerLocomotion = PlayerLocomotion.new()
var house_idx: int = 0
var _control_locked: bool = false


func bind(
	loco: Node3D,
	mid: Node3D,
	caboose: Node3D,
	engineer: Node3D,
	porter: Node3D,
	nook: Node3D,
	player: Node3D,
	camera: Camera3D
) -> void:
	_loco = loco
	_mid = mid
	_caboose = caboose
	_engineer = engineer
	_porter = porter
	_nook = nook
	_player = player
	_camera = camera
	_caboose_anim = GeneratedVisual.find_animation_player(caboose)
	_player_anim = GeneratedVisual.find_animation_player(player)
	_porter_anim = GeneratedVisual.find_animation_player(porter)
	_nook_anim = GeneratedVisual.find_animation_player(nook)
	_engineer_anim = GeneratedVisual.find_animation_player(engineer)
	## Door open/close bake a non-bind `joint_0` translation; strip so only doors move.
	GeneratedVisual.strip_named_joint_tracks(_caboose_anim, "joint_0")
	GeneratedVisual.strip_named_joint_tracks(
		GeneratedVisual.find_animation_player(loco), "joint_0"
	)
	_house_gx = HOUSE_GX.duplicate()
	_load_unit_centers()
	## Callers that know the town layout should `set_landmarks` after `bind`.


func set_block_origin(origin_meters: Vector3) -> void:
	_origin_meters = origin_meters


func set_world_ground(data: WorldData, grid: WorldGrid) -> void:
	_world_data = data
	_world_grid = grid


func set_landmarks(
	out_station_z_gx: float,
	nook_spawn_gx: Vector3,
	nook_face_gx: Vector3,
	nook_explain_gx: Vector3,
	house_gx: Array[Vector3]
) -> void:
	_out_station_z_gx = out_station_z_gx
	_nook_spawn_gx = nook_spawn_gx
	_nook_face_gx = nook_face_gx
	_nook_explain_gx = nook_explain_gx
	if house_gx.is_empty():
		_house_gx = HOUSE_GX.duplicate()
	else:
		_house_gx = house_gx.duplicate()


func reset() -> void:
	action = Action.ARRIVE_SETUP
	_loco_x_gx = TRAIN_START_X_GX
	_train_speed = TRAIN_SLOW_SPEED
	_signal_timer = 0.0
	_getoff_t = 0.0
	_awaiting_dialogue = false
	_tick_accum = 0.0
	_control_locked = false
	house_idx = 0
	_motor.reset(PI * 0.5)
	if _nook != null:
		_nook.visible = false
	_place_static_actors()
	_place_train()
	_snap_player_to_ride()
	_set_arrive_camera()
	_play_clip(_engineer_anim, "npc_1_wait1", true)
	_play_clip(_porter_anim, "npc_1_wait1", true)
	_play_clip(_player_anim, "ply_1_wait1", true)
	_set_action(Action.TRAIN_APPROACH)


func begin_debt_after_house() -> void:
	## World re-entry after claiming a vacant myhome.
	_control_locked = false
	_awaiting_dialogue = true
	if _nook != null:
		_nook.visible = true
	_face_toward(_nook, _player_gx())
	_face_toward(_player, _node_gx(_nook))
	_play_clip(_nook_anim, "npc_1_wait1", true)
	_play_clip(_player_anim, "ply_1_wait1", true)
	_set_action(Action.NOOK_DEBT)
	nook_debt_requested.emit()


func missing_assets() -> PackedStringArray:
	var missing: PackedStringArray = []
	for path: String in REQUIRED_PATHS:
		if not ResourceLoader.exists(path):
			missing.append(path)
	return missing


func tick(delta: float) -> void:
	_tick_accum += delta
	var step: float = 1.0 / TICK_HZ
	while _tick_accum >= step:
		_tick_accum -= step
		_tick_frame()
	if _player_may_move():
		_tick_player_control(delta)
	_update_follow_camera()


func notify_dialogue_closed() -> void:
	if not _awaiting_dialogue:
		return
	_awaiting_dialogue = false
	match action:
		Action.PORTER_TALK:
			_motor.reset(_player.rotation.y if _player else 0.0)
			_set_action(Action.PLAYER_CONTROL)
			_set_exit_camera()
			_play_clip(_player_anim, "ply_1_wait1", true)
		Action.NOOK_CALL:
			_set_action(Action.NOOK_APPROACH)
			_nook_goal_gx = _player_gx() + Vector3(0.0, 0.0, 70.0)
			_play_clip(_nook_anim, "npc_1_run1", true)
			_face_toward(_nook, _nook_goal_gx)
		Action.NOOK_INTRODUCE:
			## Lead the player to the vacant plots (`aNRG` TAKE_WITH → EXPLAIN).
			_nook_goal_gx = _nook_explain_gx
			_play_clip(_nook_anim, "npc_1_run1", true)
			_face_toward(_nook, _nook_goal_gx)
			_motor.reset(_player.rotation.y if _player else 0.0)
			_set_action(Action.NOOK_LEAD)
			_set_exit_camera()
		Action.NOOK_EXPLAIN:
			_set_action(Action.PLAYER_PICK)
			house_pick_enabled.emit(true)
			_play_clip(_player_anim, "ply_1_wait1", true)
			_play_clip(_nook_anim, "npc_1_wait1", true)
		Action.NOOK_DEBT:
			_awaiting_dialogue = true
			_set_action(Action.NOOK_JOB)
			nook_job_requested.emit()
		Action.NOOK_JOB:
			_set_action(Action.DONE)
			finished.emit()


func notify_house_entered(idx: int) -> void:
	if action != Action.PLAYER_PICK:
		return
	house_idx = clampi(idx, 0, maxi(_house_gx.size() - 1, 0))
	house_pick_enabled.emit(false)
	_control_locked = true
	_play_clip(_player_anim, "ply_1_wait1", true)
	_set_action(Action.IN_HOUSE)
	enter_house_requested.emit(house_idx)


func notify_house_exited() -> void:
	if action != Action.IN_HOUSE:
		return
	_control_locked = false
	## Place player just south of the chosen door; Nook faces them for the loan talk.
	var door: Vector3 = (
		_house_gx[house_idx] if house_idx < _house_gx.size() else HOUSE_GX[0]
	) + Vector3(0.0, 0.0, 40.0)
	_set_node_gx(_player, _with_ground(door))
	_set_node_gx(_nook, _with_ground(door + Vector3(40.0, 0.0, 0.0)))
	_face_toward(_nook, _player_gx())
	_face_toward(_player, _node_gx(_nook))
	leave_house_requested.emit()
	_awaiting_dialogue = true
	_set_action(Action.NOOK_DEBT)
	nook_debt_requested.emit()


func notify_house_pick_again() -> void:
	## Player rejected the house (`msg_2023`) — free stick to try another vacant plot.
	_awaiting_dialogue = false
	_control_locked = false
	_set_action(Action.PLAYER_PICK)
	house_pick_enabled.emit(true)
	_play_clip(_player_anim, "ply_1_wait1", true)
	_play_clip(_nook_anim, "npc_1_wait1", true)


func _player_may_move() -> bool:
	## Free stick only after Porter and again for house pick. TAKE_WITH is demo-walk.
	if _awaiting_dialogue or _control_locked:
		return false
	return action in [Action.PLAYER_CONTROL, Action.PLAYER_PICK]


func player_controls_locked() -> bool:
	## Director uses this for `set_busy` — locked during ride, talks, and Nook lead.
	if action == Action.DONE:
		return true
	return action not in [Action.PLAYER_CONTROL, Action.PLAYER_PICK]


func player_cutscene_driven() -> bool:
	## Stage owns pose during train ride / get-off / guided follow.
	return action in [
		Action.ARRIVE_SETUP,
		Action.TRAIN_APPROACH,
		Action.DOOR_OPEN,
		Action.GET_OFF,
		Action.NOOK_LEAD,
	]


static func gx_to_meters(gx: Vector3) -> Vector3:
	return gx * FieldCatalog.GX_TO_METERS


func ground_y_gx(x_gx: float, z_gx: float) -> float:
	if _world_data != null and _world_grid != null:
		var world: Vector3 = _origin_meters + gx_to_meters(Vector3(x_gx, 0.0, z_gx))
		var y: float = FieldCollision.ground_y_at(_world_data, _world_grid, world, 0.0, false)
		if FieldCollision.has_floor(y):
			return y / FieldCatalog.GX_TO_METERS
	## Sample `grd_s_t_st1_1` center counts (elev 0 for isolated acre scene).
	if _unit_centers.is_empty():
		if z_gx < 160.0:
			return TRACK_Y_GX
		if z_gx < 280.0:
			return PLATFORM_Y_GX
		return LAND_Y_GX
	var ux: int = clampi(int(floor(x_gx / 40.0)), 0, 15)
	var uz: int = clampi(int(floor(z_gx / 40.0)), 0, 15)
	var count: int = int(_unit_centers[uz * 16 + ux])
	return FieldCatalog.counts_to_y(count, 0) / FieldCatalog.GX_TO_METERS


func _tick_frame() -> void:
	match action:
		Action.TRAIN_APPROACH:
			_tick_train_approach()
		Action.DOOR_OPEN:
			_tick_door_open()
		Action.GET_OFF:
			_tick_get_off()
		Action.NOOK_APPROACH:
			_tick_nook_approach()
		Action.NOOK_LEAD:
			_tick_nook_lead()
		_:
			pass
	_place_train()
	if action == Action.TRAIN_APPROACH or action == Action.DOOR_OPEN:
		_snap_player_to_ride()


func _tick_train_approach() -> void:
	## One 30 Hz frame of `mTRC_ACTION_BEGIN_SLOWDOWN` → `BEGIN_STOP`.
	if _loco_x_gx <= TRAIN_SLOW_X_GX:
		_train_speed = TRAIN_SLOW_SPEED
	else:
		_train_speed = move_toward(_train_speed, 0.0, TRAIN_STOP_RATE)
		if _train_speed < 0.008:
			_train_speed = 0.0
			_signal_timer = float(SIGNAL_STOP_FRAMES)
			_open_caboose_door()
			_set_action(Action.DOOR_OPEN)
			return
	_loco_x_gx += 0.5 * _train_speed


func _tick_door_open() -> void:
	_signal_timer = maxf(0.0, _signal_timer - 1.0)
	if _signal_timer > 0.0:
		return
	_set_action(Action.GET_OFF)
	_getoff_t = 0.0
	_getoff_from_gx = _ride_player_gx()
	_play_getoff_anim()


func _tick_get_off() -> void:
	_getoff_t = minf(1.0, _getoff_t + (1.0 / TICK_HZ) / GETOFF_DURATION)
	var to_gx: Vector3 = _with_ground(Vector3(DOORWAY_GX.x, 0.0, DOORWAY_GX.z + 8.0))
	var p: Vector3 = _getoff_from_gx.lerp(to_gx, smoothstep(0.0, 1.0, _getoff_t))
	_set_node_gx(_player, p)
	_face_yaw(_player, 0.0) ## face +Z (south, off the platform)
	if _getoff_t < 1.0:
		return
	_play_clip(_player_anim, "ply_1_wait1", true)
	_face_toward(_porter, _player_gx())
	_awaiting_dialogue = true
	_set_action(Action.PORTER_TALK)
	porter_talk_requested.emit()


func _tick_player_control(delta: float) -> void:
	if _player == null:
		return
	if drive_player and delta > 0.0:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var stick: float = clampf(input_dir.length(), 0.0, 1.0)
		var wish := _camera_wish(input_dir)
		var planar: Vector3 = _motor.tick(
			delta, wish, stick, Input.is_action_pressed("sprint"), false
		)
		var pos: Vector3 = _player_gx()
		pos.x += planar.x * delta / FieldCatalog.GX_TO_METERS
		pos.z += planar.z * delta / FieldCatalog.GX_TO_METERS
		pos.y = ground_y_gx(pos.x, pos.z)
		_set_node_gx(_player, pos)
		_player.rotation = Vector3(0.0, _motor.facing, 0.0)
		_sync_player_gait_anim()
	if action == Action.PLAYER_CONTROL and _player_gx().z >= _out_station_z_gx:
		_play_clip(_player_anim, "ply_1_wait1", true)
		_set_action(Action.NOOK_BIRTH)
		_spawn_nook()


func _tick_nook_approach() -> void:
	var pos: Vector3 = _node_gx(_nook)
	var goal: Vector3 = _nook_goal_gx
	var delta_xz := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
	var dist: float = delta_xz.length()
	var step: float = NOOK_RUN_SPEED_GX
	if dist <= step:
		_set_node_gx(_nook, _with_ground(goal))
		_play_clip(_nook_anim, "npc_1_wait1", true)
		_face_toward(_nook, _player_gx())
		_face_toward(_player, goal)
		_awaiting_dialogue = true
		_set_action(Action.NOOK_INTRODUCE)
		nook_introduce_requested.emit()
		return
	_set_node_gx(_nook, _with_ground(pos + delta_xz.normalized() * step))
	_face_toward(_nook, goal)


func _tick_nook_lead() -> void:
	var pos: Vector3 = _node_gx(_nook)
	var goal: Vector3 = _nook_goal_gx
	var delta_xz := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
	var dist: float = delta_xz.length()
	var step: float = NOOK_RUN_SPEED_GX
	if dist <= step:
		_set_node_gx(_nook, _with_ground(goal))
		_play_clip(_nook_anim, "npc_1_wait1", true)
		## Face the house cluster (door fronts), not only the first stub plot.
		var face := Vector3.ZERO
		if not _house_gx.is_empty():
			for h: Vector3 in _house_gx:
				face += h
			face /= float(_house_gx.size())
		else:
			face = HOUSE_GX[0]
		_face_toward(_nook, face)
		_awaiting_dialogue = true
		_set_action(Action.NOOK_EXPLAIN)
		nook_show_houses_requested.emit()
		return
	_set_node_gx(_nook, _with_ground(pos + delta_xz.normalized() * step))
	_face_toward(_nook, goal)
	## `aID_walk_after_rcn_guide`: demo-walk the player toward Nook (controls locked).
	_demo_follow_nook()


func _demo_follow_nook() -> void:
	if _player == null or _nook == null:
		return
	var nook_gx: Vector3 = _node_gx(_nook)
	var pos: Vector3 = _player_gx()
	var delta_xz := Vector3(nook_gx.x - pos.x, 0.0, nook_gx.z - pos.z)
	var dist: float = delta_xz.length()
	if dist < 8.0:
		_play_clip(_player_anim, "ply_1_wait1", true)
		return
	var rate: float = (
		DEMO_FOLLOW_NEAR_RATE if dist < DEMO_FOLLOW_NEAR_GX else DEMO_FOLLOW_FAR_RATE
	)
	var speed: float = NOOK_RUN_SPEED_GX * rate
	var step: float = minf(speed, dist)
	var next: Vector3 = pos + delta_xz.normalized() * step
	next.y = ground_y_gx(next.x, next.z)
	_set_node_gx(_player, next)
	_face_toward(_player, nook_gx)
	_play_clip(_player_anim, "ply_1_run1" if rate >= 0.99 else "ply_1_walk1", true)


func _spawn_nook() -> void:
	if _nook == null:
		return
	_nook.visible = true
	_set_node_gx(_nook, _with_ground(_nook_spawn_gx))
	_face_toward(_nook, _nook_face_gx)
	_play_clip(_nook_anim, "npc_1_wait1", true)
	_awaiting_dialogue = true
	_set_action(Action.NOOK_CALL)
	nook_call_requested.emit()


func _place_static_actors() -> void:
	_set_node_gx(_porter, _with_ground(PORTER_GX))
	_face_yaw(_porter, PI) ## face −Z toward tracks
	if _nook != null:
		_nook.visible = false


func _place_train() -> void:
	var track_y: float = ground_y_gx(_loco_x_gx, TRACK_Z_GX)
	var loco_gx := Vector3(_loco_x_gx, track_y, TRACK_Z_GX)
	_set_node_gx(_loco, loco_gx)
	_face_yaw(_loco, LOCO_YAW)
	_center_train_visual(_loco, LOCO_MESH_CENTER_GX)
	## Mid-car: `ac_train0_draw` translates to arg0_f (= loco.x − 125) with no yaw.
	var mid_gx := Vector3(_loco_x_gx - CABOOSE_GAP_GX, track_y, TRACK_Z_GX)
	_set_node_gx(_mid, mid_gx)
	_face_yaw(_mid, MID_YAW)
	_center_train_visual(_mid, MID_MESH_CENTER_GX)
	## Passenger / caboose (`TRAIN1`): another 125 behind mid → loco.x − 250.
	var caboose_gx := Vector3(_loco_x_gx - PASSENGER_GAP_GX, track_y, TRACK_Z_GX)
	_set_node_gx(_caboose, caboose_gx)
	_face_yaw(_caboose, CABOOSE_YAW)
	_center_train_visual(_caboose, CABOOSE_MESH_CENTER_GX)
	if _engineer != null:
		_set_node_gx(_engineer, loco_gx + ENGINEER_OFF_GX)
		_face_yaw(_engineer, LOCO_YAW)


func _snap_player_to_ride() -> void:
	_set_node_gx(_player, _ride_player_gx())
	## `aTR1_passenger_ctrl` forces rot.y = 0 while riding.
	_face_yaw(_player, RIDE_YAW)


func _ride_player_gx() -> Vector3:
	## Stand in the passenger car (`aTR1_passenger_ctrl`), not the mid body.
	var track_y: float = ground_y_gx(_loco_x_gx - PASSENGER_GAP_GX, TRACK_Z_GX)
	return Vector3(_loco_x_gx - PASSENGER_GAP_GX, track_y, TRACK_Z_GX) + RIDE_OFF_GX


func _open_caboose_door() -> void:
	if _caboose_anim == null:
		return
	for name: String in ["obj_train1_3_open", "open"]:
		if _caboose_anim.has_animation(name):
			_caboose_anim.play(name, 0.0, 0.5)
			return


func _play_getoff_anim() -> void:
	if _player_anim == null:
		return
	for name: String in ["ply_1_outtrain1", "ply_1_walk1"]:
		if _player_anim.has_animation(name):
			_player_anim.play(name)
			return


func _set_arrive_camera() -> void:
	if _camera == null or not drive_camera:
		return
	_camera.fov = CAM_FOV
	_camera.near = CAM_NEAR_METERS
	_camera.far = CAM_FAR_METERS
	## Look near doorway at `GetBgY(..., -35)` — ground sample + CAM_LOOK_Y_OFF_GX.
	var look_gx := Vector3(
		DOORWAY_GX.x,
		ground_y_gx(DOORWAY_GX.x, DOORWAY_GX.z) + CAM_LOOK_Y_OFF_GX,
		DOORWAY_GX.z
	)
	var eye_gx: Vector3 = look_gx + Vector3(0.0, CAM_DIST_GX * CAM_ISO, CAM_DIST_GX * CAM_ISO)
	_camera.global_position = _gx_to_world(eye_gx)
	_camera.look_at(_gx_to_world(look_gx), Vector3.UP)


func _set_exit_camera() -> void:
	## Hand off to FollowCamera (`Camera2_request_main_normal`) — director resumes it.
	pass


func _update_follow_camera(_force: bool = false) -> void:
	## Demo doorway framing is applied once in `_set_action`, not every tick (avoids
	## look_at jitter while the player steps off the caboose). After Porter, the
	## world's FollowCamera owns the eye.
	pass


func _set_action(next: Action) -> void:
	var prev: Action = action
	action = next
	## Pin DEMO framing when entering arrival beats; hold it (no per-frame rewrite).
	if drive_camera and next in [
		Action.TRAIN_APPROACH,
		Action.DOOR_OPEN,
		Action.GET_OFF,
		Action.PORTER_TALK,
	]:
		if prev != next:
			_apply_arrive_camera_once()
	stage_changed.emit(_action_name(next))


func _apply_arrive_camera_once() -> void:
	_set_arrive_camera()


func _action_name(a: Action) -> StringName:
	match a:
		Action.ARRIVE_SETUP:
			return &"arrive_setup"
		Action.TRAIN_APPROACH:
			return &"train_approach"
		Action.DOOR_OPEN:
			return &"door_open"
		Action.GET_OFF:
			return &"get_off"
		Action.PORTER_TALK:
			return &"porter_talk"
		Action.PLAYER_CONTROL:
			return &"player_control"
		Action.NOOK_BIRTH:
			return &"nook_birth"
		Action.NOOK_CALL:
			return &"nook_call"
		Action.NOOK_APPROACH:
			return &"nook_approach"
		Action.NOOK_INTRODUCE:
			return &"nook_introduce"
		Action.NOOK_LEAD:
			return &"nook_lead"
		Action.NOOK_EXPLAIN:
			return &"nook_explain"
		Action.PLAYER_PICK:
			return &"player_pick"
		Action.IN_HOUSE:
			return &"in_house"
		Action.NOOK_DEBT:
			return &"nook_debt"
		Action.NOOK_JOB:
			return &"nook_job"
		_:
			return &"done"


func _player_gx() -> Vector3:
	return _node_gx(_player)


func _node_gx(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return (node.global_position - _origin_meters) / FieldCatalog.GX_TO_METERS


func _set_node_gx(node: Node3D, gx: Vector3) -> void:
	if node == null:
		return
	node.global_position = _gx_to_world(gx)


func _gx_to_world(gx: Vector3) -> Vector3:
	return _origin_meters + gx_to_meters(gx)


func _with_ground(gx: Vector3) -> Vector3:
	return Vector3(gx.x, ground_y_gx(gx.x, gx.z), gx.z)


func _face_toward(node: Node3D, target_gx: Vector3) -> void:
	if node == null:
		return
	var from: Vector3 = _node_gx(node)
	var delta := Vector3(target_gx.x - from.x, 0.0, target_gx.z - from.z)
	if delta.length_squared() < 0.01:
		return
	_face_yaw(node, atan2(delta.x, delta.z))


func _face_yaw(node: Node3D, yaw: float) -> void:
	if node == null:
		return
	if node.has_method("apply_facing"):
		node.call("apply_facing", yaw)
	else:
		node.rotation = Vector3(0.0, yaw, 0.0)


func _center_train_visual(host: Node3D, center_gx: Vector3) -> void:
	## Keep the actor origin on the decomp track point; shift only the mesh so the
	## car body sits on the rails (pipeline AABBs are off-origin).
	if host == null:
		return
	var vis: Node3D = host.get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	var s: float = vis.scale.x if vis.scale.x > 0.0 else FieldCatalog.actor_uniform_scale()
	vis.position.x = -center_gx.x * s
	vis.position.z = -center_gx.z * s


func _sync_player_gait_anim() -> void:
	match _motor.gait():
		PlayerLocomotion.Gait.WAIT:
			_play_clip(_player_anim, "ply_1_wait1", true)
		PlayerLocomotion.Gait.WALK:
			_play_clip(_player_anim, "ply_1_walk1", true)
		PlayerLocomotion.Gait.RUN:
			_play_clip(_player_anim, "ply_1_run1", true)
		PlayerLocomotion.Gait.DASH:
			_play_clip(_player_anim, "ply_1_dash1", true)


func _play_clip(anim: AnimationPlayer, clip: String, loop: bool) -> void:
	if anim == null or clip.is_empty():
		return
	var resolved := clip
	if not anim.has_animation(clip):
		resolved = ""
		for anim_name: String in anim.get_animation_list():
			if (
				anim_name == clip
				or anim_name.ends_with("/" + clip)
				or anim_name.ends_with(clip)
			):
				resolved = anim_name
				break
		if resolved.is_empty():
			return
	if anim.current_animation == resolved and anim.is_playing():
		return
	var animation: Animation = anim.get_animation(resolved)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim.play(resolved)


func _camera_wish(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var look := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	if _camera != null:
		look = -_camera.global_transform.basis.z
		look.y = 0.0
		if look.length_squared() > 0.0001:
			look = look.normalized()
		right = _camera.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()
	var wish := look * -input_dir.y + right * input_dir.x
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	return wish


func _load_unit_centers() -> void:
	_unit_centers = PackedByteArray()
	var path := "res://assets/generated/environment/acres/grd_s_t_st1_1.col.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var units: Variant = (parsed as Dictionary).get("units", [])
	if typeof(units) != TYPE_ARRAY:
		return
	var arr: Array = units
	_unit_centers.resize(256)
	for i: int in mini(arr.size(), 256):
		var u: Variant = arr[i]
		if typeof(u) == TYPE_DICTIONARY:
			_unit_centers[i] = clampi(int((u as Dictionary).get("c", 4)), 0, 31)
		else:
			_unit_centers[i] = 4
