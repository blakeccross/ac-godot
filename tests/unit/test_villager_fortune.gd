class_name TestVillagerFortune
extends GdUnitTestSuite

## Katrina's fortunes as the villagers feel them (`aNPC_set_over_friendship`,
## `aNPC_chk_friendship_lv`) and as luck (`mPr_GetGoodsPower`).

const L := VillagerPersonality.Looks

var _saved_type: int
var _saved_date: Vector3i
var _saved_goods: int


func before_test() -> void:
	_saved_type = Game.destiny_type
	_saved_date = Game.destiny_date
	_saved_goods = Game.goods_power


func after_test() -> void:
	Game.destiny_type = _saved_type
	Game.destiny_date = _saved_date
	Game.goods_power = _saved_goods


func test_an_unpopular_day_sends_villagers_away() -> void:
	var D := Game.Destiny
	assert_int(VillagerFortune.step(D.UNPOPULAR, L.JOCK, &"male", true, 100.0)).is_equal(VillagerFortune.Step.AVOID_RUN)
	assert_int(VillagerFortune.step(D.UNPOPULAR, L.JOCK, &"male", true, 150.0)).is_equal(VillagerFortune.Step.AVOID_WALK)
	assert_int(VillagerFortune.step(D.UNPOPULAR, L.JOCK, &"male", true, 200.0)).is_equal(VillagerFortune.Step.NONE)
	## Only in the player's acre.
	assert_int(VillagerFortune.step(D.UNPOPULAR, L.JOCK, &"male", false, 50.0)).is_equal(VillagerFortune.Step.NONE)


func test_a_popular_day_draws_the_other_sex_over() -> void:
	var D := Game.Destiny
	assert_int(VillagerFortune.step(D.POPULAR, L.PEPPY, &"male", true, 200.0)).is_equal(VillagerFortune.Step.SEEK_RUN)
	assert_int(VillagerFortune.step(D.POPULAR, L.SNOOTY, &"male", true, 100.0)).is_equal(VillagerFortune.Step.SEEK_WALK)
	assert_int(VillagerFortune.step(D.POPULAR, L.NORMAL, &"male", true, 40.0)).is_equal(VillagerFortune.Step.SEEK_WAIT)
	## Same sex: no change.
	assert_int(VillagerFortune.step(D.POPULAR, L.CRANKY, &"male", true, 200.0)).is_equal(VillagerFortune.Step.NONE)
	assert_int(VillagerFortune.step(D.POPULAR, L.LAZY, &"female", true, 200.0)).is_equal(VillagerFortune.Step.SEEK_RUN)
	## Ordinary days leave everyone be.
	assert_int(VillagerFortune.step(D.NORMAL, L.PEPPY, &"male", true, 40.0)).is_equal(VillagerFortune.Step.NONE)
	assert_int(VillagerFortune.step(D.MONEY_LUCK, L.PEPPY, &"male", true, 40.0)).is_equal(VillagerFortune.Step.NONE)


func test_a_close_admirer_calls_out() -> void:
	assert_bool(VillagerFortune.can_call(70.0, 10.0)).is_true()
	assert_bool(VillagerFortune.can_call(90.0, 10.0)).is_false()
	assert_bool(VillagerFortune.can_call(70.0, 70.0)).is_false()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	assert_int(VillagerFortune.call_msg(L.PEPPY, rng)).is_between(0x075F + 3, 0x075F + 5)


func test_avoiding_heads_straight_away() -> void:
	var to: Vector3 = VillagerFortune.away_from(Vector3(2.0, 0.0, 0.0), Vector3.ZERO)
	assert_float(to.x).is_greater(2.0)
	assert_float(to.z).is_equal_approx(0.0, 0.0001)


func test_goods_power_moves_with_the_fortune_and_is_held_in_range() -> void:
	Game.goods_power = 40
	Game.set_destiny(Game.Destiny.GOODS_LUCK)
	assert_int(Game.goods_power_now()).is_equal(50)
	Game.goods_power = 0
	Game.set_destiny(Game.Destiny.BAD_LUCK)
	assert_int(Game.goods_power_now()).is_equal(-30)
	Game.set_destiny(Game.Destiny.NORMAL)
	Game.goods_power = 12
	assert_int(Game.goods_power_now()).is_equal(12)


func test_an_unpopular_day_greets_in_a_hurry() -> void:
	Game.set_destiny(Game.Destiny.UNPOPULAR)
	var v := VillagerData.new()
	v.id = &"fortune_test"
	v.personality = VillagerPersonality.new()
	v.personality.looks = L.LAZY
	var st := VillagerState.new()
	var ctx := DialogueContext.new()
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = 5
	ctx.hour = 12
	## A villager met before (`meet` past the first hello).
	st.last_spoke_day = "2001-1-1"
	ctx.days_since_talk = 1
	assert_int(DialogueGreeting.meet_type(st, ctx)).is_not_equal(DialogueGreeting.MEET_FIRST)
	var n: int = DialogueGreeting.hello_msg_no(v, st, ctx)
	assert_int(n).is_between(1869 + 6, 1869 + 8)
