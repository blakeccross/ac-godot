class_name TestBodyAnimator
extends GdUnitTestSuite

## `BodyAnimator` over the player model's clips.

const STEP := 1.0 / 60.0


func _animator() -> BodyAnimator:
	if not ResourceLoader.exists(Player.PLAYER_BOY_GLB):
		return null
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	var body: Node3D = (load(Player.PLAYER_BOY_GLB) as PackedScene).instantiate()
	host.add_child(body)
	var animator := BodyAnimator.new()
	animator.tree_root = load("res://scenes/actors/player_animation.tres")
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	host.add_child(animator)
	var player: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
	animator.bind(player)
	for clip: String in ["ply_1_walk1", "ply_1_run1", "ply_1_wait1"]:
		animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return animator


func _run(animator: BodyAnimator, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		animator.advance(STEP)
		t += STEP


func test_switching_gait_keeps_the_step_phase() -> void:
	var a := _animator()
	if a == null:
		return  ## player model not generated (no disc)
	a.play(&"ply_1_wait1")
	_run(a, 0.2)
	a.play_gait(&"walk", 1.0, 0.0)
	assert_float(a.current_animation_position).is_equal_approx(0.0, 0.001)
	_run(a, 0.25)
	var phase: float = a.current_animation_position
	a.play_gait(&"run", 1.0, 0.1)
	assert_str(a.current_animation).is_equal("ply_1_run1")
	_run(a, 0.05)
	assert_float(a.current_animation_position).is_equal_approx(phase + 0.05, 0.002)


func test_gait_rate_scales_the_clock() -> void:
	var a := _animator()
	if a == null:
		return
	a.play_gait(&"walk", 2.0, 0.0)
	a.advance(0.0)
	_run(a, 0.1)
	assert_float(a.current_animation_position).is_equal_approx(0.2, 0.002)


func test_a_one_shot_stops_at_its_end_and_says_so() -> void:
	var a := _animator()
	if a == null:
		return
	var finished: Array[StringName] = []
	a.animation_finished.connect(func(clip: StringName) -> void: finished.append(clip))
	var clip: Animation = a.get_animation(&"ply_1_getoff1")
	clip.loop_mode = Animation.LOOP_NONE
	a.play(&"ply_1_getoff1", 0.1)
	assert_bool(a.is_playing()).is_true()
	assert_str(a.current_animation).is_equal("ply_1_getoff1")
	_run(a, clip.length * 0.5)
	assert_bool(a.is_playing()).is_true()
	_run(a, clip.length * 0.5 + 0.1)
	assert_bool(a.is_playing()).is_false()
	assert_array(finished).contains_exactly([&"ply_1_getoff1"])


func test_seek_moves_the_clip_now() -> void:
	var a := _animator()
	if a == null:
		return
	a.play(&"ply_1_getoff1", 0.0)
	a.seek(0.4, true)
	assert_float(a.current_animation_position).is_equal_approx(0.4, 0.001)
	_run(a, 0.1)
	assert_float(a.current_animation_position).is_equal_approx(0.5, 0.002)


func test_playing_the_running_clip_again_carries_on() -> void:
	var a := _animator()
	if a == null:
		return
	a.play(&"ply_1_wait1")
	_run(a, 0.3)
	a.play(&"ply_1_wait1", 0.12)
	_run(a, STEP)
	assert_float(a.current_animation_position).is_greater(0.3)


func test_backwards_runs_from_the_end_to_the_start() -> void:
	var a := _animator()
	if a == null:
		return
	var clip: Animation = a.get_animation(&"ply_1_putaway1")
	clip.loop_mode = Animation.LOOP_NONE
	a.speed_scale = 1.0
	a.play_backwards(&"ply_1_putaway1", 0.0)
	a.advance(0.0)
	assert_float(a.current_animation_position).is_equal_approx(clip.length, 0.002)
	_run(a, clip.length + 0.1)
	assert_bool(a.is_playing()).is_false()


func test_the_tree_poses_the_model_skeleton() -> void:
	var a := _animator()
	if a == null:
		return
	var skeleton: Skeleton3D = a.get_parent().find_children("*", "Skeleton3D", true, false)[0]
	a.play_gait(&"walk", 1.0, 0.0)
	a.advance(0.0)
	var poses: Array[Quaternion] = []
	for i: int in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose_rotation(i))
	_run(a, 0.25)
	var moved: int = 0
	for i: int in skeleton.get_bone_count():
		if not skeleton.get_bone_pose_rotation(i).is_equal_approx(poses[i]):
			moved += 1
	assert_int(moved).is_greater(4)
