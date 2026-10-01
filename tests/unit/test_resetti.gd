extends GdUnitTestSuite

## `mCD_SetResetInfo` / `aRSD_first_set_init` / `ac_npc_majin*`.

const PATH := "user://test_resetti_save.json"


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	SaveService.delete_save(PATH)
	Game.reset_session()


func test_visits_follow_the_count() -> void:
	assert_int(int(ResettiVisit.visit(1)[1])).is_equal(0x3A38)
	assert_str(String(ResettiVisit.visit(5)[0])).is_equal(String(ResettiVisit.DON))
	assert_bool(bool(ResettiVisit.visit(4)[2])).is_true()
	assert_int(ResettiVisit.normalized(8)).is_equal(8)
	assert_int(ResettiVisit.normalized(9)).is_equal(6)
	assert_int(ResettiVisit.normalized(11)).is_equal(8)
	assert_int(ResettiVisit.normalized(12)).is_equal(6)


func test_an_open_session_counts_as_a_reset() -> void:
	assert_int(SaveService.save_game(PATH)).is_equal(OK)
	assert_int(SaveService.load_game(PATH)).is_equal(OK)
	Game.note_reset(SaveService.last_reset_code)
	assert_bool(Game.reset_flag).is_false()
	## Loaded and quit without saving.
	SaveService.mark_session_open(Game.reset_count, PATH)
	Game.reset_session()
	assert_int(SaveService.load_game(PATH)).is_equal(OK)
	Game.note_reset(SaveService.last_reset_code)
	assert_bool(Game.reset_flag).is_true()
	assert_int(Game.reset_count).is_equal(1)
	## The raised count is in the file before any save.
	SaveService.mark_session_open(Game.reset_count, PATH)
	Game.reset_session()
	SaveService.load_game(PATH)
	assert_int(Game.reset_count).is_equal(1)
	Game.note_reset(SaveService.last_reset_code)
	assert_int(Game.reset_count).is_equal(2)
	## A proper save clears it.
	SaveService.save_game(PATH)
	SaveService.load_game(PATH)
	Game.note_reset(SaveService.last_reset_code)
	assert_bool(Game.reset_flag).is_false()
	assert_int(Game.reset_count).is_equal(2)
