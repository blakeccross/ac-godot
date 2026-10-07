extends GdUnitTestSuite

## Blanca (`m_mask_cat.h`, `ac_npc_mask_cat`, `ac_npc_mask_cat2`).


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func _drawn() -> DesignPattern:
	var d := MaskCat.blank_face()
	d.pixels[0] = 3
	return d


func test_she_arrives_faceless() -> void:
	var d := MaskCat.blank_face()
	assert_int(d.palette).is_equal(15)
	assert_bool(MaskCat.is_drawn(d)).is_false()
	assert_bool(MaskCat.is_drawn(_drawn())).is_true()
	assert_bool(MaskCat.check_birth()).is_false()


func test_a_face_brings_her_to_town_until_ten_talks_or_a_week() -> void:
	MaskCat.store(_drawn(), "Ann", 1000)
	assert_bool(MaskCat.check_birth()).is_true()
	assert_str(str(MaskCat.state()["creator"])).is_equal("Ann")
	MaskCat.check_delete(1006)
	assert_bool(MaskCat.check_birth()).is_true()
	MaskCat.check_delete(1007)
	assert_bool(MaskCat.check_birth()).is_false()
	MaskCat.store(_drawn(), "Ann", 1000)
	Game.mask_cat["talk_idx"] = MaskCat.TALK_MAX
	assert_bool(MaskCat.check_birth()).is_false()


func test_her_talks_count_up_once_a_day() -> void:
	MaskCat.store(_drawn(), "Ann", 1000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	assert_int(MaskCat.town_msg(true, rng)).is_equal(0x31E4)
	assert_int(MaskCat.town_msg(true, rng)).is_equal(0x31E8)
	var again: int = MaskCat.town_msg(false, rng)
	assert_int(again).is_between(0x31E9, 0x31EB)
	assert_int(int(Game.mask_cat["talk_idx"])).is_equal(2)


func test_she_rides_every_visit_and_every_other_trip_home() -> void:
	var out: Dictionary = {}
	assert_bool(MaskCat.rides_train(true, false, 0.9, out)).is_true()
	out = {}
	assert_bool(MaskCat.rides_train(false, false, 0.3, out)).is_true()
	assert_bool(bool(out["scheduled"])).is_true()
	out = {}
	assert_bool(MaskCat.rides_train(false, true, 0.3, out)).is_false()
	assert_bool(bool(out["scheduled"])).is_false()


func test_she_takes_the_weekly_slot_but_not_gullivers_day() -> void:
	MaskCat.store(_drawn(), "Ann", EventDates.ordinal(2026, 10, 6))
	var cal := EventCalendar.new()
	## Tuesday 2026-10-06.
	var now := {"year": 2026, "month": 10, "day": 6, "hour": 10, "weekday": 2}
	cal._init_weekly(now)
	if cal.weekly_date == EventDates.md(10, 6):
		assert_str(String(cal.weekly_flag)).is_equal("")
	else:
		assert_str(String(cal.weekly_flag)).is_equal("mask_npc")
	assert_bool(cal._row_gated_off(&"mask_npc")).is_equal(cal.weekly_flag != &"mask_npc")
	MaskCat.clear()
	cal._init_weekly(now)
	assert_str(String(cal.weekly_flag)).is_equal("")


func test_the_train_talk_asks_then_thanks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_int(BlancaTalk.new(BlancaTalk.Kind.ASK, rng).start_msg()).is_equal(0x33F2)
	assert_int(BlancaTalk.new(BlancaTalk.Kind.ASK_AGAIN, rng).start_msg()).is_equal(0x33F3)
	assert_int(BlancaTalk.new(BlancaTalk.Kind.REDO, rng).start_msg()).is_equal(0x321A)
	assert_int(BlancaTalk.new(BlancaTalk.Kind.THANKS, rng).start_msg()).is_between(0x31E1, 0x31E3)
