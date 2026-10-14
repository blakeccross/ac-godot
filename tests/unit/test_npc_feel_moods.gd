class_name TestNpcFeelMoods
extends GdUnitTestSuite

## The clip-long villager feel effects (`NpcFeelMoods`) and the reaction clip that carries
## them on (`NpcManpu.follow_clip`).

var _host: Node3D


func before_test() -> void:
	_host = auto_free(Node3D.new())
	add_child(_host)


func _moods(kind: StringName, view_diff: float = 0.0) -> NpcFeelMoods:
	return NpcFeelMoods.new(_host, kind, 0.0, view_diff, 7)


func _run(m: NpcFeelMoods, ticks: int) -> void:
	for _i: int in ticks:
		m.tick()


func test_each_reaction_family_names_its_effect() -> void:
	var map := {
		"punpun1": "pun", "punpun_r1": "pun", "happy1": "siawase", "happy_f1": "siawase",
		"muuuuu1": "kangaeru", "warudakumi1": "takurami", "goukyu1": "naku",
		"buruburu1": "buruburu", "hyuuu1": "kaze", "hyuuu_r1": "kaze", "otikomu1": "otikomi",
		"neboke1": "neboke",
	}
	for clip: String in map:
		assert_str(String(NpcManpu.feel_for(clip))).append_failure_message(clip).is_equal(map[clip])
		assert_bool(NpcFeelMoods.KINDS.has(NpcManpu.feel_for(clip))).is_true()


func test_a_reaction_settles_into_its_second_clip() -> void:
	assert_str(NpcManpu.follow_clip("npc_1_punpun1")).is_equal("npc_1_punpun2")
	assert_str(NpcManpu.follow_clip("npc_1_happy_f1")).is_equal("npc_1_happy_f2")
	assert_str(NpcManpu.follow_clip("npc_1_a2_r1")).is_equal("npc_1_a_r2")
	## The quiet faces hold their first clip.
	assert_str(NpcManpu.follow_clip("npc_1_niko1")).is_equal("npc_1_niko1")
	assert_str(NpcManpu.follow_clip("npc_1_musu_r1")).is_equal("npc_1_musu_r1")
	assert_str(NpcManpu.follow_clip("npc_1_keirei1")).is_equal("npc_1_keirei1")


func test_anger_puffs_steam_every_loop_while_the_clip_holds() -> void:
	var m := _moods(&"pun")
	## 24 ticks to settle, then a puff 8 ticks into each 44-tick loop.
	_run(m, 31)
	assert_int(m.parts.size()).is_equal(0)
	_run(m, 1)
	assert_int(m.parts.size()).is_equal(2)
	assert_array(m.trg_se).contains([&"pun_yuge"])
	_run(m, 200)
	assert_bool(m.alive).is_true()
	m.release()
	assert_bool(m.alive).is_false()


func test_the_happy_glow_fades_out_after_the_clip() -> void:
	var m := _moods(&"siawase")
	_run(m, 60)
	assert_str(String(m.ongen)).is_equal("lev_e")
	assert_int(m.parts.size()).is_greater(1)  ## the glow and its petals
	m.release()
	assert_int(m.state).is_equal(NpcFeelMoods.State.FINISHED)
	_run(m, 71)
	assert_bool(m.alive).is_true()
	_run(m, 1)
	assert_bool(m.alive).is_false()
	## The petals already out drift on to the end of their lives.
	_run(m, 200)
	assert_int(m.parts.size()).is_equal(0)


func test_thinking_gears_hum_and_fade_over_seven_ticks() -> void:
	var m := _moods(&"kangaeru")
	_run(m, 50)
	assert_str(String(m.ongen)).is_equal("lev_58")
	m.release()
	_run(m, 1)
	assert_str(String(m.ongen)).is_equal("")
	_run(m, 6)
	assert_bool(m.alive).is_false()


func test_a_scheming_grin_plays_out_whatever_the_clip_does() -> void:
	var m := _moods(&"takurami")
	_run(m, 1)
	assert_array(m.trg_se).contains([&"117"])
	_run(m, 10)
	assert_int(m.parts.size()).is_equal(2)  ## the shadow and its sparkle
	m.release()
	assert_bool(m.alive).is_true()
	_run(m, 50)
	assert_bool(m.alive).is_false()


func test_tears_alternate_sides() -> void:
	var m := _moods(&"naku")
	_run(m, 8)
	assert_str(String(m.ongen)).is_equal("lev_2e")
	assert_int(m.parts.size()).is_equal(4)
	var xs: Array[float] = []
	_run(m, 6)
	for p: NpcFeelMoods.Part in m.parts.slice(0, 2):
		xs.append(NpcFeelMoods._rot_y(Vector3(p.data["local"]), 0.0).x)
	assert_float(xs[0] * xs[1]).is_less(0.0)


func test_wind_blows_a_leaf_across() -> void:
	var m := _moods(&"kaze")
	_run(m, 1)
	assert_array(m.trg_se).contains([&"kaze"])
	_run(m, 36)
	assert_int(m.parts.size()).is_equal(2)
	_run(m, 70)
	assert_bool(m.alive).is_false()


func test_the_gloom_cloud_wobbles_ever_more_gently() -> void:
	var m := _moods(&"otikomi")
	_run(m, 5)
	var early: float = float(m._es["wobble"])
	_run(m, 200)
	assert_float(float(m._es["wobble"])).is_less(early)
	assert_str(String(m.ongen)).is_equal("lev_59")
	m.release()
	_run(m, 10)
	assert_bool(m.alive).is_false()


func test_a_sleepy_villager_yawns_then_breathes_zs() -> void:
	var m := _moods(&"neboke")
	_run(m, 17)
	assert_int(m.parts.size()).is_equal(1)
	_run(m, 28)
	assert_int(m.parts.size()).is_equal(2)
	## Settled: a "z" at 46 and 74 ticks into each loop.
	_run(m, 112 - 45 + 47)
	assert_bool(m.parts.any(func(p: NpcFeelMoods.Part) -> bool: return p.life == 64)).is_true()


func test_shivering_flicks_between_two_frames() -> void:
	var m := _moods(&"buruburu")
	_run(m, 1)
	assert_str(String(m.ongen)).is_equal("lev_2d")
	var widths: Array[float] = []
	for _i: int in 4:
		widths.append(absf(m._body.node.scale.x))
		m.tick()
	assert_bool(widths.max() > widths.min()).is_true()


func test_adjust_is_the_decomp_ramp() -> void:
	assert_float(NpcFeelMoods._adjust(0, 0, 10, 0.0, 1.0)).is_equal(0.0)
	assert_float(NpcFeelMoods._adjust(5, 0, 10, 0.0, 1.0)).is_equal_approx(0.5, 0.0001)
	assert_float(NpcFeelMoods._adjust(12, 0, 10, 0.0, 1.0)).is_equal(1.0)
	assert_float(NpcFeelMoods._adjust(3, 4, 4, 2.0, 9.0)).is_equal(2.0)


func test_glyph_node_runs_and_releases_a_mood() -> void:
	var g: NpcFeelGlyphs = auto_free(NpcFeelGlyphs.new())
	_host.add_child(g)
	g.play(&"pun")
	assert_object(g._moods).is_not_null()
	g.release()
	g._tick_moods(1.0 / 60.0)
	assert_object(g._moods).is_null()


func test_moods_pick_their_poses() -> void:
	var M := VillagerState.Mood
	assert_str(NpcManpu.mood_clip(NpcManpu.MOOD_WAIT, M.HAPPY)).is_equal("npc_1_wait_ki1")
	assert_str(NpcManpu.mood_clip(NpcManpu.MOOD_WALK, M.ANGRY)).is_equal("npc_1_walk_do1")
	assert_str(NpcManpu.mood_clip(NpcManpu.MOOD_RUN, M.SAD)).is_equal("npc_1_walk_ai1")
	assert_str(NpcManpu.mood_clip(NpcManpu.MOOD_WALK, M.SLEEPY)).is_equal("npc_1_walk1")
	assert_str(NpcManpu.mood_clip(NpcManpu.MOOD_WAIT, M.SLEEPY)).is_equal("npc_1_wait_nemu1")
	## Talking, a happy villager keeps the plain idle (`talk_def_anime`).
	assert_str(NpcManpu.mood_clip(NpcManpu.MOOD_TALK, M.HAPPY)).is_equal("npc_1_wait1")
	assert_str(NpcManpu.mood_clip(NpcManpu.MOOD_TALK, M.ANGRY)).is_equal("npc_1_wait_do1")


func test_mood_poses_give_off_their_effects() -> void:
	var m := _moods(&"ambient")
	assert_bool(m.alive).is_false()
	for e: StringName in [&"konpu", &"pun_yuge", &"doyon", &"neboke_awa"]:
		m.pulse(e)
	assert_int(m.parts.size()).is_equal(4)
	assert_array(m.trg_se).contains([&"43f", &"pun_yuge", &"doyon"])
	_run(m, 80)
	assert_int(m.parts.size()).is_equal(0)


func test_a_pose_fires_on_its_counter() -> void:
	var g: NpcFeelGlyphs = auto_free(NpcFeelGlyphs.new())
	_host.add_child(g)
	g.set_pose("npc_1_wait_ai1")
	## Counter 0.5 a tick, firing at 10, wrapping past 10: every 20 ticks.
	g._tick_pose(1.0 / 60.0 * 21.0)
	assert_object(g._ambient).is_not_null()
	assert_int(g._ambient.parts.size()).is_equal(1)
	g.set_pose("npc_1_walk1")
	g._tick_pose(1.0 / 60.0 * 200.0)
	assert_int(g._ambient.parts.size()).is_equal(0)
