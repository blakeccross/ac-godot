class_name TestIsland
extends GdUnitTestSuite

## Kapp'n's island (`mRF_BLOCKKIND_ISLAND`) as a world of its own.

func _town() -> WorldData:
	return WorldGenerator.generate(12345)


func test_the_island_is_two_acres_with_the_towns_island_visuals() -> void:
	var town := _town()
	var island := WorldGenerator.generate_island(town)
	assert_int(island.columns).is_equal(32)
	assert_int(island.rows).is_equal(16)
	var xcols: int = TownFieldGenerator.BLOCK_X
	assert_str(String(island.acre_visuals[1 * xcols + 1])).is_equal(String(town.acre_visuals[8 * xcols + 4]))
	assert_str(String(island.acre_visuals[1 * xcols + 2])).is_equal(String(town.acre_visuals[8 * xcols + 5]))


func test_the_island_carries_its_fg_and_both_cottages() -> void:
	var island := WorldGenerator.generate_island(_town())
	var ids: Array[String] = []
	for b: BuildingPlacement in island.buildings:
		ids.append(String(b.id))
	assert_bool(ids.has("cottage_my")).is_true()
	assert_bool(ids.has("cottage_npc")).is_true()
	assert_int(island.objects.size()).is_greater(5)


func test_the_route_runs_from_the_wharf_to_the_landing() -> void:
	assert_vector(IslandRoute.point(0, false)).is_equal_approx(Vector3(139.0, 0.0, 181.0), Vector3.ONE * 0.01)
	assert_vector(IslandRoute.point(7, true)).is_equal_approx(Vector3(55.0, 0.0, 11.0), Vector3.ONE * 0.01)
	assert_int(IslandRoute.path(true).size()).is_equal(8)
	assert_vector(IslandRoute.path(false)[0]).is_equal_approx(IslandRoute.point(7, false), Vector3.ONE * 0.01)


func test_the_town_wharf_is_the_port_acre() -> void:
	assert_bool(IslandRoute.town_has_wharf(_town())).is_equal(
		int(_town().acre_types[6 * TownFieldGenerator.BLOCK_X + 5]) == TownFieldGenerator.T_PORT
	)


func test_the_boat_sails_every_way_point_and_stops_at_the_last() -> void:
	var boat := auto_free(preload("res://features/island/boat.tscn").instantiate()) as Boat
	add_child(boat)
	var pts: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, 10.0), Vector3(8.0, 0.0, 20.0)]
	boat.moor(pts[0], 0.0, Callable())
	var arrived: Array[bool] = [false]
	boat.arrived.connect(func() -> void: arrived[0] = true)
	boat.sail(pts)
	var steps: int = 0
	while boat.is_sailing() and steps < 6000:
		boat._physics_process(1.0 / 60.0)
		steps += 1
	assert_bool(arrived[0]).is_true()
	assert_float(boat.global_position.distance_to(Vector3(8.0, boat.global_position.y, 20.0))).is_less(0.2)
	assert_float(boat._speed).is_equal(0.0)


func test_kapp_n_talks_in_the_players_voice_and_asks_for_a_name() -> void:
	assert_int(KappnTalk.gendered(0x3073, false)).is_equal(0x3073)
	assert_int(KappnTalk.gendered(0x3073, true)).is_equal(0x3073 + 210)
	var talk := KappnTalk.new(KappnTalk.Kind.TOWN)
	Game.town.island_name = ""
	assert_int(talk.start_msg()).is_equal(0x3073)
	assert_int(talk.picked(0x3073, 1)).is_equal(0x3074)
	assert_bool(talk.ride).is_false()
	assert_int(talk.picked(0x3073, 0)).is_equal(0x3079)
	assert_bool(talk.ride).is_true()
	talk.current_msg = 0x3079
	talk.npc_order("npc0", 9, 1)
	assert_dict(talk.next_step()).contains_keys(["text"])
	assert_int(int(talk.text_result("Mira")["msg"])).is_equal(0x30BE)
	assert_str(Game.town.island_name).is_equal("Mira")
	Game.town.island_name = ""


func test_a_named_island_boards_at_once_and_the_way_home_asks_first() -> void:
	Game.town.island_name = "Mira"
	var talk := KappnTalk.new(KappnTalk.Kind.TOWN)
	assert_int(talk.picked(0x3073, 0)).is_equal(0x30BE)
	var home := KappnTalk.new(KappnTalk.Kind.ISLAND)
	assert_int(home.start_msg()).is_equal(0x3080)
	assert_int(home.picked(0x3080, 1)).is_equal(0x3081)
	assert_bool(home.ride).is_false()
	assert_int(home.picked(0x3080, 0)).is_equal(0x3084)
	assert_bool(home.ride).is_true()
	Game.town.island_name = ""


func test_the_shanty_follows_the_riders_pattern() -> void:
	assert_int(KappnTalk.pattern_for(false, false)).is_equal(0)
	assert_int(KappnTalk.pattern_for(false, true)).is_equal(1)
	assert_int(KappnTalk.pattern_for(true, false)).is_equal(2)
	assert_int(KappnTalk.pattern_for(true, true)).is_equal(3)
	assert_array(KappnTalk.song_messages(1, 2, 3, 4)).is_equal([0x3163 + 2, 0x316D + 3, 0x3181 + 4])
