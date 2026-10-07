extends GdUnitTestSuite

## What grows from the shine spot's hole (`bIT_common_bury_after`): a money bag a money tree
## (or a plain sapling), the shovel the golden tree.


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


func _world() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	for z: int in 16:
		for x: int in 16:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	add_child(world)
	return world


## A hole where the day's shine spot was.
func _shine_hole(ctx: InteractionContext, cell: Vector2i) -> void:
	assert_bool(HoleUse.dig(ctx, cell, false)).is_true()
	Game.shine_hole = HoleUse.persist_id(cell)


func test_money_tree_odds() -> void:
	assert_bool(PlantGrowth.money_tree_takes(0.49, 0, false)).is_true()
	assert_bool(PlantGrowth.money_tree_takes(0.51, 0, false)).is_false()
	## Money power adds half its value; Money Luck always takes.
	assert_bool(PlantGrowth.money_tree_takes(0.59, 20, false)).is_true()
	assert_bool(PlantGrowth.money_tree_takes(0.99, 0, true)).is_true()


func test_bag_in_shine_hole_grows_a_money_tree() -> void:
	var world := _world()
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(5, 5)
	_shine_hole(ctx, cell)
	Game.destiny_type = Game.Destiny.MONEY_LUCK
	assert_bool(BuriedUse.bury(ctx, cell, &"money_1000")).is_true()
	var pid: StringName = world.grid.occupant_at(cell)
	assert_str(String(pid)).is_equal(String(PlantGrowth.persist_id(cell)))
	assert_int(PlantGrowth.shake_content(pid)).is_equal(TreeUse.Content.MONEY_1000)
	assert_bool(PlantGrowth.is_gold(pid)).is_false()
	assert_str(String(Game.shine_hole)).is_equal("")


func test_shovel_in_shine_hole_grows_the_golden_tree() -> void:
	var world := _world()
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(6, 5)
	_shine_hole(ctx, cell)
	assert_bool(BuriedUse.bury(ctx, cell, &"shovel")).is_true()
	var pid: StringName = world.grid.occupant_at(cell)
	assert_bool(PlantGrowth.is_gold(pid)).is_true()
	assert_int(PlantGrowth.shake_content(pid)).is_equal(TreeUse.Content.GOLDEN_SHOVEL)


func test_other_holes_just_bury() -> void:
	var world := _world()
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(7, 5)
	assert_bool(HoleUse.dig(ctx, cell, false)).is_true()
	assert_bool(BuriedUse.bury(ctx, cell, &"money_1000")).is_true()
	assert_bool(BuriedUse.is_buried(world.grid.occupant_at(cell))).is_true()


func test_golden_tree_drops_the_shovel_once_grown() -> void:
	var plant: PlantData = PlantGrowth.plant_data(&"hardwood_tree")
	var sapling := TreeUse.new()
	sapling.configure(plant, &"TREE", false, TreeUse.Size.S0, false, TreeUse.Content.GOLDEN_SHOVEL)
	assert_bool(sapling.shake().drops.is_empty()).is_true()
	var grown := TreeUse.new()
	grown.configure(plant, &"TREE", false, TreeUse.Size.FULL, false, TreeUse.Content.GOLDEN_SHOVEL)
	var out: TreeUse.Outcome = grown.shake()
	assert_int(out.drops.size()).is_equal(1)
	assert_str(String(out.drops[0].id)).is_equal("golden_shovel")
	assert_bool(grown.shake().drops.is_empty()).is_true()


func test_spare_shovel_can_be_buried_not_the_one_in_hand() -> void:
	var inv: Inventory = Game.inventory
	inv.clear()
	inv.add(ItemCatalog.get_item(&"shovel"), 1)
	inv.equipment_id = &"shovel"
	inv.bury_ready = true
	assert_bool(inv.tags_for_slot(0).has("Bury")).is_false()
	inv.add(ItemCatalog.get_item(&"shovel"), 1)
	assert_bool(inv.tags_for_slot(1).has("Bury")).is_true()
	inv.bury_ready = false


func test_shine_hole_saves() -> void:
	Game.shine_hole = &"hole_3_4"
	var data: Dictionary = Game.to_save()
	Game.reset_session()
	assert_str(String(Game.shine_hole)).is_equal("")
	Game.apply_snapshot(data)
	assert_str(String(Game.shine_hole)).is_equal("hole_3_4")
