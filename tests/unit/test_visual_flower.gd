class_name TestVisualFlower
extends GdUnitTestSuite

## Field flower species and colours (`flower_DL_table`, `mFM_SetFGPal`).


func test_species_pick_the_mesh_and_colour_the_palette() -> void:
	assert_int(VisualFlower.colour_of(&"FLOWER_PANSIES0")).is_equal(0)
	assert_int(VisualFlower.colour_of(&"FLOWER_COSMOS2")).is_equal(2)
	assert_int(VisualFlower.colour_of(&"FLOWER_TULIP1")).is_equal(1)
	assert_int(VisualFlower.colour_of(&"FLOWER_LEAVES_TULIP1")).is_equal(-1)
	var pansy: PackedStringArray = FieldCatalog.mesh_paths(&"FLOWER_PANSIES2")
	var cosmos: PackedStringArray = FieldCatalog.mesh_paths(&"FLOWER_COSMOS0")
	if pansy.is_empty():
		return  ## no generated assets
	assert_str(pansy[0]).ends_with("obj_flower_a.glb")
	assert_str(cosmos[0]).ends_with("obj_flower_b.glb")
	assert_str(FieldCatalog.mesh_paths(&"FLOWER_TULIP0")[0]).ends_with("obj_flower_c.glb")
	assert_str(FieldCatalog.mesh_paths(&"FLOWER_LEAVES_COSMOS1")[0]).ends_with("obj_flower_leaf.glb")


func test_colour_rows_follow_the_term() -> void:
	## Term 0 (early January) is row 8; summer term 5 row 1; colour 2 adds 18.
	assert_int(VisualFlower.palette_row(0, 0)).is_equal(8)
	assert_int(VisualFlower.palette_row(0, 5)).is_equal(1)
	assert_int(VisualFlower.palette_row(2, 5)).is_equal(19)


func test_each_seed_bag_plants_its_own_flower() -> void:
	for pair: Array in [[&"purple_pansy_bag", &"FLOWER_PANSIES1"], [&"blue_cosmos_bag", &"FLOWER_COSMOS2"], [&"yellow_tulip_bag", &"FLOWER_TULIP2"]]:
		var bag: ItemData = ItemCatalog.get_item(pair[0])
		var plant: PlantData = PlantGrowth.plant_data(bag.plant_id)
		assert_object(plant).is_not_null()
		assert_str(String(plant.visual_mature)).is_equal(String(pair[1]))
		## `bIT_common_bury_after`: a buried bag comes up a grown flower.
		assert_int(PlantGrowth.pipeline_for_days(0, plant)).is_equal(PlantGrowth.Pipeline.HARVESTABLE)
