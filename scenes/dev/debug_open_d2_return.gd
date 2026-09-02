extends Node

## Jump straight to OPEN_DOOR and verify return walk.


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate()
	intro.preview_seated_daylight = false
	add_child(intro)
	_run(intro)


func _run(intro: Node3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var stage: IntroTrainStage = intro.get("_stage")
	var rover: IntroTrainRoverAnim = intro.get_node("%Rover") as IntroTrainRoverAnim
	if not IntroTrainStage.missing_assets().is_empty():
		print("missing assets")
		get_tree().quit()
		return
	# Park at vestibule like phone sequence end.
	stage.action = IntroTrainStage.Action.OPEN_DOOR
	stage._pos_gx = IntroTrainStage.ROVER_DOOR_GX
	stage._yaw = PI
	stage._apply_rover_pose()
	stage._play_rover(IntroTrainStage.ANIM_OPEN_D2, false)
	stage._play_door_sync(IntroTrainStageSync.SYNC_OPEN_D2)
	stage._await_then(IntroTrainStage.Action.RETURN_APPROACH, IntroTrainStage.ANIM_OPEN_D2)
	print("start open_d2 z=", stage._pos_gx.z)
	for i: int in 600:
		await get_tree().process_frame
		stage.tick(1.0 / 60.0)
		var act := String(stage._action_name(stage.action))
		if i % 20 == 0 or act == "return_approach":
			print(
				"f=", i, " act=", act, " z=", snappedf(stage._pos_gx.z, 0.1),
				" pending_suffix=", stage._pending_suffix,
				" anim=", rover.body_animation_player().current_animation if rover.body_animation_player() else "?",
				" playing=", rover.intro_clip_playing(),
				" tree=", rover.get("_tree").active if rover.get("_tree") else "?",
			)
		if act == "return_approach" and stage._pos_gx.z > 200.0:
			print("SUCCESS z=", stage._pos_gx.z)
			break
		if i == 599:
			print("FAIL act=", act, " z=", stage._pos_gx.z)
	get_tree().quit()
