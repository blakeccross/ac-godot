class_name PlayerTools
extends Node

## The tool in the player's hand: binding the equipped item to the hand and its hold
## pose (`HeldTool`, `ToolCarry`), taking it out and putting it away round doors
## (`PUTIN_ITEM` / `TAKEOUT_ITEM`), the umbrella opening and folding, the balloon's sway
## and the pinwheel's spin. A child of the `Player`; it reads the player's body animation
## and busy flag directly.

## `mPlayer_ANIM_PUTAWAY1` — pocket put-away (`putin_item` forward, `takeout_item` reversed).
const ANIM_PUTAWAY1 := "ply_1_putaway1"
## `m_player_main_putin_item` / `takeout_item` / `return_outdoor*` timers are game ticks (60 Hz).
## `morph_counter` 9.0 falls 0.5 per tick and `cKF_SkeletonInfo_R_play` holds the clip's first
## frame the whole time, so the pose morph is 18 ticks before the clip itself starts moving.
const TOOL_MORPH_SEC := 18.0 * DecompTime.TICK_SEC
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

var _hold_anim: StringName = &""
## The umbrella in hand (`player->umbrella_actor`).
var umbrella: HeldUmbrella = null
## The item's carry pose layered on the arms (`BOY_part_data` / anim1).
var carry: ToolCarry = null
var tool_hold_anim: StringName = &""
var tool_use_anim: StringName = &""
## Tool is put away (door enter) or not yet taken back out (door emerge). `item_kind` is −1 in
## interiors too — `Player_actor_CheckScene_AbleOutItem` only allows the outdoor field.
var tool_stowed: bool = false
## `PUTIN_ITEM` / `TAKEOUT_ITEM` own the pose; `_update_animation` stays out of the way.
var tool_swap: bool = false
## `Player_actor_Item_windmill_CulcRotationSpeed`: the pinwheel turns as fast as the player
## carries it through the air (8 × GX moved a frame) plus the wind (10 × its power), easing
## toward that like `add_calc`.
var _pin_last: Vector3 = Vector3.INF
var _pin_speed: float = 0.0
## `Player_actor_Item_Movement_balloon_normal`, then the sway is put on the model hanging
## off the hand.
var _balloon: HeldBalloon = null
var _balloon_hand: Vector3 = Vector3.INF

## The Player this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


func on_equipment_changed(_item_id: StringName) -> void:
	var tool: ToolData = equipped_tool()
	var to_umbrella: bool = tool != null and tool.is_umbrella()
	## An umbrella opens out of / folds into the hand (`TAKEOUT_ITEM` / `PUTIN_ITEM` with
	## `UMB_OPEN1` / `UMB_CLOSE1`) rather than just appearing.
	if (to_umbrella or umbrella != null) and not tool_hidden() and not _player._busy and is_inside_tree() \
			and _player._anim != null:
		_swap_umbrella(to_umbrella)
		return
	bind_equipped_tool(not tool_hidden())
	if not _player._busy:
		_player._replay_gait_clip()


## `setup_main_Putin_item` (umbrella: `UMB_CLOSE1`, the tool folds shut over 30 frames) then
## `setup_main_Takeout_item` (umbrella: `UMB_OPEN1`, it opens from nothing).
func _swap_umbrella(to_umbrella: bool) -> void:
	var was_busy: bool = _player._busy
	_player._busy = true
	tool_swap = true
	if umbrella != null:
		await _fold_umbrella()
	if to_umbrella:
		await _open_umbrella()
	else:
		bind_equipped_tool(not tool_hidden())
	tool_swap = false
	_player._busy = was_busy
	if not _player._busy:
		_player._replay_gait_clip()


func _fold_umbrella() -> void:
	if umbrella == null:
		return
	umbrella.set_action(HeldUmbrella.Action.PUTAWAY)
	var length: float = _play_umbrella_clip("ply_1_umb_close1")
	var waited: float = 0.0
	while is_inside_tree() and waited < maxf(length, 1.0) and not umbrella.is_closed():
		await get_tree().process_frame
		waited += get_process_delta_time()
	umbrella = null
	HeldTool.unbind(HeldTool.find_skeleton(_player._mesh))


func _open_umbrella() -> void:
	bind_equipped_tool(true, HeldUmbrella.Action.TAKEOUT_BEFORE)
	var length: float = _play_umbrella_clip("ply_1_umb_open1")
	if length > 0.0 and is_inside_tree():
		await get_tree().create_timer(length).timeout


## Full-body umbrella clip once (`cKF_FRAMECONTROL_STOP`); returns its length.
func _play_umbrella_clip(leaf: String) -> float:
	var clip := _player._resolve_clip(leaf)
	if _player._anim == null or clip.is_empty():
		return 0.0
	_player._anim.speed_scale = 1.0
	_player._anim.play(clip, 0.08)
	var res: Animation = _player._anim.get_animation(clip)
	return res.length if res != null else 0.0


## `mPlib_check_player_open_umbrella`: an umbrella is out and fully open.
func is_umbrella_open() -> bool:
	return umbrella != null and umbrella.opened_fully and not tool_hidden()


## `Player_actor_InitAnimation_Base1` with a part table: while standing / walking / running the
## carried item's clip drives the table's arm joints over the body clip. Every other state
## (swings, digs, take-out, the umbrella's own clips) plays one clip on the whole body.
func apply_carry_pose() -> void:
	if carry == null or tool_swap or _player._anim == null or not ToolCarry.rides_on(String(_player._anim.current_animation)):
		return
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	if skeleton != null:
		carry.apply(skeleton)


func tool_hidden() -> bool:
	return tool_stowed or Game.is_indoors()


func tick_balloon(delta: float) -> void:
	if _balloon == null or tool_hidden():
		return
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	var attach := skeleton.get_node_or_null(HeldTool.ATTACH_NAME) as Node3D if skeleton != null else null
	if attach == null:
		return
	var hand: Vector3 = attach.global_position
	if _balloon_hand == Vector3.INF:
		_balloon_hand = hand
	if delta > 0.0:
		## The hand's speed, GX a 30 fps frame.
		var frames: float = delta * DecompTime.FRAME_HZ
		var moved: Vector3 = (hand - _balloon_hand) / FieldCatalog.GX_TO_METERS / frames
		var walking: bool = _player._motor.gait() == PlayerLocomotion.Gait.WALK or _player._motor.gait() == PlayerLocomotion.Gait.RUN
		var speed_gx: float = Vector2(_player.velocity.x, _player.velocity.z).length() / FieldCatalog.GX_TO_METERS / DecompTime.FRAME_HZ
		_balloon.step(delta, moved, _player._motor.facing, walking, speed_gx)
		_balloon_hand = hand
	_balloon.apply(_player._motor.facing)


func tick_pinwheel(delta: float) -> void:
	var tool: ToolData = equipped_tool()
	if tool == null or not tool.is_pinwheel() or tool_hidden():
		_pin_last = Vector3.INF
		return
	var anim: AnimationPlayer = HeldTool.animation_player(HeldTool.find_skeleton(_player._mesh))
	if anim == null:
		return
	var frames: float = maxf(delta * DecompTime.FRAME_HZ, 0.0001)
	var moved: float = 0.0 if _pin_last == Vector3.INF else _player.global_position.distance_to(_pin_last)
	_pin_last = _player.global_position
	var target: float = HeldPinwheel.target_speed(moved / FieldCatalog.GX_TO_METERS / frames, Game.wind.power())
	_pin_speed = HeldPinwheel.ease_speed(_pin_speed, target, frames)
	anim.speed_scale = _pin_speed


func bind_equipped_tool(
	show_tool: bool, umbrella_start: HeldUmbrella.Action = HeldUmbrella.Action.OPEN_NOW
) -> void:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	HeldTool.unbind(skeleton)
	umbrella = null
	_balloon = null
	carry = null
	_hold_anim = &""
	tool_hold_anim = &""
	tool_use_anim = &""
	var tool: ToolData = equipped_tool()
	if show_tool and tool != null and tool.visual_id != &"":
		var attach: Node3D = HeldTool.bind(skeleton, tool.visual_id)
		carry = ToolCarry.build(_player._anim, skeleton, tool)
		if tool.is_balloon() and attach != null and attach.get_child_count() > 0:
			_balloon = HeldBalloon.new()
			_balloon.setup(attach.get_child(0) as Node3D)
			_balloon_hand = Vector3.INF
		if tool.is_umbrella() and attach != null and attach.get_child_count() > 0:
			umbrella = HeldUmbrella.new()
			umbrella.setup(attach.get_child(0) as Node3D, umbrella_start)
			HeldUmbrella.paint_canopy(attach.get_child(0) as Node3D, HeldUmbrella.design_texture(tool))
		_hold_anim = tool.hold_anim
		tool_hold_anim = tool.visual_hold_anim
		tool_use_anim = tool.visual_use_anim
		HeldTool.play(skeleton, tool_hold_anim, true)


## `Player_actor_CheckAndRequest_ItemInOut`: a door request while a tool is out is swapped for
## `PUTIN_ITEM` (`PUTAWAY1` forward, the tool shrinking into the hand over 18 ticks), and the
## door sequence only starts once it ends. The equipped item itself is untouched.
func put_away_tool_for_door() -> void:
	if tool_hidden() or equipped_tool() == null:
		return
	var was_busy: bool = _player._busy
	_player._busy = true
	tool_swap = true
	if not _player.doors.door_entering:
		_player.doors.door_clear_busy = false
	if umbrella != null:
		## `setup_main_Putin_item`: an umbrella folds (`UMB_CLOSE1`) instead of `PUTAWAY1`.
		await _fold_umbrella()
		tool_stowed = true
		bind_equipped_tool(false)
		tool_swap = false
		_player._busy = was_busy
		return
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	var length: float = _play_tool_swap_clip(false)
	var total: float = TOOL_MORPH_SEC + length + PUTIN_STOP_TICKS * DecompTime.TICK_SEC
	var elapsed: float = 0.0
	while elapsed < total:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if elapsed < TOOL_MORPH_SEC and _player._anim != null:
			_player._anim.seek(0.0, true)
		var scale_t: float = clampf(elapsed / (PUTIN_SCALE_TICKS * DecompTime.TICK_SEC), 0.0, 1.0)
		HeldTool.set_scale(skeleton, 1.0 - scale_t)
	tool_stowed = true
	bind_equipped_tool(false)
	tool_swap = false
	## The door sequence (`begin_door_enter`) takes over from here and locks movement itself.
	_player._busy = was_busy


## Outdoor spawn from a door: `OUTDOOR` has `ABLE_ITEM_NONE`, so nothing is in hand until
## `take_out_tool`.
func stow_tool_for_door_exit() -> void:
	if equipped_tool() == null:
		return
	tool_stowed = true
	bind_equipped_tool(false)


## `RETURN_OUTDOOR` (3 ticks) → `TAKEOUT_ITEM` → `RETURN_OUTDOOR2` (3 ticks). Take-out plays
## `PUTAWAY1` reversed with nothing in hand, then from tick 36 blends to the tool's hold pose
## while it grows 0 → 1, ending at tick 54.
func take_out_tool() -> void:
	if not tool_stowed:
		return
	var was_busy: bool = _player._busy
	_player._busy = true
	tool_swap = true
	if not _player.doors.door_entering:
		_player.doors.door_clear_busy = false
	await get_tree().create_timer(RETURN_OUTDOOR_TICKS * DecompTime.TICK_SEC).timeout
	tool_stowed = false
	var held: ToolData = equipped_tool()
	if held != null and held.is_umbrella() and not Game.is_indoors():
		## `setup_main_Takeout_item`: an umbrella opens out (`UMB_OPEN1`), no grow-in.
		await _open_umbrella()
		await get_tree().create_timer(RETURN_OUTDOOR_TICKS * DecompTime.TICK_SEC).timeout
		tool_swap = false
		_player._busy = was_busy
		if not _player._busy:
			_player._replay_gait_clip()
		return
	bind_equipped_tool(not Game.is_indoors())
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	HeldTool.set_scale(skeleton, 0.0)
	var length: float = _play_tool_swap_clip(true)
	var grow_start: float = TAKEOUT_SCALE_START_TICKS * DecompTime.TICK_SEC
	var end: float = TAKEOUT_END_TICKS * DecompTime.TICK_SEC
	var elapsed: float = 0.0
	var posed: bool = false
	while elapsed < end:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not posed and elapsed < TOOL_MORPH_SEC and _player._anim != null:
			## Reverse clip: the morph holds its *last* frame.
			_player._anim.seek(length, true)
		if elapsed < grow_start:
			continue
		if not posed:
			posed = true
			_blend_to_hold_pose()
		elif elapsed < grow_start + TOOL_MORPH_SEC and _player._anim != null:
			_player._anim.seek(0.0, true)
		HeldTool.set_scale(skeleton, clampf((elapsed - grow_start) / (end - grow_start), 0.0, 1.0))
	HeldTool.set_scale(skeleton, 1.0)
	await get_tree().create_timer(RETURN_OUTDOOR_TICKS * DecompTime.TICK_SEC).timeout
	tool_swap = false
	_player._busy = was_busy
	if not _player._busy and (_player._anim == null or not _player._anim.is_playing()):
		_player._replay_gait_clip()


## Plays `PUTAWAY1` (reversed for take-out) plus its GASAGOSO rustle; returns its length.
func _play_tool_swap_clip(reverse: bool) -> float:
	var clip := _player._resolve_clip(ANIM_PUTAWAY1)
	if _player._anim == null or clip.is_empty():
		return 0.0
	_player._anim.speed_scale = 1.0
	if reverse:
		_player._anim.play_backwards(clip, TOOL_MORPH_SEC)
	else:
		_player._anim.play(clip, TOOL_MORPH_SEC)
	if reverse:
		## The take-out rustles as it starts, which is the clip's end.
		PlayerSe.play_opening(_player, StringName(clip))
	var res: Animation = _player._anim.get_animation(clip)
	return res.length if res != null else 0.0


func _blend_to_hold_pose() -> void:
	if _player._anim == null:
		return
	var clip := _player._resolve_clip(Player.ANIM_WAIT)
	if clip.is_empty():
		return
	_player._ensure_loop(clip)
	_player._gait = PlayerLocomotion.Gait.WAIT
	_player._anim.speed_scale = 1.0
	_player._anim.play(clip, TOOL_MORPH_SEC)


func equipped_tool() -> ToolData:
	if Game.inventory == null or Game.inventory.equipment_id == &"":
		return null
	return ItemCatalog.get_item(Game.inventory.equipment_id) as ToolData
