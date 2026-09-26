extends CharacterBody3D

## CharacterBody3D player. Locomotion feel from `m_player_main_walk`; visual from
## generated `boy_1.glb` when the local pipeline has been run. Equipped tools
## parent to HAND (`HeldTool`). Walk physics cylinder radius matches `BgCheckControll`
## range (18 GX → 0.9 m) — same as `FieldCollision.ACTOR_RADIUS` / trees-rocks columns.
## Height keeps the OcInfo stand pipe (60 GX → 3.0 m). Cliffs/water use `revise_xz`,
## not this shape. OcInfo radius 20 is actor-actor CollisionCheck, not world walk.

const GENERATED_PLAYER := "res://assets/generated/characters/player/boy_1.glb"
const LOOK_HEIGHT := 0.85
const INTERACT_REACH := 1.1

## The pipeline samples every `cKF_ba_r_*` clip at 30 fps, so decomp frame numbers convert to
## clip time at this rate.
const ANIM_FPS := 30.0
## `notice_rod` chains message 0x1348 onto the fish catch report when pockets are full.
const POCKETS_FULL_MSG_ID := &"msg_4936"
## `mMsg_Set_continue_msg_num(win, 0xA4F)` for insect catches.
const POCKETS_FULL_BUG_MSG_ID := &"msg_2639"

const ANIM_WAIT := "ply_1_wait1"
const ANIM_WALK := "ply_1_walk1"
const ANIM_RUN := "ply_1_run1"
const ANIM_DASH := "ply_1_dash1"
## `mPlayer_ANIM_RUN_SLIP1` — the dash skid (`turn_dash`).
const ANIM_RUN_SLIP := "ply_1_run_slip1"
## cKF morph −5 / −12 at 60 Hz (`-5.0f` on walk/run/dash/wait, `-12.0f` skid → wait).
const MORPH_5 := 10.0 / 60.0
const MORPH_12 := 24.0 / 60.0
## `Player_actor_sound_slip` (`0x4129`).
const SE_SLIP := &"4129"
## `mPlayer_ANIM_KOKERU*` — fall / get-up, by held item (`Get_PlayerAnimeIndex_fromItemKind_Tumble`).
const ANIM_KOKERU := "ply_1_kokeru1"
const ANIM_KOKERU_A := "ply_1_kokeru_a1"
const ANIM_KOKERU_N := "ply_1_kokeru_n1"
const ANIM_KOKERU_GETUP := "ply_1_kokeru_getup1"
const ANIM_KOKERU_GETUP_A := "ply_1_kokeru_getup_a1"
const ANIM_KOKERU_GETUP_N := "ply_1_kokeru_getup_n1"
## `mPlayer_ANIM_OPEN1` — door enter demo (`mPlayer_INDEX_DOOR`, type 0).
const ANIM_OPEN1 := "ply_1_open1"
## `mPlayer_ANIM_INTO_S1` — indoor door / exit walk (`mPlayer_INDEX_DOOR`, type ≠ 0).
const ANIM_INTO_S1 := "ply_1_into_s1"
## `mPlayer_ANIM_GO_OUT_S1` — outdoor emerge demo (`mPlayer_INDEX_OUTDOOR`, is_start_demo).
const ANIM_GO_OUT_S1 := "ply_1_go_out_s1"
## `mPlayer_ANIM_GO_OUT_O1` — non-demo outdoor emerge (`Player_actor_setup_main_Outdoor`).
const ANIM_GO_OUT_O1 := "ply_1_go_out_o1"
## `mPlayer_ANIM_PUTAWAY1` — pocket put-away (`putin_item` forward, `takeout_item` reversed).
const ANIM_PUTAWAY1 := "ply_1_putaway1"
## `mPlayer_INDEX_HOLD` / `PUSH` / `PULL` / `ROTATE_FURNITURE` clips (`FurnitureGrip`).
const ANIM_HOLD_WAIT1 := "ply_1_hold_wait1"
const ANIM_PUSH1 := "ply_1_push1"
const ANIM_PULL1 := "ply_1_pull1"
const ANIM_LTURN1 := "ply_1_Lturn1"
const ANIM_RTURN1 := "ply_1_Rturn1"
## `mPlayer_INDEX_SITDOWN` / `SITDOWN_WAIT` / `STANDUP` and the bed states (`FurnitureSeat`).
const ANIM_SITDOWN1 := "ply_1_sitdown1"
const ANIM_SITDOWN_WAIT1 := "ply_1_sitdown_wait1"
const ANIM_STANDUP1 := "ply_1_standup1"
const ANIM_INBED_L1 := "ply_1_inbed_L1"
const ANIM_INBED_R1 := "ply_1_inbed_R1"
const ANIM_BED_WAIT1 := "ply_1_bed_wait1"
const ANIM_OUTBED_L1 := "ply_1_outbed_L1"
const ANIM_OUTBED_R1 := "ply_1_outbed_R1"
## Any stick past this gets you up (`Player_actor_GetController_move_percentX/Y`).
const REST_STAND_STICK := 0.1
## `furniture_push` / `furniture_pull` cKF at half speed: 24 frames of 30 Hz.
const FURNITURE_MOVE_SEC := 0.8
## `aMR_FtrRotate`: 5.6°/tick ellipse over 90° — a little under half a second.
const FURNITURE_TURN_SEC := 0.45
## `Player_actor_Movement_Hold`: the player settles onto the contact point.
const GRIP_SETTLE_RATE := 14.0
## `m_player_main_putin_item` / `takeout_item` / `return_outdoor*` timers are game ticks (60 Hz).
const TOOL_TICK_SEC := 1.0 / 60.0
## `morph_counter` 9.0 falls 0.5 per tick and `cKF_SkeletonInfo_R_play` holds the clip's first
## frame the whole time, so the pose morph is 18 ticks before the clip itself starts moving.
const TOOL_MORPH_SEC := 18.0 * TOOL_TICK_SEC
## Put-away: `item_scale` = 1 − t / 18 (ticks), so the tool is gone as the morph ends. The state
## then runs the clip and `Player_actor_CulcAnimation_Base2` needs two more ticks to report
## it stopped (STOPPED, then speed already 0).
const PUTIN_SCALE_TICKS := 18.0
const PUTIN_STOP_TICKS := 2.0
## Take-out: reverse clip after the morph; at tick 36 the item's own hold pose morphs in
## (`InitAnimation_Base1`, morph 9 → 18 ticks) while `item_scale` grows 0 → 1 to tick 54, which
## is also when the state ends.
const TAKEOUT_SCALE_START_TICKS := 36.0
const TAKEOUT_END_TICKS := 54.0
## `RETURN_OUTDOOR` / `RETURN_OUTDOOR2` bracket the take-out, 3 ticks each.
const RETURN_OUTDOOR_TICKS := 3.0
## `extra_data == 2` exits (houses, post office, Able Sisters) start O1 at frame 25 — the
## walk-out is already done, so only the turn-and-close-door shows. `extra_data == 3`
## exits (Nook, museum, police, …) start at frame 1 and walk out in full.
const GO_OUT_O1_DOOR_ONLY_START_SEC := 24.0 / 30.0  ## cKF frame 25 (frame 1 is t = 0)
## `mPlayer_ANIM_OUTTRAIN1` — station caboose step-off (`mPlayer_INDEX_DEMO_GETOFF_TRAIN`).
const ANIM_OUTTRAIN1 := "ply_1_outtrain1"

@onready var _mesh: Node3D = $MeshPivot
@onready var _placeholder: MeshInstance3D = $MeshPivot/PlaceholderMesh
@onready var _probe: Area3D = $MeshPivot/InteractProbe
@onready var _look: Marker3D = $CameraLook

## Title demo: a recorded stick + A replace live input (`mEv_IsTitleDemo` swaps the controller
## in `m_player_controller.c_inc`). Null during normal play.
var scripted_input: TitleDemoInput = null
## `mPlib_request_main_demo_walk_type1`: walk to a world point with the stick ignored (the house
## gyroid's "Save" walk to the door). Inactive when `_demo_walk_speed` is 0.
var _demo_walk_goal: Vector3 = Vector3.ZERO
var _demo_walk_speed: float = 0.0
var _demo_walk_arrive: float = 0.0
var _motor: PlayerLocomotion = PlayerLocomotion.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _busy: bool = false
## Station intro ride / guided walk — stage owns XZ/Y; skip snap + move_and_slide.
var _cutscene_driven: bool = false
var _focus: Node = null
var _anim: AnimationPlayer
var _gait: PlayerLocomotion.Gait = PlayerLocomotion.Gait.WAIT
var _placeholder_bob: float = 0.0
var _hold_anim: StringName = &""
## The umbrella in hand (`player->umbrella_actor`).
var _umbrella: HeldUmbrella = null
## The item's carry pose layered on the arms (`BOY_part_data` / anim1).
var _carry: ToolCarry = null
var _tool_hold_anim: StringName = &""
var _tool_use_anim: StringName = &""
## Tool is put away (door enter) or not yet taken back out (door emerge). `item_kind` is −1 in
## interiors too — `Player_actor_CheckScene_AbleOutItem` only allows the outdoor field.
var _tool_stowed: bool = false
## `PUTIN_ITEM` / `TAKEOUT_ITEM` own the pose; `_update_animation` stays out of the way.
var _tool_swap: bool = false
var _step_time: float = 0.0
var _right_foot: bool = true
var _door_entering: bool = false
## `cKF_SkeletonInfo_R_AnimationMove` for INDEX_DOOR. False for INDEX_OUTDOOR (mesh root motion).
var _door_animation_move: bool = false
var _door_from: Vector3 = Vector3.ZERO
var _door_to: Vector3 = Vector3.ZERO
var _door_yaw: float = 0.0
var _door_move_elapsed: float = 0.0
var _door_move_duration: float = StructureDoor.APPROACH_SEC
var _door_clear_busy: bool = false
## `model_world_position_correction` — decays toward 0 over `fixed_counter` game frames.
var _door_correction: Vector3 = Vector3.ZERO
var _door_fixed_counter: float = 0.0
var _door_frame_accum: float = 0.0
var _door_root_clip: String = ""
## `Player_actor_Movement_Talk` — ease yaw toward the NPC while the talk demo runs.
var _talk_face: Node3D = null
## `player->shake_tree_*`: trees this player has already shaken (little or button).
var _tree_bump: TreeBump = TreeBump.new()
var _talk_turn_debt: float = 0.0
## Holding onto a piece of furniture (`mPlayer_INDEX_HOLD` and its push / pull / turn children).
var _grip: FurnitureGrip = FurnitureGrip.new()
var _gripping: bool = false
var _grip_nice: Vector3 = Vector3.ZERO
var _grip_move: Dictionary = {}
## Sitting in a chair or lying in a bed: `{ kind, id, pos, yaw_facing, approach, phase, t, dur, from, to }`.
var _seat: FurnitureSeat = FurnitureSeat.new()
var _rest: Dictionary = {}
## Crossing into the next acre (`mPlayer_INDEX_WADE`): `{start, end, t}` (world metres,
## ticks); empty when not wading. See `AcreWade`.
var _wade: Dictionary = {}
## Leaf clip → Animation of scaled joint_0 XZ deltas (meters, model space). Filled once.
static var _door_root_xz: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	_motor.ground_sampler = _motor_ground_y
	_motor.flat_sampler = _motor_unit_flat
	_look.position = Vector3(0.0, LOOK_HEIGHT, 0.0)
	_try_load_generated_visual()
	if Game != null and not Game.cloth_changed.is_connected(_on_cloth_changed):
		Game.cloth_changed.connect(_on_cloth_changed)
	if Game != null and not Game.design_changed.is_connected(_on_design_changed):
		Game.design_changed.connect(_on_design_changed)
	_apply_worn_cloth()
	Game.inventory.equipment_changed.connect(_on_equipment_changed)
	_on_equipment_changed(Game.inventory.equipment_id)


func _exit_tree() -> void:
	if Game.inventory.equipment_changed.is_connected(_on_equipment_changed):
		Game.inventory.equipment_changed.disconnect(_on_equipment_changed)


func facing_yaw() -> float:
	return _motor.facing


## World space of the computed left hand (`Player_actor_draw_After_Larm2` / `left_hand_pos`).
## Used by ground-item pocket pull after PICKUP1 frame 20.
func left_hand_global() -> Vector3:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	if skeleton == null:
		return global_position + Vector3(0.0, 0.9, 0.0)
	return HeldCatch.left_hand_global(skeleton)


## `mDemo` TYPE_TALK `turn` — face `npc` until `end_talk_face` (`TalkCamera.end`).
func begin_talk_face(npc: Node3D) -> void:
	_talk_face = npc
	_talk_turn_debt = 0.0


func end_talk_face() -> void:
	_talk_face = null
	_talk_turn_debt = 0.0


func is_talk_facing() -> bool:
	return _talk_face != null and is_instance_valid(_talk_face)


## `aINS_get_stress_sub`: player planar speed as GX per 30 Hz frame.
func insect_stress_move_gx() -> float:
	return _motor.planar_speed / FieldCatalog.GX_TO_METERS / PlayerLocomotion.FRAME_HZ


## `mPlayer_INDEX_DASH`: fish bolt from a dashing player but ignore a walking one.
func is_dashing() -> bool:
	return _motor.gait() == PlayerLocomotion.Gait.DASH


func camera_look_position() -> Vector3:
	return _look.global_position


func apply_spawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	_motor.reset(yaw)
	_mesh.rotation.y = yaw
	_snap_to_bg()


func set_busy(locked: bool) -> void:
	## Intro / cutscene lock — skips wish input and interact.
	_busy = locked
	## Don't steal door-emerge ownership while GO_OUT is running — otherwise
	## `end_door_leave` cannot hand off, and external locks keep clearing the flag.
	if not _door_entering:
		_door_clear_busy = false


func set_facing(yaw: float) -> void:
	_motor.facing = yaw
	if _mesh != null:
		_mesh.rotation.y = yaw


## Hard stop for the exit-cell warp — natural deceleration from run speed would leave the
## player visibly sliding as the 0.6 s wipe goes black. Kill the speed outright.
func stop_for_door() -> void:
	_busy = true
	if not _door_entering:
		_door_clear_busy = false
	_motor.reset(_motor.facing)
	velocity = Vector3.ZERO
	## `_update_animation` only re-picks a clip when the current one has stopped
	## playing, but WALK/RUN loop forever — force the idle pose now instead of
	## letting the walk cycle keep looping under `_busy`.
	play_wait_idle()


func is_busy() -> bool:
	return _busy


func play_wait_anim() -> void:
	play_wait_idle()


func animation_player() -> AnimationPlayer:
	return _anim


## Idle while input-locked (talk / intro). Safe to call during `_busy`.
func play_wait_idle() -> void:
	if _anim == null or _door_entering:
		return
	var clip := _resolve_clip(ANIM_WAIT)
	if clip.is_empty():
		return
	_ensure_loop(clip)
	_gait = PlayerLocomotion.Gait.WAIT
	_anim.speed_scale = 1.0
	if _anim.current_animation != clip or not _anim.is_playing():
		_anim.play(clip, 0.12)


func set_cutscene_driven(enabled: bool) -> void:
	## External pose owner (train ride, Nook TAKE_WITH). Avoids fighting `_snap_to_bg`.
	_cutscene_driven = enabled
	if enabled:
		velocity = Vector3.ZERO
		_motor.reset(_motor.facing)


func is_cutscene_driven() -> bool:
	return _cutscene_driven


func apply_facing(yaw: float) -> void:
	_motor.reset(yaw)
	_mesh.rotation.y = yaw


func _physics_process(delta: float) -> void:
	if _mesh != null:
		_mesh.rotation.x = _motor.lean
	if _umbrella != null:
		_umbrella.tick(delta)
	if _carry != null:
		_carry.advance(delta)
	if _door_entering:
		_tick_door_enter(delta)
		return
	if _cutscene_driven:
		velocity = Vector3.ZERO
		_mesh.rotation.y = _motor.facing
		_update_animation(delta)
		return

	if not _wade.is_empty():
		_tick_wade(delta)
		return

	if _gripping:
		_tick_grip(delta)
	elif not _rest.is_empty():
		_tick_rest(delta)
	elif not _busy and scripted_input == null:
		_poll_furniture_pickup()
		_poll_rest(delta)
	var bg: Array = _bg()
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
		motion_mode = MOTION_MODE_FLOATING
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var wish := Vector3.ZERO
	var stick := 0.0
	var input_dir := Vector2.ZERO
	var menu_open: bool = _menu_open()
	if _demo_walk_speed > 0.0 and not _busy and not menu_open:
		var to_goal := Vector3(_demo_walk_goal.x - global_position.x, 0.0, _demo_walk_goal.z - global_position.z)
		if to_goal.length() > _demo_walk_arrive:
			wish = to_goal.normalized()
			stick = clampf(_demo_walk_speed / PlayerLocomotion.WALK_SPEED, 0.0, 1.0)
	elif not _busy and not menu_open:
		if scripted_input != null:
			input_dir = scripted_input.move
		else:
			input_dir = _read_stick()
		stick = clampf(input_dir.length(), 0.0, 1.0)
		wish = _camera_wish(input_dir)
		if scripted_input != null and scripted_input.consume_a_pressed():
			_try_interact()

	var sprint: bool = (
		scripted_input == null and not is_demo_walking() and Input.is_action_pressed("sprint")
	)
	_motor.position = global_position
	## `mEv_IsNotTitleDemo() && destiny == BAD_LUCK` gates the dash trip.
	_motor.bad_luck = scripted_input == null and Game.destiny() == Game.Destiny.BAD_LUCK
	_motor.axes_active = _axes_active(input_dir) if scripted_input == null else stick > 0.0
	_feed_clip_state()
	var planar: Vector3 = _motor.tick(
		delta, wish, stick, sprint and not menu_open, _busy or menu_open
	)
	velocity.x = planar.x
	velocity.z = planar.z
	_tick_talk_face(delta)
	_mesh.rotation.y = _motor.body_yaw
	_mesh.rotation.x = _motor.lean
	var before: Vector3 = global_position
	move_and_slide()
	if bg.size() == 2:
		global_position = FieldCollision.revise_xz(
			bg[0] as WorldData, bg[1] as WorldGrid, before, global_position
		)
	elif on_bg:
		_snap_to_bg()
	_note_wall_contact(before, planar, delta)
	if bg.size() == 2 and TownSpace.is_outdoor_town():
		_acre_border(before, input_dir, bg)
		if not _wade.is_empty():
			return
	_update_animation(delta)
	_update_footprints(delta, bg)
	_update_focus()
	_tick_tree_bump(delta)
	_clear_auto_enter_block()
	_try_auto_enter()


## `Player_actor_CorrectWadeBlockBorder` then `Player_actor_Set_ScrollDemo_forWade` (walk /
## run / dash only): stay inside this acre unless the stick takes the player across.
func _acre_border(before: Vector3, input_dir: Vector2, bg: Array) -> void:
	var old_gx: Vector3 = TownSpace.world_to_gx(before)
	var now_gx: Vector3 = TownSpace.world_to_gx(global_position)
	var held: Vector3 = AcreWade.confine(old_gx, now_gx)
	if held.x != now_gx.x or held.z != now_gx.z:
		var back: Vector3 = TownSpace.gx_to_world(held)
		global_position.x = back.x
		global_position.z = back.z
		_snap_to_bg()
	if _busy or _menu_open() or _motor.gait() == PlayerLocomotion.Gait.WAIT:
		return
	var pos_gx: Vector3 = TownSpace.world_to_gx(global_position)
	var dir: AcreWade.Dir = AcreWade.direction(
		pos_gx,
		_motor.facing,
		Vector2(input_dir.x, -input_dir.y),
		func(d: AcreWade.Dir) -> bool: return _can_land(pos_gx, d, bg)
	)
	if dir != AcreWade.Dir.NONE:
		_begin_wade(pos_gx, dir)


## `mCoBG_ScrollCheck` toward 18 GX past the border (walls, water, FG solids), plus — outside
## the title demo — no villager within 36 GX of it.
func _can_land(pos_gx: Vector3, dir: AcreWade.Dir, bg: Array) -> bool:
	var data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	var probe: Vector3 = TownSpace.gx_to_world(AcreWade.landing_probe(pos_gx, dir))
	probe.y = global_position.y
	var reached: Vector3 = FieldCollision.revise_xz(data, grid, global_position, probe)
	if Vector2(reached.x - probe.x, reached.z - probe.z).length() > 0.05:
		return false
	if grid.is_occupied(grid.world_to_cell(probe)):
		return false
	if scripted_input == null:
		var clear: float = AcreWade.NPC_CLEAR_GX * FieldCatalog.GX_TO_METERS
		for npc: Node in get_tree().get_nodes_in_group("villagers"):
			if npc is Node3D and (npc as Node3D).global_position.distance_to(probe) < clear:
				return false
	return true


func _begin_wade(pos_gx: Vector3, dir: AcreWade.Dir) -> void:
	var end: Vector3 = TownSpace.gx_to_world(AcreWade.end_pos(pos_gx, dir))
	end.y = global_position.y
	_wade = {"start": global_position, "end": end, "t": 0.0, "dir": dir}
	## `Player_actor_Movement_Base_Stop` + `mPlayer_ANIM_WAIT1`.
	_motor.planar_speed = 0.0
	velocity = Vector3.ZERO
	play_wait_idle()
	_gait = PlayerLocomotion.Gait.WAIT


## `Player_actor_main_Wade`: carried across on `get_percent_forAccelBrake`, stick ignored.
func _tick_wade(delta: float) -> void:
	velocity = Vector3.ZERO
	## A pressed during the wade is never read (`Player_actor_Request_Wade` takes no input).
	if scripted_input != null:
		scripted_input.consume_a_pressed()
	var t: float = float(_wade["t"]) + delta * AcreWade.TICK_HZ
	_wade["t"] = t
	var start: Vector3 = _wade["start"]
	var end: Vector3 = _wade["end"]
	var p: float = AcreWade.percent(minf(t, AcreWade.TICKS))
	global_position = Vector3(
		lerpf(start.x, end.x, p), global_position.y, lerpf(start.z, end.z, p)
	)
	_snap_to_bg()
	_mesh.rotation.y = _motor.facing
	if t > AcreWade.TICKS:
		_wade = {}


## `{start, end, t}` while wading (for the camera), else empty.
func wade_state() -> Dictionary:
	return _wade


## `aMR_ManageMoveBottun`: A against a piece in your own house grips it. Anything else —
## nothing there, a piece in the pockets to place, another room — falls through to the normal verb.
func _try_grip() -> bool:
	if _busy or _gripping or _door_entering or not Game.is_decorating() or Game.held_furniture() != null:
		return false
	var session: IndoorSession = Game.interior_session
	if session == null:
		return false
	var contact: Dictionary = _grip.press(
		session, global_position, WorldGrid.facing_from_player_yaw(_motor.facing)
	)
	if contact.is_empty():
		return false
	_gripping = true
	_busy = true
	_grip_move = {}
	_grip_nice = contact["nice_pos"] as Vector3
	_motor.reset(WorldGrid.yaw_for_furniture(_grip.facing))
	_mesh.rotation.y = _motor.facing
	_play_grip_clip(ANIM_HOLD_WAIT1, true)
	return true


func _grip_stick() -> Vector2:
	if _menu_open():
		return Vector2.ZERO
	var input_dir: Vector2 = _read_stick()
	var wish: Vector3 = _camera_wish(input_dir)
	return Vector2(wish.x, wish.z) * clampf(input_dir.length(), 0.0, 1.0)


func _tick_grip(delta: float) -> void:
	if Game.interior_session == null:
		_end_grip()
		return
	var held: bool = Input.is_action_pressed("interact") and not _menu_open()
	var events: Array[Dictionary] = _grip.advance(
		delta, Game.interior_session, held, _grip_stick(), global_position
	)
	if not _grip_move.is_empty():
		_advance_grip_move(delta)
	elif _gripping:
		var pos: Vector3 = global_position
		global_position = pos.lerp(Vector3(_grip_nice.x, pos.y, _grip_nice.z), clampf(delta * GRIP_SETTLE_RATE, 0.0, 1.0))
	for event: Dictionary in events:
		if not _gripping:
			break
		_on_grip_event(event)
	velocity = Vector3.ZERO


func _on_grip_event(event: Dictionary) -> void:
	match str(event.get("op", "")):
		"tap":
			var side: int = int(event.get("side", -1))
			var tapped_id: StringName = event.get("id", &"") as StringName
			_end_grip()
			_tap_furniture(tapped_id, side)
		"release":
			_end_grip()
		"move":
			_notify_moved(event)
			var pushing: bool = event.get("kind") == &"push"
			_grip_move = {
				"t": 0.0,
				"dur": FURNITURE_MOVE_SEC,
				"from": event["player_from"] as Vector3,
				"to": event["player_to"] as Vector3,
			}
			_grip_nice = event["player_to"] as Vector3
			_play_grip_clip(ANIM_PUSH1 if pushing else ANIM_PULL1, false)
			_sync_furniture(FURNITURE_MOVE_SEC)
		"rotate":
			_notify_moved(event)
			_grip_move = {"t": 0.0, "dur": FURNITURE_TURN_SEC, "from": global_position, "to": global_position}
			_play_grip_clip(ANIM_LTURN1 if bool(event.get("ccw", true)) else ANIM_RTURN1, false)
			_sync_furniture(FURNITURE_TURN_SEC)
		"bubu":
			## `aMR_SetBubu`: the puff of a piece that will not budge. Just the held pose for now.
			pass


func _notify_moved(event: Dictionary) -> void:
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() != null else null
	if host != null and host.has_method("on_furniture_moved"):
		host.call("on_furniture_moved", event.get("vacated", []))


## `mPlayer_INDEX_SHOCK` (`aMR_RequestPlayerBikkuri`): the first roach of the session makes the
## player jump — a beat, then `gaaan1`, facing north.
func request_surprise() -> void:
	if _busy:
		await get_tree().create_timer(0.3).timeout
	_busy = true
	var yaw: float = WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
	_motor.reset(yaw)
	_mesh.rotation.y = yaw
	await get_tree().create_timer(20.0 / 60.0).timeout
	_play_grip_clip("ply_1_gaaan1", false)
	await get_tree().create_timer(44.0 / 60.0).timeout
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	play_wait_idle()


func _advance_grip_move(delta: float) -> void:
	var dur: float = maxf(float(_grip_move["dur"]), 0.001)
	var t: float = minf(float(_grip_move["t"]) + delta, dur)
	_grip_move["t"] = t
	var k: float = smoothstep(0.0, 1.0, t / dur)
	var from: Vector3 = _grip_move["from"] as Vector3
	var to: Vector3 = _grip_move["to"] as Vector3
	global_position = Vector3(lerpf(from.x, to.x, k), global_position.y, lerpf(from.z, to.z, k))
	if t >= dur:
		_grip_move = {}
		_grip.finish_busy()
		_play_grip_clip(ANIM_HOLD_WAIT1, true)


func _sync_furniture(duration: float) -> void:
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() != null else null
	if host != null and host.has_method("sync_placements"):
		host.call("sync_placements", duration)


func _end_grip() -> void:
	_gripping = false
	_grip_move = {}
	_grip.reset()
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	play_wait_idle()


## A short A on a gripped piece is the ordinary use verb (open, switch, put a fish on it).
func _tap_furniture(placement_id: StringName, side: int) -> void:
	var interior: Node = get_tree().get_first_node_in_group("interior") if get_tree() != null else null
	var host: Node = interior.call("furniture_node", placement_id) if interior != null else null
	if host == null or not InteractionQuery.is_host(host):
		return
	var ctx: InteractionContext = _make_context()
	ctx.contact_side = side
	var offered: Array[Interaction] = []
	var raw: Variant = host.get_interactions(ctx)
	if raw is Array:
		offered.assign(raw)
	var action: Interaction = Interaction.primary(offered)
	if action == null:
		return
	var tapped := InteractionQuery.new()
	tapped.host = host
	tapped.action = action
	await _run_interact(tapped)


func _play_grip_clip(leaf: String, loop: bool) -> void:
	if _anim == null:
		return
	var clip: String = _resolve_clip(leaf)
	if clip.is_empty():
		return
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.12)


## `aMR_SitDownFurniture` / `aMR_JudgeGoToBed`: walking straight into a chair or a bed.
func _poll_rest(delta: float) -> void:
	if _menu_open() or Game.interior_session == null or not Game.is_indoors():
		_seat.reset()
		return
	var hit: Dictionary = _seat.poll(
		delta,
		Game.interior_session,
		global_position,
		WorldGrid.facing_from_player_yaw(_motor.facing),
		_grip_stick()
	)
	if not hit.is_empty():
		_begin_rest(hit)


func _begin_rest(hit: Dictionary) -> void:
	var lying: bool = int(hit["kind"]) == FurnitureSeat.Rest.LIE
	var leaf: String = ANIM_SITDOWN1
	if lying:
		leaf = ANIM_INBED_L1 if bool(hit.get("from_left", true)) else ANIM_INBED_R1
	_rest = hit.duplicate()
	_rest["phase"] = &"in"
	_rest["t"] = 0.0
	_rest["dur"] = _clip_seconds(leaf, 0.8)
	_rest["from"] = global_position
	_rest["to"] = hit["pos"] as Vector3
	_busy = true
	var yaw: float = WorldGrid.yaw_for_furniture(hit["yaw_facing"] as WorldGrid.Facing)
	_motor.reset(yaw)
	_mesh.rotation.y = yaw
	_play_grip_clip(leaf, false)
	PlayerSe.schedule_clip(self, StringName(leaf))


func _tick_rest(delta: float) -> void:
	velocity = Vector3.ZERO
	var lying: bool = int(_rest["kind"]) == FurnitureSeat.Rest.LIE
	var phase: StringName = _rest["phase"] as StringName
	if phase == &"wait":
		if _grip_stick().length() > REST_STAND_STICK:
			_begin_stand(lying)
		return
	var t: float = minf(float(_rest["t"]) + delta, float(_rest["dur"]))
	_rest["t"] = t
	var k: float = smoothstep(0.0, 1.0, t / maxf(float(_rest["dur"]), 0.001))
	var from: Vector3 = _rest["from"] as Vector3
	var to: Vector3 = _rest["to"] as Vector3
	global_position = Vector3(lerpf(from.x, to.x, k), global_position.y, lerpf(from.z, to.z, k))
	if t < float(_rest["dur"]):
		return
	if phase == &"in":
		_rest["phase"] = &"wait"
		_play_grip_clip(ANIM_BED_WAIT1 if lying else ANIM_SITDOWN_WAIT1, true)
	else:
		_end_rest()


func _begin_stand(lying: bool) -> void:
	var session: IndoorSession = Game.interior_session
	if session == null:
		_end_rest()
		return
	var seat_pos: Vector3 = _rest["pos"] as Vector3
	var spot: Dictionary
	if lying:
		spot = FurnitureSeat.bed_exit_spot(session, _rest["approach"] as Vector3)
	else:
		spot = FurnitureSeat.stand_spot(session, seat_pos, _rest["yaw_facing"] as WorldGrid.Facing)
	if spot.is_empty():
		return
	var leaf: String = ANIM_STANDUP1
	if lying:
		leaf = ANIM_OUTBED_L1 if bool(_rest.get("from_left", true)) else ANIM_OUTBED_R1
	_rest["phase"] = &"out"
	_rest["t"] = 0.0
	_rest["dur"] = _clip_seconds(leaf, 0.8)
	_rest["from"] = global_position
	_rest["to"] = spot["pos"] as Vector3
	_play_grip_clip(leaf, false)


func _end_rest() -> void:
	_rest = {}
	_seat.reset()
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	play_wait_idle()


func _clip_seconds(leaf: String, fallback: float) -> float:
	var clip: String = _resolve_clip(leaf)
	if _anim == null or clip.is_empty():
		return fallback
	var animation: Animation = _anim.get_animation(clip)
	return animation.length if animation != null and animation.length > 0.0 else fallback


## Shut the dresser / wardrobe / closet again once the last message has closed.
func play_storage_close(storage_type: int) -> void:
	var leaf: StringName = FurnitureStorage.CLOSE_CLIPS.get(storage_type, &"") as StringName
	if leaf == &"" or _anim == null:
		return
	var clip: String = _resolve_clip(String(leaf))
	if clip.is_empty():
		return
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)
	PlayerSe.schedule_clip(self, leaf)
	await _anim.animation_finished


## `Player_actor_CheckAndRequest_main_pickup_all`: B facing a piece in your own house picks it up.
func _poll_furniture_pickup() -> void:
	if not Input.is_action_just_pressed("sprint") or _menu_open() or _door_entering:
		return
	if not Game.is_decorating() or Game.interior_session == null:
		return
	var id: StringName = FurnitureGrip.find_pickup(
		Game.interior_session, global_position, WorldGrid.facing_from_player_yaw(_motor.facing)
	)
	if id == &"":
		return
	_busy = true
	var tail: float = await _play_action(&"ply_1_pickup1", 20.0)
	Game.pick_up_furniture(id)
	await _finish_action(tail)
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT


## `Player_actor_check_little_shake_tree`: walking up to a tree shakes it a little.
func _tick_tree_bump(delta: float) -> void:
	var bg: Array = _bg()
	if bg.size() != 2:
		return
	var here: Vector3 = global_position
	var reach_sq: float = pow((bg[1] as WorldGrid).cell_size * 3.0, 2.0)
	var trees: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("plant"):
		var tree_node := node as Node3D
		if tree_node == null or not tree_node.has_method("can_bump"):
			continue
		if tree_node.global_position.distance_squared_to(here) > reach_sq:
			continue
		if bool(tree_node.call("can_bump")):
			trees.append(tree_node)
	var hit: Node3D = _tree_bump.tick(
		delta, here, _motor.facing, bg[0] as WorldData, bg[1] as WorldGrid, trees
	)
	if hit != null:
		hit.call("bump")


## `mPlib_Check_tree_shaken`: cells of trees being shaken right now.
func shaken_tree_cells() -> Array[Vector2i]:
	return _tree_bump.active_cells()


## The button shake (`Player_actor_Set_shake_tree_table`) claims the tree in the same table.
func note_big_tree_shake(cell: Vector2i) -> void:
	_tree_bump.note_big_shake(cell)


## `Player_actor_Movement_Talk`: ease toward the NPC on a fixed 60 Hz tick.
func _tick_talk_face(delta: float) -> void:
	if not is_talk_facing():
		return
	_talk_turn_debt += delta
	var step: float = 1.0 / TalkCamera.TURN_HZ
	while _talk_turn_debt >= step:
		_talk_turn_debt -= step
		var target: float = TalkCamera.face_yaw_toward(global_position, _talk_face.global_position)
		_motor.facing = MLib.short_angle2(
			_motor.facing,
			target,
			TalkCamera.TURN_FRACTION,
			TalkCamera.TURN_MAX_STEP,
			TalkCamera.TURN_MIN_STEP
		)


## After a room load, walk-in doors stay armed until the probe leaves every auto door.
func _clear_auto_enter_block() -> void:
	if not Game.block_auto_enter_doors:
		return
	## Keep blocked while still on an indoor EXIT_DOOR strip after a room load.
	if _on_indoor_exit_cell():
		return
	var hit: InteractionQuery = _resolve_interact()
	if hit == null or hit.host == null:
		Game.block_auto_enter_doors = false
		return
	if hit.host.get("auto_enter") != true:
		Game.block_auto_enter_doors = false


func _on_indoor_exit_cell() -> bool:
	if not Game.is_indoors():
		return false
	var session: IndoorSession = Game.interior_session
	if session == null or session.room == null or session.grid == null:
		return false
	if session.room.kind == Room.Kind.MUSEUM:
		return false
	return session.room.is_exit_cell(session.grid.world_to_cell(global_position))


## `mPlayer_INDEX_DOOR`: OPEN1 / INTO_S1 with `cKF_SkeletonInfo_R_AnimationMove_base`.
## World XZ = door stand + decaying (start−stand) + scaled joint_0 delta; mesh root stays bind.
func begin_door_enter(target: Vector3, face_yaw: float, walk_in: bool = false) -> void:
	var leaf := ANIM_INTO_S1 if walk_in else ANIM_OPEN1
	_begin_animation_move(
		target,
		face_yaw,
		leaf,
		StructureDoor.ANIM_MOVE_COUNTER,
		StructureDoor.INTO_SEC if walk_in else StructureDoor.OPEN1_SEC,
	)


## `mPlayer_INDEX_DEMO_GETOFF_TRAIN`: OUTTRAIN1 with AnimationMove. Decomp passes the
## current ride pose as correctpos — root motion alone steps onto the platform.
func begin_demo_getoff_train(stand: Vector3, face_yaw: float) -> void:
	_begin_animation_move(
		stand,
		face_yaw,
		ANIM_OUTTRAIN1,
		StructureDoor.ANIM_MOVE_COUNTER_GETOFF,
		StructureDoor.OUTTRAIN_SEC,
	)


## Walk to `goal` at `speed` (m/s), stopping within `arrive` (m); repeat calls move the goal
## (`mPlib_Set_goal_player_demo_walk`). Held until `end_demo_walk`.
func begin_demo_walk(goal: Vector3, speed: float, arrive: float) -> void:
	_demo_walk_goal = goal
	_demo_walk_speed = maxf(speed, 0.0)
	_demo_walk_arrive = maxf(arrive, 0.0)


func end_demo_walk() -> void:
	_demo_walk_speed = 0.0


func is_demo_walking() -> bool:
	return _demo_walk_speed > 0.0


func is_door_entering() -> bool:
	return _door_entering


func _begin_animation_move(
	target: Vector3,
	face_yaw: float,
	clip_leaf: String,
	counter: float,
	duration: float,
) -> void:
	_door_entering = true
	_door_animation_move = true
	_door_clear_busy = false
	_door_from = global_position
	_door_to = Vector3(target.x, global_position.y, target.z)
	_door_correction = Vector3(_door_from.x - _door_to.x, 0.0, _door_from.z - _door_to.z)
	_door_fixed_counter = counter
	_door_frame_accum = 0.0
	_door_yaw = face_yaw
	_door_move_elapsed = 0.0
	_door_move_duration = duration
	_motor.reset(face_yaw)
	_mesh.rotation.y = face_yaw
	velocity = Vector3.ZERO
	var clip := _resolve_clip(clip_leaf)
	_door_root_clip = clip_leaf if _door_root_xz.has(clip_leaf) else ""
	if _anim == null or clip.is_empty():
		return
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)


func end_door_enter() -> void:
	## A failed enter (`Game.try_enter_interior`) stays outdoors — the tool comes back out.
	if _tool_stowed and not Game.is_indoors():
		take_out_tool()
	_door_entering = false
	_door_animation_move = false
	_door_root_clip = ""


func await_door_enter() -> void:
	## Used when the structure has no door cKF (museum / police). Wait out INTO_S1 / OPEN1.
	if _anim != null and _anim.is_playing():
		await _anim.animation_finished
	elif get_tree() != null:
		await get_tree().create_timer(maxf(_door_move_duration, StructureDoor.INTO_SEC)).timeout


## `mPlayer_INDEX_OUTDOOR`: actor stays on the exit stand; GO_OUT `joint_0` walks the mesh
## from behind to bind (`Set_force_shadow_position_fromAnimePosition` only).
func begin_door_leave(stand: Vector3, _target: Vector3, face_yaw: float, full_walk: bool = false) -> void:
	_busy = true
	_door_entering = true
	_door_animation_move = false
	_door_clear_busy = true
	global_position = Vector3(stand.x, global_position.y, stand.z)
	_door_from = global_position
	_door_to = global_position
	_door_correction = Vector3.ZERO
	_door_yaw = face_yaw
	_door_move_elapsed = 0.0
	_door_move_duration = StructureDoor.LEAVE_SEC
	_door_root_clip = ""
	_motor.reset(face_yaw)
	_mesh.rotation.y = face_yaw
	velocity = Vector3.ZERO
	var clip := _resolve_clip(ANIM_GO_OUT_O1)
	if _anim == null or clip.is_empty():
		return
	_anim.speed_scale = 1.0
	## No morph (`InitAnimation_Base2` morph 0.0) so the first shown frame is the clip's own.
	_anim.play(clip, 0.0)
	if not full_walk:
		_anim.seek(GO_OUT_O1_DOOR_ONLY_START_SEC, true)
	## Pose the first frame now so un-hiding the model never shows the idle pose.
	_anim.advance(0.0)
	visible = true


func end_door_leave() -> void:
	_door_entering = false
	_door_animation_move = false
	if _door_clear_busy:
		_busy = false
	_door_clear_busy = false


## Indoor `EXIT_DOOR`: INTO_S1 while walking south through the exit cell.
func run_indoor_exit(target: Vector3, face_yaw: float) -> void:
	_busy = true
	_door_clear_busy = true
	begin_door_enter(target, face_yaw, true)
	_door_clear_busy = true
	if _anim != null and _anim.is_playing():
		await _anim.animation_finished
	else:
		await get_tree().create_timer(_door_move_duration).timeout
	end_door_leave()


func _tick_door_enter(delta: float) -> void:
	_door_move_elapsed += delta
	_motor.reset(_door_yaw)
	_mesh.rotation.y = _door_yaw
	velocity = Vector3.ZERO
	if _door_animation_move:
		## `AnimationMove_base` runs once per 60 Hz game frame (`fixed_counter` −= 0.5).
		_door_frame_accum += delta * StructureDoor.ANIM_MOVE_HZ
		while _door_frame_accum >= 1.0:
			_door_frame_accum -= 1.0
			_decay_door_correction()
		var root: Vector3 = _sample_door_root_xz()
		var world_root := Vector3(
			root.x * cos(_door_yaw) + root.z * sin(_door_yaw),
			0.0,
			-root.x * sin(_door_yaw) + root.z * cos(_door_yaw),
		)
		global_position = Vector3(
			_door_to.x + _door_correction.x + world_root.x,
			global_position.y,
			_door_to.z + _door_correction.z + world_root.z,
		)
	_snap_to_bg()


func _decay_door_correction() -> void:
	## Mirror `cKF_SkeletonInfo_R_AnimationMove_base` XZ correction decay.
	var fc: float = _door_fixed_counter
	var count: float = 1.0 + fc
	if count > 0.5:
		var w: float = 0.5 / count
		_door_correction.x -= _door_correction.x * w
		_door_correction.z -= _door_correction.z * w
	else:
		_door_correction = Vector3.ZERO
	_door_fixed_counter = maxf(fc - 0.5, 0.0)


func _sample_door_root_xz() -> Vector3:
	if _door_root_clip.is_empty() or not _door_root_xz.has(_door_root_clip):
		return Vector3.ZERO
	var root_anim: Animation = _door_root_xz[_door_root_clip] as Animation
	if root_anim == null or root_anim.get_track_count() < 1:
		return Vector3.ZERO
	var t: float = 0.0
	if _anim != null:
		t = clampf(_anim.current_animation_position, 0.0, root_anim.length)
	return root_anim.position_track_interpolate(0, t)


func _bg() -> Array:
	if get_tree() == null:
		return []
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return []
	var data: Variant = world.get("layout")
	var grid: Variant = world.get("grid")
	if not (data is WorldData) or not (grid is WorldGrid):
		return []
	return [data, grid]


func _snap_to_bg() -> bool:
	## `mCoBG_BgCheckControll` / `GetBgY_AngleS_FromWpos`: feet on the heightfield at this XZ.
	## Door walks keep acre `keep_h` — structure plus-offsets are walls, not a raised path.
	var bg: Array = _bg()
	if bg.is_empty():
		return false
	var y: float = FieldCollision.ground_y_at(
		bg[0] as WorldData, bg[1] as WorldGrid, global_position, 0.0, not _door_entering
	)
	if not FieldCollision.has_floor(y):
		return false
	floor_snap_length = 0.0
	floor_block_on_wall = false
	global_position.y = y
	return true


func _menu_open() -> bool:
	return (
		_group_open("inventory_ui")
		or _group_open("map_ui")
		or _group_open("dialogue_ui")
		or _group_open("shop_ui")
		or _group_open("debug_console_ui")
		or _group_open("design_ui")
		or _group_open("design_list_ui")
		or _group_open("name_entry_ui")
	)


func _group_open(group: String) -> bool:
	if get_tree() == null:
		return false
	var ui: Node = get_tree().get_first_node_in_group(group)
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func _unhandled_input(event: InputEvent) -> void:
	if scripted_input != null or _busy or _menu_open() or is_demo_walking():
		return
	if event.is_action_pressed("interact"):
		if _try_grip():
			get_viewport().set_input_as_handled()
			return
		_try_interact()
		get_viewport().set_input_as_handled()


func _camera_wish(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var look := Vector3.FORWARD
	var right := Vector3.RIGHT
	if cam != null:
		look = -cam.global_transform.basis.z
		look.y = 0.0
		if look.length_squared() > 0.0001:
			look = look.normalized()
		right = cam.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()
	var wish := look * -input_dir.y + right * input_dir.x
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	return wish


## `mCon_calc`: raw stick (no Godot dead-zone remap) → `move_pR` direction × percent.
## Below `STICK_MIN` it reads zero; above, the percent is the raw radius — not rescaled
## from the dead zone, so the smallest registered tilt already walks at ~16 %.
func _read_stick() -> Vector2:
	var raw: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0)
	var pr: float = PlayerLocomotion.stick_percent(raw.length())
	if pr <= 0.0:
		return Vector2.ZERO
	return raw.normalized() * pr


## `mCon_calc` `move_pX` / `move_pY`: zeroed per axis inside the dead zone.
func _axes_active(stick_vec: Vector2) -> bool:
	if stick_vec == Vector2.ZERO:
		return false
	var raw: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0)
	return (
		PlayerLocomotion.axis_percent(raw.x) != 0.0 or PlayerLocomotion.axis_percent(raw.y) != 0.0
	)


## `Player_actor_Check_FlatPlace` probe: the unit's normal is vertical.
func _motor_unit_flat(pos: Vector3) -> bool:
	var bg: Array = _bg()
	if bg.size() != 2:
		return false
	var grid := bg[1] as WorldGrid
	var cell: Vector2i = grid.world_to_cell(pos)
	if not grid.is_in_bounds(cell):
		return false
	return FieldCollision.unit_is_flat(bg[0] as WorldData, cell)


## Tumble / get-up transitions wait on the clip (`CulcAnimation` end), like the original.
func _feed_clip_state() -> void:
	if _anim == null:
		_motor.clip_done = true
		return
	var mode: PlayerLocomotion.Gait = _motor.gait()
	if mode != PlayerLocomotion.Gait.TUMBLE and mode != PlayerLocomotion.Gait.TUMBLE_GETUP:
		return
	if _motor.mode_changed or _gait != mode:
		_motor.clip_frame = 0.0
		_motor.clip_done = false
		return
	var frame: float = _anim.current_animation_position * ANIM_FPS
	_motor.clip_done = not _anim.is_playing()
	if mode == PlayerLocomotion.Gait.TUMBLE:
		_tumble_events(_motor.clip_frame, frame)
	_motor.clip_frame = frame


## `Player_actor_SetEffect_Tumble`: rumble at frame 10, landing dust at 15, body print at 17.
func _tumble_events(before: float, now: float) -> void:
	var bg: Array = _bg()
	var attr: int = _unit_attr(bg)
	if before < 10.0 and now >= 10.0:
		Input.start_joy_vibration(0, 0.6, 1.0, 17.0 / 60.0)
	if before < 15.0 and now >= 15.0:
		StepFx.tumble(bg, global_position, _motor.facing, attr, 1)
	if before < 17.0 and now >= 17.0:
		StepFx.body_print(bg, global_position, _motor.facing, attr)


func _unit_attr(bg: Array) -> int:
	if bg.size() != 2:
		return -1
	return FieldCollision.unit_attr_at(bg[0] as WorldData, bg[1] as WorldGrid, global_position)


## `mCoBG_GetBgNorm_FromWpos` stand-in for the motor's uphill speed normalise.
func _motor_ground_y(pos: Vector3) -> float:
	var bg: Array = _bg()
	if bg.size() != 2:
		return FieldCollision.NO_FLOOR
	return FieldCollision.ground_y_at(bg[0] as WorldData, bg[1] as WorldGrid, pos)


## `bg_collision_check.result.hit_wall`: how much of this frame's step the walls let
## through. `Player_actor_CulcAnimation_Walk` slows the clip by √ of it next frame.
func _note_wall_contact(before: Vector3, planar: Vector3, delta: float) -> void:
	var intended: float = Vector2(planar.x, planar.z).length() * delta
	if intended <= 0.0005:
		_motor.wall_ratio = 1.0
		return
	var moved: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var ratio: float = clampf(moved / intended, 0.0, 1.0)
	_motor.wall_ratio = 1.0 if ratio > 0.98 else ratio


func _update_animation(delta: float) -> void:
	if _tool_swap:
		return
	var next: PlayerLocomotion.Gait = _motor.gait()
	if _anim == null:
		_placeholder_bob += delta * (8.0 if next != PlayerLocomotion.Gait.WAIT else 2.0)
		if _placeholder.visible:
			var amp: float = 0.04 if next != PlayerLocomotion.Gait.WAIT else 0.0
			_placeholder.position.y = 0.625 + sin(_placeholder_bob) * amp
		return
	if _busy:
		## After door emerge / while dialogue locks input, keep wait looping —
		## otherwise we freeze on the last GO_OUT frame.
		if not _door_entering and not _cutscene_driven and not _anim.is_playing():
			play_wait_idle()
		return
	var one_shot: bool = next in [
		PlayerLocomotion.Gait.TURN_DASH, PlayerLocomotion.Gait.TUMBLE, PlayerLocomotion.Gait.TUMBLE_GETUP
	]
	if next == _gait and not _motor.mode_changed and (_anim.is_playing() or one_shot):
		_anim.speed_scale = _anim_speed(next)
		return
	_motor.mode_changed = false
	var prev: PlayerLocomotion.Gait = _gait
	_gait = next
	var clip := _resolve_clip(_clip_for(next))
	if clip.is_empty():
		return
	_on_mode_entered(prev, next)
	if one_shot:
		var once: Animation = _anim.get_animation(clip)
		if once != null:
			once.loop_mode = Animation.LOOP_NONE
	else:
		_ensure_loop(clip)
	## Walk ↔ run ↔ dash keep the current keyframe (`frame = current_frame`); wait → walk
	## and every other start restart at frame 1.
	var gaits: Array = [
		PlayerLocomotion.Gait.WALK, PlayerLocomotion.Gait.RUN, PlayerLocomotion.Gait.DASH
	]
	var carry: bool = prev in gaits and next in gaits and _anim.is_playing()
	var phase: float = _anim.current_animation_position if carry else 0.0
	var blend: float = MORPH_12 if prev == PlayerLocomotion.Gait.TURN_DASH else MORPH_5
	_anim.speed_scale = _anim_speed(next)
	_anim.play(clip, blend)
	if carry:
		var length: float = _anim.get_animation(clip).length
		_anim.seek(fmod(phase, maxf(length, 0.001)), true)


## Mode entry side effects: skid SE + `TURN_ASIMOTO`, tumble SE + `TUMBLE` (arg 0), and the
## skid's `TURN_FOOTPRINT` at the right foot when it settles into wait.
func _on_mode_entered(prev: PlayerLocomotion.Gait, next: PlayerLocomotion.Gait) -> void:
	var bg: Array = _bg()
	var attr: int = _unit_attr(bg)
	match next:
		PlayerLocomotion.Gait.TURN_DASH:
			Audio.play_se(SE_SLIP, self)
			StepFx.turn(bg, global_position, _motor.facing, attr, 0)
		PlayerLocomotion.Gait.TUMBLE:
			Audio.play_se(_tumble_se(attr), self)
			StepFx.tumble(bg, global_position, _motor.facing, attr, 0)
	if prev == PlayerLocomotion.Gait.TURN_DASH:
		var foot: Transform3D = _foot_anchor(true)
		var at: Vector3 = foot.origin if foot.basis.determinant() != 0.0 else global_position
		StepFx.turn_footprint(bg, at, _motor.facing, attr)


## `sAdo_Get_KokeruLabel`: the footstep label for the unit, as its tumble twin.
func _tumble_se(attr: int) -> StringName:
	if Game.is_indoors():
		return &"tumble_wood"
	var bg: Array = _bg()
	var step: StringName
	if attr >= 0:
		step = FootstepSe.id_for_attr(attr, Clock.season())
	elif bg.size() == 2:
		var data := bg[0] as WorldData
		step = FootstepSe.id_for_terrain(
			data.terrain_at((bg[1] as WorldGrid).world_to_cell(global_position)), Clock.season()
		)
	else:
		step = &"footstep_soil"
	var tumble := StringName(String(step).replace("footstep_", "tumble_"))
	return tumble if SeCatalog.stream_for(tumble) != null else &"tumble_soil"


func _update_footprints(delta: float, bg: Array) -> void:
	## `Player_actor_Set_FootMark_MarkOnly` + `Player_actor_sound_FootStep2`: one print and
	## footstep SE per foot on the gait cadence. Clips lack frame tags, so period comes
	## from clip rate — same time between steps, tracks still spread as gait speeds up.
	## SE fires even when the surface cannot hold a mark (stone / soil / wood / indoors).
	var gait: PlayerLocomotion.Gait = _motor.gait()
	if (
		bg.size() != 2
		or _busy
		or gait == PlayerLocomotion.Gait.WAIT
		or gait == PlayerLocomotion.Gait.TURN_DASH
		or gait == PlayerLocomotion.Gait.TUMBLE
		or gait == PlayerLocomotion.Gait.TUMBLE_GETUP
	):
		_step_time = 0.0
		return
	_step_time += delta
	var period: float = FootprintMarks.step_period(_anim_speed(gait))
	if _step_time < period:
		return
	_step_time -= period
	_right_foot = not _right_foot
	var data := bg[0] as WorldData
	var grid := bg[1] as WorldGrid
	var season: Clock.Season = Clock.season()
	var attr: int = FieldCollision.unit_attr_at(data, grid, global_position)
	var terrain: WorldGrid.Terrain = data.terrain_at(grid.world_to_cell(global_position))
	var indoors: bool = Game.is_indoors()
	FootstepSe.play_at(self, attr, terrain, season, gait, indoors)
	if indoors:
		return
	var foot: Vector3
	var yaw: float
	var anchor: Transform3D = _foot_anchor(_right_foot)
	if anchor.basis.determinant() != 0.0:
		foot = anchor.origin
		yaw = anchor.basis.get_euler().y
	else:
		yaw = _motor.facing
		foot = FootprintMarks.foot_position(global_position, yaw, _right_foot)
	_step_effects(gait, bg, attr, foot, yaw)
	var marks: Node = get_tree().get_first_node_in_group("footprints")
	if marks == null or not marks.has_method("spawn"):
		return
	var snow: bool
	if attr >= 0:
		if not FootprintMarks.marks_attr(attr, season):
			return
		snow = FootprintMarks.is_snow_mark(attr)
	else:
		if not FootprintMarks.marks_terrain(terrain, season):
			return
		snow = terrain != WorldGrid.Terrain.SAND
	var xform: Transform3D = FootprintMarks.mark_transform(data, grid, foot, yaw)
	if xform.basis.determinant() == 0.0:
		return
	marks.call("spawn", xform, snow)


## `Player_actor_SetEffect_Walk` / `_Dash`: `WALK_ASIMOTO` on walk + run foot plants,
## `DASH_ASIMOTO` on dash ones — unless 1 in 4 dash plants on a flower tramples it
## (`SetEffectRemoveFlower_Dash` → `HANATIRI` instead).
func _step_effects(gait: PlayerLocomotion.Gait, bg: Array, attr: int, foot: Vector3, yaw: float) -> void:
	if gait == PlayerLocomotion.Gait.DASH:
		var grid := bg[1] as WorldGrid
		if randi() % 4 == 0:
			var cell: Vector2i = grid.world_to_cell(global_position)
			var flower: int = StepFx.flower_index(global_position)
			var world: Node = get_tree().get_first_node_in_group("world")
			if PlantGrowth.trample_flower(world, grid, cell):
				## `mFI_Wpos2UtCenterWpos`: petals burst from the unit centre.
				var center: Vector3 = grid.cell_corner(cell) + Vector3(grid.cell_size, 0.0, grid.cell_size) * 0.5
				center.y = global_position.y
				StepFx.hanatiri(bg, center, flower)
				return
		StepFx.dash_step(bg, foot, yaw, attr)
	else:
		StepFx.walk_step(bg, foot, yaw, attr)


func _foot_anchor(right_foot: bool) -> Transform3D:
	## `Player_actor_draw_After_Lfoot3` / `_Rfoot3` call `Matrix_Position_Zero` on the
	## `LFOOT3` / `RFOOT3` joint, so the mark sits at the foot joint's own origin and takes
	## that joint's yaw — no lateral offset and no body facing involved. Tracks therefore
	## follow the animated feet, and each print is turned the way the foot is.
	## A zero basis means the visual has no rig; the caller falls back to a fixed stance.
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	if skeleton == null:
		return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var want: String = "rfoot3" if right_foot else "lfoot3"
	for i: int in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).to_lower().begins_with(want):
			return skeleton.global_transform * skeleton.get_bone_global_pose(i)
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)


func _anim_speed(gait: PlayerLocomotion.Gait) -> float:
	## Walk / run / dash: `0.6·√(speed / 7.5)` keyframes per 1/60 s (floor 0.22, wall
	## contact slows it) over the clip's native 0.5. Wait and the skid play at 0.5.
	match gait:
		PlayerLocomotion.Gait.WALK, PlayerLocomotion.Gait.RUN, PlayerLocomotion.Gait.DASH:
			return _motor.anim_speed_scale()
		_:
			return 1.0


func _clip_for(gait: PlayerLocomotion.Gait) -> String:
	match gait:
		PlayerLocomotion.Gait.WALK:
			return ANIM_WALK
		PlayerLocomotion.Gait.RUN:
			return ANIM_RUN
		PlayerLocomotion.Gait.DASH:
			return ANIM_DASH
		PlayerLocomotion.Gait.TURN_DASH:
			return ANIM_RUN_SLIP
		PlayerLocomotion.Gait.TUMBLE:
			return _tumble_clip(false)
		PlayerLocomotion.Gait.TUMBLE_GETUP:
			return _tumble_clip(true)
		_:
			## The carried item's pose rides on the arms (`ToolCarry`), not a whole-body clip.
			return ANIM_WAIT


## `Get_PlayerAnimeIndex_fromItemKind_Tumble(_getup)`: axes / shovels / fans → `_a1`;
## nets / umbrellas / rods / pinwheels → `_n1`; empty hands → plain `kokeru1`.
func _tumble_clip(getup: bool) -> String:
	var tool: ToolData = _equipped_tool()
	var kind: ToolData.Kind = tool.kind if tool != null else ToolData.Kind.NONE
	match kind:
		ToolData.Kind.AXE, ToolData.Kind.SHOVEL, ToolData.Kind.WATERING_CAN:
			return ANIM_KOKERU_GETUP_A if getup else ANIM_KOKERU_A
		ToolData.Kind.NET, ToolData.Kind.FISHING_ROD, ToolData.Kind.UMBRELLA:
			return ANIM_KOKERU_GETUP_N if getup else ANIM_KOKERU_N
		_:
			return ANIM_KOKERU_GETUP if getup else ANIM_KOKERU


func _resolve_clip(suffix: String) -> String:
	if _anim == null or suffix.is_empty():
		return ""
	if _anim.has_animation(suffix):
		return suffix
	for anim_name: String in _anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	if suffix == ANIM_DASH:
		return _resolve_clip(ANIM_RUN)
	return ""


func _update_focus() -> void:
	var hit: InteractionQuery = _resolve_interact()
	var next: Node = hit.host if hit else null
	var prompt := ""
	if hit != null and hit.action != null:
		prompt = hit.action.prompt
	if next == _focus:
		if prompt == "" and Game.is_decorating() and Game.held_furniture() != null:
			prompt = "Place %s" % Game.held_furniture().display_name
		Game.set_interact_prompt(prompt)
		return
	_focus = next
	if prompt == "" and Game.is_decorating() and Game.held_furniture() != null:
		prompt = "Place %s" % Game.held_furniture().display_name
	Game.set_interact_prompt(prompt)


func _query_focus() -> InteractionQuery:
	if _probe == null:
		return null
	return InteractionQuery.best_in_areas(
		_probe.get_overlapping_areas(),
		_motor.facing_point(global_position, INTERACT_REACH),
		_make_context()
	)


func _resolve_interact() -> InteractionQuery:
	return ToolUse.resolve(_query_focus(), _make_context())


func _make_context() -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.actor = self
	ctx.inventory = Game.inventory
	var tree := get_tree()
	if tree != null:
		ctx.world = tree.get_first_node_in_group("world")
	return ctx


## Inventory Plant after submenu close (`mTG_plant_proc` → putin scoop or throw-put).
## Item is already removed from the pocket; refunds on failure.
func plant_from_submenu(
	plant: PlantData,
	cell: Vector2i,
	use_scoop: bool,
	item: ItemData,
	condition: InventoryItem.Condition,
	success_msg: String
) -> void:
	if _busy:
		_refund_plant(item, condition)
		return
	_busy = true
	var ctx: InteractionContext = _make_context()
	if use_scoop:
		_face_cell(ctx, cell)
		var tail: float = await _play_action(
			PlantGrowth.PUTIN_SCOOP_ANIM, PlantGrowth.PUTIN_HOLE_EFFECT_FRAME
		)
		var pid: StringName = PlantGrowth.plant(ctx, plant, cell)
		if pid == &"":
			_refund_plant(item, condition)
			Game.post_notice("Can't plant here.")
		else:
			PlantGrowth.play_grow_in(PlantGrowth.host_at(ctx.world, pid))
			if success_msg != "":
				Game.post_notice(success_msg)
		await _finish_action(tail)
	else:
		## No body clip — `mTG_common_throw_put_field` / `player_drop_entry` only.
		var pid: StringName = PlantGrowth.plant(ctx, plant, cell)
		if pid == &"":
			_refund_plant(item, condition)
			Game.post_notice("Can't plant here.")
		else:
			PlantGrowth.play_grow_in(PlantGrowth.host_at(ctx.world, pid))
			if success_msg != "":
				Game.post_notice(success_msg)
			## Brief lock so grow-in is not walked through mid-scale.
			await get_tree().create_timer(PlantGrowth.GROW_IN_SEC).timeout
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	_update_focus()


func _refund_plant(item: ItemData, condition: InventoryItem.Condition) -> void:
	if item != null and Game.inventory != null:
		Game.inventory.add(item, 1, condition)


func _face_cell(ctx: InteractionContext, cell: Vector2i) -> void:
	if ctx == null or ctx.world == null:
		return
	var grid_v: Variant = ctx.world.get("grid")
	if not (grid_v is WorldGrid):
		return
	var target: Vector3 = (grid_v as WorldGrid).cell_to_world(cell)
	var yaw: float = TalkCamera.face_yaw_toward(global_position, target)
	_motor.facing = yaw
	_mesh.rotation.y = yaw


func _try_interact() -> void:
	if _motor.gait() in [PlayerLocomotion.Gait.TUMBLE, PlayerLocomotion.Gait.TUMBLE_GETUP]:
		return
	if Game.held_furniture() != null and Game.try_place_furniture(self):
		return
	var hit: InteractionQuery = _resolve_interact()
	if hit == null or hit.action == null:
		if Game.try_place_furniture(self):
			return
		return
	if scripted_input != null and not TitleDemo.allows_verb(hit.action.id):
		return
	await _run_interact(hit)


func _try_auto_enter() -> void:
	## Museum walk-in (`aMsm_check_player`): no A press while open.
	if scripted_input != null or _busy or _door_entering or _menu_open():
		return
	var hit: InteractionQuery = _resolve_interact()
	if hit == null or hit.host == null or hit.action == null:
		return
	if not hit.host.has_method("should_auto_enter"):
		return
	if not bool(hit.host.call("should_auto_enter")):
		return
	## Lock before the first await so the next physics tick does not re-fire.
	_busy = true
	await _run_interact(hit)


func _run_interact(hit: InteractionQuery) -> void:
	_focus = hit.host
	_busy = hit.action.locks_player
	## `SHAKE_TREE` / `SWING_AXE` / scoop set `angle_y` toward the unit before the clip.
	_face_host(hit)
	var tail: float = await _play_action(hit.action.player_anim, hit.action.effect_frame)
	var ctx: InteractionContext = _make_context()
	var t0: int = Time.get_ticks_msec()
	if hit.host != null and is_instance_valid(hit.host):
		## Door enter awaits the structure open clip before changing scene.
		## Ground pickup awaits the pocket shrink (`Set_Item_Pickup` 20→40); that overlaps
		## the clip tail, so subtract spent time from `_finish_action`.
		await hit.host.interact(hit.action, ctx)
	else:
		ToolUse.apply_field(hit.action, ctx)
	var spent: float = float(Time.get_ticks_msec() - t0) / 1000.0
	await _finish_action(maxf(0.0, tail - spent))
	await _play_reel()
	await _play_catch()
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	_update_focus()


## Snap yaw toward the host when the verb plays a body-directed clip. Talk and door enter
## own their facing; empty-tile field verbs keep stick facing (no host).
func _face_host(hit: InteractionQuery) -> void:
	if hit == null or hit.action == null or hit.action.player_anim == &"":
		return
	var host: Node3D = hit.host as Node3D
	if host == null or not is_instance_valid(host):
		return
	var yaw: float = TalkCamera.face_yaw_toward(global_position, host.global_position)
	_motor.facing = yaw
	_mesh.rotation.y = yaw


## Plays the action clip and returns when the effect should land, along with however much of
## the clip is still to run. An `effect_frame` of -1 waits for the whole clip, which is what
## every verb but the cast wants; the cast lets go of the bobber a third of the way in, so the
## swing has to keep playing around it instead of gating it.
func _play_action(clip_name: StringName, effect_frame: float = -1.0) -> float:
	if clip_name == &"":
		return 0.0
	var clip := _resolve_clip(String(clip_name))
	if _anim == null or clip.is_empty():
		await get_tree().create_timer(0.12).timeout
		return 0.0
	## One-shots must not inherit LOOP_LINEAR from a gait `_ensure_loop` on a shared clip
	## name, and must not loop or `animation_finished` never fires while `_busy`.
	var res0: Animation = _anim.get_animation(clip)
	if res0 != null:
		res0.loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	HeldTool.play(HeldTool.find_skeleton(_mesh), _tool_use_anim, false)
	_anim.play(clip, 0.08)
	PlayerSe.schedule_clip(self, clip_name)
	if effect_frame < 0.0:
		await _anim.animation_finished
		HeldTool.play(HeldTool.find_skeleton(_mesh), _tool_hold_anim, true)
		return 0.0
	## The pipeline samples `cKF_ba_r_*` at 30 fps, so a decomp frame number is that frame
	## over 30 in clip time. Timed rather than signalled: the tail has to be waited out after
	## the effect has already been applied, and there is no second `animation_finished`.
	var res: Animation = _anim.get_animation(clip)
	var length: float = res.length if res != null else 0.0
	var mark: float = minf(effect_frame / ANIM_FPS, length)
	if mark > 0.0:
		await get_tree().create_timer(mark).timeout
	return maxf(0.0, length - mark)


## Lets the rest of a split action clip play out before the reel takes over.
func _finish_action(tail: float) -> void:
	if tail <= 0.0:
		return
	await get_tree().create_timer(tail).timeout
	HeldTool.play(HeldTool.find_skeleton(_mesh), _tool_hold_anim, true)


## The rod's reel-in runs after the action, not through `player_anim`: the hook has to
## resolve on the button frame or the bite window is spent animating. `Fishing` picks the
## beats from what came up on the line.
func _play_reel() -> void:
	for beat: Fishing.ReelBeat in Fishing.take_reel_beats():
		if beat.face_camera or beat.hold > 0.0:
			await _play_show(beat)
		else:
			await _play_clip(beat.player_anim, beat.tool_anim)


func _play_catch() -> void:
	for beat: Netting.CatchBeat in Netting.take_catch_beats():
		if beat.face_camera or beat.hold > 0.0:
			await _play_bug_show(beat)
		else:
			await _play_clip(beat.player_anim, beat.tool_anim)


## `m_player_main_notice_rod`: hold the catch up and turn square-on to the camera, then put
## the catch report on screen and keep the pose until the player dismisses it. The facing is
## restored afterwards because the original threads it through `notice_rod` into
## `putaway_rod`, which turns the player back the way they were fishing.
func _play_show(beat: Fishing.ReelBeat) -> void:
	if beat.player_anim == &"":
		return
	var entry_yaw: float = _motor.facing
	var clip := _resolve_clip(String(beat.player_anim))
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	HeldTool.play(skeleton, beat.tool_anim, false)
	HeldCatch.bind(skeleton, beat.fish)
	var length: float = 0.0
	if _anim != null and not clip.is_empty():
		_anim.speed_scale = 1.0
		_anim.play(clip, 0.08)
		var res: Animation = _anim.get_animation(clip)
		if res != null:
			length = res.length
	## `main_notice->timer` counts independently of the animation, so the report opens on
	## frame 42 whether or not the clip has finished — `GET_T2` is longer than that and plays
	## on underneath the text.
	var held: float = 0.0
	var turn_debt: float = 0.0
	var step: float = 1.0 / Fishing.SHOW_TURN_HZ
	while held < beat.hold:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		held += delta
		if not beat.face_camera:
			continue
		## `Player_actor_Movement_Notice_rod` turns once per mover frame, so the step is
		## accumulated on a fixed tick rather than scaled by the frame we happen to get.
		turn_debt += delta
		while turn_debt >= step:
			turn_debt -= step
			_motor.facing = MLib.short_angle2(
				_motor.facing,
				Fishing.SHOW_YAW,
				Fishing.SHOW_TURN_FRACTION,
				Fishing.SHOW_TURN_MAX_STEP,
				Fishing.SHOW_TURN_MIN_STEP
			)
	if beat.catch_msg == 0:
		## Nothing to hold for, so the pose still has to outlast its own clip: dropping
		## `_busy` early would let the idle animation cut it off mid-hold.
		if held < length:
			await get_tree().create_timer(length - held).timeout
	else:
		await _report_catch(beat.catch_msg, beat.pockets_full)
	_motor.facing = entry_yaw
	await _play_putaway(skeleton)


## `Player_actor_request_proc_index_fromNotice_rod` hands the dismissed report to
## `putaway_rod`, which plays `PUTAWAY_T1` with a `GASAGOSO` rustle and then falls back to the
## wait. The catch is in the pocket well before this: `setup_main_Notice_rod` banks it with
## `Player_actor_putin_item` before the text ever opens, so this is the visible half of a move
## already made — which is also why a full pocket takes the other branch and throws it back.
func _play_putaway(skeleton: Skeleton3D) -> void:
	## The rod has no putaway clip of its own — `tol_sao_1` carries six and none is one — so it
	## holds the wait pose while the player's hands do the work.
	HeldTool.play(skeleton, _tool_hold_anim, true)
	var clip := _resolve_clip(String(Fishing.PUTAWAY))
	if _anim == null or clip.is_empty():
		HeldCatch.unbind(skeleton)
		return
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)
	## Timed off the clip rather than waited on `animation_finished`, which never arrives if
	## anything else drives the player in the meantime — and then the catch is never released.
	var res: Animation = _anim.get_animation(clip)
	if res != null and res.length > 0.0:
		await get_tree().create_timer(res.length).timeout
	## Released at the end, not the start: the fish rides the hand down and goes as the pose
	## closes, rather than blinking out from under a hand still holding it up.
	HeldCatch.unbind(skeleton)


func _play_bug_show(beat: Netting.CatchBeat) -> void:
	if beat.player_anim == &"":
		return
	var entry_yaw: float = _motor.facing
	var clip := _resolve_clip(String(beat.player_anim))
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	HeldTool.play(skeleton, beat.tool_anim, false)
	HeldCatch.bind_bug(skeleton, beat.bug)
	var length: float = 0.0
	if _anim != null and not clip.is_empty():
		_anim.speed_scale = 1.0
		_anim.play(clip, 0.08)
		var res: Animation = _anim.get_animation(clip)
		if res != null:
			length = res.length
	var held: float = 0.0
	var turn_debt: float = 0.0
	var step: float = 1.0 / Netting.SHOW_TURN_HZ
	while held < beat.hold:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		held += delta
		if not beat.face_camera:
			continue
		turn_debt += delta
		while turn_debt >= step:
			turn_debt -= step
			_motor.facing = MLib.short_angle2(
				_motor.facing,
				Netting.SHOW_YAW,
				Netting.SHOW_TURN_FRACTION,
				Netting.SHOW_TURN_MAX_STEP,
				Netting.SHOW_TURN_MIN_STEP
			)
	if beat.catch_msg == 0:
		if held < length:
			await get_tree().create_timer(length - held).timeout
	else:
		await _report_catch(beat.catch_msg, beat.pockets_full, POCKETS_FULL_BUG_MSG_ID, true)
	_motor.facing = entry_yaw
	await _play_bug_putaway(skeleton)


func _play_bug_putaway(skeleton: Skeleton3D) -> void:
	HeldTool.play(skeleton, _tool_hold_anim, true)
	var clip := _resolve_clip(String(Netting.PUTAWAY))
	if _anim == null or clip.is_empty():
		HeldCatch.unbind(skeleton)
		return
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)
	var res: Animation = _anim.get_animation(clip)
	if res != null and res.length > 0.0:
		await get_tree().create_timer(res.length).timeout
	HeldCatch.unbind(skeleton)


## `Player_actor_MessageControl_Notice_rod` opens the catch report once its 42 frames are up
## and holds `LockContinue` until the player advances it, so the pose stays on screen for as
## long as the text does. `_update_animation` bails while `_busy`, which is what keeps the
## last frame of `GET_T2` up rather than falling back to the idle.
## The text is the game's own: `Player_actor_Get_sakana_msg_num` gives a message number per
## species and the extracted bank has the line, pun and all. The rare three (stringfish,
## coelacanth, arapaima) run to two pages, which is why this plays a conversation through the
## runner instead of pushing a single string.
func _report_catch(
	catch_msg: int,
	pockets_full: bool = false,
	full_msg_id: StringName = POCKETS_FULL_MSG_ID,
	use_bug_text: bool = false
) -> void:
	if catch_msg == 0:
		return
	var ui: Node = null
	if get_tree() != null:
		ui = get_tree().get_first_node_in_group("dialogue_ui")
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % catch_msg))
	var fallback: String = (
		BugCatalog.catch_text(catch_msg) if use_bug_text else FishCatalog.catch_text(catch_msg)
	)
	if ui == null or not ui.has_signal("closed"):
		Game.post_notice(fallback)
		return
	if data != null and ui.has_method("play"):
		ui.call("play", data, null)
	elif ui.has_method("say"):
		ui.call("say", fallback)
	else:
		Game.post_notice(fallback)
		return
	await ui.closed
	if not pockets_full:
		return
	var full: DialogueData = DialogueCatalog.conversation(full_msg_id)
	var text: String = (
		BugCatalog.first_line(full) if use_bug_text else FishCatalog.first_line(full)
	)
	if text.is_empty():
		return
	if ui.has_method("say"):
		ui.call("say", text)
		await ui.closed
	else:
		Game.post_notice(text)


func _play_clip(clip_name: StringName, tool_clip: StringName) -> void:
	if clip_name == &"":
		return
	var clip := _resolve_clip(String(clip_name))
	if _anim == null or clip.is_empty():
		await get_tree().create_timer(0.12).timeout
		return
	_anim.speed_scale = 1.0
	HeldTool.play(HeldTool.find_skeleton(_mesh), tool_clip, false)
	_anim.play(clip, 0.08)
	PlayerSe.schedule_clip(self, clip_name)
	await _anim.animation_finished
	HeldTool.play(HeldTool.find_skeleton(_mesh), _tool_hold_anim, true)


func _try_load_generated_visual() -> void:
	if not ResourceLoader.exists(GENERATED_PLAYER):
		return
	var packed: PackedScene = load(GENERATED_PLAYER) as PackedScene
	if packed == null:
		return
	var visual: Node = packed.instantiate()
	if not (visual is Node3D):
		visual.queue_free()
		return
	var body := visual as Node3D
	_placeholder.visible = false
	_mesh.add_child(body)
	_scale_visual(body)
	_apply_preview_materials(body)
	_anim = _find_animation_player(body)
	if _anim != null:
		## Carry overlay lands after the body's own mix (anim1 on the part-table joints).
		_anim.mixer_applied.connect(_apply_carry_pose)
		## INDEX_DOOR / getoff: capture joint_0 XZ into AnimationMove, strip so the mesh stays on the body.
		## INDEX_OUTDOOR GO_OUT keeps joint_0 (starts behind stand, ends at bind — no snap).
		_capture_door_root_xz(_anim)
		VisualAnimation.strip_named_joint_tracks(
			_anim,
			"joint_0",
			PackedStringArray(
				[
					ANIM_OPEN1,
					ANIM_INTO_S1,
					ANIM_OUTTRAIN1,
					ANIM_PUSH1,
					ANIM_PULL1,
					ANIM_SITDOWN1,
					ANIM_STANDUP1,
					ANIM_INBED_L1,
					ANIM_INBED_R1,
					ANIM_OUTBED_L1,
					ANIM_OUTBED_R1,
				]
			),
		)
		var wait_clip := _resolve_clip(ANIM_WAIT)
		if not wait_clip.is_empty():
			_ensure_loop(wait_clip)
			_anim.play(wait_clip)
	_apply_worn_cloth()


func _on_cloth_changed(_cloth_id: StringName) -> void:
	_apply_worn_cloth()


func _on_design_changed() -> void:
	_apply_worn_cloth()


func _apply_worn_cloth() -> void:
	if Game == null or _mesh == null:
		return
	## Custom original design worn as a shirt (`cloth.idx >= CLOTH_NUM+1`).
	if Game.worn_design_slot >= 0 and Game.designs != null:
		var design: DesignPattern = Game.designs.resolved(Game.worn_design_slot)
		if design != null:
			VisualCloth.apply_design(_mesh, DesignTexture.build(design))
			return
	var data: ItemData = ItemCatalog.get_item(Game.cloth_id)
	var index: int = data.cloth_index if data != null else -1
	if index < 0 and Game.cloth_id != &"":
		## Fallback: shirt_NNN id → index.
		var raw := String(Game.cloth_id)
		if raw.begins_with("shirt_"):
			index = int(raw.substr(6))
	if index < 0:
		return
	VisualCloth.apply_cloth(_mesh, index)


func _capture_door_root_xz(anim_player: AnimationPlayer) -> void:
	## Bake scaled joint_0 XZ deltas once before stripping (`base_model_translation` XZ = 0).
	var scale: float = FieldCatalog.actor_uniform_scale()
	for leaf: String in [ANIM_OPEN1, ANIM_INTO_S1, ANIM_OUTTRAIN1]:
		if _door_root_xz.has(leaf):
			continue
		var clip_name := _resolve_clip_in(anim_player, leaf)
		if clip_name.is_empty():
			continue
		var src: Animation = anim_player.get_animation(clip_name)
		if src == null:
			continue
		var track_i: int = _find_joint0_position_track(src)
		if track_i < 0:
			continue
		var baked := Animation.new()
		baked.length = src.length
		var out_track: int = baked.add_track(Animation.TYPE_POSITION_3D)
		baked.track_set_path(out_track, NodePath("."))
		var key_count: int = src.track_get_key_count(track_i)
		for key_i: int in range(key_count):
			var t: float = src.track_get_key_time(track_i, key_i)
			var pos: Vector3 = src.track_get_key_value(track_i, key_i) as Vector3
			## `scale * (cur_joint.xz - base_model_translation.xz)`; base XZ is 0.
			baked.position_track_insert_key(
				out_track, t, Vector3(pos.x * scale, 0.0, pos.z * scale)
			)
		_door_root_xz[leaf] = baked


func _find_joint0_position_track(animation: Animation) -> int:
	var needle := ":joint_0"
	for track_i: int in range(animation.get_track_count()):
		var path := String(animation.track_get_path(track_i))
		if not (path.contains(":joint_0:") or path.ends_with(needle)):
			continue
		var ttype: int = animation.track_get_type(track_i)
		if ttype == Animation.TYPE_POSITION_3D or ttype == Animation.TYPE_VALUE:
			return track_i
	return -1


func _resolve_clip_in(anim_player: AnimationPlayer, suffix: String) -> String:
	if anim_player == null or suffix.is_empty():
		return ""
	if anim_player.has_animation(suffix):
		return suffix
	for anim_name: String in anim_player.get_animation_list():
		if anim_name == suffix or anim_name.ends_with("/" + suffix) or anim_name.ends_with(suffix):
			return anim_name
	return ""


func _on_equipment_changed(_item_id: StringName) -> void:
	var tool: ToolData = _equipped_tool()
	var to_umbrella: bool = tool != null and tool.kind == ToolData.Kind.UMBRELLA
	## An umbrella opens out of / folds into the hand (`TAKEOUT_ITEM` / `PUTIN_ITEM` with
	## `UMB_OPEN1` / `UMB_CLOSE1`) rather than just appearing.
	if (to_umbrella or _umbrella != null) and not _tool_hidden() and not _busy and is_inside_tree() \
			and _anim != null:
		_swap_umbrella(to_umbrella)
		return
	_bind_equipped_tool(not _tool_hidden())
	if not _busy:
		_replay_gait_clip()


## `setup_main_Putin_item` (umbrella: `UMB_CLOSE1`, the tool folds shut over 30 frames) then
## `setup_main_Takeout_item` (umbrella: `UMB_OPEN1`, it opens from nothing).
func _swap_umbrella(to_umbrella: bool) -> void:
	var was_busy: bool = _busy
	_busy = true
	_tool_swap = true
	if _umbrella != null:
		await _fold_umbrella()
	if to_umbrella:
		await _open_umbrella()
	else:
		_bind_equipped_tool(not _tool_hidden())
	_tool_swap = false
	_busy = was_busy
	if not _busy:
		_replay_gait_clip()


func _fold_umbrella() -> void:
	if _umbrella == null:
		return
	_umbrella.set_action(HeldUmbrella.Action.PUTAWAY)
	var length: float = _play_umbrella_clip("ply_1_umb_close1")
	var waited: float = 0.0
	while is_inside_tree() and waited < maxf(length, 1.0) and not _umbrella.is_closed():
		await get_tree().process_frame
		waited += get_process_delta_time()
	_umbrella = null
	HeldTool.unbind(HeldTool.find_skeleton(_mesh))


func _open_umbrella() -> void:
	_bind_equipped_tool(true, HeldUmbrella.Action.TAKEOUT_BEFORE)
	var length: float = _play_umbrella_clip("ply_1_umb_open1")
	if length > 0.0 and is_inside_tree():
		await get_tree().create_timer(length).timeout


## Full-body umbrella clip once (`cKF_FRAMECONTROL_STOP`); returns its length.
func _play_umbrella_clip(leaf: String) -> float:
	var clip := _resolve_clip(leaf)
	if _anim == null or clip.is_empty():
		return 0.0
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)
	PlayerSe.schedule_clip(self, StringName(clip))
	var res: Animation = _anim.get_animation(clip)
	return res.length if res != null else 0.0


## `mPlib_check_player_open_umbrella`: an umbrella is out and fully open.
func is_umbrella_open() -> bool:
	return _umbrella != null and _umbrella.opened_fully and not _tool_hidden()


## `Player_actor_InitAnimation_Base1` with a part table: while standing / walking / running the
## carried item's clip drives the table's arm joints over the body clip. Every other state
## (swings, digs, take-out, the umbrella's own clips) plays one clip on the whole body.
func _apply_carry_pose() -> void:
	if _carry == null or _tool_swap or _anim == null or not ToolCarry.rides_on(String(_anim.current_animation)):
		return
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	if skeleton != null:
		_carry.apply(skeleton)


func _tool_hidden() -> bool:
	return _tool_stowed or Game.is_indoors()


func _bind_equipped_tool(
	show_tool: bool, umbrella_start: HeldUmbrella.Action = HeldUmbrella.Action.OPEN_NOW
) -> void:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	HeldTool.unbind(skeleton)
	_umbrella = null
	_carry = null
	_hold_anim = &""
	_tool_hold_anim = &""
	_tool_use_anim = &""
	var tool: ToolData = _equipped_tool()
	if show_tool and tool != null and tool.visual_id != &"":
		var attach: Node3D = HeldTool.bind(skeleton, tool.visual_id)
		_carry = ToolCarry.build(_anim, skeleton, tool)
		if tool.kind == ToolData.Kind.UMBRELLA and attach != null and attach.get_child_count() > 0:
			_umbrella = HeldUmbrella.new()
			_umbrella.setup(attach.get_child(0) as Node3D, umbrella_start)
		_hold_anim = tool.hold_anim
		_tool_hold_anim = tool.visual_hold_anim
		_tool_use_anim = tool.visual_use_anim
		HeldTool.play(skeleton, _tool_hold_anim, true)


## `Player_actor_CheckAndRequest_ItemInOut`: a door request while a tool is out is swapped for
## `PUTIN_ITEM` (`PUTAWAY1` forward, the tool shrinking into the hand over 18 ticks), and the
## door sequence only starts once it ends. The equipped item itself is untouched.
func put_away_tool_for_door() -> void:
	if _tool_hidden() or _equipped_tool() == null:
		return
	var was_busy: bool = _busy
	_busy = true
	_tool_swap = true
	if not _door_entering:
		_door_clear_busy = false
	if _umbrella != null:
		## `setup_main_Putin_item`: an umbrella folds (`UMB_CLOSE1`) instead of `PUTAWAY1`.
		await _fold_umbrella()
		_tool_stowed = true
		_bind_equipped_tool(false)
		_tool_swap = false
		_busy = was_busy
		return
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	var length: float = _play_tool_swap_clip(false)
	var total: float = TOOL_MORPH_SEC + length + PUTIN_STOP_TICKS * TOOL_TICK_SEC
	var elapsed: float = 0.0
	while elapsed < total:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if elapsed < TOOL_MORPH_SEC and _anim != null:
			_anim.seek(0.0, true)
		var scale_t: float = clampf(elapsed / (PUTIN_SCALE_TICKS * TOOL_TICK_SEC), 0.0, 1.0)
		HeldTool.set_scale(skeleton, 1.0 - scale_t)
	_tool_stowed = true
	_bind_equipped_tool(false)
	_tool_swap = false
	## The door sequence (`begin_door_enter`) takes over from here and locks movement itself.
	_busy = was_busy


## Outdoor spawn from a door: `OUTDOOR` has `ABLE_ITEM_NONE`, so nothing is in hand until
## `take_out_tool`.
func stow_tool_for_door_exit() -> void:
	if _equipped_tool() == null:
		return
	_tool_stowed = true
	_bind_equipped_tool(false)


## `RETURN_OUTDOOR` (3 ticks) → `TAKEOUT_ITEM` → `RETURN_OUTDOOR2` (3 ticks). Take-out plays
## `PUTAWAY1` reversed with nothing in hand, then from tick 36 blends to the tool's hold pose
## while it grows 0 → 1, ending at tick 54.
func take_out_tool() -> void:
	if not _tool_stowed:
		return
	var was_busy: bool = _busy
	_busy = true
	_tool_swap = true
	if not _door_entering:
		_door_clear_busy = false
	await get_tree().create_timer(RETURN_OUTDOOR_TICKS * TOOL_TICK_SEC).timeout
	_tool_stowed = false
	var held: ToolData = _equipped_tool()
	if held != null and held.kind == ToolData.Kind.UMBRELLA and not Game.is_indoors():
		## `setup_main_Takeout_item`: an umbrella opens out (`UMB_OPEN1`), no grow-in.
		await _open_umbrella()
		await get_tree().create_timer(RETURN_OUTDOOR_TICKS * TOOL_TICK_SEC).timeout
		_tool_swap = false
		_busy = was_busy
		if not _busy:
			_replay_gait_clip()
		return
	_bind_equipped_tool(not Game.is_indoors())
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	HeldTool.set_scale(skeleton, 0.0)
	var length: float = _play_tool_swap_clip(true)
	var grow_start: float = TAKEOUT_SCALE_START_TICKS * TOOL_TICK_SEC
	var end: float = TAKEOUT_END_TICKS * TOOL_TICK_SEC
	var elapsed: float = 0.0
	var posed: bool = false
	while elapsed < end:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not posed and elapsed < TOOL_MORPH_SEC and _anim != null:
			## Reverse clip: the morph holds its *last* frame.
			_anim.seek(length, true)
		if elapsed < grow_start:
			continue
		if not posed:
			posed = true
			_blend_to_hold_pose()
		elif elapsed < grow_start + TOOL_MORPH_SEC and _anim != null:
			_anim.seek(0.0, true)
		HeldTool.set_scale(skeleton, clampf((elapsed - grow_start) / (end - grow_start), 0.0, 1.0))
	HeldTool.set_scale(skeleton, 1.0)
	await get_tree().create_timer(RETURN_OUTDOOR_TICKS * TOOL_TICK_SEC).timeout
	_tool_swap = false
	_busy = was_busy
	if not _busy and (_anim == null or not _anim.is_playing()):
		_replay_gait_clip()


## Plays `PUTAWAY1` (reversed for take-out) plus its GASAGOSO rustle; returns its length.
func _play_tool_swap_clip(reverse: bool) -> float:
	var clip := _resolve_clip(ANIM_PUTAWAY1)
	if _anim == null or clip.is_empty():
		return 0.0
	_anim.speed_scale = 1.0
	if reverse:
		_anim.play_backwards(clip, TOOL_MORPH_SEC)
	else:
		_anim.play(clip, TOOL_MORPH_SEC)
	PlayerSe.schedule_clip(self, StringName(clip))
	var res: Animation = _anim.get_animation(clip)
	return res.length if res != null else 0.0


func _blend_to_hold_pose() -> void:
	if _anim == null:
		return
	var clip := _resolve_clip(ANIM_WAIT)
	if clip.is_empty():
		return
	_ensure_loop(clip)
	_gait = PlayerLocomotion.Gait.WAIT
	_anim.speed_scale = 1.0
	_anim.play(clip, TOOL_MORPH_SEC)


func _equipped_tool() -> ToolData:
	if Game.inventory == null or Game.inventory.equipment_id == &"":
		return null
	return ItemCatalog.get_item(Game.inventory.equipment_id) as ToolData


func _replay_gait_clip() -> void:
	if _anim == null:
		return
	var gait: PlayerLocomotion.Gait = _motor.gait()
	_gait = gait
	var clip := _resolve_clip(_clip_for(gait))
	if clip.is_empty():
		return
	_ensure_loop(clip)
	_anim.speed_scale = _anim_speed(gait)
	_anim.play(clip, 0.12)


func _scale_visual(body: Node3D) -> void:
	var s: float = FieldCatalog.actor_uniform_scale()
	body.scale = Vector3.ONE * s
	var aabb := _mesh_aabb(body)
	if aabb.size.y <= 0.001:
		return
	body.position.y = -aabb.position.y * s


func _ensure_loop(clip: String) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _apply_preview_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
			if mat is StandardMaterial3D:
				var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				std.vertex_color_use_as_albedo = false
				std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				## Pipeline bakes REPEAT/MIRROR into the PNG and remaps UVs to 0–1;
				## keep clamp so U never sticks to the shirt texture's right edge.
				std.texture_repeat = false
				std.cull_mode = BaseMaterial3D.CULL_DISABLED
				std.roughness = 1.0
				std.metallic = 0.0
				if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
					std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				VisualMaterials.harden_imported_cutout(std)
				mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_apply_preview_materials(child)


func _mesh_aabb(node: Node) -> AABB:
	var merged := AABB()
	var started := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			merged = mi.transform * mi.mesh.get_aabb()
			started = true
	for child in node.get_children():
		var child_aabb := _mesh_aabb(child)
		if child_aabb.size == Vector3.ZERO:
			continue
		if child is Node3D:
			child_aabb = (child as Node3D).transform * child_aabb
		if started:
			merged = merged.merge(child_aabb)
		else:
			merged = child_aabb
			started = true
	return merged
