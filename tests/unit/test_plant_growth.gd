class_name TestPlantGrowth
extends GdUnitTestSuite

## Daily FG growth from planted_renew. Original mAGrw_RenewalFgItem at 06:00.


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


func test_apple_pipeline_from_days() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	assert_that(PlantGrowth.pipeline_for_days(0, plant)).is_equal(PlantGrowth.Pipeline.SEED)
	assert_that(PlantGrowth.pipeline_for_days(1, plant)).is_equal(PlantGrowth.Pipeline.GROWING)
	assert_that(PlantGrowth.pipeline_for_days(2, plant)).is_equal(PlantGrowth.Pipeline.GROWING)
	assert_that(PlantGrowth.pipeline_for_days(3, plant)).is_equal(PlantGrowth.Pipeline.MATURE)
	assert_that(PlantGrowth.pipeline_for_days(4, plant)).is_equal(PlantGrowth.Pipeline.MATURE)
	assert_that(PlantGrowth.pipeline_for_days(5, plant)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)
	assert_that(PlantGrowth.tree_size(PlantGrowth.Pipeline.SEED)).is_equal(TreeUse.Size.S0)
	assert_that(PlantGrowth.tree_size(PlantGrowth.Pipeline.GROWING)).is_equal(TreeUse.Size.S1)
	assert_that(PlantGrowth.tree_size(PlantGrowth.Pipeline.MATURE)).is_equal(TreeUse.Size.S2)
	assert_that(PlantGrowth.tree_size(PlantGrowth.Pipeline.HARVESTABLE)).is_equal(TreeUse.Size.FULL)


func test_tree_grows_from_planted_renew() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	var rec := _rec("apple_tree", 10)
	assert_that(PlantGrowth.pipeline(rec, plant, 10)).is_equal(PlantGrowth.Pipeline.SEED)
	assert_str(String(PlantGrowth.visual_id(rec, plant, 10))).is_equal("TREE_S0")
	assert_that(PlantGrowth.pipeline(rec, plant, 11)).is_equal(PlantGrowth.Pipeline.GROWING)
	assert_str(String(PlantGrowth.visual_id(rec, plant, 11))).is_equal("TREE_S1")
	assert_that(PlantGrowth.pipeline(rec, plant, 13)).is_equal(PlantGrowth.Pipeline.MATURE)
	assert_str(String(PlantGrowth.visual_id(rec, plant, 13))).is_equal("TREE")
	assert_that(PlantGrowth.pipeline(rec, plant, 15)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)
	assert_str(String(PlantGrowth.visual_id(rec, plant, 15))).is_equal("TREE_APPLE_FRUIT")
	assert_bool(PlantGrowth.fruit_ready(rec, plant, 15)).is_true()


func test_fruit_returns_next_renew() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	var rec := _rec("apple_tree", 10)
	rec[PlantGrowth.KEY_FRUIT] = 15
	assert_bool(PlantGrowth.fruit_ready(rec, plant, 15)).is_false()
	assert_str(String(PlantGrowth.visual_id(rec, plant, 15))).is_equal("TREE")
	assert_bool(PlantGrowth.fruit_ready(rec, plant, 16)).is_true()
	assert_str(String(PlantGrowth.visual_id(rec, plant, 16))).is_equal("TREE_APPLE_FRUIT")


func test_take_fruit_persists_until_next_renew() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 10, "hour": 12, "minute": 0})
	var pid := &"plant_4_6"
	PlantGrowth.ensure(pid, plant, &"TREE_APPLE_FRUIT", Vector2i(4, 6))
	assert_bool(PlantGrowth.take_fruit(pid)).is_true()
	assert_bool(PlantGrowth.take_fruit(pid)).is_false()
	var rec: Dictionary = PlantGrowth.record(pid)
	assert_bool(PlantGrowth.fruit_ready(rec, plant)).is_false()
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 11, "hour": 12, "minute": 0})
	assert_bool(PlantGrowth.fruit_ready(PlantGrowth.record(pid), plant)).is_true()


func test_flower_water_caps_growth() -> void:
	var plant: PlantData = load("res://data/plants/pansy.tres")
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 1, "hour": 12, "minute": 0})
	var pid := &"plant_6_10"
	PlantGrowth.ensure(pid, plant, &"FLOWER_LEAVES_PANSIES0", Vector2i(6, 10))
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 8, "hour": 12, "minute": 0})
	var rec: Dictionary = PlantGrowth.record(pid)
	assert_int(PlantGrowth.growth_days(rec, plant)).is_equal(0)
	assert_that(PlantGrowth.pipeline(rec, plant)).is_equal(PlantGrowth.Pipeline.SEED)
	assert_bool(PlantGrowth.water(pid)).is_true()
	assert_bool(PlantGrowth.water(pid)).is_false()
	rec = PlantGrowth.record(pid)
	assert_int(PlantGrowth.growth_days(rec, plant)).is_equal(7)
	assert_that(PlantGrowth.pipeline(rec, plant)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)


func test_bloom_color_visuals_are_harvestable() -> void:
	var plant: PlantData = load("res://data/plants/pansy.tres")
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 1, "hour": 12, "minute": 0})
	for color: StringName in [&"FLOWER_PANSIES0", &"FLOWER_PANSIES1", &"FLOWER_PANSIES2"]:
		var pid := StringName("bloom_%s" % String(color))
		PlantGrowth.clear(pid)
		var rec: Dictionary = PlantGrowth.ensure(pid, plant, color, Vector2i(1, 1))
		assert_that(PlantGrowth.pipeline(rec, plant)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)
		assert_str(String(PlantGrowth.visual_id(rec, plant))).is_equal(String(color))


func test_flower_winter_does_not_count() -> void:
	var plant: PlantData = load("res://data/plants/pansy.tres")
	var rec := _rec("pansy", 1)
	rec[PlantGrowth.KEY_WATERED] = 80
	## Jan 1 2001 is winter; spring starts 25 Feb. Days 1..54 stay winter.
	assert_int(PlantGrowth.growth_days(rec, plant, 40)).is_equal(0)
	var apple: PlantData = load("res://data/plants/apple_tree.tres")
	assert_int(PlantGrowth.growth_days(_rec("apple_tree", 1), apple, 40)).is_equal(39)


func test_flower_dies_when_left_dry() -> void:
	## Use spring renews so `winter_pauses` does not zero the dry span.
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 1, "hour": 12, "minute": 0})
	var plant: PlantData = load("res://data/plants/pansy.tres")
	var watered: int = Clock.renew_index()
	var rec := _rec("pansy", watered)
	rec[PlantGrowth.KEY_WATERED] = watered
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 4, "hour": 12, "minute": 0})
	assert_bool(PlantGrowth.should_die(rec, plant)).is_false()
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 5, "hour": 12, "minute": 0})
	assert_bool(PlantGrowth.should_die(rec, plant)).is_true()


func test_can_plant_terrain_and_occupancy() -> void:
	var apple: PlantData = load("res://data/plants/apple_tree.tres")
	var palm: PlantData = load("res://data/plants/palm_tree.tres")
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(8, 8)
	assert_bool(PlantGrowth.can_plant(ctx, apple, cell)).is_true()
	assert_bool(PlantGrowth.can_plant(ctx, palm, cell)).is_false()
	world.grid.set_terrain(cell, WorldGrid.Terrain.SAND)
	assert_bool(PlantGrowth.can_plant(ctx, apple, cell)).is_false()
	assert_bool(PlantGrowth.can_plant(ctx, palm, cell)).is_true()
	world.grid.set_terrain(cell, WorldGrid.Terrain.GRASS)
	world.grid.place(&"rock", cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	assert_bool(PlantGrowth.can_plant(ctx, apple, cell)).is_false()
	world.grid.remove(&"rock")
	Game.mark_hole(&"hole_8_8")
	world.grid.place(&"hole_8_8", cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	assert_bool(PlantGrowth.can_plant(ctx, apple, cell)).is_true()


func test_plant_occupies_and_saves() -> void:
	var apple: PlantData = load("res://data/plants/apple_tree.tres")
	var world := auto_free(_GridWorld.new()) as _GridWorld
	add_child(world)
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(5, 7)
	var pid: StringName = PlantGrowth.plant(ctx, apple, cell)
	assert_str(String(pid)).is_equal("plant_5_7")
	assert_str(String(world.grid.occupant_at(cell))).is_equal("plant_5_7")
	var rec: Dictionary = PlantGrowth.record(pid)
	assert_str(str(rec.get(PlantGrowth.KEY_PLANT, ""))).is_equal("apple_tree")
	assert_that(PlantGrowth.pipeline(rec, apple)).is_equal(PlantGrowth.Pipeline.SEED)
	assert_str(String(PlantGrowth.visual_id(rec, apple))).is_equal("TREE_S0")
	assert_int(objects.get_child_count()).is_equal(1)
	assert_str(String(objects.get_child(0).get("visual_id"))).is_equal("TREE_S0")


func test_plant_from_slot_consumes_sapling() -> void:
	ItemCatalog.reload()
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	var actor := auto_free(Node3D.new()) as Node3D
	add_child(actor)
	actor.global_position = world.grid.cell_to_world(Vector2i(8, 8))
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.actor = actor
	ctx.inventory = Inventory.new()
	var sapling: ItemData = ItemCatalog.get_item(&"apple_sapling")
	assert_that(sapling).is_not_null()
	ctx.inventory.add(sapling, 1)
	var msg: String = PlantGrowth.plant_from_slot(ctx, 0)
	assert_str(msg).contains("Planted")
	assert_int(ctx.inventory.count_of(&"apple_sapling")).is_equal(0)
	var face: Vector2i = ToolUse.facing_cell(ctx)
	assert_bool(PlantGrowth.has_record(PlantGrowth.persist_id(face))).is_true()


func test_take_plant_from_slot_flags_scoop_on_hole() -> void:
	ItemCatalog.reload()
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	var actor := auto_free(Node3D.new()) as Node3D
	add_child(actor)
	actor.global_position = world.grid.cell_to_world(Vector2i(8, 8))
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.actor = actor
	ctx.inventory = Inventory.new()
	ctx.inventory.add(ItemCatalog.get_item(&"shovel"), 1)
	ctx.inventory.equip_slot(0)
	ctx.inventory.add(ItemCatalog.get_item(&"apple_sapling"), 1)
	var face: Vector2i = ToolUse.facing_cell(ctx)
	assert_bool(HoleUse.dig(ctx, face)).is_true()
	assert_bool(PlantGrowth.scoop_plant_ready(ctx)).is_true()
	var taken: Dictionary = PlantGrowth.take_plant_from_slot(ctx, 1)
	assert_bool(bool(taken.get("ok", false))).is_true()
	assert_bool(bool(taken.get("use_scoop", false))).is_true()
	assert_int(ctx.inventory.count_of(&"apple_sapling")).is_equal(0)
	## Consumed only — host appears after putin scoop / plant().
	assert_bool(PlantGrowth.has_record(PlantGrowth.persist_id(face))).is_false()
	var pid: StringName = PlantGrowth.plant(ctx, taken.get("plant") as PlantData, face)
	assert_str(String(pid)).is_equal(String(PlantGrowth.persist_id(face)))
	assert_bool(Game.is_hole(HoleUse.persist_id(face))).is_false()


func test_scoop_plant_ready_needs_shovel_and_hole() -> void:
	ItemCatalog.reload()
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var actor := auto_free(Node3D.new()) as Node3D
	add_child(actor)
	actor.global_position = world.grid.cell_to_world(Vector2i(4, 4))
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.actor = actor
	ctx.inventory = Inventory.new()
	assert_bool(PlantGrowth.scoop_plant_ready(ctx)).is_false()
	ctx.inventory.add(ItemCatalog.get_item(&"shovel"), 1)
	ctx.inventory.equip_slot(0)
	assert_bool(PlantGrowth.scoop_plant_ready(ctx)).is_false()
	assert_bool(HoleUse.dig(ctx, ToolUse.facing_cell(ctx))).is_true()
	assert_bool(PlantGrowth.scoop_plant_ready(ctx)).is_true()


func test_putin_scoop_anim_constants() -> void:
	assert_str(String(PlantGrowth.PUTIN_SCOOP_ANIM)).is_equal("ply_1_fill_up_i1")
	assert_float(PlantGrowth.PUTIN_HOLE_EFFECT_FRAME).is_equal(25.0)
	assert_str(String(PlantGrowth.FILL_SCOOP_ANIM)).is_equal("ply_1_fill_up1")
	assert_float(PlantGrowth.FILL_HOLE_EFFECT_FRAME).is_equal(18.0)

func test_save_round_trip_keeps_planted_renew() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 10, "hour": 12, "minute": 0})
	PlantGrowth.ensure(&"tree_1", plant, &"TREE_APPLE_FRUIT", Vector2i(4, 6))
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	assert_bool(PlantGrowth.has_record(&"tree_1")).is_false()
	Game.apply_snapshot(snap)
	var rec: Dictionary = PlantGrowth.record(&"tree_1")
	assert_bool(rec.is_empty()).is_false()
	assert_that(PlantGrowth.pipeline(rec, plant)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)
	assert_bool(PlantGrowth.fruit_ready(rec, plant)).is_true()


func test_ensure_backdates_from_visual() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 10, "hour": 12, "minute": 0})
	var rec: Dictionary = PlantGrowth.ensure(&"tree_1", plant, &"TREE_APPLE_FRUIT", Vector2i(4, 6))
	assert_that(PlantGrowth.pipeline(rec, plant)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)
	var again: Dictionary = PlantGrowth.ensure(&"tree_1", plant, &"TREE", Vector2i(4, 6))
	assert_int(int(again.get(PlantGrowth.KEY_PLANTED, 0))).is_equal(int(rec.get(PlantGrowth.KEY_PLANTED, -1)))


func test_persist_id_round_trip() -> void:
	var cell := Vector2i(8, 9)
	var pid: StringName = PlantGrowth.persist_id(cell)
	assert_str(String(pid)).is_equal("plant_8_9")
	assert_vector(PlantGrowth.cell_from_persist(pid)).is_equal(cell)
	assert_vector(PlantGrowth.cell_from_persist(&"tree_1")).is_equal(Vector2i(-1, -1))


func test_assign_special_trees_tops_up_bare_mature() -> void:
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 20, "hour": 12, "minute": 0})
	var hardwood: PlantData = load("res://data/plants/hardwood_tree.tres")
	for i: int in 40:
		var cell := Vector2i(i % 16, i / 16)
		var pid: StringName = PlantGrowth.persist_id(cell)
		PlantGrowth.ensure(pid, hardwood, &"TREE", cell)
	PlantGrowth.assign_special_trees(null)
	var bees := 0
	var ftr := 0
	var bells := 0
	for key: Variant in Game.plant_states.keys():
		match PlantGrowth.shake_content(StringName(str(key))):
			TreeUse.Content.BEES:
				bees += 1
			TreeUse.Content.FURNITURE:
				ftr += 1
			TreeUse.Content.BELLS:
				bells += 1
			_:
				pass
	assert_int(bees).is_equal(PlantGrowth.BEE_COLUMN_NUM)
	assert_int(ftr).is_equal(PlantGrowth.FTR_TREE_NUM)
	assert_int(bells).is_equal(PlantGrowth.MONEY_TREE_NUM)


func test_fruiting_tree_is_not_special_candidate() -> void:
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 20, "hour": 12, "minute": 0})
	var apple: PlantData = load("res://data/plants/apple_tree.tres")
	var pid := &"plant_2_2"
	PlantGrowth.ensure(pid, apple, &"TREE_APPLE_FRUIT", Vector2i(2, 2))
	var rec: Dictionary = PlantGrowth.record(pid)
	assert_bool(PlantGrowth.can_hold_special(rec, apple)).is_false()


func _rec(plant_id: String, planted: int) -> Dictionary:
	return {
		PlantGrowth.KEY_PLANT: plant_id,
		PlantGrowth.KEY_PLANTED: planted,
		PlantGrowth.KEY_WATERED: planted,
		PlantGrowth.KEY_FRUIT: -1,
		PlantGrowth.KEY_CELL_X: 0,
		PlantGrowth.KEY_CELL_Z: 0,
	}
