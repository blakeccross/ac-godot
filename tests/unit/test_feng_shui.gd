extends GdUnitTestSuite

## `m_huusui_room_ovl.c` and the shop's ABC tiers (`mSP_GetItemList`).

const Y := FengShui.Colour.YELLOW
const R := FengShui.Colour.RED
const O := FengShui.Colour.ORANGE
const G := FengShui.Colour.GREEN
const L := FengShui.Colour.LUCKY


func _cells(arr: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Variant in arr:
		out.append(c)
	return out


func test_colours_pay_on_their_side() -> void:
	## Medium room: units 1–6, walls at 0 and 7 (`ut_max` 8), bands two units deep.
	assert_that(FengShui.score_piece(_cells([Vector2i(1, 4)]), Y, false, 0, 8)).is_equal(Vector2i(4, 0))
	assert_that(FengShui.score_piece(_cells([Vector2i(6, 4)]), Y, false, 0, 8)).is_equal(Vector2i.ZERO)
	assert_that(FengShui.score_piece(_cells([Vector2i(6, 4)]), R, false, 0, 8)).is_equal(Vector2i(0, 8))
	assert_that(FengShui.score_piece(_cells([Vector2i(4, 1)]), O, false, 0, 8)).is_equal(Vector2i(2, 4))
	assert_that(FengShui.score_piece(_cells([Vector2i(4, 6)]), G, false, 0, 8)).is_equal(Vector2i(2, 4))
	## Lucky pieces pay anywhere, even mid-room.
	assert_that(FengShui.score_piece(_cells([Vector2i(4, 4)]), L, false, 0, 8)).is_equal(Vector2i(4, 8))
	## A 1×2 half out of the band earns nothing.
	assert_that(FengShui.score_piece(_cells([Vector2i(2, 4), Vector2i(3, 4)]), Y, false, 0, 8)).is_equal(Vector2i.ZERO)
	## A corner piece counts for both walls it sits in.
	assert_that(FengShui.score_piece(_cells([Vector2i(1, 1)]), O, false, 0, 8)).is_equal(Vector2i(2, 4))


func test_small_rooms_band_one_unit_for_small_pieces() -> void:
	assert_that(FengShui.score_piece(_cells([Vector2i(1, 2)]), Y, false, 0, 6)).is_equal(Vector2i(4, 0))
	assert_that(FengShui.score_piece(_cells([Vector2i(2, 2)]), Y, false, 0, 6)).is_equal(Vector2i.ZERO)


func test_a_face_turned_to_the_wall_costs() -> void:
	## Against the west wall, facing west (`rot` 3).
	assert_that(FengShui.score_piece(_cells([Vector2i(1, 4)]), Y, true, 3, 8)).is_equal(Vector2i(4 - 10, -5))
	assert_that(FengShui.score_piece(_cells([Vector2i(1, 4)]), Y, true, 0, 8)).is_equal(Vector2i(4, 0))
	## In the band but off the wall: no penalty.
	assert_that(FengShui.score_piece(_cells([Vector2i(2, 4)]), Y, true, 3, 8)).is_equal(Vector2i(4, 0))


func test_goods_power_is_capped_and_halved_up() -> void:
	assert_int(FengShui.finish_goods(9)).is_equal(5)
	assert_int(FengShui.finish_goods(80)).is_equal(20)
	assert_int(FengShui.finish_goods(-5)).is_equal(-2)


func test_goods_power_moves_nooks_odds() -> void:
	assert_that(ShopGoods.tier_cutoffs(0)).is_equal(Vector2i(5, 40))
	assert_that(ShopGoods.tier_cutoffs(20)).is_equal(Vector2i(25, 60))
	assert_that(ShopGoods.tier_cutoffs(-10)).is_equal(Vector2i(5, 30))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var rare: int = 0
	for _i: int in 2000:
		if ShopGoods.roll_tier(20, rng) == ShopGoods.Tier.RARE:
			rare += 1
	assert_int(rare).is_between(400, 600)


func test_each_session_deals_the_lists_their_tiers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	ShopGoods.deal_priorities(rng)
	for kind: String in ShopGoods.ABC_KINDS:
		var order: Array = ShopGoods.priorities_of(kind)
		var sorted: Array = order.duplicate()
		sorted.sort()
		assert_array(sorted).is_equal([0, 1, 2])
	if ShopGoods.has_disc_lists():
		var picks: Array[StringName] = ShopGoods.select("ftr", 5, -1, 0, rng)
		assert_int(picks.size()).is_equal(5)
		var rare: Array[StringName] = ShopGoods.tier_list("ftr", ShopGoods.Tier.RARE)
		assert_bool(rare.is_empty()).is_false()
