class_name TestWorldProps
extends GdUnitTestSuite

## FG props from the disc templates: fences, community / map / tune boards, lotus.
## Layout tests need the gitignored FG catalog and skip without it.

const PROP_KINDS: Array[StringName] = [&"prop", &"lotus", &"sign"]


func test_wide_props_shift_west_and_span_two_units() -> void:
	## `pos_table2` draws the `*0` unit at its left edge, so the mesh straddles the `*1`/`*0` seam.
	for item: int in [
		FgCatalog.ITEM_FENCE0,
		FgCatalog.ITEM_MESSAGE_BOARD0,
		FgCatalog.ITEM_MAP_BOARD0,
		FgCatalog.ITEM_MUSIC_BOARD0,
	]:
		var place: Dictionary = FgCatalog.placement_for_item(item)
		assert_that(place["foot"]).is_equal(Vector2i(2, 1))
		assert_that(place["cell_shift"]).is_equal(Vector2i(-1, 0))


func test_second_half_of_a_wide_prop_places_nothing() -> void:
	## FENCE1 / MESSAGE_BOARD1 / MAP_BOARD1 / MUSIC_BOARD1 are covered by the 2×1 footprint.
	for item: int in [0x0006, 0x000B, 0x000D, 0x000F]:
		assert_that(FgCatalog.placement_for_item(item).is_empty()).is_true()


func test_board_kinds_and_visuals() -> void:
	var notice: Dictionary = FgCatalog.placement_for_item(FgCatalog.ITEM_MESSAGE_BOARD0)
	assert_that(notice["kind"]).is_equal(&"sign")
	assert_that(notice["visual"]).is_equal(&"obj_s_notice")
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_MAP_BOARD0)["visual"]).is_equal(&"obj_s_sightmap")
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_MUSIC_BOARD0)["visual"]).is_equal(&"obj_s_melody")
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_FENCE0)["visual"]).is_equal(&"obj_s_fenceL")
	var short: Dictionary = FgCatalog.placement_for_item(FgCatalog.ITEM_WOOD_FENCE)
	assert_that(short["visual"]).is_equal(&"obj_s_fenceS")
	assert_that(short.has("foot")).is_false()


func test_lotus_placed_and_station_statue_is_not() -> void:
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_LOTUS)["kind"]).is_equal(&"lotus")
	## The statue only exists after a loan payoff (`aDOU_set_check`); a new town has nothing there.
	assert_that(FgCatalog.placement_for_item(0x5843).is_empty()).is_true()


func test_registry_knows_new_kinds() -> void:
	assert_that(WorldObjectRegistry.has_kind(&"prop")).is_true()
	assert_that(WorldObjectRegistry.has_kind(&"lotus")).is_true()
	assert_str(WorldObjectRegistry.scene_path(&"prop")).is_equal("res://scenes/world/prop.tscn")
	assert_str(WorldObjectRegistry.scene_path(&"lotus")).is_equal("res://scenes/world/lotus.tscn")
	assert_that(FieldCatalog.default_visual(&"prop")).is_equal(&"obj_s_fenceS")
	assert_that(FieldCatalog.default_visual(&"lotus")).is_equal(&"obj_s_lotus")


func test_lotus_flower_window() -> void:
	## `aLOT_actor_draw_before`: May 26 – Aug 25.
	var lotus_script: GDScript = load("res://scenes/world/lotus.gd")
	assert_that(lotus_script.flower_in_bloom(5, 25)).is_false()
	assert_that(lotus_script.flower_in_bloom(5, 26)).is_true()
	assert_that(lotus_script.flower_in_bloom(6, 1)).is_true()
	assert_that(lotus_script.flower_in_bloom(7, 31)).is_true()
	assert_that(lotus_script.flower_in_bloom(8, 25)).is_true()
	assert_that(lotus_script.flower_in_bloom(8, 26)).is_false()
	assert_that(lotus_script.flower_in_bloom(1, 1)).is_false()
	assert_that(lotus_script.flower_in_bloom(12, 25)).is_false()


func test_generated_towns_place_fixed_props() -> void:
	if not FgCatalog.has_catalog():
		return
	var seen: Dictionary = {}
	for seed: int in range(40):
		var data: WorldData = WorldGenerator.generate(5000 + seed)
		for o: ObjectPlacement in data.objects:
			if o.kind in PROP_KINDS:
				seen[o.visual_id] = int(seen.get(o.visual_id, 0)) + 1
				assert_that(data.is_in_bounds(o.cell)).is_true()
	## Not every town rolls a pond acre or the boards' acres, but fences appear in most of them.
	assert_that(seen.has(&"obj_s_fenceL")).is_true()
	assert_that(seen.has(&"obj_s_notice")).is_true()
	assert_that(seen.has(&"obj_s_lotus")).is_true()
	print("world props over 40 seeds: ", seen)


func test_wide_props_occupy_two_cells() -> void:
	if not FgCatalog.has_catalog():
		return
	for seed: int in range(12):
		var data: WorldData = WorldGenerator.generate(6000 + seed)
		for o: ObjectPlacement in data.objects:
			if o.visual_id in [&"obj_s_fenceL", &"obj_s_notice", &"obj_s_sightmap", &"obj_s_melody"]:
				assert_that(o.footprint).is_equal(Vector2i(2, 1))
			if o.kind == &"lotus":
				assert_that(o.occupy_grid).is_false()


func test_map_board_offers_read_and_fences_do_not() -> void:
	var packed: PackedScene = load("res://scenes/world/prop.tscn")
	var board: Node = auto_free(packed.instantiate())
	board.set("visual_id", &"obj_s_sightmap")
	add_child(board)
	var read: Array[Interaction] = board.call("get_interactions", null)
	assert_int(read.size()).is_equal(1)
	assert_that(read[0].id).is_equal(Interaction.READ)
	var fence: Node = auto_free(packed.instantiate())
	fence.set("visual_id", &"obj_s_fenceL")
	add_child(fence)
	var none: Array[Interaction] = fence.call("get_interactions", null)
	assert_int(none.size()).is_equal(0)


func test_first_job_notice_moves_to_the_community_board() -> void:
	## With a community board in the tree, other signs stop offering "Post a notice".
	var packed: PackedScene = load("res://scenes/world/sign.tscn")
	var board: Node = auto_free(packed.instantiate())
	board.set("visual_id", &"obj_s_notice")
	add_child(board)
	assert_that(board.is_in_group("notice_board")).is_true()
	var other: Node = auto_free(packed.instantiate())
	add_child(other)
	assert_that(other.is_in_group("notice_board")).is_false()
	assert_that(other.call("_needs_first_job_notice")).is_false()
