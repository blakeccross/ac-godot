extends GdUnitTestSuite

## `m_map_ovl.c`: labels and layout of the town map.

const MapOverlayScript := preload("res://scenes/ui/map_overlay.gd")


func test_label_counts_pick_the_label_frame() -> void:
	assert_int(MapOverlayScript.label_count({})).is_equal(0)
	assert_int(MapOverlayScript.label_count({"label": MapOverlayScript.MapLabel.SHOP, "residents": []})).is_equal(2)
	var npc := {"label": MapOverlayScript.MapLabel.NPC, "residents": [{}, {}, {}]}
	assert_int(MapOverlayScript.label_count(npc)).is_equal(3)


func test_screen_mapping_is_centre_origin_y_up() -> void:
	assert_vector(MapOverlayScript.to_screen(Vector2.ZERO)).is_equal(Vector2(160, 120))
	assert_vector(MapOverlayScript.to_screen(Vector2(11.7, 45.7))).is_equal_approx(Vector2(171.7, 74.3), Vector2.ONE * 0.01)


func test_generated_town_labels_its_buildings_and_houses() -> void:
	var data: WorldData = Game.resolve_world_data() if Game != null else null
	if data == null or data.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return
	var acres: Dictionary = MapOverlayScript.build_labels(data)
	var kinds: Dictionary = {}
	for fg: Variant in acres.keys():
		kinds[int(acres[fg]["label"])] = true
	assert_bool(kinds.has(MapOverlayScript.MapLabel.STATION)).is_true()
	assert_bool(kinds.has(MapOverlayScript.MapLabel.PLAYER)).is_true()
