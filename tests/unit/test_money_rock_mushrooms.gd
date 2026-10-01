extends GdUnitTestSuite

## `mAGrw_SetMoneyStone` / `bIT_actor_ten_coin_entryR` and `m_mushroom`.


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()
	var layout: WorldData = null


class _Host extends Node3D:
	func can_host_mushroom() -> bool:
		return true


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.ensure_loaded()


func after_test() -> void:
	Game.reset_session()


func _world() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(64, 64, 2.0, Vector3(-64, 0, -64))
	for z: int in 64:
		for x: int in 64:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	add_child(world)
	return world


func _tree(world: _GridWorld, cell: Vector2i) -> void:
	var host := _Host.new()
	host.add_to_group("plant")
	world.add_child(host)
	host.global_position = world.grid.cell_to_world(cell)
	world.grid.place(StringName("tree_%d_%d" % [cell.x, cell.y]), cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)


func test_money_rock_pays_more_as_the_hits_go_on() -> void:
	assert_str(String(MoneyRock.payout(0, false))).is_equal("money_100")
	assert_str(String(MoneyRock.payout(2, false))).is_equal("money_100")
	assert_str(String(MoneyRock.payout(3, false))).is_equal("money_1000")
	assert_str(String(MoneyRock.payout(6, false))).is_equal("money_10000")
	assert_str(String(MoneyRock.payout(9, true))).is_equal("money_30000")
	## 386 frames, plus 0.6 per point of money power; the luck bonus cancels itself out.
	assert_float(MoneyRock.window_frames(0, false)).is_equal_approx(386.0, 0.01)
	assert_float(MoneyRock.window_frames(100, true)).is_equal_approx(386.0, 0.01)
	assert_float(MoneyRock.window_frames(-50, false)).is_equal_approx(356.0, 0.01)
	Game.money_rock = "rock_4"
	assert_object(MoneyRock.hit(&"rock_3", 0)).is_null()
	var bags: Array[StringName] = []
	for i: int in 8:
		bags.append(MoneyRock.hit(&"rock_4", i * 700).id)
	assert_str(String(bags[0])).is_equal("money_100")
	assert_str(String(bags[4])).is_equal("money_1000")
	assert_str(String(bags[7])).is_equal("money_10000")
	## After the window it is an ordinary rock until a new one is picked.
	assert_object(MoneyRock.hit(&"rock_4", 60000)).is_null()
	assert_str(Game.money_rock).is_equal("")


func test_money_rock_choice_and_drop_spot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rocks: Dictionary = {&"rock_1": Vector2i(1, 1), &"rock_2": Vector2i(1, 1), &"rock_3": Vector2i(2, 3)}
	assert_bool(rocks.has(MoneyRock.choose(rocks, rng))).is_true()
	assert_str(String(MoneyRock.choose({}, rng))).is_equal("")
	var world := _world()
	var rock := Vector2i(10, 10)
	world.grid.place(&"rock_1", rock, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	## North first, then east, south, west.
	assert_that(MoneyRock.drop_cell(world.grid, rock)).is_equal(Vector2i(10, 9))
	world.grid.place(&"x1", Vector2i(10, 9), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	assert_that(MoneyRock.drop_cell(world.grid, rock)).is_equal(Vector2i(11, 10))


func test_mushroom_crop_by_the_quarter_hour() -> void:
	assert_int(MushroomUse.crop(8, 0, true)).is_equal(5)
	assert_int(MushroomUse.crop(8, 47, true)).is_equal(2)
	assert_int(MushroomUse.crop(9, 10, true)).is_equal(1)
	assert_int(MushroomUse.crop(9, 15, true)).is_equal(0)
	assert_int(MushroomUse.crop(8, 0, false)).is_equal(0)
	assert_int(MushroomUse.quarters_between(8 * 60, 8 * 60 + 44)).is_equal(2)
	assert_int(MushroomUse.quarters_between(8 * 60 + 14, 8 * 60)).is_equal(0)


func test_mushrooms_grow_under_trees_then_go() -> void:
	var world := _world()
	## Hosts in field acres (1,1) and (2,2); the player stands in acre (1,3).
	_tree(world, Vector2i(20, 20))
	_tree(world, Vector2i(36, 36))
	Game.events.force(MushroomUse.SEASON_EVENT)
	Game.events.sync(EventCalendar.make_date(2002, 10, 16, 8))
	assert_bool(MushroomUse.in_season()).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var day: int = 100 * 1440
	Game.mushroom_minute = day - 1440 + 600
	MushroomUse.tick(world, day + 8 * 60, 8, 0, Vector2i(1, 3), rng)
	## Acre (1,1) shares the player's column, so only the tree in (2,2) can take them; it has
	## five spots.
	assert_int(Game.mushrooms.size()).is_equal(5)
	for key: Variant in Game.mushrooms:
		var cell: Vector2i = MushroomUse.cell_from_persist(StringName(str(key)))
		assert_that(cell / 16).is_equal(Vector2i(2, 2))
	assert_bool(Game.mushroom_active).is_false()
	## Same quarter: nothing changes. Half an hour on: two have gone.
	MushroomUse.tick(world, day + 8 * 60 + 10, 8, 10, Vector2i(1, 3), rng)
	assert_int(Game.mushrooms.size()).is_equal(5)
	MushroomUse.tick(world, day + 8 * 60 + 30, 8, 30, Vector2i(1, 3), rng)
	assert_int(Game.mushrooms.size()).is_equal(3)
	## Standing in that acre keeps them.
	MushroomUse.tick(world, day + 10 * 60, 10, 0, Vector2i(2, 2), rng)
	assert_int(Game.mushrooms.size()).is_equal(3)
	## Next morning they are long gone and a new crop may come.
	MushroomUse.first_clear(world, day + 1440 + 7 * 60, rng)
	assert_int(Game.mushrooms.size()).is_equal(0)
	assert_bool(Game.mushroom_active).is_true()
	Game.events.unforce(MushroomUse.SEASON_EVENT)
