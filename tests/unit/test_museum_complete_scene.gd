class_name TestMuseumCompleteScene
extends GdUnitTestSuite

## Museum complete harness instances per-room `.tscn` files.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_each_museum_room_is_its_own_scene() -> void:
	for wing: String in [
		"museum_entrance",
		"museum_painting",
		"museum_fossil",
		"museum_insect",
		"museum_fish",
	]:
		var path := "res://scenes/world/museum/%s.tscn" % wing
		var packed: PackedScene = load(path)
		assert_that(packed).is_not_null()
		var room: Node3D = auto_free(packed.instantiate()) as Node3D
		assert_that(room).is_not_null()
		assert_that(room.get("room_id")).is_equal(StringName(wing))
		assert_that(room.get_node_or_null("Shell/GeneratedVisual")).is_not_null()
		assert_that(room.get_node_or_null("Terrain")).is_not_null()
		assert_that(room.get_node_or_null("Furniture")).is_not_null()
		assert_that(room.get_node_or_null("Doors")).is_not_null()
		assert_that(room.get_node_or_null("PlayerSpawn")).is_not_null()
		assert_bool(room.has_method("populate")).is_true()
	## Shells match field_data.
	var painting: Node = load("res://scenes/world/museum/museum_painting.tscn").instantiate()
	auto_free(painting)
	assert_that(painting.get_node_or_null("Shell/GeneratedVisual/rom_museum3")).is_not_null()
	var fossil: Node = load("res://scenes/world/museum/museum_fossil.tscn").instantiate()
	auto_free(fossil)
	assert_that(fossil.get_node_or_null("Shell/GeneratedVisual/rom_museum2")).is_not_null()
	var entrance: Node = load("res://scenes/world/museum/museum_entrance.tscn").instantiate()
	auto_free(entrance)
	var doors: Node = entrance.get_node("Doors")
	assert_that(doors.get_node_or_null("Link_museum_painting")).is_not_null()
	assert_that(doors.get_node_or_null("Link_museum_fossil")).is_not_null()
	assert_that(doors.get_node_or_null("Link_museum_insect")).is_not_null()
	assert_that(doors.get_node_or_null("Link_museum_fish")).is_not_null()
	assert_that(doors.get_node_or_null("Exit")).is_not_null()


func test_museum_complete_instances_room_scenes() -> void:
	var packed: PackedScene = load("res://scenes/dev/museum_complete.tscn")
	assert_that(packed).is_not_null()
	var scene: Node3D = auto_free(packed.instantiate()) as Node3D
	add_child(scene)
	await get_tree().process_frame
	assert_bool(scene.is_in_group("museum_complete_stage")).is_true()
	var rooms: Node = scene.get_node("Rooms")
	for wing: String in [
		"museum_entrance",
		"museum_painting",
		"museum_fossil",
		"museum_insect",
		"museum_fish",
	]:
		assert_that(rooms.get_node_or_null(wing)).is_not_null()
	## Painting exhibits live under that room scene only.
	assert_int(rooms.get_node("museum_painting/Furniture").get_child_count()).is_greater(0)
	assert_int(rooms.get_node("museum_entrance/Furniture").get_child_count()).is_equal(0)
	## Each wing owns Terrain shell colliders after populate.
	assert_int(_static_body_count(rooms.get_node("museum_painting/Terrain"))).is_greater(3)
	assert_int(_static_body_count(rooms.get_node("museum_fossil/Terrain"))).is_greater(3)
	assert_that(
		rooms.get_node_or_null("museum_fossil/Furniture/Fossil_00/ExhibitCollision")
	).is_not_null()
	assert_bool(Game.try_enter_interior(&"museum_painting")).is_true()
	await get_tree().process_frame
	assert_that(Game.current_room_id).is_equal(&"museum_painting")
	assert_bool((rooms.get_node("museum_painting") as Node3D).visible).is_true()
	assert_bool((rooms.get_node("museum_entrance") as Node3D).visible).is_false()


func _static_body_count(node: Node) -> int:
	var n := 0
	for child: Node in node.get_children():
		if child is StaticBody3D:
			n += 1
	return n
