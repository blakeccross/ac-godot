extends GdUnitTestSuite

## The fishing tourney's records, results letter and board post (`m_fishrecord.c`).


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _o(y: int, m: int, d: int) -> int:
	return EventDates.ordinal(y, m, d)


func test_tourney_days_are_june_and_november_sundays() -> void:
	assert_bool(FishRecord.is_tourney_day(2026, 6, 7)).is_true()
	assert_bool(FishRecord.is_tourney_day(2026, 11, 1)).is_true()
	assert_bool(FishRecord.is_tourney_day(2026, 6, 8)).is_false()
	assert_bool(FishRecord.is_tourney_day(2026, 7, 5)).is_false()


func test_one_record_a_day_and_five_at_most() -> void:
	var records: Array = []
	FishRecord.set_record(records, "Ann", true, 12, _o(2026, 6, 7), 600)
	FishRecord.set_record(records, "Ann", true, 15, _o(2026, 6, 7), 700)
	assert_int(records.size()).is_equal(1)
	assert_int(int(records[0]["size"])).is_equal(15)
	## A villager's record from another day goes when a new day starts.
	FishRecord.set_record(records, "Bill", false, 10, _o(2026, 6, 14), 600)
	FishRecord.set_record(records, "Ann", true, 11, _o(2026, 6, 21), 600)
	assert_int(records.size()).is_equal(2)
	for d: int in [28]:
		FishRecord.set_record(records, "Ann", true, 11, _o(2026, 6, d), 600)
	for d: int in [1, 8, 15]:
		FishRecord.set_record(records, "Ann", true, 11, _o(2026, 11, d), 600)
	assert_int(records.size()).is_equal(FishRecord.MAX)
	## The oldest made room.
	for r: Dictionary in records:
		assert_int(int(r["ordinal"])).is_not_equal(_o(2026, 6, 7))


func test_villagers_fish_until_ten_to_six() -> void:
	assert_int(FishRecord.npc_best(FishRecord.LAST_ROLL, 0, _rng(1))).is_equal(0)
	## Nobody lands a 99-incher.
	assert_int(FishRecord.npc_best(6 * 60, 99, _rng(1))).is_equal(0)
	## Twenty-four rolls from 6:00 beat a 1-incher.
	assert_int(FishRecord.npc_best(6 * 60, 1, _rng(1))).is_greater(1)
	var rec: Dictionary = {"name": "Ann", "player": true, "size": 1, "ordinal": 1, "minute": 360}
	FishRecord.settle(rec, ["Bill"], _rng(2))
	assert_bool(bool(rec["player"])).is_false()
	assert_str(str(rec["name"])).is_equal("Bill")
	var kept: int = int(rec["size"])
	FishRecord.settle(rec, ["Bill"], _rng(3))
	assert_int(int(rec["size"])).is_equal(kept)


func test_the_winner_gets_a_letter_after_six() -> void:
	var records: Array = []
	var day: int = _o(2026, 6, 7)
	FishRecord.set_record(records, "Ann", true, 99, day, 9 * 60)
	var got: Array = []
	var deliver := func(mail: MailData) -> bool:
		got.append(mail)
		return true
	assert_int(FishRecord.send_mail(records, day, 17, [], [], "Ann", _rng(1), deliver)).is_equal(0)
	assert_int(records.size()).is_equal(1)
	var sent: int = FishRecord.send_mail(records, day, 18, [], [], "Ann", _rng(1), deliver)
	if MailBank.has_bank():
		assert_int(sent).is_equal(1)
		assert_int(records.size()).is_equal(0)
		var mail: MailData = got[0]
		assert_int(mail.paper_type).is_equal(FishRecord.PAPER)
		assert_str(mail.footer).contains("Chip")
		assert_bool(mail.present_item_id != &"").is_true()


func test_the_prize_is_furniture_not_yet_owned() -> void:
	var lottery: Array[StringName] = FtrCatalog.list("lottery")
	var events: Array[StringName] = FtrCatalog.list("event")
	if lottery.is_empty() or events.is_empty():
		return
	var owned: Array = lottery.duplicate()
	owned.append_array(events.slice(1))
	assert_str(String(FishRecord.present(owned, _rng(5)))).is_equal(String(events[0]))


func test_the_board_posts_the_winner() -> void:
	var records: Array = []
	FishRecord.set_record(records, "Ann", true, 99, _o(2026, 6, 7), 9 * 60)
	var b := NoticeBoard.new()
	b.checked = Vector4i(2026, 6, 7, 10)
	var rng := _rng(1)
	var n: int = b.auto_write(2026, 6, 8, 9, {}, func(ordinal: int) -> Dictionary:
		return FishRecord.holder(records, ordinal, ["Bill"], rng))
	## The result (June 7th, 18:00), then the June 8th seasonal notice.
	assert_int(n).is_equal(2)
	if MailBank.has_bank():
		var post: Dictionary = b.posts[-2]
		assert_str(str(post["text"])).contains("Ann")
		assert_str(str(post["text"])).contains("99")
		assert_int(int(post["day"])).is_equal(7)
		assert_int(int(post["hour"])).is_equal(18)
