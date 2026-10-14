extends Node

## A gyroid in a room (`ac_hnw_common.c`): switched on, it poses its own clip by the rhythm
## counter (`GyroidRhythm`); switched off, it holds still. Child of the furniture node, whose
## name is the placement id.

var haniwa_idx: int = -1
var _anim: AnimationPlayer
var _clip: StringName = &""
var _seconds: float = 0.0
var _was_on: bool = false


func setup(visual_root: Node, ftr_index: int) -> void:
	haniwa_idx = GyroidRhythm.haniwa_index(ftr_index)
	_anim = VisualAnimation.find_animation_player(visual_root) if visual_root != null else null
	if _anim == null:
		return
	var names: PackedStringArray = _anim.get_animation_list()
	if not names.is_empty():
		_clip = StringName(names[0])
	_pose(0.0)


func _process(delta: float) -> void:
	if _anim == null or _clip == &"" or haniwa_idx < 0:
		return
	var on: bool = _is_on()
	if on and not _was_on:
		_seconds = 0.0
	_was_on = on
	if not on:
		_pose(0.0)
		return
	_seconds += delta
	_pose(GyroidRhythm.counter(GyroidRhythm.steps(_seconds), haniwa_idx))


func _is_on() -> bool:
	var session: IndoorSession = Game.interior_session if Game != null else null
	if session == null or session.room == null:
		return true
	var entry: FurniturePlacement = session.room.placement_by_id(StringName(get_parent().name))
	return entry == null or entry.on


func _pose(c: float) -> void:
	var anim: Animation = _anim.get_animation(_clip)
	if anim == null:
		return
	if _anim.current_animation != String(_clip):
		_anim.play(_clip)
	_anim.pause()
	## Clip frames run 1…frames at 30 per second; the clip's own length is frames / 30.
	var frames: float = anim.length * DecompTime.FRAME_HZ
	_anim.seek((GyroidRhythm.clip_frame(c, frames) - 1.0) / DecompTime.FRAME_HZ, true)
