class_name TestTalkCamera
extends GdUnitTestSuite

## CAMERA2_PROCESS_TALK framing (`TalkCamera` / FollowCamera).


func test_talk_frame_is_closer_than_follow() -> void:
	var speaker := Node3D.new()
	var listener := Node3D.new()
	auto_free(speaker)
	auto_free(listener)
	speaker.position = Vector3(0.0, 0.0, 0.0)
	listener.position = Vector3(0.0, 0.0, 2.0)
	var framed: Dictionary = TalkCamera.frame(speaker, listener)
	var eye: Vector3 = framed["eye"] as Vector3
	var center: Vector3 = framed["center"] as Vector3
	var dist: float = float(framed["distance"])
	assert_float(dist).is_less(620.0 * PlayerLocomotion.UNIT_METERS)
	assert_float(dist).is_greater(TalkCamera.BASE_DIST_GX * FieldCatalog.GX_TO_METERS * 0.9)
	assert_float(eye.distance_to(center)).is_equal_approx(dist, 0.05)
	## Flatter than the 45° follow camera (inv pitch ~24°).
	var rise: float = eye.y - center.y
	assert_float(rise / dist).is_less(0.5)


func test_talk_yaw_flips_when_listener_is_east_vs_west() -> void:
	## `Camera2_Talk_GetAngleY`: N/S pair with a small E/W offset flips ±15° nudge.
	var south := Vector3(0.0, 0.0, 2.0)
	var north := Vector3(0.0, 0.0, 0.0)
	## Speaker south of listener, listener slightly east → one sign.
	var east_tweak: float = TalkCamera.yaw_tweak_deg(south + Vector3(-0.5, 0.0, 0.0), north)
	## Listener slightly west → opposite sign.
	var west_tweak: float = TalkCamera.yaw_tweak_deg(south + Vector3(0.5, 0.0, 0.0), north)
	assert_float(east_tweak).is_not_equal(0.0)
	assert_float(west_tweak).is_not_equal(0.0)
	assert_bool(signf(east_tweak) != signf(west_tweak)).is_true()
	assert_float(absf(east_tweak)).is_less_equal(TalkCamera.YAW_TWEAK_DEG + 0.01)
	assert_float(absf(west_tweak)).is_less_equal(TalkCamera.YAW_TWEAK_DEG + 0.01)


func test_talk_yaw_zero_when_pair_is_east_west() -> void:
	## E/W band (45°–135°) keeps world-south framing (no nudge).
	var tweak: float = TalkCamera.yaw_tweak_deg(Vector3(0.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0))
	assert_float(tweak).is_equal_approx(0.0, 0.001)


func test_talk_frame_eye_shifts_left_vs_right() -> void:
	var speaker := Node3D.new()
	var listener_e := Node3D.new()
	var listener_w := Node3D.new()
	auto_free(speaker)
	auto_free(listener_e)
	auto_free(listener_w)
	add_child(speaker)
	add_child(listener_e)
	add_child(listener_w)
	## Player (speaker) south of NPC; NPC east vs west of the aisle.
	speaker.position = Vector3(0.0, 0.0, 4.0)
	listener_e.position = Vector3(1.0, 0.0, 0.0)
	listener_w.position = Vector3(-1.0, 0.0, 0.0)
	var framed_e: Dictionary = TalkCamera.frame(speaker, listener_e)
	var framed_w: Dictionary = TalkCamera.frame(speaker, listener_w)
	var eye_e: Vector3 = framed_e["eye"] as Vector3
	var eye_w: Vector3 = framed_w["eye"] as Vector3
	var center_e: Vector3 = framed_e["center"] as Vector3
	var center_w: Vector3 = framed_w["center"] as Vector3
	## Lateral offset from look-at should flip with approach side.
	assert_float(float(framed_e["yaw_tweak_deg"])).is_not_equal(0.0)
	assert_bool(signf(eye_e.x - center_e.x) != signf(eye_w.x - center_w.x)).is_true()


func test_face_yaw_toward_npc() -> void:
	## `player_angle_y + 180°` — player south of NPC faces north (yaw ≈ π).
	var yaw: float = TalkCamera.face_yaw_toward(Vector3(0.0, 0.0, 4.0), Vector3(0.0, 0.0, 0.0))
	assert_float(absf(angle_difference(yaw, PI))).is_less(0.01)
	## Player west of NPC faces +X (east); `forward` = (sin yaw, 0, cos yaw).
	yaw = TalkCamera.face_yaw_toward(Vector3(-2.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
	assert_float(absf(angle_difference(yaw, PI * 0.5))).is_less(0.01)


func test_talk_face_eases_like_movement_talk() -> void:
	## `Player_actor_Movement_Talk` short_angle2 rates; south→north should close in.
	var facing: float = 0.0
	var target: float = TalkCamera.face_yaw_toward(Vector3(0.0, 0.0, 4.0), Vector3(0.0, 0.0, 0.0))
	for _i: int in 30:
		facing = MLib.short_angle2(
			facing,
			target,
			TalkCamera.TURN_FRACTION,
			TalkCamera.TURN_MAX_STEP,
			TalkCamera.TURN_MIN_STEP
		)
	assert_float(absf(angle_difference(facing, target))).is_less(0.01)


func test_talk_camera_begin_calls_player_face() -> void:
	var player: Node3D = _TalkFaceStub.new()
	auto_free(player)
	add_child(player)
	player.add_to_group("player")
	var npc := Node3D.new()
	auto_free(npc)
	add_child(npc)
	TalkCamera.begin(player, npc, get_tree())
	assert_that(player.faced).is_same(npc)
	TalkCamera.end(get_tree())
	assert_that(player.faced).is_null()


class _TalkFaceStub extends Node3D:
	var faced: Node3D = null

	func begin_talk_face(npc: Node3D) -> void:
		faced = npc

	func end_talk_face() -> void:
		faced = null


func test_blathers_greeting_loads() -> void:
	DialogueCatalog.reset()
	var data: DialogueData = DialogueCatalog.conversation(&"blathers_greeting")
	assert_that(data).is_not_null()
	var ctx := DialogueContext.from_game()
	ctx.speaker_name = "Blathers"
	ctx.already_talked = false
	var runner := DialogueRunner.new()
	runner.start(data, ctx)
	assert_str(runner.line).contains("welcome to the museum")
	ctx.already_talked = true
	runner.start(data, ctx)
	assert_str(runner.line).contains("Still exploring")


func test_follow_camera_begin_end_talk() -> void:
	var cam := Camera3D.new()
	cam.set_script(load("res://scenes/world/follow_camera.gd"))
	auto_free(cam)
	add_child(cam)
	await get_tree().process_frame
	var speaker := Node3D.new()
	var listener := Node3D.new()
	auto_free(speaker)
	auto_free(listener)
	add_child(speaker)
	add_child(listener)
	speaker.position = Vector3(4.0, 0.0, 4.0)
	listener.position = Vector3(4.0, 0.0, 6.0)
	cam.call("set_target", listener)
	await get_tree().process_frame
	var follow_pos: Vector3 = cam.global_position
	cam.call("begin_talk", speaker, listener)
	assert_bool(cam.call("is_talking")).is_true()
	## Morph in — no snap on begin.
	assert_vector(cam.global_position).is_equal(follow_pos)
	for _i: int in 20:
		await get_tree().process_frame
	assert_bool(cam.global_position.distance_to(follow_pos) > 0.5).is_true()
	cam.call("end_talk")
	assert_bool(cam.call("is_talking")).is_false()
