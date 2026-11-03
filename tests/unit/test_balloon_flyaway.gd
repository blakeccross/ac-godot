class_name TestBalloonFlyaway
extends GdUnitTestSuite

## A held balloon floats off when the player gets up from a tumble.


func test_it_speeds_up_to_seven_gx_a_tick() -> void:
	assert_float(BalloonFlyaway.speed_after(0.0)).is_equal(0.0)
	assert_float(BalloonFlyaway.speed_after(100.0)).is_equal(BalloonFlyaway.MAX_SPEED)
	assert_float(BalloonFlyaway.MAX_SPEED).is_equal_approx(7.0 * 0.05 * 60.0, 0.0001)


func test_it_is_gone_in_about_a_second() -> void:
	var secs: float = BalloonFlyaway.seconds_to_rise(BalloonFlyaway.HIDE_HEIGHT)
	assert_float(secs).is_between(0.8, 1.6)


func test_letting_go_empties_the_pocket_and_frees_the_hand() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	var balloon: ItemData = null
	for item: Variant in ItemCatalog.all_items():
		if item is ToolData and (item as ToolData).is_balloon():
			balloon = item as ToolData
			break
	if balloon == null:
		return
	Game.inventory.add(balloon, 1)
	var slot: int = -1
	for i: int in Inventory.POCKET_SLOTS:
		var held: InventorySlot = Game.inventory.slot_at(i)
		if held != null and not held.is_empty() and held.item.item_id == balloon.id:
			slot = i
	assert_int(slot).is_not_equal(-1)
	assert_bool(Game.inventory.equip_slot(slot)).is_true()
	assert_that(Game.inventory.equipment_id).is_equal(balloon.id)
	assert_bool(Game.inventory.swap_equipped(&"")).is_true()
	assert_that(Game.inventory.equipment_id).is_equal(&"")
	assert_int(Game.inventory.count_of(balloon.id)).is_equal(0)
	Game.reset_session()
