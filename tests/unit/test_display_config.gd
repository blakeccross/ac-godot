class_name TestDisplayConfig
extends GdUnitTestSuite

## The screen-shape option for the settings page.

const PATH := "user://test_display_config.cfg"


func before_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DisplayConfig.reset(PATH)


func after_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DisplayConfig.reset()
	DisplayConfig._loaded = false


func test_defaults_to_adaptive_fill() -> void:
	assert_int(DisplayConfig.aspect).is_equal(DisplayConfig.Aspect.ADAPTIVE)
	assert_int(DisplayConfig.scale_aspect()).is_equal(Window.CONTENT_SCALE_ASPECT_EXPAND)


func test_next_cycles_through_every_mode() -> void:
	var seen: Array[int] = []
	var mode: int = DisplayConfig.Aspect.ADAPTIVE
	for _i: int in DisplayConfig.LABELS.size():
		seen.append(mode)
		mode = DisplayConfig.next(mode)
	assert_array(seen).contains_exactly_in_any_order([0, 1, 2])
	assert_int(mode).is_equal(DisplayConfig.Aspect.ADAPTIVE)


func test_fixed_modes_keep_their_shape() -> void:
	assert_int(DisplayConfig.scale_aspect(DisplayConfig.Aspect.STANDARD)).is_equal(Window.CONTENT_SCALE_ASPECT_KEEP)
	var wide := DisplayConfig.content_size(DisplayConfig.Aspect.WIDESCREEN)
	var standard := DisplayConfig.content_size(DisplayConfig.Aspect.STANDARD)
	assert_float(float(wide.x) / wide.y).is_equal_approx(16.0 / 9.0, 0.001)
	assert_float(float(standard.x) / standard.y).is_equal_approx(4.0 / 3.0, 0.001)


func test_choice_is_saved_and_reloaded() -> void:
	var window := Window.new()
	DisplayConfig.set_aspect(DisplayConfig.Aspect.STANDARD, window)
	assert_vector(Vector2(window.content_scale_size)).is_equal(Vector2(960, 720))
	assert_int(window.content_scale_aspect).is_equal(Window.CONTENT_SCALE_ASPECT_KEEP)
	window.free()
	DisplayConfig.aspect = DisplayConfig.Aspect.ADAPTIVE
	DisplayConfig._loaded = false
	DisplayConfig.ensure_loaded()
	assert_int(DisplayConfig.aspect).is_equal(DisplayConfig.Aspect.STANDARD)
