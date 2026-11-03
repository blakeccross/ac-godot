class_name TestGyroidVoices
extends GdUnitTestSuite

## The gyroids' rhythm voices (`rhythm.c`, seq 246) on the room's beat clock.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func test_streams_are_named_by_gyroid_and_beat_type() -> void:
	assert_that(GyroidVoices.stream_id(0, false)).is_equal(&"gyroid_000")
	assert_that(GyroidVoices.stream_id(126, true)).is_equal(&"gyroid_126_swing")


func test_the_loop_is_sixteen_beats_of_eight_seconds() -> void:
	assert_float(GyroidVoices.loop_position(0.0)).is_equal_approx(0.0, 0.0001)
	assert_float(GyroidVoices.loop_position(4.0)).is_equal_approx(2.0, 0.0001)
	assert_float(GyroidVoices.loop_position(16.0)).is_equal_approx(0.0, 0.0001)
	assert_float(GyroidVoices.loop_position(17.5)).is_equal_approx(0.75, 0.0001)


func test_tempo_speeds_the_render_up_or_down() -> void:
	assert_float(GyroidVoices.playback_rate(120.0)).is_equal_approx(1.0, 0.0001)
	assert_float(GyroidVoices.playback_rate(90.0)).is_equal_approx(0.75, 0.0001)
	assert_float(GyroidVoices.playback_rate(500.0)).is_equal(GyroidVoices.PITCH_MAX)
	assert_float(GyroidVoices.playback_rate(10.0)).is_equal(GyroidVoices.PITCH_MIN)


func test_silent_music_keeps_the_idle_tempo() -> void:
	var info: Dictionary = GyroidVoices.rhythm_for(&"no_such_track")
	assert_float(float(info["bpm"])).is_equal(GyroidVoices.REF_BPM)
	assert_bool(bool(info["swing"])).is_false()


func test_pan_steps_share_the_gyroid_bus_at_the_centre() -> void:
	assert_str(GyroidVoices.pan_bus(0.0)).is_equal(GyroidVoices.BUS)
	assert_str(GyroidVoices.pan_bus(-1.0)).is_equal("Gyroid_pan0")
	assert_str(GyroidVoices.pan_bus(1.0)).is_equal("Gyroid_pan8")
	assert_int(AudioServer.get_bus_index("Gyroid_pan0")).is_not_equal(-1)
	assert_str(AudioServer.get_bus_send(AudioServer.get_bus_index("Gyroid_pan0"))).is_equal(GyroidVoices.BUS)


func test_only_switched_on_gyroids_in_a_house_sound() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	room.placements.clear()
	var session := IndoorSession.new()
	session.bind(room)
	var gyroid: FurnitureData = ItemCatalog.get_item(FurnitureCatalog.item_id(GyroidRhythm.FIRST_FTR)) as FurnitureData
	if gyroid == null:
		return
	var entry: FurniturePlacement = session.place(gyroid, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	assert_that(entry).is_not_null()
	entry.on = false
	assert_int(GyroidVoices.sounding(session).size()).is_equal(0)
	entry.on = true
	var heard: Array = GyroidVoices.sounding(session)
	assert_int(heard.size()).is_equal(1)
	assert_that((heard[0] as Array)[0]).is_equal(entry.id)
	assert_int(int((heard[0] as Array)[1])).is_between(0, GyroidRhythm.COUNT - 1)


func test_tempo_is_undone_by_a_pitch_shifter_on_the_gyroid_bus() -> void:
	var voices: GyroidVoices = auto_free(GyroidVoices.new())
	add_child(voices)
	var bus: int = AudioServer.get_bus_index(GyroidVoices.BUS)
	assert_int(bus).is_not_equal(-1)
	voices._set_pitch_back(1.5)
	assert_bool(AudioServer.is_bus_effect_enabled(bus, 0)).is_true()
	assert_float((AudioServer.get_bus_effect(bus, 0) as AudioEffectPitchShift).pitch_scale).is_equal_approx(1.0 / 1.5, 0.0001)
	voices._set_pitch_back(1.0)
	assert_bool(AudioServer.is_bus_effect_enabled(bus, 0)).is_false()


func test_rendered_voices_are_loaded_when_the_catalog_has_them() -> void:
	if not SeCatalog.has_id(&"gyroid_000"):
		return
	assert_that(SeCatalog.stream_for(&"gyroid_000")).is_not_null()
	assert_that(SeCatalog.stream_for(&"gyroid_126_swing")).is_not_null()
