class_name TestVillagerGreeting
extends GdUnitTestSuite

## `VillagerGreeting` against `aNPC_greeting_area_check` / `ac_npc_act_greeting.c_inc`, and the
## mailed-shirt present (`mNpc_SetPresentCloth` / `mNpc_ChangePresentCloth`).


func before_test() -> void:
	VillagerCatalog.reload()


func _node(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	return auto_free(n)


func _info(looks: int, friendship: int, slot: int) -> Dictionary:
	var v: VillagerData = null
	for c: VillagerData in VillagerCatalog.all_villagers():
		if c.personality != null and int(c.personality.looks) == looks and not c.islander:
			v = c
			break
	var s := VillagerState.new()
	s.villager_id = v.id
	s.relationship.set_friendship(friendship)
	return {"state": s, "data": v, "slot": slot}


func test_pairs_within_80_gx_first_come() -> void:
	var a := _node(Vector3(0, 0, 0))
	var b := _node(Vector3(3.5, 0, 0))
	var c := _node(Vector3(0, 0, 3.0))
	var d := _node(Vector3(20, 0, 0))
	var pairs: Array = VillagerGreeting.pair_up([a, b, c, d])
	assert_int(pairs.size()).is_equal(1)
	assert_that(pairs[0][0]).is_equal(a)
	assert_that(pairs[0][1]).is_equal(b)
	## Too far apart vertically.
	var e := _node(Vector3(0, 3, 0))
	assert_int(VillagerGreeting.pair_up([c, e]).size()).is_equal(0)


func test_upset_villagers_do_not_greet() -> void:
	var s := VillagerState.new()
	assert_bool(VillagerGreeting.can_greet(s)).is_true()
	s.mood = VillagerState.Mood.SAD
	assert_bool(VillagerGreeting.can_greet(s)).is_false()
	s.mood = VillagerState.Mood.HAPPY
	assert_bool(VillagerGreeting.can_greet(s)).is_true()


func test_reactions_move_moods_opinions_and_clothes() -> void:
	var residents := TownResidents.new()
	var seen: Dictionary = {}
	for seed_value: int in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var x: Dictionary = _info(0, 40, 0)
		var y: Dictionary = _info(1, 20, 1)
		var react: int = VillagerGreeting.react(x, y, [], residents, rng)
		seen[react] = true
		match react:
			NeedleworkTrend.React.RESET_END_WORDS:
				## A (the friendlier one) scolds B back to their own catchphrase.
				assert_int(int((x["state"] as VillagerState).mood)).is_equal(VillagerState.Mood.ANGRY)
			NeedleworkTrend.React.SET_CLOTH:
				assert_int(int((x["state"] as VillagerState).mood)).is_equal(VillagerState.Mood.SAD)
			NeedleworkTrend.React.CHG_SP_CLOTH:
				assert_int((x["state"] as VillagerState).cloth_design).is_between(0, 3)
	## The 20 % tail is "nothing happens".
	assert_bool(seen.has(-1)).is_true()
	assert_bool(seen.has(NeedleworkTrend.React.SET_FEEL)).is_true()


func test_a_present_shirt_blocks_the_shirt_reactions() -> void:
	var residents := TownResidents.new()
	for seed_value: int in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var x: Dictionary = _info(0, 40, 0)
		var y: Dictionary = _info(2, 20, 1)
		(y["state"] as VillagerState).wearing_present_cloth = true
		var react: int = VillagerGreeting.react(x, y, [], residents, rng)
		assert_int(react).is_less(NeedleworkTrend.React.COPY_CLOTH)


func test_copy_end_words_between_same_sex() -> void:
	var residents := TownResidents.new()
	var x: Dictionary = _info(0, 40, 0)
	var y: Dictionary = _info(2, 20, 1)
	(x["state"] as VillagerState).catchphrase = "zoinks"
	VillagerGreeting._apply(NeedleworkTrend.React.COPY_END_WORDS, x, y, [], residents, RandomNumberGenerator.new())
	## Normal and lazy are different sexes: nothing copied, both still cheered up.
	assert_str((y["state"] as VillagerState).catchphrase).is_not_equal("zoinks")
	assert_int(int((y["state"] as VillagerState).mood)).is_equal(VillagerState.Mood.HAPPY)
	var z: Dictionary = _info(1, 20, 2)
	VillagerGreeting._apply(NeedleworkTrend.React.COPY_END_WORDS, x, z, [], residents, RandomNumberGenerator.new())
	assert_str((z["state"] as VillagerState).catchphrase).is_equal("zoinks")
	assert_int(residents.relation(0, 2)).is_equal(TownResidents.RELATION_NEUTRAL + 8)


func test_around_list_sorts_every_other_slot() -> void:
	var list: Array = [{"friendship": 1}, {"friendship": 5}, {"friendship": 3}, {"friendship": 9}]
	VillagerGreeting.sort_around(list)
	assert_int(int(list[0]["friendship"])).is_equal(9)
	assert_int(int(list[2]["friendship"])).is_equal(3)


func test_mailed_shirt_is_worn_after_the_next_start_and_thanked_once() -> void:
	var s := VillagerState.new()
	s.relationship.set_friendship(20)
	assert_bool(s.receive_present_cloth(&"shirt_002")).is_false()
	s.relationship.set_friendship(40)
	assert_bool(s.receive_present_cloth(&"apple")).is_false()
	assert_bool(s.receive_present_cloth(&"shirt_002")).is_true()
	assert_that(s.cloth_id).is_equal(&"")
	s.wear_present_cloth()
	assert_that(s.cloth_id).is_equal(&"shirt_002")
	assert_bool(s.wearing_present_cloth).is_true()
	var v: VillagerData = _info(3, 40, 0)["data"]
	var ctx := DialogueContext.new()
	ctx.rng = RandomNumberGenerator.new()
	s.relationship.record_talk("2001-01-01")
	ctx.days_since_talk = 3
	var msg: int = DialogueGreeting.hello_msg_no(v, s, ctx)
	assert_int(msg).is_between(DialogueGreeting.THANKS_CLOTH + 3 * 3, DialogueGreeting.THANKS_CLOTH + 3 * 3 + 2)
	assert_str(ctx.item0).is_not_empty()
	assert_bool(s.wearing_present_cloth).is_false()
	assert_int(DialogueGreeting.hello_msg_no(v, s, ctx)).is_not_equal(msg)
