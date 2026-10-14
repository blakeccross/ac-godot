class_name TestWindowLightFade
extends GdUnitTestSuite

## Window lights fade between off and on at 320/0x3FFF a tick (`aPBOX_actor_move`): 0.85 s.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false
	VisualWindowLight._level = -1.0


func test_lights_come_on_over_about_0_85_seconds() -> void:
	var root := Node3D.new()
	add_child(root)
	Clock.apply_snapshot({"year": 2002, "month": 5, "day": 1, "hour": 12, "minute": 0})
	VisualWindowLight._level = -1.0
	VisualWindowLight.step_window_lights(root, 1.0 / 60.0)
	assert_float(VisualWindowLight.lit_level()).is_equal(0.0)
	Clock.apply_snapshot({"year": 2002, "month": 5, "day": 1, "hour": 18, "minute": 0})
	VisualWindowLight.step_window_lights(root, 25.0 / 60.0)
	assert_float(VisualWindowLight.lit_level()).is_between(0.45, 0.5)
	VisualWindowLight.step_window_lights(root, 0.5)
	assert_float(VisualWindowLight.lit_level()).is_equal(1.0)
	assert_that(VisualWindowLight.pane_color(0.5)).is_equal(Color(0.5, 0.5, 75.0 / 255.0, 1.0))
	root.free()
