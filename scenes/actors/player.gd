class_name Player
extends CharacterBody3D

## CharacterBody3D player. Locomotion feel from `m_player_main_walk`; visual from
## `boy_1.glb` or `grl_1.glb` (`mPlib_get_player_mdl_p`). Equipped tools
## parent to HAND (`HeldTool`). Walk physics cylinder radius matches `BgCheckControll`
## range (18 GX → 0.9 m) — same as `FieldCollision.ACTOR_RADIUS` / trees-rocks columns.
## Height keeps the OcInfo stand pipe (60 GX → 3.0 m). Cliffs/water use `revise_xz`,
## not this shape. OcInfo radius 20 is actor-actor CollisionCheck, not world walk.

const PLAYER_BOY_GLB := "res://assets/generated/characters/player/boy_1.glb"
const PLAYER_GIRL_GLB := "res://assets/generated/characters/player/grl_1.glb"
## `Player_actor_set_eye_PositionAndAngle`: the eye is 33 GX up (`Actor_world_to_eye`).
## The outdoor and talk cameras centre on it.
const LOOK_HEIGHT := 33.0 * PlayerLocomotion.UNIT_METERS
const INTERACT_REACH := 1.1

## `notice_rod` chains message 0x1348 onto the fish catch report when pockets are full.
const POCKETS_FULL_MSG_ID := &"msg_4936"
## `notice_rod`'s follow-up to 0x1349 when the catch completes the fish record.
const FISH_RECORD_DONE_MSG := 0x134A
## `notice_rod`: the fish page finished (0x134A) under its own jingle (0x4C).
const ROD_COMPLETE_MSG := 0x134A
const ROD_COMPLETE_FANFARE := 0x4C
const POCKETS_FULL_MSG := 4936

const ANIM_WAIT := "ply_1_wait1"
## `Player_actor_request_proc_index_fromRelease_creature` / `Look_Release_creature` timers.
## `mPlayer_ANIM_SAISEN1` / `OMAIRI_US1`: the New Year coin toss and prayer at the well.
const ANIM_SAISEN := &"ply_1_saisen1"
const ANIM_OMAIRI := &"ply_1_omairi_us1"
## The step onto the coin spot takes 5 frames at 30 fps; the purse rustles at keyframe 9 and
## the coin flies at 33.
const SHRINE_STEP_SEC := 5.0 / DecompTime.FRAME_HZ
const SHRINE_RUSTLE_SEC := 9.0 / DecompTime.FRAME_HZ
const SHRINE_THROW_SEC := 33.0 / DecompTime.FRAME_HZ
## `mPlayer_ANIM_CONFIRM1`: the mailbox hop and landing.
const ANIM_CONFIRM := &"ply_1_confirm1"
## `cKF_SkeletonInfo_R_AnimationMove_ct_base(…, 8.0f, …)`: 8 frames at 30 fps.
const MAIL_JUMP_SEC := 8.0 / DecompTime.FRAME_HZ
## `main_Release_creature`: 84 ticks of `WAIT1`, the head following for the first 60.
const RELEASE_SECONDS := 84.0 / DecompTime.TICK_HZ
const RELEASE_LOOK_SECONDS := 60.0 / DecompTime.TICK_HZ
const ANIM_WALK := "ply_1_walk1"
const ANIM_RUN := "ply_1_run1"
const ANIM_DASH := "ply_1_dash1"
## `mPlayer_ANIM_RUN_SLIP1` — the dash skid (`turn_dash`).
const ANIM_RUN_SLIP := "ply_1_run_slip1"
## cKF morph −5 / −12 at 60 Hz (`-5.0f` on walk/run/dash/wait, `-12.0f` skid → wait).
const MORPH_5 := 10.0 / DecompTime.TICK_HZ
const MORPH_12 := 24.0 / DecompTime.TICK_HZ
## `Player_actor_SetEffect_Tumble` frames.
const TUMBLE_MARKS: Array = [[10.0, &"tumble_rumble"], [15.0, &"tumble_dust"], [17.0, &"tumble_print"]]
## `BodyAnimator` gait per moving gait.
const GAIT_STATES := {
	PlayerLocomotion.Gait.WALK: &"walk",
	PlayerLocomotion.Gait.RUN: &"run",
	PlayerLocomotion.Gait.DASH: &"dash",
}
## `Player_actor_sound_slip` (`0x4129`).
const SE_SLIP := &"4129"
## `mPlayer_ANIM_OPEN1` — door enter demo (`mPlayer_INDEX_DOOR`, type 0).
const ANIM_OPEN1 := "ply_1_open1"
## `mPlayer_ANIM_KNOCK1`: knocking before a door that is not the player's own.
const ANIM_KNOCK1 := "ply_1_knock1"
## `mPlayer_ANIM_INTO_S1` — indoor door / exit walk (`mPlayer_INDEX_DOOR`, type ≠ 0).
const ANIM_INTO_S1 := "ply_1_into_s1"
## `mPlayer_ANIM_GO_OUT_S1` — outdoor emerge demo (`mPlayer_INDEX_OUTDOOR`, is_start_demo).
const ANIM_GO_OUT_S1 := "ply_1_go_out_s1"
## `mPlayer_ANIM_GO_OUT_O1` — non-demo outdoor emerge (`Player_actor_setup_main_Outdoor`).
const ANIM_GO_OUT_O1 := "ply_1_go_out_o1"
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
## `mPlayer_ANIM_NEGAERI_L1` / `R1`: rolling over in bed (`Roll_bed`).
const ANIM_NEGAERI_L1 := "ply_1_negaeri_L1"
const ANIM_NEGAERI_R1 := "ply_1_negaeri_R1"
## `m_player_main_stung_bee` (`HATI1` → `HATI2`) then `notice_bee` (`HATI3` + the report).
const ANIM_HATI1 := "ply_1_hati1"
const ANIM_HATI2 := "ply_1_hati2"
const ANIM_HATI3 := "ply_1_hati3"
## `SearchAnimation_Stung_bee`: the face swells on `HATI2` frame 21.
const STUNG_SWELL_FRAME := 21.0
## `Movement_Stung_bee` turns to face the camera after 94 ticks; at 252 → `notice_bee`.
const STUNG_TURN_SEC := 94.0 / DecompTime.TICK_HZ
const STUNG_NOTICE_SEC := 252.0 / DecompTime.TICK_HZ
## `Player_actor_Notice_bee_demo_ct`: `0x17B4` in a lilac report window.
const BEE_NOTICE_MSG := 0x17B4
const BEE_NOTICE_COLOR := Color8(225, 165, 255)
## `READY_PITFALL` → `FALL_PITFALL` → `STRUGGLE_PITFALL` → `CLIMBUP_PITFALL`.
const ANIM_GURATUKU1 := "ply_1_guratuku1"
const ANIM_OTIRU1 := "ply_1_otiru1"
const ANIM_MOGAKU1 := "ply_1_mogaku1"
const ANIM_DERU1 := "ply_1_deru1"
## `ControlAnimationSpeed_Struggle_pitfall`: 20 presses' worth of A and stick wiggling.
const STRUGGLE_PRESSES := 20.0
const STRUGGLE_SPEED_MIN := 0.5
const STRUGGLE_SPEED_DECAY := 0.00435
const STRUGGLE_SPEED_EASE := 0.10875
## `m_player_main_stung_mosquito` (`MOSQUITO1`) → `notice_mosquito` (`MOSQUITO2` + report).
const ANIM_MOSQUITO1 := "ply_1_mosquito1"
const ANIM_MOSQUITO2 := "ply_1_mosquito2"
const MOSQUITO_NOTICE_MSG := 0x3063
## `mPlayer_ANIM_OUTTRAIN1` — station caboose step-off (`mPlayer_INDEX_DEMO_GETOFF_TRAIN`).
const ANIM_OUTTRAIN1 := "ply_1_outtrain1"

@onready var _mesh: Node3D = $MeshPivot
@onready var _placeholder: MeshInstance3D = $MeshPivot/PlaceholderMesh
@onready var _probe: Area3D = $MeshPivot/InteractProbe
@onready var _look: Marker3D = $CameraLook
## Glyphs over the player's head: the startle (`ef_shock`) and the like.
@onready var feel: NpcFeelGlyphs = $Feel
@onready var _animator: BodyAnimator = $Animator

## The player's components, child nodes declared in `player.tscn` (set before any child's
## `_ready`). Each owns one kind of action and reads this node's motor, body animation and
## busy flag directly.
@export var doors: PlayerDoors
@export var furniture: PlayerFurniture
@export var tools: PlayerTools
@export var net: PlayerNet
@export var fishing: PlayerFishing
@export var snowball: PlayerSnowball

## The catch is up in the show-off pose (`PlayerFishing`). Villagers ask for it by name
## so their tests can use stand-ins.
var catch_showing: bool:
	get:
		return fishing != null and fishing.catch_showing

## Title demo: a recorded stick + A replace live input (`mEv_IsTitleDemo` swaps the controller
## in `m_player_controller.c_inc`). Null during normal play.
var scripted_input: TitleDemoInput = null
## `mPlib_Set_unable_wade`: acre crossings are refused; trying one raises `wade_cancelled`
## (`excute_cancel_wade`, which the intro's Nook answers).
var unable_wade: bool = false
## `mCoBG_ChangeBlockBgCheckMode(1)` (intro house pick): walls one unit further in on the
## player-house acre, and the wade border with them.
var intro_block_bg_check: bool = false
var _motor: PlayerLocomotion = PlayerLocomotion.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## `Player_actor_Movement_Base_Braking_common(actor, 0.32625002f)`.
const RECOIL_BRAKE := 0.32625002
var _recoil_speed: float = 0.0
var _recoil_yaw: float = 0.0
var _busy: bool = false
## Station intro ride / guided walk — stage owns XZ/Y; skip snap + move_and_slide.
var _cutscene_driven: bool = false
var _focus: Node = null
## The body tree once the model is bound (`_animator`), null without a model.
var _anim: BodyAnimator
var _gait: PlayerLocomotion.Gait = PlayerLocomotion.Gait.WAIT
var _placeholder_bob: float = 0.0
var _radio := RadioExercise.new()
## Doing a radio exercise (`mPlayer_INDEX_RADIO_EXERCISE`).
var exercising: bool = false
## Inside `Stung_bee` / `Notice_bee` (`mPlib_Check_end_stung_bee` is its fall).
var stung: bool = false
## Between stepping on a pitfall and climbing out of it.
var in_pitfall: bool = false
## Scripted struggle (tests, captures): added to the press count every tick.
var struggle_assist: float = 0.0
var _step_time: float = 0.0
var _right_foot: bool = true
## `ripple_timer` / `ripple_foot_idx`: standing or wading in the surf rings the water at
## one foot and then the other, every eight ticks.
var _ripple_time: float = 0.0
var _ripple_right: bool = false
const RIPPLE_SECONDS := 8.0 / DecompTime.TICK_HZ
## `Player_actor_Movement_Talk` — ease yaw toward the NPC while the talk demo runs.
var _talk_face: Node3D = null
## `player->shake_tree_*`: trees this player has already shaken (little or button).
var _tree_bump: TreeBump = TreeBump.new()
## Crossing into the next acre (`mPlayer_INDEX_WADE`): `{start, end, t}` (world metres,
## ticks); empty when not wading. See `AcreWade`.
var _wade: Dictionary = {}
## Stick direction × strength on the ground plane, last physics frame (snowballs read it).
var move_intent: Vector3 = Vector3.ZERO
## The snowball being pushed (`mPlayer_INDEX_PUSH_SNOWBALL`), or null.
var _snowball: Node3D = null


signal wade_cancelled

const GROUP := &"player"


## The field / room player in `tree`, or null.
static func find(tree: SceneTree) -> Player:
	return tree.get_first_node_in_group(GROUP) as Player if tree != null else null


## `mPlib_get_player_mdl_p`: male is `cKF_bs_r_boy_1`, anyone else is `cKF_bs_r_grl_1`.
static func visual_path() -> String:
	if (
		Game != null
		and Game.resident.player_gender == IntroSequence.GENDER_FEMALE
		and ResourceLoader.exists(PLAYER_GIRL_GLB)
	):
		return PLAYER_GIRL_GLB
	return PLAYER_BOY_GLB


static func visual_id() -> StringName:
	return &"grl_1" if visual_path() == PLAYER_GIRL_GLB else &"boy_1"


func _ready() -> void:
	add_to_group(GROUP)
	feel.set_head_lift(LOOK_HEIGHT)
	_motor.ground_sampler = _motor_ground_y
	_motor.flat_sampler = _motor_unit_flat
	_look.position = Vector3(0.0, LOOK_HEIGHT, 0.0)
	_try_load_generated_visual()
	if Game != null and not Game.cloth_changed.is_connected(_on_cloth_changed):
		Game.cloth_changed.connect(_on_cloth_changed)
	if Game != null and not Game.design_changed.is_connected(_on_design_changed):
		Game.design_changed.connect(_on_design_changed)
	if Game != null and not Game.face_changed.is_connected(_apply_face):
		Game.face_changed.connect(_apply_face)
	_apply_worn_cloth()
	## `Player_actor_Check_player_sunburn_for_ct`: a tan earned or faded shows on set-up.
	if Game != null and not Game.title_demo_active:
		Sunburn.on_setup(Game.resident.sunburn, Clock.day_number())
	_apply_face()
	Game.inventory.equipment_changed.connect(tools.on_equipment_changed)
	tools.on_equipment_changed(Game.inventory.equipment_id)


func _exit_tree() -> void:
	if Game.inventory.equipment_changed.is_connected(tools.on_equipment_changed):
		Game.inventory.equipment_changed.disconnect(tools.on_equipment_changed)


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


func end_talk_face() -> void:
	_talk_face = null


func is_talk_facing() -> bool:
	return _talk_face != null and is_instance_valid(_talk_face)


## `aINS_get_stress_sub`: player planar speed as GX per 30 Hz frame.
func insect_stress_move_gx() -> float:
	return _motor.planar_speed / FieldCatalog.GX_TO_METERS / DecompTime.FRAME_HZ


## `mPlayer_INDEX_DASH`: fish bolt from a dashing player but ignore a walking one.
## `Get_WadeEndPos_proc`: where the running acre crossing lands (world metres), or
## `Vector3.INF` when not wading. The set manager reads it to pick the acre it spawns in.
func wade_end_position() -> Vector3:
	return _wade.get("end", Vector3.INF) if not _wade.is_empty() else Vector3.INF


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
	if not doors.door_entering:
		doors.door_clear_busy = false


func set_facing(yaw: float) -> void:
	_motor.facing = yaw
	if _mesh != null:
		_mesh.rotation.y = yaw


## Hard stop for the exit-cell warp — natural deceleration from run speed would leave the
## player visibly sliding as the 0.6 s wipe goes black. Kill the speed outright.
func stop_for_door() -> void:
	_busy = true
	if not doors.door_entering:
		doors.door_clear_busy = false
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


func animation_player() -> BodyAnimator:
	return _anim


## Idle while input-locked (talk / intro). Safe to call during `_busy`.
func play_wait_idle() -> void:
	if _anim == null or doors.door_entering:
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
	_tick_sunburn(delta)
	if _mesh != null:
		_mesh.rotation.x = _motor.lean
	if tools.umbrella != null:
		tools.umbrella.tick(delta)
	tools.tick_pinwheel(delta)
	tools.tick_balloon(delta)
	if tools.carry != null:
		tools.carry.advance(delta)
	if doors.door_entering:
		doors.tick_door_enter(delta)
		return
	if _cutscene_driven:
		velocity = Vector3.ZERO
		_mesh.rotation.y = _motor.facing
		_update_animation(delta)
		return

	if not _wade.is_empty():
		_tick_wade(delta)
		return

	if furniture.gripping:
		furniture.tick_grip(delta)
	elif not furniture.rest.is_empty():
		furniture.tick_rest(delta)
	elif not _busy and scripted_input == null and not net.is_active():
		furniture.poll_furniture_pickup()
		_poll_pitfall()
		_poll_radio_exercise(delta)
		furniture.poll_rest(delta)
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
	if doors.demo_walk_speed > 0.0 and not _busy and not menu_open:
		var to_goal := Vector3(doors.demo_walk_goal.x - global_position.x, 0.0, doors.demo_walk_goal.z - global_position.z)
		if to_goal.length() > doors.demo_walk_arrive:
			wish = to_goal.normalized()
			stick = clampf(doors.demo_walk_speed / PlayerLocomotion.WALK_SPEED, 0.0, 1.0)
	elif not _busy and not menu_open:
		if scripted_input != null:
			input_dir = scripted_input.move
		else:
			input_dir = _read_stick()
		stick = clampf(input_dir.length(), 0.0, 1.0)
		wish = _camera_wish(input_dir)
		if scripted_input != null and scripted_input.consume_a_pressed():
			_try_interact()
		elif scripted_input != null and scripted_input.consume_b_pressed():
			_try_pick_up()

	## `cast_rod` / `relax_rod` / `vib_rod`: `Movement_Base_Braking_common`, stick ignored.
	var rod_locked: bool = Fishing.holds(self)
	if rod_locked:
		wish = Vector3.ZERO
		stick = 0.0
		input_dir = Vector2.ZERO
	var sprint: bool = (
		scripted_input == null and not doors.is_demo_walking() and Input.is_action_pressed("sprint")
	)
	move_intent = wish * stick
	if _snowball != null:
		snowball.push_snowball(delta, wish, stick, sprint and not menu_open, input_dir, bg)
		if _snowball == null:
			_update_animation(delta)
		return
	_motor.position = global_position
	## `mEv_IsNotTitleDemo() && destiny == BAD_LUCK` gates the dash trip.
	_motor.bad_luck = scripted_input == null and Game.destiny() == Game.Destiny.BAD_LUCK
	## Recorded title-demo input and demo walks (`Player_actor_Movement_Demo_walk` steers
	## without the stick) count as held axes whenever they ask to move.
	if scripted_input != null or doors.is_demo_walking():
		_motor.axes_active = stick > 0.0
	else:
		_motor.axes_active = _axes_active(input_dir)
	_feed_clip_state()
	var planar: Vector3
	if net.is_active():
		planar = net.tick_net(delta, input_dir, wish, stick, menu_open)
	else:
		planar = _motor.tick(
			delta, wish, stick, sprint and not menu_open, _busy or menu_open or rod_locked
		)
	planar += _tick_recoil(delta)
	velocity.x = planar.x
	velocity.z = planar.z
	fishing.face_bobber(delta)
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
	_update_ripples(delta, bg)
	_update_focus()
	_tick_tree_bump(delta)
	doors.clear_auto_enter_block()
	_try_auto_enter()


## `SetAngleSpeedF_Reflect_scoop` / `_Reflect_axe`: knocked back at `speed_gx` (GX per
## frame) the way the player faces, braking 0.32625 a tick (`Movement_axe_common`).
func recoil(speed_gx: float) -> void:
	_recoil_speed = speed_gx
	_recoil_yaw = _motor.facing + PI


func _tick_recoil(delta: float) -> Vector3:
	if _recoil_speed <= 0.0:
		return Vector3.ZERO
	var v: float = _recoil_speed * 0.5 * FieldCatalog.GX_TO_METERS * DecompTime.TICK_HZ
	_recoil_speed = maxf(_recoil_speed - RECOIL_BRAKE * delta * DecompTime.TICK_HZ, 0.0)
	return Vector3(sin(_recoil_yaw), 0.0, cos(_recoil_yaw)) * v


## `Player_actor_CorrectWadeBlockBorder` then `Player_actor_Set_ScrollDemo_forWade` (walk /
## run / dash only): stay inside this acre unless the stick takes the player across.
func _acre_border(before: Vector3, input_dir: Vector2, bg: Array) -> void:
	var old_gx: Vector3 = TownSpace.world_to_gx(before)
	var now_gx: Vector3 = TownSpace.world_to_gx(global_position)
	var inset: float = AcreWade.INTRO_INSET_GX if intro_block_bg_check else 0.0
	var wall_inset: float = inset if _is_player_house_block(TownSpace.block_of(old_gx)) else 0.0
	var held: Vector3 = AcreWade.confine(old_gx, now_gx, wall_inset)
	if held.x != now_gx.x or held.z != now_gx.z:
		var back: Vector3 = TownSpace.gx_to_world(held)
		global_position.x = back.x
		global_position.z = back.z
		_snap_to_bg()
	if _busy or _menu_open() or _motor.gait() == PlayerLocomotion.Gait.WAIT:
		return
	var pos_gx: Vector3 = TownSpace.world_to_gx(global_position)
	## `Player_actor_request_proc_index_fromDemo_walk` → `Set_ScrollDemo_forDemo_wade`; the
	## demo walk picks up again after the 36-tick wade (`fromDemo_wade`).
	if doors.is_demo_walking():
		if _motor.planar_speed > 0.0:
			var block: Vector2i = TownSpace.block_of(pos_gx)
			var demo_dir: AcreWade.Dir = AcreWade.demo_direction(
				pos_gx, _motor.facing, func(d: AcreWade.Dir) -> bool: return AcreWade.scroll_ok(block, d)
			)
			if demo_dir != AcreWade.Dir.NONE:
				_begin_wade(pos_gx, demo_dir)
		return
	var dir: AcreWade.Dir = AcreWade.direction(
		pos_gx,
		_motor.facing,
		Vector2(input_dir.x, -input_dir.y),
		func(d: AcreWade.Dir) -> bool: return _can_land(pos_gx, d, bg),
		inset,
		unable_wade,
	)
	if dir == AcreWade.Dir.NONE:
		return
	if unable_wade:
		wade_cancelled.emit()
		return
	_begin_wade(pos_gx, dir)


## `mFI_BkNum2BlockKind(bx, bz) & mRF_BLOCKKIND_PLAYER` — the four house plots' acre.
func _is_player_house_block(block: Vector2i) -> bool:
	return block == WorldGenerator.PLAYER_HOUSE_BLOCK


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
		var clear: float = AcreWade.NPC_CLEAR
		for npc: Node in get_tree().get_nodes_in_group("villagers"):
			if npc is Node3D and (npc as Node3D).global_position.distance_to(probe) < clear:
				return false
	return true


func _begin_wade(pos_gx: Vector3, dir: AcreWade.Dir) -> void:
	var end: Vector3 = TownSpace.gx_to_world(AcreWade.end_pos(pos_gx, dir))
	end.y = global_position.y
	_wade = {"start": global_position, "end": end, "t": 0.0, "dir": dir}
	Game.notify_wade_start()
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
	var t: float = float(_wade["t"]) + delta * DecompTime.TICK_HZ
	## `Player_actor_ChangeFace_for_Wade`: on tick 18 of the crossing the tan catches up.
	if float(_wade["t"]) < 18.0 and t >= 18.0 and Sunburn.settle(Game.resident.sunburn, Clock.day_number()):
		_apply_face()
	_wade["t"] = t
	var start: Vector3 = _wade["start"]
	var end: Vector3 = _wade["end"]
	var p: float = AcreWade.percent(minf(t, AcreWade.TICKS))
	global_position = Vector3(
		lerpf(start.x, end.x, p), global_position.y, lerpf(start.z, end.z, p)
	)
	_snap_to_bg()
	_mesh.rotation.y = _motor.facing
	var ball: Variant = _wade.get("ball")
	if ball != null and is_instance_valid(ball):
		(ball as Node3D).call("carry_to", global_position + (_wade["ball_ofs"] as Vector3))
	if t > AcreWade.TICKS:
		_wade = {}


## `{start, end, t}` while wading (for the camera), else empty.
func wade_state() -> Dictionary:
	return _wade


## `mPlayer_INDEX_SHOCK` (`aMR_RequestPlayerBikkuri`): the first roach of the session makes the
## player jump — a beat, then `gaaan1`, facing north.
func request_surprise() -> void:
	if _busy:
		await get_tree().create_timer(0.3).timeout
	_busy = true
	var yaw: float = WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
	_motor.reset(yaw)
	_mesh.rotation.y = yaw
	await get_tree().create_timer(20.0 / DecompTime.TICK_HZ).timeout
	_play_grip_clip("ply_1_gaaan1", false)
	await get_tree().create_timer(44.0 / DecompTime.TICK_HZ).timeout
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	play_wait_idle()


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


## `Player_actor_Movement_Talk`: ease toward the NPC.
func _tick_talk_face(delta: float) -> void:
	if not is_talk_facing():
		return
	var target: float = TalkCamera.face_yaw_toward(global_position, _talk_face.global_position)
	_motor.facing = PlayerLocomotion.ease_turn(_motor.facing, target, delta)


func _bg() -> Array:
	if get_tree() == null:
		return []
	var world := World.find(get_tree())
	if world == null:
		return []
	var data: Variant = world.layout
	var grid: Variant = world.grid
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
		bg[0] as WorldData, bg[1] as WorldGrid, global_position, 0.0, not doors.door_entering
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
		or _group_open("design_album_ui")
		or _group_open("name_entry_ui")
	)


func _group_open(group: String) -> bool:
	if get_tree() == null:
		return false
	var ui: Node = get_tree().get_first_node_in_group(group)
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func _unhandled_input(event: InputEvent) -> void:
	if scripted_input != null or _busy or _menu_open() or doors.is_demo_walking() or net.is_active():
		return
	if event.is_action_pressed("interact"):
		if furniture.try_grip():
			get_viewport().set_input_as_handled()
			return
		_try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pick_up"):
		_try_pick_up()
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
	_motor.clip_done = not _anim.is_playing()
	_motor.clip_frame = _anim.current_animation_position * DecompTime.FRAME_HZ


## Frame marks written into the body's clips: each action's SE (`PlayerSe.CLIP_MARKS`) and
## `Player_actor_SetEffect_Tumble`'s rumble at frame 10, landing dust at 15 and body print
## at 17, on every tumble clip.
## `Player_actor_SetEffectHit_Fill_scoop`: clods at frames 13, 19 and 25 and the scoop's
## dirt at 40 (seven later on `FILL_UP_I1`). The fill clips are only ever a fill.
const FILL_MARKS: Array = [[13.0, &"fx_fill_3"], [19.0, &"fx_fill_4"], [25.0, &"fx_fill_5"], [40.0, &"fx_fill_scoop"]]
## `Player_actor_SetEffectStart_axe_common` (frame 12, every swing) and the bounce's stars
## (`SetEffectHit_Reflect_axe`, frame 15). The axe clips are only ever the axe.
## `Player_actor_main_Gaaan` → `eEC_EFFECT_SHOCK` at frame 5 of the startle.
const SHOCK_MARKS: Array = [[5.0, &"fx_shock"]]
const AXE_MARKS: Dictionary = {
	&"ply_1_axe_swing1": [[12.0, &"fx_axe_start"]],
	&"ply_1_axe_suka1": [[12.0, &"fx_axe_start"]],
	&"ply_1_axe_hane1": [[12.0, &"fx_axe_start"], [15.0, &"fx_axe_bounce"]],
}


func _clip_marks() -> Dictionary:
	var marks: Dictionary = PlayerSe.CLIP_MARKS.duplicate(true)
	for clip: String in [ToolUse.ANIM_KOKERU, ToolUse.ANIM_KOKERU_A, ToolUse.ANIM_KOKERU_N]:
		marks[StringName(clip)] = TUMBLE_MARKS
	var gaaan: Array = (marks.get(&"ply_1_gaaan1", []) as Array).duplicate()
	gaaan.append_array(SHOCK_MARKS)
	marks[&"ply_1_gaaan1"] = gaaan
	for clip: StringName in AXE_MARKS:
		var axe_list: Array = (marks.get(clip, []) as Array).duplicate()
		axe_list.append_array(AXE_MARKS[clip])
		marks[clip] = axe_list
	for pair: Array in [[&"ply_1_fill_up1", 0.0], [&"ply_1_fill_up_i1", 7.0]]:
		var list: Array = (marks.get(pair[0], []) as Array).duplicate()
		for mark: Array in FILL_MARKS:
			list.append([float(mark[0]) + float(pair[1]), mark[1]])
		marks[pair[0]] = list
	return marks


func _on_clip_event(_clip: StringName, event: StringName) -> void:
	match event:
		&"tumble_rumble":
			GameConfig.rumble(GameConfig.TUMBLE)
		&"fx_shock":
			feel.play(&"shock")
		&"fx_axe_start":
			FootstepEffects.axe_start(_bg(), global_position, _motor.facing)
		&"fx_axe_bounce":
			FootstepEffects.axe_bounce(_bg(), global_position, _motor.facing)
		&"fx_fill_3", &"fx_fill_4", &"fx_fill_5", &"fx_fill_scoop":
			var ctx: InteractionContext = _make_context()
			var grid: WorldGrid = ctx.world.get("grid") as WorldGrid if ctx.world != null else null
			if grid == null:
				return
			var bg: Array = _bg()
			var hole: Vector3 = grid.cell_to_world(ToolUse.facing_cell(ctx))
			hole.y = global_position.y
			var attr: int = FootstepEffects.attr_at(bg, hole)
			if event == &"fx_fill_scoop":
				FootstepEffects.dig_scoop(bg, hole, global_position, _motor.facing, attr, 2)
			else:
				FootstepEffects.dig_hole(bg, hole, global_position, _motor.facing, attr, int(String(event).right(1)))
		&"tumble_dust", &"tumble_print":
			var bg: Array = _bg()
			var attr: int = _unit_attr(bg)
			if event == &"tumble_dust":
				FootstepEffects.tumble(bg, global_position, _motor.facing, attr, 1)
			else:
				FootstepEffects.body_print(bg, global_position, _motor.facing, attr)
		_:
			Audio.play_se(event, self)


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
	if tools.tool_swap or net.is_active():
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
		if not doors.door_entering and not _cutscene_driven and not _anim.is_playing():
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
	var blend: float = MORPH_12 if prev == PlayerLocomotion.Gait.TURN_DASH else MORPH_5
	## Walk ↔ run ↔ dash keep the current keyframe (`frame = current_frame`), which the
	## tree's synced gait transition does; wait → walk and every other start restart at
	## frame 1.
	if GAIT_STATES.has(next) and clip == _anim.gait_clips.get(GAIT_STATES[next], ""):
		_ensure_loop(clip)
		_anim.play_gait(GAIT_STATES[next], _anim_speed(next), blend)
		return
	if one_shot:
		var once: Animation = _anim.get_animation(clip)
		if once != null:
			once.loop_mode = Animation.LOOP_NONE
	else:
		_ensure_loop(clip)
	_anim.speed_scale = _anim_speed(next)
	_anim.play(clip, blend)


## Mode entry side effects: skid SE + `TURN_ASIMOTO`, tumble SE + `TUMBLE` (arg 0), and the
## skid's `TURN_FOOTPRINT` at the right foot when it settles into wait.
func _on_mode_entered(prev: PlayerLocomotion.Gait, next: PlayerLocomotion.Gait) -> void:
	var bg: Array = _bg()
	var attr: int = _unit_attr(bg)
	match next:
		PlayerLocomotion.Gait.TURN_DASH:
			Audio.play_se(SE_SLIP, self)
			FootstepEffects.turn(bg, global_position, _motor.facing, attr, 0)
		PlayerLocomotion.Gait.TUMBLE:
			Audio.play_se(_tumble_se(attr), self)
			FootstepEffects.tumble(bg, global_position, _motor.facing, attr, 0)
	if prev == PlayerLocomotion.Gait.TURN_DASH:
		var foot: Transform3D = _foot_anchor(true)
		var at: Vector3 = foot.origin if foot.basis.determinant() != 0.0 else global_position
		FootstepEffects.turn_footprint(bg, at, _motor.facing, attr)


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


## `Player_actor_set_ripple` → `eWait_Asimoto_init`: in the surf or the sea, a small ring
## (`TURI_HAMON` 3) at alternate feet every eight ticks, moving or not.
func _update_ripples(delta: float, bg: Array) -> void:
	if bg.size() != 2 or Game.is_indoors():
		return
	_ripple_time += delta
	if _ripple_time < RIPPLE_SECONDS - 0.0001:
		return
	_ripple_time = 0.0
	_ripple_right = not _ripple_right
	var attr: int = FieldCollision.unit_attr_at(bg[0] as WorldData, bg[1] as WorldGrid, global_position)
	if attr != FootstepEffects.ATTR_WAVE and not FieldCatalog.is_sea_attr(attr):
		return
	var anchor: Transform3D = _foot_anchor(_ripple_right)
	var foot: Vector3 = anchor.origin if anchor.basis.determinant() != 0.0 else global_position
	FootstepEffects.ripple(Vector3(foot.x, global_position.y, foot.z), 3)


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
	var marks: Footprints = Footprints.find(get_tree())
	if marks == null:
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
	marks.spawn(xform, snow)
	## `eFootPrint_ct` / `_mv`: a print in the surf rings the water as it is made and again
	## ten ticks later.
	if attr == FootstepEffects.ATTR_WAVE:
		var at := Vector3(foot.x, global_position.y, foot.z)
		FootstepEffects.ripple(at, 2)
		get_tree().create_timer(10.0 / DecompTime.TICK_HZ).timeout.connect(func() -> void: FootstepEffects.ripple(at, 2))


## `Player_actor_SetEffect_Walk` / `_Dash`: `WALK_ASIMOTO` on walk + run foot plants,
## `DASH_ASIMOTO` on dash ones — unless 1 in 4 dash plants on a flower tramples it
## (`SetEffectRemoveFlower_Dash` → `HANATIRI` instead).
func _step_effects(gait: PlayerLocomotion.Gait, bg: Array, attr: int, foot: Vector3, yaw: float) -> void:
	if gait == PlayerLocomotion.Gait.DASH:
		var grid := bg[1] as WorldGrid
		if randi() % 4 == 0:
			var cell: Vector2i = grid.world_to_cell(global_position)
			var flower: int = FootstepEffects.flower_index(global_position)
			var world := World.find(get_tree())
			if PlantGrowth.trample_flower(world, grid, cell):
				## `mFI_Wpos2UtCenterWpos`: petals burst from the unit centre.
				var center: Vector3 = grid.cell_corner(cell) + Vector3(grid.cell_size, 0.0, grid.cell_size) * 0.5
				center.y = global_position.y
				FootstepEffects.hanatiri(bg, center, flower)
				return
		FootstepEffects.dash_step(bg, foot, yaw, attr)
	else:
		FootstepEffects.walk_step(bg, foot, yaw, attr)


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


func _tumble_clip(getup: bool) -> String:
	return ToolUse.tumble_clip(tools.equipped_tool(), getup)


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
	if hit == null or hit.action == null:
		## Nothing for A: show what B would pick up.
		hit = _query_focus(true)
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


func _query_focus(pickup: bool = false) -> InteractionQuery:
	if _probe == null:
		return null
	return InteractionQuery.best_in_areas(
		_probe.get_overlapping_areas(),
		_motor.facing_point(global_position, INTERACT_REACH),
		_make_context(),
		pickup
	)


func _resolve_interact() -> InteractionQuery:
	return ToolUse.resolve(_query_focus(), _make_context())


func _make_context() -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.actor = self
	ctx.inventory = Game.inventory
	var tree := get_tree()
	if tree != null:
		ctx.world = World.find(tree)
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
	if net.net_swing.state != NetSwing.State.NONE:
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
	if hit.host == null and hit.action.id == Interaction.SWING_NET:
		net.begin_net()
		return
	await _run_interact(hit)


## B (`Player_actor_CheckAndRequest_main_pickup_all`): ground items, weeds, signboards and
## furniture. A never picks anything up.
func _try_pick_up() -> void:
	if _motor.gait() in [PlayerLocomotion.Gait.TUMBLE, PlayerLocomotion.Gait.TUMBLE_GETUP]:
		return
	if net.net_swing.state != NetSwing.State.NONE or Fishing.holds(self):
		return
	var hit: InteractionQuery = _query_focus(true)
	if hit == null or hit.action == null:
		return
	if scripted_input != null and not TitleDemo.allows_verb(hit.action.id):
		return
	await _run_interact(hit)


func _try_auto_enter() -> void:
	## Museum walk-in (`aMsm_check_player`): no A press while open.
	if scripted_input != null or _busy or doors.door_entering or _menu_open() or net.is_active():
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
		await hit.run(ctx)
	else:
		ToolUse.apply_field(hit.action, ctx)
	var spent: float = float(Time.get_ticks_msec() - t0) / 1000.0
	if Fishing.take_cut_swing():
		tail = 0.0
	await _finish_action(maxf(0.0, tail - spent))
	await fishing.play_reel()
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
	HeldTool.play(HeldTool.find_skeleton(_mesh), tools.tool_use_anim, false)
	_anim.play(clip, 0.08)
	if effect_frame < 0.0:
		await _anim.animation_finished
		HeldTool.play(HeldTool.find_skeleton(_mesh), tools.tool_hold_anim, true)
		return 0.0
	## The pipeline samples `cKF_ba_r_*` at 30 fps, so a decomp frame number is that frame
	## over 30 in clip time. Timed rather than signalled: the tail has to be waited out after
	## the effect has already been applied, and there is no second `animation_finished`.
	var res: Animation = _anim.get_animation(clip)
	var length: float = res.length if res != null else 0.0
	var mark: float = minf(effect_frame / DecompTime.FRAME_HZ, length)
	if mark > 0.0:
		await get_tree().create_timer(mark).timeout
	return maxf(0.0, length - mark)


## Lets the rest of a split action clip play out before the reel takes over.
func _finish_action(tail: float) -> void:
	if tail <= 0.0:
		return
	await get_tree().create_timer(tail).timeout
	HeldTool.play(HeldTool.find_skeleton(_mesh), tools.tool_hold_anim, true)


## `Player_actor_setup_main_Mail_jump`: `CONFIRM1` while sliding onto `to` and turning to
## `yaw` over its first 8 frames; the clip holds its last frame while the box is open.
func mail_jump(to: Vector3, yaw: float) -> void:
	var from: Vector3 = global_position
	var from_yaw: float = _motor.facing
	_motor.reset(from_yaw)
	_play_body_once(ANIM_CONFIRM)
	var hop := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	hop.tween_method(
		func(k: float) -> void:
			global_position = Vector3(lerpf(from.x, to.x, k), global_position.y, lerpf(from.z, to.z, k))
			set_facing(lerp_angle(from_yaw, yaw, k)),
		0.0, 1.0, MAIL_JUMP_SEC
	)
	await hop.finished
	_motor.reset(yaw)


## `Player_actor_setup_main_Throw_money` → `_Pray`: step onto `to` turned to `yaw` over 5
## frames, toss the coin (`SAISEN1`: the purse rustles at keyframe 9, the coin flies at
## 33), then pray (`OMAIRI_US1`). `toss` false is a wish without money: the prayer only.
func shrine_visit(to: Vector3, yaw: float, toss: bool, base_y: float) -> void:
	_busy = true
	var from: Vector3 = global_position
	var from_yaw: float = _motor.facing
	_motor.reset(from_yaw)
	var elapsed: float = 0.0
	if toss:
		_play_body_once(ANIM_SAISEN)
	else:
		_play_body_once(ANIM_OMAIRI)
	var rustled: bool = false
	var thrown: bool = false
	while is_inside_tree():
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var k: float = clampf(elapsed / SHRINE_STEP_SEC, 0.0, 1.0)
		global_position = Vector3(lerpf(from.x, to.x, k), global_position.y, lerpf(from.z, to.z, k))
		set_facing(lerp_angle(from_yaw, yaw, k))
		if toss and not rustled and elapsed >= SHRINE_RUSTLE_SEC:
			rustled = true
			Audio.play_se(&"coin_gasagoso", self)
		if toss and not thrown and elapsed >= SHRINE_THROW_SEC:
			thrown = true
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			WellCoin.toss(get_parent(), global_position, base_y, rng)
		if _anim == null or not _anim.is_playing():
			break
	_motor.reset(yaw)
	if toss:
		_play_body_once(ANIM_OMAIRI)
		while is_inside_tree() and _anim != null and _anim.is_playing():
			await get_tree().process_frame
	play_wait_idle()
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT


## `Player_actor_setup_main_Mail_land`: `CONFIRM1` again at half speed as the box shuts,
## then the wait.
func mail_land() -> void:
	_play_body_once(ANIM_CONFIRM)
	if _anim == null:
		return
	_anim.speed_scale = 0.5
	var clip: StringName = _anim.current_animation
	while is_inside_tree() and _anim.is_playing() and _anim.current_animation == clip:
		await get_tree().process_frame
	_anim.speed_scale = 1.0
	if is_inside_tree() and not _anim.is_playing():
		play_wait_idle()


## `mTG_release_proc` → `setup_main_Release_creature`: a bug from the pockets is let go
## 7 GX ahead and 13 up and flies off; a fish is thrown at `water` (`ac_gyo_release`).
## Then the player stands and watches it go.
func release_from_pocket(data: ItemData, water: Variant) -> void:
	if data == null or _busy:
		return
	var freed: Object = null
	var yaw: float = _motor.facing
	if data is BugData:
		var field: BugField = Netting.field_of(_make_context())
		var bug := data as BugData
		var habitat: BugData.Habitat = (bug.habitats[0] as BugData.Habitat) if not bug.habitats.is_empty() else BugData.Habitat.FLYING
		var at: Vector3 = global_position + Vector3(
			sin(yaw) * CreatureRelease.BUG_AHEAD_GX, CreatureRelease.BUG_UP_GX, cos(yaw) * CreatureRelease.BUG_AHEAD_GX
		) * FieldCatalog.GX_TO_METERS
		freed = field.spawn(bug, habitat, at, true) if field != null else null
	elif data is FishData and water != null:
		var host: Node = get_parent() if get_parent() != null else self
		freed = FishRelease.throw(host, data as FishData, global_position, water as Vector3)
	_busy = true
	await _watch_release(freed, HeldTool.find_skeleton(_mesh))
	_motor.reset(_motor.facing)
	_motor.mode_changed = true
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT


## `main_Release_creature`: `WAIT1` for 84 ticks while the head follows what was let go
## for the first 60 (`Player_actor_Look_Release_creature`); it snaps back as the wait ends.
func _watch_release(target: Object, skeleton: Skeleton3D) -> void:
	var look := PlayerHeadLook.new()
	look.bind(skeleton, _anim)
	_play_body_loop(StringName(ANIM_WAIT))
	var elapsed: float = 0.0
	while elapsed < RELEASE_SECONDS and is_inside_tree():
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		var want := Vector2.ZERO
		var at: Variant = _release_target_pos(target)
		if elapsed <= RELEASE_LOOK_SECONDS and at != null:
			want = PlayerHeadLook.want(global_position + Vector3(0.0, PlayerHeadLook.EYE, 0.0),
				_motor.facing, at as Vector3)
		look.body_yaw = _motor.facing
		look.step(want, delta)
	look.angle = Vector2.ZERO
	look.unbind()


## Where the released thing is now, or null once it is gone (`insect_flags.destruct`).
static func _release_target_pos(target: Variant) -> Variant:
	## A thrown fish frees itself in the water: test before anything reads its class.
	if not is_instance_valid(target):
		return null
	if target is BugActor:
		return null if (target as BugActor).f_destruct else (target as BugActor).position
	if target is FishRelease:
		var thrown := target as FishRelease
		return thrown.global_position if thrown.exist and thrown.is_inside_tree() else null
	if target is Node3D and (target as Node3D).is_inside_tree():
		return (target as Node3D).global_position
	return null


## `mPlayer_INDEX_DEMO_GET_GOLDEN_ITEM(2)`: the golden tool held up in the hand with
## `YATTA1`, turning to face the camera, and 42 frames in the player's own green report
## ("YESSSSS!!!!! I got the Golden Rod!", 0x306D–0x306F); then back to waiting with the
## equipped tool again. Tortimer's golden rod / net visit and the well spirit's axe end here.
const GOLDEN_YATTA := &"ply_1_yatta1"
const GOLDEN_REPORT_SEC := 42.0 / DecompTime.FRAME_HZ
const GOLDEN_WINDOW := Color8(185, 245, 80)
const GOLDEN_MSG: Dictionary = {&"golden_net": 0x306D, &"golden_fishing_rod": 0x306E, &"golden_axe": 0x306F}
## `Player_actor_sound_Get_bgm_num_forDemoGetGoldenItem`: `BGM_ALL_INSECTS`, `BGM_ALL_FISH`,
## `BGM_INTRO_CHORES_COMPLETE`, else `BGM_DEBT_PAID`.
const GOLDEN_FANFARE: Dictionary = {&"golden_net": 0x4B, &"golden_fishing_rod": 0x4C, &"golden_axe": 0x49}
const GOLDEN_FANFARE_OTHER := 0x4A


func get_golden_item(item_id: StringName) -> void:
	if _busy or not is_inside_tree():
		return
	_busy = true
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	var tool := ItemCatalog.get_item(item_id) as ToolData
	HeldTool.unbind(skeleton)
	if tool != null and tool.visual_id != &"":
		HeldTool.bind(skeleton, tool.visual_id)
		## Only the net has a clip of its own for this (`yatta_m1`); other tools just stay put.
		HeldTool.play(skeleton, Netting.TOOL_YATTA, false)
	_play_body_once(GOLDEN_YATTA)
	var jingle: StringName = BgmCatalog.id_for_num(int(GOLDEN_FANFARE.get(item_id, GOLDEN_FANFARE_OTHER)))
	Audio.push_fanfare(jingle)
	var elapsed: float = 0.0
	while elapsed < GOLDEN_REPORT_SEC and is_inside_tree():
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		## The turn steps once per 30 fps frame here: half the rate of the tick-stepped turns.
		_motor.facing = PlayerLocomotion.ease_turn(_motor.facing, Netting.SHOW_YAW, delta * 0.5)
		_mesh.rotation.y = _motor.facing
	var ui: DialogueOverlay = DialogueOverlay.find(get_tree()) if is_inside_tree() else null
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % int(GOLDEN_MSG.get(item_id, 0x3070))))
	if ui != null and data != null:
		var ctx := DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.window_color = GOLDEN_WINDOW
		ui.play(data, ctx)
		await _net_wait_closed(ui)
	Audio.pop_fanfare(jingle)
	if not is_inside_tree():
		return
	_motor.reset(_motor.facing)
	_motor.mode_changed = true
	tools.bind_equipped_tool(not tools.tool_hidden())
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	_update_focus()


## `mPlayer_INDEX_BROKEN_AXE`: the axe gave out on the last swing. `AXE_BREAK1`, then
## `AXE_BREAKWAIT1`; 80 frames on the report (0x3067) opens in its lilac window. The
## halves fly off at frame 15 (`BrokenAxePiece`).
func broken_axe() -> void:
	while _busy and is_inside_tree():
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	_busy = true
	HeldTool.unbind(HeldTool.find_skeleton(_mesh))
	_play_body_once(AxeWear.ANIM_BREAK)
	var elapsed: float = 0.0
	var waiting: bool = false
	var thrown: bool = false
	while elapsed < AxeWear.REPORT_DELAY_FRAMES / DecompTime.FRAME_HZ and is_inside_tree():
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		## `Player_actor_SetEffect_Broken_axe`: the halves fly at frame 15.
		if not thrown and elapsed >= AxeWear.PIECES_FRAME / DecompTime.FRAME_HZ:
			thrown = true
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			BrokenAxePiece.spawn_pair(get_parent(), global_position, facing_yaw(), rng)
		if not waiting and _anim != null and not _anim.is_playing():
			waiting = true
			_play_body_loop(AxeWear.ANIM_BREAK_WAIT)
	var ui: DialogueOverlay = DialogueOverlay.find(get_tree()) if is_inside_tree() else null
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % AxeWear.MSG_BROKEN))
	if ui != null and data != null:
		var ctx := DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.window_color = AxeWear.BROKEN_WINDOW
		ui.play(data, ctx)
		await _net_wait_closed(ui)
	if not is_inside_tree():
		return
	_motor.reset(_motor.facing)
	_motor.mode_changed = true
	tools.bind_equipped_tool(not tools.tool_hidden())
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	_update_focus()


func _play_body_loop(clip_name: StringName) -> void:
	if _anim == null:
		return
	var clip := _resolve_clip(String(clip_name))
	if clip.is_empty():
		return
	var res: Animation = _anim.get_animation(clip)
	if res != null:
		res.loop_mode = Animation.LOOP_LINEAR
	_anim.speed_scale = 1.0
	_anim.play(clip, MORPH_5)


func _play_body_once(clip_name: StringName) -> void:
	if _anim == null:
		return
	var clip := _resolve_clip(String(clip_name))
	if clip.is_empty():
		return
	var res: Animation = _anim.get_animation(clip)
	if res != null:
		res.loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	_anim.play(clip, MORPH_5)


## Opens one catch-report message (`mDemo_Set_msg_num`); 0xA4E names the insect.
func _net_say(ui: DialogueOverlay, msg: int, bug: BugData) -> void:
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg))
	var text: String = BugCatalog.catch_text(msg)
	if ui == null:
		Game.post_notice(text)
		return
	if data != null:
		var ctx := DialogueContext.from_game()
		ctx.item0 = bug.display_name if bug != null else ""
		ui.play(data, ctx)
	else:
		ui.say(text)


func _net_wait_closed(ui: DialogueOverlay) -> void:
	if ui != null and ui.is_open():
		await ui.closed


## `Player_actor_MessageControl_Notice_rod` opens the catch report once its 42 frames are up
## and holds `LockContinue` until the player advances it, so the pose stays on screen for as
## long as the text does. `_update_animation` bails while `_busy`, which is what keeps the
## last frame of `GET_T2` up rather than falling back to the idle.
## The text is the game's own: `Player_actor_Get_sakana_msg_num` gives a message number per
## species and the extracted bank has the line, pun and all. The rare three (stringfish,
## coelacanth, arapaima) run to two pages, which is why this plays a conversation through the
## runner instead of pushing a single string.
func _report_catch(
	catch_msg: int, pockets_full: bool = false, fish: FishData = null, completes_record: bool = false
) -> void:
	if catch_msg == 0:
		return
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % catch_msg))
	var fallback: String = FishCatalog.catch_text(catch_msg)
	if ui == null:
		Game.post_notice(fallback)
		return
	## 0x1349 names the fish (`mMsg_Set_item_str_art(win, mMsg_ITEM_STR0, …)`).
	var ctx := DialogueContext.from_game()
	ctx.item0 = fish.display_name if fish != null else ""
	if data != null:
		ui.play(data, ctx)
	else:
		ui.say(fallback)
	## `Player_actor_Notice_rod_demo_ct` → `settle_main_Notice_rod`: the catch jingle runs
	## under the report.
	var jingle: StringName = BgmCatalog.id_for_num(Netting.FANFARE_CATCH)
	Audio.push_fanfare(jingle)
	await ui.closed
	## `MessageControl_Notice_rod` states 1–2: the last fish of the page — "I've caught
	## them all!", then `YATTA2` as the jingle turns to the collection-complete one (0x4C).
	if completes_record:
		var all: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % ROD_COMPLETE_MSG))
		if all != null:
			ui.play(all, ctx)
		else:
			ui.say(FishCatalog.catch_text(ROD_COMPLETE_MSG))
		await ui.closed
		_play_body_once(Netting.ANIM_YATTA)
		Audio.pop_fanfare(jingle)
		jingle = BgmCatalog.id_for_num(ROD_COMPLETE_FANFARE)
		Audio.push_fanfare(jingle)
	if pockets_full:
		## "Swap" trades a pocket for the fish (`putaway_rod` → `mSM_IV_OPEN_EXCHANGE`).
		if await _ask_swap(POCKETS_FULL_MSG) and fish != null:
			await exchange_into_pockets(fish.id)
	Audio.pop_fanfare(jingle)


## A pockets-full question (Swap / let it go); true when "Swap" was taken.
func _ask_swap(msg_no: int) -> bool:
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg_no))
	if ui == null or data == null:
		return false
	var talk := BankTalk.Fixed.new(msg_no)
	var dctx := DialogueContext.from_game()
	dctx.speaker_name = ""
	talk.context = dctx
	ui.play(data, dctx, null, Callable(), talk)
	await ui.closed
	return talk.chosen == 0


## `mSM_IV_OPEN_EXCHANGE`: the pockets open, and the one picked goes on the ground in front
## to make room for `item_id`. False when nothing was picked or there's nowhere to put it.
func exchange_into_pockets(item_id: StringName) -> bool:
	var inv: Inventory = Game.inventory
	var data: ItemData = ItemCatalog.get_item(item_id)
	var world := World.find(get_tree())
	if inv == null or data == null or world == null or not (world.grid is WorldGrid):
		return false
	Game.request_quest_handover(-1, "take")
	var picked: Array = await Game.quest_handover_resolved
	var pocket: int = int(picked[1])
	var slot: InventorySlot = inv.slot_at(pocket) if pocket >= 0 else null
	if slot == null or slot.is_empty() or slot.item.count > 1:
		return false
	var grid: WorldGrid = world.grid
	var front: Vector2i = ToolUse.facing_cell(_make_context())
	var cell: Vector2i = FieldItems.drop_cell(grid, front, front - grid.world_to_cell(global_position))
	if cell.x < 0:
		return false
	var out: InventoryItem = inv.remove_from_slot(pocket, 1)
	inv.add(data, 1)
	FieldItems.put(world, cell, out.item_id, out.condition == InventoryItem.Condition.PRESENT)
	return true


## `COMPLETE_PAYMENT`: `YATTA1` facing the camera under the debt-paid (or chores-done) jingle,
## then "YESSSSS!!!" once 42 ticks are up.
const PAYMENT_MSG_HOUSE := 0x17B7
const PAYMENT_MSG_ARBEIT := 0x17B6
const PAYMENT_FANFARE_HOUSE := 0x4A
const PAYMENT_FANFARE_ARBEIT := 0x49
const PAYMENT_REPORT_TICKS := 42


func run_complete_payment() -> void:
	var kind: StringName = Game.complete_payment
	if kind == &"" or _busy:
		return
	Game.complete_payment = &""
	_busy = true
	_motor.facing = Netting.SHOW_YAW
	_mesh.rotation.y = Netting.SHOW_YAW
	_start_one_shot(GOLDEN_YATTA)
	var arbeit: bool = kind == Game.PAYMENT_ARBEIT
	var jingle: StringName = BgmCatalog.id_for_num(PAYMENT_FANFARE_ARBEIT if arbeit else PAYMENT_FANFARE_HOUSE)
	Audio.push_fanfare(jingle)
	await get_tree().create_timer(float(PAYMENT_REPORT_TICKS) / DecompTime.TICK_HZ).timeout
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % (PAYMENT_MSG_ARBEIT if arbeit else PAYMENT_MSG_HOUSE)))
	if ui != null and data != null:
		var dctx := DialogueContext.from_game()
		dctx.speaker_name = ""
		dctx.window_color = GOLDEN_WINDOW
		ui.play(data, dctx)
		await ui.closed
	Audio.pop_fanfare(jingle)
	_busy = false


## `GET_SCOOP` (`m_player_main_get_scoop`): the find comes up in the hand (`GET_D1`), the
## report and its jingle follow 86 ticks later, then `PUTAWAY_SCOOP`. Pockets full: "Swap"
## opens the pockets (`mSM_IV_OPEN_EXCHANGE`) and the pocket picked goes into the hole for
## it; otherwise the find goes back in (`PUTIN_SCOOP`).
func run_dig_get(item_id: StringName, banked: bool, cell: Vector2i, ctx: InteractionContext) -> void:
	_busy = true
	_start_one_shot(DigReport.ANIM_GET)
	var prop: HandOverItem = HandOverItem.spawn(get_parent(), item_id)
	if prop != null:
		prop.set_master(self)
		prop.begin_mode(HandOverItem.Mode.TRANS_WAIT)
	await get_tree().create_timer(float(DigReport.REPORT_TICKS) / DecompTime.TICK_HZ).timeout
	var talk := DigReport.new(item_id, banked)
	var ui := DialogueOverlay.find(get_tree())
	var jingle: StringName = BgmCatalog.id_for_num(DigReport.FANFARE)
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % DigReport.MSG_GOT))
	if ui != null and data != null:
		var dctx := DialogueContext.from_game()
		dctx.speaker_name = ""
		dctx.window_color = GOLDEN_WINDOW
		talk.context = dctx
		talk.prepare()
		Audio.push_fanfare(jingle)
		ui.play(data, dctx, null, Callable(), talk)
		await ui.closed
		Audio.pop_fanfare(jingle)
	if prop != null and is_instance_valid(prop):
		prop.finish()
	if not banked:
		await _dig_swap_or_bury(item_id, talk.swap, cell, ctx)
	_busy = false


## `PUTAWAY_SCOOP` with `submenu_flag` → the exchange pockets, or `PUTIN_SCOOP` with the find.
func _dig_swap_or_bury(item_id: StringName, swap: bool, cell: Vector2i, ctx: InteractionContext) -> void:
	if swap and Game.inventory != null:
		Game.request_quest_handover(-1, "take")
		var picked: Array = await Game.quest_handover_resolved
		var pocket: int = int(picked[1])
		if pocket >= 0:
			var out: InventoryItem = Game.inventory.remove_from_slot(pocket, Game.inventory.slot_at(pocket).item.count)
			var find: ItemData = ItemCatalog.get_item(item_id)
			if find != null:
				Game.inventory.add(find, 1)
			if out != null:
				BuriedUse.bury(ctx, cell, out.item_id)
			return
	BuriedUse.bury(ctx, cell, item_id)


## `Stung_mosquito` → `Notice_mosquito`: slap at the bite (`MOSQUITO1`), then scratch it
## (`MOSQUITO2`) turning to the camera under the "Yow!" report and the bee-stung jingle.
## Not while busy or in a demo (`Player_actor_Check_is_demo_mode`).
func run_stung_mosquito() -> void:
	if _busy or stung or in_pitfall or doors.door_entering or Game.title_demo_active:
		return
	stung = true
	_busy = true
	set_cutscene_driven(true)
	var clip: String = _start_one_shot(ANIM_MOSQUITO1)
	while _clip_running(clip):
		await get_tree().process_frame
	_start_one_shot(ANIM_MOSQUITO2)
	var turning := true
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % MOSQUITO_NOTICE_MSG))
	var prior_bgm: StringName = EventManager.demo_bgm
	EventManager.demo_bgm = &"bee_stung"
	Audio.play_bgm(&"bee_stung")
	if ui != null and data != null:
		var ctx: DialogueContext = DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.voice_mode = DialogueVoice.Mode.CLICK
		ctx.window_color = BEE_NOTICE_COLOR
		ui.play(data, ctx)
		while ui.is_open():
			await get_tree().process_frame
			if turning:
				_motor.facing = PlayerLocomotion.ease_turn(
					_motor.facing, Fishing.SHOW_YAW, get_process_delta_time()
				)
				_mesh.rotation.y = _motor.facing
	else:
		Game.post_notice("You got bitten by a mosquito!")
	EventManager.demo_bgm = prior_bgm if prior_bgm != &"bee_stung" else &""
	var world: World = World.find(get_tree())
	if world != null:
		world.call("_play_outdoor_bgm")
	set_cutscene_driven(false)
	play_wait_idle()
	_busy = false
	stung = false


## `m_player_main_wait`: the C-stick is logged while standing (the right stick, or I / J /
## K / L), and a finished pattern starts that exercise.
func _poll_radio_exercise(delta: float) -> void:
	if exercising:
		return
	var standing: bool = _motor.gait() == PlayerLocomotion.Gait.WAIT
	_radio.log_command(
		RadioExercise.direction(_c_stick()) if standing and _radio_able() else -1, delta
	)
	var start: int = _radio.step(standing, delta)
	if start >= 0:
		run_radio_exercise(start)


## `Player_actor_Check_AbleRadioExercise`: empty hands, and either the aerobics event on the
## shrine acre or (only when no such event runs) the aerobics radio playing in this room.
func _radio_able() -> bool:
	if Game.inventory != null and Game.inventory.equipment_id != &"":
		return false
	var manager := EventManager.find(get_tree())
	if manager != null and (manager.is_running(&"morning_aerobics") or manager.is_running(&"sports_fair_aerobics")):
		var bg: Array = _bg()
		if bg.is_empty():
			return false
		var cell: Vector2i = (bg[1] as WorldGrid).world_to_cell(global_position)
		return FieldCollision.acre_type_at(bg[0] as WorldData, cell) == TownFieldGenerator.T_SHRINE
	var session: IndoorSession = Game.interior_session
	return session != null and session.room != null \
		and FurnitureMusic.active_bgm(session.room) == FurnitureMusic.AEROBICS_BGM


## The GameCube C-stick, y up: the right stick, or I / J / K / L.
func _c_stick() -> Vector2:
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var keys := Vector2(
		float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J)),
		float(Input.is_physical_key_pressed(KEY_I)) - float(Input.is_physical_key_pressed(KEY_K))
	)
	if keys != Vector2.ZERO:
		return keys.normalized()
	return v


## `Radio_exercise`: play the move at its speed, keep logging the stick, and from 24 frames
## before the end pick up the next move; one waiting when the clip ends follows straight on.
func run_radio_exercise(cmd: int) -> void:
	if exercising or cmd < 0 or cmd >= RadioExercise.CLIPS.size():
		return
	exercising = true
	_busy = true
	set_cutscene_driven(true)
	while cmd >= 0:
		_radio.begin()
		var clip: String = _start_one_shot(RadioExercise.CLIPS[cmd], 0.12)
		if clip.is_empty():
			break
		## cKF frames per tick → clip rate (the bake runs at 30 fps = 0.5 per tick).
		_anim.speed_scale = RadioExercise.SPEED[cmd] / 0.5
		var length: float = _clip_length(clip)
		while _clip_running(clip):
			await get_tree().process_frame
			var delta: float = get_process_delta_time()
			var left_frames: float = (length - _anim.current_animation_position) * DecompTime.FRAME_HZ
			_radio.log_command(RadioExercise.direction(_c_stick()) if _radio_able() else -1, delta)
			## The next exercise can be queued in the last 24 keyframes.
			if left_frames <= 24.0:
				_radio.step(false, delta)
		cmd = _radio.pending if _radio.pending >= 0 and _radio.pending_timer <= 0.0 else -1
	_anim.speed_scale = 1.0
	set_cutscene_driven(false)
	play_wait_idle()
	_busy = false
	exercising = false


## `Player_actor_check_pitfall` (walk / run / wait states): standing within 19 GX of the
## centre of a unit holding a buried pitfall springs it.
func _poll_pitfall() -> void:
	if in_pitfall:
		return
	var bg: Array = _bg()
	if bg.is_empty():
		return
	var grid := bg[1] as WorldGrid
	var cell: Vector2i = grid.world_to_cell(global_position)
	if not grid.is_in_bounds(cell) or not BuriedUse.is_pitfall(grid.occupant_at(cell)):
		return
	var center: Vector3 = grid.cell_corner(cell) + Vector3(grid.cell_size, 0.0, grid.cell_size) * 0.5
	var reach: float = BuriedUse.PITFALL_REACH
	if Vector2(center.x - global_position.x, center.z - global_position.z).length() > reach:
		return
	center.y = global_position.y
	run_pitfall(cell, center)


## The pitfall states. `GURATUKU1` totters onto the pit centre, `OTIRU1` drops in,
## `MOGAKU1` struggles until A presses and stick wiggles add up to 20 (faster struggling
## speeds the clip up), then `DERU1` climbs out as the pit closes behind. The original moves
## the actor by each clip's root (`AnimationMove`); here the drop rides on the mesh pivot.
func run_pitfall(cell: Vector2i, center: Vector3) -> void:
	if in_pitfall:
		return
	in_pitfall = true
	var was_busy: bool = _busy
	_busy = true
	set_cutscene_driven(true)
	var world := World.find(get_tree())
	var grid: WorldGrid = world.grid if world != null else null
	BuriedUse.spring_pitfall(world, grid, cell)
	var start: Vector3 = global_position
	var clip: String = _start_one_shot(ANIM_GURATUKU1)
	var length: float = _clip_length(clip)
	var t: float = 0.0
	while _clip_running(clip):
		await get_tree().process_frame
		t += get_process_delta_time()
		global_position = start.lerp(center, clampf(t / maxf(length, 0.001), 0.0, 1.0))
	global_position = center
	clip = _chain_clip(ANIM_OTIRU1)
	while _clip_running(clip):
		await get_tree().process_frame
	_chain_clip(ANIM_MOGAKU1, true)
	await _struggle()
	## `setup_main_Climbup_pitfall` → `pit_exit_proc`.
	BuriedUse.close_pit(world, cell)
	clip = _chain_clip(ANIM_DERU1)
	while _clip_running(clip):
		await get_tree().process_frame
	_mesh.position = Vector3.ZERO
	var wait := _resolve_clip(ANIM_WAIT)
	if _anim != null and not wait.is_empty():
		_gait = PlayerLocomotion.Gait.WAIT
		_anim.speed_scale = 1.0
		_anim.play(wait, 0.0)
	set_cutscene_driven(false)
	_busy = was_busy
	in_pitfall = false
	struggle_assist = 0.0


## `Struggle_pitfall`: count A presses and stick motion until 20, easing the clip speed
## toward a target that presses raise and time lowers (0.5–1.0).
func _struggle() -> void:
	var presses: float = 0.0
	var target: float = STRUGGLE_SPEED_MIN
	var speed: float = STRUGGLE_SPEED_MIN
	var old_stick := Vector2.ZERO
	while presses < STRUGGLE_PRESSES:
		await get_tree().process_frame
		var ticks: float = get_process_delta_time() * DecompTime.TICK_HZ
		var stick: Vector2 = _read_stick() if scripted_input == null else scripted_input.move
		var add: float = 1.0 if Input.is_action_just_pressed("interact") and not _menu_open() else 0.0
		add += absf(old_stick.length() - stick.length()) * 0.5
		if old_stick.length() > 0.0 and stick.length() > 0.0:
			## `s16` move-angle change × 0.00002.
			add += absf(wrapf(stick.angle() - old_stick.angle(), -PI, PI)) * 65536.0 / TAU * 0.00002
		add += struggle_assist * ticks
		old_stick = stick
		presses += add
		## Presses raise the target clip speed; it sags `STRUGGLE_SPEED_DECAY` a tick, and the
		## speed eases `STRUGGLE_SPEED_EASE` of the way to it a tick.
		target = clampf(target + add * 0.25 - STRUGGLE_SPEED_DECAY * ticks, STRUGGLE_SPEED_MIN, 1.0)
		speed = lerpf(speed, target, 1.0 - pow(1.0 - STRUGGLE_SPEED_EASE, ticks))
		if _anim != null:
			_anim.speed_scale = speed
	if _anim != null:
		_anim.speed_scale = 1.0


## Start `leaf` from the pose the last clip ended in: whatever joint_0 travelled is handed to
## the mesh pivot so the body does not jump (`cKF_SkeletonInfo_R_AnimationMove_dt`).
func _chain_clip(leaf: String, loop: bool = false) -> String:
	var before: Vector3 = _root_joint_position()
	var clip: String = _start_one_shot(leaf, 0.0)
	if clip.is_empty():
		return clip
	if loop:
		var res: Animation = _anim.get_animation(clip)
		if res != null:
			res.loop_mode = Animation.LOOP_LINEAR
	_anim.seek(0.0, true)
	var after: Vector3 = _root_joint_position()
	if before != Vector3.INF and after != Vector3.INF:
		_mesh.position += before - after
	return clip


func _root_joint_position() -> Vector3:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	if skeleton == null:
		return Vector3.INF
	var bone: int = skeleton.find_bone("joint_0")
	if bone < 0:
		return Vector3.INF
	return to_local(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)


func _clip_running(clip: String) -> bool:
	return not clip.is_empty() and _anim != null and _anim.is_playing() and _anim.current_animation == clip


func _clip_length(clip: String) -> float:
	if clip.is_empty() or _anim == null:
		return 0.0
	var res: Animation = _anim.get_animation(clip)
	return res.length if res != null else 0.0


## `Stung_bee` → `Notice_bee`. The music goes quiet, `HATI1` flinches into `HATI2`, whose
## frame 21 swells the face; from tick 94 the player turns their back to the camera (angle
## 0x8000), and at tick 252 `HATI3` spins round to show the face under the "stung by a bee"
## report with the bee-stung jingle.
func run_stung_bee() -> void:
	if stung:
		return
	stung = true
	var was_busy: bool = _busy
	_busy = true
	## Holds `HATI2`'s last frame between clips rather than dropping to the wait.
	set_cutscene_driven(true)
	## `mBGMPsComp_make_ps_quiet` (and the chase music goes with it).
	EventManager.demo_bgm = &"_quiet"
	Audio.stop_bgm()
	var elapsed: float = 0.0
	var swelled := false
	var clip: String = _start_one_shot(ANIM_HATI1)
	var on_hati2: bool = clip.is_empty()
	var hati2_t: float = 0.0
	while elapsed <= STUNG_NOTICE_SEC:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		elapsed += delta
		if not on_hati2 and (_anim == null or not _anim.is_playing() or _anim.current_animation != clip):
			on_hati2 = true
			_start_one_shot(ANIM_HATI2)
		elif on_hati2:
			hati2_t += delta
		if on_hati2 and not swelled and hati2_t >= STUNG_SWELL_FRAME / DecompTime.FRAME_HZ:
			swelled = true
			Game.sting_by_bee()
		if elapsed > STUNG_TURN_SEC:
			_motor.facing = PlayerLocomotion.ease_turn(_motor.facing, Fishing.SHOW_YAW + PI, delta)
			_mesh.rotation.y = _motor.facing
	if not swelled:
		Game.sting_by_bee()
	await _notice_bee()
	stung = false
	EventManager.demo_bgm = &""
	var world: World = World.find(get_tree())
	if world != null:
		world.call("_play_outdoor_bgm")
	set_cutscene_driven(false)
	_busy = was_busy


## `Notice_bee`: `HATI3` and the report; both have to finish before the wait.
func _notice_bee() -> void:
	var clip: String = _start_one_shot(ANIM_HATI3)
	EventManager.demo_bgm = &"bee_stung"
	Audio.play_bgm(&"bee_stung")
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % BEE_NOTICE_MSG))
	if ui != null and data != null:
		var ctx: DialogueContext = DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.voice_mode = DialogueVoice.Mode.CLICK
		ctx.window_color = BEE_NOTICE_COLOR
		ui.play(data, ctx)
		await ui.closed
	else:
		Game.post_notice("You've been stung by bees!")
	while not clip.is_empty() and _anim != null and _anim.is_playing() and _anim.current_animation == clip:
		await get_tree().process_frame
	## `settle_main_Notice_bee`: `HATI3`'s half-turn lives on joint_0 here (the original moves
	## it onto the actor with `AnimationMove` ROT_Y), so hand it to the facing and cut to the
	## wait without a blend — the pose reads the same either side of the swap.
	_motor.reset(Fishing.SHOW_YAW)
	_mesh.rotation.y = _motor.facing
	var wait := _resolve_clip(ANIM_WAIT)
	if _anim != null and not wait.is_empty():
		_gait = PlayerLocomotion.Gait.WAIT
		_anim.play(wait, 0.0)


func _start_one_shot(leaf: String, blend: float = 0.08) -> String:
	var clip := _resolve_clip(leaf)
	if _anim == null or clip.is_empty():
		return ""
	var res: Animation = _anim.get_animation(clip)
	if res != null:
		res.loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	_anim.play(clip, blend)
	return clip


func _play_clip(clip_name: StringName, tool_clip: StringName, start_frame: float = 0.0) -> void:
	if clip_name == &"":
		return
	var clip := _resolve_clip(String(clip_name))
	if _anim == null or clip.is_empty():
		await get_tree().create_timer(0.12).timeout
		return
	_anim.speed_scale = 1.0
	HeldTool.play(HeldTool.find_skeleton(_mesh), tool_clip, false)
	_anim.play(clip, 0.08)
	if start_frame > 0.0:
		_anim.seek(start_frame / DecompTime.FRAME_HZ, true)
	await _anim.animation_finished
	HeldTool.play(HeldTool.find_skeleton(_mesh), tools.tool_hold_anim, true)


func _try_load_generated_visual() -> void:
	var path := visual_path()
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path) as PackedScene
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
	var body_player: AnimationPlayer = _find_animation_player(body)
	if body_player != null:
		_animator.bind(body_player)
		_anim = _animator
		## Carry overlay lands after the body's own mix (anim1 on the part-table joints).
		if not _anim.mixer_applied.is_connected(tools.apply_carry_pose):
			_anim.mixer_applied.connect(tools.apply_carry_pose)
		_anim.add_clip_events(_clip_marks(), DecompTime.FRAME_HZ)
		if not _anim.clip_event.is_connected(_on_clip_event):
			_anim.clip_event.connect(_on_clip_event)
		## INDEX_DOOR / getoff: capture joint_0 XZ into AnimationMove, strip so the mesh stays on the body.
		## INDEX_OUTDOOR GO_OUT keeps joint_0 (starts behind stand, ends at bind — no snap).
		doors.capture_door_root_xz(body_player)
		VisualAnimation.strip_named_joint_tracks(
			body_player,
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


## `mPlib_change_player_face`: the chosen face type, swollen after a bee sting, tanned.
func _apply_face() -> void:
	if Game == null or _mesh == null:
		return
	PlayerFace.apply(
		_mesh, Game.resident.player_gender == IntroSequence.GENDER_FEMALE, Game.resident.player_face, Game.bee_swell,
		int(Game.resident.sunburn.get("rank", 0))
	)


## `Player_actor_Check_player_sunburn_for_main`, out in town.
func _tick_sunburn(delta: float) -> void:
	if delta <= 0.0 or Game == null or Game.title_demo_active or not TownSpace.is_outdoor_town():
		return
	var today: int = Clock.day_number()
	Sunburn.change_day(Game.resident.sunburn, today)
	Sunburn.rankdown_interval(Game.resident.sunburn, today)
	Sunburn.check_rankdown(Game.resident.sunburn, today)
	var exposed: bool = (
		not Game.intro_station_active and Game.town.weather == &"clear" and tools.umbrella == null
	)
	Sunburn.sun_tick(Game.resident.sunburn, exposed, Clock.month, Clock.day, Clock.hour, delta)


func _on_cloth_changed(_cloth_id: StringName) -> void:
	_apply_worn_cloth()


func _on_design_changed() -> void:
	_apply_worn_cloth()


func _apply_worn_cloth() -> void:
	if Game == null or _mesh == null:
		return
	## Custom original design worn as a shirt (`cloth.idx >= CLOTH_NUM+1`).
	if Game.resident.worn_design_slot >= 0 and Game.designs != null:
		var design: DesignPattern = Game.designs.resolved(Game.resident.worn_design_slot)
		if design != null:
			VisualCloth.apply_design(_mesh, DesignTexture.build(design))
			return
	var data: ItemData = ItemCatalog.get_item(Game.resident.cloth_id)
	var index: int = data.cloth_index if data != null else -1
	if index < 0 and Game.resident.cloth_id != &"":
		## Fallback: shirt_NNN id → index.
		var raw := String(Game.resident.cloth_id)
		if raw.begins_with("shirt_"):
			index = int(raw.substr(6))
	if index < 0:
		return
	VisualCloth.apply_cloth(_mesh, index)


func _resolve_clip_in(anim_player: AnimationPlayer, suffix: String) -> String:
	if anim_player == null or suffix.is_empty():
		return ""
	if anim_player.has_animation(suffix):
		return suffix
	for anim_name: String in anim_player.get_animation_list():
		if anim_name == suffix or anim_name.ends_with("/" + suffix) or anim_name.ends_with(suffix):
			return anim_name
	return ""


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
