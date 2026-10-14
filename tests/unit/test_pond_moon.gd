extends GdUnitTestSuite

## `eNight13Moon_GetNowMoonPos` (`ef_night13_moon.c`).


func test_moon_glides_east_to_west_over_the_evening() -> void:
	assert_float(PondMoon.glide_x_gx(17, 59, 59)).is_equal(100.0)
	assert_float(PondMoon.glide_x_gx(18, 0, 0)).is_equal(100.0)
	assert_float(PondMoon.glide_x_gx(19, 0, 0)).is_equal_approx(33.3333, 0.001)
	## One game hour at 1/54 GX per second = 66.67 GX, meeting the next hour's start.
	assert_float(PondMoon.glide_x_gx(19, 59, 59)).is_equal_approx(PondMoon.glide_x_gx(20, 0, 0), 0.05)
	assert_float(PondMoon.glide_x_gx(21, 0, 0)).is_equal(-100.0)
