class_name TestFollowCamera
extends GdUnitTestSuite

## `FollowCamera`'s door framing against `Camera2_Door_SetEyePos` / `Camera2_setup_main_Door`.


func _camera() -> FollowCamera:
	var cam := FollowCamera.new()
	auto_free(cam)
	add_child(cam)
	cam.suspend()
	return cam


func _elevation(cam: FollowCamera, center: Vector3) -> float:
	var arm: Vector3 = cam.global_position - center
	return atan2(arm.y, Vector2(arm.x, arm.z).length())


func test_coming_out_snaps_to_the_door_framing() -> void:
	var cam: FollowCamera = _camera()
	var center := Vector3(3.0, 1.65, -2.0)
	cam.begin_door(center, false)
	cam._follow_door(false, 1.0 / 60.0)
	assert_float(cam.global_position.distance_to(center)).is_equal_approx(FollowCamera.DOOR_DISTANCE, 0.001)
	## 350 GX at about 20.3° above the horizontal, due south of the player's eye.
	assert_float(rad_to_deg(_elevation(cam, center))).is_equal_approx(20.28, 0.05)
	assert_float(cam.global_position.x).is_equal_approx(center.x, 0.001)
	assert_float(cam.global_position.z).is_greater(center.z)


func test_going_in_morphs_over_140_ticks() -> void:
	var cam: FollowCamera = _camera()
	## Start from the plain 620 / 45° follow framing.
	var start := Vector3.ZERO
	cam.global_position = start + FollowCamera.DEFAULT_OFFSET
	cam._look_current = start
	cam._has_look = true
	var center := Vector3(1.0, 1.65, 1.0)
	cam.begin_door(center, true)
	var ticks: int = roundi(FollowCamera.DOOR_MORPH_SECONDS * 60.0)
	for _i in ticks / 2:
		cam._follow_door(false, 1.0 / 60.0)
	var halfway: float = cam.global_position.distance_to(cam._look_current)
	assert_float(halfway).is_between(FollowCamera.DOOR_DISTANCE + 0.5, FollowCamera.FOLLOW_DISTANCE - 0.5)
	for _i in ticks - ticks / 2:
		cam._follow_door(false, 1.0 / 60.0)
	assert_vector(cam._look_current).is_equal_approx(center, Vector3.ONE * 0.001)
	assert_float(cam.global_position.distance_to(center)).is_equal_approx(FollowCamera.DOOR_DISTANCE, 0.001)
