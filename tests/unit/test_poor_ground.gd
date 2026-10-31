class_name TestPoorGround
extends GdUnitTestSuite

## `mCoBG_Change2PoorAttr` fields (`mFM_PoorTree`, `mRF_CheckBeastRoad`) and what the plant limit does.

const GRASS_AND_SOIL: Array[int] = [0, 1, 4, 5]


class _World extends Node:
	var grid: WorldGrid = WorldGrid.new()
	var layout: WorldData


func before_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _town() -> WorldData:
	var data: WorldData = WorldGenerator.generate(12345)
	FieldCollision.reset(data)
	PoorGround.apply(data)
	return data


func test_every_acre_type_has_a_gate_row() -> void:
	var file := FileAccess.open(PoorGround.GATES_PATH, FileAccess.READ)
	var table: Dictionary = JSON.parse_string(file.get_as_text())
	assert_int((table["block_gates"] as Array).size()).is_equal(108)
	assert_int((table["gate_kinds"] as Array).size()).is_equal(6)
	## A flat acre opens one gate on each side, centred; the three-gate kind lists three.
	for side: Variant in table["block_gates"][TownFieldGenerator.T_FLAT]:
		assert_int(int(side)).is_equal(1)
	assert_int((table["gate_kinds"][5][0] as Array).size()).is_equal(3)


func test_the_outer_columns_and_house_acre_units_turn_poor() -> void:
	if not FieldObjectCatalog.has_catalog():
		return
	var data: WorldData = _town()
	for z: int in range(0, 96, 5):
		for x: int in [0, 79]:
			assert_bool(GRASS_AND_SOIL.has(FieldCollision.unit_attr_at_cell(data, Vector2i(x, z)))).is_false()
	for unit: Vector2i in PoorGround.HOUSE_UNITS:
		var cell: Vector2i = Vector2i(32, 32) + unit
		assert_bool(GRASS_AND_SOIL.has(FieldCollision.unit_attr_at_cell(data, cell))).is_false()


func test_acre_gates_turn_poor() -> void:
	if not FieldObjectCatalog.has_catalog():
		return
	var data: WorldData = _town()
	var checked := 0
	for cell: Vector2i in PoorGround.cells(data):
		assert_bool(GRASS_AND_SOIL.has(FieldCollision.unit_attr_at_cell(data, cell))).is_false()
		checked += 1
	assert_int(checked).is_greater(400)
	## Not the ground a gate leads onto: the middle of an acre keeps its grass.
	var grass := 0
	for z: int in range(2, 94):
		for x: int in range(2, 78):
			if GRASS_AND_SOIL.has(FieldCollision.unit_attr_at_cell(data, Vector2i(x, z))):
				grass += 1
	assert_int(grass).is_greater(1000)


func test_poor_ground_lets_no_tree_live_but_flowers_grow() -> void:
	if not FieldObjectCatalog.has_catalog():
		return
	var data: WorldData = _town()
	assert_int(PlantGrowth.unit_limit(data, Vector2i(0, 40))).is_equal(0)
	## Open grass inside an acre lets a plant grow to its full size.
	var found := false
	for x: int in range(20, 60):
		if PlantGrowth.unit_limit(data, Vector2i(x, 40)) == FieldCatalog.PLANT_FULL:
			found = true
			break
	assert_bool(found).is_true()


func test_a_tree_planted_on_a_limited_unit_stops_growing() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	var rec := {PlantGrowth.KEY_PLANT: "apple_tree", PlantGrowth.KEY_PLANTED: 10, PlantGrowth.KEY_FRUIT: -1}
	assert_that(PlantGrowth.pipeline(rec, plant, 30)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)
	for row: Array in [[1, PlantGrowth.Pipeline.SEED], [2, PlantGrowth.Pipeline.GROWING],
			[3, PlantGrowth.Pipeline.MATURE], [4, PlantGrowth.Pipeline.HARVESTABLE]]:
		rec[PlantGrowth.KEY_LIMIT] = row[0]
		assert_that(PlantGrowth.pipeline(rec, plant, 30)).is_equal(row[1])
	rec[PlantGrowth.KEY_LIMIT] = 2
	assert_str(String(PlantGrowth.visual_id(rec, plant, 30))).is_equal("TREE_S1")
	assert_bool(PlantGrowth.fruit_ready(rec, plant, 30)).is_false()


func test_renewal_clears_trees_on_poor_ground_and_plants_on_dead_units() -> void:
	if not FieldObjectCatalog.has_catalog():
		return
	var data: WorldData = _town()
	var world: _World = auto_free(_World.new())
	world.layout = data
	world.grid.configure_from_world(data)
	add_child(world)
	var now: int = Clock.renew_index()
	var poor := Vector2i(0, 40)
	assert_int(PlantGrowth.unit_limit(data, poor)).is_equal(0)
	var tree_id: StringName = PlantGrowth.persist_id(poor)
	Game.town.plant_states[String(tree_id)] = {
		PlantGrowth.KEY_PLANT: "apple_tree", PlantGrowth.KEY_PLANTED: now - 3,
		PlantGrowth.KEY_CELL_X: poor.x, PlantGrowth.KEY_CELL_Z: poor.y, PlantGrowth.KEY_FRUIT: -1,
	}
	## A flower on poor ground is fine (`aAGrw_GrowFlower` runs first); a tree planted today waits.
	var flower := Vector2i(0, 41)
	var flower_id: StringName = PlantGrowth.persist_id(flower)
	Game.town.plant_states[String(flower_id)] = {
		PlantGrowth.KEY_PLANT: "pansy", PlantGrowth.KEY_PLANTED: now - 3,
		PlantGrowth.KEY_CELL_X: flower.x, PlantGrowth.KEY_CELL_Z: flower.y,
	}
	var fresh := Vector2i(0, 42)
	var fresh_id: StringName = PlantGrowth.persist_id(fresh)
	Game.town.plant_states[String(fresh_id)] = {
		PlantGrowth.KEY_PLANT: "apple_tree", PlantGrowth.KEY_PLANTED: now,
		PlantGrowth.KEY_CELL_X: fresh.x, PlantGrowth.KEY_CELL_Z: fresh.y, PlantGrowth.KEY_FRUIT: -1,
	}
	PlantGrowth.cull_unfit_plants(world, world.grid, data)
	assert_bool(PlantGrowth.has_record(tree_id)).is_false()
	assert_bool(PlantGrowth.has_record(flower_id)).is_true()
	assert_bool(PlantGrowth.has_record(fresh_id)).is_true()
