class_name IntroTrainSleepNpc
extends RefCounted

## Background passenger (`SP_NPC_SLEEP_OBABA`) — loops kokkuri nod/twitch anims.

const ANIM_KOKKURI_D1 := "npc_1_kokkuri_d1"
const ANIM_KOKKURI_D2 := "npc_1_kokkuri_d2"
## Window-side rear bench (`start_demo1` ut 4,4 → aisle spawn, −40 GX to window column).
const SPAWN_GX := Vector3(100.0, 0.0, 166.0)
## Seated passengers face down the car (+Z).
const SPAWN_YAW := 0.0

var _host: Node3D
var _anim: AnimationPlayer
var _clip: String = ""
var _loops_left: int = 0
var _pending: bool = false


func bind(host: Node3D, anim: AnimationPlayer) -> void:
	_host = host
	_anim = anim
	if _host != null:
		_host.global_position = IntroTrainStage.gx_to_meters(SPAWN_GX)
		_host.rotation.y = SPAWN_YAW
	_start_sleep()


func tick(_delta: float) -> void:
	if _pending:
		_flush_pending()


func _start_sleep() -> void:
	_loops_left = 2 + randi() % 3
	_play(ANIM_KOKKURI_D1, false)


func _play(suffix: String, loop: bool) -> void:
	if _anim == null:
		_clip = suffix
		_pending = true
		return
	var clip: String = IntroTrainStage.resolve_rover_clip(_anim, suffix)
	if clip.is_empty():
		return
	if _clip == clip and _anim.is_playing():
		return
	_clip = clip
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim.play(clip, 0.0)
	if _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.disconnect(_on_anim_finished)
	if not loop:
		_anim.animation_finished.connect(_on_anim_finished)


func _on_anim_finished(anim_name: StringName) -> void:
	if _clip != "" and String(anim_name) != _clip:
		return
	if _anim != null and _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.disconnect(_on_anim_finished)
	_pending = true


func _flush_pending() -> void:
	_pending = false
	if _clip == ANIM_KOKKURI_D1:
		_loops_left -= 1
		if _loops_left <= 0:
			_loops_left = 2 + randi() % 3
			_play(ANIM_KOKKURI_D2, false)
		else:
			_play(ANIM_KOKKURI_D1, false)
	elif _clip == ANIM_KOKKURI_D2:
		_start_sleep()
	else:
		_start_sleep()
