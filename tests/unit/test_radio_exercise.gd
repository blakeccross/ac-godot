extends GdUnitTestSuite

## `Player_actor_Check_radio_exercise_command` / `CheckController_forRadio_exercise`.


func _feed(rx: RadioExercise, cmds: Array) -> void:
	for c: int in cmds:
		rx.log_command(c)


func test_stick_directions() -> void:
	assert_int(RadioExercise.direction(Vector2.ZERO)).is_equal(0)
	assert_int(RadioExercise.direction(Vector2(0.0, 0.5))).is_equal(0)
	assert_int(RadioExercise.direction(Vector2(0.0, -1.0))).is_equal(6)
	assert_int(RadioExercise.direction(Vector2(0.0, 1.0))).is_equal(3)
	assert_int(RadioExercise.direction(Vector2(1.0, 0.0))).is_equal(1)
	assert_int(RadioExercise.direction(Vector2(-1.0, 0.0))).is_equal(2)
	assert_int(RadioExercise.direction(Vector2(1.0, -1.0).normalized())).is_equal(7)
	assert_int(RadioExercise.direction(Vector2(-1.0, -1.0).normalized())).is_equal(8)
	assert_int(RadioExercise.direction(Vector2(1.0, 1.0).normalized())).is_equal(4)
	assert_int(RadioExercise.direction(Vector2(-1.0, 1.0).normalized())).is_equal(5)


func test_down_neutral_up_is_the_first_exercise() -> void:
	var rx := RadioExercise.new()
	_feed(rx, [0, 6, 0, 3])
	assert_int(rx.step()).is_equal(0)
	## Starting it logs a blank, so it does not fire again by itself.
	rx.begin()
	assert_int(rx.step()).is_equal(-1)


func test_holding_a_direction_logs_it_once() -> void:
	var rx := RadioExercise.new()
	for _i: int in 30:
		rx.log_command(6)
	_feed(rx, [0, 3])
	assert_int(rx.step()).is_equal(0)


func test_full_circle_and_its_chain() -> void:
	var rx := RadioExercise.new()
	_feed(rx, [1, 4, 3, 5, 2])
	## The half circle chains (`continue_command_data`): it waits 6 ticks for the full circle.
	assert_int(rx.step()).is_equal(-1)
	assert_int(rx.pending).is_equal(1)
	for _i: int in 5:
		rx.step()
	assert_int(rx.step()).is_equal(1)
	var full := RadioExercise.new()
	_feed(full, [6, 8, 2, 5, 3, 4, 1, 7])
	assert_int(full.step()).is_equal(16)


func test_no_input_breaks_a_pattern() -> void:
	var rx := RadioExercise.new()
	_feed(rx, [6, -1, 3])
	assert_int(rx.step()).is_equal(-1)
