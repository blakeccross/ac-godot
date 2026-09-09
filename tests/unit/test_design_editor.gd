extends GdUnitTestSuite

## Design editor tool maths + Able trade / trend ops
## (`m_design_ovl.c`, `ac_npc_needlework_talk.c_inc`).

const EDITOR := preload("res://scenes/ui/design_editor_overlay.tscn")


func _editor() -> Node:
	var e: Node = auto_free(EDITOR.instantiate())
	add_child(e)
	e.open(0)
	## start from a clean canvas — slot 0's seed is a striped starter design
	e._work.fill(DesignPattern.BLANK_INDEX)
	e._undo = e._work.duplicate()
	return e


func test_flood_fill_stops_at_a_border() -> void:
	var e := _editor()
	# frame a 6x6 box in colour 3, flood the inside with 5
	e._paint = 3
	for i in range(10, 16):
		e._work[10 * 32 + i] = 3
		e._work[15 * 32 + i] = 3
	for j in range(10, 16):
		e._work[j * 32 + 10] = 3
		e._work[j * 32 + 15] = 3
	e._paint = 5
	e._cursor = Vector2i(12, 12)
	e._do_fill()
	assert_int(e._work[12 * 32 + 12]).is_equal(5)
	assert_int(e._work[11 * 32 + 11]).is_equal(5)
	# outside the border is untouched
	assert_int(e._work[0]).is_equal(DesignPattern.BLANK_INDEX)
	assert_int(e._work[20 * 32 + 20]).is_equal(DesignPattern.BLANK_INDEX)


func test_fill_all_paints_every_texel() -> void:
	var e := _editor()
	e._paint = 7
	e._fill_mode = 5
	e._do_fill()
	for v in e._work:
		assert_int(v).is_equal(7)


func test_bresenham_line_is_connected() -> void:
	var e := _editor()
	e._paint = 4
	e._pen_size = 0
	e._line(Vector2i(2, 2), Vector2i(20, 8))
	assert_int(e._work[2 * 32 + 2]).is_equal(4)
	assert_int(e._work[8 * 32 + 20]).is_equal(4)
	# every row the line passes through has at least one painted texel
	var rows := {}
	for y in 32:
		for x in 32:
			if e._work[y * 32 + x] == 4:
				rows[y] = true
	for y in range(2, 9):
		assert_bool(rows.has(y)).override_failure_message("row %d not drawn" % y).is_true()


func test_rect_outline_vs_filled() -> void:
	var e := _editor()
	e._paint = 6
	e._shape = 0
	e._waku_anchor = Vector2i(4, 4)
	e._cursor = Vector2i(10, 10)
	e._do_shape()
	assert_int(e._work[4 * 32 + 4]).is_equal(6)   # corner
	assert_int(e._work[7 * 32 + 7]).is_equal(DesignPattern.BLANK_INDEX)  # hollow centre
	e._shape = 2
	e._do_shape()
	assert_int(e._work[7 * 32 + 7]).is_equal(6)   # now filled


func test_stamp_places_a_glyph() -> void:
	var e := _editor()
	e._paint = 9
	e._stamp = 3  # square: solid border
	e._cursor = Vector2i(16, 16)
	e._stamp_glyph()
	var painted := 0
	for v in e._work:
		if v == 9:
			painted += 1
	assert_int(painted).is_greater(20)


func test_undo_is_a_reversible_swap() -> void:
	var e := _editor()
	var canvas0: PackedByteArray = e._work.duplicate()
	e._snapshot()
	e._paint = 2
	e._cursor = Vector2i(5, 5)
	e._set_px(5, 5)
	assert_int(e._work[5 * 32 + 5]).is_equal(2)
	e._do_undo()
	assert_array(Array(e._work)).is_equal(Array(canvas0))
	e._do_undo()  # redo
	assert_int(e._work[5 * 32 + 5]).is_equal(2)


func test_paint_index_wraps_1_to_15() -> void:
	var e := _editor()
	e._paint = 15
	e._step_paint(1)
	assert_int(e._paint).is_equal(1)
	e._step_paint(-1)
	assert_int(e._paint).is_equal(15)


func test_save_writes_pixels_palette_and_flag() -> void:
	var e := _editor()
	e._palette_no = 11
	e._paint = 8
	e._fill_mode = 5
	e._do_fill()
	e._open_prompt()
	e._resolve_prompt(0)  # "Save it"
	var d: DesignPattern = Game.designs.player[Game.designs.resolved_index(0)]
	assert_int(d.palette).is_equal(11)
	assert_bool(d.flag_set).is_true()
	assert_int(d.pixels[100]).is_equal(8)
	assert_bool(e.is_open()).is_false()


func test_trade_display_and_exchange_touch_the_right_slots() -> void:
	Game.designs.clear()
	var mine := DesignPattern.generate(DesignPattern.Motif.CHECK, 4, 2, 9)
	Game.designs.player[Game.designs.resolved_index(3)].copy_from(mine)
	Game.designs.copy_player_to_shop(1, 3)
	assert_array(Array(Game.designs.shop[1].pixels)).is_equal(Array(mine.pixels))
	assert_int(Game.designs.trend_eligible[1]).is_equal(1)

	var shop_before: PackedByteArray = Game.designs.shop[2].pixels.duplicate()
	var player_before: PackedByteArray = Game.designs.player[Game.designs.resolved_index(0)].pixels.duplicate()
	Game.designs.exchange(2, 0)
	assert_array(Array(Game.designs.shop[2].pixels)).is_equal(Array(player_before))
	assert_array(Array(Game.designs.player[Game.designs.resolved_index(0)].pixels)).is_equal(Array(shop_before))


func test_trend_grows_only_for_displayed_designs_and_resets_on_delete() -> void:
	Game.designs.clear()
	Game.designs.copy_player_to_shop(0, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for day in 20:
		Game.designs.tick_trend("2026-01-%02d" % (day + 1), 8, rng)
	assert_int(Game.designs.trend_count[0]).is_greater(0)
	assert_int(Game.designs.trend_count[3]).is_equal(0)  # never displayed
	Game.designs.trend_delete(0)
	assert_int(Game.designs.trend_count[0]).is_equal(0)
	assert_int(Game.designs.trend_eligible[0]).is_equal(0)


func test_mabel_menu_options_match_the_rom() -> void:
	## `aNNW_set_6_ways` choice strings (select.json 489/490/488/49/435/50).
	var data: DialogueData = DialogueCatalog.conversation(&"mabel_menu")
	assert_that(data).is_not_null()
	data.ensure_loaded()
	var menu: Dictionary = data.node(&"menu")
	assert_str(str(menu.get("prompt", ""))).contains("Ohhh, yes?")
	var labels: Array = (menu.get("options", []) as Array).map(func(o): return str(o.get("text", "")))
	assert_array(labels).is_equal([
		"Design a pattern", "Save a pattern", "Any suggestions?",
		"What's this?", "Other things", "Nothing...",
	])


func test_trend_line_tiers() -> void:
	assert_str(NeedleworkTalk.trend_line("X", 0, false)).contains("caught on")
	assert_str(NeedleworkTalk.trend_line("X", 1, false)).contains("just starting")
	assert_str(NeedleworkTalk.trend_line("X", 3, false)).contains("turning heads")
	assert_str(NeedleworkTalk.trend_line("X", 9, true)).contains("THE umbrella print")


func test_save_round_trip_keeps_trend_state() -> void:
	Game.designs.clear()
	Game.designs.copy_player_to_shop(2, 0)
	Game.designs.trend_count[2] = 4
	var snap: Dictionary = Game.designs.to_save()
	var fresh := DesignBook.new()
	fresh.apply_snapshot(snap)
	assert_int(fresh.trend_count[2]).is_equal(4)
	assert_int(fresh.trend_eligible[2]).is_equal(1)
