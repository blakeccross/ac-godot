class_name TestAudioMix
extends GdUnitTestSuite

## Sound lookup and voice mixing against the sound driver (`Na_VoiceSe`, `SE_SINGLETON`).


func test_hex_ids_resolve_by_number_and_without_flags() -> void:
	SeCatalog.reset()
	if not SeCatalog.has_id(&"register"):
		return
	## 0x54 is `kokoro_toguru`; 0x1050 is MONO(`register`); 0x8026 is SINGLETON(0x26).
	assert_that(SeCatalog.resolve(&"54")).is_equal(&"kokoro_toguru")
	assert_that(SeCatalog.resolve(&"1050")).is_equal(&"register")
	assert_that(SeCatalog.resolve(&"8026")).is_equal(&"26")
	## Named ids stay themselves, even when they read as hex.
	assert_that(SeCatalog.resolve(&"a")).is_equal(&"a")
	assert_that(SeCatalog.resolve(&"cursol")).is_equal(&"cursol")


func test_at_most_two_phonemes_sound_at_once() -> void:
	## `sou_voice_se_toguru`: two voice subtracks in turn.
	for i: int in 10:
		Audio.play_voice(1, i % 4)
	assert_int(Audio.voices_playing()).is_less_equal(2)


func test_menus_turn_the_music_down_and_back() -> void:
	## `mBGMPsComp_pause`: half under the pockets, silent under the tune board.
	Audio.set_music_pause(Audio.PAUSE_POCKETS)
	assert_float(Audio.music_pause_level()).is_equal(0.5)
	Audio.set_music_pause(Audio.PAUSE_TUNE_BOARD)
	assert_float(Audio.music_pause_level()).is_equal(0.0)
	Audio.set_music_pause(1.0)
	assert_float(Audio.music_pause_level()).is_equal(1.0)
	await await_millis(300)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Audio.MUSIC_BUS))).is_equal_approx(0.0, 0.01)


func test_the_hourly_chime_steps_slower_than_the_tune_board() -> void:
	## seq 248 voice headers: the board's voice 0 is 24 tatums, the chime's 0xFF is 64, at
	## 96 tatums a second.
	assert_float(Audio.MELODY_STEP_SEC).is_equal_approx(0.25, 0.0001)
	assert_float(Audio.CHIME_STEP_SEC).is_equal_approx(0.6667, 0.001)


func test_the_music_rests_around_the_hour() -> void:
	## `mBGMTime_silent_check`: XX:59:52 to XX:00:16.
	var world: GDScript = load("res://scenes/world/world.gd")
	assert_bool(world.time_signal_quiet(59, 51)).is_false()
	assert_bool(world.time_signal_quiet(59, 52)).is_true()
	assert_bool(world.time_signal_quiet(0, 15)).is_true()
	assert_bool(world.time_signal_quiet(0, 16)).is_false()


func test_far_sounds_fade_and_pan() -> void:
	## `distance2vol` / `angle2pan` from the mic.
	assert_float(SoundEmitter.volume(0.0)).is_greater(1.0)
	assert_float(SoundEmitter.volume(300.0)).is_less(SoundEmitter.volume(100.0))
	assert_float(SoundEmitter.volume(600.0)).is_equal(0.0)
	## Off the field (the Audio node itself) a one-shot plays flat.
	assert_vector(Audio.field_placement(Audio)).is_equal(Vector2(1.0, 0.0))
