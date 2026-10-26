extends GdUnitTestSuite

## Present balloons (`m_fuusen.c`, `ac_fuusen.c`) and the wind they ride (`m_kankyo_weather`).


func test_wind_terms_follow_the_calendar() -> void:
	assert_int(Wind.term(1, 7)).is_equal(0)
	assert_int(Wind.term(1, 8)).is_equal(1)
	assert_int(Wind.term(4, 6)).is_equal(2)
	assert_int(Wind.term(9, 30)).is_equal(3)
	assert_int(Wind.term(12, 25)).is_equal(4)


func test_wind_power_stays_in_range() -> void:
	var wind := Wind.new()
	for _i: int in 50:
		wind.advance(10.0)
		assert_float(wind.power()).is_between(0.0, 1.0)


func test_missed_rolls_raise_the_chance_and_a_launch_resets_it() -> void:
	var sky := BalloonSky.new()
	auto_free(sky)
	sky.chance = 0.0
	sky.roll()
	## 2.5% base + up to 2.5% random, no luck, no town rank.
	assert_float(sky.chance).is_between(0.025, 0.05)
	sky.chance = 0.4
	sky.state = BalloonSky.State.CHECKED
	sky._on_gone(true)
	assert_int(sky.state).is_equal(BalloonSky.State.LOOK_UP)


func test_present_is_rare_furniture_or_foreign_fruit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var own: StringName = Game.town.town_fruit
	for _i: int in 40:
		var id: StringName = Balloon.true_present(rng)
		assert_str(String(id)).is_not_empty()
		assert_str(String(id)).is_not_equal(String(own))
		if FurnitureCatalog.available() and not id in ShopBook.FRUITS:
			assert_bool(FurnitureCatalog.named_list("ftr", "C").has(id)).is_true()


## The wind belongs to the session: a fresh one comes with each, and it doesn't reset
## when the town scene does (going into a building and back out).
func test_the_wind_is_the_sessions_and_a_new_session_brings_a_new_one() -> void:
	var before: Wind = Game.wind
	assert_that(before).is_not_null()
	Game.reset_session()
	assert_that(Game.wind).is_not_null()
	assert_that(Game.wind).is_not_same(before)


## Over the town a balloon cruises 110 GX up (bobbing 10) and drifts downwind at 1–1.5 GX a
## frame, so in metres it moves 1.5–2.25 m a second.
func test_a_balloon_drifts_downwind_at_cruising_height() -> void:
	var world: World = auto_free(load("res://scenes/world/world.tscn").instantiate()) as World
	add_child(world)
	await get_tree().process_frame
	var balloon := Balloon.new()
	world.add_child(balloon)
	auto_free(balloon)
	var start: Vector3 = world.grid.cell_to_world(Vector2i(world.grid.columns / 2, world.grid.rows / 2))
	balloon.start_near(start)
	balloon.heading = 0
	var from: Vector3 = balloon.pos
	for _i: int in 120:
		balloon._step(1.0 / 60.0)
	var flat: float = Vector2(balloon.pos.x - from.x, balloon.pos.z - from.z).length()
	assert_float(flat).is_between(1.5 * 2.0 * 0.9, 2.25 * 2.0 * 1.1)
	var ground: float = FieldCollision.ground_y(world.layout, world.grid.world_to_cell(balloon.pos))
	assert_float(balloon.pos.y - ground).is_between(Balloon.HEIGHT - Balloon.BOB - 0.5, Balloon.HEIGHT + Balloon.BOB + 0.5)
