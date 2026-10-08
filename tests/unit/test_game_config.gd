extends GdUnitTestSuite

## K.K.'s options (`aNPS2_setup_sound_option` / `_voice_option` / `_yure_option`) and the
## rumble table (`m_player_vibration`).

const PATH := "user://test_game_config.cfg"


func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	GameConfig.reset(PATH)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	GameConfig.reset(PATH)


func _mono_on() -> bool:
	var bus: int = AudioServer.get_bus_index(&"Master")
	for i: int in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).resource_name == GameConfig.MONO_EFFECT:
			return true
	return false


func test_settings_are_kept_between_runs() -> void:
	GameConfig.set_sound(GameConfig.Sound.MONO)
	GameConfig.set_voice(2)
	GameConfig.set_rumble(false)
	GameConfig.sound_mode = GameConfig.Sound.STEREO
	GameConfig.voice_mode = DialogueVoice.Mode.ANIMALESE
	GameConfig.rumble_on = true
	GameConfig._loaded = false
	GameConfig.ensure_loaded()
	assert_int(GameConfig.sound_mode).is_equal(GameConfig.Sound.MONO)
	assert_int(GameConfig.voice_mode).is_equal(DialogueVoice.Mode.SILENT)
	assert_bool(GameConfig.rumble_on).is_false()


func test_mono_folds_the_master_bus_once() -> void:
	GameConfig.set_sound(GameConfig.Sound.MONO)
	GameConfig.set_sound(GameConfig.Sound.MONO)
	assert_bool(_mono_on()).is_true()
	GameConfig.set_sound(GameConfig.Sound.HEADPHONES)
	assert_bool(_mono_on()).is_false()


func test_the_voice_setting_replaces_animalese_only() -> void:
	GameConfig.set_voice(1)
	assert_int(GameConfig.voice_for(DialogueVoice.Mode.ANIMALESE)).is_equal(DialogueVoice.Mode.CLICK)
	GameConfig.set_voice(2)
	assert_int(GameConfig.voice_for(DialogueVoice.Mode.ANIMALESE)).is_equal(DialogueVoice.Mode.SILENT)
	assert_int(GameConfig.voice_for(DialogueVoice.Mode.CLICK)).is_equal(DialogueVoice.Mode.CLICK)


func test_rumble_off_stays_still() -> void:
	GameConfig.set_rumble(false)
	assert_bool(GameConfig.rumble(GameConfig.AXE_CUT)).is_false()
	GameConfig.set_rumble(true)
	assert_bool(GameConfig.rumble(GameConfig.AXE_CUT)).is_true()


func test_rumble_shapes_follow_the_player_table() -> void:
	## `Axe_cut`: 100, KI_GA_TAORERU, 3 + 36 frames.
	var cut: Vector2 = GameConfig.rumble_shape(GameConfig.AXE_CUT)
	assert_float(cut.y).is_equal_approx(39.0 / DecompTime.FRAME_HZ, 0.0001)
	## A hard reflect is stronger than a soft one.
	assert_float(GameConfig.rumble_shape(GameConfig.REFLECT_HARD).x).is_greater(GameConfig.rumble_shape(GameConfig.REFLECT_SOFT).x)


func _run_to_choice(runner: DialogueRunner) -> void:
	var guard := 0
	while not runner.waiting_choice and not runner.done and guard < 60:
		guard += 1
		runner.advance()


func test_kk_sets_sound_then_voice_then_rumble() -> void:
	if DialogueCatalog.conversation(&"msg_5106") == null:
		return
	var roster := PlayerRoster.new()
	roster.slots[0] = {"player_name": "Ann"}
	var talk := PlayerSelectTalk.new(roster, "Pine")
	talk.context = DialogueContext.new()
	var runner := DialogueRunner.new()
	runner.talk_manager = talk
	talk.prepare()
	runner.start(DialogueCatalog.conversation(&"msg_5106"), talk.context)
	_run_to_choice(runner)
	runner.choose(1)  ## "Before I go..."
	_run_to_choice(runner)
	runner.choose(0)  ## Sound settings
	_run_to_choice(runner)
	## The pick comes before "OK, all done!" (`OPENCHOICE` mid-message).
	assert_str(str(runner.choices[1]["text"])).is_equal("Mono")
	runner.choose(1)
	assert_int(GameConfig.sound_mode).is_equal(GameConfig.Sound.MONO)
	assert_str(talk.context.substitute(str(runner.current_record().get("text", "")))).contains("Mono")
	_run_to_choice(runner)
	assert_int(talk.current_msg).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.VOICE))
	runner.choose(1)  ## Bebebese
	assert_int(GameConfig.voice_mode).is_equal(DialogueVoice.Mode.CLICK)
	_run_to_choice(runner)
	runner.choose(0)  ## That's fine!
	assert_int(GameConfig.voice_mode).is_equal(DialogueVoice.Mode.CLICK)
	_run_to_choice(runner)
	assert_int(talk.current_msg).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE))
	runner.choose(1)
	_run_to_choice(runner)
	runner.choose(1)  ## Rumble settings
	_run_to_choice(runner)
	runner.choose(1)  ## Rumble: OFF
	assert_bool(GameConfig.rumble_on).is_false()
	_run_to_choice(runner)
	assert_int(talk.current_msg).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE))
