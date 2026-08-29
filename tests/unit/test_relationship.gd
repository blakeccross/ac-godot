class_name TestRelationship
extends GdUnitTestSuite

## Player ↔ villager memory: friendship, talks, gifts, milestones. Not dialogue.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_first_talk_is_plus_three_and_met() -> void:
	var bond := Relationship.new()
	bond.villager_id = &"filbert"
	assert_int(bond.record_talk("2001-01-01")).is_equal(Relationship.TALK_FIRST)
	assert_int(bond.friendship).is_equal(Relationship.TALK_FIRST)
	assert_int(bond.talk_count).is_equal(1)
	assert_bool(bond.has_milestone(Relationship.MET)).is_true()
	assert_bool(bond.has_milestone(Relationship.BEST_FRIEND)).is_false()
	assert_str(str(bond.talks[0].get("kind", ""))).is_equal("first")


func test_same_day_talk_is_plus_one() -> void:
	var bond := Relationship.new()
	bond.record_talk("2001-01-01")
	assert_int(bond.record_talk("2001-01-01")).is_equal(Relationship.TALK_REPEAT)
	assert_int(bond.friendship).is_equal(Relationship.TALK_FIRST + Relationship.TALK_REPEAT)
	assert_str(str(bond.talks[1].get("kind", ""))).is_equal("today")


func test_new_day_talk_is_again() -> void:
	var bond := Relationship.new()
	bond.record_talk("2001-01-01")
	bond.record_talk("2001-01-02")
	assert_str(str(bond.talks[1].get("kind", ""))).is_equal("again")
	assert_int(bond.talk_count).is_equal(2)


func test_gift_adds_three_and_first_gift_milestone() -> void:
	var bond := Relationship.new()
	assert_int(bond.record_gift(&"apple", "2001-01-01")).is_equal(Relationship.GIFT_DELTA)
	assert_int(bond.gift_count).is_equal(1)
	assert_bool(bond.has_gifted(&"apple")).is_true()
	assert_bool(bond.has_milestone(Relationship.FIRST_GIFT)).is_true()
	assert_int(bond.friendship).is_equal(Relationship.GIFT_DELTA)


func test_best_friend_unlocks_at_eighty() -> void:
	var bond := Relationship.new()
	var unlocked: Array[StringName] = []
	bond.milestone_reached.connect(func(mark: StringName) -> void: unlocked.append(mark))
	bond.set_friendship(Relationship.BEST_FRIEND_AT - 1)
	assert_bool(bond.has_milestone(Relationship.BEST_FRIEND)).is_false()
	bond.add_friendship(1)
	assert_bool(bond.has_milestone(Relationship.BEST_FRIEND)).is_true()
	assert_bool(unlocked.has(Relationship.BEST_FRIEND)).is_true()
	bond.set_friendship(Relationship.KINDRED_AT)
	assert_bool(bond.has_milestone(Relationship.KINDRED)).is_true()


func test_book_give_gift_takes_from_inventory() -> void:
	var inv := Inventory.new()
	inv.add(load("res://data/items/apple.tres"), 1)
	var book := RelationshipBook.new()
	assert_bool(book.give_gift(&"filbert", &"apple", inv, "2001-01-01")).is_true()
	assert_int(inv.count_of(&"apple")).is_equal(0)
	assert_int(book.get_or_create(&"filbert").gift_count).is_equal(1)
	assert_bool(book.give_gift(&"filbert", &"apple", inv, "2001-01-01")).is_false()


func test_history_caps_at_twelve() -> void:
	var bond := Relationship.new()
	for i: int in 14:
		bond.record_talk("2001-01-%02d" % (i + 1))
	assert_int(bond.talks.size()).is_equal(Relationship.HISTORY)
	assert_str(str(bond.talks[0].get("day", ""))).is_equal("2001-01-03")


func test_save_round_trip_keeps_gifts_and_milestones() -> void:
	var bond := Game.relationships.get_or_create(&"filbert")
	bond.record_talk("2001-01-01")
	bond.record_gift(&"apple", "2001-01-01")
	bond.set_friendship(Relationship.BEST_FRIEND_AT)
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	var loaded: Relationship = Game.relationships.get_or_create(&"filbert")
	assert_int(loaded.friendship).is_equal(Relationship.BEST_FRIEND_AT)
	assert_int(loaded.talk_count).is_equal(1)
	assert_bool(loaded.has_gifted(&"apple")).is_true()
	assert_bool(loaded.has_milestone(Relationship.BEST_FRIEND)).is_true()
	assert_object(Game.villagers.get_or_create(&"filbert").relationship).is_same(loaded)


func test_legacy_villager_snapshot_still_loads_friendship() -> void:
	Game.villagers.apply_snapshot(
		{"filbert": {"id": "filbert", "friendship": 12, "last_spoke_day": "2001-01-01"}}
	)
	var state: VillagerState = Game.villagers.get_or_create(&"filbert")
	assert_int(state.friendship).is_equal(12)
	assert_str(state.last_spoke_day).is_equal("2001-01-01")
	assert_int(state.relationship.friendship).is_equal(12)


func test_dialogue_queries_milestones_without_owning_them() -> void:
	var data: DialogueData = DialogueData.from_dict(
		{
			"id": "rel",
			"start": "start",
			"nodes": {
				"start": {
					"type": "branch",
					"when": [
						{"if": {"milestone": "best_friend"}, "goto": "pal"},
						{"if": {"gifted": "apple"}, "goto": "gift"},
						{"goto": "new"},
					],
				},
				"pal": {"type": "line", "text": "Best pal."},
				"gift": {"type": "line", "text": "Thanks for the apple."},
				"new": {"type": "line", "text": "Hello."},
			},
		}
	)
	var state := VillagerState.new()
	assert_str(_spoken(data, DialogueContext.from_game(null, state), state)).is_equal("Hello.")
	state.relationship.record_gift(&"apple", "2001-01-01")
	assert_str(_spoken(data, DialogueContext.from_game(null, state), state)).is_equal(
		"Thanks for the apple."
	)
	state.relationship.set_friendship(Relationship.BEST_FRIEND_AT)
	assert_str(_spoken(data, DialogueContext.from_game(null, state), state)).is_equal("Best pal.")


func _spoken(data: DialogueData, ctx: DialogueContext, state: VillagerState) -> String:
	var runner := DialogueRunner.new()
	runner.start(data, ctx, state)
	return runner.line
