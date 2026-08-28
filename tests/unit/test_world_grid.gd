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
