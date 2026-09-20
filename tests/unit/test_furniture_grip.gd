class_name TestFurnitureGrip
extends GdUnitTestSuite

const TICK := 1.0 / 60.0

var _session: IndoorSession
var _chair: FurnitureData
var _table: FurnitureData


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()
	var room: Room = Game.interiors.room(&"player_main")
	room.placements.clear()
	Game.interiors.house(InteriorCatalog.PLAYER_HOUSE_ID).size_tier = House.SizeTier.LARGE
	Game.interiors.refresh_player_rooms()
	_session = IndoorSession.new()
	_session.bind(room)
	_chair = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	_table = ItemCatalog.get_item(&"wood_table") as FurnitureData


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func _place(data: FurnitureData, cell: Vector2i, facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH) -> FurniturePlacement:
	var entry: FurniturePlacement = _session.place(data, cell, facing)
	assert_that(entry).is_not_null()
	return entry


func _stand(cell: Vector2i) -> Vector3:
	var pos: Vector3 = _session.grid.cell_to_world(cell)
	pos.y = 0.1
	return pos


func _run(grip: FurnitureGrip, ticks: int, a_held: bool, stick: Vector2, pos: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i: int in ticks:
		out.append_array(grip.advance(TICK + 0.0001, _session, a_held, stick, pos))
	return out


func _ops(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for event: Dictionary in events:
		out.append(str(event["op"]))
	return out


## --- contact ------------------------------------------------------------------------------


func test_contact_needs_a_piece_in_front_and_close() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3))
	var hit: Dictionary = FurnitureGrip.find_contact(_session, _stand(Vector2i(3, 4)), WorldGrid.Facing.NORTH)
	assert_bool(hit.is_empty()).is_false()
	assert_that((hit["placement"] as FurniturePlacement).id).is_equal(chair.id)
	assert_that(hit["pivot"]).is_equal(Vector2i(3, 3))
	assert_bool(FurnitureGrip.find_contact(_session, _stand(Vector2i(3, 4)), WorldGrid.Facing.SOUTH).is_empty()).is_true()
	assert_bool(FurnitureGrip.find_contact(_session, _stand(Vector2i(3, 6)), WorldGrid.Facing.NORTH).is_empty()).is_true()


func test_contact_side_is_relative_to_the_way_the_piece_faces() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	assert_int(FurnitureGrip.side_of(chair, WorldGrid.Facing.NORTH)).is_equal(FurnitureGrip.ContactSide.FRONT)
	assert_int(FurnitureGrip.side_of(chair, WorldGrid.Facing.SOUTH)).is_equal(FurnitureGrip.ContactSide.BACK)
	chair.facing = WorldGrid.Facing.EAST
	assert_int(FurnitureGrip.side_of(chair, WorldGrid.Facing.WEST)).is_equal(FurnitureGrip.ContactSide.FRONT)


func test_press_grips_and_lines_up_with_the_piece() -> void:
	_place(_chair, Vector2i(3, 3))
	var grip := FurnitureGrip.new()
	var offset: Vector3 = _stand(Vector2i(3, 4)) + Vector3(0.5, 0.0, 0.3)
	var contact: Dictionary = grip.press(_session, offset, WorldGrid.Facing.NORTH)
	assert_bool(contact.is_empty()).is_false()
	assert_bool(grip.is_active()).is_true()
	var nice: Vector3 = contact["nice_pos"]
	assert_float(nice.z).is_equal_approx(_session.grid.cell_to_world(Vector2i(3, 4)).z, 0.001)
	assert_bool(grip.press(_session, offset, WorldGrid.Facing.NORTH).is_empty()).is_true()


func test_nothing_to_grip_in_open_floor() -> void:
	var grip := FurnitureGrip.new()
	assert_bool(grip.press(_session, _stand(Vector2i(3, 4)), WorldGrid.Facing.NORTH).is_empty()).is_true()
	assert_bool(grip.is_active()).is_false()


## --- tap versus hold ----------------------------------------------------------------------


func test_a_short_press_is_a_tap() -> void:
	_place(_chair, Vector2i(3, 3))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	var events: Array[Dictionary] = _run(grip, 5, true, Vector2.ZERO, pos)
	events.append_array(_run(grip, 1, false, Vector2.ZERO, pos))
	assert_array(_ops(events)).is_equal(["tap"])
	assert_bool(grip.is_active()).is_false()


func test_a_long_press_released_is_not_a_tap() -> void:
	_place(_chair, Vector2i(3, 3))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	_run(grip, FurnitureGrip.TAP_TICKS + 2, true, Vector2.ZERO, pos)
	assert_array(_ops(_run(grip, 1, false, Vector2.ZERO, pos))).is_equal(["release"])


## --- push ---------------------------------------------------------------------------------


func test_push_waits_out_the_timer_then_slides_one_unit() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	var early: Array[Dictionary] = _run(grip, FurnitureGrip.MOVE_TICKS, true, Vector2(0.0, -1.0), pos)
	assert_int(early.size()).is_equal(0)
	assert_that(chair.cell).is_equal(Vector2i(3, 3))
	var events: Array[Dictionary] = _run(grip, 2, true, Vector2(0.0, -1.0), pos)
	assert_array(_ops(events)).is_equal(["move"])
	assert_that(events[0]["kind"]).is_equal(&"push")
	assert_that(chair.cell).is_equal(Vector2i(3, 2))
	assert_that(_session.grid.occupant_at(Vector2i(3, 2))).is_equal(chair.id)
	assert_that(_session.grid.occupant_at(Vector2i(3, 3))).is_equal(&"")
	var player_to: Vector3 = events[0]["player_to"]
	assert_float(player_to.z - pos.z).is_equal_approx(-_session.grid.cell_size, 0.001)
	assert_int(grip.phase).is_equal(FurnitureGrip.Phase.BUSY)


func test_push_into_a_wall_puffs_and_needs_the_stick_released() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 1))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 2))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	var events: Array[Dictionary] = _run(grip, 18, true, Vector2(0.0, -1.0), pos)
	assert_array(_ops(events)).is_equal(["bubu"])
	assert_that(chair.cell).is_equal(Vector2i(3, 1))
	assert_bool(grip.need_neutral).is_true()
	## Still shoving: no retry until the stick comes back.
	assert_int(_run(grip, 40, true, Vector2(0.0, -1.0), pos).size()).is_equal(0)
	_run(grip, 1, true, Vector2.ZERO, pos)
	assert_bool(grip.need_neutral).is_false()


func test_push_is_blocked_by_other_furniture() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3))
	_place(_chair, Vector2i(3, 2))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	assert_array(_ops(_run(grip, 18, true, Vector2(0.0, -1.0), pos))).is_equal(["bubu"])
	assert_that(chair.cell).is_equal(Vector2i(3, 3))


func test_a_diagonal_stick_never_pushes() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	assert_int(_run(grip, 40, true, Vector2(0.7, -0.7), pos).size()).is_equal(0)
	assert_that(chair.cell).is_equal(Vector2i(3, 3))


func test_a_soft_stick_never_pushes() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	assert_int(_run(grip, 40, true, Vector2(0.0, -0.5), pos).size()).is_equal(0)
	assert_that(chair.cell).is_equal(Vector2i(3, 3))


func test_pushing_carries_what_sits_on_a_table() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3))
	var rider := FurniturePlacement.new()
	rider.id = &"rider"
	rider.furniture_id = _chair.id
	rider.cell = Vector2i(4, 3)
	rider.layer = 1
	_session.room.placements.append(rider)
	assert_bool(_session.move_placement(table.id, Vector2i(0, -1))).is_true()
	assert_that(table.cell).is_equal(Vector2i(3, 2))
	assert_that(rider.cell).is_equal(Vector2i(4, 2))


## --- pull ---------------------------------------------------------------------------------


func test_pull_drags_the_piece_toward_the_player_who_backs_up() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	var events: Array[Dictionary] = _run(grip, 18, true, Vector2(0.0, 1.0), pos)
	assert_array(_ops(events)).is_equal(["move"])
	assert_that(events[0]["kind"]).is_equal(&"pull")
	assert_that(chair.cell).is_equal(Vector2i(3, 4))
	var player_to: Vector3 = events[0]["player_to"]
	assert_float(player_to.z - pos.z).is_equal_approx(_session.grid.cell_size, 0.001)


func test_pull_needs_room_behind_the_player() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 6))
	var grip := FurnitureGrip.new()
	## Large house: carpet ends at row 8, so stand on the last row and pull toward the wall.
	var pos: Vector3 = _stand(Vector2i(3, 7))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	assert_array(_ops(_run(grip, 18, true, Vector2(0.0, 1.0), pos))).is_equal(["move"])
	grip.finish_busy()
	var wall_pos: Vector3 = _stand(Vector2i(3, 8))
	var second := FurnitureGrip.new()
	second.press(_session, wall_pos, WorldGrid.Facing.NORTH)
	assert_array(_ops(_run(second, 18, true, Vector2(0.0, 1.0), wall_pos))).is_equal(["bubu"])
	assert_that(chair.cell).is_equal(Vector2i(3, 7))


func test_grip_returns_after_a_move_and_can_go_again() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 4))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 5))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	_run(grip, 18, true, Vector2(0.0, -1.0), pos)
	assert_that(chair.cell).is_equal(Vector2i(3, 3))
	grip.finish_busy()
	var again: Vector3 = _stand(Vector2i(3, 4))
	assert_array(_ops(_run(grip, 18, true, Vector2(0.0, -1.0), again))).is_equal(["move"])
	assert_that(chair.cell).is_equal(Vector2i(3, 2))


## --- rotate -------------------------------------------------------------------------------


func test_stick_sideways_turns_a_small_piece_in_place() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	## Player is south of it: dragging the near edge east is a left (counter-clockwise) turn.
	var events: Array[Dictionary] = _run(grip, 2, true, Vector2(1.0, 0.0), pos)
	assert_array(_ops(events)).is_equal(["rotate"])
	assert_bool(bool(events[0]["ccw"])).is_true()
	assert_that(chair.facing).is_equal(WorldGrid.Facing.EAST)
	assert_that(chair.cell).is_equal(Vector2i(3, 3))


func test_turning_the_other_way_is_clockwise() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	var events: Array[Dictionary] = _run(grip, 2, true, Vector2(-1.0, 0.0), pos)
	assert_bool(bool(events[0]["ccw"])).is_false()
	assert_that(chair.facing).is_equal(WorldGrid.Facing.WEST)


func test_one_turn_per_flick() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	_run(grip, 2, true, Vector2(1.0, 0.0), pos)
	grip.finish_busy()
	assert_int(_run(grip, 30, true, Vector2(1.0, 0.0), pos).size()).is_equal(0)
	_run(grip, 1, true, Vector2.ZERO, pos)
	assert_array(_ops(_run(grip, 2, true, Vector2(1.0, 0.0), pos))).is_equal(["rotate"])
	assert_that(chair.facing).is_equal(WorldGrid.Facing.NORTH)


func test_a_long_piece_swings_about_the_end_being_held() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	assert_int(_session.grid.cells_of(table.id).size()).is_equal(2)
	assert_bool(_session.grid.cells_of(table.id).has(Vector2i(4, 3))).is_true()
	## Held at the west end (3,3), turning counter-clockwise: the east end swings up to (3,2).
	assert_bool(_session.rotate_about(table.id, 1, Vector2i(3, 3))).is_true()
	var cells: Array[Vector2i] = _session.grid.cells_of(table.id)
	assert_bool(cells.has(Vector2i(3, 3))).is_true()
	assert_bool(cells.has(Vector2i(3, 2))).is_true()
	assert_bool(cells.has(Vector2i(4, 3))).is_false()
	assert_that(table.facing).is_equal(WorldGrid.Facing.EAST)


func test_the_pivot_is_whichever_end_is_held() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	assert_bool(_session.rotate_about(table.id, 1, Vector2i(4, 3))).is_true()
	var cells: Array[Vector2i] = _session.grid.cells_of(table.id)
	assert_bool(cells.has(Vector2i(4, 3))).is_true()
	assert_bool(cells.has(Vector2i(4, 4))).is_true()


func test_a_long_piece_will_not_swing_through_furniture() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	_place(_chair, Vector2i(4, 2))
	## Counter-clockwise from the west end sweeps (3,2) and (4,2): the chair is in the way.
	assert_bool(_session.rotate_about(table.id, 1, Vector2i(3, 3))).is_false()
	assert_that(table.facing).is_equal(WorldGrid.Facing.SOUTH)
	assert_bool(_session.grid.cells_of(table.id).has(Vector2i(4, 3))).is_true()


func test_a_long_piece_will_not_swing_onto_the_player() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	assert_bool(_session.rotate_about(table.id, 1, Vector2i(3, 3), Vector2i(3, 2))).is_false()


func test_a_long_piece_will_not_swing_into_a_wall() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 1), WorldGrid.Facing.SOUTH)
	assert_bool(_session.rotate_about(table.id, 1, Vector2i(3, 1))).is_false()


func test_riders_turn_with_the_table() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var rider := FurniturePlacement.new()
	rider.id = &"rider"
	rider.furniture_id = _chair.id
	rider.cell = Vector2i(4, 3)
	rider.layer = 1
	_session.room.placements.append(rider)
	assert_bool(_session.rotate_about(table.id, 1, Vector2i(3, 3))).is_true()
	assert_that(rider.cell).is_equal(Vector2i(3, 2))


func test_rotating_a_table_by_hand_reports_failure_cleanly() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	_place(_chair, Vector2i(3, 2))
	var grip := FurnitureGrip.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	grip.press(_session, pos, WorldGrid.Facing.NORTH)
	assert_array(_ops(_run(grip, 2, true, Vector2(1.0, 0.0), pos))).is_equal(["bubu"])
	assert_that(table.facing).is_equal(WorldGrid.Facing.SOUTH)


## --- pick up (B) --------------------------------------------------------------------------


func test_pickup_finds_the_piece_in_front_and_prefers_what_sits_on_it() -> void:
	var table: FurniturePlacement = _place(_table, Vector2i(3, 3))
	var pos: Vector3 = _stand(Vector2i(3, 4))
	assert_that(FurnitureGrip.find_pickup(_session, pos, WorldGrid.Facing.NORTH)).is_equal(table.id)
	assert_that(FurnitureGrip.find_pickup(_session, pos, WorldGrid.Facing.SOUTH)).is_equal(&"")
	var rider := FurniturePlacement.new()
	rider.id = &"rider"
	rider.furniture_id = _chair.id
	rider.cell = Vector2i(3, 3)
	rider.layer = 1
	_session.room.placements.append(rider)
	assert_that(FurnitureGrip.find_pickup(_session, pos, WorldGrid.Facing.NORTH)).is_equal(&"rider")


func test_pickup_reach_is_56_gx() -> void:
	_place(_chair, Vector2i(3, 3))
	assert_that(FurnitureGrip.find_pickup(_session, _stand(Vector2i(3, 5)), WorldGrid.Facing.NORTH)).is_equal(&"")


## --- furniture cap (`aMR_GetSceneFurnitureMax`) -----------------------------------------


func test_each_floor_has_its_furniture_limit() -> void:
	var house: House = Game.interiors.player_house()
	var caps: Array[int] = [32, 48, 64, 64]
	for tier: int in caps.size():
		house.size_tier = tier as House.SizeTier
		assert_int(PlayerHouse.furniture_cap(PlayerHouse.MAIN, house)).is_equal(caps[tier])
	assert_int(PlayerHouse.furniture_cap(PlayerHouse.UPPER, house)).is_equal(48)
	assert_int(PlayerHouse.furniture_cap(PlayerHouse.BASEMENT, house)).is_equal(64)
	assert_int(PlayerHouse.furniture_cap(&"npc_0", house)).is_equal(0)


func test_a_full_room_takes_no_more() -> void:
	var house: House = Game.interiors.player_house()
	house.size_tier = House.SizeTier.SMALL
	house.next_size_tier = House.SizeTier.SMALL
	Game.interiors.refresh_player_rooms()
	var room: Room = Game.interiors.room(&"player_main")
	room.placements.clear()
	_session = IndoorSession.new()
	_session.bind(room)
	assert_int(_session.capacity()).is_equal(32)
	for i: int in 32:
		var filler := FurniturePlacement.new()
		filler.id = StringName("filler_%d" % i)
		filler.furniture_id = _chair.id
		filler.layer = 1
		filler.cell = Vector2i(1, 1)
		room.placements.append(filler)
	assert_bool(_session.is_full()).is_true()
	assert_that(_session.place(_chair, Vector2i(2, 2), WorldGrid.Facing.SOUTH)).is_null()
	room.placements.pop_back()
	assert_that(_session.place(_chair, Vector2i(2, 2), WorldGrid.Facing.SOUTH)).is_not_null()


## --- the player's heading versus grid facings ---------------------------------------------


func test_the_players_heading_maps_east_and_west_the_way_the_motor_turns() -> void:
	## `PlayerLocomotion.facing` is `atan2(x, z)`: walking east is +90°, west −90°.
	assert_that(WorldGrid.facing_from_player_yaw(atan2(1.0, 0.0))).is_equal(WorldGrid.Facing.EAST)
	assert_that(WorldGrid.facing_from_player_yaw(atan2(-1.0, 0.0))).is_equal(WorldGrid.Facing.WEST)
	assert_that(WorldGrid.facing_from_player_yaw(atan2(0.0, 1.0))).is_equal(WorldGrid.Facing.SOUTH)
	assert_that(WorldGrid.facing_from_player_yaw(atan2(0.0, -1.0))).is_equal(WorldGrid.Facing.NORTH)
	for facing: int in 4:
		var f := facing as WorldGrid.Facing
		assert_that(WorldGrid.facing_from_player_yaw(WorldGrid.yaw_for_furniture(f))).is_equal(f)


func test_a_piece_can_be_gripped_from_the_east_and_west_sides() -> void:
	var chair: FurniturePlacement = _place(_chair, Vector2i(4, 4))
	for spec: Array in [
		[Vector2i(3, 4), WorldGrid.Facing.EAST, Vector2(1.0, 0.0)],
		[Vector2i(5, 4), WorldGrid.Facing.WEST, Vector2(-1.0, 0.0)],
	]:
		var grip := FurnitureGrip.new()
		var pos: Vector3 = _stand(spec[0] as Vector2i)
		var face: WorldGrid.Facing = spec[1] as WorldGrid.Facing
		assert_bool(grip.press(_session, pos, face).is_empty()).is_false()
		var events: Array[Dictionary] = _run(grip, 18, true, spec[2] as Vector2, pos)
		assert_array(_ops(events)).is_equal(["move"])
		grip.reset()
		chair.cell = Vector2i(4, 4)
		_session.grid.remove(chair.id)
		_session.grid.place(chair.id, chair.cell, Vector2i.ONE, chair.facing, WorldGrid.PlaceKind.FURNITURE)
