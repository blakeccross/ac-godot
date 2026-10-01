extends GdUnitTestSuite

## The birthday picker (`mBR_move_Play`), star signs, the present visit
## (`aNPS2_make_door_data`, `aPRD_setup_present`) and the cards' timing (`check_past_day`).

const K := PresentVisit.Kind
const F := BirthdayOverlay.Field


func test_picker_wraps_like_a_leap_year() -> void:
	assert_that(BirthdayOverlay.step(12, 5, F.MONTH, true)).is_equal(Vector2i(1, 5))
	assert_that(BirthdayOverlay.step(1, 5, F.MONTH, false)).is_equal(Vector2i(12, 5))
	## A month change pulls the day into range; February has 29 days.
	assert_that(BirthdayOverlay.step(1, 31, F.MONTH, true)).is_equal(Vector2i(2, 29))
	assert_that(BirthdayOverlay.step(2, 29, F.DAY, true)).is_equal(Vector2i(2, 1))
	assert_that(BirthdayOverlay.step(4, 1, F.DAY, false)).is_equal(Vector2i(4, 30))


func test_star_signs() -> void:
	assert_int(VillagerTalkManager.constellation(1, 19)).is_equal(0)
	assert_int(VillagerTalkManager.constellation(1, 20)).is_equal(1)
	assert_int(VillagerTalkManager.constellation(12, 21)).is_equal(11)
	assert_int(VillagerTalkManager.constellation(12, 22)).is_equal(0)


func test_who_waits_at_the_door() -> void:
	var bd := Vector2i(10, 1)
	## Birthday first, even over Resetti, once a year, with room and a friend.
	assert_int(PresentVisit.decide(10, 1, 2026, bd, 0, true, true, true, true, false, false, false)).is_equal(K.BIRTHDAY)
	assert_int(PresentVisit.decide(10, 1, 2026, bd, 2026, true, false, true, false, false, false, false)).is_equal(K.NONE)
	assert_int(PresentVisit.decide(10, 1, 2026, bd, 0, false, false, true, false, false, false, false)).is_equal(K.NONE)
	assert_int(PresentVisit.decide(10, 1, 2026, bd, 0, true, false, false, false, false, false, false)).is_equal(K.NONE)
	## Then Tortimer: the rod before the net, each once, never past Resetti or full pockets.
	assert_int(PresentVisit.decide(10, 2, 2026, bd, 0, true, false, true, true, false, true, false)).is_equal(K.GOLDEN_ROD)
	assert_int(PresentVisit.decide(10, 2, 2026, bd, 0, true, false, true, true, true, true, false)).is_equal(K.GOLDEN_NET)
	assert_int(PresentVisit.decide(10, 2, 2026, bd, 0, true, false, true, true, true, true, true)).is_equal(K.NONE)
	assert_int(PresentVisit.decide(10, 2, 2026, bd, 0, true, true, true, true, false, false, false)).is_equal(K.NONE)
	assert_int(PresentVisit.decide(10, 2, 2026, bd, 0, true, false, false, true, false, false, false)).is_equal(K.NONE)


func test_cards_come_once_the_birthday_has_passed() -> void:
	var bd := Vector2i(10, 1)
	var sep30: int = EventDates.ordinal(2026, 9, 30)
	var oct1: int = EventDates.ordinal(2026, 10, 1)
	var oct5: int = EventDates.ordinal(2026, 10, 5)
	assert_bool(PresentVisit.birthday_passed(bd, sep30, oct1)).is_true()
	assert_bool(PresentVisit.birthday_passed(bd, sep30, oct5)).is_true()
	assert_bool(PresentVisit.birthday_passed(bd, oct1, oct5)).is_false()
	assert_bool(PresentVisit.birthday_passed(bd, sep30, sep30)).is_false()
	## Away over New Year: last year's date still counts.
	assert_bool(PresentVisit.birthday_passed(Vector2i(12, 30), EventDates.ordinal(2025, 12, 20), EventDates.ordinal(2026, 1, 3))).is_true()
	## No birthday, or no last date: nothing.
	assert_bool(PresentVisit.birthday_passed(Vector2i.ZERO, sep30, oct1)).is_false()
	assert_bool(PresentVisit.birthday_passed(bd, 0, oct1)).is_false()
	## Leap-day birthdays fall on February 28th in other years.
	assert_bool(PresentVisit.birthday_passed(Vector2i(2, 29), EventDates.ordinal(2027, 2, 27), EventDates.ordinal(2027, 2, 28))).is_true()


func test_the_talk_hands_the_present_over_on_the_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var talk := PresentVisit.Talk.new(K.GOLDEN_NET, 0, rng)
	talk.inventory = Inventory.new()
	var had_net: bool = PresentVisit.has_trophy(PresentVisit.TROPHY_NET)
	assert_int(talk.start_msg()).is_equal(PresentVisit.MSG_NET)
	assert_that(talk.lock_continue()).is_equal({})
	talk.npc_order("npc0", 1, 2)
	assert_that(talk.lock_continue()).is_equal({"anim": {"give": PresentVisit.GOLDEN_NET}})
	assert_that(talk.lock_continue()).is_equal({})
	assert_int(talk.inventory.count_of(PresentVisit.GOLDEN_NET)).is_equal(1)
	assert_bool(PresentVisit.has_trophy(PresentVisit.TROPHY_NET)).is_true()
	if not had_net:
		(PresentVisit.record().get("trophies", {}) as Dictionary).erase(str(PresentVisit.TROPHY_NET))
	var bday := PresentVisit.Talk.new(K.BIRTHDAY, 2, rng)
	var first: int = bday.start_msg()
	assert_int(first).is_between(PresentVisit.MSG_BIRTHDAY + 12, PresentVisit.MSG_BIRTHDAY + 14)


## The present changes hands between the two pages, then the message goes on.
func test_the_runner_holds_the_page_for_the_hand_over() -> void:
	if DialogueCatalog.conversation(&"msg_12739") == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var talk := PresentVisit.Talk.new(K.GOLDEN_ROD, 0, rng)
	talk.inventory = Inventory.new()
	var had_rod: bool = PresentVisit.has_trophy(PresentVisit.TROPHY_ROD)
	var runner := DialogueRunner.new()
	runner.talk_manager = talk
	talk.context = DialogueContext.new()
	var asked: Array = []
	runner.action_requested.connect(func(a: Dictionary) -> void: asked.append(a))
	runner.start(DialogueCatalog.conversation(&"msg_12739"), talk.context)
	var guard := 0
	while not runner.waiting_action and not runner.done and guard < 20:
		guard += 1
		runner.advance()
	assert_bool(runner.waiting_action).is_true()
	assert_int(asked.size()).is_equal(1)
	assert_that(asked[0]).is_equal({"anim": {"give": PresentVisit.GOLDEN_ROD}})
	assert_int(talk.current_msg).is_equal(PresentVisit.MSG_ROD)
	runner.resolve_action({})
	assert_bool(runner.done).is_false()
	assert_int(talk.current_msg).is_equal(0x31C4)
	assert_int(talk.inventory.count_of(PresentVisit.GOLDEN_ROD)).is_equal(1)
	if not had_rod:
		(PresentVisit.record().get("trophies", {}) as Dictionary).erase(str(PresentVisit.TROPHY_ROD))
