extends Node3D

## Vestibule door — gateway alignment on ready; `open_door()` driven by `StageSync` method tracks.

var _anim: AnimationPlayer
var _pulse_armed: bool = false


func _ready() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	VisualTrain.apply_train_door_materials(vis)
	_anim = VisualAnimation.find_animation_player(self)
	if _anim != null:
		## `aTRD_actor_move`: when the clip ends the door returns to frame 1 (closed) and stops.
		_anim.animation_finished.connect(_on_door_clip_finished)
	## Closed pose is anim frame 0 (decomp actor). Snap before gateway fit so a
	## ckf_basis-only rest GLB still skins the panel into the vestibule.
	_snap_closed()
	var car: Node3D = get_node_or_null("%TrainCar") as Node3D
	var car_vis: Node3D = car.get_node_or_null("GeneratedVisual") as Node3D if car != null else null
	if car_vis != null:
		VisualTrain.place_train_door_at_gateway(
			self,
			vis,
			IntroTrainStage.DOOR_GATE_GX,
			car_vis,
			IntroTrainStage.DOOR_PANEL_Z_BIAS_GX
		)


func _on_door_clip_finished(_clip: StringName) -> void:
	_snap_closed()


func reset_door_pulse() -> void:
	_pulse_armed = true


func open_door() -> void:
	if not _pulse_armed:
		return
	_pulse_armed = false
	if _anim == null:
		return
	var clip: String = _resolve_door_clip()
	if clip.is_empty():
		return
	_anim.play(clip)
	## `aTRD_actor_move`: `frame_control.speed = 0.5` a 60 Hz tick is 30 clip frames a second,
	## real time for a clip authored at 30 fps (Rover's own clips run the same way).
	_anim.speed_scale = 1.0


func _snap_closed() -> void:
	if _anim == null:
		return
	var clip: String = _resolve_door_clip()
	if clip.is_empty():
		return
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	_anim.play(clip)
	_anim.seek(0.0, true)
	_anim.speed_scale = 0.0


func _resolve_door_clip() -> String:
	if _anim == null:
		return ""
	var clips: PackedStringArray = _anim.get_animation_list()
	if clips.is_empty():
		return ""
	for name: String in clips:
		if "romtrain_door" in name or name.ends_with("door"):
			return name
	return clips[0]
