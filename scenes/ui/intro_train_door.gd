extends Node3D

## Vestibule door — gateway alignment on ready; `open_door()` driven by `StageSync` method tracks.

var _anim: AnimationPlayer
var _pulse_armed: bool = false


func _ready() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	GeneratedVisual.apply_train_door_materials(vis)
	var car: Node3D = get_node_or_null("%TrainCar") as Node3D
	var car_vis: Node3D = car.get_node_or_null("GeneratedVisual") as Node3D if car != null else null
	if car_vis != null:
		GeneratedVisual.place_train_door_at_gateway(
			self,
			vis,
			IntroTrainStage.DOOR_GATE_GX,
			car_vis,
			IntroTrainStage.DOOR_PANEL_Z_BIAS_GX
		)
	_anim = GeneratedVisual.find_animation_player(self)


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
	_anim.speed_scale = 0.5


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
