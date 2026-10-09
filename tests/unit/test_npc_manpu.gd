class_name TestNpcManpu
extends GdUnitTestSuite


func test_seated_codes_map_to_d1_clips() -> void:
	assert_str(NpcManpu.clip_for("24")).is_equal("npc_1_smile_d1")
	assert_str(NpcManpu.clip_for("smile_d1")).is_equal("npc_1_smile_d1")
	assert_str(NpcManpu.clip_for("25")).is_equal("npc_1_gaaan_d1")
	assert_str(NpcManpu.clip_for("reset_sit")).is_equal("npc_1_sitdown_wait_d1")


func test_emote_guess_matches_reaction_family() -> void:
	assert_int(NpcManpu.emote_for("smile_d1")).is_equal(NpcFaceAnim.Emote.LAUGH)
	assert_int(NpcManpu.emote_for("gaaan_d1")).is_equal(NpcFaceAnim.Emote.SURPRISE)
	assert_int(NpcManpu.emote_for("musu_d1")).is_equal(NpcFaceAnim.Emote.ANGRY)
	assert_int(NpcManpu.emote_for("komari_d1")).is_equal(NpcFaceAnim.Emote.SAD)
	assert_int(NpcManpu.emote_for("hate1")).is_equal(NpcFaceAnim.Emote.NORMAL)
	assert_int(NpcManpu.emote_for("reset_sit")).is_equal(NpcFaceAnim.Emote.NORMAL)
	assert_int(NpcManpu.mouth_hold_for("smile_d1")).is_equal(NpcFaceAnim.MOUTH_OPEN)
	assert_int(NpcManpu.mouth_hold_for("gaaan_d1")).is_equal(NpcFaceAnim.MOUTH_ANGRY_OPEN)
	assert_int(NpcManpu.mouth_hold_for("musu_d1")).is_equal(NpcFaceAnim.MOUTH_ANGRY_SHUT)
	assert_str(String(NpcManpu.feel_for("smile1"))).is_equal("warau")
	assert_str(String(NpcManpu.feel_for("gaaan_d1"))).is_equal("shock")
	assert_str(String(NpcManpu.feel_for("hirameki_d1"))).is_equal("hirameki")
	assert_str(String(NpcManpu.feel_for("ha_d1"))).is_equal("ha")
	assert_str(String(NpcManpu.feel_for("reset"))).is_equal("")


func test_each_reaction_draws_its_own_clips_glyph() -> void:
	## `npc_1_*` `feel_effect`: only the smiling clips laugh.
	assert_str(String(NpcManpu.feel_for("smile1"))).is_equal("warau")
	assert_str(String(NpcManpu.feel_for("niko1"))).is_equal("")
	assert_str(String(NpcManpu.feel_for("lovelove1"))).is_equal("")
	assert_str(String(NpcManpu.feel_for("hate1"))).is_equal("gimonhu")
	assert_str(String(NpcManpu.feel_for("a_r1"))).is_equal("kantanhu")
	assert_str(String(NpcManpu.feel_for("aseru1"))).is_equal("ase")
	assert_str(String(NpcManpu.feel_for("gaaan_d1"))).is_equal("shock")
	assert_str(String(NpcManpu.feel_for("ha_e1"))).is_equal("ha")


func test_question_mark_pops_then_fades() -> void:
	var glyphs := NpcFeelGlyphs.new()
	add_child(glyphs)
	glyphs.play(&"gimonhu")
	assert_str(String(glyphs._kind)).is_equal("gimonhu")
	glyphs._frame = float(NpcFeelGlyphs.POP_LIFE)
	glyphs._tick_pop()
	assert_str(String(glyphs._kind)).is_equal("")
	glyphs.free()
