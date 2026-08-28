class_name TestInventory
extends GdUnitTestSuite


func test_add_and_count() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_int(inv.add(apple, 2)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(2)
	assert_int(inv.count_of_occupied()).is_equal(1)


func test_stacking_respects_max_stack() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_int(apple.max_stack).is_equal(9)
	assert_int(inv.add(apple, 10)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(10)
	assert_int(inv.count_of_occupied()).is_equal(2)
	assert_int(inv.slot_at(0).item.count).is_equal(9)
	assert_int(inv.slot_at(1).item.count).is_equal(1)


func test_tools_do_not_stack() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	assert_int(inv.add(axe, 2)).is_equal(0)
	assert_int(inv.count_of_occupied()).is_equal(2)


func test_remove() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 3)
	assert_int(inv.remove(&"apple", 2)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(1)
	assert_int(inv.remove(&"apple", 5)).is_equal(4)
	assert_int(inv.count_of(&"apple")).is_equal(0)


func test_has_space_for_stacking() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	assert_bool(inv.has_space_for(apple, 1)).is_true()
	assert_int(inv.add(axe, Inventory.POCKET_SLOTS)).is_equal(0)
	assert_bool(inv.has_space_for(axe, 1)).is_false()
	assert_bool(inv.has_space(1)).is_false()


func test_select_and_use_fruit() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 2)
	inv.select(0)
	var msg: String = inv.use_slot(0)
	assert_str(msg).contains("Eat")
	assert_int(inv.count_of(&"apple")).is_equal(1)


func test_equip_tool() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(axe, 1)
	assert_bool(inv.equip_slot(0)).is_true()
	assert_that(inv.equipment_id).is_equal(&"axe")


func test_drop_slot() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 2)
	var removed: InventoryItem = inv.drop_slot(0, 1)
	assert_that(removed.item_id).is_equal(&"apple")
	assert_int(removed.count).is_equal(1)
	assert_int(inv.count_of(&"apple")).is_equal(1)


func test_hand_move() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(axe, 1)
	assert_bool(inv.pick_hand(0)).is_true()
	assert_int(inv.hand_index).is_equal(0)
	assert_bool(inv.place_hand(3)).is_true()
	assert_bool(inv.slot_at(0).is_empty()).is_true()
	assert_bool(inv.slot_at(3).is_empty()).is_false()


func test_wallet() -> void:
	var inv := Inventory.new()
	assert_int(inv.add_bells(500)).is_equal(500)
	assert_bool(inv.spend_bells(200)).is_true()
	assert_int(inv.wallet).is_equal(300)
	assert_bool(inv.spend_bells(999)).is_false()


func test_save_round_trip() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(apple, 4)
	inv.add(axe, 1)
	inv.set_wallet(1234)
	inv.equip_slot(1)
	var other := Inventory.new()
	other.from_save(inv.to_save())
	assert_int(other.count_of(&"apple")).is_equal(4)
	assert_int(other.count_of(&"axe")).is_equal(1)
	assert_int(other.wallet).is_equal(1234)
	assert_that(other.equipment_id).is_equal(&"axe")


func test_legacy_array_save() -> void:
	var inv := Inventory.new()
	inv.from_save([{ "id": "apple", "count": 1 }, { "id": "axe", "count": 1 }])
	assert_int(inv.count_of(&"apple")).is_equal(1)
	assert_int(inv.count_of(&"axe")).is_equal(1)


func test_item_catalog() -> void:
	ItemCatalog.reload()
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	assert_object(apple).is_not_null()
	assert_str(apple.display_name).is_equal("Apple")
