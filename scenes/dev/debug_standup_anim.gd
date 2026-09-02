extends Node


func _ready() -> void:
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate()
	add_child(intro)
	await get_tree().process_frame
	await get_tree().process_frame
	var rover: IntroTrainRoverAnim = intro.get_node("%Rover") as IntroTrainRoverAnim
	var anim: AnimationPlayer = rover.body_animation_player()
	if IntroTrainStage.missing_assets().size() > 0:
		get_tree().quit()
		return
	for clip: String in ["npc_1_sitdown_wait_d1", "npc_1_standup_d1", "npc_1_walk1"]:
		anim.stop()
		anim.play(clip, 0.0)
		print("play ", clip, " len=", anim.get_animation(clip).length)
		for i: int in 30:
			await get_tree().process_frame
			if i % 10 == 0:
				print("  f=", i, " pos=", snappedf(anim.current_animation_position, 3))
	get_tree().quit()
