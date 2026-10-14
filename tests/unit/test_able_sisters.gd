class_name TestAbleSisters
extends GdUnitTestSuite

## Able Sisters behaviour: villagers wearing shop designs (`NeedleworkTrend`), the
## trade ops' effect on wearers, Sable's story pick, Mabel's goodbye trigger and the
## design album (`DesignBook.album`).

const MABEL := preload("res://scenes/world/interiors/mabel.gd")
const ALBUM := preload("res://scenes/ui/design_album_overlay.gd")


func _states(n: int) -> Array[VillagerState]:
	var out: Array[VillagerState] = []
	for i in n:
		var s := VillagerState.new()
		s.villager_id = StringName("v%d" % i)
		out.append(s)
	return out


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- trend ----------------------------------------------------------------

func test_trend_counts_cloth_and_umbrella_wearers_per_display() -> void:
	var s := _states(5)
	s[0].cloth_design = 2
	s[1].cloth_design = 2
	s[2].cloth_design = 0
	s[3].umbrella_design = 1
	assert_int(NeedleworkTrend.count(s, 2)).is_equal(2)
	assert_int(NeedleworkTrend.count(s, 0)).is_equal(1)
	assert_int(NeedleworkTrend.count(s, 5)).is_equal(1)  ## stand 1 = shop slot 5
	assert_int(NeedleworkTrend.count(s, 1)).is_equal(0)
	var top: Array = NeedleworkTrend.top(s, false, _rng(1))
	assert_int(top[0]).is_equal(2)
	assert_int(top[1]).is_equal(2)
	var umb: Array = NeedleworkTrend.top(s, true, _rng(1))
	assert_int(umb[0]).is_equal(5)
	assert_int(umb[1]).is_equal(1)


func test_nobody_wearing_picks_a_random_display_with_zero_count() -> void:
	var top: Array = NeedleworkTrend.top(_states(3), true, _rng(7))
	assert_int(top[1]).is_equal(0)
	assert_bool(int(top[0]) >= 4 and int(top[0]) <= 7).is_true()


func test_trend_delete_sends_only_that_displays_wearers_home() -> void:
	var s := _states(4)
	s[0].cloth_design = 1
	s[1].cloth_design = 1
	s[2].cloth_design = 3
	s[3].umbrella_design = 1
	assert_int(NeedleworkTrend.delete(s, 1)).is_equal(2)
	assert_int(s[0].cloth_design).is_equal(-1)
	assert_int(s[2].cloth_design).is_equal(3)
	assert_int(s[3].umbrella_design).is_equal(1)  ## umbrella 1 is a different display
	assert_int(NeedleworkTrend.delete(s, 5)).is_equal(1)
	assert_int(s[3].umbrella_design).is_equal(-1)


func test_reaction_table_matches_react_rate_table() -> void:
	## Walk the cumulative table (0.2, .1, .1, .1, .1, .05, .1, .05 → 0.8).
	var total := 0.0
	for r in NeedleworkTrend.REACT_RATES:
		total += r
	assert_float(total).is_equal_approx(0.8, 0.0001)
	var hits := {}
	var rng := _rng(3)
	for _i in 4000:
		var react := NeedleworkTrend.roll_reaction(rng)
		hits[react] = int(hits.get(react, 0)) + 1
	## ~20% fall past the table, ~10% change into a shop shirt.
	assert_int(int(hits.get(-1, 0))).is_between(650, 950)
	assert_int(int(hits.get(NeedleworkTrend.React.CHG_SP_CLOTH, 0))).is_between(300, 500)


func test_reactions_change_clothes_like_the_greeting_code() -> void:
	var s := _states(3)
	var rng := _rng(11)
	NeedleworkTrend.apply_reaction(NeedleworkTrend.React.CHG_SP_CLOTH, s[0], s[1], s, rng)
	var first := s[0].cloth_design
	assert_bool(first >= 0 and first <= 3).is_true()
	NeedleworkTrend.apply_reaction(NeedleworkTrend.React.CHG_SP_CLOTH, s[0], s[1], s, rng)
	assert_int(s[0].cloth_design).is_not_equal(first)  ## always a different design
	NeedleworkTrend.apply_reaction(NeedleworkTrend.React.COPY_CLOTH, s[0], s[1], s, rng)
	assert_int(s[1].cloth_design).is_equal(s[0].cloth_design)
	## B already matches → a third villager picks it up.
	NeedleworkTrend.apply_reaction(NeedleworkTrend.React.COPY_CLOTH, s[0], s[1], s, rng)
	assert_int(s[2].cloth_design).is_equal(s[0].cloth_design)
	NeedleworkTrend.apply_reaction(NeedleworkTrend.React.CHG_SP_UMB, s[1], s[0], s, rng)
	assert_int(s[1].umbrella_design).is_between(0, 3)
	NeedleworkTrend.apply_reaction(NeedleworkTrend.React.RESET_CLOTH_AND_UMB, s[1], s[0], s, rng)
	assert_int(s[1].cloth_design).is_equal(-1)
	assert_int(s[1].umbrella_design).is_equal(-1)
	NeedleworkTrend.apply_reaction(NeedleworkTrend.React.SET_CLOTH, s[2], s[0], s, rng)
	assert_int(s[2].cloth_design).is_equal(-1)


func test_designs_spread_over_days_of_greetings() -> void:
	## Shirts come and go (normal shirts get copied too), but over a couple of weeks
	## someone always picks one up.
	var s := _states(8)
	var rng := _rng(5)
	var most := 0
	for _day in 14:
		NeedleworkTrend.daily_greetings(s, rng, 1)
		var wearing := 0
		for st in s:
			if st.cloth_design >= 0:
				wearing += 1
		most = maxi(most, wearing)
	assert_int(most).is_greater(0)


func test_wear_survives_the_villager_save() -> void:
	var st := VillagerState.new()
	st.villager_id = &"bob"
	st.cloth_design = 2
	st.umbrella_design = 0
	var back := VillagerState.new()
	back.apply_snapshot(st.to_save())
	assert_int(back.cloth_design).is_equal(2)
	assert_int(back.umbrella_design).is_equal(0)


func test_display_and_exchange_undo_wearers_but_buying_does_not() -> void:
	var book := DesignBook.new()
	var s := _states(3)
	for st in s:
		st.cloth_design = 1
	## "I want it!" copies the display; it stays up, so wearers keep it.
	assert_bool(MABEL.apply_trade(book, "buy", 1, 0, s)).is_true()
	assert_int(NeedleworkTrend.count(s, 1)).is_equal(3)
	assert_array(Array(book.resolved(0).pixels)).is_equal(Array(book.shop[1].pixels))
	## "Display mine!" replaces it (`aNNW_trend_delete_cloth`).
	assert_bool(MABEL.apply_trade(book, "display", 1, 2, s)).is_true()
	assert_int(NeedleworkTrend.count(s, 1)).is_equal(0)
	for st in s:
		st.umbrella_design = 2
	assert_bool(MABEL.apply_trade(book, "exchange", 6, 3, s)).is_true()
	assert_int(NeedleworkTrend.count(s, 6)).is_equal(0)
	assert_bool(MABEL.apply_trade(book, "nope", 0, 0, s)).is_false()


# --- Sable ----------------------------------------------------------------

func test_first_talk_of_the_day_tells_the_next_chapter() -> void:
	var rng := _rng(2)
	## `aNNW_get_make_sister_message` counts today itself: 3 days so far + today = 4.
	assert_int(NeedleworkTalk.pick_story_row(3, true, rng)).is_equal(5)
	assert_int(NeedleworkTalk.pick_story_row(4, true, rng)).is_equal(9)
	assert_int(NeedleworkTalk.pick_story_row(6, true, rng)).is_equal(17)
	## Talking again the same day gives a follow-up row.
	assert_int(NeedleworkTalk.pick_story_row(4, false, rng)).is_between(6, 8)
	assert_int(NeedleworkTalk.pick_story_row(9, false, rng)).is_between(21, 23)
	assert_int(NeedleworkTalk.pick_story_row(0, true, rng)).is_between(0, 4)


func test_story_parts_alternate_sable_mabel_sable_with_text_for_each() -> void:
	assert_str(NeedleworkTalk.story_speaker(0)).is_equal("Sable")
	assert_str(NeedleworkTalk.story_speaker(1)).is_equal("Mabel")
	assert_str(NeedleworkTalk.story_speaker(2)).is_equal("Sable")
	var rng := _rng(1)
	for row in 24:
		var ids := NeedleworkTalk.story_line_ids(row, rng)
		var authored: Array = NeedleworkTalk.STORY_TEXT[row]
		assert_int(authored.size()).override_failure_message("row %d" % row).is_equal(ids.size())
		for now in ids.size():
			assert_str(NeedleworkTalk.story_text(row, now)).is_not_empty()


func test_sable_day_counter_ticks_once_a_day_and_caps() -> void:
	var book := DesignBook.new()
	book.tick_sable_day("2026-01-01")
	book.tick_sable_day("2026-01-01")
	assert_int(book.sable_days).is_equal(1)
	for d in 20:
		book.tick_sable_day("2026-02-%02d" % (d + 1))
	assert_int(book.sable_days).is_equal(DesignBook.SABLE_DAYS_MAX)


# --- Mabel ------------------------------------------------------------------

func test_goodbye_fires_facing_the_exit_from_the_row_inside() -> void:
	var room: Room = InteriorCatalog.room_template(&"needlework")
	var session := IndoorSession.new()
	session.bind(room)
	var grid := session.grid
	var door := room.door_cell
	var inside := grid.cell_to_world(Vector2i(door.x, door.y - 1))
	var yaw_to_door := atan2(grid.cell_to_world(door).x - inside.x, grid.cell_to_world(door).z - inside.z)
	assert_bool(MABEL.facing_exit(session, inside, yaw_to_door)).is_true()
	## facing back into the shop (just walked in) → no goodbye
	assert_bool(MABEL.facing_exit(session, inside, yaw_to_door + PI)).is_false()
	## two rows in → no goodbye
	var deeper := grid.cell_to_world(Vector2i(door.x, door.y - 2))
	assert_bool(MABEL.facing_exit(session, deeper, yaw_to_door)).is_false()


# --- album ------------------------------------------------------------------

func test_album_is_eight_folders_of_twelve_blank_designs() -> void:
	var book := DesignBook.new()
	assert_int(book.album.size()).is_equal(DesignBook.ALBUM_PAGES)
	assert_int((book.album[0] as Array).size()).is_equal(DesignBook.ALBUM_PER_PAGE)
	assert_bool(book.album_design(7, 11).flag_set).is_false()
	assert_str(book.album_names[3]).is_equal("")


func test_album_swaps_and_round_trips_through_the_save() -> void:
	var book := DesignBook.new()
	var mine := book.resolved(0).duplicate_design()
	book.album_swap_player(2, 5, 0)
	assert_array(Array(book.album_design(2, 5).pixels)).is_equal(Array(mine.pixels))
	assert_bool(book.resolved(0).flag_set).is_false()  ## a blank came back
	book.album_swap(2, 5, 7, 0)
	assert_str(book.album_design(7, 0).name).is_equal(mine.name)
	book.set_folder_name(7, "Summer shirts and more")
	assert_str(book.album_names[7]).is_equal("Summer shirt")  ## 12 characters
	var back := DesignBook.new()
	back.apply_snapshot(book.to_save())
	assert_str(back.album_design(7, 0).name).is_equal(mine.name)
	assert_array(Array(back.album_design(7, 0).pixels)).is_equal(Array(mine.pixels))
	assert_str(back.album_names[7]).is_equal("Summer shirt")


func test_album_hand_swaps_follow_mco_swap_image() -> void:
	Game.designs.clear()
	var first := Game.designs.resolved(0).duplicate_design()
	var second := Game.designs.resolved(1).duplicate_design()
	## pockets ↔ pockets = display-order swap
	ALBUM.swap([ALBUM.Region.MINE, -1, 0], [ALBUM.Region.MINE, -1, 1])
	assert_str(Game.designs.resolved(0).name).is_equal(second.name)
	## album ↔ pockets, either way round
	ALBUM.swap([ALBUM.Region.ALBUM, 3, 4], [ALBUM.Region.MINE, -1, 1])
	assert_str(Game.designs.album_design(3, 4).name).is_equal(first.name)
	ALBUM.swap([ALBUM.Region.MINE, -1, 1], [ALBUM.Region.ALBUM, 3, 4])
	assert_str(Game.designs.resolved(1).name).is_equal(first.name)
	Game.designs.clear()


func test_mabel_speaks_the_rom_lines_when_the_bank_is_there() -> void:
	var fallback := "authored"
	assert_array(NeedleworkTalk.pages(0x7FFFFF, fallback)).is_equal([fallback])
	if NeedleworkTalk.line(NeedleworkTalk.GREETING_REPEAT) == null:
		return
	## 0x3005: one page, then its event and choice (Mabel's own menu answers).
	var lead: Array[String] = NeedleworkTalk.pages(NeedleworkTalk.GREETING_REPEAT, fallback)
	assert_int(lead.size()).is_equal(1)
	assert_str(lead[0]).contains("What do you need?")
	## 0x2FE7: two pages before the menu, with the player's name tag.
	var broke: Array[String] = NeedleworkTalk.pages(NeedleworkTalk.MSG_DESIGN_NO_MONEY, fallback)
	assert_int(broke.size()).is_equal(2)
	assert_str(broke[0]).contains("{player}")
	## "Any tips?" hands the plate Mabel → Sable → Mabel.
	var speakers: Array = []
	for row: Array in NeedleworkTalk.listen_pages():
		if speakers.is_empty() or speakers[-1] != row[0]:
			speakers.append(row[0])
	assert_array(speakers).is_equal(["Mabel", "Sable", "Mabel"])
