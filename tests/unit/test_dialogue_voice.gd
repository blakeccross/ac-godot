class_name TestDialogueVoice
extends GdUnitTestSuite


func test_looks_sound_spec_table() -> void:
	assert_that(DialogueVoice.sound_spec_for_looks(VillagerPersonality.Looks.NORMAL)).is_equal(4)
	assert_that(DialogueVoice.sound_spec_for_looks(VillagerPersonality.Looks.PEPPY)).is_equal(4)
	assert_that(DialogueVoice.sound_spec_for_looks(VillagerPersonality.Looks.LAZY)).is_equal(2)
	assert_that(DialogueVoice.sound_spec_for_looks(VillagerPersonality.Looks.JOCK)).is_equal(2)
	assert_that(DialogueVoice.sound_spec_for_looks(VillagerPersonality.Looks.CRANKY)).is_equal(3)
	assert_that(DialogueVoice.sound_spec_for_looks(VillagerPersonality.Looks.SNOOTY)).is_equal(4)


func test_voice_seq_folders() -> void:
	assert_that(DialogueVoice.voice_seq_for_spec(2)).is_equal(1)
	assert_that(DialogueVoice.voice_seq_for_spec(3)).is_equal(2)
	assert_that(DialogueVoice.voice_seq_for_spec(4)).is_equal(3)
	assert_that(DialogueVoice.voice_seq_for_spec(7)).is_equal(1)
	assert_that(DialogueVoice.voice_seq_for_spec(8)).is_equal(3)
	assert_that(DialogueVoice.voice_seq_for_spec(9)).is_equal(1)


func test_spec_pitch_table() -> void:
	assert_that(float(DialogueVoice.SPEC_PITCH[2])).is_equal(1.0)
	assert_that(float(DialogueVoice.SPEC_PITCH[7])).is_equal(1.3)
	assert_that(float(DialogueVoice.SPEC_PITCH[8])).is_equal(0.75)
	assert_that(float(DialogueVoice.SPEC_PITCH[9])).is_equal(0.65)


func test_letter_maps_to_phoneme() -> void:
	assert_that(DialogueVoice.raw_voice_code("A")).is_equal(0x5D)
	assert_that(DialogueVoice.raw_voice_code("a")).is_equal(0x5D)
	assert_that(DialogueVoice.phoneme_for_char("A")).is_equal(0x01)
	assert_that(DialogueVoice.phoneme_for_char("E")).is_equal(0x14)
	assert_that(DialogueVoice.phoneme_for_char(" ")).is_equal(-1)
	assert_that(DialogueVoice.phoneme_for_char(".")).is_equal(-1)


func test_tanboin_digraph_hint() -> void:
	assert_that(DialogueVoice.tanboin(0x5F, 0x65)).is_equal(0x23)
	assert_that(DialogueVoice.tanboin(0x5F, 0x5D)).is_equal(0x18)


func test_chouboin_long_vowel() -> void:
	assert_that(DialogueVoice.chouboin(0x5D, 0x5E)).is_equal(0x02)
	assert_that(DialogueVoice.chouboin(0x65, 0x5E)).is_equal(0x15)


func test_connect_digraphs() -> void:
	assert_that(DialogueVoice.connect_check(0x5D, 0x65, 0xFF)).is_equal(0x0F) # Ae
	assert_that(DialogueVoice.connect_check(0x5D, 0x68, 0xFF)).is_equal(0x02) # Ah
	assert_that(DialogueVoice.connect_check(0x74, 0x61, 0xFF)).is_equal(0x74) # unchanged T
	assert_that(DialogueVoice.connect_check(0x6B, 0x73, 0xFF)).is_equal(0x06) # Ks


func test_mood_to_status() -> void:
	assert_that(DialogueVoice.status_for_mood(VillagerState.Mood.ANGRY)).is_equal(DialogueVoice.Status.ANGRY)
	assert_that(DialogueVoice.status_for_mood(VillagerState.Mood.SAD)).is_equal(DialogueVoice.Status.SAD)
	assert_that(DialogueVoice.status_for_mood(VillagerState.Mood.HAPPY)).is_equal(DialogueVoice.Status.FUN)
	assert_that(DialogueVoice.status_for_mood(VillagerState.Mood.SLEEPY)).is_equal(DialogueVoice.Status.SLEEPY)


func test_silent_mode_skips() -> void:
	assert_bool(DialogueVoice.utter("A", DialogueVoice.Mode.SILENT, 2)).is_false()


func test_session_question_mark_bumps_pitch() -> void:
	var voice := DialogueVoice.new()
	voice.configure(DialogueVoice.Mode.ANIMALESE, 4)
	voice.rng.seed = 1
	voice.utter_glyph("?")
	assert_that(voice._pitch_bump).is_equal(1.13)


func test_angry_emotion_modulates() -> void:
	var voice := DialogueVoice.new()
	voice.configure(DialogueVoice.Mode.ANIMALESE, 4, DialogueVoice.Status.ANGRY)
	voice.rng.seed = 42
	var mods: Vector2 = voice._angry_mods()
	assert_bool(mods.x > 0.0).is_true()
	assert_bool(mods.y > 0.0).is_true()
