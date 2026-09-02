extends Node

## Verify keitai_on clip completion via AnimationPlayer.


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
	var clip := IntroTrainStage.resolve_rover_clip(anim, IntroTrainStage.ANIM_KEITAI_ON)
	var a: Animation = anim.get_animation(clip)
	print("clip=", clip, " len=", a.length if a else -1, " loop=", a.loop_mode if a else -1)
	var finished := false
	anim.animation_finished.connect(func(name: StringName) -> void:
		print("anim_finished name=", name, " pos=", anim.current_animation_position)
		finished = true
	)
	rover.intro_clip_finished.connect(func(suffix: StringName) -> void:
		print("intro_clip_finished suffix=", suffix)
	)
	rover.play_intro_clip(IntroTrainStage.ANIM_KEITAI_ON, false, IntroTrainStage.KEITAI_ON_ANIM_SPEED)
	print("after play: current=", anim.current_animation, " playing=", anim.is_playing(), " speed=", anim.speed_scale)
	for i: int in 1200:
		await get_tree().process_frame
		if i % 60 == 0:
			print(
				"f=", i, " current=", anim.current_animation,
				" pos=", snappedf(anim.current_animation_position, 2),
				" playing=", anim.is_playing(),
				" clip_active=", rover.get("_clip_active"),
			)
		if finished or not rover.get("_clip_active"):
			print("DONE at f=", i, " finished=", finished)
			break
		if i == 1199:
			print("TIMEOUT")
	get_tree().quit()
