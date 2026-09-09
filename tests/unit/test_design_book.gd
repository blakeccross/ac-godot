class_name TestDesignBook
extends GdUnitTestSuite

## `DesignBook` — original-design storage + Able Sisters shop state
## (`src/game/m_needlework.c`, `ac_needlework_indoor.c`).


func test_palettes_are_16x16_opaque() -> void:
	assert_int(NeedleworkPalettes.RAW.size()).is_equal(16)
	for p in 16:
		var cols := NeedleworkPalettes.colors(p)
		assert_int(cols.size()).is_equal(16)
		for c in cols:
			assert_float(c.a).is_equal(1.0)
	## palette 0, CI 0 = 0x525252 (the "erase" colour)
	assert_object(NeedleworkPalettes.color_at(0, 0)).is_equal(Color8(0x52, 0x52, 0x52))
	assert_object(NeedleworkPalettes.color_at(0, 15)).is_equal(Color8(0xFF, 0xFF, 0xFF))


func test_starter_seeding_matches_decomp_tables() -> void:
	var book := DesignBook.new()
	## mNW_InitMyOriginalPallet pal_table {0,8,7,7,0,0,0,0}
	assert_int(book.player[1].palette).is_equal(8)
	assert_int(book.player[2].palette).is_equal(7)
	## slots 4-7 blank
	assert_str(book.player[5].name).is_equal("blank")
	assert_bool(book.player[5].flag_set).is_false()
	## mNW_InitNeedleworkPelatteNo pal_table {7,1,10,3,6,0,6,7}
	assert_int(book.shop[0].palette).is_equal(7)
	assert_int(book.shop[2].palette).is_equal(10)
	assert_int(book.shop.size()).is_equal(8)
	for i in 8:
		assert_int(int(book.player_order[i])).is_equal(i)


func test_ci4_round_trip_is_lossless() -> void:
	var d := DesignPattern.blank()
	for y in 32:
		for x in 32:
			d.set_px(x, y, (x + y) & 0xF)
	var restored := DesignPattern.blank()
	restored.from_ci4(d.to_ci4())
	assert_bool(restored.pixels == d.pixels).is_true()


func test_copy_player_to_shop_is_one_way() -> void:
	var book := DesignBook.new()
	book.player[0].set_px(0, 0, 5)
	book.player[0].palette = 9
	book.copy_player_to_shop(2, 0)
	assert_int(book.shop[2].get_px(0, 0)).is_equal(5)
	assert_int(book.shop[2].palette).is_equal(9)
	## player unchanged
	book.shop[2].set_px(0, 0, 1)
	assert_int(book.player[0].get_px(0, 0)).is_equal(5)


func test_exchange_swaps_both_ways() -> void:
	var book := DesignBook.new()
	book.player[0].set_px(1, 1, 3)
	book.shop[1].set_px(1, 1, 7)
	book.exchange(1, 0)
	assert_int(book.player[0].get_px(1, 1)).is_equal(7)
	assert_int(book.shop[1].get_px(1, 1)).is_equal(3)


func test_buy_shop_into_player_overwrites_player_only() -> void:
	var book := DesignBook.new()
	book.shop[3].set_px(2, 2, 4)
	book.buy_shop_into_player(3, 5)
	assert_int(book.player[5].get_px(2, 2)).is_equal(4)


func test_order_swap_reorders_display_slots() -> void:
	var book := DesignBook.new()
	book.player[0].name = "A"
	book.player[1].name = "B"
	book.swap_player_order(0, 1)
	assert_str(book.resolved(0).name).is_equal("B")
	assert_str(book.resolved(1).name).is_equal("A")
	## contents untouched, only the table moved
	assert_str(book.player[0].name).is_equal("A")


func test_sable_day_advances_once_per_date_and_caps() -> void:
	var book := DesignBook.new()
	book.tick_sable_day("2026-09-08")
	book.tick_sable_day("2026-09-08")
	assert_int(book.sable_days).is_equal(1)
	for i in 20:
		book.tick_sable_day("2026-10-%02d" % (i + 1))
	assert_int(book.sable_days).is_equal(DesignBook.SABLE_DAYS_MAX)


func test_save_round_trips() -> void:
	var book := DesignBook.new()
	book.player[0].set_px(4, 4, 6)
	book.player[0].name = "Star"
	book.player[0].palette = 11
	book.swap_player_order(0, 3)
	book.tick_sable_day("2026-09-08")
	book.first_talk_done = true
	var restored := DesignBook.new()
	restored.apply_snapshot(book.to_save())
	assert_str(restored.player[0].name).is_equal("Star")
	assert_int(restored.player[0].get_px(4, 4)).is_equal(6)
	assert_int(restored.player[0].palette).is_equal(11)
	assert_int(int(restored.player_order[0])).is_equal(3)
	assert_int(restored.sable_days).is_equal(1)
	assert_bool(restored.first_talk_done).is_true()


func test_game_persists_designs_and_worn_slot() -> void:
	Game.designs.clear()
	Game.designs.player[2].name = "Custom"
	Game.designs.player[2].set_px(0, 0, 9)
	Game.worn_design_slot = 2
	var snapshot := Game.to_save()
	Game.designs.clear()
	Game.worn_design_slot = -1
	Game.apply_snapshot(snapshot)
	assert_str(Game.designs.player[2].name).is_equal("Custom")
	assert_int(Game.worn_design_slot).is_equal(2)
	Game.designs.clear()
	Game.worn_design_slot = -1
