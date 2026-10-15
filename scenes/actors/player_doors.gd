class_name PlayerDoors
extends Node

## The player through doors and demo walks: walking into a building and out of one
## (`mPlayer_INDEX_DOOR` / `INDEX_OUTDOOR`, the clip's root travel as `AnimationMove`), the
## indoor exit, getting off the train, and the scripted walks events lead the player on
## (`INDEX_DEMO_WALK`). Callers reach it as `player.doors`; it reads the player's motor,
## body animation and busy flag directly.

## `extra_data == 2` exits (houses, post office, Able Sisters) start O1 at frame 25 — the
## walk-out is already done, so only the turn-and-close-door shows. `extra_data == 3`
## exits (Nook, museum, police, …) start at frame 1 and walk out in full.
const GO_OUT_O1_DOOR_ONLY_START_SEC := 24.0 / DecompTime.FRAME_HZ  ## cKF frame 25 (frame 1 is t = 0)

## `mPlib_request_main_demo_walk_type1`: walk to a world point with the stick ignored (the house
## gyroid's "Save" walk to the door). Inactive when `_demo_walk_speed` is 0.
var demo_walk_goal: Vector3 = Vector3.ZERO
var demo_walk_speed: float = 0.0
var demo_walk_arrive: float = 0.0
var door_entering: bool = false
## `cKF_SkeletonInfo_R_AnimationMove` for INDEX_DOOR. False for INDEX_OUTDOOR (mesh root motion).
var _door_animation_move: bool = false
var _door_from: Vector3 = Vector3.ZERO
var _door_to: Vector3 = Vector3.ZERO
var _door_yaw: float = 0.0
var _door_move_elapsed: float = 0.0
var _door_move_duration: float = StructureDoor.APPROACH_SEC
var door_clear_busy: bool = false
## `model_world_position_correction` — decays toward 0 over `fixed_counter` game frames;
## `_door_correction_start` is where it began.
var _door_correction: Vector3 = Vector3.ZERO
var _door_correction_start: Vector3 = Vector3.ZERO
var _door_fixed_counter: float = 0.0
var _door_root_clip: String = ""
## `mPlayer_INDEX_DEMO_GETOFF_TRAIN`: `cKF_ANIMATION_TRANS_Y` is on too — the body follows the
## clip's root height from `_door_base_y`, and the state ends itself when the clip does.
var _door_getoff: bool = false
var _door_base_y: float = 0.0
## Leaf clip → Animation of scaled joint_0 deltas (meters, model space): XZ from the origin,
## Y from the 1000-unit base height (`base_shape_trs` y). Filled once.
static var _door_root_xz: Dictionary = {}

var _player: Player


func _enter_tree() -> void:
	_player = get_parent() as Player


## After a room load, walk-in doors stay armed until the probe leaves every auto door.
func clear_auto_enter_block() -> void:
	if not Game.block_auto_enter_doors:
		return
	## Keep blocked while still on an indoor EXIT_DOOR strip after a room load.
	if _on_indoor_exit_cell():
		return
	var hit: InteractionQuery = _player._resolve_interact()
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
	return session.room.is_exit_cell(session.grid.world_to_cell(_player.global_position))


## `mPlayer_INDEX_DOOR`: OPEN1 / INTO_S1 with `cKF_SkeletonInfo_R_AnimationMove_base`.
## World XZ = door stand + decaying (start−stand) + scaled joint_0 delta; mesh root stays bind.
func begin_door_enter(target: Vector3, face_yaw: float, walk_in: bool = false) -> void:
	var leaf := Player.ANIM_INTO_S1 if walk_in else Player.ANIM_OPEN1
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
		Player.ANIM_OUTTRAIN1,
		StructureDoor.ANIM_MOVE_COUNTER_GETOFF,
		StructureDoor.OUTTRAIN_SEC,
	)
	_door_getoff = true
	_door_base_y = stand.y
	_player.global_position.y = stand.y


## Walk to `goal` at `speed` (m/s), stopping within `arrive` (m); repeat calls move the goal
## (`mPlib_Set_goal_player_demo_walk`). Held until `end_demo_walk`.
func begin_demo_walk(goal: Vector3, speed: float, arrive: float) -> void:
	demo_walk_goal = goal
	demo_walk_speed = maxf(speed, 0.0)
	demo_walk_arrive = maxf(arrive, 0.0)


func end_demo_walk() -> void:
	demo_walk_speed = 0.0


func is_demo_walking() -> bool:
	return demo_walk_speed > 0.0


func is_door_entering() -> bool:
	return door_entering


func _begin_animation_move(
	target: Vector3,
	face_yaw: float,
	clip_leaf: String,
	counter: float,
	duration: float,
) -> void:
	door_entering = true
	_door_animation_move = true
	door_clear_busy = false
	_door_from = _player.global_position
	_door_to = Vector3(target.x, _player.global_position.y, target.z)
	_door_correction = Vector3(_door_from.x - _door_to.x, 0.0, _door_from.z - _door_to.z)
	_door_correction_start = _door_correction
	_door_fixed_counter = counter
	_door_yaw = face_yaw
	_door_move_elapsed = 0.0
	_door_move_duration = duration
	_player._motor.reset(face_yaw)
	_player._mesh.rotation.y = face_yaw
	_player.velocity = Vector3.ZERO
	var clip := _player._resolve_clip(clip_leaf)
	_door_root_clip = clip_leaf if _door_root_xz.has(clip_leaf) else ""
	if _player._anim == null or clip.is_empty():
		return
	_player._anim.speed_scale = 1.0
	_player._anim.play(clip, 0.08)


func end_door_enter() -> void:
	## A failed enter (`Game.try_enter_interior`) stays outdoors — the tool comes back out.
	if _player.tools.tool_stowed and not Game.is_indoors():
		_player.tools.take_out_tool()
	door_entering = false
	_door_animation_move = false
	_door_getoff = false
	_door_root_clip = ""


func await_door_enter() -> void:
	## Used when the structure has no door cKF (museum / police). Wait out INTO_S1 / OPEN1.
	if _player._anim != null and _player._anim.is_playing():
		await _player._anim.animation_finished
	elif get_tree() != null:
		await get_tree().create_timer(maxf(_door_move_duration, StructureDoor.INTO_SEC)).timeout


## `mPlayer_INDEX_OUTDOOR`: actor stays on the exit stand; GO_OUT `joint_0` walks the mesh
## from behind to bind (`Set_force_shadow_position_fromAnimePosition` only).
func begin_door_leave(stand: Vector3, _target: Vector3, face_yaw: float, full_walk: bool = false) -> void:
	_player._busy = true
	door_entering = true
	_door_animation_move = false
	door_clear_busy = true
	_player.global_position = Vector3(stand.x, _player.global_position.y, stand.z)
	_door_from = _player.global_position
	_door_to = _player.global_position
	_door_correction = Vector3.ZERO
	_door_yaw = face_yaw
	_door_move_elapsed = 0.0
	_door_move_duration = StructureDoor.LEAVE_SEC
	_door_root_clip = ""
	_player._motor.reset(face_yaw)
	_player._mesh.rotation.y = face_yaw
	_player.velocity = Vector3.ZERO
	var clip := _player._resolve_clip(Player.ANIM_GO_OUT_O1)
	if _player._anim == null or clip.is_empty():
		return
	_player._anim.speed_scale = 1.0
	## No morph (`InitAnimation_Base2` morph 0.0) so the first shown frame is the clip's own.
	_player._anim.play(clip, 0.0)
	if not full_walk:
		_player._anim.seek(GO_OUT_O1_DOOR_ONLY_START_SEC, true)
	## Pose the first frame now so un-hiding the model never shows the idle pose.
	_player._anim.advance(0.0)
	_player.visible = true


func end_door_leave() -> void:
	door_entering = false
	_door_animation_move = false
	if door_clear_busy:
		_player._busy = false
	door_clear_busy = false


## Indoor `EXIT_DOOR`: INTO_S1 while walking south through the exit cell.
func run_indoor_exit(target: Vector3, face_yaw: float) -> void:
	_player._busy = true
	door_clear_busy = true
	begin_door_enter(target, face_yaw, true)
	door_clear_busy = true
	if _player._anim != null and _player._anim.is_playing():
		await _player._anim.animation_finished
	else:
		await get_tree().create_timer(_door_move_duration).timeout
	end_door_leave()


func tick_door_enter(delta: float) -> void:
	_door_move_elapsed += delta
	_player._motor.reset(_door_yaw)
	_player._mesh.rotation.y = _door_yaw
	_player.velocity = Vector3.ZERO
	if _door_animation_move:
		_decay_door_correction()
		var root: Vector3 = _sample_door_root_xz()
		var world_root := Vector3(
			root.x * cos(_door_yaw) + root.z * sin(_door_yaw),
			0.0,
			-root.x * sin(_door_yaw) + root.z * cos(_door_yaw),
		)
		_player.global_position = Vector3(
			_door_to.x + _door_correction.x + world_root.x,
			_door_base_y + root.y if _door_getoff else _player.global_position.y,
			_door_to.z + _door_correction.z + world_root.z,
		)
	if _door_getoff:
		## `Player_actor_request_proc_index_fromDemo_getoff_train`: the clip's end hands over
		## to `demo_wait` (the caller keeps the player busy).
		if _door_move_elapsed >= _door_move_duration:
			end_door_enter()
			_player.play_wait_idle()
		return
	_player._snap_to_bg()


## `cKF_SkeletonInfo_R_AnimationMove_base`'s XZ correction, at `_door_move_elapsed`. Each
## tick the original keeps `(fc + 0.5) / (fc + 1)` of it and drops `fixed_counter` (fc) by
## 0.5; the product telescopes, so it shrinks in a straight line to `1 / (1 + fc₀)` of the
## start as the counter runs out (30 a second), then halves every tick after.
func _decay_door_correction() -> void:
	var fc0: float = maxf(_door_fixed_counter, 0.0)
	var ticks: float = _door_move_elapsed * DecompTime.TICK_HZ
	var fc: float = maxf(fc0 - 0.5 * ticks, 0.0)
	var after: float = maxf(ticks - 2.0 * fc0, 0.0)
	_door_correction = _door_correction_start * ((1.0 + fc) / (1.0 + fc0) * pow(0.5, after))


func _sample_door_root_xz() -> Vector3:
	if _door_root_clip.is_empty() or not _door_root_xz.has(_door_root_clip):
		return Vector3.ZERO
	var root_anim: Animation = _door_root_xz[_door_root_clip] as Animation
	if root_anim == null or root_anim.get_track_count() < 1:
		return Vector3.ZERO
	var t: float = 0.0
	if _player._anim != null:
		t = clampf(_player._anim.current_animation_position, 0.0, root_anim.length)
	return root_anim.position_track_interpolate(0, t)


func capture_door_root_xz(anim_player: AnimationPlayer) -> void:
	## Bake scaled joint_0 XZ deltas once before stripping (`base_model_translation` XZ = 0).
	var scale: float = FieldCatalog.actor_uniform_scale()
	for leaf: String in [Player.ANIM_OPEN1, Player.ANIM_INTO_S1, Player.ANIM_OUTTRAIN1]:
		if _door_root_xz.has(leaf):
			continue
		var clip_name := _player._resolve_clip_in(anim_player, leaf)
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
			## `scale * (cur_joint - base_model_translation)`; base XZ is 0, base Y 1000.
			baked.position_track_insert_key(
				out_track, t, Vector3(pos.x * scale, (pos.y - 1.0) * scale, pos.z * scale)
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
