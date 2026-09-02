extends Node

## Log camera look during TALK -> SITDOWN -> SEATED.


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
	var cam: Camera3D = intro.get_node("%IntroCamera") as Camera3D
	for _i: int in 300:
		await get_tree().process_frame
		if stage.action == IntroTrainStage.Action.TALK and stage.lock_camera:
			break
	print("locked talk, cue sit")
	stage.cue_sit()
	for i: int in 120:
		await get_tree().process_frame
		stage.tick(1.0 / 60.0)
		var act := String(stage._action_name(stage.action))
		if i % 5 == 0 or act in ["sitdown", "seated"]:
			var look := _look_gx(cam)
			print(
				"f=", i, " act=", act,
				" rover=", stage._pos_gx,
				" lock=", stage.lock_camera,
				" morph=", stage.camera_morph,
				" look=", look,
				" tracks=", stage._camera_morph_tracks_rover,
			)
		if stage.action == IntroTrainStage.Action.SEATED and i > 50:
			break
	get_tree().quit()


func _look_gx(cam: Camera3D) -> Vector3:
	var fwd := -cam.global_transform.basis.z
	var eye := cam.global_position / FieldCatalog.GX_TO_METERS
	var t := 10.0
	var hit := eye + fwd * t
	return Vector3(hit.x, hit.y, hit.z)
