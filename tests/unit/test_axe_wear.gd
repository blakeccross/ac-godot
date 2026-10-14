extends GdUnitTestSuite

## The axe wearing out (`Player_actor_GetitemNo_forDamageAxe`): 9 damage a stage, 1 a tree,
## 3 a bounce; seven stages, then it breaks.


func before_test() -> void:
	Game.reset_session()
	AxeWear.reset()


func after_test() -> void:
	Game.reset_session()
	AxeWear.reset()


func _equip(id: StringName) -> Inventory:
	var inv := Inventory.new()
	inv.add(ItemCatalog.get_item(id), 1)
	inv.equip_slot(0)
	return inv


func test_nine_trees_chip_the_axe_once() -> void:
	var inv := _equip(&"axe")
	for i: int in 8:
		assert_str(String(AxeWear.apply(inv, false))).is_equal("axe")
	assert_str(String(AxeWear.apply(inv, false))).is_equal("axe_use_1")
	assert_str(String(inv.equipment_id)).is_equal("axe_use_1")
	assert_int(inv.count_of(&"axe_use_1")).is_equal(1)
	assert_int(inv.count_of(&"axe")).is_equal(0)
	assert_int(AxeWear.damage).is_equal(0)


func test_bouncing_wears_it_three_times_as_fast() -> void:
	var inv := _equip(&"axe_use_3")
	AxeWear.apply(inv, true)
	AxeWear.apply(inv, true)
	assert_str(String(AxeWear.apply(inv, true))).is_equal("axe_use_4")


func test_the_seventh_stage_breaks_and_leaves_the_hand_empty() -> void:
	var inv := _equip(&"axe_use_7")
	AxeWear.damage = 8
	assert_str(String(AxeWear.apply(inv, false))).is_equal("")
	assert_str(String(inv.equipment_id)).is_equal("")
	assert_int(inv.count_of(&"axe_use_7")).is_equal(0)


func test_the_golden_axe_never_wears() -> void:
	var inv := _equip(&"golden_axe")
	for i: int in 40:
		assert_str(String(AxeWear.apply(inv, true))).is_equal("golden_axe")


func test_worn_axes_look_chipped() -> void:
	assert_str(String((ItemCatalog.get_item(&"axe_use_1") as ToolData).visual_id)).is_equal("tol_axe_1")
	assert_str(String((ItemCatalog.get_item(&"axe_use_2") as ToolData).visual_id)).is_equal("tol_axe_1_b")
	assert_str(String((ItemCatalog.get_item(&"axe_use_7") as ToolData).visual_id)).is_equal("tol_axe_1_c")
	assert_int((ItemCatalog.get_item(&"axe_use_4") as ToolData).kind).is_equal(ToolData.Kind.AXE)
