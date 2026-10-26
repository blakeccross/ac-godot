class_name TestGroundItemLabel
extends GdUnitTestSuite

## Stopping on a ground item names it (`Player_actor_Get_itemNo_forWindow`, `m_watch_my_step`).

const CELL := Vector2i(5, 5)
const AHEAD := Vector2i(5, 6)


func _grid() -> WorldGrid:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3.ZERO)
	return grid


func _place(grid: WorldGrid, cell: Vector2i, id: StringName) -> void:
	grid.place(id, cell, Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)


func test_standing_on_an_item_names_it() -> void:
	var grid := _grid()
	_place(grid, CELL, &"apple")
	var spots: Array = [GroundItemLabel.make(&"apple", Vector3(11.0, 0.0, 11.0), "Apple")]
	assert_str(GroundItemLabel.label_for(Vector3(11.0, 0.0, 11.0), 0.0, grid, spots, true)).is_equal("Apple")


func test_a_weed_underfoot_names_nothing() -> void:
	var grid := _grid()
	_place(grid, CELL, &"weed")
	var spots: Array = [GroundItemLabel.make(&"weed", Vector3(11.0, 0.0, 11.0), "Weed", false, true)]
	assert_str(GroundItemLabel.label_for(Vector3(11.0, 0.0, 11.0), 0.0, grid, spots, true)).is_equal("")


func test_an_item_one_unit_ahead_is_not_named() -> void:
	## The 35-ahead probe sees it and throws it out (only a signboard counts there).
	var grid := _grid()
	_place(grid, AHEAD, &"apple")
	var spots: Array = [GroundItemLabel.make(&"apple", Vector3(11.0, 0.0, 13.0), "Apple")]
	assert_str(GroundItemLabel.label_for(Vector3(11.0, 0.0, 11.0), 0.0, grid, spots, true)).is_equal("")


func test_a_signboard_one_unit_ahead_is_named() -> void:
	var grid := _grid()
	_place(grid, AHEAD, &"sign")
	var spots: Array = [GroundItemLabel.make(&"sign", Vector3(11.0, 0.0, 13.0), "Signboard", true)]
	assert_str(GroundItemLabel.label_for(Vector3(11.0, 0.0, 11.0), 0.0, grid, spots, true)).is_equal("Signboard")


func test_the_middle_probe_names_an_item_just_ahead() -> void:
	## Player toward the front of their unit: 20 GX ahead lands on the next item, 10 GX does not.
	var grid := _grid()
	_place(grid, AHEAD, &"apple")
	var spots: Array = [GroundItemLabel.make(&"apple", Vector3(11.0, 0.0, 13.0), "Apple")]
	assert_str(GroundItemLabel.label_for(Vector3(11.0, 0.0, 11.6), 0.0, grid, spots, true)).is_equal("Apple")


func test_furniture_is_named_outdoors_only() -> void:
	var grid := _grid()
	_place(grid, CELL, &"chair")
	var spots: Array = [GroundItemLabel.make(&"chair", Vector3(11.0, 0.0, 11.0), "Chair", false, false, true)]
	var at := Vector3(11.0, 0.0, 11.0)
	assert_str(GroundItemLabel.label_for(at, 0.0, grid, spots, true)).is_equal("Chair")
	assert_str(GroundItemLabel.label_for(at, 0.0, grid, spots, false)).is_equal("")


func test_an_item_above_the_reach_is_missed() -> void:
	var grid := _grid()
	_place(grid, CELL, &"apple")
	var spots: Array = [GroundItemLabel.make(&"apple", Vector3(11.0, 1.0, 11.0), "Apple")]
	assert_str(GroundItemLabel.label_for(Vector3(11.0, 0.0, 11.0), 0.0, grid, spots, true)).is_equal("")


func test_the_name_sits_in_the_font_window() -> void:
	## Cut width 55 → scale 0.25 (`(55 * 0.875 - 17.5) / 122.5`). On the 320×240 ortho
	## the glyph top-left is the `mFont_SetLineStrings` formula, and the tail hangs
	## back toward the player.
	assert_float(GroundItemLabel.name_scale(55.0)).is_equal_approx(0.25, 0.0001)
	assert_float(GroundItemLabel.name_scale(0.0)).is_equal(0.0)
	var view := Vector2(320, 240)
	var frame := GroundItemLabel.frame_at(Vector2(100, 100), Vector2(1, 1), view, 55.0)
	assert_vector(frame.origin).is_equal_approx(Vector2(140, 58), Vector2.ONE * 0.001)
	assert_vector(frame.body_size).is_equal_approx(Vector2(70, 24.75), Vector2.ONE * 0.001)
	assert_vector(frame.body_position).is_equal_approx(Vector2(105, 45.625), Vector2.ONE * 0.001)
	assert_vector(frame.text_position).is_equal_approx(Vector2(115.75, 51.375), Vector2.ONE * 0.001)
	assert_int(frame.font_px).is_equal(14)
	assert_vector(frame.tip_position).is_equal_approx(Vector2(119, 84), Vector2.ONE * 0.001)
	assert_vector(frame.tip_size).is_equal(Vector2(16, 8))
	assert_vector(frame.joint_position).is_equal_approx(Vector2(127, 72), Vector2.ONE * 0.001)
	## A 1280×720 view keeps the 40×42 nudge square (×3), instead of stretching x by 4.
	assert_float(GroundItemLabel.units(Vector2(1280, 720))).is_equal(3.0)
	var wide := GroundItemLabel.frame_at(Vector2(400, 300), Vector2(1, 1), Vector2(1280, 720), 55.0)
	assert_vector(wide.origin).is_equal_approx(Vector2(520, 174), Vector2.ONE * 0.001)
	assert_vector(wide.body_size).is_equal_approx(Vector2(210, 74.25), Vector2.ONE * 0.001)
	assert_int(wide.font_px).is_equal(42)


func test_the_box_flips_away_from_the_screen_edge() -> void:
	assert_vector(GroundItemLabel.flip(210.0, 100.0, 0.0)).is_equal(Vector2(-1.0, 1.0))
	assert_vector(GroundItemLabel.flip(150.0, 100.0, 0.5)).is_equal(Vector2(-1.0, 1.0))
	assert_vector(GroundItemLabel.flip(150.0, 100.0, -0.5)).is_equal(Vector2(1.0, 1.0))
	assert_vector(GroundItemLabel.flip(100.0, 40.0, 0.0)).is_equal(Vector2(1.0, -1.0))


func test_the_name_fades_in_after_the_lead_and_out_when_you_leave() -> void:
	var popup := GroundItemLabel.Reveal.new()
	popup.advance(GroundItemLabel.LEAD_IN, "Apple", false)
	assert_int(popup.phase).is_equal(GroundItemLabel.Reveal.Phase.SHOWN)
	assert_float(popup.opacity).is_equal(0.0)
	assert_float(popup.text_alpha()).is_equal(0.0)
	popup.advance(DecompTime.TICK_SEC, "Apple", false)
	assert_float(popup.opacity).is_equal_approx(0.25, 0.001)
	for _i: int in 8:
		popup.advance(DecompTime.TICK_SEC, "Apple", false)
	assert_float(popup.opacity).is_equal_approx(1.0, 0.001)
	popup.advance(DecompTime.TICK_SEC, "", false)
	assert_int(popup.phase).is_equal(GroundItemLabel.Reveal.Phase.CLOSING)
	## Close steps 0.1 then 0.005 off a full window.
	assert_float(popup.opacity).is_equal_approx(0.895, 0.02)
	popup.advance(1.0, "", false)
	assert_int(popup.phase).is_equal(GroundItemLabel.Reveal.Phase.HIDDEN)
	assert_str(popup.label).is_equal("")


func test_the_indoor_camera_swing_holds_the_name() -> void:
	var cam := FollowCamera.new()
	auto_free(cam)
	add_child(cam)
	cam.suspend()
	assert_bool(cam.name_window_held()).is_false()
	assert_bool(cam.step_indoor(-1, 0)).is_true()
	assert_bool(cam.name_window_held()).is_true()
	cam._physics_process(59.0 * DecompTime.TICK_SEC)
	assert_bool(cam.name_window_held()).is_true()
	cam._physics_process(DecompTime.TICK_SEC)
	assert_bool(cam.name_window_held()).is_false()
