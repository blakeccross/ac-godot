class_name TestRedd
extends GdUnitTestSuite

## Crazy Redd: unlock gate, weekly schedule, genuine/forged stock, purchase, forgery
## rejection at the museum.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_locked_until_art_or_town_age() -> void:
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 3, "hour": 12})
	Game.redd.check_unlock()
	assert_bool(Game.redd.unlocked).is_false()
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 20, "hour": 12})
	Game.redd.check_unlock()
	assert_bool(Game.redd.unlocked).is_true()


func test_unlocks_when_museum_gets_art() -> void:
	Game.museum.set_art(4, int(MuseumBook.Donator.PLAYER1))
	Game.redd.check_unlock()
	assert_bool(Game.redd.unlocked).is_true()
	assert_int(Game.redd.open_weekday).is_between(0, 6)


func test_open_only_on_scheduled_weekday() -> void:
	Game.redd.unlocked = true
	Game.redd.open_weekday = 3
	## Walk the week; open on exactly one day.
	var open_days := 0
	for day: int in range(1, 8):
		Clock.apply_snapshot({"year": 2001, "month": 4, "day": day, "hour": 12})
		if Game.redd.is_open_today():
			open_days += 1
	assert_int(open_days).is_equal(1)


func test_stock_always_forges_art02_and_art03() -> void:
	ReddBook.ensure_art_items()
	Game.redd.unlocked = true
	Game.redd.open_weekday = Clock.weekday()
	var forged_indices: Array = []
	for row: Dictionary in Game.redd.stock():
		if bool(row.get("forged", false)):
			forged_indices.append(int(row.get("art_index", -1)))
	for row: Dictionary in Game.redd.stock():
		var idx: int = int(row.get("art_index", -1))
		if idx in ReddBook.ALWAYS_FORGED and idx >= 0:
			assert_bool(bool(row.get("forged"))).is_true()


func test_buy_genuine_then_donate_completes_toward_art() -> void:
	ReddBook.ensure_art_items()
	var genuine_id: StringName = ReddBook.art_item_id(4, false)
	Game.inventory.add(ItemCatalog.get_item(genuine_id), 1)
	var res: Dictionary = Game.donate_museum_result(genuine_id)
	assert_bool(res.get("ok", false)).is_true()
	assert_int(Game.museum.count_art()).is_equal(1)


func test_forgery_is_rejected_by_blathers() -> void:
	ReddBook.ensure_art_items()
	var fake_id: StringName = ReddBook.art_item_id(6, true)
	var fake: ItemData = ItemCatalog.get_item(fake_id)
	assert_that(Game.museum.display_info_for_item(fake)).is_equal(MuseumBook.DisplayInfo.CANNOT_DONATE)
	Game.inventory.add(fake, 1)
	var res: Dictionary = Game.donate_museum_result(fake_id)
	assert_bool(res.get("ok", false)).is_false()
	assert_str(str(res.get("reason", ""))).is_equal("forgery")
	assert_int(Game.museum.count_art()).is_equal(0)


func test_one_purchase_per_visit() -> void:
	ReddBook.ensure_art_items()
	Game.redd.unlocked = true
	Game.redd.open_weekday = Clock.weekday()
	Game.inventory.set_wallet(50000)
	var first: Dictionary = Game.redd.stock()[0]
	var msg1: String = Game.redd.buy(StringName(str(first.get("item_id"))), Game.inventory)
	assert_str(msg1).contains("Pleasure")
	var second: Dictionary = Game.redd.stock()[1]
	var msg2: String = Game.redd.buy(StringName(str(second.get("item_id"))), Game.inventory)
	assert_str(msg2).contains("customer")
