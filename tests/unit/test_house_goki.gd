class_name TestHouseGoki
extends GdUnitTestSuite

var _session: IndoorSession
var _chair: FurnitureData


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Clock.apply_snapshot({"year": 2001, "month": 3, "day": 20, "hour": 12, "minute": 0})
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()
	var house: House = Game.interiors.player_house()
	house.size_tier = House.SizeTier.LARGE
	house.next_size_tier = House.SizeTier.LARGE
	Game.interiors.refresh_player_rooms()
	var room: Room = Game.interiors.room(&"player_main")
	room.placements.clear()
	_session = IndoorSession.new()
	_session.bind(room)
	_chair = ItemCatalog.get_item(&"wood_chair") as FurnitureData


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func _house() -> House:
	return Game.interiors.player_house()


func _away(days: int) -> House:
	var house: House = _house()
	var then: Dictionary = Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_datetime_dict({"year": 2001, "month": 3, "day": 20, "hour": 12})) - days * 86400
	)
	house.goki_year = int(then["year"])
	house.goki_month = int(then["month"])
	house.goki_day = int(then["day"])
	return house


## --- how many move in (`mCkRh_DecideNowGokiFamilyCount`) ------------------------------------


func test_nothing_moves_in_within_six_days() -> void:
	for days: int in [0, 1, 6]:
		var house: House = _away(days)
		house.goki_count = 0
		HouseGoki.decide_family_count(house)
		assert_int(house.goki_count).is_equal(0)


func test_one_more_for_every_day_past_the_sixth() -> void:
	var house: House = _away(7)
	HouseGoki.decide_family_count(house)
	assert_int(house.goki_count).is_equal(1)
	house = _away(8)
	house.goki_count = 0
	HouseGoki.decide_family_count(house)
	assert_int(house.goki_count).is_equal(2)
	house = _away(12)
	house.goki_count = 0
	HouseGoki.decide_family_count(house)
	assert_int(house.goki_count).is_equal(6)


func test_a_house_that_already_has_them_adds_the_whole_gap() -> void:
	var house: House = _away(8)
	house.goki_count = 2
	HouseGoki.decide_family_count(house)
	assert_int(house.goki_count).is_equal(10)


func test_never_more_than_ten() -> void:
	var house: House = _away(90)
	HouseGoki.decide_family_count(house)
	assert_int(house.goki_count).is_equal(HouseGoki.MAX_STORED)


func test_a_house_with_no_recorded_visit_starts_clean() -> void:
	var house: House = _house()
	assert_int(house.goki_year).is_equal(0)
	HouseGoki.decide_family_count(house)
	assert_int(house.goki_count).is_equal(0)
	assert_int(house.goki_year).is_equal(2001)


func test_playing_resets_the_clock() -> void:
	var house: House = _away(30)
	HouseGoki.save_play_time(house)
	assert_int(HouseGoki.days_away(house)).is_equal(0)


func test_days_away_counts_across_month_ends() -> void:
	var house: House = _house()
	house.goki_year = 2001
	house.goki_month = 2
	house.goki_day = 27
	assert_int(HouseGoki.days_away(house)).is_equal(21)


func test_goki_data_round_trips_through_save() -> void:
	var house: House = _away(3)
	house.goki_count = 4
	var copy := House.new()
	copy.apply_snapshot(JSON.parse_string(JSON.stringify(house.to_save())))
	assert_int(copy.goki_count).is_equal(4)
	assert_int(copy.goki_day).is_equal(house.goki_day)


func test_game_start_lets_them_in_and_saving_stamps_today() -> void:
	var house: House = _away(9)
	var snapshot: Dictionary = Game.to_save()
	assert_int(HouseGoki.days_away(_house())).is_equal(0)
	Game.reset_session()
	Game.apply_snapshot(snapshot)
	assert_int(Game.interiors.player_house().goki_count).is_equal(0)
	Game.reset_session()
	var neglected: House = Game.interiors.player_house()
	neglected.goki_year = 2001
	neglected.goki_month = 3
	neglected.goki_day = 10
	var raw: Dictionary = {"interiors": Game.interiors.to_save()}
	Game.reset_session()
	Game.apply_snapshot(raw)
	assert_int(Game.interiors.player_house().goki_count).is_equal(4)


## --- who shows up ---------------------------------------------------------------------------


func test_at_most_three_are_out_and_the_rest_stay_in_the_walls() -> void:
	var house: House = _house()
	house.goki_count = 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var pos: Vector3 = _session.grid.cell_to_world(Vector2i(4, 5))
	var spawns: Array[Dictionary] = HouseGoki.entry_spawns(_session, house, pos, rng)
	assert_int(spawns.size()).is_equal(3)
	assert_int(house.goki_count).is_equal(5)


func test_nothing_appears_when_none_are_waiting() -> void:
	var rng := RandomNumberGenerator.new()
	assert_int(HouseGoki.entry_spawns(_session, _house(), Vector3.ZERO, rng).size()).is_equal(0)


func test_spawns_land_on_free_floor_inside_the_room() -> void:
	_session.place(_chair, Vector2i(2, 2), WorldGrid.Facing.SOUTH)
	var house: House = _house()
	house.goki_count = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spawns: Array[Dictionary] = HouseGoki.entry_spawns(_session, house, _session.grid.cell_to_world(Vector2i(5, 5)), rng)
	for spawn: Dictionary in spawns:
		var cell: Vector2i = _session.grid.world_to_cell(spawn["pos"] as Vector3)
		assert_bool(_session.room.is_inner(cell)).is_true()
		assert_that(_session.grid.occupant_at(cell)).is_equal(&"")


func test_a_full_floor_has_nowhere_to_spawn() -> void:
	var house: House = _house()
	house.goki_count = 3
	for z: int in range(1, 9):
		for x: int in range(1, 9):
			_session.grid.place(StringName("blk_%d_%d" % [x, z]), Vector2i(x, z), Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.FURNITURE)
	assert_int(HouseGoki.free_cells(_session, house).size()).is_equal(0)
	var rng := RandomNumberGenerator.new()
	assert_int(HouseGoki.entry_spawns(_session, house, Vector3.ZERO, rng).size()).is_equal(0)
	assert_int(house.goki_count).is_equal(3)


func test_the_spawn_area_grows_with_the_house() -> void:
	var house: House = _house()
	for tier: int in 4:
		house.size_tier = tier as House.SizeTier
		Game.interiors.refresh_player_rooms()
		var session := IndoorSession.new()
		session.bind(Game.interiors.room(&"player_main"))
		var side: int = [4, 6, 8, 8][tier]
		assert_int(HouseGoki.free_cells(session, house).size()).is_equal(side * side)


func test_shoving_furniture_can_flush_one_out_but_never_a_fourth() -> void:
	var house: House = _house()
	house.goki_count = 2
	assert_that(HouseGoki.furniture_spawn(_session, house, Vector2i(3, 3), 3)).is_equal({})
	assert_int(house.goki_count).is_equal(2)
	var spawn: Dictionary = HouseGoki.furniture_spawn(_session, house, Vector2i(3, 3), 1)
	assert_bool(bool(spawn["fade"])).is_true()
	assert_int(house.goki_count).is_equal(1)
	house.goki_count = 0
	assert_that(HouseGoki.furniture_spawn(_session, house, Vector2i(3, 3), 0)).is_equal({})


func test_survivors_go_back_but_the_dead_do_not() -> void:
	var house: House = _house()
	house.goki_count = 5
	var rng := RandomNumberGenerator.new()
	var spawns: Array[Dictionary] = HouseGoki.entry_spawns(_session, house, _session.grid.cell_to_world(Vector2i(4, 5)), rng)
	assert_int(spawns.size()).is_equal(3)
	HouseGoki.return_survivors(house, 2)
	assert_int(house.goki_count).is_equal(4)


func test_grip_reports_the_cells_a_piece_left() -> void:
	_session.place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _session.grid.cell_to_world(Vector2i(3, 4))
	pos.y = 0.1
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	var events: Array[Dictionary] = []
	for _i: int in 18:
		events.append_array(grip.advance(1.0 / 60.0 + 0.0001, _session, true, Vector2(0.0, -1.0), pos))
	assert_array(events[0]["vacated"]).is_equal([Vector2i(3, 3)])


## --- the roach itself -------------------------------------------------------------------------


func _goki(cell: Vector2i, fade: bool = false) -> Node3D:
	var node: Node3D = auto_free(load("res://scenes/world/house_goki.tscn").instantiate()) as Node3D
	add_child(node)
	node.position = _session.grid.cell_to_world(cell)
	node.call("setup", _session, fade)
	return node


func _step(node: Node, frames: int) -> void:
	for _i: int in frames:
		node._physics_process(1.0 / 60.0)


func test_a_roach_scurries_and_stays_inside_the_room() -> void:
	var goki: Node3D = _goki(Vector2i(4, 4))
	_step(goki, 240)
	var cell: Vector2i = _session.grid.world_to_cell(goki.position)
	assert_bool(_session.room.is_inner(cell)).is_true()
	assert_bool(bool(goki.get("alive"))).is_true()


func test_a_roach_never_walks_through_furniture() -> void:
	for x: int in range(1, 9):
		if x != 4:
			_session.place(_chair, Vector2i(x, 3), WorldGrid.Facing.SOUTH)
	var goki: Node3D = _goki(Vector2i(4, 4))
	_step(goki, 300)
	assert_that(_session.grid.occupant_at(_session.grid.world_to_cell(goki.position))).is_equal(&"")


func test_furniture_landing_on_a_roach_kills_it() -> void:
	var goki: Node3D = _goki(Vector2i(4, 4))
	_session.place(_chair, Vector2i(4, 4), WorldGrid.Facing.SOUTH)
	_step(goki, 3)
	assert_bool(bool(goki.get("alive"))).is_false()


func test_a_fading_in_roach_cannot_be_crushed_until_it_is_solid() -> void:
	var goki: Node3D = _goki(Vector2i(4, 4), true)
	assert_float(float(goki.get("alpha"))).is_equal_approx(30.0, 0.1)
	_step(goki, 20)
	assert_float(float(goki.get("alpha"))).is_greater(30.0)
	assert_bool(bool(goki.get("alive"))).is_true()


func test_a_moving_player_treads_on_it_but_a_standing_one_does_not() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	auto_free(player)
	var goki: Node3D = _goki(Vector2i(4, 4))
	goki.set("alpha", 255.0)
	player.global_position = goki.global_position + Vector3(0.2, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	goki.set("speed_units", 0.0)
	goki.set("act", 2)
	_step(goki, 3)
	assert_bool(bool(goki.get("alive"))).is_true()
	player.velocity = Vector3(1.0, 0.0, 0.0)
	_step(goki, 3)
	assert_bool(bool(goki.get("alive"))).is_false()


func test_a_roach_runs_from_a_player_who_comes_close() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	auto_free(player)
	var goki: Node3D = _goki(Vector2i(4, 4))
	goki.set("alpha", 255.0)
	goki.set("act", 2)
	goki.set("speed_units", 0.0)
	player.global_position = goki.global_position + Vector3(-2.0, 0.0, 0.0)
	player.velocity = Vector3(1.0, 0.0, 0.0)
	_step(goki, 2)
	assert_int(int(goki.get("act"))).is_equal(0)


func test_the_console_can_set_and_age_the_infestation() -> void:
	var console := DebugConsole.new()
	assert_bool(console.execute("house goki 6").contains("6")).is_true()
	assert_int(_house().goki_count).is_equal(6)
	Game.interiors.player_house().goki_count = 0
	assert_bool(console.execute("house neglect 9").contains("3")).is_true()
	assert_int(_house().goki_count).is_equal(3)
