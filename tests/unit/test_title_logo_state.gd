class_name TestTitleLogoState
extends GdUnitTestSuite

## `ac_animal_logo.c` state machine, run in seconds.

const STEP := 1.0 / 60.0


func _run(state: TitleLogoState, seconds: float, hz: float = 60.0) -> void:
	for i: int in roundi(seconds * hz):
		state.update(1.0 / hz, false)


func _to_game_start() -> TitleLogoState:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_SECONDS)
	assert_int(state.action).is_equal(TitleLogoState.Action.BACK_FADE_IN)
	_run(state, 0.25)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)
	_run(state, TitleLogoState.HOLD_TIME + STEP)
	return state


func test_logo_animates_for_four_seconds_then_fades_the_back_in() -> void:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_SECONDS - 0.1)
	assert_int(state.action).is_equal(TitleLogoState.Action.IN)
	assert_float(state.anim_seconds()).is_equal_approx(3.9, 0.001)
	_run(state, 0.1)
	assert_int(state.action).is_equal(TitleLogoState.Action.BACK_FADE_IN)
	assert_float(state.anim_seconds()).is_equal_approx(TitleLogoState.IN_SECONDS, 0.0001)
	assert_bool(state.back_visible()).is_true()
	assert_bool(state.copyright_visible()).is_false()


func test_back_fades_in_to_220_over_about_eleven_ticks() -> void:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_SECONDS)
	_run(state, 5.0 / 60.0)
	assert_float(state.back_opacity).is_equal_approx(100.0 / 255.0, 0.01)
	assert_int(state.action).is_equal(TitleLogoState.Action.BACK_FADE_IN)
	_run(state, 7.0 / 60.0)
	assert_float(state.back_opacity).is_equal_approx(TitleLogoState.BACK_FADEIN_MAX, 0.0001)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)


func test_start_skips_the_intro_and_snaps_everything_to_the_end() -> void:
	var state := TitleLogoState.new()
	_run(state, 0.5)
	state.update(STEP, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)
	assert_float(state.in_time).is_equal(TitleLogoState.IN_SECONDS)
	assert_float(state.copyright_opacity).is_equal(1.0)
	assert_float(state.back_opacity).is_equal(TitleLogoState.BACK_FADEIN_MAX)
	assert_float(state.hold_left).is_equal(TitleLogoState.HOLD_TIME)
	assert_bool(state.copyright_visible()).is_true()


func test_start_skips_the_back_fade_too() -> void:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_SECONDS + 3.0 / 60.0)
	state.update(STEP, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)


func test_start_is_ignored_until_the_hold_runs_out() -> void:
	var state := TitleLogoState.new()
	state.update(STEP, true)
	## A second of hold, START ignored (it only means something in GAME_START) …
	for i: int in 59:
		state.update(STEP, true)
		assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)
	## … and then it moves on.
	state.update(STEP, false)
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)


func test_press_start_pulses_through_the_full_range_dim_half_faster() -> void:
	var state := _to_game_start()
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)
	assert_bool(state.press_start_visible()).is_true()
	var lo := 1.0
	var hi := 0.0
	var dim := 0
	var bright := 0
	for i: int in 144:
		state.update(STEP, false)
		lo = minf(lo, state.press_start_opacity)
		hi = maxf(hi, state.press_start_opacity)
		if state.press_start_opacity < 0.5:
			dim += 1
		else:
			bright += 1
	assert_float(lo).is_less(0.02)
	assert_float(hi).is_greater(0.98)
	## Two periods of ~1.2 s: the ~50-tick bright half outlasts the ~22-tick dim one.
	assert_int(bright).is_greater(dim * 2)


func test_pulse_is_the_same_at_any_frame_rate() -> void:
	var a := _to_game_start()
	var b := _to_game_start()
	_run(a, 1.7, 60.0)
	_run(b, 1.7, 10.0)
	assert_float(b.press_start_opacity).is_equal_approx(a.press_start_opacity, 0.001)


func test_start_is_gated_on_readiness_and_the_demo_lockout() -> void:
	var state := _to_game_start()
	var signals := monitor_signals(state)
	state.update(STEP, true, false, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)
	state.update(STEP, true, true, false)
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)
	state.update(STEP, true, true, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.FADE_OUT_START)
	await assert_signal(signals).is_emitted("start_chime")
	assert_float(state.press_start_opacity).is_equal(1.0)
	assert_float(state.hold_left).is_equal(TitleLogoState.FADEOUT_TIME)


func test_fade_out_holds_26_ticks_then_selects_once() -> void:
	var state := _to_game_start()
	var selected: Array[int] = [0]
	state.start_selected.connect(func() -> void: selected[0] += 1)
	state.update(STEP, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.FADE_OUT_START)
	_run(state, TitleLogoState.FADEOUT_TIME - 2.0 * STEP)
	assert_int(state.action).is_equal(TitleLogoState.Action.FADE_OUT_START)
	assert_int(selected[0]).is_equal(0)
	_run(state, 2.0 * STEP)
	assert_int(state.action).is_equal(TitleLogoState.Action.OUT)
	assert_bool(state.is_leaving()).is_true()
	assert_bool(state.press_start_visible()).is_true()
	_run(state, 0.5)
	assert_int(selected[0]).is_equal(1)


func test_demo_running_out_idles_the_logo_and_hides_press_start() -> void:
	var state := _to_game_start()
	state.update(STEP, false, true, true, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.IDLE)
	assert_bool(state.press_start_visible()).is_false()
	assert_bool(state.copyright_visible()).is_true()
	## Nothing brings it back.
	state.update(STEP, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.IDLE)
