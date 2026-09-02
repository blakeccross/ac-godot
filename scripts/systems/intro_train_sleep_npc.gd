class_name IntroTrainSleepNpc
extends Node3D

## Background passenger (`SP_NPC_SLEEP_OBABA`) — `AnimationPlayer` clip chaining.

const ANIM_KOKKURI_D1 := "npc_1_kokkuri_d1"
const ANIM_KOKKURI_D2 := "npc_1_kokkuri_d2"
const SPAWN_GX := Vector3(174.0, 0.0, 156.0)
const BENCH_FLOOR_Y_GX := 0.0

var _anim: AnimationPlayer
var _tree: AnimationTree
var _d1: StringName = &""
var _d2: StringName = &""
var _loops_left: int = 0
var _active_clip: StringName = &""
var _waiting_finish: bool = false


static func spawn_yaw() -> float:
	return IntroTrainStage.yaw_toward_player(SPAWN_GX)


func _ready() -> void:
	global_position = IntroTrainStage.gx_to_meters(SPAWN_GX)
	_anim = GeneratedVisual.find_animation_player(self)
	_ensure_visual_scale()
	_setup_player()
	_apply_spawn_pose()
	call_deferred("_start_sleep")


func _process(_delta: float) -> void:
	_poll_clip_end()


func realign() -> void:
	global_position = IntroTrainStage.gx_to_meters(SPAWN_GX)
	_ensure_visual_scale()
	_apply_spawn_pose()
	_start_sleep()


func _ensure_visual_scale() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis != null:
		GeneratedVisual.apply_actor_scale(vis)


func _setup_player() -> void:
	if _anim == null:
		return
	_d1 = StringName(IntroTrainStage.resolve_rover_clip(_anim, ANIM_KOKKURI_D1))
	_d2 = StringName(IntroTrainStage.resolve_rover_clip(_anim, ANIM_KOKKURI_D2))
	if _d1.is_empty():
		return
	if _d2.is_empty():
		_d2 = _d1
	_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _tree != null:
		_tree.active = false
	if not _anim.animation_finished.is_connected(_on_sleep_anim_finished):
		_anim.animation_finished.connect(_on_sleep_anim_finished)


func _apply_spawn_pose() -> void:
	rotation = Vector3.ZERO
	rotation.y = spawn_yaw()
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis != null:
		vis.rotation = Vector3.ZERO
	_defer_align_to_seat()


func _defer_align_to_seat() -> void:
	if not is_inside_tree():
		_align_to_seat()
		return
	var tree: SceneTree = get_tree()
	if tree.process_frame.is_connected(_align_to_seat):
		return
	tree.process_frame.connect(_align_to_seat, CONNECT_ONE_SHOT)


func _start_sleep() -> void:
	_loops_left = 2 + randi() % 3
	_play_clip(_d1, false, true)


func _align_to_seat() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	vis.position.y = 0.0
	GeneratedVisual.align_actor_world_min_to_height_gx(vis, BENCH_FLOOR_Y_GX)


func _on_sleep_anim_finished(anim_name: StringName) -> void:
	if anim_name != _d1 and anim_name != _d2:
		return
	_finish_sleep_clip(anim_name)


func _handle_sleep_clip_done(anim_name: StringName) -> void:
	if anim_name == _d1:
		_loops_left -= 1
		if _loops_left <= 0:
			_loops_left = 2 + randi() % 3
			_play_clip(_d2, false)
		else:
			_play_clip(_d1, false)
	elif anim_name == _d2:
		_start_sleep()


func _clip_reached_end() -> bool:
	if _active_clip.is_empty() or _anim == null:
		return false
	if _anim.current_animation != String(_active_clip):
		return false
	var animation: Animation = _anim.get_animation(_active_clip)
	if animation == null:
		return true
	return _anim.current_animation_position >= animation.length - 0.02


func _poll_clip_end() -> void:
	if not _waiting_finish:
		return
	if _clip_reached_end():
		_finish_sleep_clip(_active_clip)


func _finish_sleep_clip(anim_name: StringName) -> void:
	if not _waiting_finish:
		return
	_waiting_finish = false
	_handle_sleep_clip_done(anim_name)


func _play_clip(clip: StringName, loop: bool, snap: bool = false) -> void:
	if _anim == null or clip.is_empty():
		return
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_active_clip = clip
	_waiting_finish = not loop
	_anim.play(clip, 0.0 if snap else IntroTrainStage.ANIM_MORPH_BLEND)
	if snap:
		_anim.advance(0.0)
		_defer_align_to_seat()
