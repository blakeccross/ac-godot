extends GdUnitTestSuite

## `TagLayout` against frames captured from the original (Dolphin, GAFE01): where the name plate
## and the verb window land for a few slots. Positions are screen units about the centre, y up;
## the measured centres carry about 1.5 units of reading error.

const TOLERANCE := 1.6


func _verb_centre(slot: Vector2, row: int, name_width: float, words: int, widest: float) -> Array:
	var item: TagLayout.Tag = TagLayout.item_tag(slot, row, name_width)
	var verb: TagLayout.Tag = TagLayout.verb_tag(item, words, widest)
	return [verb.base + verb.body_ofs, item]


func test_name_plate_hangs_right_of_a_left_slot() -> void:
	## "bad plaid shirt" (92 wide in the ROM font) on the top-left slot.
	var item: TagLayout.Tag = TagLayout.item_tag(Vector2(-77, -10), 0, 92.0)
	assert_int(item.arrow_dir).is_equal(1)
	var centre: Vector2 = item.base + item.body_ofs
	assert_float(centre.x).is_equal_approx(-34.0, TOLERANCE)
	assert_float(centre.y).is_equal_approx(-25.0, TOLERANCE)


func test_name_plate_flips_left_when_it_would_leave_the_screen() -> void:
	## "yellow pansy bag" (102) still fits to the right of the top-right slot (reference frame)...
	var fits: TagLayout.Tag = TagLayout.item_tag(Vector2(19, -10), 0, 102.0)
	assert_int(fits.arrow_dir).is_equal(1)
	## ... a much longer name does not.
	var wide: TagLayout.Tag = TagLayout.item_tag(Vector2(19, -10), 0, 150.0)
	assert_int(wide.arrow_dir).is_equal(2)
	assert_float(wide.body_ofs.x).is_less(0.0)


func test_verb_window_below_the_plate_on_the_top_row() -> void:
	## Grab / Drop / Quit under "bad plaid shirt": measured centre (-14.4, -68.1).
	var got: Array = _verb_centre(Vector2(-77, -10), 0, 92.0, 3, 28.0)
	var centre: Vector2 = got[0]
	assert_float(centre.x).is_equal_approx(-14.4, TOLERANCE)
	assert_float(centre.y).is_equal_approx(-68.1, TOLERANCE + 1.0)


func test_verb_window_stays_on_screen_in_the_right_column() -> void:
	## "yellow pansy bag" on the top-right slot: measured centre (87.25, -68.75).
	var got: Array = _verb_centre(Vector2(19, -10), 0, 102.0, 3, 31.0)
	var centre: Vector2 = got[0]
	assert_float(centre.x).is_equal_approx(87.25, 3.0)
	assert_float(centre.y).is_equal_approx(-68.75, TOLERANCE + 1.0)


func test_verb_window_goes_above_the_plate_on_the_middle_row() -> void:
	## "red tulip bag" on the left slot of row 1: measured centre (-20.8, -7.5).
	var got: Array = _verb_centre(Vector2(-77, -34), 1, 79.0, 3, 31.0)
	var centre: Vector2 = got[0]
	assert_float(centre.x).is_equal_approx(-20.8, TOLERANCE)
	assert_float(centre.y).is_equal_approx(-7.5, TOLERANCE)
