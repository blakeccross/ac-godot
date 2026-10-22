class_name TestTouchPath
extends GdUnitTestSuite

## `TouchPath`: A* over the units, pulled tight, never cutting a corner.


func _grid(cols: int = 12, rows: int = 12) -> WorldGrid:
	var grid := WorldGrid.new()
	grid.configure(cols, rows, 2.0, Vector3.ZERO)
	for z: int in rows:
		for x: int in cols:
			grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	return grid


func _at(grid: WorldGrid, cell: Vector2i) -> Vector3:
	return grid.cell_to_world(cell)


func test_open_ground_is_one_straight_leg() -> void:
	var grid: WorldGrid = _grid()
	var path: PackedVector3Array = TouchPath.find(null, grid, _at(grid, Vector2i(1, 1)), _at(grid, Vector2i(8, 5)))
	assert_int(path.size()).is_equal(2)
	assert_vector(path[1]).is_equal_approx(_at(grid, Vector2i(8, 5)), Vector3.ONE * 0.01)


func test_goes_round_a_wall() -> void:
	var grid: WorldGrid = _grid()
	for z: int in range(0, 9):
		grid.place(StringName("wall_%d" % z), Vector2i(5, z), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.BUILDING)
	var path: PackedVector3Array = TouchPath.find(null, grid, _at(grid, Vector2i(2, 2)), _at(grid, Vector2i(8, 2)))
	assert_int(path.size()).is_greater(2)
	## Every leg stays off the wall.
	for p: Vector3 in path:
		assert_bool(grid.is_occupied(grid.world_to_cell(p))).is_false()
	var through_gap := false
	for p: Vector3 in path:
		if grid.world_to_cell(p).y >= 9:
			through_gap = true
	assert_bool(through_gap).is_true()


func test_no_diagonal_squeeze_between_two_trees() -> void:
	var grid: WorldGrid = _grid()
	grid.place(&"tree_a", Vector2i(4, 3), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	grid.place(&"tree_b", Vector2i(3, 4), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	assert_bool(TouchPath.can_step(null, grid, Vector2i(3, 3), Vector2i(4, 4))).is_false()


func test_a_tap_on_a_tree_walks_to_the_unit_beside_it() -> void:
	var grid: WorldGrid = _grid()
	grid.place(&"tree", Vector2i(6, 6), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	var path: PackedVector3Array = TouchPath.find(null, grid, _at(grid, Vector2i(1, 6)), _at(grid, Vector2i(6, 6)))
	assert_int(path.size()).is_greater_equal(2)
	var end: Vector2i = grid.world_to_cell(path[path.size() - 1])
	assert_bool(end != Vector2i(6, 6)).is_true()
	assert_int(maxi(absi(end.x - 6), absi(end.y - 6))).is_equal(1)


func test_unreachable_gives_no_route() -> void:
	var grid: WorldGrid = _grid()
	for z: int in 12:
		grid.place(StringName("wall_%d" % z), Vector2i(5, z), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.BUILDING)
	var path: PackedVector3Array = TouchPath.find(null, grid, _at(grid, Vector2i(2, 2)), _at(grid, Vector2i(8, 2)))
	assert_int(path.size()).is_equal(0)
