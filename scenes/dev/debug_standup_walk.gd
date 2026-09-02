extends Node

## Log standup -> walk transition.


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
	var anim: AnimationPlayer = rover.body_animation_player()
	if not IntroTrainStage.missing_assets().is_empty():
		get_tree().quit()
		return
	stage._pos_gx = IntroTrainStage.ROVER_SIT_GX
	stage._yaw = 0.0
	stage.action = IntroTrainStage.Action.SEATED
	stage._apply_rover_pose()
	rover.play_intro_clip(IntroTrainStage.ANIM_SIT_WAIT, true)
	await get_tree().create_timer(0.2).timeout
	stage.cue_phone()
	var saw_standup_end := false
	for i: int in 300:
		await get_tree().process_frame
		var act := String(stage._action_name(stage.action))
		if act == "standup" and rover.get("_clip_active") == false and not saw_standup_end:
			saw_standup_end = true
			print(
				"standup finished f=", i,
				" anim=", anim.current_animation,
				" pos=", anim.current_animation_position,
			)
		if saw_standup_end and i <= saw_standup_end + 15:
			print(
				"f=", i, " act=", act,
				" anim=", anim.current_animation,
				" pos=", snappedf(anim.current_animation_position, 3),
				" yaw=", snappedf(stage._yaw, 2),
				" host=", stage._pos_gx,
			)
		if act == "move_door":
			print("reached move_door f=", i)
			break
	get_tree().quit()
