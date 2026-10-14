extends GdUnitTestSuite

## The diary (`m_diary_ovl.c`): a page per month, 31 lines, 992 characters.


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func test_pages_are_capped_like_the_original() -> void:
	var many: PackedStringArray = []
	for i: int in 40:
		many.append("line %d" % i)
	var kept: String = DiaryOverlay.clip("\n".join(many))
	assert_int(kept.split("\n").size()).is_equal(DiaryOverlay.LINES)
	assert_int(DiaryOverlay.clip("x".repeat(2000)).length()).is_equal(DiaryOverlay.ENTRY_SIZE)


func test_a_page_per_month_survives_a_save() -> void:
	Game.diary[4] = "Caught a coelacanth."
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Game.to_save()))
	Game.diary.clear()
	Game.apply_snapshot(snap)
	assert_str(DiaryOverlay.entry(4)).is_equal("Caught a coelacanth.")
	assert_str(DiaryOverlay.entry(5)).is_equal("")


func test_the_notebooks_are_diaries() -> void:
	var note := FurnitureData.new()
	note.id = FtrCatalog.item_id(1087)
	if FtrCatalog.available():
		assert_bool(FurnitureUse.is_diary(note)).is_true()
	var chair := FurnitureData.new()
	chair.id = &"wood_chair"
	assert_bool(FurnitureUse.is_diary(chair)).is_false()


func test_a_notebook_on_the_floor_is_not_read() -> void:
	var floor_note := FurniturePlacement.new()
	floor_note.layer = 0
	assert_bool(FurnitureUse._diary_open_here(floor_note)).is_false()


func test_a_housemates_diary_reads_from_their_saved_pages() -> void:
	Game.roster.current = 0
	Game.diary[4] = "Mine."
	Game.roster.slots[1] = {"player_name": "Ann", "diary": {"4": "Ann's page."}}
	assert_str(DiaryOverlay.entry(4, 1)).is_equal("Ann's page.")
	assert_str(DiaryOverlay.entry(4, 0)).is_equal("Mine.")
	assert_str(DiaryOverlay.entry(4)).is_equal("Mine.")
	Game.visiting_slot = 1
	assert_int(FurnitureUse.diary_owner()).is_equal(1)
