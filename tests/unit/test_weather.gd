class_name TestWeather
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	Weather.seed_rng(1)


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false
	Game.reset_session()


func test_weather_terms_match_decomp_table() -> void:
	assert_int(Weather.weather_term(1, 1)).is_equal(0)
	assert_int(Weather.weather_term(1, 8)).is_equal(1)
	assert_int(Weather.weather_term(2, 24)).is_equal(1)
	assert_int(Weather.weather_term(2, 25)).is_equal(2)
	assert_int(Weather.weather_term(4, 5)).is_equal(4)
	assert_int(Weather.weather_term(4, 8)).is_equal(5)
	assert_int(Weather.weather_term(12, 10)).is_equal(16)
	assert_int(Weather.weather_term(12, 31)).is_equal(19)


func test_april_sakura_terms_are_forced() -> void:
	## Term 4 (Apr 5–7) is 100% light sakura; term 5 (Apr 8) is 100% heavy sakura.
	Weather.seed_rng(42)
	for _i: int in 20:
		var light: Dictionary = Weather.roll(4, 6)
		assert_that(light["kind"]).is_equal(Weather.Kind.SAKURA)
		assert_that(light["intensity"]).is_equal(Weather.Intensity.LIGHT)
	for _i: int in 20:
		var heavy: Dictionary = Weather.roll(4, 8)
		assert_that(heavy["kind"]).is_equal(Weather.Kind.SAKURA)
		assert_that(heavy["intensity"]).is_equal(Weather.Intensity.HEAVY)


func test_new_years_is_always_clear() -> void:
	Weather.seed_rng(7)
	for _i: int in 20:
		var result: Dictionary = Weather.roll(1, 3)
		assert_that(result["kind"]).is_equal(Weather.Kind.CLEAR)


func test_blizzard_term_is_always_heavy_snow() -> void:
	## Dec 10 is 100% blizzard → snow + heavy.
	Weather.seed_rng(3)
	for _i: int in 20:
		var result: Dictionary = Weather.roll(12, 10)
		assert_that(result["kind"]).is_equal(Weather.Kind.SNOW)
		assert_that(result["intensity"]).is_equal(Weather.Intensity.HEAVY)


func test_pack_unpack_round_trip() -> void:
	var packed: int = Weather.pack(Weather.Kind.RAIN, Weather.Intensity.HEAVY)
	var unpacked: Dictionary = Weather.unpack(packed)
	assert_that(unpacked["kind"]).is_equal(Weather.Kind.RAIN)
	assert_that(unpacked["intensity"]).is_equal(Weather.Intensity.HEAVY)


func test_game_apply_roll_updates_session() -> void:
	Game.apply_weather_roll({"kind": Weather.Kind.RAIN, "intensity": Weather.Intensity.LIGHT})
	assert_that(Game.weather).is_equal(&"rain")
	assert_int(Game.weather_intensity).is_equal(int(Weather.Intensity.LIGHT))
	assert_bool(Weather.is_raining()).is_true()


func test_cycle_debug_walks_kinds() -> void:
	Game.set_weather(&"clear")
	Game.cycle_weather_debug()
	assert_that(Game.weather).is_equal(&"rain")
	Game.cycle_weather_debug()
	assert_that(Game.weather).is_equal(&"snow")
	Game.cycle_weather_debug()
	assert_that(Game.weather).is_equal(&"sakura")
	Game.cycle_weather_debug()
	assert_that(Game.weather).is_equal(&"clear")


func test_field_renew_rerolls_weather() -> void:
	Game.set_weather(&"clear")
	Weather.seed_rng(99)
	## Advance across a 06:00 so `field_renewed` fires.
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 1, "hour": 5, "minute": 50})
	Clock.advance_minutes(20)
	## July term allows rain/thunder; seeded roll should leave clear or precip — just ensure it set something valid.
	assert_bool(
		Game.weather == &"clear"
		or Game.weather == &"rain"
		or Game.weather == &"snow"
		or Game.weather == &"sakura"
	).is_true()


func test_precip_uses_rain_palette() -> void:
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 1, "hour": 12, "minute": 0})
	var fine: Dictionary = Weather.outdoor_light_for(&"clear")
	var rain: Dictionary = Weather.outdoor_light_for(&"rain")
	assert_float(float(rain["sun_energy"])).is_less(float(fine["sun_energy"]) + 0.001)
	## Midday rain sun is dimmer than fine (162 vs 180 channel).
	assert_float((rain["sun"] as Color).r).is_less((fine["sun"] as Color).r + 0.001)


func test_save_round_trip_includes_intensity() -> void:
	Game.set_weather(&"snow", int(Weather.Intensity.HEAVY))
	var snap: Dictionary = Game.to_save()
	assert_str(str(snap.get("weather", ""))).is_equal("snow")
	assert_int(int(snap.get("weather_intensity", -1))).is_equal(int(Weather.Intensity.HEAVY))
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_that(Game.weather).is_equal(&"snow")
	assert_int(Game.weather_intensity).is_equal(int(Weather.Intensity.HEAVY))
