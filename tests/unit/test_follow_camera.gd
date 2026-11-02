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


func test_portrait_opens_the_lens_a_little() -> void:
	assert_float(FollowCamera.fov_for_aspect(16.0 / 9.0)).is_equal_approx(FollowCamera.BASE_FOV, 0.001)
	assert_float(FollowCamera.fov_for_aspect(21.0 / 9.0)).is_equal_approx(FollowCamera.BASE_FOV, 0.001)
	var portrait: float = FollowCamera.fov_for_aspect(9.0 / 16.0)
	assert_float(portrait).is_between(FollowCamera.BASE_FOV + 1.0, FollowCamera.NARROW_FOV_MAX)
	var phone: float = FollowCamera.fov_for_aspect(9.0 / 19.5)
	assert_float(phone).is_equal_approx(FollowCamera.NARROW_FOV_MAX, 0.05)
	var standard: float = FollowCamera.fov_for_aspect(4.0 / 3.0)
	assert_float(standard).is_between(FollowCamera.BASE_FOV, portrait)


func test_look_center_is_the_eased_lookat_not_the_eye() -> void:
	## `Camera2_getCenterPos_p` — weather spawn boxes use this.
	var cam: FollowCamera = _camera()
	var center := Vector3(4.0, 1.5, -3.0)
	cam._look_current = center
	cam._has_look = true
	cam.global_position = center + FollowCamera.DEFAULT_OFFSET
	assert_vector(cam.look_center()).is_equal(center)
	assert_vector(cam.look_center()).is_not_equal(cam.global_position)


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
	@warning_ignore("integer_division")
	for _i in ticks / 2:
		cam._follow_door(false, 1.0 / 60.0)
	var halfway: float = cam.global_position.distance_to(cam._look_current)
	assert_float(halfway).is_between(FollowCamera.DOOR_DISTANCE + 0.5, FollowCamera.FOLLOW_DISTANCE - 0.5)
	@warning_ignore("integer_division")
	for _i in ticks - ticks / 2:
		cam._follow_door(false, 1.0 / 60.0)
	assert_vector(cam._look_current).is_equal_approx(center, Vector3.ONE * 0.001)
	assert_float(cam.global_position.distance_to(center)).is_equal_approx(FollowCamera.DOOR_DISTANCE, 0.001)


func test_a_report_closes_in_to_370_at_37_degrees() -> void:
	## `Camera2_SetPos_Item`: 620 − 250 GX, 1400 short angles under the 45° base.
	var cam: FollowCamera = _camera()
	var player := Node3D.new()
	auto_free(player)
	add_child(player)
	player.global_position = Vector3(2.0, 0.0, 3.0)
	cam.global_position = player.global_position + FollowCamera.DEFAULT_OFFSET
	cam._look_current = player.global_position
	cam._has_look = true
	cam.begin_item(player)
	for _i in 600:
		cam._follow_item(1.0 / 60.0)
	var center: Vector3 = player.global_position + FollowCamera.ITEM_CENTER
	assert_vector(cam._look_current).is_equal_approx(center, Vector3.ONE * 0.01)
	assert_float(cam.global_position.distance_to(center) / PlayerLocomotion.UNIT_METERS).is_equal_approx(370.0, 0.5)
	var arm: Vector3 = cam.global_position - center
	assert_float(rad_to_deg(atan2(arm.y, Vector2(arm.x, arm.z).length()))).is_equal_approx(37.31, 0.05)
	cam.end_item()
	assert_bool(cam.is_item()).is_false()


## --- indoor C-stick index (`Player_actor_Set_Indoor_Camera_Index`) ------------------------


func test_indoor_index_clamps_and_reports_moves() -> void:
	var cam: FollowCamera = _camera()
	assert_that(cam.indoor_index()).is_equal(Vector2i(1, 1))
	assert_bool(cam.step_indoor(-1, 0)).is_true()
	assert_bool(cam.step_indoor(-1, 0)).is_false()
	assert_bool(cam.step_indoor(0, 1)).is_true()
	assert_bool(cam.step_indoor(0, 1)).is_false()
	assert_that(cam.indoor_index()).is_equal(Vector2i(0, 2))


func test_indoor_index_moves_the_arm() -> void:
	## 620 GX at 45° by default; closer is 340 GX at 21.76°, farther 920 GX at 64.12°.
	var cam: FollowCamera = _camera()
	var base: Vector3 = FollowCamera.DEFAULT_OFFSET
	cam._ease_indoor(0.0, true)
	assert_vector(cam.indoor_offset(base)).is_equal_approx(base, Vector3.ONE * 0.001)
	cam.step_indoor(-1, 0)
	cam._ease_indoor(0.0, true)
	var near: Vector3 = cam.indoor_offset(base)
	assert_float(near.length()).is_equal_approx(340.0 * 0.05, 0.01)
	assert_float(rad_to_deg(atan2(near.y, Vector2(near.x, near.z).length()))).is_equal_approx(21.76, 0.01)
	cam.step_indoor(2, 1)
	cam._ease_indoor(0.0, true)
	var far: Vector3 = cam.indoor_offset(base)
	assert_float(far.length()).is_equal_approx(920.0 * 0.05, 0.01)
	assert_float(rad_to_deg(atan2(far.y, Vector2(far.x, far.z).length()))).is_equal_approx(64.12, 0.01)
	assert_float(rad_to_deg(atan2(far.x, far.z))).is_equal_approx(16.1, 0.01)


func test_indoor_index_morphs_in_over_about_80_ticks() -> void:
	var cam: FollowCamera = _camera()
	cam._ease_indoor(0.0, true)
	cam.step_indoor(1, 0)
	for _i: int in 80:
		cam._ease_indoor(1.0 / 60.0, false)
	assert_float(cam._indoor_dist_add).is_equal_approx(15.0, 0.01)
	assert_float(cam._indoor_pitch_add).is_equal_approx(deg_to_rad(19.12), deg_to_rad(0.1))


func test_only_homes_and_museum_wings_take_the_index() -> void:
	assert_bool(InteriorLighting.allows_camera_index(InteriorCatalog.room_template(&"museum_insect"))).is_true()
	assert_bool(InteriorLighting.allows_camera_index(InteriorCatalog.room_template(&"museum_entrance"))).is_false()
	assert_bool(InteriorLighting.allows_camera_index(InteriorCatalog.room_template(&"police_box"))).is_false()


func test_room_center_follows_inside_the_border_and_centres_small_rooms() -> void:
	## 28 m × 24 m (a museum wing): follow, 5.5 m off the far edge, 7.5 m from the near one.
	var wing := AABB(Vector3(2, 0, 2), Vector3(28, 3, 24))
	var at: Vector3 = FollowCamera.room_center(Vector3(3, 1, 3), wing, 1, 1)
	assert_float(at.x).is_equal_approx(7.5, 0.001)
	assert_float(at.z).is_equal_approx(7.5, 0.001)
	var near: Vector3 = FollowCamera.room_center(Vector3(29, 1, 25), wing, 1, 1)
	assert_float(near.x).is_equal_approx(24.5, 0.001)
	assert_float(near.z).is_equal_approx(22.5, 0.001)
	## A 12 m home is narrower than 330 GX: its middle.
	var home := AABB(Vector3(0, 0, 0), Vector3(12, 3, 12))
	var mid: Vector3 = FollowCamera.room_center(Vector3(1, 1, 11), home, 1, 1)
	assert_float(mid.x).is_equal_approx(6.0, 0.001)
	assert_float(mid.z).is_equal_approx(6.0, 0.001)


func test_small_house_zooms_out_past_the_exit() -> void:
	## The rug is centred in frame. The door is south of it, so the arm lengthens until
	## a step of floor past that wall is still inside the lens.
	var room: Room = InteriorCatalog.room_template(&"player_main")
	var session := IndoorSession.new()
	session.bind(room)
	var carpet: AABB = InteriorShellBuilder.shell_bounds(room, session.grid)
	var south: float = InteriorShellBuilder.south_floor_z(room, session.grid)
	var offset: Vector3 = FollowCamera.offset_to_show_south(carpet, south)
	assert_float(offset.length()).is_greater(FollowCamera.FOLLOW_DISTANCE)
	var look: Vector3 = FollowCamera.room_center(
		Vector3(carpet.get_center().x, 0.0, carpet.end.z + 50.0), carpet, 1, 1
	)
	var shown: float = look.z + FollowCamera.south_floor_past_look(offset.length())
	assert_float(shown).is_greater_equal(south + FollowCamera.SOUTH_FLOOR_MARGIN - 0.05)


func test_a_deep_room_keeps_the_normal_arm() -> void:
	var wing := AABB(Vector3(0, 0, 0), Vector3(28, 3, 24))
	var offset: Vector3 = FollowCamera.offset_to_show_south(wing, wing.end.z)
	assert_float(offset.length()).is_equal_approx(FollowCamera.FOLLOW_DISTANCE, 0.05)
