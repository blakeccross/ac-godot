class_name TestDesignUmbrella
extends GdUnitTestSuite

## `ITM_MY_ORG_UMBRELLA0-7`: the player's designs as umbrellas.


func test_eight_design_umbrellas_on_the_plain_canopy() -> void:
	for slot: int in 8:
		var tool := ItemCatalog.get_item(DesignUmbrella.item_id(slot)) as ToolData
		assert_object(tool).is_not_null()
		assert_int(tool.design_slot).is_equal(slot)
		assert_str(String(tool.visual_id)).is_equal("tol_umb_w")
		assert_bool(tool.is_umbrella()).is_true()
		assert_bool(tool.is_stock_umbrella()).is_false()


func test_shops_and_presents_never_stock_them() -> void:
	for id: StringName in ShopGoods.umbrella_pool():
		assert_bool(DesignUmbrella.is_design_umbrella(id)).is_false()
	assert_int(ShopGoods.umbrella_pool().size()).is_equal(32)


func test_making_one_equips_it_or_swaps_the_held_one() -> void:
	var inv := Inventory.new()
	assert_str(DesignUmbrella.make(inv, 2)).is_empty()
	assert_str(String(inv.equipment_id)).is_equal("design_umbrella_2")
	## Already holding a design umbrella: that one becomes the new design.
	DesignUmbrella.make(inv, 5)
	assert_str(String(inv.equipment_id)).is_equal("design_umbrella_5")
	assert_int(inv.count_of(&"design_umbrella_2")).is_equal(0)
	assert_int(inv.count_of(&"design_umbrella_5")).is_equal(1)


func test_holding_something_else_it_goes_in_the_pockets() -> void:
	var inv := Inventory.new()
	inv.add(ItemCatalog.get_item(&"axe"), 1)
	inv.equip_slot(0)
	DesignUmbrella.make(inv, 1)
	assert_str(String(inv.equipment_id)).is_equal("axe")
	assert_int(inv.count_of(&"design_umbrella_1")).is_equal(1)


func test_the_canopy_draws_the_slots_current_design() -> void:
	var tool := ItemCatalog.get_item(DesignUmbrella.item_id(0)) as ToolData
	var tex: Texture2D = HeldUmbrella.design_texture(tool)
	assert_object(tex).is_not_null()
	assert_object(HeldUmbrella.design_texture(ItemCatalog.get_item(&"berry_umbrella") as ToolData)).is_null()


func test_a_villager_with_a_stand_design_carries_the_plain_canopy() -> void:
	var state := VillagerState.new()
	state.umbrella_design = 2
	assert_str(String(VillagerOutdoor.umbrella_visual(null, state))).is_equal("tol_umb_w")
	assert_object(VillagerOutdoor.umbrella_design_texture(state)).is_not_null()
	state.umbrella_design = -1
	assert_object(VillagerOutdoor.umbrella_design_texture(state)).is_null()
