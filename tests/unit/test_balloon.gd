extends GdUnitTestSuite

## Present balloons (`m_fuusen.c`, `ac_fuusen.c`) and the wind they ride (`m_kankyo_weather`).


func test_wind_terms_follow_the_calendar() -> void:
	assert_int(Wind.term(1, 7)).is_equal(0)
	assert_int(Wind.term(1, 8)).is_equal(1)
	assert_int(Wind.term(4, 6)).is_equal(2)
	assert_int(Wind.term(9, 30)).is_equal(3)
	assert_int(Wind.term(12, 25)).is_equal(4)


func test_wind_power_stays_in_range() -> void:
	for _i: int in 50:
		Wind.tick(10.0)
		assert_float(Wind.power()).is_between(0.0, 1.0)


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
	var own: StringName = Game.town_fruit
	for _i: int in 40:
		var id: StringName = Balloon.true_present(rng)
		assert_str(String(id)).is_not_empty()
		assert_str(String(id)).is_not_equal(String(own))
		if FtrCatalog.available() and not id in ShopBook.FRUITS:
			assert_bool(FtrCatalog.named_list("ftr", "C").has(id)).is_true()
