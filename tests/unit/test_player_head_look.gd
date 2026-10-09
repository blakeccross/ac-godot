class_name TestPlayerHeadLook
extends GdUnitTestSuite

## The player's `head_angle` while watching something they let go.


func test_bearing_and_elevation_are_clamped() -> void:
	var gx: float = FieldCatalog.GX_TO_METERS
	## Close by: no turn (`dist_xz >= 18`).
	assert_that(PlayerHeadLook.want(Vector3.ZERO, 0.0, Vector3(0.0, 0.0, 10.0 * gx))).is_equal(Vector2.ZERO)
	var right: Vector2 = PlayerHeadLook.want(Vector3.ZERO, 0.0, Vector3(3.0, 0.0, 0.0))
	assert_float(right.x).is_equal_approx(PlayerHeadLook.YAW_LIMIT, 1e-5)
	var up: Vector2 = PlayerHeadLook.want(Vector3.ZERO, 0.0, Vector3(0.0, 5.0, 2.0))
	assert_float(up.y).is_equal_approx(PlayerHeadLook.PITCH_LIMIT, 1e-5)


func test_the_head_eases_toward_the_target() -> void:
	var look := PlayerHeadLook.new()
	look.step(Vector2(1.0, 0.0))
	## 500 / 65536 of a turn at most a tick.
	assert_float(look.angle.x).is_equal_approx(PlayerHeadLook.MAX_STEP, 1e-6)
	for i: int in 60:
		look.step(Vector2(1.0, 0.0))
	assert_float(look.angle.x).is_equal_approx(1.0, 1e-3)


func test_the_turn_is_about_the_vertical_whatever_the_joint_axes() -> void:
	var skel := Skeleton3D.new()
	add_child(skel)
	skel.add_bone("neck")
	skel.add_bone("head_boy_model")
	skel.set_bone_parent(1, 0)
	## A parent frame lying on its side, like the converted cKF joints.
	skel.set_bone_pose_rotation(0, Quaternion(Vector3(0.3, 0.2, 1.0).normalized(), 1.7))
	skel.set_bone_pose_rotation(1, Quaternion(Vector3(1.0, 0.0, 0.4).normalized(), 0.6))
	var look := PlayerHeadLook.new()
	look.bind(skel, null)
	var before: Basis = skel.global_transform.basis * skel.get_bone_global_pose(1).basis
	look.angle = Vector2(deg_to_rad(40.0), 0.0)
	look._apply()
	var after: Basis = skel.global_transform.basis * skel.get_bone_global_pose(1).basis
	var turn: Basis = after * before.inverse()
	assert_float(turn.get_rotation_quaternion().get_axis().dot(Vector3.UP)).is_equal_approx(1.0, 1e-4)
	assert_float(turn.get_rotation_quaternion().get_angle()).is_equal_approx(deg_to_rad(40.0), 1e-4)
	look.unbind()
	skel.free()
