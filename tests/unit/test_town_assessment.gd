extends GdUnitTestSuite

## `m_field_assessment` and the wishing well's reply (`aSHR_talk`).


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()
	var layout: WorldData = null


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func _acres(trees: int, weeds: int = 0, flowers: int = 0) -> Array:
	var out: Array = []
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var a := TownAssessment.AcreTally.new()
			a.block = Vector2i(bx, bz)
			a.trees = trees
			a.weeds = weeds
			a.flowers = flowers
			out.append(a)
	return out


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	return rng


func test_acre_scores_by_trees_weeds_and_trash() -> void:
	var a := TownAssessment.AcreTally.new()
	for pair: Array in [[8, 0], [9, 1], [11, 1], [12, 2], [14, 2], [15, 1], [17, 1], [18, 0]]:
		a.trees = pair[0]
		assert_int(TownAssessment.block_rank(a)).is_equal(pair[1])
	a.trees = 12
	a.weeds = 3
	assert_int(TownAssessment.block_rank(a)).is_equal(0)
	a.flowers = 1
	assert_int(TownAssessment.block_rank(a)).is_equal(2)
	a.dust = 1
	assert_int(TownAssessment.block_rank(a)).is_equal(0)


func test_town_rank_and_remarks() -> void:
	## Every acre perfect: 30 → rank 6, nothing to remark on.
	var best: Dictionary = TownAssessment.evaluate(_acres(13), _rng())
	assert_int(int(best["rank"])).is_equal(6)
	assert_int(int(best["condition"])).is_equal(TownAssessment.Condition.NO_CASE)
	## Good acres count half: 30 good → 15 → rank 5.
	assert_int(int(TownAssessment.evaluate(_acres(10), _rng())["rank"])).is_equal(5)
	## Bare town: too few trees, and the remark names an acre.
	var bare: Dictionary = TownAssessment.evaluate(_acres(0), _rng())
	assert_int(int(bare["rank"])).is_equal(0)
	assert_int(int(bare["condition"])).is_equal(TownAssessment.Condition.TREE_LESS)
	## Weeds over flowers: weeds is the remark once the trees are fine.
	var weedy: Dictionary = TownAssessment.evaluate(_acres(13, 6, 0), _rng())
	assert_int(int(weedy["condition"])).is_equal(TownAssessment.Condition.GRASS_OVER)
	## Five pieces of trash: rank 0 whatever else.
	var acres: Array = _acres(13)
	for i: int in 5:
		(acres[i] as TownAssessment.AcreTally).dust = 1
	var dirty: Dictionary = TownAssessment.evaluate(acres, _rng())
	assert_int(int(dirty["rank"])).is_equal(0)
	assert_int(int(dirty["condition"])).is_equal(TownAssessment.Condition.DUST_OVER)


func test_perfect_streak_counts_days_and_caps() -> void:
	assert_that(TownAssessment.next_streak(6, 0, -1, 100)).is_equal(Vector2i(0, 100))
	assert_that(TownAssessment.next_streak(6, 0, 100, 103)).is_equal(Vector2i(3, 103))
	assert_that(TownAssessment.next_streak(6, 14, 100, 110)).is_equal(Vector2i(15, 110))
	assert_that(TownAssessment.next_streak(6, 3, 103, 103)).is_equal(Vector2i(3, 103))
	assert_that(TownAssessment.next_streak(5, 9, 103, 104)).is_equal(Vector2i(0, -1))


func test_well_names_the_acre_to_look_at() -> void:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(112, 112, 2.0, Vector3.ZERO)
	add_child(world)
	var talk := WishingWellTalk.new(world, Game.inventory, _rng())
	talk.context = DialogueContext.new()
	var msg: int = talk.picked(WishingWellTalk.MSG_ASK, 0)
	assert_int(msg).is_equal(WishingWellTalk.MSG_TREE_LESS)
	assert_int(talk.context.frees.size()).is_equal(2)
	assert_str(talk.context.frees[0]).is_not_equal("Q")
	assert_bool(talk.summon_spirit).is_false()
	## Nothing to apologize for.
	assert_int(talk.picked(WishingWellTalk.MSG_ASK, 1)).is_equal(WishingWellTalk.MSG_NOTHING_TO_APOLOGIZE)
	assert_bool(talk.pick_step(WishingWellTalk.MSG_ASK, 1).is_empty()).is_true()
