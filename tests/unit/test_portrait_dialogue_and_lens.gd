class_name TestPortraitDialogueAndLens
extends GdUnitTestSuite

## Portrait phone only: the intro cameras zoom out a little and the talk window grows.

const OVERLAY_SCENE := "res://scenes/ui/dialogue_overlay.tscn"


func before_test() -> void:
	InputDeviceTracker.on_mobile = true
	InputDeviceTracker.portrait_override = 1


func after_test() -> void:
	InputDeviceTracker.on_mobile = OS.has_feature("android") or OS.has_feature("ios")
	InputDeviceTracker.portrait_override = -1


func test_lens_zooms_out_in_portrait_on_a_phone() -> void:
	var fov: float = IntroPortraitLens.fov(IntroKkStage.CAM_FOV)
	assert_float(fov).is_greater(IntroKkStage.CAM_FOV)
	## Visible extent grows by `ZOOM_OUT`.
	var ratio: float = tan(deg_to_rad(fov * 0.5)) / tan(deg_to_rad(IntroKkStage.CAM_FOV * 0.5))
	assert_float(ratio).is_equal_approx(IntroPortraitLens.ZOOM_OUT, 0.0001)


func test_lens_is_the_stages_in_landscape_and_off_a_phone() -> void:
	InputDeviceTracker.portrait_override = 0
	assert_float(IntroPortraitLens.fov(40.0)).is_equal(40.0)
	InputDeviceTracker.portrait_override = 1
	InputDeviceTracker.on_mobile = false
	assert_float(IntroPortraitLens.fov(40.0)).is_equal(40.0)


func test_train_camera_follows_the_orientation() -> void:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	var rig := IntroTrainCamera.new()
	rig.setup(cam)
	assert_float(cam.fov).is_equal_approx(IntroPortraitLens.fov(IntroTrainStage.CAM_FOV), 0.001)
	InputDeviceTracker.portrait_override = 0
	rig.advance(0.016, IntroTrainStage.ROVER_START_GX)
	assert_float(cam.fov).is_equal_approx(IntroTrainStage.CAM_FOV, 0.001)


func test_talk_window_fills_the_width_in_portrait() -> void:
	var chrome := _chrome(Vector2(390.0, 844.0))
	var rect: Rect2 = (chrome.get_node("Cloud") as Control).get_global_rect()
	assert_float(rect.size.x).is_equal_approx(390.0 * MessageWindowChrome.PORTRAIT_FILL, 0.5)
	assert_float(rect.get_center().x).is_equal_approx(195.0, 0.5)


func test_talk_window_keeps_the_screen_fit_in_landscape() -> void:
	InputDeviceTracker.portrait_override = 0
	var chrome := _chrome(Vector2(844.0, 390.0))
	var rect: Rect2 = (chrome.get_node("Cloud") as Control).get_global_rect()
	var fit: float = 390.0 / MessageWindowChrome.SCREEN_H
	assert_float(rect.size.x).is_equal_approx(MessageWindowChrome.WINDOW_SIZE.x * fit, 0.5)


func _chrome(screen: Vector2) -> MessageWindowChrome:
	var host: Control = auto_free(Control.new())
	host.size = screen
	add_child(host)
	var overlay: DialogueOverlay = (load(OVERLAY_SCENE) as PackedScene).instantiate()
	host.add_child(overlay)
	var chrome: MessageWindowChrome = overlay.get_node("%MessageChrome")
	chrome.size = screen
	chrome.set_window_scale(1.0)
	return chrome
