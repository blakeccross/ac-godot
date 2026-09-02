class_name TestHostCollision
extends GdUnitTestSuite


func test_box_matches_building_footprint() -> void:
	var xz: Vector2 = HostCollision.xz_size(Vector2i(2, 2), 2.0)
	assert_float(xz.x).is_equal_approx(2.0 * 2.0 * HostCollision.INSET, 0.001)
	assert_float(xz.y).is_equal_approx(xz.x, 0.001)
	var npc: Vector2 = HostCollision.xz_size(Vector2i(3, 3), 2.0)
	assert_float(npc.x).is_greater(xz.x)


func test_player_house_sensor_not_a_physics_box() -> void:
	var house: StaticBody3D = auto_free(load("res://scenes/world/house.tscn").instantiate()) as StaticBody3D
	house.visual_id = &"obj_s_myhome1"
	house.footprint = Vector2i(2, 2)
	add_child(house)
	var col: CollisionShape3D = house.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(col.disabled).is_true()
	assert_int(house.collision_layer).is_equal(0)
	var door: Node3D = house.get_node("InteractVolume") as Node3D
	var stand: Vector3 = HostCollision.player_door_offset()
	assert_float(door.position.x).is_equal_approx(stand.x, 0.05)
	assert_float(door.position.z).is_equal_approx(stand.z, 0.05)


func test_npc_house_disables_physics() -> void:
	var house: StaticBody3D = auto_free(load("res://scenes/world/house.tscn").instantiate()) as StaticBody3D
	house.footprint = Vector2i(3, 3)
	add_child(house)
	var col: CollisionShape3D = house.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(col.disabled).is_true()
	var door: Node3D = house.get_node("InteractVolume") as Node3D
	var xz: Vector2 = HostCollision.xz_size(Vector2i(3, 3), 2.0)
	assert_float(door.position.z).is_greater(xz.y * 0.5)


func test_shop_disables_physics() -> void:
	var shop: StaticBody3D = auto_free(load("res://scenes/world/shop.tscn").instantiate()) as StaticBody3D
	add_child(shop)
	var col: CollisionShape3D = shop.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(col.disabled).is_true()
	assert_int(shop.collision_layer).is_equal(0)
	var door: Node3D = shop.get_node("InteractVolume") as Node3D
	var stand: Vector3 = HostCollision.door_offset(&"obj_s_shop1")
	assert_float(door.position.x).is_equal_approx(stand.x, 0.05)
	assert_float(door.position.z).is_equal_approx(stand.z, 0.05)
	assert_float(door.position.x).is_less(0.0)
	assert_float(door.position.z).is_greater(0.0)


func test_museum_disables_physics() -> void:
	var building: StaticBody3D = auto_free(load("res://scenes/world/building.tscn").instantiate()) as StaticBody3D
	building.visual_id = &"obj_s_museum"
	building.footprint = Vector2i(2, 2)
	add_child(building)
	var col: CollisionShape3D = building.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(col.disabled).is_true()
	assert_int(building.collision_layer).is_equal(0)
	var door: Node3D = building.get_node("Door") as Node3D
	var stand: Vector3 = HostCollision.door_offset(&"obj_s_museum")
	assert_float(door.position.x).is_equal_approx(stand.x, 0.05)
	assert_float(door.position.z).is_equal_approx(stand.z, 0.05)
	assert_float(door.position.z).is_greater(2.0)
	assert_bool(door.get("auto_enter")).is_true()


func test_able_sisters_disables_physics() -> void:
	var building: StaticBody3D = auto_free(load("res://scenes/world/building.tscn").instantiate()) as StaticBody3D
	building.visual_id = &"obj_s_tailor"
	building.footprint = Vector2i(2, 2)
	add_child(building)
	var col: CollisionShape3D = building.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(col.disabled).is_true()
	assert_int(building.collision_layer).is_equal(0)
	var door: Node3D = building.get_node("Door") as Node3D
	var stand: Vector3 = HostCollision.door_offset(&"obj_s_tailor")
	assert_float(door.position.x).is_equal_approx(stand.x, 0.05)
	assert_float(door.position.z).is_equal_approx(stand.z, 0.05)
	assert_float(door.position.x).is_less(0.0)


func test_police_disables_physics() -> void:
	var building: StaticBody3D = auto_free(load("res://scenes/world/building.tscn").instantiate()) as StaticBody3D
	building.visual_id = &"obj_s_kouban"
	building.footprint = Vector2i(3, 3)
	add_child(building)
	var col: CollisionShape3D = building.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(col.disabled).is_true()
	assert_int(building.collision_layer).is_equal(0)
	var door: Node3D = building.get_node("Door") as Node3D
	var stand: Vector3 = HostCollision.door_offset(&"obj_s_kouban")
	assert_float(door.position.x).is_equal_approx(stand.x, 0.05)
	assert_float(door.position.z).is_equal_approx(stand.z, 0.05)
	assert_float(door.position.x).is_greater(0.0)


func test_post_office_disables_physics() -> void:
	var building: StaticBody3D = auto_free(load("res://scenes/world/building.tscn").instantiate()) as StaticBody3D
	building.visual_id = &"obj_s_yubinkyoku"
	building.footprint = Vector2i(2, 2)
	add_child(building)
	var col: CollisionShape3D = building.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(col.disabled).is_true()
	assert_int(building.collision_layer).is_equal(0)


func test_tree_uses_a_cell_cylinder() -> void:
	var tree: StaticBody3D = auto_free(load("res://scenes/world/tree.tscn").instantiate()) as StaticBody3D
	add_child(tree)
	var col: CollisionShape3D = tree.get_node("CollisionShape3D") as CollisionShape3D
	assert_object(col.shape).is_instanceof(CylinderShape3D)
	var cyl := col.shape as CylinderShape3D
	var xz: Vector2 = HostCollision.xz_size(Vector2i(1, 1), 2.0)
	assert_float(cyl.radius).is_equal_approx(xz.x * 0.5, 0.01)
	assert_float(cyl.radius).is_greater(0.5)
