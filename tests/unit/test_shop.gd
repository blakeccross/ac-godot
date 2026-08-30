class_name TestShop
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 12, "minute": 0})
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func test_prices_follow_listed_and_quarter() -> void:
	var shovel: ItemData = ItemCatalog.get_item(&"shovel")
	assert_int(ShopBook.buy_price(shovel)).is_equal(500)
	assert_int(ShopBook.sell_price(shovel)).is_equal(125)
	var chair: ItemData = ItemCatalog.get_item(&"wood_chair")
	assert_int(ShopBook.buy_price(chair)).is_equal(320)
	assert_int(ShopBook.sell_price(chair)).is_equal(80)
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	assert_int(ShopBook.buy_price(apple)).is_equal(100)
	assert_int(ShopBook.sell_price(apple)).is_equal(100)
	var shirt: ItemData = ItemCatalog.get_item(&"shirt_000")
	assert_that(shirt).is_not_null()
	assert_that(shirt.category).is_equal(ItemData.Category.CLOTH)
	assert_int(shirt.cloth_index).is_equal(0)
	assert_int(ShopBook.buy_price(shirt)).is_equal(360)


func test_nook_buy_takes_wallet_stock_and_sales() -> void:
	var shop: ShopBook = Game.shops
	shop.ensure_today(ShopBook.NOOK_ID)
	var listed: Array[StringName] = shop.goods(ShopBook.NOOK_ID)
	assert_int(listed.size()).is_equal(8)
	var item_id: StringName = listed[0]
	var data: ItemData = ItemCatalog.get_item(item_id)
	var price: int = ShopBook.buy_price(data)
	Game.inventory.set_wallet(price)
	var msg: String = shop.buy(ShopBook.NOOK_ID, item_id, Game.inventory)
	assert_str(msg).contains("Bought")
	assert_int(Game.inventory.wallet).is_equal(0)
	assert_int(Game.inventory.count_of(item_id)).is_equal(1)
	assert_int(shop.goods(ShopBook.NOOK_ID).size()).is_equal(7)
	assert_int(shop.sales_sum(ShopBook.NOOK_ID)).is_equal(price)


func test_cannot_buy_if_broke_or_full_or_sold_out() -> void:
	var shop: ShopBook = Game.shops
	shop.ensure_today(ShopBook.NOOK_ID)
	var item_id: StringName = shop.goods(ShopBook.NOOK_ID)[0]
	var data: ItemData = ItemCatalog.get_item(item_id)
	Game.inventory.set_wallet(0)
	assert_str(shop.buy(ShopBook.NOOK_ID, item_id, Game.inventory)).contains("Not enough")
	assert_int(shop.goods(ShopBook.NOOK_ID).size()).is_equal(8)
	Game.inventory.set_wallet(ShopBook.buy_price(data) * 20)
	var chair: ItemData = ItemCatalog.get_item(&"wood_chair")
	for _i: int in Inventory.POCKET_SLOTS:
		assert_int(Game.inventory.add(chair, 1)).is_equal(0)
	assert_str(shop.buy(ShopBook.NOOK_ID, item_id, Game.inventory)).contains("full")
	Game.reset_session()
	shop.ensure_today(ShopBook.NOOK_ID)
	Game.inventory.set_wallet(99999)
	assert_str(shop.buy(ShopBook.NOOK_ID, &"shirt_000", Game.inventory)).contains("sold out")


func test_nook_sells_quarter_able_does_not_buy() -> void:
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	Game.inventory.add(apple, 2)
	var sold: String = Game.shops.sell(ShopBook.NOOK_ID, &"apple", Game.inventory, 1)
	assert_str(sold).contains("100")
	assert_int(Game.inventory.wallet).is_equal(100)
	assert_int(Game.inventory.count_of(&"apple")).is_equal(1)
	assert_str(Game.shops.sell(ShopBook.ABLE_ID, &"apple", Game.inventory, 1)).contains("don't buy")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(1)
	var chair: ItemData = ItemCatalog.get_item(&"wood_chair")
	Game.inventory.add(chair, 1)
	assert_str(Game.shops.sell(ShopBook.NOOK_ID, &"wood_chair", Game.inventory, 1)).contains("80")


func test_able_stock_is_shirts_and_buy_works() -> void:
	Game.inventory.set_wallet(2000)
	Game.shops.ensure_today(ShopBook.ABLE_ID)
	var listed: Array[StringName] = Game.shops.goods(ShopBook.ABLE_ID)
	assert_int(listed.size()).is_equal(4)
	for item_id: StringName in listed:
		var data: ItemData = ItemCatalog.get_item(item_id)
		assert_that(data.category).is_equal(ItemData.Category.CLOTH)
	var first: StringName = listed[0]
	assert_str(Game.shops.buy(ShopBook.ABLE_ID, first, Game.inventory)).contains("Bought")
	assert_int(Game.shops.goods(ShopBook.ABLE_ID).size()).is_equal(3)
	assert_int(Game.inventory.count_of(first)).is_equal(1)
	assert_bool(Game.shops.allows_sell(ShopBook.ABLE_ID)).is_false()
	assert_bool(Game.shops.allows_sell(ShopBook.NOOK_ID)).is_true()


func test_sold_out_does_not_restock_until_six() -> void:
	Game.inventory.set_wallet(99999)
	Game.shops.ensure_today(ShopBook.NOOK_ID)
	var listed: Array[StringName] = Game.shops.goods(ShopBook.NOOK_ID).duplicate()
	for item_id: StringName in listed:
		Game.shops.buy(ShopBook.NOOK_ID, item_id, Game.inventory)
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(0)
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(0)
	Clock.advance_minutes(18 * 60)
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(8)
	assert_int(Game.shops.sales_sum(ShopBook.NOOK_ID)).is_greater(0)


func test_shop_snapshot_round_trip() -> void:
	Game.inventory.set_wallet(99999)
	Game.shops.ensure_today(ShopBook.NOOK_ID)
	var item_id: StringName = Game.shops.goods(ShopBook.NOOK_ID)[0]
	Game.shops.buy(ShopBook.NOOK_ID, item_id, Game.inventory)
	var sales: int = Game.shops.sales_sum(ShopBook.NOOK_ID)
	var leftover: int = Game.shops.goods(ShopBook.NOOK_ID).size()
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(leftover)
	assert_int(Game.shops.sales_sum(ShopBook.NOOK_ID)).is_equal(sales)
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).find(item_id)).is_equal(-1)


func test_shop_id_from_room_kind() -> void:
	var nook: Room = InteriorCatalog.room_template(&"shop0")
	var able: Room = InteriorCatalog.room_template(&"needlework")
	assert_that(Game.shops.shop_id_for_room(nook)).is_equal(ShopBook.NOOK_ID)
	assert_that(Game.shops.shop_id_for_room(able)).is_equal(ShopBook.ABLE_ID)
	assert_bool(Game.shops.is_shop_room(nook)).is_true()
	assert_bool(Game.shops.is_shop_room(able)).is_true()
	assert_int(nook.placements.size()).is_equal(2)
	assert_int(able.placements.size()).is_equal(1)
	assert_bool(able.shell_ids.has("rom_tailor")).is_true()


func test_counter_offers_shop_verb() -> void:
	var counter: Node = auto_free(load("res://scenes/world/shop_counter.tscn").instantiate())
	counter.set("shop_id", ShopBook.NOOK_ID)
	var action: Interaction = Interaction.primary(ShopUse.actions(counter, InteractionContext.new()))
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.BUY))
	assert_str(action.prompt).is_equal("Shop")
