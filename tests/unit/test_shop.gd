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
	assert_int(listed.size()).is_equal(9)
	var item_id: StringName = listed[0]
	var data: ItemData = ItemCatalog.get_item(item_id)
	var price: int = ShopBook.buy_price(data)
	Game.inventory.set_wallet(price)
	var msg: String = shop.buy(ShopBook.NOOK_ID, item_id, Game.inventory)
	assert_str(msg).contains("Bought")
	assert_int(Game.inventory.wallet).is_equal(0)
	assert_int(Game.inventory.count_of(item_id)).is_equal(1)
	assert_int(shop.goods(ShopBook.NOOK_ID).size()).is_equal(8)
	assert_int(shop.sales_sum(ShopBook.NOOK_ID)).is_equal(price)


func test_cannot_buy_if_broke_or_full_or_sold_out() -> void:
	var shop: ShopBook = Game.shops
	shop.ensure_today(ShopBook.NOOK_ID)
	var item_id: StringName = shop.goods(ShopBook.NOOK_ID)[0]
	var data: ItemData = ItemCatalog.get_item(item_id)
	Game.inventory.set_wallet(0)
	assert_str(shop.buy(ShopBook.NOOK_ID, item_id, Game.inventory)).contains("Not enough")
	assert_int(shop.goods(ShopBook.NOOK_ID).size()).is_equal(9)
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
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(9)
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
	assert_int(nook.placements.size()).is_equal(0)
	assert_int(able.placements.size()).is_equal(1)
	assert_bool(able.shell_ids.has("rom_tailor")).is_true()
	assert_that(nook.wall_id).is_equal(ShopDisplay.nook_wall_id(0))
	assert_that(nook.floor_id).is_equal(ShopDisplay.nook_floor_id(0))


func test_tom_nook_offers_talk_buy_sell() -> void:
	Game.current_room_id = &"shop0"
	var nook: Node = auto_free(load("res://scenes/world/interiors/tom_nook.tscn").instantiate())
	var actions: Array[Interaction] = nook.get_interactions(InteractionContext.new())
	var ids: PackedStringArray = PackedStringArray()
	for action: Interaction in actions:
		ids.append(String(action.id))
	assert_bool(ids.has(String(Interaction.TALK))).is_true()
	assert_bool(ids.has(String(Interaction.BUY))).is_true()
	assert_bool(ids.has(String(Interaction.SELL))).is_true()
	Game.current_room_id = &""


func test_cranny_stock_maps_to_rsv_cells() -> void:
	Game.shops.ensure_today(ShopBook.NOOK_ID)
	var listed: Array[StringName] = Game.shops.goods(ShopBook.NOOK_ID)
	var cells: Array[Vector2i] = ShopDisplay.stock_cells_for_goods(listed)
	assert_int(cells.size()).is_equal(listed.size())
	assert_int(cells.size()).is_less_equal(ShopDisplay.CRANNY_SLOTS.size())
	var placements: Array[Dictionary] = ShopDisplay.stock_placements_for_goods(listed)
	var saw_shelf := false
	var saw_floor := false
	for row: Dictionary in placements:
		var y: float = float(row["y_gx"])
		if is_equal_approx(y, ShopDisplay.CRANNY_SHELF_Y_GX):
			saw_shelf = true
		elif is_equal_approx(y, 0.0):
			saw_floor = true
	assert_bool(saw_shelf).is_true()
	assert_bool(saw_floor).is_true()


func test_tom_nook_model_follows_shop_level() -> void:
	var rooms: Array[StringName] = [&"shop0", &"shop1", &"shop2", &"shop3_1"]
	for level: int in rooms.size():
		var species: StringName = ShopDisplay.nook_species(level)
		if FieldCatalog.villager_path(species).is_empty():
			continue
		Game.current_room_id = rooms[level]
		var nook: Node = auto_free(load("res://scenes/world/interiors/tom_nook.tscn").instantiate())
		add_child(nook)
		var vis: Node = nook.get_node_or_null("Model/GeneratedVisual")
		assert_that(vis).is_not_null()
		assert_bool(_nook_visual_named(vis, String(species))).is_true()
	Game.current_room_id = &""


func _nook_visual_named(node: Node, prefix: String) -> bool:
	if node == null or prefix.is_empty():
		return false
	if String(node.name).begins_with(prefix):
		return true
	for child: Node in node.get_children():
		if _nook_visual_named(child, prefix):
			return true
	return false


func test_tom_nook_stand_follows_shop_room() -> void:
	var room: Room = InteriorCatalog.room_template(&"shop1")
	var session := Interior.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	InteriorBuilder.new().add_tom_nook(root, session)
	var nook: Node3D = root.get_node_or_null("TomNook") as Node3D
	assert_that(nook).is_not_null()
	var expected: Vector3 = ShopDisplay.gx_to_world(session.grid, ShopDisplay.nook_stand_gx(1))
	assert_float(nook.position.x).is_equal_approx(expected.x, 0.05)
	assert_float(nook.position.z).is_equal_approx(expected.z, 0.05)


func test_nook_clock_spawns_in_cranny() -> void:
	var room: Room = InteriorCatalog.room_template(&"shop0")
	var session := Interior.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	InteriorBuilder.new().build(root, session)
	var clock: Node3D = root.get_node_or_null("Furniture/NookClock") as Node3D
	if FieldCatalog.mesh_paths(ShopDisplay.nook_clock_visual(0)).is_empty():
		return
	assert_that(clock).is_not_null()
	var expected: Vector3 = ShopDisplay.gx_to_world(
		session.grid, Vector3(ShopDisplay.CLOCK_GX.x, 0.0, ShopDisplay.CLOCK_GX.z)
	)
	assert_float(clock.position.x).is_equal_approx(expected.x, 0.05)
	assert_float(clock.position.z).is_equal_approx(expected.z, 0.05)


func test_nook_upgrades_by_sales() -> void:
	var shop: ShopBook = Game.shops
	assert_int(shop.nook_level()).is_equal(0)
	assert_that(shop.nook_room_id()).is_equal(&"shop0")
	assert_that(shop.nook_visual_id()).is_equal(&"obj_s_shop1")
	assert_that(ShopDisplay.nook_species(shop.nook_level())).is_equal(&"rcn")
	assert_int(shop.nook_open_hour()).is_equal(9)
	shop.apply_snapshot(
		{"shop0": {"id": "shop0", "goods": [], "sales": ShopBook.COMBINI_SUM, "renew": Clock.renew_index()}}
	)
	assert_int(shop.nook_level()).is_equal(1)
	assert_that(shop.nook_room_id()).is_equal(&"shop1")
	assert_that(shop.nook_visual_id()).is_equal(&"obj_s_shop2")
	assert_that(ShopDisplay.nook_species(shop.nook_level())).is_equal(&"rcc")
	assert_int(shop.nook_open_hour()).is_equal(7)
	assert_int(shop.nook_close_hour()).is_equal(23)
	shop.apply_snapshot(
		{"shop0": {"id": "shop0", "goods": [], "sales": ShopBook.SUPER_SUM, "renew": Clock.renew_index()}}
	)
	assert_that(shop.nook_room_id()).is_equal(&"shop2")
	assert_that(shop.nook_visual_id()).is_equal(&"obj_s_shop3")
	assert_that(ShopDisplay.nook_species(shop.nook_level())).is_equal(&"rcs")
	shop.apply_snapshot(
		{"shop0": {"id": "shop0", "goods": [], "sales": ShopBook.DSUPER_SUM, "renew": Clock.renew_index()}}
	)
	assert_that(shop.nook_room_id()).is_equal(&"shop3_1")
	assert_that(shop.nook_visual_id()).is_equal(&"obj_s_shop4")
	assert_that(ShopDisplay.nook_species(shop.nook_level())).is_equal(&"rcd")
	assert_that(InteriorCatalog.resolve_entry(&"acre_shop")).is_equal(&"shop3_1")


func test_authored_public_interior_scenes_exist() -> void:
	for room_id: StringName in [
		&"shop0",
		&"shop1",
		&"shop2",
		&"shop3_1",
		&"shop3_2",
		&"needlework",
		&"police_box",
		&"post_office",
		&"museum_entrance",
	]:
		assert_bool(InteriorCatalog.has_authored_scene(room_id)).is_true()
	assert_str(WorldObjectRegistry.scene_for_building(&"able_sisters", &"building")).contains(
		"able_sisters.tscn"
	)
	assert_str(WorldObjectRegistry.scene_for_building(&"police", &"building")).contains(
		"police_station.tscn"
	)
	assert_str(WorldObjectRegistry.scene_for_building(&"post_office", &"building")).contains(
		"post_office.tscn"
	)


func test_counter_offers_shop_verb() -> void:
	var counter: Node = auto_free(load("res://scenes/world/shop_counter.tscn").instantiate())
	counter.set("shop_id", ShopBook.NOOK_ID)
	var actions: Array[Interaction] = ShopUse.actions(counter, InteractionContext.new())
	var action: Interaction = Interaction.primary(actions)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.BUY))
	assert_str(action.prompt).is_equal("Buy")
	var ids: PackedStringArray = PackedStringArray()
	for entry: Interaction in actions:
		ids.append(String(entry.id))
	assert_bool(ids.has(String(Interaction.SELL))).is_true()
