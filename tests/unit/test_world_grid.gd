class_name TestWorldGrid
extends GdUnitTestSuite

var _grid: WorldGrid


func before_test() -> void:
	_grid = WorldGrid.new()
	_grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))


func test_world_and_cell_round_trip() -> void:
	for x: int in 16:
		for z: int in 16:
			var cell := Vector2i(x, z)
			var world: Vector3 = _grid.cell_to_world(cell)
			assert_that(_grid.world_to_cell(world)).is_equal(cell)


func test_world_to_cell_uses_floor() -> void:
	assert_that(_grid.world_to_cell(Vector3(-16.0, 0, -16.0))).is_equal(Vector2i(0, 0))
	assert_that(_grid.world_to_cell(Vector3(-14.01, 0, -16.0))).is_equal(Vector2i(0, 0))
	assert_that(_grid.world_to_cell(Vector3(-14.0, 0, -16.0))).is_equal(Vector2i(1, 0))
	assert_that(_grid.world_to_cell(Vector3(15.9, 0, 15.9))).is_equal(Vector2i(15, 15))


func test_out_of_bounds() -> void:
	assert_bool(_grid.is_in_bounds(Vector2i(0, 0))).is_true()
	assert_bool(_grid.is_in_bounds(Vector2i(15, 15))).is_true()
	assert_bool(_grid.is_in_bounds(Vector2i(-1, 0))).is_false()
	assert_bool(_grid.is_in_bounds(Vector2i(16, 8))).is_false()
	assert_that(_grid.terrain_at(Vector2i(-1, 0))).is_equal(WorldGrid.Terrain.BLOCKED)


func test_neighbors() -> void:
	var mid: Array[Vector2i] = _grid.neighbors4(Vector2i(8, 8))
	assert_int(mid.size()).is_equal(4)
	var corner: Array[Vector2i] = _grid.neighbors4(Vector2i(0, 0))
	assert_int(corner.size()).is_equal(2)
	var around: Array[Vector2i] = _grid.neighbors8(Vector2i(0, 0))
	assert_int(around.size()).is_equal(3)
	assert_int(_grid.neighbors8(Vector2i(8, 8)).size()).is_equal(8)


func test_footprint_rotation_1x2() -> void:
	var anchor := Vector2i(5, 5)
	var size := Vector2i(1, 2)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.SOUTH)).is_equal(
		[Vector2i(5, 5), Vector2i(5, 6)]
	)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.EAST)).is_equal(
		[Vector2i(5, 5), Vector2i(6, 5)]
	)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.NORTH)).is_equal(
		[Vector2i(5, 5), Vector2i(5, 4)]
	)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.WEST)).is_equal(
		[Vector2i(5, 5), Vector2i(4, 5)]
	)


func test_rotate_facing_wraps() -> void:
	assert_that(_grid.rotate_facing(WorldGrid.Facing.WEST, 1)).is_equal(WorldGrid.Facing.SOUTH)
	assert_that(_grid.rotate_facing(WorldGrid.Facing.SOUTH, -1)).is_equal(WorldGrid.Facing.WEST)


func test_facing_from_yaw() -> void:
	assert_that(WorldGrid.facing_from_yaw(0.0)).is_equal(WorldGrid.Facing.SOUTH)
	assert_that(WorldGrid.facing_from_yaw(PI)).is_equal(WorldGrid.Facing.NORTH)
	assert_that(WorldGrid.facing_from_yaw(WorldGrid.yaw_for_facing(WorldGrid.Facing.EAST))).is_equal(
		WorldGrid.Facing.EAST
	)
	assert_that(_grid.step(Vector2i(4, 4), WorldGrid.Facing.NORTH)).is_equal(Vector2i(4, 3))


func test_furniture_yaw_matches_amr_table() -> void:
	assert_float(WorldGrid.yaw_for_furniture(WorldGrid.Facing.SOUTH)).is_equal_approx(0.0, 0.0001)
	assert_float(WorldGrid.yaw_for_furniture(WorldGrid.Facing.EAST)).is_equal_approx(PI * 0.5, 0.0001)
	assert_float(WorldGrid.yaw_for_furniture(WorldGrid.Facing.NORTH)).is_equal_approx(PI, 0.0001)
	assert_float(WorldGrid.yaw_for_furniture(WorldGrid.Facing.WEST)).is_equal_approx(PI * 1.5, 0.0001)


func test_furniture_world_keeps_1x2_on_anchor() -> void:
	var one: Vector3 = _grid.cell_to_world(Vector2i(3, 4))
	assert_that(_grid.furniture_world(Vector2i(3, 4), Vector2i.ONE, WorldGrid.Facing.EAST)).is_equal(one)
	assert_that(_grid.furniture_world(Vector2i(3, 4), Vector2i(2, 1), WorldGrid.Facing.SOUTH)).is_equal(one)
	var two: Vector3 = one + Vector3(_grid.cell_size * 0.5, 0.0, _grid.cell_size * 0.5)
	assert_that(_grid.furniture_world(Vector2i(3, 4), Vector2i(2, 2), WorldGrid.Facing.SOUTH)).is_equal(two)


func test_typeb_footprint_matches_l_typeb0_table() -> void:
	var anchor := Vector2i(5, 5)
	var size := Vector2i(2, 1)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.SOUTH)).is_equal(
		[Vector2i(5, 5), Vector2i(6, 5)]
	)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.EAST)).is_equal(
		[Vector2i(5, 5), Vector2i(5, 4)]
	)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.NORTH)).is_equal(
		[Vector2i(5, 5), Vector2i(4, 5)]
	)
	assert_that(_grid.footprint_cells(anchor, size, WorldGrid.Facing.WEST)).is_equal(
		[Vector2i(5, 5), Vector2i(5, 6)]
	)


func test_typec_footprint_ignores_facing() -> void:
	## `mRmTp_size_l_data` / `aMR_SetInfoFurnitureTable` TYPEC: always +X/+Z.
	var anchor := Vector2i(4, 4)
	var size := Vector2i(2, 2)
	var south: Array[Vector2i] = _grid.footprint_cells(anchor, size, WorldGrid.Facing.SOUTH)
	var north: Array[Vector2i] = _grid.footprint_cells(anchor, size, WorldGrid.Facing.NORTH)
	assert_that(south).is_equal(
		[Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 4), Vector2i(5, 5)]
	)
	assert_that(north).is_equal(south)
	assert_that(
		_grid.furniture_world(anchor, size, WorldGrid.Facing.NORTH)
	).is_equal(_grid.cell_to_world(anchor) + Vector3(1.0, 0.0, 1.0))


func test_place_and_occupancy() -> void:
	assert_bool(
		_grid.place(&"tree", Vector2i(3, 3), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_true()
	assert_that(_grid.occupant_at(Vector2i(3, 3))).is_equal(&"tree")
	assert_bool(_grid.is_occupied(Vector2i(3, 3))).is_true()
	assert_bool(
		_grid.can_place(Vector2i(3, 3), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)
	).is_false()
	assert_bool(
		_grid.place(&"tree", Vector2i(4, 4), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_false()
	_grid.remove(&"tree")
	assert_that(_grid.occupant_at(Vector2i(3, 3))).is_equal(&"")
	assert_bool(
		_grid.can_place(Vector2i(3, 3), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_true()


func test_building_footprint_blocks_all_cells() -> void:
	assert_bool(
		_grid.place(
			&"house", Vector2i(7, 1), Vector2i(2, 2), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.BUILDING
		)
	).is_true()
	assert_int(_grid.cells_of(&"house").size()).is_equal(4)
	assert_that(_grid.occupant_at(Vector2i(8, 2))).is_equal(&"house")
	assert_bool(
		_grid.can_place(Vector2i(8, 2), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_false()


func test_sand_and_path_are_walkable_cliff_is_not() -> void:
	_grid.set_terrain(Vector2i(4, 4), WorldGrid.Terrain.SAND)
	_grid.set_terrain(Vector2i(5, 5), WorldGrid.Terrain.PATH)
	_grid.set_terrain(Vector2i(7, 7), WorldGrid.Terrain.STONE)
	_grid.set_terrain(Vector2i(6, 6), WorldGrid.Terrain.CLIFF)
	assert_bool(_grid.is_walkable(Vector2i(4, 4))).is_true()
	assert_bool(_grid.is_walkable(Vector2i(5, 5))).is_true()
	assert_bool(_grid.is_walkable(Vector2i(7, 7))).is_true()
	assert_bool(_grid.is_walkable(Vector2i(6, 6))).is_false()
	assert_bool(
		_grid.can_place(Vector2i(6, 6), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_false()
	assert_bool(
		_grid.can_place(Vector2i(4, 4), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)
	).is_true()
	assert_bool(_grid.can_place(Vector2i(5, 5), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)).is_true()
	assert_bool(
		_grid.can_place(Vector2i(7, 7), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.FURNITURE)
	).is_true()
	assert_bool(
		_grid.can_place(Vector2i(4, 4), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_true()


func test_water_rejects_placement() -> void:
	_grid.set_terrain(Vector2i(12, 3), WorldGrid.Terrain.WATER)
	assert_bool(_grid.is_walkable(Vector2i(12, 3))).is_false()
	assert_bool(
		_grid.can_place(Vector2i(12, 3), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_false()
	assert_bool(
		_grid.can_place(Vector2i(4, 4), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	).is_true()


func test_footprint_out_of_bounds() -> void:
	assert_bool(
		_grid.can_place(Vector2i(15, 15), Vector2i(1, 2), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.FURNITURE)
	).is_false()


func test_configure_from_acre_applies_water() -> void:
	var acre: AcreData = load("res://data/acres/plot_a.tres")
	var g := WorldGrid.new()
	g.configure_from_acre(acre)
	assert_int(g.columns).is_equal(16)
	assert_that(g.terrain_at(Vector2i(12, 3))).is_equal(WorldGrid.Terrain.WATER)
	assert_that(g.terrain_at(Vector2i(0, 0))).is_equal(WorldGrid.Terrain.GRASS)
	assert_that(g.world_to_cell(Vector3(0, 0, 6))).is_equal(Vector2i(8, 11))
