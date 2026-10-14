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
	var ticks: int = 0
	while not coin.sunk() and ticks < WellCoin.FLY_TICKS:
		coin.tick()
		peak = maxf(peak, coin.height_gx())
		ticks += 1
	assert_bool(coin.sunk()).is_true()
	## 5.5 up under 0.2 a tick: about 75 GX of climb from 11 up.
	assert_float(peak).is_greater(80.0)
	## About 55 ticks up and back down to where it left.
	assert_int(ticks).is_between(50, 60)
	assert_float(coin.height_gx()).is_equal_approx(water, 0.001)
	assert_float(coin.alpha()).is_equal_approx(180.0 / 255.0, 0.01)
	for i: int in 200:
		coin.tick()
	assert_float(coin.height_gx()).is_equal_approx(water - WellCoin.SINK_DEPTH, 0.001)
	coin.free()


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
