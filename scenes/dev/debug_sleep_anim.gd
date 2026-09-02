extends Node

## Verify sleep passenger animation advances.


func _ready() -> void:
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate()
	add_child(intro)
	_watch(intro)


func _watch(intro: Node3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var sleep: IntroTrainSleepNpc = intro.get_node("%SleepPassenger") as IntroTrainSleepNpc
	var anim: AnimationPlayer = sleep.get("_anim") as AnimationPlayer
	var last_pos: float = -1.0
	var changes: int = 0
	for i: int in 1800:
		await get_tree().process_frame
		if anim == null:
			continue
		var pos: float = anim.current_animation_position
		if last_pos >= 0.0 and absf(pos - last_pos) > 0.05:
			changes += 1
		last_pos = pos
		if i % 300 == 0:
			print(
				"f=", i, " clip=", anim.current_animation,
				" pos=", snappedf(pos, 2), " playing=", anim.is_playing(),
				" changes=", changes,
			)
	print("sleep_anim_changes=", changes)
	get_tree().quit()
