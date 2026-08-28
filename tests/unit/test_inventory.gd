class_name TestInventory
extends GdUnitTestSuite


func test_add_and_count() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_int(inv.add(apple, 2)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(2)
	assert_int(inv.count_of_occupied()).is_equal(2)


func test_no_stacking() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_int(inv.add(apple, 3)).is_equal(0)
	assert_int(inv.count_of_occupied()).is_equal(3)


func test_remove() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 3)
	assert_int(inv.remove(&"apple", 2)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(1)
	assert_int(inv.remove(&"apple", 5)).is_equal(4)
	assert_int(inv.count_of(&"apple")).is_equal(0)


func test_has_space() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_bool(inv.has_space(1)).is_true()
	assert_int(inv.add(apple, Inventory.POCKET_SLOTS)).is_equal(0)
	assert_bool(inv.has_space(1)).is_false()


func test_save_round_trip() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(apple, 4)
	inv.add(axe, 1)
	var other := Inventory.new()
	other.from_save(inv.to_save())
	assert_int(other.count_of(&"apple")).is_equal(4)
	assert_int(other.count_of(&"axe")).is_equal(1)
