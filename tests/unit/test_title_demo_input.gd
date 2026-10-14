class_name TestTitleDemoInput
extends GdUnitTestSuite

## `m_titledemo.c` `set_player_demo_keydata`: 7-bit signed sticks, A/B bits, 30 Hz samples
## consumed at 60 Hz with the stick blended across the odd tick.


func test_stick_fields_are_seven_bit_signed() -> void:
	## `XXXXXXXB YYYYYYYA`: 0x0201 → X = +1 (0x0200 / 512), Y = 0, A down.
	assert_int(TitleDemoInput.stick_x(0x0201)).is_equal(1)
	assert_int(TitleDemoInput.stick_y(0x0201)).is_equal(0)
	assert_bool(TitleDemoInput.a_bit(0x0201)).is_true()
	## 0x7E00 is the largest positive X (63); 0x8000 the most negative (−64).
	assert_int(TitleDemoInput.stick_x(0x7E00)).is_equal(63)
	assert_int(TitleDemoInput.stick_x(0x8000)).is_equal(-64)
	## Y lives in the low byte's top seven bits: 0x7E → +63, 0x80 → −64, 0xFE → −1.
	assert_int(TitleDemoInput.stick_y(0x007E)).is_equal(63)
	assert_int(TitleDemoInput.stick_y(0x0080)).is_equal(-64)
	assert_int(TitleDemoInput.stick_y(0x00FE)).is_equal(-1)


func test_b_is_bit_eight_and_a_is_bit_zero() -> void:
	assert_bool(TitleDemoInput.b_bit(0x0100)).is_true()
	assert_bool(TitleDemoInput.a_bit(0x0100)).is_false()
	assert_bool(TitleDemoInput.a_bit(0x0001)).is_true()
	assert_bool(TitleDemoInput.b_bit(0x0001)).is_false()


func test_real_sample_words_decode() -> void:
	## First moving words of `pact0`: 0x02EC then 0x36FE (its long steady hold).
	assert_int(TitleDemoInput.stick_x(0x02EC)).is_equal(1)
	assert_int(TitleDemoInput.stick_y(0x02EC)).is_equal(-10)
	assert_int(TitleDemoInput.stick_x(0x36FE)).is_equal(27)
	assert_int(TitleDemoInput.stick_y(0x36FE)).is_equal(-1)


func test_deadzone_and_clamp() -> void:
	assert_vector(TitleDemoInput.stick_to_move(0.0, 0.0)).is_equal(Vector2.ZERO)
	## Under `STICK_MIN` (9.9) nothing moves.
	assert_vector(TitleDemoInput.stick_to_move(9.0, 0.0)).is_equal(Vector2.ZERO)
	## Full deflection is magnitude 1; stick up (+Y) is Godot forward (−Y).
	assert_vector(TitleDemoInput.stick_to_move(61.0, 0.0)).is_equal(Vector2(1.0, 0.0))
	assert_vector(TitleDemoInput.stick_to_move(0.0, 61.0)).is_equal(Vector2(0.0, -1.0))
	## Beyond `STICK_MAX` the magnitude clamps at 1.
	assert_float(TitleDemoInput.stick_to_move(122.0, 0.0).length()).is_equal_approx(1.0, 0.0001)
	## Half deflection keeps its direction.
	var half: Vector2 = TitleDemoInput.stick_to_move(30.5, 0.0)
	assert_float(half.x).is_equal_approx(0.5, 0.0001)


## A 60 Hz physics step.
const T := 1.0 / 60.0


func test_samples_play_at_30_hz_and_blend_between() -> void:
	var input := TitleDemoInput.new()
	## Sample 0 is idle, sample 1 is full right (X = 63 → 0x7E00).
	input.setup(PackedInt32Array([0x0000, 0x7E00, 0x7E00]))
	input.step(T)  # t = 0: sample 0 → idle
	assert_vector(input.move).is_equal(Vector2.ZERO)
	input.step(T)  # halfway to sample 1 → stick (0 + 63) / 2 = 31.5
	assert_float(input.move.x).is_equal_approx(31.5 / 61.0, 0.0001)
	input.step(T)  # sample 1 → stick 63, past `STICK_MAX`, clamps to magnitude 1
	assert_float(input.move.x).is_equal_approx(1.0, 0.0001)
	assert_float(input.time).is_equal_approx(3.0 * T, 0.0001)


func test_blend_stops_at_sample_limit() -> void:
	var samples := PackedInt32Array()
	samples.resize(1802)
	samples.fill(0)
	samples[1800] = 0x7E00
	samples[1799] = 0x0000
	var input := TitleDemoInput.new()
	input.setup(samples)
	## Halfway between 1799 and 1800 (≥ 1800): no blend, only sample 1799.
	input.time = 1799.5 / TitleDemoInput.SAMPLE_HZ
	input.step(T)
	assert_vector(input.move).is_equal(Vector2.ZERO)


func test_a_trigger_is_a_rising_edge_that_latches_until_consumed() -> void:
	var input := TitleDemoInput.new()
	input.setup(PackedInt32Array([0x0001, 0x0001, 0x0000]))
	input.step(T)  # sample 0, A down → edge
	assert_bool(input.a_held).is_true()
	assert_bool(input.consume_a_pressed()).is_true()
	## Taken once: a second read in the same step does not fire again.
	assert_bool(input.consume_a_pressed()).is_false()
	input.step(T)  # still sample 0 → held, no new edge
	assert_bool(input.a_held).is_true()
	assert_bool(input.consume_a_pressed()).is_false()
	input.step(T)  # sample 1 (A) → still held
	input.step(T)
	input.step(T)  # sample 2 → released
	assert_bool(input.a_held).is_false()


func test_an_unread_edge_survives_a_double_step() -> void:
	var input := TitleDemoInput.new()
	input.setup(PackedInt32Array([0x0001, 0x0001, 0x0001]))
	input.step(T)  # edge
	input.step(T)  # second step before anyone read it — must not swallow the press
	assert_bool(input.consume_a_pressed()).is_true()
	assert_bool(input.consume_a_pressed()).is_false()


func test_a_tap_between_coarse_steps_still_presses() -> void:
	## A held for one sample (1/30 s) is caught even when a step skips past it.
	var input := TitleDemoInput.new()
	input.setup(PackedInt32Array([0x0000, 0x0001, 0x0000, 0x0000]))
	input.step(0.1)
	input.step(0.1)
	assert_bool(input.a_held).is_false()
	assert_bool(input.consume_a_pressed()).is_true()


func test_running_off_the_end_is_idle() -> void:
	var input := TitleDemoInput.new()
	input.setup(PackedInt32Array([0x7E01]))
	input.time = 10.0 / TitleDemoInput.SAMPLE_HZ
	input.step(T)
	assert_vector(input.move).is_equal(Vector2.ZERO)
	assert_bool(input.a_held).is_false()
