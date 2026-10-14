extends GdUnitTestSuite

## `mBGM_KATEGORIE_FANFARE`: jingles over the music (`Audio.push_fanfare` / `pop_fanfare`).


func after_test() -> void:
	Audio.pop_fanfare(Audio.fanfare_id())
	Audio.stop_bgm()


func test_a_jingle_stops_the_music_and_hands_it_back() -> void:
	var jingle: StringName = BgmCatalog.id_for_num(0x28)
	if jingle == &"" or BgmCatalog.stream_for(jingle) == null or BgmCatalog.stream_for(&"field_00") == null:
		return
	Audio.play_bgm(&"field_00")
	Audio.push_fanfare(jingle)
	assert_str(String(Audio.fanfare_id())).is_equal(String(jingle))
	assert_str(String(Audio.current_id)).is_equal("")
	## Music asked for meanwhile waits for the jingle to come off.
	Audio.play_bgm(&"field_01")
	assert_str(String(Audio.current_id)).is_equal("")
	## Only the jingle that is up can be taken off.
	Audio.pop_fanfare(&"all_fish")
	assert_str(String(Audio.fanfare_id())).is_equal(String(jingle))
	Audio.pop_fanfare(jingle)
	assert_str(String(Audio.fanfare_id())).is_equal("")
	assert_str(String(Audio.current_id)).is_equal("field_01")


func test_one_jingle_replaces_another() -> void:
	var catch_jingle: StringName = BgmCatalog.id_for_num(0x28)
	var complete: StringName = BgmCatalog.id_for_num(0x4B)
	if BgmCatalog.stream_for(catch_jingle) == null or BgmCatalog.stream_for(complete) == null:
		return
	Audio.play_bgm(&"field_00")
	Audio.push_fanfare(catch_jingle)
	Audio.pop_fanfare(catch_jingle)
	Audio.push_fanfare(complete)
	assert_str(String(Audio.fanfare_id())).is_equal(String(complete))
	Audio.pop_fanfare(complete)
	assert_str(String(Audio.current_id)).is_equal("field_00")
