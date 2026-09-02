class_name IntroTrainRoverAnim
extends Node3D

## Rover actor host — `AnimationPlayer` for all intro clips (tree node kept for scene compat).

signal visual_ready(visual: Node3D)
signal intro_clip_finished(anim_name: StringName)

const INTRO_CLIP_SUFFIXES: Array[String] = [
	IntroTrainStage.ANIM_OPEN_D1,
	IntroTrainStage.ANIM_WALK,
	IntroTrainStage.ANIM_WAIT,
	IntroTrainStage.ANIM_SITDOWN,
	IntroTrainStage.ANIM_SIT_WAIT,
	IntroTrainStage.ANIM_STANDUP,
	IntroTrainStage.ANIM_TO_DECK,
	IntroTrainStage.ANIM_KEITAI_ON,
	IntroTrainStage.ANIM_KEITAI_TALK,
	IntroTrainStage.ANIM_KEITAI_OFF,
	IntroTrainStage.ANIM_OPEN_D2,
]

## Wait for `animation_finished` — early poll cuts these clips short.
const _SIGNAL_FINISH_SUFFIXES: Array[String] = [
	IntroTrainStage.ANIM_STANDUP,
]

var _anim: AnimationPlayer
var _tree: AnimationTree
var _active_clip: String = ""
var _active_suffix: String = ""
var _clip_active: bool = false
var _looping: bool = false


func _ready() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis != null:
		GeneratedVisual.apply_actor_scale(vis)
		call_deferred("_emit_visual_ready", vis)
	_setup_player()


func _process(_delta: float) -> void:
	_poll_one_shot_end()


func body_animation_player() -> AnimationPlayer:
	return _anim


func play_intro_clip(
	suffix: String, loop: bool, speed_scale: float = 1.0, blend_override: float = -1.0
) -> bool:
	if _anim == null:
		return false
	var clip: String = IntroTrainStage.resolve_rover_clip(_anim, suffix)
	if clip.is_empty():
		return false
	if (
		_active_suffix == suffix
		and _clip_active
		and _looping == loop
		and _anim.current_animation == clip
		and _anim.is_playing()
	):
		var anim_check: Animation = _anim.get_animation(clip)
		if anim_check != null:
			var want_loop: int = (
				Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			)
			if anim_check.loop_mode == want_loop:
				return true
	if not loop and _looping and _anim.is_playing():
		_anim.stop()
	var anim: Animation = _anim.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _tree != null:
		_tree.active = false
	_active_suffix = suffix
	_active_clip = clip
	_looping = loop
	_clip_active = true
	_anim.speed_scale = speed_scale
	var blend: float = (
		blend_override if blend_override >= 0.0 else IntroTrainStage._rover_anim_blend(suffix)
	)
	_anim.play(clip, blend)
	return true


func commit_one_shot_pose() -> void:
	if _anim == null or _active_clip.is_empty():
		_clip_active = false
		return
	var anim: Animation = _anim.get_animation(_active_clip)
	if anim == null:
		_clip_active = false
		return
	_anim.play(_active_clip, 0.0)
	_anim.seek(anim.length, true)
	_clip_active = false


func intro_clip_playing() -> bool:
	if not _clip_active or _anim == null:
		return false
	if _looping:
		return _anim.is_playing()
	if _active_suffix in _SIGNAL_FINISH_SUFFIXES:
		return _anim.is_playing()
	return _anim.is_playing() and not _one_shot_reached_end()


func current_intro_clip() -> String:
	return _active_clip


func snap_intro_clip_to_end() -> void:
	if _anim != null:
		_anim.advance(1000.0)
	_clip_active = false


func connect_intro_clip_finished(callable: Callable) -> void:
	if not intro_clip_finished.is_connected(callable):
		intro_clip_finished.connect(callable)


func disconnect_intro_clip_finished(callable: Callable) -> void:
	if intro_clip_finished.is_connected(callable):
		intro_clip_finished.disconnect(callable)


func _emit_visual_ready(visual: Node3D) -> void:
	visual_ready.emit(visual)


func _setup_player() -> void:
	_anim = GeneratedVisual.find_animation_player(self)
	_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _tree != null:
		_tree.active = false
	if _anim != null and not _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.connect(_on_anim_finished)


func _one_shot_reached_end() -> bool:
	if _active_clip.is_empty() or _anim.current_animation != _active_clip:
		return false
	var anim: Animation = _anim.get_animation(_active_clip)
	if anim == null:
		return true
	return _anim.current_animation_position >= anim.length - 0.02


func _poll_one_shot_end() -> void:
	if not _clip_active or _looping:
		return
	if _active_suffix in _SIGNAL_FINISH_SUFFIXES:
		return
	if _one_shot_reached_end():
		_finish_one_shot()


func _on_anim_finished(anim_name: StringName) -> void:
	if not _clip_active or _looping:
		return
	var finished := String(anim_name)
	if finished != _active_clip and not finished.ends_with(_active_suffix):
		return
	_finish_one_shot()


func _finish_one_shot() -> void:
	if not _clip_active or _looping:
		return
	_clip_active = false
	intro_clip_finished.emit(StringName(_active_suffix))
