class_name TestTitleLogo
extends GdUnitTestSuite

## The title logo (`ac_animal_logo.c`): the `Sequence` clips against the decomp's tick counts,
## and START / the demo running out driving them.

## 60 Hz ticks: the logo clips (frames 1–121 at speed 0.5), the backdrop's fade to 220/255
## (there on tick 11, moving on at 12: `aAL_back_fadein` checks `> 220`), `aAL_TIMER`, the pulse halves (32768 s16 at 655 / 1489 a tick) and
## `aAL_FADEOUT_TIMER`.
const LOGO_TICKS := 240
const BACK_FADE_TICKS := 11
const BACK_DONE_TICKS := 12
const BACK_MAX := 220.0 / 255.0
const HOLD_TICKS := 60
const BRIGHT_TICKS := 32768.0 / 655.0
const DIM_TICKS := 32768.0 / 1489.0
const FADEOUT_TICKS := 26
const S := DecompTime.TICK_SEC


func _logo() -> CanvasLayer:
	var logo: CanvasLayer = auto_free((load("res://scenes/ui/title_logo.tscn") as PackedScene).instantiate())
	add_child(logo)
	## Step it by hand: the tests own the clock.
	_seq(logo).callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return logo


func _seq(logo: CanvasLayer) -> AnimationPlayer:
	return logo.get_node("%Sequence") as AnimationPlayer


func _run(logo: CanvasLayer, seconds: float) -> void:
	for _i: int in roundi(seconds / S):
		_seq(logo).advance(S)


func _to_pulse(logo: CanvasLayer) -> void:
	_run(logo, (LOGO_TICKS + BACK_DONE_TICKS + HOLD_TICKS + 2) * S)
	assert_str(String(_seq(logo).current_animation)).is_equal("pulse")


func test_clips_match_the_decomp_ticks() -> void:
	var seq: AnimationPlayer = _seq(_logo())
	var intro: Animation = seq.get_animation(&"in")
	assert_float(intro.length).is_equal_approx((LOGO_TICKS + BACK_DONE_TICKS) * S, 0.001)
	var back: int = intro.find_track(^".:back_opacity", Animation.TYPE_VALUE)
	assert_float(float(intro.value_track_interpolate(back, LOGO_TICKS * S))).is_equal_approx(0.0, 0.001)
	assert_float(float(intro.value_track_interpolate(back, (LOGO_TICKS + 5) * S))).is_equal_approx(100.0 / 255.0, 0.001)
	assert_float(float(intro.value_track_interpolate(back, (LOGO_TICKS + BACK_FADE_TICKS) * S))).is_equal_approx(BACK_MAX, 0.001)
	assert_float(float(intro.value_track_interpolate(back, intro.length))).is_equal_approx(BACK_MAX, 0.001)
	assert_float(seq.get_animation(&"hold").length).is_equal_approx(HOLD_TICKS * S, 0.001)
	var pulse: Animation = seq.get_animation(&"pulse")
	assert_int(pulse.loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_float(pulse.length).is_equal_approx((BRIGHT_TICKS + DIM_TICKS) * S, 0.001)
	var beat: int = pulse.find_track(^".:pulse", Animation.TYPE_VALUE)
	assert_float(pulse.track_get_key_time(beat, 1)).is_equal_approx(BRIGHT_TICKS * S, 0.001)
	assert_float(seq.get_animation(&"start").length).is_equal_approx(FADEOUT_TICKS * S, 0.001)


func test_logo_then_backdrop_then_hold_then_pulse() -> void:
	var logo := _logo()
	assert_bool((logo.get_node("%BackRoot") as Node3D).visible).is_false()
	_run(logo, (LOGO_TICKS + 3) * S)
	assert_str(String(_seq(logo).current_animation)).is_equal("in")
	assert_bool((logo.get_node("%BackRoot") as Node3D).visible).is_true()
	_run(logo, (BACK_DONE_TICKS + 2) * S)
	assert_str(String(_seq(logo).current_animation)).is_equal("hold")
	assert_float(float(logo.get("back_opacity"))).is_equal_approx(BACK_MAX, 0.001)
	assert_bool((logo.get_node("%Tm") as Node3D).visible).is_true()
	assert_bool((logo.get_node("%PressStart") as Control).visible).is_false()
	_run(logo, HOLD_TICKS * S)
	assert_str(String(_seq(logo).current_animation)).is_equal("pulse")
	assert_bool((logo.get_node("%PressStart") as Control).visible).is_true()


func test_start_skips_the_intro_then_waits_out_the_hold() -> void:
	var logo := _logo()
	_run(logo, 0.5)
	logo.call("press_start")
	_run(logo, 2 * S)
	assert_str(String(_seq(logo).current_animation)).is_equal("hold")
	assert_float(float(logo.get("back_opacity"))).is_equal_approx(BACK_MAX, 0.001)
	## START during the hold means nothing.
	logo.call("press_start")
	_run(logo, (HOLD_TICKS - 5) * S)
	assert_str(String(_seq(logo).current_animation)).is_equal("hold")
	_run(logo, 8 * S)
	assert_str(String(_seq(logo).current_animation)).is_equal("pulse")


func test_press_start_breathes_bright_slow_dim_fast() -> void:
	var logo := _logo()
	_to_pulse(logo)
	var press := logo.get_node("%PressStart") as Control
	var lo := 1.0
	var hi := 0.0
	var dim := 0
	var bright := 0
	for _i: int in 144:
		_seq(logo).advance(S)
		lo = minf(lo, press.modulate.a)
		hi = maxf(hi, press.modulate.a)
		if press.modulate.a < 0.5:
			dim += 1
		else:
			bright += 1
	assert_float(lo).is_less(0.02)
	assert_float(hi).is_greater(0.98)
	## The ~50-tick bright half outlasts the ~22-tick dim one.
	assert_int(bright).is_greater(dim * 2)


func test_start_waits_for_the_owner_then_selects_once() -> void:
	var logo := _logo()
	var chimes: Array[int] = [0]
	var selected: Array[int] = [0]
	logo.connect(&"start_chime", func() -> void: chimes[0] += 1)
	logo.connect(&"start_selected", func() -> void: selected[0] += 1)
	_to_pulse(logo)
	logo.set("can_start", false)
	logo.call("press_start")
	assert_str(String(_seq(logo).current_animation)).is_equal("pulse")
	logo.set("can_start", true)
	logo.set("button_ok", false)
	logo.call("press_start")
	assert_str(String(_seq(logo).current_animation)).is_equal("pulse")
	logo.set("button_ok", true)
	logo.call("press_start")
	assert_str(String(_seq(logo).current_animation)).is_equal("start")
	assert_int(chimes[0]).is_equal(1)
	_seq(logo).advance(0.0)
	assert_float((logo.get_node("%PressStart") as Control).modulate.a).is_equal(1.0)
	_run(logo, (FADEOUT_TICKS - 2) * S)
	assert_int(selected[0]).is_equal(0)
	_run(logo, 0.5)
	assert_int(selected[0]).is_equal(1)


func test_demo_running_out_idles_the_logo() -> void:
	var logo := _logo()
	_to_pulse(logo)
	logo.set("demo_ended", true)
	assert_bool(_seq(logo).is_playing()).is_false()
	assert_bool((logo.get_node("%PressStart") as Control).visible).is_false()
	assert_bool((logo.get_node("%Tm") as Node3D).visible).is_true()
	## Nothing brings it back.
	logo.set("can_start", true)
	logo.call("press_start")
	assert_bool(_seq(logo).is_playing()).is_false()


func test_demo_over_before_the_pulse_idles_as_it_starts() -> void:
	var logo := _logo()
	logo.set("demo_ended", true)
	_run(logo, (LOGO_TICKS + BACK_DONE_TICKS + HOLD_TICKS + 2) * S)
	assert_bool(_seq(logo).is_playing()).is_false()
	assert_bool((logo.get_node("%PressStart") as Control).visible).is_false()

