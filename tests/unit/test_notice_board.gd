extends GdUnitTestSuite

## `m_notice.c` / `m_notice_ovl.c`: the community board.


func test_seed_posts_the_four_handbills() -> void:
	var b := NoticeBoard.new()
	b.seed(2001, 7, 15, 12, 0)
	assert_int(b.count()).is_equal(4)
	if MailBank.has_bank():
		assert_str(str(b.posts[3]["text"])).contains("Adding Messages")
	assert_int(int(b.posts[0]["year"])).is_equal(2001)


func test_a_full_board_drops_its_oldest_post() -> void:
	var b := NoticeBoard.new()
	for i: int in NoticeBoard.POST_COUNT + 2:
		b.write({"text": "post %d" % i, "year": 2001, "month": 1, "day": 1, "hour": 6, "minute": 0})
	assert_int(b.count()).is_equal(NoticeBoard.POST_COUNT)
	assert_str(str(b.posts[0]["text"])).is_equal("post 2")
	assert_str(str(b.posts[NoticeBoard.POST_COUNT - 1]["text"])).is_equal("post 16")


func test_auto_dates_move_with_the_equinoxes_and_sort() -> void:
	var dates: Array = NoticeBoard.auto_dates(2001)
	assert_int(dates.size()).is_equal(41)
	var prev := 0
	for row: Array in dates:
		var key: int = int(row[1]) * 32 + int(row[2])
		assert_int(key).is_greater_equal(prev)
		prev = key
	for row: Array in dates:
		if int(row[0]) == 0x08:
			## Vernal equinox 2001 is March 20th; the schedule goes up the day before.
			assert_int(int(row[1])).is_equal(3)
			assert_int(int(row[2])).is_equal(EventDates.vernal_equinox_day(2001) - 1)


func test_auto_write_posts_what_came_due_since_the_last_check() -> void:
	var b := NoticeBoard.new()
	b.seed(2001, 6, 20, 12, 0)
	## Chip's last tourney post (June 23rd), the Fireworks notice (25th), July weather (1st).
	var n: int = b.auto_write(2001, 7, 2, 9, {0: "Town", 1: "Nook's Cranny"})
	assert_int(n).is_equal(3)
	assert_int(b.count()).is_equal(7)
	assert_int(int(b.posts[4]["day"])).is_equal(23)
	assert_int(int(b.posts[5]["month"])).is_equal(6)
	assert_int(int(b.posts[5]["day"])).is_equal(25)
	assert_int(int(b.posts[5]["hour"])).is_equal(6)
	## Nothing new the same day, and a notice's own day counts only from 06:00.
	assert_int(b.auto_write(2001, 7, 2, 10)).is_equal(0)
	assert_int(b.auto_write(2001, 7, 5, 5)).is_equal(0)
	assert_int(b.auto_write(2001, 7, 5, 6)).is_equal(1)


func test_a_long_absence_posts_only_the_latest_five() -> void:
	var b := NoticeBoard.new()
	b.seed(2001, 1, 2, 12, 0)
	assert_int(b.auto_write(2001, 12, 31, 12)).is_equal(NoticeBoard.AUTO_WRITE_MAX)
	assert_int(int(b.posts[b.count() - 1]["month"])).is_equal(12)


func test_save_round_trip() -> void:
	var b := NoticeBoard.new()
	b.seed(2001, 7, 15, 12, 30)
	var c := NoticeBoard.new()
	c.apply_snapshot(b.to_save())
	assert_int(c.count()).is_equal(4)
	assert_int(int(c.posts[0]["minute"])).is_equal(30)
	assert_that(c.checked).is_equal(b.checked)


func test_overlay_turns_pages_and_jumps_to_the_first() -> void:
	var ui: NoticeBoardOverlay = auto_free(load("res://scenes/ui/notice_board_overlay.tscn").instantiate())
	add_child(ui)
	Game.notice_board = NoticeBoard.new()
	Game.notice_board.seed(Clock.year, Clock.month, Clock.day, Clock.hour, Clock.minute)
	ui.open()
	assert_int(ui.now_page).is_equal(3)
	ui.turn(-1)
	assert_int(ui.now_page).is_equal(2)
	for _i: int in 60:
		ui._tick()
	assert_int(ui.mode).is_equal(NoticeBoardOverlay.Mode.READ)
	## Down: back to entry 1 in (at most three) steps.
	ui.turn(-ui.now_page)
	for _i: int in 120:
		ui._tick()
	assert_int(ui.now_page).is_equal(0)
	assert_int(ui.disp_page).is_equal(0)


func test_writing_a_post_adds_it_and_closes() -> void:
	var ui: NoticeBoardOverlay = auto_free(load("res://scenes/ui/notice_board_overlay.tscn").instantiate())
	add_child(ui)
	Game.notice_board = NoticeBoard.new()
	Game.notice_board.seed(Clock.year, Clock.month, Clock.day, Clock.hour, Clock.minute)
	ui.open()
	ui._start_write()
	assert_int(ui.now_page).is_equal(NoticeBoard.POST_COUNT)
	ui._on_written("Hello, town!")
	assert_int(Game.notice_board.count()).is_equal(5)
	assert_str(str(Game.notice_board.posts[4]["text"])).is_equal("Hello, town!")
	ui._on_writer_closed()
	assert_bool(ui.is_open()).is_false()


func test_throwing_it_out_goes_back_to_the_latest_post() -> void:
	var ui: NoticeBoardOverlay = auto_free(load("res://scenes/ui/notice_board_overlay.tscn").instantiate())
	add_child(ui)
	Game.notice_board = NoticeBoard.new()
	Game.notice_board.seed(Clock.year, Clock.month, Clock.day, Clock.hour, Clock.minute)
	ui.open()
	ui._start_write()
	ui._on_writer_closed()
	for _i: int in 60:
		ui._tick()
	assert_bool(ui.is_open()).is_true()
	assert_int(ui.mode).is_equal(NoticeBoardOverlay.Mode.READ)
	assert_int(ui.now_page).is_equal(3)
	assert_int(Game.notice_board.count()).is_equal(4)
