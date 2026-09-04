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
## `mPlayer_ANIM_OPEN1` — door enter demo (`mPlayer_INDEX_DOOR`, type 0).
const ANIM_OPEN1 := "ply_1_open1"
## `mPlayer_ANIM_INTO_S1` — indoor door / exit walk (`mPlayer_INDEX_DOOR`, type ≠ 0).
const ANIM_INTO_S1 := "ply_1_into_s1"
## `mPlayer_ANIM_GO_OUT_S1` — outdoor emerge demo (`mPlayer_INDEX_OUTDOOR`, is_start_demo).
const ANIM_GO_OUT_S1 := "ply_1_go_out_s1"
## `mPlayer_ANIM_GO_OUT_O1` — non-demo outdoor emerge fallback.
const ANIM_GO_OUT_O1 := "ply_1_go_out_o1"
## `mPlayer_ANIM_OUTTRAIN1` — station caboose step-off (`mPlayer_INDEX_DEMO_GETOFF_TRAIN`).
const ANIM_OUTTRAIN1 := "ply_1_outtrain1"

@onready var _mesh: Node3D = $MeshPivot
@onready var _placeholder: MeshInstance3D = $MeshPivot/PlaceholderMesh
@onready var _probe: Area3D = $MeshPivot/InteractProbe
@onready var _look: Marker3D = $CameraLook

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
var _tool_hold_anim: StringName = &""
var _tool_use_anim: StringName = &""
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
var _talk_turn_debt: float = 0.0
## Leaf clip → Animation of scaled joint_0 XZ deltas (meters, model space). Filled once.
static var _door_root_xz: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	_look.position = Vector3(0.0, LOOK_HEIGHT, 0.0)
	_try_load_generated_visual()
	Game.inventory.equipment_changed.connect(_on_equipment_changed)
	_on_equipment_changed(Game.inventory.equipment_id)


func _exit_tree() -> void:
	if Game.inventory.equipment_changed.is_connected(_on_equipment_changed):
		Game.inventory.equipment_changed.disconnect(_on_equipment_changed)


func facing_yaw() -> float:
	return _motor.facing


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


func is_busy() -> bool:
	return _busy


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
	if _door_entering:
		_tick_door_enter(delta)
		return
	if _cutscene_driven:
		velocity = Vector3.ZERO
		_mesh.rotation.y = _motor.facing
		_update_animation(delta)
		return

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
	var menu_open: bool = _menu_open()
	if not _busy and not menu_open:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		stick = clampf(input_dir.length(), 0.0, 1.0)
		wish = _camera_wish(input_dir)

	var planar: Vector3 = _motor.tick(
		delta, wish, stick, Input.is_action_pressed("sprint") and not menu_open, _busy or menu_open
	)
	velocity.x = planar.x
	velocity.z = planar.z
	_tick_talk_face(delta)
	_mesh.rotation.y = _motor.facing
	var before: Vector3 = global_position
	move_and_slide()
	if bg.size() == 2:
		global_position = FieldCollision.revise_xz(
			bg[0] as WorldData, bg[1] as WorldGrid, before, global_position
		)
	elif on_bg:
		_snap_to_bg()
	_update_animation(delta)
	_update_footprints(delta, bg)
	_update_focus()
	_clear_auto_enter_block()
	_try_auto_enter()


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
	var hit: InteractionQuery = _resolve_interact()
	if hit == null or hit.host == null:
		Game.block_auto_enter_doors = false
		return
	if hit.host.get("auto_enter") != true:
		Game.block_auto_enter_doors = false


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
func begin_door_leave(stand: Vector3, _target: Vector3, face_yaw: float) -> void:
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
	var clip := _resolve_clip(ANIM_GO_OUT_S1)
	if clip.is_empty():
		clip = _resolve_clip(ANIM_GO_OUT_O1)
	if _anim == null or clip.is_empty():
		return
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)


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
	)


func _group_open(group: String) -> bool:
	if get_tree() == null:
		return false
	var ui: Node = get_tree().get_first_node_in_group(group)
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _menu_open():
		return
	if event.is_action_pressed("interact"):
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


func _update_animation(delta: float) -> void:
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
	if next == _gait and _anim.is_playing():
		_anim.speed_scale = _anim_speed(next)
		return
	_gait = next
	var clip := _resolve_clip(_clip_for(next))
	if clip.is_empty():
		return
	_ensure_loop(clip)
	_anim.speed_scale = _anim_speed(next)
	_anim.play(clip, 0.12)


func _update_footprints(delta: float, bg: Array) -> void:
	## `Player_actor_Set_FootMark_MarkOnly`: one print per foot, alternating, on the gait
	## clip's foot-down frames. Our generated clips carry no frame tags, so the cadence
	## comes from the clip rate instead — same time between steps, so tracks still spread
	## out as the gait speeds up.
	var gait: PlayerLocomotion.Gait = _motor.gait()
	if bg.size() != 2 or _busy or gait == PlayerLocomotion.Gait.WAIT:
		_step_time = 0.0
		return
	var marks: Node = get_tree().get_first_node_in_group("footprints")
	if marks == null or not marks.has_method("spawn"):
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
	var snow: bool
	if attr >= 0:
		if not FootprintMarks.marks_attr(attr, season):
			return
		snow = FootprintMarks.is_snow_mark(attr)
	else:
		var terrain: WorldGrid.Terrain = data.terrain_at(grid.world_to_cell(global_position))
		if not FootprintMarks.marks_terrain(terrain, season):
			return
		snow = terrain != WorldGrid.Terrain.SAND
	var foot: Vector3
	var yaw: float
	var anchor: Transform3D = _foot_anchor(_right_foot)
	if anchor.basis.determinant() != 0.0:
		foot = anchor.origin
		yaw = anchor.basis.get_euler().y
	else:
		yaw = _motor.facing
		foot = FootprintMarks.foot_position(global_position, yaw, _right_foot)
	var xform: Transform3D = FootprintMarks.mark_transform(data, grid, foot, yaw)
	if xform.basis.determinant() == 0.0:
		return
	marks.call("spawn", xform, snow)


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
	match gait:
		PlayerLocomotion.Gait.WAIT:
			return 1.0
		PlayerLocomotion.Gait.WALK:
			return clampf(_motor.planar_speed / PlayerLocomotion.WALK_RUN_SPEED, 0.7, 1.15)
		_:
			return clampf(_motor.planar_speed / PlayerLocomotion.RUN_SPEED, 0.85, 1.25)


func _clip_for(gait: PlayerLocomotion.Gait) -> String:
	match gait:
		PlayerLocomotion.Gait.WALK:
			return ANIM_WALK
		PlayerLocomotion.Gait.RUN:
			return ANIM_RUN
		PlayerLocomotion.Gait.DASH:
			return ANIM_DASH
		_:
			if _hold_anim != &"" and not _resolve_clip(String(_hold_anim)).is_empty():
				return String(_hold_anim)
			return ANIM_WAIT


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


func _try_interact() -> void:
	if Game.held_furniture() != null and Game.try_place_furniture(self):
		return
	var hit: InteractionQuery = _resolve_interact()
	if hit == null or hit.action == null:
		if Game.try_place_furniture(self):
			return
		return
	await _run_interact(hit)


func _try_auto_enter() -> void:
	## Museum walk-in (`aMsm_check_player`): no A press while open.
	if _busy or _door_entering or _menu_open():
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
	if hit.host != null and is_instance_valid(hit.host):
		## Door enter awaits the structure open clip before changing scene.
		await hit.host.interact(hit.action, ctx)
	else:
		ToolUse.apply_field(hit.action, ctx)
	await _finish_action(tail)
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
	_anim.speed_scale = 1.0
	HeldTool.play(HeldTool.find_skeleton(_mesh), _tool_use_anim, false)
	_anim.play(clip, 0.08)
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
		## INDEX_DOOR / getoff: capture joint_0 XZ into AnimationMove, strip so the mesh stays on the body.
		## INDEX_OUTDOOR GO_OUT keeps joint_0 (starts behind stand, ends at bind — no snap).
		_capture_door_root_xz(_anim)
		GeneratedVisual.strip_named_joint_tracks(
			_anim,
			"joint_0",
			PackedStringArray([ANIM_OPEN1, ANIM_INTO_S1, ANIM_OUTTRAIN1]),
		)
		var wait_clip := _resolve_clip(ANIM_WAIT)
		if not wait_clip.is_empty():
			_ensure_loop(wait_clip)
			_anim.play(wait_clip)


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
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	HeldTool.unbind(skeleton)
	_hold_anim = &""
	_tool_hold_anim = &""
	_tool_use_anim = &""
	var tool: ToolData = _equipped_tool()
	if tool != null and tool.visual_id != &"":
		HeldTool.bind(skeleton, tool.visual_id)
		_hold_anim = tool.hold_anim
		_tool_hold_anim = tool.visual_hold_anim
		_tool_use_anim = tool.visual_use_anim
		HeldTool.play(skeleton, _tool_hold_anim, true)
	if not _busy:
		_replay_gait_clip()


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
