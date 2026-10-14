extends GdUnitTestSuite

## `Player_actor_Check_player_sunburn_*` (`mPr_sunburn_c`).


func before_test() -> void:
	Sunburn.reset_session()


func after_test() -> void:
	Sunburn.reset_session()


func test_only_midsummer_middays() -> void:
	assert_bool(Sunburn.in_season(7, 15)).is_false()
	assert_bool(Sunburn.in_season(7, 16)).is_true()
	assert_bool(Sunburn.in_season(8, 1)).is_true()
	assert_bool(Sunburn.in_season(9, 15)).is_true()
	assert_bool(Sunburn.in_season(9, 16)).is_false()
	assert_bool(Sunburn.sunny_hour(9)).is_false()
	assert_bool(Sunburn.sunny_hour(16)).is_true()
	assert_bool(Sunburn.sunny_hour(17)).is_false()


func test_fifteen_minutes_in_the_sun_is_a_rank() -> void:
	var state: Dictionary = {"rank": 0, "changed": -1, "hold": 0}
	for _i: int in Sunburn.SUN_TICKS:
		Sunburn.sun_tick(state, true, 8, 1, 12)
	assert_bool(Sunburn.rankup_pending).is_false()
	Sunburn.sun_tick(state, true, 8, 1, 12)
	assert_bool(Sunburn.rankup_pending).is_true()
	assert_bool(Sunburn.settle(state, 100)).is_true()
	assert_int(int(state["rank"])).is_equal(1)
	assert_int(int(state["hold"])).is_equal(Sunburn.HOLD_DAYS)
	## Freshly tanned: no more today.
	for _i: int in Sunburn.SUN_TICKS + 2:
		Sunburn.sun_tick(state, true, 8, 1, 12)
	assert_bool(Sunburn.rankup_pending).is_false()
	## Shade, rain or an umbrella stop the count.
	Sunburn.reset_session()
	var fresh: Dictionary = {"rank": 0, "changed": -1, "hold": 0}
	for _i: int in Sunburn.SUN_TICKS + 2:
		Sunburn.sun_tick(fresh, false, 8, 1, 12)
	assert_int(Sunburn.sun_ticks).is_equal(0)


func test_the_tan_holds_then_fades_a_rank_a_day() -> void:
	var state: Dictionary = {"rank": 3, "changed": 100, "hold": 2}
	## Next day: the hold counts down and the change date moves with it.
	assert_bool(Sunburn.on_setup(state, 101)).is_false()
	assert_int(int(state["hold"])).is_equal(1)
	assert_int(int(state["changed"])).is_equal(101)
	## The day after, the hold is spent and a rank goes.
	assert_bool(Sunburn.on_setup(state, 102)).is_true()
	assert_int(int(state["hold"])).is_equal(0)
	assert_int(int(state["rank"])).is_equal(2)
	## Two days later, two more.
	assert_bool(Sunburn.on_setup(state, 104)).is_true()
	assert_int(int(state["rank"])).is_equal(0)
	assert_bool(Sunburn.on_setup(state, 110)).is_false()


func test_tan_palette_index() -> void:
	assert_int(PlayerFace.tan_index(false, 0, false, 1)).is_equal(1)
	assert_int(PlayerFace.tan_index(true, 3, false, 8)).is_equal(8 + 24 + 64)
	assert_int(PlayerFace.tan_index(true, 7, true, 8)).is_equal(8 + 56 + 64 + 128)
