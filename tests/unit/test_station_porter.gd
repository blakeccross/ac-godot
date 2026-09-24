class_name TestStationPorter
extends GdUnitTestSuite

## `aSTM_look_player` + `aNPC_ACT_TURN2`.


func test_title_spot_is_block_3_1_unit_5_4() -> void:
	assert_vector(StationPorter.TITLE_GX).is_equal(Vector3(3 * 640 + 5 * 40 + 20, 0.0, 640 + 4 * 40 + 20))


func test_turns_only_when_the_player_is_outside_67_5_degrees() -> void:
	assert_bool(StationPorter.needs_turn(0.0, deg_to_rad(60.0))).is_false()
	assert_bool(StationPorter.needs_turn(0.0, deg_to_rad(-60.0))).is_false()
	assert_bool(StationPorter.needs_turn(0.0, deg_to_rad(70.0))).is_true()
	assert_bool(StationPorter.needs_turn(deg_to_rad(170.0), deg_to_rad(-170.0))).is_false()


func test_turn_is_0x800_times_30_per_second_and_lands_on_target() -> void:
	## `chase_angle`: 11.25° × `game_GameFrame_2F` (0.5 at 60 Hz) per frame = 337.5°/s.
	var f: float = StationPorter.turn_toward(0.0, deg_to_rad(90.0))
	assert_float(rad_to_deg(f)).is_equal_approx(5.625, 0.001)
	f = StationPorter.turn_toward(0.0, deg_to_rad(-90.0))
	assert_float(rad_to_deg(f)).is_equal_approx(-5.625, 0.001)
	var ticks := 0
	f = 0.0
	while not is_equal_approx(f, PI * 0.5) and ticks < 100:
		f = StationPorter.turn_toward(f, PI * 0.5)
		ticks += 1
	assert_int(ticks).is_equal(16)


func test_turn_takes_the_short_way_across_the_back() -> void:
	## 175° → −175° goes through 180°, not back round through 0°.
	var f: float = StationPorter.turn_toward(deg_to_rad(175.0), deg_to_rad(-175.0))
	assert_float(rad_to_deg(f)).is_equal_approx(-179.375, 0.001)
	f = StationPorter.turn_toward(f, deg_to_rad(-175.0))
	assert_float(rad_to_deg(f)).is_equal_approx(-175.0, 0.001)
