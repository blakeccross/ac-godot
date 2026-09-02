extends Node

## Drive intro to OPEN_DOOR / RETURN_APPROACH and log stage + rover state.


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate()
	add_child(intro)
	_run(intro)


func _run(intro: Node3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var stage: IntroTrainStage = intro.get("_stage")
	var rover: IntroTrainRoverAnim = intro.get_node("%Rover") as IntroTrainRoverAnim
	print("=== INTRO ANIM DEBUG ===")
	print("missing=", IntroTrainStage.missing_assets())
	if not IntroTrainStage.missing_assets().is_empty():
		print("ABORT: missing assets")
		get_tree().quit()
		return
	for i: int in 300:
		await get_tree().process_frame
		if stage.action == IntroTrainStage.Action.TALK:
			print("talk at frame ", i)
			break
	stage.cue_sit()
	for i: int in 200:
		await get_tree().process_frame
		if stage.action == IntroTrainStage.Action.SEATED:
			print("seated at frame ", i)
			break
	stage.cue_phone()
	for i: int in 600:
		await get_tree().process_frame
		if stage.action == IntroTrainStage.Action.KEITAI_TALK:
			print("keitai_talk at frame ", i, " z=", stage._pos_gx.z)
			break
	stage.end_phone_talk()
	print("end_phone_talk action=", stage.action)
	for i: int in 900:
		await get_tree().process_frame
		var action_name: String = String(stage._action_name(stage.action))
		if i % 30 == 0 or action_name in ["open_door", "return_approach", "talk"]:
			_print_tick(i, stage, rover, action_name)
		if stage.action == IntroTrainStage.Action.TALK and stage._pos_gx.z > 200.0:
			print("RETURN COMPLETE at frame ", i, " z=", stage._pos_gx.z)
			break
		if i == 899:
			print("TIMEOUT action=", action_name, " z=", stage._pos_gx.z)
			_print_rover(rover)
	get_tree().quit()


func _print_tick(i: int, stage: IntroTrainStage, rover: IntroTrainRoverAnim, action_name: String) -> void:
	print(
		"f=", i,
		" act=", action_name,
		" z=", snappedf(stage._pos_gx.z, 0.1),
		" pending=", stage._pending_next,
		" pending_ready=", stage._pending_ready,
		" pending_suffix=", stage._pending_suffix,
		" clip_active=", rover.get("_clip_active") if rover != null else "?",
		" rover_suffix=", rover.get("_active_suffix") if rover != null else "?",
		" rover_node=", _rover_state_node(rover),
	)
	if action_name == "open_door":
		_print_rover(rover)


func _print_rover(rover: IntroTrainRoverAnim) -> void:
	if rover == null:
		print("  rover missing")
		return
	var playback: AnimationNodeStateMachinePlayback = rover.get("_playback")
	print(
		"  rover clip_active=", rover.get("_clip_active"),
		" suffix=", rover.get("_active_suffix"),
		" clip=", rover.get("_active_clip"),
		" playing=", playback.is_playing() if playback != null else "?",
		" current=", playback.get_current_node() if playback != null else "?",
		" fading=", playback.get_fading_from_node() if playback != null else "?",
	)


func _rover_state_node(rover: IntroTrainRoverAnim) -> String:
	if rover == null:
		return "?"
	var playback: AnimationNodeStateMachinePlayback = rover.get("_playback")
	if playback == null:
		return "no-playback"
	return String(playback.get_current_node())
