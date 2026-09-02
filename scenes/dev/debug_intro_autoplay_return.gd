extends Node

## Real intro scene: phone_done path through return walk.


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate()
	intro.auto_advance_dialogue = true
	add_child(intro)
	_watch(intro)


func _watch(intro: Node3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var stage: IntroTrainStage = intro.get("_stage")
	for i: int in 12000:
		await get_tree().process_frame
		var act := String(stage._action_name(stage.action))
		if i % 120 == 0 or act in ["keitai_off", "open_door", "return_approach", "talk"]:
			print(
				"f=", i, " act=", act, " z=", snappedf(stage._pos_gx.z, 1),
				" pending=", stage._pending_suffix,
			)
		if act == "return_approach" and stage._pos_gx.z > 250.0:
			print("RETURN OK z=", stage._pos_gx.z, " at f=", i)
			break
		if i == 4999:
			print("TIMEOUT act=", act, " z=", stage._pos_gx.z)
	get_tree().quit()
