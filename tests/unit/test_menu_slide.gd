extends GdUnitTestSuite

## `mSM_move_Move` / `mSM_move_menu` (`m_submenu_ovl.c`).


func _run(slide: MenuSlide, limit: int = 200) -> Array[float]:
	var trail: Array[float] = []
	for _i in limit:
		var done := slide.step()
		trail.append(slide.position.x)
		if done:
			break
	return trail


func test_slide_in_from_the_right_glides_to_rest() -> void:
	var slide: MenuSlide = auto_free(MenuSlide.new())
	slide.slide_in(MenuSlide.Dir.IN_RIGHT)
	assert_float(slide.position.x).is_equal(300.0)
	var trail := _run(slide)
	assert_float(trail.back()).is_equal(0.0)
	assert_bool(slide.is_moving()).is_false()
	## 37.5 units a frame until it passes 120, then it slows.
	assert_float(trail[0]).is_equal(262.0)
	for i in range(1, trail.size()):
		assert_bool(trail[i] <= trail[i - 1]).is_true()
	var first_gap: float = 300.0 - trail[0]
	var last_gap: float = trail[trail.size() - 2] - trail.back()
	assert_bool(last_gap < first_gap).is_true()


func test_slide_out_speeds_away_and_reports_done() -> void:
	var slide: MenuSlide = auto_free(MenuSlide.new())
	slide.slide_in(MenuSlide.Dir.IN_TOP)
	while not slide.step():
		pass
	assert_float(slide.position.y).is_equal(0.0)
	var done := [false]
	slide.slide_out(MenuSlide.Dir.OUT_TOP, func() -> void: done[0] = true)
	var steps: int = 0
	while not slide.step():
		steps += 1
	assert_float(slide.position.y).is_equal(300.0)
	assert_bool(done[0]).is_true()
	assert_int(steps).is_less(40)


func test_slide_in_from_the_bottom_rises() -> void:
	var slide: MenuSlide = auto_free(MenuSlide.new())
	slide.slide_in(MenuSlide.Dir.IN_BOTTOM)
	assert_float(slide.position.y).is_equal(-300.0)
	slide.step()
	assert_bool(slide.position.y > -300.0).is_true()
