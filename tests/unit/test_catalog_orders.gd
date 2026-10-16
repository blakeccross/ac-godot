class_name TestCatalogOrders
extends GdUnitTestSuite

## `CatalogBook.is_orderable` against `mCL_furniture_init` / `mCL_wall_init` & co.


func test_rare_list_furniture_can_be_ordered() -> void:
	if not ShopGoods.has_disc_lists():
		return
	var rare: Array[StringName] = FurnitureCatalog.named_list("ftr", "C")
	var checked: int = 0
	for id: StringName in rare:
		var data: ItemData = ItemCatalog.get_item(id)
		if data == null or ShopBook.buy_price(data) <= 0:
			continue
		assert_bool(CatalogBook.is_orderable(data)).override_failure_message(String(id)).is_true()
		checked += 1
		if checked >= 5:
			break


func test_redd_and_raffle_furniture_can_be_ordered() -> void:
	if not ShopGoods.has_disc_lists():
		return
	for label: String in ["Event", "Lottery"]:
		for id: StringName in FurnitureCatalog.named_list("ftr", label):
			var data: ItemData = ItemCatalog.get_item(id)
			if data != null and ShopBook.buy_price(data) > 0:
				assert_bool(CatalogBook.is_orderable(data)).override_failure_message(String(id)).is_true()
				break


func test_listless_furniture_is_not_for_sale() -> void:
	if not ShopGoods.has_disc_lists():
		return
	## The Halloween list is Jack's; nothing on it alone has a price in the catalog.
	var listed: Dictionary = {}
	for label: String in CatalogBook.ORDER_LISTS["ftr"]:
		for id: StringName in FurnitureCatalog.named_list("ftr", label):
			listed[id] = true
	for id: StringName in FurnitureCatalog.named_list("ftr", "Halloween"):
		if listed.has(id):
			continue
		var data: ItemData = ItemCatalog.get_item(id)
		if data != null:
			assert_bool(CatalogBook.is_orderable(data)).override_failure_message(String(id)).is_false()
			return
