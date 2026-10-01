extends GdUnitTestSuite

## `mAGrw_SetGrass` / `m_player_main_remove_grass`.


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()
	var layout: WorldData = null


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func _world() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(32, 32, 2.0, Vector3(-32, 0, -32))
	for z: int in 32:
		for x: int in 32:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	add_child(world)
	return world


func test_five_a_day_on_free_grass() -> void:
	var world := _world()
	world.grid.set_terrain(Vector2i(3, 3), WorldGrid.Terrain.SAND)
	assert_bool(WeedUse.can_grow(world.grid, null, Vector2i(3, 3))).is_false()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_int(WeedUse.amount_for(2)).is_equal(10)
	assert_int(WeedUse.grow(world, world.grid, null, WeedUse.amount_for(2), rng)).is_equal(10)
	assert_int(WeedUse.count()).is_equal(10)
	for key: Variant in Game.weeds:
		var cell: Vector2i = WeedUse.cell_from_persist(StringName(str(key)))
		assert_str(String(world.grid.occupant_at(cell))).is_equal(str(key))
	## A wish that cleared the town keeps them away.
	Game.clear_grass = true
	assert_int(WeedUse.grow(world, world.grid, null, 5, rng)).is_equal(0)


func test_pulling_frees_the_unit() -> void:
	var world := _world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	WeedUse.grow(world, world.grid, null, 1, rng)
	var weed: Node = world.get_node("Objects").get_child(0)
	var pid: StringName = weed.get("persist_id")
	var ctx := InteractionContext.new()
	ctx.world = world
	var action: Interaction = Interaction.primary(weed.get_interactions(ctx))
	assert_str(String(action.player_anim)).is_equal(String(WeedUse.PULL_ANIM))
	assert_bool(weed.interact(action, ctx)).is_true()
	assert_bool(WeedUse.is_weed(pid)).is_false()
	assert_bool(world.grid.is_occupied(WeedUse.cell_from_persist(pid))).is_false()


func test_days_wait_for_the_field_and_survive_a_save() -> void:
	Game._on_field_renewed(3)
	Game.weeds["weed_4_5"] = 2
	var saved: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(saved)
	assert_int(int(Game.weeds["weed_4_5"])).is_equal(2)
	assert_int(Game.take_weed_days()).is_equal(3)
	assert_int(Game.take_weed_days()).is_equal(0)
