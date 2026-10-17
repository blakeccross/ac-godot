class_name TestWeatherFx
extends GdUnitTestSuite

## `weather_fx.tscn`: the weather turns the right `GPUParticles3D` emitters on, at the share
## its intensity calls for.


func _fx() -> Node3D:
	var fx: Node3D = auto_free(load("res://scenes/world/weather_fx.tscn").instantiate()) as Node3D
	add_child(fx)
	return fx


func _weather(kind: StringName, intensity: Weather.Intensity) -> void:
	Game.town.weather = kind
	Game.town.weather_intensity = intensity
	Game.weather_changed.emit(kind)


func after_test() -> void:
	_weather(&"clear", Weather.Intensity.NONE)


func test_heavy_rain_runs_the_rain_and_its_splashes_only() -> void:
	var fx := _fx()
	_weather(&"rain", Weather.Intensity.HEAVY)
	var rain := fx.get_node("Rain") as GPUParticles3D
	var splash := fx.get_node("Splash") as GPUParticles3D
	assert_bool(rain.emitting).is_true()
	assert_bool(splash.emitting).is_true()
	assert_float(rain.amount_ratio).is_equal(1.0)
	assert_bool((fx.get_node("Snow") as GPUParticles3D).emitting).is_false()
	assert_bool((fx.get_node("Petals") as GPUParticles3D).emitting).is_false()
	## 3 drops a frame at 60 Hz, each living 10 ticks.
	assert_float(rain.amount / rain.lifetime).is_equal_approx(180.0, 1.0)


func test_light_rain_and_snow_run_at_their_share() -> void:
	var fx := _fx()
	_weather(&"rain", Weather.Intensity.LIGHT)
	assert_float((fx.get_node("Rain") as GPUParticles3D).amount_ratio).is_equal_approx(1.0 / 3.0, 0.001)
	_weather(&"snow", Weather.Intensity.LIGHT)
	var snow := fx.get_node("Snow") as GPUParticles3D
	assert_bool(snow.emitting).is_true()
	assert_float(snow.amount_ratio).is_equal(0.25)
	assert_bool((fx.get_node("Rain") as GPUParticles3D).emitting).is_false()
	## Heavy snow: a flake every other frame over its 280-tick life.
	assert_float(snow.amount / snow.lifetime).is_equal_approx(30.0, 0.5)


func test_clear_weather_stops_every_emitter() -> void:
	var fx := _fx()
	_weather(&"sakura", Weather.Intensity.NORMAL)
	assert_bool((fx.get_node("Petals") as GPUParticles3D).emitting).is_true()
	_weather(&"clear", Weather.Intensity.NONE)
	for name: String in ["Rain", "Splash", "Snow", "Petals"]:
		assert_bool((fx.get_node(name) as GPUParticles3D).emitting).override_failure_message(name).is_false()


func test_spawn_box_follows_the_follow_camera_lookat() -> void:
	## `Camera2_getCenterPos_p`, not the player's look marker.
	var fx := _fx()
	var cam := FollowCamera.new()
	auto_free(cam)
	add_child(cam)
	cam.current = true
	cam.add_to_group(FollowCamera.GROUP)
	var center := Vector3(12.0, 2.0, -8.0)
	cam._look_current = center
	cam._has_look = true
	cam.global_position = center + FollowCamera.DEFAULT_OFFSET
	assert_vector(fx.call("_center") as Vector3).is_equal_approx(center, Vector3.ONE * 0.001)


func test_splash_points_sit_in_the_rain_box() -> void:
	var fx := _fx()
	var process := (fx.get_node("Splash") as GPUParticles3D).process_material as ParticleProcessMaterial
	assert_int(process.emission_point_count).is_equal(fx.get("SPLASH_POINTS"))
	var img: Image = process.emission_point_texture.get_image()
	for i: int in img.get_width():
		var p: Color = img.get_pixel(i, 0)
		assert_float(absf(p.r)).is_less_equal(fx.get("RAIN_X") + 0.001)
		assert_float(p.b).is_between(-fx.get("RAIN_Z_BACK") - 0.001, fx.get("RAIN_Z_FRONT") + 0.001)
