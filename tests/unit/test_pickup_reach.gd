class_name TestPickupReach
extends GdUnitTestSuite

## `Player_actor_Search_putin_item`: B looks 35 GX (signboards only), 20, then 10 GX ahead.


func _grid() -> WorldGrid:
	var grid := WorldGrid.new()
	grid.cell_size = 2.0
	return grid


func _item(at: Vector3, signboard: bool = false) -> Node3D:
	var node := auto_free(Node3D.new()) as Node3D
	add_child(node)
	node.global_position = at
	node.add_to_group(PickupReach.GROUP)
	if signboard:
		node.add_to_group(PickupReach.SIGNBOARD_GROUP)
	return node


func test_an_item_a_metre_ahead_is_found_by_the_20_gx_look() -> void:
	var reach := PickupReach.new(Vector3(0.5, 0.0, 0.5), 0.0, _grid())  ## facing +Z
	assert_int(reach.rank(_item(Vector3(0.5, 0.0, 1.5)))).is_equal(1)


func test_an_item_close_in_front_is_found_by_the_10_gx_look() -> void:
	## From z 1.4 the 20 GX look is over in the next unit; the 10 GX look is still on this one.
	var reach := PickupReach.new(Vector3(0.5, 0.0, 1.4), 0.0, _grid())
	assert_int(reach.rank(_item(Vector3(0.5, 0.0, 1.9)))).is_equal(2)


func test_an_item_beside_or_behind_is_not_reached() -> void:
	var reach := PickupReach.new(Vector3(0.5, 0.0, 0.5), 0.0, _grid())
	assert_int(reach.rank(_item(Vector3(1.9, 0.0, 0.5)))).is_equal(-1)
	assert_int(reach.rank(_item(Vector3(0.5, 0.0, -1.0)))).is_equal(-1)


func test_the_look_must_land_on_the_same_unit_as_the_item() -> void:
	## 20 GX ahead is on cell z 0 here, and an item in cell z 1 is not that unit's.
	var reach := PickupReach.new(Vector3(0.5, 0.0, 0.2), 0.0, _grid())
	assert_int(reach.rank(_item(Vector3(0.5, 0.0, 2.3)))).is_equal(-1)


func test_only_a_signboard_is_seen_from_35_gx_out() -> void:
	var reach := PickupReach.new(Vector3(0.5, 0.0, 0.1), 0.0, _grid())
	var board: Node3D = _item(Vector3(0.5, 0.0, 1.95), true)
	var thing: Node3D = _item(Vector3(0.5, 0.0, 1.95))
	assert_int(reach.rank(board)).is_equal(0)
	assert_int(reach.rank(thing)).is_equal(-1)


func test_a_step_up_or_down_over_15_gx_is_out_of_reach() -> void:
	var reach := PickupReach.new(Vector3(0.5, 0.0, 0.5), 0.0, _grid())
	assert_int(reach.rank(_item(Vector3(0.5, 1.0, 1.5)))).is_equal(-1)
