class_name TestHoleUse
extends GdUnitTestSuite

## Dig writes hole FG; fill restores empty. Original DIG_SCOOP / FILL_SCOOP.


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_persist_id_round_trip() -> void:
	var cell := Vector2i(8, 9)
	var pid: StringName = HoleUse.persist_id(cell)
	assert_str(String(pid)).is_equal("hole_8_9")
	assert_vector(HoleUse.cell_from_persist(pid)).is_equal(cell)
	assert_vector(HoleUse.cell_from_persist(&"tree_1")).is_equal(Vector2i(-1, -1))


func test_can_open_needs_empty_diggable_ground() -> void:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	assert_bool(HoleUse.can_open(grid, Vector2i(8, 8))).is_true()
	grid.set_terrain(Vector2i(8, 8), WorldGrid.Terrain.WATER)
	assert_bool(HoleUse.can_open(grid, Vector2i(8, 8))).is_false()
	grid.set_terrain(Vector2i(8, 9), WorldGrid.Terrain.GRASS)
	grid.place(&"rock", Vector2i(8, 9), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	assert_bool(HoleUse.can_open(grid, Vector2i(8, 9))).is_false()
	assert_bool(HoleUse.can_open(grid, Vector2i(-1, 0))).is_false()


func test_dig_occupies_and_marks() -> void:
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(8, 9)
	assert_bool(HoleUse.dig(ctx, cell)).is_true()
	var pid: StringName = HoleUse.persist_id(cell)
	assert_bool(Game.is_hole(pid)).is_true()
	assert_str(String(world.grid.occupant_at(cell))).is_equal(String(pid))
	assert_bool(HoleUse.dig(ctx, cell)).is_false()


func test_fill_clears_occupancy() -> void:
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	world.name = "world"
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(4, 5)
	assert_bool(HoleUse.dig(ctx, cell)).is_true()
	var pid: StringName = HoleUse.persist_id(cell)
	var hole: Node = objects.get_child(0)
	assert_that(hole).is_not_null()
	assert_bool(HoleUse.fill(hole, ctx)).is_true()
	assert_bool(Game.is_hole(pid)).is_false()
	assert_bool(world.grid.is_occupied(cell)).is_false()
	assert_bool(hole.is_queued_for_deletion()).is_true()


func test_restore_places_saved_holes() -> void:
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	var cell := Vector2i(3, 4)
	var pid: StringName = HoleUse.persist_id(cell)
	Game.mark_hole(pid)
	HoleUse.restore(world, world.grid)
	assert_str(String(world.grid.occupant_at(cell))).is_equal(String(pid))
	assert_int(objects.get_child_count()).is_equal(1)
	assert_bool(HoleUse.can_open(world.grid, cell)).is_false()


func test_cannot_dig_until_occupant_released() -> void:
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(6, 7)
	world.grid.place(&"tree_1", cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	assert_bool(HoleUse.dig(ctx, cell)).is_false()
	world.grid.remove(&"tree_1")
	assert_bool(HoleUse.dig(ctx, cell)).is_true()
	assert_bool(Game.is_hole(HoleUse.persist_id(cell))).is_true()
