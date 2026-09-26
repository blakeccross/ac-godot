class_name TestTrainControl
extends GdUnitTestSuite

## `m_train_control.c` timetable and motion, `ac_train0/1` couplings and door, and the sound
## curves in `TrainService`.


## Run one whole visit from entry; returns the states raised, in order, with their tick.
func _run_visit(control: TrainControl, start_sec: int) -> Array[Vector2i]:
	var raised: Array[Vector2i] = []
	var sec_accum: float = 0.0
	var now: int = start_sec
	for tick: int in int(DecompTime.TICK_HZ) * 60 * 20:
		var state: int = control.step(now, 1)
		if state != TrainControl.STATE_NONE:
			raised.append(Vector2i(state, tick))
			if state == TrainControl.STATE_GONE:
				break
		sec_accum += DecompTime.TICK_SEC
		if sec_accum >= 1.0:
			sec_accum -= 1.0
			now += 1
	return raised


func test_departure_table_enters_four_ten_before_the_nineteen() -> void:
	## 10:00 → next due 10:19:00, enter at 10:14:50.
	assert_int(TrainControl.depart_time(10 * 3600)).is_equal(10 * 3600 + 14 * 60 + 50)
	## Exactly on a due time still counts (`>=`).
	assert_int(TrainControl.depart_time(10 * 3600 + 19 * 60)).is_equal(10 * 3600 + 14 * 60 + 50)
	## Just after → the next hour.
	assert_int(TrainControl.depart_time(10 * 3600 + 19 * 60 + 1)).is_equal(11 * 3600 + 14 * 60 + 50)
	## After 23:19 the table's 24:19 row → past midnight, beyond 86400.
	assert_int(TrainControl.depart_time(23 * 3600 + 30 * 60)).is_equal(24 * 3600 + 14 * 60 + 50)


func test_no_train_before_its_time() -> void:
	var control := TrainControl.new()
	control.init(10 * 3600, 1)
	assert_int(control.step(10 * 3600 + 60, 1)).is_equal(TrainControl.STATE_NONE)
	assert_bool(control.is_running()).is_false()


func test_a_visit_arrives_stops_at_the_station_waits_and_leaves() -> void:
	var control := TrainControl.new()
	control.init(10 * 3600, 1)
	var enter: int = control.start_timer
	var raised: Array[Vector2i] = _run_visit(control, enter)
	var states: Array[int] = []
	for r: Vector2i in raised:
		states.append(r.x)
	assert_array(states).is_equal([
		TrainControl.STATE_APPROACH,
		TrainControl.STATE_STOPPED,
		TrainControl.STATE_PULL_OUT,
		TrainControl.STATE_GONE,
	])
	assert_bool(control.is_running()).is_false()
	## Next visit is the following hour.
	assert_int(control.start_timer).is_equal(11 * 3600 + 14 * 60 + 50)


func test_the_train_stops_just_past_the_station_trigger() -> void:
	var control := TrainControl.new()
	control.init(10 * 3600, 1)
	var now: int = control.start_timer
	var hz := int(DecompTime.TICK_HZ)
	for tick: int in hz * 120:
		if control.step(now + tick / hz, 1) == TrainControl.STATE_STOPPED:
			break
	assert_int(control.action).is_equal(TrainControl.Action.SIGNAL_STOPPED)
	assert_float(control.x_gx).is_greater(TrainControl.STOP_FROM_X_GX)
	## It stops on the station acre (block 3).
	assert_int(int(control.x_gx / TrainControl.BLOCK_GX)).is_equal(3)


func test_the_train_waits_its_dwell_before_leaving() -> void:
	var control := TrainControl.new()
	control.init(10 * 3600, 1)
	var raised: Array[Vector2i] = _run_visit(control, control.start_timer)
	var stopped_tick: int = raised[1].y
	var pull_tick: int = raised[2].y
	## Stood for at least the 310 s dwell (entry → stop already ate into `start_timer`).
	assert_int(pull_tick - stopped_tick).is_greater(int(DecompTime.TICK_HZ) * 60)


func test_the_first_job_holds_the_timetable() -> void:
	var control := TrainControl.new()
	control.init(10 * 3600, 1)
	assert_int(control.step(control.start_timer, 1, true)).is_equal(TrainControl.STATE_NONE)
	assert_bool(control.is_running()).is_false()


func test_title_demo_one_parks_and_never_leaves() -> void:
	var control := TrainControl.new()
	control.init(13 * 3600, 6)
	for tick: int in 30 * 60 * 30:
		assert_int(control.step(13 * 3600 + tick / int(DecompTime.TICK_HZ), 6, false, true)).is_equal(TrainControl.STATE_NONE)
	assert_int(control.action).is_equal(TrainControl.Action.WAIT_STOPPED)
	assert_float(control.x_gx).is_equal(TrainControl.PARKED_X_GX)


func test_a_new_day_rolls_a_past_midnight_timer_back() -> void:
	var control := TrainControl.new()
	control.init(23 * 3600 + 30 * 60, 1)
	assert_int(control.start_timer).is_greater(TrainControl.DAY_SEC)
	control.step(10, 2)
	assert_int(control.start_timer).is_equal(14 * 60 + 50)


func test_area_is_the_players_row_within_one_block() -> void:
	var control := TrainControl.new()
	control.mati_init()
	## Loco at 2367 → block 3, rail row block 1.
	assert_bool(control.in_area(Vector2i(3, 1))).is_true()
	assert_bool(control.in_area(Vector2i(2, 1))).is_true()
	assert_bool(control.in_area(Vector2i(4, 1))).is_true()
	assert_bool(control.in_area(Vector2i(5, 1))).is_false()
	assert_bool(control.in_area(Vector2i(3, 2))).is_false()


func test_mid_and_passenger_cars_settle_on_their_couplings() -> void:
	var cars := TrainCars.new()
	cars.spawn(1000.0)
	for i: int in 200:
		cars.step(1000.0, 0.0, TrainControl.Action.WAIT_STOPPED, false)
	assert_float(cars.mid_x).is_between(875.0, 877.0)
	assert_float(cars.caboose_x).is_between(750.0, 754.0)


func test_couplings_stay_within_their_slack_while_moving() -> void:
	var cars := TrainCars.new()
	var x: float = 320.0
	cars.spawn(x)
	for i: int in 600:
		x += 0.5 * TrainControl.FAST_SPEED
		cars.step(x, TrainControl.FAST_SPEED, TrainControl.Action.SPAWN_MOVING, false)
		assert_float(cars.mid_x - (x - 125.0)).is_between(0.0, 2.0)
		assert_float(cars.caboose_x - (cars.mid_x - 125.0)).is_between(0.0, 2.0)


func test_title_demo_pins_the_mid_car_and_freezes_the_passenger_car() -> void:
	var cars := TrainCars.new()
	cars.spawn(2367.0)
	cars.step(2367.0, 0.0, TrainControl.Action.WAIT_STOPPED, true)
	assert_float(cars.mid_x).is_equal(2367.0 - 125.0)
	assert_float(cars.caboose_x).is_equal(2367.0 - 250.0)


func test_door_table_matches_setup_action() -> void:
	## Stopping: `open` clip at 0.5 with the SE; standing: `close` held at frame 1 (open);
	## starting: `close` at 0.5 with the SE; running: `open` frame 1 (shut).
	var stopping: Dictionary = TrainCars.door_setup(TrainControl.Action.SIGNAL_STOPPED, false)
	assert_int(stopping["clip"]).is_equal(TrainCars.DOOR_OPEN_CLIP)
	assert_float(stopping["speed"]).is_equal(0.5)
	assert_bool(stopping["sound"]).is_true()
	var standing: Dictionary = TrainCars.door_setup(TrainControl.Action.WAIT_STOPPED, false)
	assert_int(standing["clip"]).is_equal(TrainCars.DOOR_CLOSE_CLIP)
	assert_float(standing["speed"]).is_equal(0.0)
	assert_bool(standing["sound"]).is_false()
	var starting: Dictionary = TrainCars.door_setup(TrainControl.Action.SIGNAL_STARTING, false)
	assert_int(starting["clip"]).is_equal(TrainCars.DOOR_CLOSE_CLIP)
	assert_bool(starting["sound"]).is_true()
	var running: Dictionary = TrainCars.door_setup(TrainControl.Action.SPEED_UP, false)
	assert_int(running["clip"]).is_equal(TrainCars.DOOR_OPEN_CLIP)
	assert_float(running["speed"]).is_equal(0.0)


func test_a_freshly_spawned_car_skips_to_the_end_quietly() -> void:
	var cars := TrainCars.new()
	cars.spawn(2200.0)
	var door: Dictionary = cars.step(2200.0, 0.0, TrainControl.Action.SIGNAL_STOPPED, false)
	assert_bool(door["at_end"]).is_true()
	assert_bool(door["sound"]).is_false()
	## Once it has run a tick, the next open/close is heard.
	var later: Dictionary = cars.step(2200.0, 0.0, TrainControl.Action.SIGNAL_STARTING, false)
	assert_bool(later["sound"]).is_true()


func test_sound_curves() -> void:
	assert_float(Ongen.volume(0.0)).is_equal_approx(1.15, 0.0001)
	assert_float(Ongen.volume(540.0)).is_equal_approx(0.0, 0.0001)
	assert_float(Ongen.volume(541.0)).is_equal(0.0)
	assert_float(TrainService.whistle_volume(320.0)).is_equal_approx(1.15, 0.0001)
	assert_float(TrainService.whistle_volume(6400.0)).is_equal_approx(0.0, 0.0001)
	assert_float(TrainService.whistle_volume(8000.0)).is_equal(0.0)


func test_pan_follows_the_east_west_bearing() -> void:
	var mic := Vector3(1000.0, 0.0, 1000.0)
	assert_float(Ongen.pan(mic, mic + Vector3(500.0, 0.0, 0.0))).is_greater(0.9)
	assert_float(Ongen.pan(mic, mic + Vector3(-500.0, 0.0, 0.0))).is_less(-0.9)
	assert_float(Ongen.pan(mic, mic + Vector3(0.0, 0.0, -500.0))).is_equal_approx(0.0, 0.05)
	assert_float(Ongen.pan(mic, mic + Vector3(0.0, 0.0, 500.0))).is_equal_approx(0.0, 0.05)


func test_gx_world_round_trip_matches_the_title_mapping() -> void:
	var gx := Vector3(2367.0, 0.0, 740.0)
	var town := WorldData.new()
	town.columns = WorldGenerator.FG_X * WorldGenerator.UT
	town.rows = WorldGenerator.FG_Z * WorldGenerator.UT
	town.cell_size = 2.0
	assert_vector(TownSpace.gx_to_world(gx)).is_equal_approx(TitleDemo.gx_to_world(town, gx), Vector3.ONE * 0.001)
	assert_vector(TownSpace.world_to_gx(TownSpace.gx_to_world(gx))).is_equal_approx(gx, Vector3.ONE * 0.001)
