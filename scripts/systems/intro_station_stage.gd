class_name IntroStationStage
extends RefCounted

## Outdoor station arrival: `ac_intro_demo` (`aID_*` actions), with the Porter
## (`ac_npc_station_master`) and Tom Nook (`ac_npc_rcn_guide`, `aNRG_*` thinks).
## Coordinates are GX relative to the station block (3, 1) origin, decomp world (1920, 640);
## every landmark below is the decomp's absolute GX minus that origin. The generated town
## keeps the decomp's fixed blocks (station at (3, 1), the four player houses at (3, 2)), so
## the absolute points line up.
##
## The train is the town train itself (`train_coming_flag = 3` → `mTRC_demo_init`): the world
## path hands in `TrainService`'s `TrainControl` + `FieldTrain`; the standalone debug acre
## steps its own `TrainControl` / `TrainCars` on the nodes it binds.

signal stage_changed(action: StringName)
signal porter_talk_requested
signal nook_call_requested
signal nook_introduce_requested
signal nook_show_houses_requested
signal nook_stop_wade_requested
signal nook_debt_requested
signal nook_job_requested
signal nook_exit_started
signal house_pick_enabled(enabled: bool)
signal enter_house_requested(house_idx: int)
signal leave_house_requested
signal finished
signal assets_missing(missing: PackedStringArray)

## `aID_ACT_*` (and the `aNRG` thinks they wait on).
enum Action {
	ARRIVE_SETUP, ## FIRST_SET / TRAIN_BIRTH_WAIT
	TRAIN_APPROACH, ## RIDE_TRAIN — player held on the passenger car until `WAIT_STOPPED`
	GET_OFF, ## RIDE_OFF_PLAYER — OUTTRAIN1, then the Porter's line
	PORTER_TALK,
	WALK_ONE_UNIT, ## demo walk to (2220, 840), demo camera still up
	PLAYER_CONTROL, ## GO_OUT_OF_STATION — free until z ≥ 970
	NOOK_BIRTH,
	NOOK_CALL, ## `aNRG` CALL (`0x07DE`)
	NOOK_APPROACH, ## APPROACH — runs to 70 below the player
	NOOK_INTRODUCE, ## INTRODUCE (`0x07DF`)
	NOOK_TURN, ## TURN toward (2240, 1300)
	NOOK_LEAD, ## TAKE_WITH / WALK_AFTER_RCN_GUIDE
	NOOK_EXPLAIN, ## EXPLAIN (`0x07E1`)
	PLAYER_PICK, ## DECIDE_HOUSE_WAIT
	NOOK_STOP_WADE, ## STOP_WADE (`0x07E2`)
	IN_HOUSE,
	NOOK_DEBT, ## RESTART_TALK (`0x07E6`)
	NOOK_JOB,
	NOOK_EXIT_TURN, ## EXIT_TURN
	NOOK_EXIT, ## EXIT — run off, then `Actor_delete`
	DONE, ## RETIRE_RCN_GUIDE_WAIT satisfied
}

const BGM_ID := &"intro_arrive"

## Decomp world GX of the station block's NW corner (`mFI_BkNum2WposXZ(3, 1)`).
const BLOCK_ORIGIN_GX := Vector3(1920.0, 0.0, 640.0)
const BLOCK_GX := 640.0
const UNIT_GX := 40.0

const TRACK_Z_GX := 100.0 ## rail row z 740
## `aTR1_passenger_ctrl`: player forced to TRAIN1 + (60, 20, 20), rot 0 (`ZeroSVec`).
const RIDE_OFF_GX := Vector3(60.0, 20.0, 20.0)
const RIDE_YAW := 0.0
## `aID_PLR_START_*`: (3·640 + 1.25·40, 640 + 3·40).
const PLAYER_START_GX := Vector3(50.0, 0.0, 120.0)
## `aID_train_birth_wait_init` demo camera centre, also the caboose doorway (2180, 820).
const DOORWAY_GX := Vector3(260.0, 0.0, 180.0)
## `aID_walk_one_unit_init`: `mPlib_request_main_demo_walk_type1(2220, 840, 2.5)`.
const OFF_UT_GX := Vector3(300.0, 0.0, 200.0)
const OFF_UT_SPEED_GX := 2.5
## `aID_OUT_OF_STATION_Z_POS`: 640 + 8.25·40 = 970.
const OUT_STATION_Z_GX := 330.0
const STATION_GX := Vector3(320.0, 0.0, 220.0) ## unit (8, 5) −20 X
## `fd_npc_land` Porter: block (3, 1) unit (5, 4) centre.
const PORTER_GX := Vector3(220.0, 0.0, 180.0)
## `aID_birth_rcn_guide`: block (3, 1) unit (8, 15) centre.
const NOOK_SPAWN_GX := Vector3(340.0, 0.0, 620.0)
## `aNRG_call_init`: faces (2320, 980).
const NOOK_FACE_GX := Vector3(400.0, 0.0, 340.0)
## `aNRG_approach_init`: run to the player's x, z + 70.
const NOOK_APPROACH_Z_GX := 70.0
## `aNRG_turn_init` / `aNRG_take_with`: (2240, 1300) then (2240, 1500).
const NOOK_LEAD_GX: Array[Vector3] = [Vector3(320.0, 0.0, 660.0), Vector3(320.0, 0.0, 860.0)]
## `aID_birth_rcn_guide` restart (`_1A4`): block (3, 2) units `restart_ux/uz`, centre +
## `restartOffsetX` ±10 / `ofsZ` 8, indexed by house (`mFI_FIELD_PLAYER0_ROOM` + idx).
const NOOK_RESTART_GX: Array[Vector3] = [
	Vector3(270.0, 0.0, 868.0),
	Vector3(370.0, 0.0, 868.0),
	Vector3(270.0, 0.0, 1148.0),
	Vector3(370.0, 0.0, 1148.0),
]
## `aNRG_exit_turn_init` / `aNRG_exit`: x 2240, split at z 1540; delete past 1220 / 1980.
const NOOK_EXIT_X_GX := 320.0
const NOOK_EXIT_SPLIT_Z_GX := 900.0
const NOOK_EXIT_TURN_Z_GX: Array[float] = [1260.0, 660.0] ## 1900, 1300
const NOOK_EXIT_NORTH_Z_GX: Array[float] = [580.0, 660.0] ## done ≤ 1220; ≤ 1300 → 1220; else → 1300
const NOOK_EXIT_SOUTH_Z_GX: Array[float] = [1340.0, 1260.0] ## done ≥ 1980; ≥ 1900 → 1980; else → 1900
## `aID_walk_after_rcn_guide`: `rate_table[player_distance_xz < 80] × rcn_guide.speed`.
const DEMO_FOLLOW_NEAR_GX := 80.0
const DEMO_FOLLOW_NEAR_RATE := 0.6
const DEMO_FOLLOW_FAR_RATE := 1.0
## `Player_actor_Movement_Demo_walk`: speed never below 0.5.
const DEMO_WALK_MIN_SPEED_GX := 0.5
## `Player_actor_Movement_Demo_walk` eases in once the goal is closer than `2 · speed` and
## snaps the last 0.5 GX; the player actor's demo walk stops at that radius instead.
const DEMO_WALK_SNAP_GX := 0.5

## Station-lawn stub plots, only for the standalone debug acre (the town uses its houses).
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

## Debug acre get-off without a player actor: OUTTRAIN1's root walks 52 GX forward.
const GETOFF_DURATION := StructureDoor.OUTTRAIN_SEC
const GETOFF_STEP_GX := 52.0
## `cKF_ba_r_obj_train1_1` — wheel/rod loop (`aTR0_actor_ct` / `aTR0_animation`).
const LOCO_WHEEL_CLIP := "obj_train1_1"

## `Camera2_request_main_demo_fromNowPos2`: centre the doorway, dist 620, direction
## (−135°, −180°) → eye = centre + (0, 620·sin 45°, 620·cos 45°), goal_delta 0 (immediate).
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

const NOOK_WAIT_CLIP := "npc_1_wait1"
const NOOK_WALK_CLIP := "npc_1_walk1"
const NOOK_RUN_CLIP := "npc_1_run1"

const REQUIRED_PATHS: PackedStringArray = [
	"res://assets/generated/environment/obj_train1_1.glb",
	"res://assets/generated/environment/obj_train1_2.glb",
	"res://assets/generated/environment/obj_train1_3.glb",
	"res://assets/generated/characters/villagers/mnk_1.glb",
	"res://assets/generated/characters/villagers/rcn_1.glb",
]

var action: Action = Action.ARRIVE_SETUP
## Debug acre only: the stage owns the camera until the Porter's walk-off.
var drive_camera: bool = true

var _loco: Node3D
var _mid: Node3D
var _caboose: Node3D
var _engineer: Node3D
var _porter: Node3D
var _nook: Node3D
var _player: Node3D
var _camera: Camera3D
var _loco_anim: AnimationPlayer
var _caboose_anim: AnimationPlayer
var _player_anim: AnimationPlayer
var _nook_anim: AnimationPlayer

var _origin_meters: Vector3 = Vector3.ZERO
var _world_data: WorldData
var _world_grid: WorldGrid
var _house_gx: Array[Vector3] = []

## The train: `TrainService`'s (world) or our own (debug acre).
var _control: TrainControl
var _cars: TrainCars
var _field_train: FieldTrain
var _own_train: bool = false
var _rail_y_gx: float = TRACK_Y_GX

var _getoff_t: float = 0.0
var _getoff_from_gx: Vector3 = Vector3.ZERO
var _awaiting_dialogue: bool = false
var _steps := FrameStepper.new()
var _unit_centers: PackedByteArray = PackedByteArray()
var _motor: PlayerLocomotion = PlayerLocomotion.new()
var _nook_move: NpcPointMove = NpcPointMove.new()
var _nook_goal_gx: Vector3 = Vector3.ZERO
var _nook_path: int = 0
var _nook_turn_gx: Vector3 = Vector3.ZERO
var house_idx: int = 0


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
	_loco_anim = VisualAnimation.find_animation_player(loco)
	_caboose_anim = VisualAnimation.find_animation_player(caboose)
	_player_anim = VisualAnimation.find_animation_player(player)
	_nook_anim = VisualAnimation.find_animation_player(nook)
	## Door/wheel clips bake a non-bind `joint_0` translation; strip so only doors/wheels move.
	VisualAnimation.strip_named_joint_tracks(_caboose_anim, "joint_0")
	VisualAnimation.strip_named_joint_tracks(_loco_anim, "joint_0")
	_house_gx = HOUSE_GX.duplicate()
	_load_unit_centers()


## World path: ride the town train (`TrainService`), which the caller has put in the arrival
## demo (`request_arrival_demo`).
func use_field_train(control: TrainControl, train: FieldTrain) -> void:
	_control = control
	_field_train = train
	_own_train = false


func set_block_origin(origin_meters: Vector3) -> void:
	_origin_meters = origin_meters


func set_world_ground(data: WorldData, grid: WorldGrid) -> void:
	_world_data = data
	_world_grid = grid


## Door sensors of the debug acre's stub plots (the town houses pick themselves).
func set_house_gx(house_gx: Array[Vector3]) -> void:
	_house_gx = HOUSE_GX.duplicate() if house_gx.is_empty() else house_gx.duplicate()


func reset() -> void:
	action = Action.ARRIVE_SETUP
	_getoff_t = 0.0
	_awaiting_dialogue = false
	_steps.reset()
	house_idx = 0
	_motor.reset(RIDE_YAW)
	_nook_move.reset(0.0)
	if _nook != null:
		_nook.visible = false
	if _control == null:
		## Debug acre: this stage runs `m_train_control` itself.
		_own_train = true
		_control = TrainControl.new()
		_control.demo_init(Clock.now_sec(), Clock.day)
		_cars = TrainCars.new()
		_cars.spawn(_control.x_gx)
		_rail_y_gx = ground_y_gx(_control.x_gx - BLOCK_ORIGIN_GX.x, TRACK_Z_GX)
		_start_loco_wheels()
		VisualTrain.snap_train_doors_closed(_caboose_anim)
		_place_own_train()
	_place_porter()
	## `aID_first_set_init`: the player starts at (1970, 760) until the train exists.
	_set_node_gx(_player, _with_ground(PLAYER_START_GX))
	_face_yaw(_player, RIDE_YAW)
	_play_clip(_player_anim, "ply_1_wait1", true)
	_set_arrive_camera()
	_set_action(Action.TRAIN_APPROACH)


## World re-entry after claiming a vacant house (`aID` `_1A4` path): Nook is born beside
## it (`aID_birth_rcn_guide` restart) and waits for the player to finish coming out
## (`aNRG_restart_wait`) before the loan talk.
func place_nook_for_restart(idx: int) -> void:
	house_idx = clampi(idx, 0, NOOK_RESTART_GX.size() - 1)
	if _nook == null:
		return
	_nook.visible = true
	_set_node_gx(_nook, _with_ground(NOOK_RESTART_GX[house_idx]))
	## `aNRG_actor_ct`: faces the player on birth.
	_nook_face(NpcPointMove.yaw_to(_node_gx(_nook), _player_gx()))
	_nook_move.stop()
	_play_clip(_nook_anim, NOOK_WAIT_CLIP, true)
	_set_action(Action.IN_HOUSE)


func begin_debt_after_house() -> void:
	## `aNRG_restart_wait` → RESTART_TALK once the player is out of the door.
	_awaiting_dialogue = true
	if _nook != null:
		_nook.visible = true
	_play_clip(_nook_anim, NOOK_WAIT_CLIP, true)
	_set_action(Action.NOOK_DEBT)
	nook_debt_requested.emit()


func missing_assets() -> PackedStringArray:
	var missing: PackedStringArray = []
	for path: String in REQUIRED_PATHS:
		if not ResourceLoader.exists(path):
			missing.append(path)
	return missing


func tick(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		_tick_frame()
	if _player_may_move():
		_tick_debug_player_control(delta)
	## `aTR1_passenger_ctrl` runs after the train moves: re-pin every rendered frame.
	if action == Action.TRAIN_APPROACH:
		_snap_player_to_ride()


func notify_dialogue_closed() -> void:
	if not _awaiting_dialogue:
		return
	_awaiting_dialogue = false
	match action:
		Action.PORTER_TALK:
			## `aSTM_talk_end_chk` → INTERRUPT_TURN / MOVE; `aID_walk_one_unit_init`.
			if _porter is StationPorter:
				(_porter as StationPorter).begin_step_east()
			_set_action(Action.WALK_ONE_UNIT)
			_demo_walk_to(OFF_UT_GX, OFF_UT_SPEED_GX)
		Action.NOOK_CALL:
			## `aNRG_approach_init`: the goal is fixed where the player stood.
			_nook_goal_gx = _player_gx() + Vector3(0.0, 0.0, NOOK_APPROACH_Z_GX)
			_set_action(Action.NOOK_APPROACH)
		Action.NOOK_INTRODUCE:
			## `aNRG_turn_init`: TURN toward (2240, 1300); the player keeps waiting.
			_nook_turn_gx = NOOK_LEAD_GX[0]
			_set_action(Action.NOOK_TURN)
		Action.NOOK_EXPLAIN:
			_begin_pick()
		Action.NOOK_STOP_WADE:
			_begin_pick()
		Action.NOOK_DEBT:
			_awaiting_dialogue = true
			_set_action(Action.NOOK_JOB)
			nook_job_requested.emit()
		Action.NOOK_JOB:
			_begin_nook_exit()


## `DECIDE_HOUSE_WAIT`: a house entry comes from the town's door (world) or a stub sensor.
func notify_house_entered(idx: int) -> void:
	if action != Action.PLAYER_PICK:
		return
	house_idx = clampi(idx, 0, maxi(_house_gx.size() - 1, 0))
	house_pick_enabled.emit(false)
	_play_clip(_player_anim, "ply_1_wait1", true)
	_set_action(Action.IN_HOUSE)
	enter_house_requested.emit(house_idx)


## Debug acre re-entry (the world path uses `place_nook_for_restart`).
func notify_house_exited() -> void:
	if action != Action.IN_HOUSE:
		return
	var door: Vector3 = (
		_house_gx[house_idx] if house_idx < _house_gx.size() else HOUSE_GX[0]
	) + Vector3(0.0, 0.0, 40.0)
	_set_node_gx(_player, _with_ground(door))
	_set_node_gx(_nook, _with_ground(door + Vector3(40.0, 0.0, 0.0)))
	_nook_face(NpcPointMove.yaw_to(_node_gx(_nook), _player_gx()))
	_face_toward(_player, _node_gx(_nook))
	leave_house_requested.emit()
	_awaiting_dialogue = true
	_set_action(Action.NOOK_DEBT)
	nook_debt_requested.emit()


func notify_house_pick_again() -> void:
	## Player rejected the house (`msg_2023`) — free stick to try another vacant plot.
	_awaiting_dialogue = false
	_begin_pick()


## `excute_cancel_wade` while `mPlib_Set_unable_wade(TRUE)`: Nook calls the player back.
func notify_wade_cancelled() -> void:
	if action != Action.PLAYER_PICK:
		return
	house_pick_enabled.emit(false)
	_awaiting_dialogue = true
	_set_action(Action.NOOK_STOP_WADE)
	nook_stop_wade_requested.emit()


func _begin_pick() -> void:
	_nook_move.stop()
	_play_clip(_nook_anim, NOOK_WAIT_CLIP, true)
	_play_clip(_player_anim, "ply_1_wait1", true)
	_motor.reset(_player.rotation.y if _player != null else 0.0)
	_set_action(Action.PLAYER_PICK)
	house_pick_enabled.emit(true)


func _player_may_move() -> bool:
	if _awaiting_dialogue:
		return false
	return action in [Action.PLAYER_CONTROL, Action.PLAYER_PICK]


## Stick input is off (talks, rides, Nook's walk-offs). Demo walks are not "locked" — the
## player actor walks itself toward the demo goal and ignores the stick meanwhile.
func player_controls_locked() -> bool:
	return action not in [
		Action.PLAYER_CONTROL,
		Action.PLAYER_PICK,
		Action.WALK_ONE_UNIT,
		Action.NOOK_LEAD,
	] or _awaiting_dialogue


## The stage pins the player's pose (the ride).
func player_cutscene_driven() -> bool:
	return action in [Action.ARRIVE_SETUP, Action.TRAIN_APPROACH]


## `mPlib_Set_unable_wade(TRUE)` from DECIDE_HOUSE until Nook has gone.
func player_unable_wade() -> bool:
	return action in [
		Action.PLAYER_PICK,
		Action.NOOK_STOP_WADE,
		Action.IN_HOUSE,
		Action.NOOK_DEBT,
		Action.NOOK_JOB,
		Action.NOOK_EXIT_TURN,
		Action.NOOK_EXIT,
	]


## Demo camera (`Camera2_request_main_demo`) until GO_OUT_OF_STATION's `request_main_normal`.
func uses_demo_camera() -> bool:
	return action in [
		Action.ARRIVE_SETUP,
		Action.TRAIN_APPROACH,
		Action.GET_OFF,
		Action.PORTER_TALK,
		Action.WALK_ONE_UNIT,
	]


static func gx_to_meters(gx: Vector3) -> Vector3:
	return gx * FieldCatalog.GX_TO_METERS


## Stage GX (station-block relative) of a decomp world GX point.
static func block_gx(world_gx: Vector3) -> Vector3:
	return world_gx - BLOCK_ORIGIN_GX


static func house_index(house_id: StringName) -> int:
	var id := String(house_id)
	if id.begins_with("player_house_"):
		return clampi(int(id.substr(13)), 0, 3)
	return 0


func ground_y_gx(x_gx: float, z_gx: float) -> float:
	if _world_data != null and _world_grid != null:
		var world: Vector3 = _origin_meters + gx_to_meters(Vector3(x_gx, 0.0, z_gx))
		var y: float = FieldCollision.ground_y_at(_world_data, _world_grid, world, 0.0, false)
		if FieldCollision.has_floor(y):
			return (y - _origin_meters.y) / FieldCatalog.GX_TO_METERS
	## Sample `grd_s_t_st1_1` center counts (elev 0 for isolated acre scene).
	if _unit_centers.is_empty():
		if z_gx < 160.0:
			return TRACK_Y_GX
		if z_gx < 280.0:
			return PLATFORM_Y_GX
		return LAND_Y_GX
	var ux: int = clampi(int(floor(x_gx / UNIT_GX)), 0, 15)
	var uz: int = clampi(int(floor(z_gx / UNIT_GX)), 0, 15)
	var count: int = int(_unit_centers[uz * 16 + ux])
	return FieldCatalog.counts_to_y(count, 0) / FieldCatalog.GX_TO_METERS


func _tick_frame() -> void:
	if _own_train:
		_step_own_train()
	match action:
		Action.TRAIN_APPROACH:
			_tick_ride_train()
		Action.GET_OFF:
			_tick_get_off()
		Action.WALK_ONE_UNIT:
			_tick_walk_one_unit()
		Action.PLAYER_CONTROL:
			_tick_go_out_of_station()
		Action.NOOK_APPROACH:
			_tick_nook_approach()
		Action.NOOK_TURN:
			_tick_nook_turn()
		Action.NOOK_LEAD:
			_tick_nook_lead()
		Action.NOOK_EXIT_TURN:
			_tick_nook_exit_turn()
		Action.NOOK_EXIT:
			_tick_nook_exit()


## `aID_ride_train`: the train stops (action 4, door opens), then `WAIT_STOPPED` (5) lets
## the player off.
func _tick_ride_train() -> void:
	if _control == null:
		return
	if _control.action == TrainControl.Action.WAIT_STOPPED:
		_begin_get_off()


## `aID_ride_off_player_init`: `train->arg0 = FALSE`, `mPlib_request_main_demo_getoff_train`.
func _begin_get_off() -> void:
	_set_action(Action.GET_OFF)
	_getoff_t = 0.0
	_getoff_from_gx = _player_gx()
	if _player is Player:
		(_player as Player).begin_demo_getoff_train(_player.global_position, RIDE_YAW)
	else:
		_play_clip(_player_anim, "ply_1_outtrain1", false)


## `aID_ride_off_player` + `aSTM_get_off_wait`: once the player is out of GETOFF_TRAIN and
## the Porter's current action has ended, he force-talks (`0x07DD`).
func _tick_get_off() -> void:
	if _player is Player:
		if (_player as Player).is_door_entering():
			return
	else:
		_getoff_t = minf(1.0, _getoff_t + DecompTime.TICK_SEC / GETOFF_DURATION)
		var to_gx: Vector3 = _getoff_from_gx + Vector3(0.0, 0.0, GETOFF_STEP_GX)
		to_gx.y = lerpf(_getoff_from_gx.y, ground_y_gx(to_gx.x, to_gx.z), _getoff_t)
		_set_node_gx(_player, _getoff_from_gx.lerp(to_gx, _getoff_t))
		if _getoff_t < 1.0:
			return
		_play_clip(_player_anim, "ply_1_wait1", true)
	if _porter is StationPorter and not (_porter as StationPorter).is_idle():
		return
	if not _porter is StationPorter:
		_face_toward(_porter, _player_gx())
	_awaiting_dialogue = true
	_set_action(Action.PORTER_TALK)
	porter_talk_requested.emit()


## `aID_walk_one_unit`: keep the demo-walk goal until the player reaches z 840.
func _tick_walk_one_unit() -> void:
	var arrive: float = demo_walk_arrive_gx(OFF_UT_SPEED_GX) + DEMO_WALK_SNAP_GX
	var pos: Vector3 = _player_gx()
	var near: bool = Vector2(OFF_UT_GX.x - pos.x, OFF_UT_GX.z - pos.z).length() <= arrive
	if pos.z < OFF_UT_GX.z and not near:
		if not _player is Player:
			_debug_step_toward(OFF_UT_GX, OFF_UT_SPEED_GX)
		return
	## `aID_go_out_of_station_init`: `wait_type3` + `Camera2_request_main_normal`.
	_end_demo_walk()
	_motor.reset(_player.rotation.y if _player != null else 0.0)
	_play_clip(_player_anim, "ply_1_wait1", true)
	_set_action(Action.PLAYER_CONTROL)


## `aID_go_out_of_station`: past z 970 the player is stopped and Nook is born.
func _tick_go_out_of_station() -> void:
	if _player_gx().z < OUT_STATION_Z_GX:
		return
	_stop_player()
	_set_action(Action.NOOK_BIRTH)
	_spawn_nook()


func _spawn_nook() -> void:
	if _nook == null:
		return
	_nook.visible = true
	_set_node_gx(_nook, _with_ground(NOOK_SPAWN_GX))
	## `aNRG_call_init` overrides the birth facing: toward (2320, 980).
	_nook_face(NpcPointMove.yaw_to(NOOK_SPAWN_GX, NOOK_FACE_GX))
	_nook_move.stop()
	_play_clip(_nook_anim, NOOK_WAIT_CLIP, true)
	_awaiting_dialogue = true
	_set_action(Action.NOOK_CALL)
	nook_call_requested.emit()


## `aNRG_approach`: RUN to the fixed point, then INTRODUCE (`aNRG_introduce_init` → WAIT).
func _tick_nook_approach() -> void:
	if _step_nook_to(_nook_goal_gx, true):
		_nook_move.stop()
		_play_clip(_nook_anim, NOOK_WAIT_CLIP, true)
		_awaiting_dialogue = true
		_set_action(Action.NOOK_INTRODUCE)
		nook_introduce_requested.emit()


## `aNRG_turn` → TAKE_WITH (`intro_demo->talk_flag` → `aID_walk_after_rcn_guide`).
func _tick_nook_turn() -> void:
	_nook_move.facing = _nook.rotation.y
	var done: bool = _nook_move.step_turn(NpcPointMove.yaw_to(_node_gx(_nook), _nook_turn_gx))
	_nook_face(_nook_move.facing)
	_play_clip(_nook_anim, NOOK_WALK_CLIP, true)
	if not done:
		return
	_nook_path = 0
	_nook_goal_gx = NOOK_LEAD_GX[0]
	_set_action(Action.NOOK_LEAD)


## `aNRG_take_with` + `aID_walk_after_rcn_guide`.
func _tick_nook_lead() -> void:
	if _step_nook_to(_nook_goal_gx, true):
		if _nook_path >= 1:
			## EXPLAIN: Nook's action drops to WAIT (`action.idx == 0`), so the player stops
			## where they are (`mPlib_request_main_wait_type3`).
			_nook_move.stop()
			_play_clip(_nook_anim, NOOK_WAIT_CLIP, true)
			_stop_player()
			_awaiting_dialogue = true
			_set_action(Action.NOOK_EXPLAIN)
			nook_show_houses_requested.emit()
			return
		_nook_path += 1
		_nook_goal_gx = NOOK_LEAD_GX[_nook_path]
	_follow_nook()


## `mPlib_Set_goal_player_demo_walk(rcn.x, rcn.z, rate · rcn.speed)` every frame.
func _follow_nook() -> void:
	if _player == null or _nook == null:
		return
	var nook_gx: Vector3 = _node_gx(_nook)
	var pos: Vector3 = _player_gx()
	var dist: float = Vector2(nook_gx.x - pos.x, nook_gx.z - pos.z).length()
	var rate: float = DEMO_FOLLOW_NEAR_RATE if dist < DEMO_FOLLOW_NEAR_GX else DEMO_FOLLOW_FAR_RATE
	var speed: float = maxf(rate * _nook_move.speed, DEMO_WALK_MIN_SPEED_GX)
	if _player is Player:
		_demo_walk_to(nook_gx, speed)
	else:
		_debug_step_toward(nook_gx, speed)


## `aNRG_exit_turn_init`: TURN toward (2240, 1900) or (2240, 1300) by which side of z 1540
## he is on. `aID_retire_rcn_guide_wait_init` starts at the same moment (BGM fade).
func _begin_nook_exit() -> void:
	var z: float = _node_gx(_nook).z
	var turn_z: float = NOOK_EXIT_TURN_Z_GX[1 if z < NOOK_EXIT_SPLIT_Z_GX else 0]
	_nook_turn_gx = Vector3(NOOK_EXIT_X_GX, 0.0, turn_z)
	_stop_player()
	_set_action(Action.NOOK_EXIT_TURN)
	nook_exit_started.emit()


func _tick_nook_exit_turn() -> void:
	_nook_move.facing = _nook.rotation.y
	var done: bool = _nook_move.step_turn(NpcPointMove.yaw_to(_node_gx(_nook), _nook_turn_gx))
	_nook_face(_nook_move.facing)
	_play_clip(_nook_anim, NOOK_WALK_CLIP, true)
	if not done:
		return
	var next: Vector3 = nook_exit_waypoint(_node_gx(_nook))
	if next == Vector3.INF:
		_retire_nook()
		return
	_nook_goal_gx = next
	_set_action(Action.NOOK_EXIT)


## `aNRG_exit`: each time a run ends, pick the next leave point from his z; past the last one
## he is deleted.
func _tick_nook_exit() -> void:
	if not _step_nook_to(_nook_goal_gx, true):
		return
	var next: Vector3 = nook_exit_waypoint(_node_gx(_nook))
	if next == Vector3.INF:
		_retire_nook()
		return
	_nook_goal_gx = next


## `aNRG_exit` leave points; `Vector3.INF` once he is past the last one (`Actor_delete`).
static func nook_exit_waypoint(pos_gx: Vector3) -> Vector3:
	var z: float = pos_gx.z
	var target_z: float
	if z < NOOK_EXIT_SPLIT_Z_GX:
		if z <= NOOK_EXIT_NORTH_Z_GX[0]:
			return Vector3.INF
		target_z = NOOK_EXIT_NORTH_Z_GX[0] if z <= NOOK_EXIT_NORTH_Z_GX[1] else NOOK_EXIT_NORTH_Z_GX[1]
	else:
		if z >= NOOK_EXIT_SOUTH_Z_GX[0]:
			return Vector3.INF
		target_z = NOOK_EXIT_SOUTH_Z_GX[0] if z >= NOOK_EXIT_SOUTH_Z_GX[1] else NOOK_EXIT_SOUTH_Z_GX[1]
	return Vector3(NOOK_EXIT_X_GX, 0.0, target_z)


func _retire_nook() -> void:
	_nook_move.stop()
	if _nook != null:
		_nook.visible = false
	_set_action(Action.DONE)
	finished.emit()


## One frame of Nook's RUN / WALK toward `goal`. True when the action ends (arrival).
func _step_nook_to(goal: Vector3, run: bool) -> bool:
	if _nook == null:
		return true
	## `aNPC_position_move` runs every frame on the actor's speed; the action's arrival check
	## only ends the action — a new point he is already inside is simply run past.
	var pos: Vector3 = _node_gx(_nook)
	_nook_move.facing = _nook.rotation.y
	var next: Vector3 = _nook_move.step_to(pos, goal, run)
	_set_node_gx(_nook, _with_ground(next))
	_nook_face(_nook_move.facing)
	_play_clip(_nook_anim, NOOK_RUN_CLIP if run else NOOK_WALK_CLIP, true)
	return NpcPointMove.arrived(next, goal)


func _nook_face(yaw: float) -> void:
	_nook_move.facing = yaw
	_face_yaw(_nook, yaw)


## `mPlib_request_main_demo_walk_type1` / `mPlib_Set_goal_player_demo_walk`.
func _demo_walk_to(goal_gx: Vector3, speed_gx: float) -> void:
	if not _player is Player:
		return
	var gx: float = FieldCatalog.GX_TO_METERS
	var goal: Vector3 = _gx_to_world(goal_gx)
	(_player as Player).begin_demo_walk(
		goal, speed_gx * DecompTime.FRAME_HZ * gx, demo_walk_arrive_gx(speed_gx) * gx
	)


static func demo_walk_arrive_gx(speed_gx: float) -> float:
	return maxf(2.0 * speed_gx, DEMO_WALK_SNAP_GX)


func _end_demo_walk() -> void:
	if _player is Player:
		(_player as Player).end_demo_walk()


## `mPlib_request_main_demo_wait_type1` / `wait_type3` mid-walk: stop dead, idle.
func _stop_player() -> void:
	_end_demo_walk()
	if _player is Player:
		(_player as Player).stop_for_door()
	else:
		_play_clip(_player_anim, "ply_1_wait1", true)


func _debug_step_toward(goal_gx: Vector3, speed_gx: float) -> void:
	var pos: Vector3 = _player_gx()
	var to := Vector3(goal_gx.x - pos.x, 0.0, goal_gx.z - pos.z)
	var step: float = 0.5 * speed_gx
	if to.length() <= step:
		_set_node_gx(_player, _with_ground(Vector3(goal_gx.x, 0.0, goal_gx.z)))
		_play_clip(_player_anim, "ply_1_wait1", true)
		return
	var next: Vector3 = pos + to.normalized() * step
	_set_node_gx(_player, _with_ground(next))
	_face_toward(_player, goal_gx)
	_play_clip(_player_anim, "ply_1_walk1", true)


## Debug acre: stick walk for the scripted `DemoPlayer` node (no player actor).
func _tick_debug_player_control(delta: float) -> void:
	if _player == null or _player is Player or delta <= 0.0:
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var stick: float = clampf(input_dir.length(), 0.0, 1.0)
	var planar: Vector3 = _motor.tick(
		delta, _camera_wish(input_dir), stick, Input.is_action_pressed("sprint"), false
	)
	var pos: Vector3 = _player_gx()
	pos.x += planar.x * delta / FieldCatalog.GX_TO_METERS
	pos.z += planar.z * delta / FieldCatalog.GX_TO_METERS
	pos.y = ground_y_gx(pos.x, pos.z)
	_set_node_gx(_player, pos)
	_player.rotation = Vector3(0.0, _motor.facing, 0.0)
	_sync_player_gait_anim()


func _place_porter() -> void:
	if _porter is StationPorter:
		(_porter as StationPorter).place_intro(_gx_to_world(_with_ground(PORTER_GX)))
		return
	_set_node_gx(_porter, _with_ground(PORTER_GX))
	_face_yaw(_porter, StationPorter.INTRO_YAW)


## Debug acre: `mTRC_move` + `aTR0` / `aTR1` actor moves on the bound car nodes.
func _step_own_train() -> void:
	_control.step(Clock.now_sec(), Clock.day)
	if _control.action == TrainControl.Action.NONE:
		return
	var door: Dictionary = _cars.step(_control.x_gx, _control.speed, _control.action, false)
	if not door.is_empty():
		FieldTrain.apply_door(_caboose_anim, door)
	if _loco_anim != null:
		_loco_anim.speed_scale = loco_wheel_speed_scale(_control.speed) * DecompTime.TICKS_PER_FRAME
	_place_own_train()


func _place_own_train() -> void:
	var loco_gx := Vector3(_control.x_gx - BLOCK_ORIGIN_GX.x, _rail_y_gx, TRACK_Z_GX)
	_set_node_gx(_loco, loco_gx)
	_face_yaw(_loco, LOCO_YAW)
	VisualTrain.center_train_visual(_loco, LOCO_MESH_CENTER_GX)
	_set_node_gx(_mid, Vector3(_cars.mid_x - BLOCK_ORIGIN_GX.x, _rail_y_gx, TRACK_Z_GX))
	_face_yaw(_mid, MID_YAW)
	VisualTrain.center_train_visual(_mid, MID_MESH_CENTER_GX)
	_set_node_gx(_caboose, Vector3(_cars.caboose_x - BLOCK_ORIGIN_GX.x, _rail_y_gx, TRACK_Z_GX))
	_face_yaw(_caboose, CABOOSE_YAW)
	VisualTrain.center_train_visual(_caboose, CABOOSE_MESH_CENTER_GX)
	if _engineer != null:
		_set_node_gx(_engineer, loco_gx + FieldTrain.ENGINEER_OFF_GX)
		_face_yaw(_engineer, FieldTrain.ENGINEER_YAW)


## `aTR1_passenger_ctrl` (arg0): the player stands at the passenger car + (60, 20, 20).
func _snap_player_to_ride() -> void:
	var car: Vector3 = _caboose_gx()
	if car == Vector3.INF:
		return
	_set_node_gx(_player, car + RIDE_OFF_GX)
	_face_yaw(_player, RIDE_YAW)


func _caboose_gx() -> Vector3:
	if _own_train:
		return Vector3(_cars.caboose_x - BLOCK_ORIGIN_GX.x, _rail_y_gx, TRACK_Z_GX)
	if _field_train == null or not _field_train.is_spawned():
		return Vector3.INF
	return _world_to_gx(_field_train.caboose_world())


static func loco_wheel_speed_scale(train_speed_gx: float) -> float:
	## `aTR0_actor_move`: `(speed / 40) * 10`, capped at 0.5 (cKF frames per tick).
	return minf((train_speed_gx / 40.0) * 10.0, 0.5)


func _start_loco_wheels() -> void:
	if _loco_anim == null:
		return
	_play_clip(_loco_anim, LOCO_WHEEL_CLIP, true)
	_loco_anim.speed_scale = loco_wheel_speed_scale(_control.speed) * DecompTime.TICKS_PER_FRAME


func _set_arrive_camera() -> void:
	if _camera == null or not drive_camera:
		return
	_camera.fov = CAM_FOV
	_camera.near = CAM_NEAR_METERS
	_camera.far = CAM_FAR_METERS
	var look_gx := Vector3(
		DOORWAY_GX.x,
		ground_y_gx(DOORWAY_GX.x, DOORWAY_GX.z) + CAM_LOOK_Y_OFF_GX,
		DOORWAY_GX.z
	)
	var eye_gx: Vector3 = look_gx + Vector3(0.0, CAM_DIST_GX * CAM_ISO, CAM_DIST_GX * CAM_ISO)
	_camera.global_position = _gx_to_world(eye_gx)
	_camera.look_at(_gx_to_world(look_gx), Vector3.UP)


func _set_action(next: Action) -> void:
	action = next
	stage_changed.emit(_action_name(next))


func _action_name(a: Action) -> StringName:
	return StringName(String(Action.keys()[a]).to_lower())


func _player_gx() -> Vector3:
	return _node_gx(_player)


func _node_gx(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return _world_to_gx(node.global_position)


func _world_to_gx(world: Vector3) -> Vector3:
	return (world - _origin_meters) / FieldCatalog.GX_TO_METERS


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
	## The player actor animates itself outside the debug acre.
	if anim == _player_anim and _player is Player:
		return
	var resolved := clip
	if not anim.has_animation(clip):
		resolved = ""
		for anim_name: String in anim.get_animation_list():
			if anim_name == clip or anim_name.ends_with("/" + clip) or anim_name.ends_with(clip):
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
	## `grd_s_t_st1_1` center counts, one byte per unit, from the acre's baked grid.
	_unit_centers = PackedByteArray()
	var units: PackedByteArray = FieldCatalog.acre_units(&"grd_s_t_st1_1")
	if units.is_empty():
		return
	_unit_centers.resize(FieldCatalog.UNITS_PER_ACRE)
	for i: int in FieldCatalog.UNITS_PER_ACRE:
		_unit_centers[i] = units[i * FieldCatalog.UNIT_STRIDE]
