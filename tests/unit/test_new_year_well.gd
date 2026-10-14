class_name TestNewYearWell
extends GdUnitTestSuite

## New Year's Day at the wishing well (`ac_hatumode_control`, `ef_coin`).


func test_the_coin_arcs_up_and_sinks_at_the_water_line() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var coin := WellCoin.new()
	coin.setup(Vector3.ZERO, 0.0, rng)
	var water: float = WellCoin.WATER_ABOVE_GROUND
	var peak: float = -INF
	var t: float = 0.0
	while not coin.sunk() and t < WellCoin.FLY_TIME:
		coin.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		if not coin.sunk():
			peak = maxf(peak, coin.coin_position().y)
	assert_bool(coin.sunk()).is_true()
	## 5.5 GX a tick up under 0.2: about 75 GX of climb from 11 up.
	assert_float(peak / FieldCatalog.GX_TO_METERS).is_greater(80.0)
	## About 55 ticks up and back down to where it left.
	assert_float(coin.splash_time()).is_between(50.0 / 60.0, 60.0 / 60.0)
	assert_float(coin.coin_position().y).is_equal_approx(water, 0.01)
	assert_float(coin.alpha()).is_equal_approx(180.0 / 255.0, 0.02)
	coin.advance(200.0 / 60.0)
	assert_float(coin.coin_position().y).is_equal_approx(water - WellCoin.SINK_DEPTH, 0.001)
	assert_bool(coin.advance(2.0)).is_false()
	coin.free()


func test_the_coin_splashes_at_the_same_moment_at_any_frame_rate() -> void:
	var a := WellCoin.new()
	var b := WellCoin.new()
	for coin: WellCoin in [a, b]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		coin.setup(Vector3.ZERO, 0.0, rng)
	for _i: int in 72:
		a.advance(1.0 / 60.0)
	for _i: int in 12:
		b.advance(1.0 / 10.0)
	assert_bool(a.sunk() and b.sunk()).is_true()
	assert_float(a.age).is_equal_approx(b.age, 0.0001)
	assert_vector(a.coin_position()).is_equal_approx(b.coin_position(), Vector3.ONE * 0.0001)
	a.free()
	b.free()


func test_the_wish_is_made_from_the_front_facing_the_well() -> void:
	var well: Node3D = auto_free(load("res://scenes/world/buildings/wishing_well.tscn").instantiate()) as Node3D
	add_child(well)
	well.global_position = Vector3.ZERO
	well.call("apply_grid_yaw", WorldGrid.Facing.SOUTH)
	var stand: Array = well.call("visit_stand")
	var at: Vector3 = stand[0]
	assert_float(at.length() / FieldCatalog.GX_TO_METERS).is_equal_approx(65.0, 0.01)
	## Turned back toward the well.
	var to_well: Vector3 = -at.normalized()
	assert_float(Vector3(sin(float(stand[1])), 0.0, cos(float(stand[1]))).dot(to_well)).is_equal_approx(1.0, 0.0001)
