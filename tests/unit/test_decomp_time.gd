class_name TestDecompTime
extends GdUnitTestSuite


func test_rates_and_conversions() -> void:
	assert_float(DecompTime.TICK_HZ).is_equal(60.0)
	assert_float(DecompTime.FRAME_HZ).is_equal(30.0)
	assert_float(DecompTime.TICKS_PER_FRAME).is_equal(2.0)
	assert_float(DecompTime.ticks_to_sec(30.0)).is_equal_approx(0.5, 1e-6)
	assert_float(DecompTime.frames_to_sec(15.0)).is_equal_approx(0.5, 1e-6)
	assert_float(DecompTime.sec_to_ticks(DecompTime.frames_to_sec(1.0))).is_equal_approx(2.0, 1e-6)


func test_pipeline_bakes_clips_at_frame_hz() -> void:
	## Clip keyframe times come from `ckf.py`; code that names a clip frame divides by
	## `FRAME_HZ`, so the two must agree.
	var src: String = FileAccess.get_file_as_string("res://tools/asset_pipeline/ckf.py")
	var re := RegEx.create_from_string("(?m)^FPS = ([0-9.]+)")
	var m: RegExMatch = re.search(src)
	assert_object(m).is_not_null()
	assert_float(float(m.get_string(1))).is_equal(DecompTime.FRAME_HZ)


func test_stepper_runs_whole_ticks_at_any_render_rate() -> void:
	for fps: float in [30.0, 60.0, 144.0, 240.0]:
		var steps := FrameStepper.new()
		var n: int = 0
		for _i: int in int(fps):
			steps.add(1.0 / fps)
			while steps.next():
				n += 1
		assert_int(n).is_between(59, 60)


func test_stepper_backlog_caps_banked_ticks() -> void:
	var steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
	assert_int(steps.take(1.0)).is_equal(8)
	assert_float(steps.pending()).is_equal(0.0)


func test_stepper_keeps_ticks_banked_when_gated() -> void:
	var steps := FrameStepper.new()
	steps.add(3.5 / 60.0)
	var alive := false
	while alive and steps.next():
		pass
	assert_float(steps.pending()).is_equal_approx(3.5, 1e-4)
	steps.reset()
	assert_float(steps.pending()).is_equal(0.0)
