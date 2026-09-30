extends GdUnitTestSuite

## `mEnv_PreRainNowFine_Init` / `mEnv_rainbow_power_calc` (`m_kankyo.c`).


func test_fine_after_rain_reserves_today() -> void:
	var r := Rainbow.new()
	r.note_weather_change(&"rain", &"clear", 7, 15)
	assert_bool(r.reserved).is_true()
	var dry := Rainbow.new()
	dry.note_weather_change(&"clear", &"clear", 7, 15)
	assert_bool(dry.reserved).is_false()


func test_fades_in_on_summer_midday_only() -> void:
	var r := Rainbow.new()
	r.reserve(7, 15)
	## 8:00 is before the window.
	r.tick(7, 15, 8 * 3600, true)
	assert_float(r.opacity).is_equal(0.0)
	for _i in 1800:
		r.tick(7, 15, 10 * 3600, true)
	assert_float(r.opacity).is_equal_approx(1.0, 0.0001)
	## Shown once: the reservation is spent, and it fades slowly after.
	assert_bool(r.reserved).is_false()
	r.tick(7, 15, 10 * 3600, true)
	assert_bool(r.opacity < 1.0).is_true()
	var winter := Rainbow.new()
	winter.reserve(1, 15)
	winter.tick(1, 15, 10 * 3600, false)
	assert_float(winter.opacity).is_equal(0.0)
