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


func test_tapping_an_acre_selects_it_without_mobile_buttons() -> void:
	var map := auto_free((load("res://scenes/ui/map_overlay.tscn") as PackedScene).instantiate()) as MapOverlay
	add_child(map)
	map.open(true)
	map._slide.settle()
	var screen := map.get_node("Root/Screen") as Control
	var acre := Vector2i(3, 4)
	var point := MapOverlay.to_screen(MapOverlay.MAP_ORIGIN) + Vector2(acre) * MapOverlay.BLOCK
	var tap := InputEventScreenTouch.new()
	tap.position = screen.get_global_transform_with_canvas() * point
	tap.pressed = true
	map._unhandled_input(tap)
	assert_vector(Vector2(map.sel)).is_equal(Vector2(acre))
	map.close()


func test_mobile_title_can_preview_map_without_unlocking_it() -> void:
	var was_mobile := InputDeviceTracker.on_mobile
	var was_demo := Game.title_demo_active
	var had_map := Game.resident.has_map
	InputDeviceTracker.on_mobile = true
	Game.title_demo_active = true
	Game.resident.has_map = false
	var map := auto_free((load("res://scenes/ui/map_overlay.tscn") as PackedScene).instantiate()) as MapOverlay
	add_child(map)
	map.open()
	assert_bool(map.is_open()).is_true()
	assert_bool(Game.resident.has_map).is_false()
	map.close()
	Game.title_demo_active = false
	map.open()
	assert_bool(map.is_open()).is_false()
	Game.resident.has_map = had_map
	Game.title_demo_active = was_demo
	InputDeviceTracker.on_mobile = was_mobile


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
