class_name TestAprilFools
extends GdUnitTestSuite

## April Fools' Day: the special NPCs' one trick a resident (`AprilFools`) and the
## villagers' holiday first hello (`DialogueGreeting.holiday_hello`).


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _april_first() -> void:
	Clock.apply_snapshot({"year": 2002, "month": 4, "day": 1, "hour": 10, "minute": 0})
	Game.events.sync(EventCalendar.make_date(2002, 4, 1, 10))


func _villager(looks: int) -> VillagerData:
	for c: VillagerData in VillagerCatalog.all_villagers():
		if c.personality != null and int(c.personality.looks) == looks and not c.islander:
			return c
	return null


func test_no_tricks_on_other_days() -> void:
	Clock.apply_snapshot({"year": 2002, "month": 4, "day": 2, "hour": 10, "minute": 0})
	Game.events.sync(EventCalendar.make_date(2002, 4, 2, 10))
	assert_bool(AprilFools.pending(&"copper")).is_false()
	assert_int(AprilFools.take(&"copper")).is_equal(-1)


func test_each_npc_tricks_a_resident_once() -> void:
	_april_first()
	assert_bool(Game.events.is_active(AprilFools.EVENT)).is_true()
	assert_int(AprilFools.take(&"copper")).is_equal(0x3BB3)
	assert_int(AprilFools.take(&"copper")).is_equal(-1)
	## The others still have theirs.
	assert_int(AprilFools.take(&"tom_nook")).is_equal(0x3BAC)
	assert_int(AprilFools.take(&"phyllis")).is_equal(0x3BAF)
	assert_bool(AprilFools.pending(&"blathers")).is_true()
	## Another resident gets their own tricks.
	Game.roster.current = 1
	assert_bool(AprilFools.pending(&"copper")).is_true()


func test_visitors_are_not_tricked() -> void:
	_april_first()
	Game.foreigner = true
	assert_bool(AprilFools.pending(&"pelly")).is_false()


func test_unknown_npcs_have_no_trick() -> void:
	_april_first()
	assert_bool(AprilFools.pending(&"tortimer")).is_false()


func test_villagers_first_hello_of_the_day_is_the_april_fools_one() -> void:
	_april_first()
	var v := _villager(2)
	var s := VillagerState.new()
	s.villager_id = v.id
	s.relationship.set_friendship(40)
	s.relationship.record_talk("2002-03-30")
	var ctx := DialogueContext.new()
	ctx.rng = RandomNumberGenerator.new()
	ctx.days_since_talk = 2
	ctx.hour = 10
	var msg: int = DialogueGreeting.hello_msg_no(v, s, ctx)
	var base: int = DialogueGreeting.APRIL_FOOLS_HELLO + 2 * 3
	assert_int(msg).is_between(base, base + 2)
	## Talking again the same day is the usual hello.
	ctx.already_talked = true
	msg = DialogueGreeting.hello_msg_no(v, s, ctx)
	assert_bool(msg >= base and msg <= base + 2).is_false()


func test_spring_cleaning_hello() -> void:
	Game.events.force(&"spring_cleaning")
	Game.events.sync(EventCalendar.make_date(2002, 3, 20, 10))
	assert_int(DialogueGreeting.holiday_hello(false)).is_equal(DialogueGreeting.SPRING_CLEANING_HELLO)
	assert_int(DialogueGreeting.holiday_hello(true)).is_equal(DialogueGreeting.ISLAND_SPRING_CLEANING_HELLO)
