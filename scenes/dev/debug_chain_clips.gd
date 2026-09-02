extends Node

## Chain walk(tree) -> to_deck -> keitai_on like phone sequence.


func _ready() -> void:
	Clock.paused = true
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate()
	add_child(intro)
	_run(intro)


func _run(intro: Node3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var rover: IntroTrainRoverAnim = intro.get_node("%Rover") as IntroTrainRoverAnim
	var anim: AnimationPlayer = rover.body_animation_player()
	rover.intro_clip_finished.connect(func(s: StringName) -> void:
		print("finished suffix=", s)
	)
	print("1 walk")
	rover.play_intro_clip(IntroTrainStage.ANIM_WALK, true)
	await get_tree().create_timer(0.5).timeout
	print("2 to_deck")
	rover.play_intro_clip(IntroTrainStage.ANIM_TO_DECK, false)
	await _wait_clip(rover, anim, "to_deck")
	print("3 keitai_on")
	rover.play_intro_clip(IntroTrainStage.ANIM_KEITAI_ON, false, IntroTrainStage.KEITAI_ON_ANIM_SPEED)
	await _wait_clip(rover, anim, "keitai_on")
	print("CHAIN OK")
	get_tree().quit()


func _wait_clip(rover: IntroTrainRoverAnim, anim: AnimationPlayer, label: String) -> void:
	for i: int in 900:
		await get_tree().process_frame
		if i % 30 == 0:
			print(
				label, " f=", i, " current=", anim.current_animation,
				" pos=", snappedf(anim.current_animation_position, 2),
				" active=", rover.get("_clip_active"),
				" tree=", rover.get("_tree").active if rover.get("_tree") else "?",
			)
		if not rover.get("_clip_active"):
			print(label, " done f=", i)
			return
	print(label, " TIMEOUT")
