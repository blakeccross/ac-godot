class_name TestBgm
extends GdUnitTestSuite


func before_test() -> void:
	BgmCatalog.reset()
	Audio.fade_sec = 0.0
	Audio.stop_bgm()


func after_test() -> void:
	Audio.stop_bgm()
	Audio.fade_sec = Audio.FADE_SEC
	BgmCatalog.reset()


func test_hour_maps_to_field_id() -> void:
	assert_that(BgmCatalog.field_id(0)).is_equal(&"field_00")
	assert_that(BgmCatalog.field_id(8)).is_equal(&"field_08")
	assert_that(BgmCatalog.field_id(14)).is_equal(&"field_14")
	assert_that(BgmCatalog.field_id(23)).is_equal(&"field_23")
	assert_that(BgmCatalog.field_id(24)).is_equal(&"field_00")


func test_rain_replaces_hourly_field() -> void:
	assert_that(BgmCatalog.outdoor_id(14, &"clear")).is_equal(&"field_14")
	assert_that(BgmCatalog.outdoor_id(14, &"rain")).is_equal(&"rain")
	assert_that(BgmCatalog.outdoor_id(8, &"snow")).is_equal(&"field_08")


func test_shop_room_has_bgm_houses_are_silent() -> void:
	assert_that(BgmCatalog.room_id(Room.Kind.SHOP)).is_equal(&"shop0")
	assert_that(BgmCatalog.room_id(Room.Kind.NEEDLEWORK)).is_equal(&"shop0")
	assert_that(BgmCatalog.room_id(Room.Kind.PLAYER)).is_equal(&"")
	assert_that(BgmCatalog.room_id(Room.Kind.NPC)).is_equal(&"")


func test_unknown_ids_are_silence() -> void:
	assert_object(BgmCatalog.stream_for(&"")).is_null()
	assert_object(BgmCatalog.stream_for(&"definitely_not_a_track")).is_null()
	assert_bool(BgmCatalog.has_id(&"definitely_not_a_track")).is_false()


func test_play_bgm_noops_when_stream_missing() -> void:
	Audio.play_bgm(&"definitely_not_a_track")
	assert_that(Audio.current_id).is_equal(&"")
	Audio.play_bgm(&"")
	assert_that(Audio.current_id).is_equal(&"")


func test_registered_stream_plays() -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.data = PackedByteArray([0, 0, 0, 0])
	BgmCatalog.register_stream(&"title", wav)
	Audio.play_bgm(&"title")
	assert_that(Audio.current_id).is_equal(&"title")
	Audio.stop_bgm()
	assert_that(Audio.current_id).is_equal(&"")
