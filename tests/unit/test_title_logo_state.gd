class_name TestTitleLogoState
extends GdUnitTestSuite

## `ac_animal_logo.c` state machine, counted in 60 Hz ticks.


func _run(state: TitleLogoState, ticks: int) -> void:
	for i: int in ticks:
		state.tick(false)


func _to_game_start() -> TitleLogoState:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_TICKS)
	assert_int(state.action).is_equal(TitleLogoState.Action.BACK_FADE_IN)
	_run(state, 12)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)
	_run(state, TitleLogoState.TIMER)
	return state


func test_logo_animates_for_four_seconds_then_fades_the_back_in() -> void:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_TICKS - 1)
	assert_int(state.action).is_equal(TitleLogoState.Action.IN)
	assert_float(state.anim_seconds()).is_equal_approx(239.0 / 60.0, 0.0001)
	state.tick(false)
	assert_int(state.action).is_equal(TitleLogoState.Action.BACK_FADE_IN)
	assert_float(state.anim_seconds()).is_equal_approx(TitleLogoState.IN_SECONDS, 0.0001)
	assert_bool(state.back_visible()).is_true()
	assert_bool(state.copyright_visible()).is_false()


func test_back_fades_in_twenty_per_tick_and_lands_on_220() -> void:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_TICKS)
	## 20, 40 … 220 over eleven ticks; the check is a strict `>`, so 220 stays put …
	_run(state, 11)
	assert_int(state.back_opacity).is_equal(220)
	assert_int(state.action).is_equal(TitleLogoState.Action.BACK_FADE_IN)
	## … and the twelfth tick overshoots, clamps and moves on.
	state.tick(false)
	assert_int(state.back_opacity).is_equal(220)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)


func test_start_skips_the_intro_and_snaps_everything_to_the_end() -> void:
	var state := TitleLogoState.new()
	_run(state, 30)
	state.tick(true)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)
	assert_int(state.in_ticks).is_equal(TitleLogoState.IN_TICKS)
	assert_int(state.copyright_opacity).is_equal(255)
	assert_int(state.back_opacity).is_equal(TitleLogoState.BACK_FADEIN_MAX)
	assert_int(state.title_timer).is_equal(TitleLogoState.TIMER)
	assert_bool(state.copyright_visible()).is_true()


func test_start_skips_the_back_fade_too() -> void:
	var state := TitleLogoState.new()
	_run(state, TitleLogoState.IN_TICKS + 3)
	state.tick(true)
	assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)


func test_start_is_ignored_until_the_hold_timer_runs_out() -> void:
	var state := TitleLogoState.new()
	state.tick(true)
	## 59 more ticks of hold, START ignored (it only means something in GAME_START) …
	for i: int in TitleLogoState.TIMER - 1:
		state.tick(true)
		assert_int(state.action).is_equal(TitleLogoState.Action.START_KEY_CHK_START)
	## … and the sixtieth tick releases the timer.
	state.tick(false)
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)


func test_press_start_pulse_follows_the_s16_phase_walk() -> void:
	var state := _to_game_start()
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)
	## The phase begins at 0 (not positive), so the first step is the fast 32768/22 = 1489.
	state.tick(false)
	var expected: float = 127.5 * sin(1489.0 * TAU / 65536.0) + 127.5
	assert_float(state.press_start_opacity).is_equal_approx(expected, 0.01)
	assert_bool(state.press_start_visible()).is_true()


func test_pulse_spans_the_full_range_and_the_negative_half_is_faster() -> void:
	var state := _to_game_start()
	var lo := 255.0
	var hi := 0.0
	var below_mid := 0
	var above_mid := 0
	for i: int in 144:
		state.tick(false)
		lo = minf(lo, state.press_start_opacity)
		hi = maxf(hi, state.press_start_opacity)
		if state.press_start_opacity < 127.5:
			below_mid += 1
		else:
			above_mid += 1
	assert_float(lo).is_less(3.0)
	assert_float(hi).is_greater(252.0)
	## Two full periods (~72 ticks each): the ~50-tick positive half beats the ~22-tick one.
	assert_int(above_mid).is_greater(below_mid)


func test_start_is_gated_on_readiness_and_the_demo_lockout() -> void:
	var state := _to_game_start()
	state.tick(false)
	state.tick(true, false, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)
	state.tick(true, true, false)
	assert_int(state.action).is_equal(TitleLogoState.Action.GAME_START)
	state.tick(true, true, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.FADE_OUT_START)
	assert_bool(state.start_chime_requested).is_true()
	assert_float(state.press_start_opacity).is_equal(255.0)
	assert_int(state.title_timer).is_equal(TitleLogoState.FADEOUT_TIMER)


func test_fade_out_holds_26_ticks_then_selects() -> void:
	var state := _to_game_start()
	state.tick(true)
	assert_int(state.action).is_equal(TitleLogoState.Action.FADE_OUT_START)
	for i: int in TitleLogoState.FADEOUT_TIMER - 1:
		state.tick(false)
		assert_int(state.action).is_equal(TitleLogoState.Action.FADE_OUT_START)
		assert_bool(state.select_requested).is_false()
	state.tick(false)
	assert_int(state.action).is_equal(TitleLogoState.Action.OUT)
	assert_bool(state.select_requested).is_true()
	assert_bool(state.is_leaving()).is_true()
	## One-shot: the request does not repeat.
	state.tick(false)
	assert_bool(state.select_requested).is_false()


func test_press_start_stays_drawn_through_the_fade_out() -> void:
	var state := _to_game_start()
	state.tick(true)
	assert_bool(state.press_start_visible()).is_true()
	_run(state, TitleLogoState.FADEOUT_TIMER)
	assert_int(state.action).is_equal(TitleLogoState.Action.OUT)
	assert_bool(state.press_start_visible()).is_true()


func test_demo_running_out_idles_the_logo_and_hides_press_start() -> void:
	var state := _to_game_start()
	state.tick(false, true, true, true)
	assert_int(state.action).is_equal(TitleLogoState.Action.IDLE)
	assert_bool(state.press_start_visible()).is_false()
	assert_bool(state.copyright_visible()).is_true()
	## Nothing brings it back.
	state.tick(true)
	assert_int(state.action).is_equal(TitleLogoState.Action.IDLE)
