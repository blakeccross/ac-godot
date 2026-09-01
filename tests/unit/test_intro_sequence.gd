class_name TestIntroSequence
extends GdUnitTestSuite

## Rover train face table + identity handoff into Game.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	DialogueCatalog.reset()


func after_test() -> void:
	DialogueCatalog.reset()
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_face_table_male_non_random() -> void:
	## flags = (q1<<3)|(q2<<2)|(q3<<1)|1 → index = flags >> 1
	var expected: Array[int] = IntroSequence.MALE_FACES
	for index: int in 8:
		var flags: int = (index << 1) | IntroSequence.FLAG_MONEY_SPARSE
		assert_int(IntroSequence.resolve_face(IntroSequence.GENDER_MALE, flags)).is_equal(
			expected[index]
		)


func test_face_table_female_non_random() -> void:
	var expected: Array[int] = IntroSequence.FEMALE_FACES
	for index: int in 8:
		var flags: int = (index << 1) | IntroSequence.FLAG_MONEY_SPARSE
		assert_int(IntroSequence.resolve_face(IntroSequence.GENDER_FEMALE, flags)).is_equal(
			expected[index]
		)


func test_money_plenty_picks_random_face() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	## Bit 0 clear → random, ignoring other bits.
	var flags: int = IntroSequence.FLAG_Q1 | IntroSequence.FLAG_Q2 | IntroSequence.FLAG_Q3
	var face: int = IntroSequence.resolve_face(IntroSequence.GENDER_MALE, flags, rng)
	assert_int(face).is_greater_equal(0)
	assert_int(face).is_less(IntroSequence.FACE_TYPE_NUM)
	## Deterministic for this seed.
	rng.seed = 42
	assert_int(IntroSequence.resolve_face(IntroSequence.GENDER_MALE, flags, rng)).is_equal(face)


func test_guide_answer_flag_combos() -> void:
	## AAA + sparse money → index 7; BBB + sparse → index 0.
	var aaa: int = (
		IntroSequence.FLAG_Q1
		| IntroSequence.FLAG_Q2
		| IntroSequence.FLAG_Q3
		| IntroSequence.FLAG_MONEY_SPARSE
	)
	assert_int(aaa >> 1).is_equal(7)
	assert_int(
		IntroSequence.resolve_face(IntroSequence.GENDER_MALE, aaa)
	).is_equal(IntroSequence.MALE_FACES[7])
	var bbb: int = IntroSequence.FLAG_MONEY_SPARSE
	assert_int(bbb >> 1).is_equal(0)
	assert_int(
		IntroSequence.resolve_face(IntroSequence.GENDER_FEMALE, bbb)
	).is_equal(IntroSequence.FEMALE_FACES[0])


func test_name_and_town_clamped() -> void:
	assert_str(IntroSequence.clamp_name("  Blake  ")).is_equal("Blake")
	assert_str(IntroSequence.clamp_name("ABCDEFGHIJ")).is_equal("ABCDEFGH")
	assert_str(IntroSequence.clamp_name("   ")).is_equal("")
	assert_str(IntroSequence.clamp_town("Villagename")).is_equal("Villagen")


func test_identity_applied_to_game() -> void:
	var intro := IntroSequence.new()
	intro.set_player_name("Blake")
	intro.set_town_name("Cedar")
	intro.set_gender("female")
	intro.answer_flags = (
		IntroSequence.FLAG_Q1 | IntroSequence.FLAG_MONEY_SPARSE
	)
	intro.complete()
	var identity: Dictionary = intro.identity()
	assert_str(str(identity["player_name"])).is_equal("Blake")
	assert_str(str(identity["town_name"])).is_equal("Cedar")
	assert_str(str(identity["player_gender"])).is_equal("female")
	assert_int(int(identity["player_face"])).is_equal(IntroSequence.FEMALE_FACES[4])
	Game.reset_session()
	Game._apply_identity(identity)
	assert_str(Game.player_name).is_equal("Blake")
	assert_str(Game.town_name).is_equal("Cedar")
	assert_that(Game.player_gender).is_equal(IntroSequence.GENDER_FEMALE)
	assert_int(Game.player_face).is_equal(IntroSequence.FEMALE_FACES[4])


func test_rover_intro_dialogue_loads() -> void:
	var data: DialogueData = DialogueCatalog.conversation(&"rover_intro")
	assert_that(data).is_not_null()
	assert_bool(data.has_node(&"greet")).is_true()
	assert_bool(data.has_node(&"finish")).is_true()


func test_prompt_events_pause_runner() -> void:
	var data: DialogueData = DialogueData.from_dict(
		{
			"id": "prompt_test",
			"start": "ask",
			"nodes":
			{
				"ask": {"type": "event", "events": [{"op": "prompt_name"}], "next": "done"},
				"done": {"type": "line", "text": "Hi {player}."},
			},
		}
	)
	var ctx := DialogueContext.new()
	ctx.player_name = "Sam"
	var runner := DialogueRunner.new()
	runner.start(data, ctx)
	assert_bool(runner.waiting_prompt).is_true()
	assert_bool(runner.done).is_false()
	ctx.player_name = "Sam"
	runner.resume_after_prompt()
	assert_bool(runner.waiting_prompt).is_false()
	assert_str(runner.line).is_equal("Hi Sam.")


func test_save_roundtrip_includes_identity() -> void:
	Game.player_name = "Blake"
	Game.town_name = "Cedar"
	Game.player_gender = IntroSequence.GENDER_FEMALE
	Game.player_face = 3
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_str(Game.player_name).is_equal("Blake")
	assert_str(Game.town_name).is_equal("Cedar")
	assert_that(Game.player_gender).is_equal(IntroSequence.GENDER_FEMALE)
	assert_int(Game.player_face).is_equal(3)
