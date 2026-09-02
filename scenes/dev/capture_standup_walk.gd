extends Node

## Capture frames + logs around standup -> walk. Run:
## Godot --path . res://scenes/dev/capture_standup_walk.tscn

const OUT_DIR := "res://recordings/standup_walk_capture"


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate()
	add_child(intro)
	_run(intro)


func _run(intro: Node3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not IntroTrainStage.missing_assets().is_empty():
		push_error("missing assets")
		get_tree().quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var stage: IntroTrainStage = intro.get("_stage")
	var rover: IntroTrainRoverAnim = intro.get_node("%Rover") as IntroTrainRoverAnim
	var anim: AnimationPlayer = rover.body_animation_player()
	stage._pos_gx = IntroTrainStage.ROVER_SIT_GX
	stage._yaw = 0.0
	stage.action = IntroTrainStage.Action.SEATED
	stage._apply_rover_pose()
	rover.play_intro_clip(IntroTrainStage.ANIM_SIT_WAIT, true)
	await get_tree().create_timer(0.3).timeout
	stage.cue_phone()
	var move_aisle_frame := -1
	for i: int in 400:
		await get_tree().process_frame
		var act := String(stage._action_name(stage.action))
		if act in ["standup", "move_aisle"] and i >= 38 and i <= 70:
			_capture(intro, "transition_%04d_%s" % [i, act])
			print(
				"f=", i, " act=", act,
				" anim=", anim.current_animation,
				" yaw=", snappedf(rad_to_deg(stage._yaw), 1),
				" turn=", snappedf(stage._aisle_turn_t, 3),
			)
		if act == "move_aisle" and move_aisle_frame < 0:
			move_aisle_frame = i
		if act == "move_door":
			print("MOVE_DOOR f=", i)
			break
	print("done move_aisle=", move_aisle_frame)
	get_tree().quit()


func _capture(intro: Node3D, name: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := intro.get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.save_png("%s/%s.png" % [OUT_DIR, name])
