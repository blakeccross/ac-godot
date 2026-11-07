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


func test_the_players_cottage_is_its_own_model_and_a_large_room() -> void:
	var island := WorldGenerator.generate_island(_town())
	var visuals := {}
	for b: BuildingPlacement in island.buildings:
		visuals[String(b.id)] = String(b.visual_id)
	assert_str(visuals["cottage_my"]).is_equal("obj_s_myhome_i")
	assert_str(visuals["cottage_npc"]).is_equal("obj_s_house_i")
	assert_that(InteriorCatalog.resolve_entry(&"cottage_my")).is_equal(&"cottage")
	assert_str(String(InteriorCatalog.resolve_entry(&"cottage_npc"))).starts_with("npc_")  ## the islander's room
	var room: Room = InteriorCatalog.room_template(&"cottage")
	assert_vector(room.inner_size).is_equal(Vector2i(8, 8))
	assert_bool(room.can_decorate).is_true()
	assert_bool(room.shell_ids.has("rom_myhome3_floor")).is_true()
	assert_bool(room.stairs.is_empty()).is_true()


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


func test_the_islands_acres_fish_the_island_list() -> void:
	## `aSOG_gyoei_make_range_data`: marine + island blocks use `f_island` (sea bass, red snapper,
	## barred knifejaw), in every month; the rest of the island's sea is the town's own.
	var island := WorldGenerator.generate_island(_town())
	var grid := WorldGrid.new()
	grid.configure_from_world(island)
	var school := FishSchool.new()
	school.configure(grid, 0.0, island)
	var want: int = FishSpawnScheduler.KIND_MARINE | FishSpawnScheduler.KIND_ISLAND
	assert_int(school.block_kind(Vector2i(1, 1)) & want).is_equal(want)
	assert_int(school.block_kind(Vector2i(2, 1)) & want).is_equal(want)
	var pool: Array = FishSpawnScheduler.make_range_data(want, false, null, 0)
	var types: Array[int] = []
	for e: Dictionary in pool:
		types.append(int(e["type_index"]))
	assert_array(types).is_equal([36, 37, 38])


func test_kappn_is_drawn_with_the_wip_skeleton() -> void:
	## `aNPC_get_draw_data_idx`: `SP_NPC_SENDO` indexes `npc_draw_data_tbl[ALL_NPC_NUM + 114]`,
	## which is `cKF_bs_r_wip_1` (the old `kab_1` is the sleeping train passenger).
	var kappn := auto_free(preload("res://features/island/kappn.tscn").instantiate()) as Kappn
	add_child(kappn)
	assert_str(String(kappn.species)).is_equal("wip")
	var found: Node = null
	for n: Node in kappn.find_children("*", "Node3D", true, false):
		if n.name == &"GeneratedVisual":
			found = n
	assert_object(found).is_not_null()
	var anim: AnimationPlayer = kappn.find_children("*", "AnimationPlayer", true, false).front()
	assert_bool(anim.has_animation(kappn.idle_clip()) or anim.get_animation_list().size() > 0).is_true()


func test_the_island_is_summer_in_midwinter_and_gives_the_towns_weather_back() -> void:
	## `aBTD_change_season`: `mFM_toSummer` on arrival, `mFM_returnSeason` on the way home.
	var was_month: int = Clock.month
	var was_day: int = Clock.day
	Clock.month = 1
	Clock.day = 15
	Game.set_weather(&"snow", int(Weather.Intensity.HEAVY))
	assert_int(Clock.season()).is_equal(Clock.Season.WINTER)
	Game.island_visit = true
	assert_int(Clock.season()).is_equal(Clock.Season.SUMMER)
	assert_str(FieldCatalog.season_letter()).is_equal("s")
	assert_str(FieldCatalog.acre_season_letter()).is_equal("s")
	assert_str(String(Game.town.weather)).is_not_equal("snow")
	Game.island_visit = false
	assert_int(Clock.season()).is_equal(Clock.Season.WINTER)
	assert_str(String(Game.town.weather)).is_equal("snow")
	Clock.month = was_month
	Clock.day = was_day


func test_the_islands_weather_is_clear_four_days_in_five() -> void:
	assert_int(int(IslandClimate.weather_roll(0.79).kind)).is_equal(int(Weather.Kind.CLEAR))
	var rain: Weather.Roll = IslandClimate.weather_roll(0.81)
	assert_int(int(rain.kind)).is_equal(int(Weather.Kind.RAIN))
	assert_int(int(rain.intensity)).is_equal(int(Weather.Intensity.HEAVY))


func test_the_shanty_music_follows_the_riders_pattern_and_rolls() -> void:
	## `sing_1st_part_bgm_no` rows: 0x5C, 0x66, 0x61, 0x6B (+ the song roll); the second part 0x70 + roll.
	assert_int(KappnTalk.first_song_bgm(0, 0)).is_equal(92)
	assert_int(KappnTalk.first_song_bgm(1, 4)).is_equal(106)
	assert_int(KappnTalk.first_song_bgm(2, 2)).is_equal(99)
	assert_int(KappnTalk.first_song_bgm(3, 1)).is_equal(108)
	assert_int(KappnTalk.second_song_bgm(9)).is_equal(121)
	for pattern: int in 4:
		for roll: int in 5:
			assert_str(String(BgmCatalog.id_for_num(KappnTalk.first_song_bgm(pattern, roll)))).is_not_empty()
	for roll: int in 10:
		assert_str(String(BgmCatalog.id_for_num(KappnTalk.second_song_bgm(roll)))).is_not_empty()
	assert_str(String(BgmCatalog.id_for_num(91))).is_equal("island")


func test_the_islander_stands_in_their_cottages_yard_on_dry_land() -> void:
	var islander: VillagerData = VillagerCatalog.get_villager(Islander.decide(12345))
	assert_bool(islander != null and islander.islander).is_true()
	assert_that(Islander.decide(12345)).is_equal(islander.id)  ## the same town, the same islander
	var island := WorldGenerator.generate_island(_town(), islander)
	var cottage: BuildingPlacement = null
	for b: BuildingPlacement in island.buildings:
		if b.id == &"cottage_npc":
			cottage = b
	var found: ObjectPlacement = null
	for o: ObjectPlacement in island.objects:
		if o.kind == &"villager":
			found = o
	assert_object(found).is_not_null()
	assert_that(found.cell).is_equal(cottage.cell + Islander.YARD_FROM_COTTAGE)
	var grid := WorldGrid.new()
	grid.configure_from_world(island)
	assert_bool(grid.terrain_at(found.cell) == WorldGrid.Terrain.WATER).is_false()


func test_the_islander_chats_after_the_greeting_without_the_quest_menu() -> void:
	var islander: VillagerData = VillagerCatalog.get_villager(Islander.decide(12345))
	var state := VillagerState.new()
	var ctx := DialogueContext.from_game(islander, state)
	var was_island: bool = Game.island_visit
	Game.island_visit = true
	var m: VillagerTalkManager = VillagerTalk.manager(islander, state, ctx)
	Game.island_visit = was_island
	assert_object(m).is_not_null()
	assert_int(m.slot).is_equal(-1)
	var first: Dictionary = m.next_step()
	var msg: int = int(first["msg"])
	var base: int = VillagerTalkManager.ISLAND_CHAT[m.looks]
	assert_int(msg).is_between(base, base + VillagerTalkManager.ISLAND_CHAT_COUNT)
	assert_object(DialogueCatalog.conversation(StringName("msg_%d" % msg))).is_not_null()
	assert_bool(m.next_step().is_empty()).is_true()  ## and then the talk is over


func test_a_knock_while_the_islander_sleeps_is_answered_from_inside() -> void:
	Game.town.islander_id = String(Islander.decide(12345))
	var who: VillagerData = Islander.data()
	var state: VillagerState = Game.villagers.get_or_create(who.id)
	var was_hour: int = Clock.hour
	state.is_home = true
	Clock.hour = 3
	var msg: int = Islander.sleeping_msg(&"cottage_npc")
	assert_int(msg).is_between(Islander.SLEEPING_MSG, Islander.SLEEPING_MSG + 5)
	assert_int(Islander.sleeping_msg(&"cottage_my")).is_equal(-1)
	state.is_home = false
	assert_int(Islander.sleeping_msg(&"cottage_npc")).is_equal(-1)  ## out and about: the plain "not in" notice
	Clock.hour = was_hour
	Game.town.islander_id = ""


func test_the_cottage_keeps_its_own_music_box_and_cockroaches() -> void:
	## `Save_Get(island).cottage.music_box` / `.goki`: separate from the player's house.
	var cottage: House = Game.interiors.house(&"cottage")
	assert_object(cottage).is_not_null()
	assert_bool(cottage != Game.interiors.player_house()).is_true()
	var room: Room = InteriorCatalog.room_template(&"cottage")
	assert_bool(HouseCockroaches.is_roach_room(room)).is_true()
	assert_object(HouseCockroaches.house_for(room)).is_same(cottage)
	assert_object(HouseCockroaches.house_for(InteriorCatalog.room_template(&"player_main"))).is_same(
		Game.interiors.player_house()
	)
	assert_bool(MinidiskCatalog.box_add(cottage, 3)).is_true()
	assert_bool(MinidiskCatalog.box_has(Game.interiors.player_house(), 3)).is_false()


func test_the_castaway_floats_out_at_sea_and_cannot_be_talked_to() -> void:
	## `ac_ev_castaway`: the `def_pos` (3580, 4670) GX, lying at 0x3060, no talk.
	assert_vector(IslandService.CASTAWAY_AT).is_equal_approx(Vector3(179.0, 0.0, 233.5), Vector3.ONE * 0.001)
	assert_float(IslandService.CASTAWAY_YAW).is_equal_approx(deg_to_rad(68.027344), 0.0001)
	var g := auto_free(preload("res://features/events/actors/gulliver.tscn").instantiate()) as Gulliver
	add_child(g)
	assert_bool(g.can_talk()).is_true()
	g.castaway = true
	assert_bool(g.can_talk()).is_false()
