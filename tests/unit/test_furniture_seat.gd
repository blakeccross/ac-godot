class_name TestFurnitureSeat
extends GdUnitTestSuite

const TICK := 1.0 / 60.0

var _session: IndoorSession
var _chair: FurnitureData
var _sofa: FurnitureData
var _bed: FurnitureData


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
	_sofa = ItemCatalog.furniture_for_visual(&"int_sum_sofa01")
	_bed = ItemCatalog.furniture_for_visual(&"int_sum_bed01")


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func _stand(cell: Vector2i) -> Vector3:
	var pos: Vector3 = _session.grid.cell_to_world(cell)
	pos.y = 0.1
	return pos


func _walk_into(seat: FurnitureSeat, ticks: int, pos: Vector3, face: WorldGrid.Facing, stick: Vector2) -> Dictionary:
	var result: Dictionary = {}
	for _i: int in ticks:
		result = seat.poll(TICK + 0.0001, _session, pos, face, stick)
		if not result.is_empty():
			return result
	return result


func test_walking_into_the_front_of_a_chair_sits_after_the_hold() -> void:
	_session.place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var seat := FurnitureSeat.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	var early: Dictionary = _walk_into(seat, FurnitureSeat.HOLD_TICKS, pos, WorldGrid.Facing.NORTH, Vector2(0.0, -1.0))
	assert_bool(early.is_empty()).is_true()
	var hit: Dictionary = _walk_into(seat, 3, pos, WorldGrid.Facing.NORTH, Vector2(0.0, -1.0))
	assert_bool(hit.is_empty()).is_false()
	assert_int(hit["kind"]).is_equal(FurnitureSeat.Rest.SIT)
	var seat_pos: Vector3 = hit["pos"]
	var center: Vector3 = _session.grid.cell_to_world(Vector2i(3, 3))
	assert_float(seat_pos.x).is_equal_approx(center.x, 0.001)
	assert_float(seat_pos.z).is_equal_approx(center.z, 0.001)
	## Sits with its back to where you came from.
	assert_that(hit["yaw_facing"]).is_equal(WorldGrid.Facing.SOUTH)


func test_a_chair_only_takes_a_seat_from_its_front() -> void:
	_session.place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var seat := FurnitureSeat.new()
	## From behind (north of it, facing south).
	var pos: Vector3 = _stand(Vector2i(3, 2))
	assert_bool(_walk_into(seat, 40, pos, WorldGrid.Facing.SOUTH, Vector2(0.0, 1.0)).is_empty()).is_true()
	## From the side.
	var side: Vector3 = _stand(Vector2i(2, 3))
	assert_bool(_walk_into(seat, 40, side, WorldGrid.Facing.EAST, Vector2(1.0, 0.0)).is_empty()).is_true()


func test_a_soft_or_slanted_stick_never_sits() -> void:
	_session.place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var seat := FurnitureSeat.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	assert_bool(_walk_into(seat, 60, pos, WorldGrid.Facing.NORTH, Vector2(0.0, -0.5)).is_empty()).is_true()
	assert_bool(_walk_into(seat, 60, pos, WorldGrid.Facing.NORTH, Vector2(0.5, -0.86)).is_empty()).is_true()


func test_the_hold_resets_when_the_stick_lets_go() -> void:
	_session.place(_chair, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	var seat := FurnitureSeat.new()
	var pos: Vector3 = _stand(Vector2i(3, 4))
	_walk_into(seat, 10, pos, WorldGrid.Facing.NORTH, Vector2(0.0, -1.0))
	_walk_into(seat, 1, pos, WorldGrid.Facing.NORTH, Vector2.ZERO)
	assert_int(seat.sit_ticks).is_equal(0)


func test_a_sofa_takes_a_seat_from_the_front() -> void:
	assert_bool(_sofa.is_sittable()).is_true()
	assert_bool(FurnitureSeat.can_sit_from(_sofa, FurnitureGrip.ContactSide.FRONT)).is_true()
	assert_bool(FurnitureSeat.can_sit_from(_sofa, FurnitureGrip.ContactSide.BACK)).is_false()


func test_a_four_way_chair_takes_a_seat_from_any_side() -> void:
	var stool := FurnitureData.new()
	stool.contact = FurnitureData.Contact.CHAIR_ANY
	for side: int in 4:
		assert_bool(FurnitureSeat.can_sit_from(stool, side)).is_true()


func test_a_table_never_sits() -> void:
	var table: FurnitureData = ItemCatalog.get_item(&"wood_table") as FurnitureData
	assert_bool(FurnitureSeat.can_sit_from(table, FurnitureGrip.ContactSide.FRONT)).is_false()


func test_walking_across_a_bed_lies_down() -> void:
	assert_bool(_bed.is_bed()).is_true()
	## A single bed is a 2×1 piece (the inferred stub is 1×1).
	_bed.footprint = Vector2i(2, 1)
	_bed.shape = FurnitureData.Shape.TYPE_B
	var entry: FurniturePlacement = _session.place(_bed, Vector2i(3, 3), WorldGrid.Facing.SOUTH)
	assert_that(entry).is_not_null()
	assert_int(_session.grid.cells_of(entry.id).size()).is_equal(2)
	var seat := FurnitureSeat.new()
	## Long axis runs east–west, so it is entered from the north or south side.
	var hit: Dictionary = _walk_into(seat, 30, _stand(Vector2i(3, 4)), WorldGrid.Facing.NORTH, Vector2(0.0, -1.0))
	assert_bool(hit.is_empty()).is_false()
	assert_int(hit["kind"]).is_equal(FurnitureSeat.Rest.LIE)
	assert_that(hit["head"]).is_equal(FurnitureSeat.head_direction(entry.facing, _session.grid))
	## Not from the end.
	var end_seat := FurnitureSeat.new()
	assert_bool(_walk_into(end_seat, 30, _stand(Vector2i(2, 3)), WorldGrid.Facing.EAST, Vector2(1.0, 0.0)).is_empty()).is_true()


func test_head_direction_follows_the_bed() -> void:
	var grid := WorldGrid.new()
	## `aMR_GetBedHeadDirect`: facing 0° → left, 90° → down, 180° → right, 270° → up.
	assert_that(FurnitureSeat.head_direction(WorldGrid.Facing.SOUTH, grid)).is_equal(WorldGrid.Facing.WEST)
	assert_that(FurnitureSeat.head_direction(WorldGrid.Facing.EAST, grid)).is_equal(WorldGrid.Facing.SOUTH)
	assert_that(FurnitureSeat.head_direction(WorldGrid.Facing.NORTH, grid)).is_equal(WorldGrid.Facing.EAST)
	assert_that(FurnitureSeat.head_direction(WorldGrid.Facing.WEST, grid)).is_equal(WorldGrid.Facing.NORTH)


func test_standing_up_steps_out_the_front_when_clear() -> void:
	var seat_pos: Vector3 = _session.grid.cell_to_world(Vector2i(3, 3))
	var spot: Dictionary = FurnitureSeat.stand_spot(_session, seat_pos, WorldGrid.Facing.SOUTH)
	assert_bool(spot.is_empty()).is_false()
	var out: Vector3 = spot["pos"]
	assert_float(out.z - seat_pos.z).is_equal_approx(FurnitureSeat.STAND_STEP, 0.001)


func test_standing_up_is_refused_when_boxed_in() -> void:
	_session.place(_chair, Vector2i(3, 4), WorldGrid.Facing.SOUTH)
	var seat_pos: Vector3 = _session.grid.cell_to_world(Vector2i(3, 3))
	assert_bool(FurnitureSeat.stand_spot(_session, seat_pos, WorldGrid.Facing.SOUTH).is_empty()).is_true()


func test_bed_exit_returns_to_the_side_you_came_from() -> void:
	var approach: Vector3 = _stand(Vector2i(3, 5))
	var spot: Dictionary = FurnitureSeat.bed_exit_spot(_session, approach)
	assert_bool(spot.is_empty()).is_false()
	assert_that(_session.grid.world_to_cell(spot["pos"])).is_equal(Vector2i(3, 5))
