extends GdUnitTestSuite

## Letters from Mom (`mPr_SendMailFromMother`).

const BD := Vector2i(10, 1)


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func test_dated_letters() -> void:
	var rng := _rng(1)
	var bday: Dictionary = MotherMail.dated(10, 1, BD, &"", rng)
	assert_int(int(bday["msg"])).is_between(MotherMail.MSG_BIRTHDAY, MotherMail.MSG_BIRTHDAY + 1)
	assert_str(String(bday["present"])).is_equal(String(FtrCatalog.item_id(MotherMail.FTR_CAKE)))
	var jan: Dictionary = MotherMail.dated(1, 1, BD, &"", rng)
	assert_int(int(jan["msg"])).is_between(0x164, 0x165)
	assert_str(String(jan["present"])).is_equal("money_10000")
	var dec: Dictionary = MotherMail.dated(12, 12, BD, &"", rng)
	assert_int(int(dec["msg"])).is_between(0x164 + 22, 0x164 + 23)
	assert_int(int(MotherMail.dated(4, 1, BD, &"", rng)["msg"])).is_between(0x180, 0x181)
	assert_int(int(MotherMail.dated(5, 10, BD, &"mothers_day", rng)["msg"])).is_between(0x17C, 0x17D)
	assert_int(int(MotherMail.dated(6, 21, BD, &"fathers_day", rng)["msg"])).is_between(0x17E, 0x17F)
	assert_int(int(MotherMail.dated(12, 24, BD, &"", rng)["msg"])).is_between(0x182, 0x183)
	assert_that(MotherMail.dated(3, 14, BD, &"", rng)).is_equal({})


func test_holidays_and_paper() -> void:
	assert_str(String(MotherMail.holiday(2026, 5, 10))).is_equal("mothers_day")
	assert_str(String(MotherMail.holiday(2026, 6, 21))).is_equal("fathers_day")
	assert_str(String(MotherMail.holiday(2026, 6, 14))).is_equal("")
	assert_int(MotherMail.paper(3, 14, BD)).is_equal(31)
	assert_int(MotherMail.paper(10, 1, BD)).is_equal(0)
	assert_int(MotherMail.paper(1, 1, BD)).is_equal(62)
	assert_int(MotherMail.paper(8, 8, BD)).is_equal(47)
	assert_int(MotherMail.paper(12, 24, BD)).is_equal(22)


func test_seasonal_letters_follow_the_disc_order() -> void:
	assert_int(MotherMail.monthly_msg(3, 0)).is_equal(0x18C)
	assert_int(MotherMail.monthly_msg(5, 1)).is_equal(0x191)
	assert_int(MotherMail.monthly_msg(6, 0)).is_equal(0x192)
	assert_int(MotherMail.monthly_msg(8, 7)).is_equal(0x19D)
	assert_int(MotherMail.monthly_msg(9, 0)).is_equal(0x186)
	assert_int(MotherMail.monthly_msg(11, 1)).is_equal(0x18B)
	assert_int(MotherMail.monthly_msg(12, 0)).is_equal(0x19E)
	assert_int(MotherMail.monthly_msg(2, 1)).is_equal(0x1A3)
	assert_str(String(MotherMail.monthly_present(5, 1, _rng(1)))).is_equal("shirt_105")
	assert_str(String(MotherMail.monthly_present(12, 0, _rng(1)))).is_equal("apple")


func test_one_letter_a_day_each_everyday_letter_once() -> void:
	var state: Dictionary = MotherMail.new_state()
	var got: Array = []
	var deliver := func(mail: MailData) -> bool:
		got.append(mail)
		return true
	var rng := _rng(7)
	var day: int = EventDates.ordinal(2026, 3, 2)
	## The first look only notes the date.
	assert_int(MotherMail.check(state, day, BD, &"", "Ann", rng, deliver)).is_equal(-1)
	assert_int(MotherMail.check(state, day, BD, &"", "Ann", rng, deliver)).is_equal(-1)
	var sent: Array[int] = []
	for i: int in 2000:
		var d: Vector3i = EventDates.from_ordinal(day + 1 + i)
		if MotherMail.dated(d.y, d.z, BD, MotherMail.holiday(d.x, d.y, d.z), _rng(0)).size() > 0:
			continue
		var n: int = MotherMail.check(state, day + 1 + i, BD, &"", "Ann", rng, deliver)
		if n >= MotherMail.MSG_NORMAL and n < MotherMail.MSG_NORMAL + MotherMail.NORMAL_COUNT:
			assert_bool(sent.has(n)).is_false()
			sent.append(n)
		if sent.size() == MotherMail.NORMAL_COUNT:
			break
	assert_int(sent.size()).is_equal(MotherMail.NORMAL_COUNT)
	## Then the record is wiped and a seasonal letter comes once.
	assert_int(MotherMail.normal_left(state).size()).is_equal(0)
	var before: int = got.size()
	var guard: int = 0
	var next: int = -1
	var d0: int = day + 3000
	while next < 0 and guard < 200:
		guard += 1
		d0 += 1
		var dd: Vector3i = EventDates.from_ordinal(d0)
		if MotherMail.dated(dd.y, dd.z, BD, MotherMail.holiday(dd.x, dd.y, dd.z), _rng(0)).size() > 0:
			continue
		next = MotherMail.check(state, d0, BD, &"", "Ann", rng, deliver)
	var dm: Vector3i = EventDates.from_ordinal(d0)
	assert_int(next).is_between(MotherMail.monthly_msg(dm.y, 0), MotherMail.monthly_msg(dm.y, MotherMail.monthly_count(dm.y) - 1))
	assert_int(got.size()).is_equal(before + 1)
	assert_int(MotherMail.normal_left(state).size()).is_equal(MotherMail.NORMAL_COUNT)
	if MailBank.has_bank():
		assert_str((got[0] as MailData).header).contains("Ann")
