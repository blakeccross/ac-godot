class_name TestTouchPick
extends GdUnitTestSuite

## Screen point ↔ ground, and the stick that walks a world direction.


func _cam() -> Camera3D:
	var cam: Camera3D = auto_free(Camera3D.new()) as Camera3D
	add_child(cam)
	cam.fov = 20.0
	cam.global_position = Vector3(3, 0, -2) + FollowCamera.DEFAULT_OFFSET
	cam.look_at(Vector3(3, 0, -2))
	cam.current = true
	return cam


func test_a_projected_point_picks_back_to_itself() -> void:
	var cam: Camera3D = _cam()
	for p: Vector3 in [Vector3(3, 0, -2), Vector3(7, 0, 1), Vector3(-1, 0, -5)]:
		var hit: Dictionary = TouchPick.ground(cam, cam.unproject_position(p), 0.0)
		assert_bool(bool(hit["hit"])).is_true()
		assert_vector(hit["pos"] as Vector3).is_equal_approx(p, Vector3.ONE * 0.05)


func test_the_stick_walks_the_world_direction() -> void:
	var cam: Camera3D = _cam()
	var player: Player = auto_free(load("res://features/player/player.tscn").instantiate()) as Player
	add_child(player)
	for dir: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3(-1, 0, 1).normalized()]:
		var stick: Vector2 = TouchPick.stick_for(cam, dir)
		assert_float(player._camera_wish(stick).normalized().dot(dir)).is_greater(0.999)
