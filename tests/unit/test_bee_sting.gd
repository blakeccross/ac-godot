extends GdUnitTestSuite

## Bee sting: `m_player_main_stung_bee`, `mPlib_Get_UseFaceRom_index`, `mNpc_SetTalkBee` and the
## greeting branches in `aQMgr_get_hello_msg_no` (`ac_quest_talk_greeting.c`).


func before_test() -> void:
	VillagerCatalog.reload()
	Game.bee_swell = false
	Game.bee_chase = false
	Game.bee_greeted.clear()


func after_test() -> void:
	Game.bee_swell = false
	Game.bee_chase = false
	Game.bee_greeted.clear()


func _villager(looks: int) -> VillagerData:
	for c: VillagerData in VillagerCatalog.all_villagers():
		if c.personality != null and int(c.personality.looks) == looks and not c.islander:
			return c
	return null


func _met_state(v: VillagerData) -> VillagerState:
	var s := VillagerState.new()
	s.villager_id = v.id
	s.relationship.set_friendship(40)
	s.relationship.record_talk("2001-01-01")
	return s


func test_face_set_index_follows_the_rom_layout() -> void:
	assert_int(PlayerFace.set_index(false, 0, false)).is_equal(0)
	assert_int(PlayerFace.set_index(false, 3, false)).is_equal(3)
	assert_int(PlayerFace.set_index(true, 3, false)).is_equal(11)
	assert_int(PlayerFace.set_index(false, 3, true)).is_equal(19)
	assert_int(PlayerFace.set_index(true, 7, true)).is_equal(31)
	## Eyes are frames 0–7, mouths 8–13 of a set.
	assert_str(PlayerFace.eye_path(19, 2)).ends_with("face_19_02.png")
	assert_str(PlayerFace.mouth_path(19, 0)).ends_with("face_19_08.png")


func test_first_sting_swells_and_readies_one_remark_each() -> void:
	var v := _villager(0)
	assert_object(v).is_not_null()
	Game.bee_chase = true
	assert_bool(Game.bee_remark_pending(v.id)).is_false()
	Game.sting_by_bee()
	assert_bool(Game.bee_swell).is_true()
	assert_bool(Game.bee_chase).is_false()
	assert_bool(Game.bee_remark_pending(v.id)).is_true()
	Game.note_bee_greeting(v.id)
	assert_bool(Game.bee_remark_pending(v.id)).is_false()
	## Stung again while still swollen: no fresh remarks (`mNpc_SetTalkBee` checks the flag).
	Game.sting_by_bee()
	assert_bool(Game.bee_remark_pending(v.id)).is_false()


func test_greeting_remarks_on_the_face_then_on_the_bees() -> void:
	var v := _villager(2)
	var s := _met_state(v)
	var ctx := DialogueContext.new()
	ctx.rng = RandomNumberGenerator.new()
	ctx.days_since_talk = 3
	ctx.hour = 12
	ctx.bee_stung = true
	var msg: int = DialogueGreeting.hello_msg_no(v, s, ctx)
	var base: int = DialogueGreeting.msg_offset(DialogueGreeting.BEE_STUNG, 2, 12, 0)
	assert_int(msg).is_between(base, base + 2)
	## A chasing swarm outranks it: "Bees!" (`MSG_10988` by looks).
	ctx.bee_chase = true
	msg = DialogueGreeting.hello_msg_no(v, s, ctx)
	assert_int(msg).is_between(DialogueGreeting.BEE_CHASE + 2 * 3, DialogueGreeting.BEE_CHASE + 2 * 3 + 2)
	## First meetings still introduce themselves.
	ctx.bee_chase = false
	var stranger := VillagerState.new()
	stranger.villager_id = v.id
	msg = DialogueGreeting.hello_msg_no(v, stranger, ctx)
	assert_bool(msg >= base and msg <= base + 2).is_false()


func test_context_reads_the_flags_once_per_villager() -> void:
	var v := _villager(1)
	Game.sting_by_bee()
	var s := _met_state(v)
	assert_bool(DialogueContext.from_game(v, s).bee_stung).is_true()
	DialogueGreeting.conversation(v, s)
	assert_bool(DialogueContext.from_game(v, s).bee_stung).is_false()
