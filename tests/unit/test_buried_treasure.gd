extends GdUnitTestSuite

## Villagers' buried treasure and their board posts (`mNtc_check_treasure`).


func test_once_a_day_from_six_three_days_apart() -> void:
	assert_bool(BuriedTreasure.due(100, 6, 0, 0)).is_true()
	assert_bool(BuriedTreasure.due(100, 5, 0, 0)).is_false()
	assert_bool(BuriedTreasure.due(100, 9, 0, 100)).is_false()
	assert_bool(BuriedTreasure.due(100, 9, 98, 99)).is_false()
	assert_bool(BuriedTreasure.due(100, 9, 97, 99)).is_true()


func test_a_third_are_pitfalls_the_rest_rare_furniture() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var lottery: Array[StringName] = FtrCatalog.list("lottery")
	var events: Array[StringName] = FtrCatalog.list("event")
	var pits: int = 0
	for _i: int in 300:
		var item: StringName = BuriedTreasure.pick_item(rng)
		if item == BuriedTreasure.PITFALL:
			pits += 1
		elif not lottery.is_empty():
			assert_bool(lottery.has(item) or events.has(item)).is_true()
	assert_int(pits).is_between(70, 130)


func test_the_post_names_the_item_and_the_acre() -> void:
	if not MailBank.has_bank():
		return
	var text: String = BuriedTreasure.post_text(0, 0, "Bill", &"pitfall", Vector2i(4, 3), "Pine")
	assert_str(text).contains("Bill")
	assert_str(text).contains("C-4")
	var data: ItemData = ItemCatalog.get_item(&"pitfall")
	if data != null:
		assert_str(text).contains(data.display_name)
