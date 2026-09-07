class_name TestSe
extends GdUnitTestSuite


func before_test() -> void:
	SeCatalog.reset()
	VoiceCatalog.reset()


func after_test() -> void:
	SeCatalog.reset()
	VoiceCatalog.reset()


func test_unknown_se_is_silence() -> void:
	assert_object(SeCatalog.stream_for(&"")).is_null()
	assert_object(SeCatalog.stream_for(&"definitely_not_an_se")).is_null()
	assert_bool(SeCatalog.has_id(&"definitely_not_an_se")).is_false()


func test_play_se_noops_when_missing() -> void:
	Audio.play_se(&"definitely_not_an_se")
	assert_bool(true).is_true()


func test_registered_se_plays() -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.data = PackedByteArray([0, 0, 0, 0])
	SeCatalog.register_stream(&"cursol", wav)
	Audio.play_se(&"cursol")
	assert_bool(SeCatalog.has_id(&"cursol")).is_true()


func test_unknown_voice_is_silence() -> void:
	assert_object(VoiceCatalog.stream_for(1, 0x7F)).is_null()


func test_play_voice_noops_when_missing() -> void:
	Audio.play_voice(1, 0x7F)
	assert_bool(true).is_true()


func test_registered_voice_plays() -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.data = PackedByteArray([0, 0, 0, 0])
	VoiceCatalog.register_stream(1, 0x01, wav)
	Audio.play_voice(1, 0x01, 1.0, -3.7)
	assert_object(VoiceCatalog.stream_for(1, 0x01)).is_not_null()
