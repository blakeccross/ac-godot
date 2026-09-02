class_name IntroTrainStageSync
extends Node

## Scene-owned door pulse timings — method tracks fire `TrainDoor.open_door()` at decomp frames.

const SYNC_ENTER := &"enter_door"
const SYNC_DECK := &"deck_door"
const SYNC_OPEN_D2 := &"open_d2_door"

const _FPS := 30.0

@onready var _player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	## Tracks resolve from the intro scene root, not `StageSync`.
	_player.root_node = NodePath("../..")
	_build_library()


func play(sync_name: StringName) -> void:
	if not _player.has_animation(sync_name):
		return
	_player.play(sync_name)


func _build_library() -> void:
	var lib := AnimationLibrary.new()
	lib.add_animation(SYNC_ENTER, _door_pulse_anim(IntroTrainStage.DOOR_OPEN_FRAME))
	lib.add_animation(SYNC_DECK, _door_pulse_anim(IntroTrainStage.DOOR_DECK_OPEN_FRAME))
	lib.add_animation(SYNC_OPEN_D2, _door_pulse_anim(IntroTrainStage.DOOR_OPEN_D2_FRAME))
	if _player.has_animation_library(&""):
		_player.remove_animation_library(&"")
	_player.add_animation_library(&"", lib)


func _door_pulse_anim(frame: float) -> Animation:
	var time: float = frame / _FPS
	var anim := Animation.new()
	anim.length = maxf(time + 0.001, 0.001)
	var track: int = anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(track, NodePath("TrainDoor"))
	anim.track_insert_key(track, time, {"method": &"open_door", "args": []})
	return anim
