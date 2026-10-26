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
	Game.resident.diary[4] = "Caught a coelacanth."
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Game.to_save()))
	Game.resident.diary.clear()
	Game.apply_snapshot(snap)
	assert_str(DiaryOverlay.entry(4)).is_equal("Caught a coelacanth.")
	assert_str(DiaryOverlay.entry(5)).is_equal("")


func test_the_notebooks_are_diaries() -> void:
	var note := FurnitureData.new()
	note.id = FurnitureCatalog.item_id(1087)
	if FurnitureCatalog.available():
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
	Game.resident.diary[4] = "Mine."
	Game.roster.slots[1] = {"player_name": "Ann", "diary": {"4": "Ann's page."}}
	assert_str(DiaryOverlay.entry(4, 1)).is_equal("Ann's page.")
	assert_str(DiaryOverlay.entry(4, 0)).is_equal("Mine.")
	assert_str(DiaryOverlay.entry(4)).is_equal("Mine.")
	Game.roster.visiting = 1
	assert_int(FurnitureUse.diary_owner()).is_equal(1)


## Without a calendar the diary opens straight away on this month, on the diary of whoever's
## house it is (`open(month, owner)`; the owner was once passed as the month).
func test_without_a_calendar_the_diary_opens_on_this_month() -> void:
	TestIsolation.forget_groups(get_tree(), [CalendarOverlay.GROUP, DiaryOverlay.GROUP] as Array[StringName])
	var diary: DiaryOverlay = auto_free((load("res://scenes/ui/diary_overlay.tscn") as PackedScene).instantiate())
	add_child(diary)
	await get_tree().process_frame
	Clock.month = 7
	Game.roster.visiting = 2
	assert_bool(FurnitureUse.open_diary(self)).is_true()
	assert_bool(diary.is_open()).is_true()
	assert_int(diary.month).is_equal(7)
	Game.roster.visiting = -1
