class_name TestRoomItems
extends GdUnitTestSuite

## Things put down in your house (`RoomItems`): floor units, table tops, the HRA's clutter.

var _session: IndoorSession
var _room: Room


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	_room = Game.interiors.room(&"player_main")
	_room.placements.clear()
	_session = IndoorSession.new()
	_session.bind(_room)
	Game.bind_interior(_session)


func after_test() -> void:
	Game.bind_interior(null)
	Game.reset_session()


func _inner(dx: int, dz: int) -> Vector2i:
	return _room.inner_origin + Vector2i(dx, dz)


func test_an_item_goes_on_the_free_floor_in_front() -> void:
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	var entry: FurniturePlacement = RoomItems.drop(_session, _inner(1, 1), apple)
	assert_object(entry).is_not_null()
	assert_that(entry.cell).is_equal(_inner(1, 1))
	assert_int(entry.layer).is_equal(0)
	assert_bool(RoomItems.is_loose(entry)).is_true()
	assert_str(String(_session.grid.occupant_at(_inner(1, 1)))).is_equal(String(entry.id))
	## The next one finds the unit beside it.
	var other: FurniturePlacement = RoomItems.drop(_session, _inner(1, 1), apple)
	assert_that(other.cell).is_not_equal(_inner(1, 1))
	assert_int(RoomItems.count(_room)).is_equal(2)
	## Furniture can't go where it lies.
	var chair: FurnitureData = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	assert_bool(_session.can_place(chair, _inner(1, 1), WorldGrid.Facing.SOUTH)).is_false()


func test_a_table_top_holds_one_item() -> void:
	var table: FurnitureData = ItemCatalog.get_item(&"wood_table") as FurnitureData
	var t: FurniturePlacement = _session.place(table, _inner(2, 2), WorldGrid.Facing.SOUTH)
	assert_object(t).is_not_null()
	var shell: ItemData = ItemCatalog.get_item(&"conch")
	var on_top: FurniturePlacement = RoomItems.drop(_session, _inner(2, 2), shell)
	assert_int(on_top.layer).is_equal(1)
	assert_that(on_top.cell).is_equal(_inner(2, 2))
	## Pushing the table carries it along.
	assert_bool(_session.move_placement(t.id, Vector2i(-1, 0))).is_true()
	assert_that(on_top.cell).is_equal(_inner(1, 2))


func test_picking_up_takes_it_off_the_room_and_it_saves() -> void:
	var entry: FurniturePlacement = RoomItems.drop(_session, _inner(1, 1), ItemCatalog.get_item(&"apple"), true)
	var saved: Dictionary = entry.to_save()
	assert_bool(FurniturePlacement.from_save(saved).wrapped).is_true()
	assert_bool(RoomItems.picked(entry.id)).is_true()
	assert_int(RoomItems.count(_room)).is_equal(0)
	assert_str(String(_session.grid.occupant_at(_inner(1, 1)))).is_equal("")


func test_things_on_the_floor_are_not_furniture_and_cost_hra_points() -> void:
	RoomItems.drop(_session, _inner(1, 1), ItemCatalog.get_item(&"apple"))
	assert_bool(_session.is_full()).is_false()
	var clean: Dictionary = HappyRoomAcademy.score_floor(HappyRoomAcademy.pieces_of(_room), 0, 0, 0, HappyRoomAcademy.EVAL_CLEAN, 0)
	var messy: Dictionary = HappyRoomAcademy.score_floor(HappyRoomAcademy.pieces_of(_room), 0, 0, 0, HappyRoomAcademy.EVAL_CLEAN, RoomItems.count(_room))
	assert_int(int(clean["points"]) - int(messy["points"])).is_less_equal(1)


func test_only_your_own_house_keeps_things_put_down() -> void:
	var shop := Room.new()
	shop.kind = Room.Kind.SHOP
	shop.id = &"shop_test"
	var s := IndoorSession.new()
	s.bind(shop)
	assert_object(RoomItems.drop(s, Vector2i(5, 5), ItemCatalog.get_item(&"apple"))).is_null()
