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
	## Zakka tools 2, furniture, wall, carpet, cloth, sapling, plants 2 + the daily umbrella.
	assert_int(listed.size()).is_equal(10)
	var item_id: StringName = listed[0]
	var data: ItemData = ItemCatalog.get_item(item_id)
	var price: int = ShopBook.buy_price(data)
	Game.inventory.set_wallet(price)
	var msg: String = shop.buy(ShopBook.NOOK_ID, item_id, Game.inventory)
	assert_str(msg).contains("Bought")
	assert_int(Game.inventory.wallet).is_equal(0)
	assert_int(Game.inventory.count_of(item_id)).is_equal(1)
	assert_int(shop.goods(ShopBook.NOOK_ID).size()).is_equal(9)
	assert_int(shop.sales_sum(ShopBook.NOOK_ID)).is_equal(price)


func test_cannot_buy_if_broke_or_full_or_sold_out() -> void:
	var shop: ShopBook = Game.shops
	shop.ensure_today(ShopBook.NOOK_ID)
	var item_id: StringName = shop.goods(ShopBook.NOOK_ID)[0]
	var data: ItemData = ItemCatalog.get_item(item_id)
	Game.inventory.set_wallet(0)
	assert_str(shop.buy(ShopBook.NOOK_ID, item_id, Game.inventory)).contains("Not enough")
	assert_int(shop.goods(ShopBook.NOOK_ID).size()).is_equal(10)
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


func test_able_holds_no_bell_stock() -> void:
	## `SCENE_NEEDLEWORK` is a design/pattern shop — designs are traded through Mabel,
	## nothing is sold for Bells (`ac_npc_needlework`, `m_needlework.c`).
	Game.shops.ensure_today(ShopBook.ABLE_ID)
	assert_int(Game.shops.goods(ShopBook.ABLE_ID).size()).is_equal(0)
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
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(10)
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
	## Able's table / machine / register are baked into the shell — no placements.
	assert_int(able.placements.size()).is_equal(0)
	assert_bool(able.shell_ids.has("rom_tailor")).is_true()
	assert_that(nook.wall_id).is_equal(ShopDisplay.nook_wall_id(0))
	assert_that(nook.floor_id).is_equal(ShopDisplay.nook_floor_id(0))


func test_tom_nook_offers_talk_only() -> void:
	## Sell / order go through his menu; goods are bought at the shelf.
	Game.current_room_id = &"shop0"
	var nook: Node = auto_free(load("res://scenes/world/interiors/tom_nook.tscn").instantiate())
	var actions: Array[Interaction] = nook.get_interactions(InteractionContext.new())
	assert_int(actions.size()).is_equal(1)
	assert_str(String(actions[0].id)).is_equal(String(Interaction.TALK))
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


func test_cranny_sapling_uses_its_own_shelf_cell() -> void:
	## `FG_TYPE_ROM_SHOP1`: saplings sit on `RSV_SHOP_HALLOWEEN` (6,4), not a seed-bag cell.
	var goods: Array[StringName] = [&"sapling", &"white_pansy_bag", &"purple_pansy_bag"]
	var cells: Array[Vector2i] = ShopDisplay.stock_cells_for_goods(goods)
	assert_that(cells[0]).is_equal(Vector2i(6, 4))
	assert_that(cells[1]).is_equal(Vector2i(4, 4))
	assert_that(cells[2]).is_equal(Vector2i(5, 4))
	assert_int(ShopDisplay.CRANNY_SLOTS.size()).is_equal(11)


func test_cranny_blocks_room01_walls_and_the_goods_tables() -> void:
	var blocked: Dictionary = ShopDisplay.cranny_blocked_units()
	for slot: Dictionary in ShopDisplay.CRANNY_SLOTS:
		var cell: Vector2i = slot["cell"] as Vector2i
		assert_bool(blocked.has(cell)).is_equal(float(slot["y_gx"]) > 0.0)
	if InteriorUnitCollision.bg_counts(ShopDisplay.CRANNY_BG_ID).is_empty():
		return  ## `room01.col.json` not generated (no disc)
	## South wall either side of the door, the east column; the door and Nook stay open.
	for x: int in range(1, 8):
		assert_bool(blocked.has(Vector2i(x, 7))).is_equal(x != 3 and x != 4)
	for z: int in range(1, 8):
		assert_bool(blocked.has(Vector2i(7, z))).is_true()
	assert_bool(blocked.has(ShopDisplay.NOOK_STAND_UT[0])).is_false()


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
	var session := IndoorSession.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	ShopPresenter.new().present(root, session)
	var nook: Node3D = root.get_node_or_null("TomNook") as Node3D
	assert_that(nook).is_not_null()
	var expected: Vector3 = ShopDisplay.gx_to_world(session.grid, ShopDisplay.nook_stand_gx(1))
	assert_float(nook.position.x).is_equal_approx(expected.x, 0.05)
	assert_float(nook.position.z).is_equal_approx(expected.z, 0.05)


func test_nook_clock_spawns_in_cranny() -> void:
	var room: Room = InteriorCatalog.room_template(&"shop0")
	var session := IndoorSession.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	InteriorBuilder.build(root, session)
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
		{"shop0": {"id": "shop0", "goods": [], "sales": ShopBook.DSUPER_SUM, "renew": Clock.renew_index(), "visitor": true}}
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


func _nook_at(sales: int) -> void:
	Game.shops.apply_snapshot(
		{"shop0": {"id": "shop0", "goods": [], "sales": sales, "renew": -1, "visitor": true}}
	)


func _present_stock(room_id: StringName) -> Node3D:
	var session := IndoorSession.new()
	session.bind(InteriorCatalog.room_template(room_id))
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	ShopPresenter.new().present(root, session)
	return root


func _stock_positions(root: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for child: Node in root.get_children():
		if child.name.begins_with("ShopStock_"):
			out[String(child.name)] = (child as Node3D).position
	return out


func test_goods_keep_their_slot_after_a_purchase() -> void:
	## `mSP_ShopSaleReport`: the sold slot turns `RSV_SHOP_SOLD_*`; nothing else moves.
	Game.inventory.set_wallet(99999)
	Game.shops.ensure_today(ShopBook.NOOK_ID)
	var before: Dictionary = _stock_positions(_present_stock(&"shop0"))
	var lineup: Array[StringName] = Game.shops.lineup(ShopBook.NOOK_ID)
	assert_int(before.size()).is_equal(lineup.size())
	assert_str(Game.shops.buy(ShopBook.NOOK_ID, lineup[0], Game.inventory)).contains("Bought")
	assert_that(Game.shops.lineup(ShopBook.NOOK_ID)).is_equal(lineup)
	assert_that(Game.shops.sold_slots(ShopBook.NOOK_ID)).is_equal([0] as Array[int])
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(lineup.size() - 1)
	var after: Dictionary = _stock_positions(_present_stock(&"shop0"))
	assert_bool(after.has("ShopStock_0")).is_false()
	assert_int(after.size()).is_equal(before.size() - 1)
	for key: String in after:
		assert_vector(after[key]).is_equal(before[key])
	## Save/load keeps the empty slot.
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_that(Game.shops.sold_slots(ShopBook.NOOK_ID)).is_equal([0] as Array[int])
	assert_that(_stock_positions(_present_stock(&"shop0"))).is_equal(after)
	## 06:00 restock clears the sold marks.
	Clock.advance_minutes(18 * 60)
	assert_int(Game.shops.sold_slots(ShopBook.NOOK_ID).size()).is_equal(0)


func test_buying_a_duplicate_good_marks_one_slot() -> void:
	Game.inventory.set_wallet(99999)
	Game.shops.apply_snapshot({"shop0": {"goods": ["shovel", "shovel"], "renew": Clock.renew_index()}})
	Game.shops.buy(ShopBook.NOOK_ID, &"shovel", Game.inventory)
	assert_that(Game.shops.sold_slots(ShopBook.NOOK_ID)).is_equal([0] as Array[int])
	Game.shops.buy(ShopBook.NOOK_ID, &"shovel", Game.inventory)
	assert_that(Game.shops.sold_slots(ShopBook.NOOK_ID)).is_equal([0, 1] as Array[int])
	var again: Dictionary = Game.shops.buy_result(ShopBook.NOOK_ID, &"shovel", Game.inventory)
	assert_int(int(again["code"])).is_equal(ShopBook.Buy.SOLD_OUT)


func test_reserve_points_match_fg_templates() -> void:
	## `RSV_SHOP_*` (`m_name_table.h`) → slot kind; the tables must equal the disc FG.
	var kinds: Dictionary = {
		0xFE00: &"paper", 0xFE01: &"cloth", 0xFE02: &"furniture", 0xFE03: &"floor",
		0xFE04: &"wall", 0xFE05: &"sapling", 0xFE06: &"tool", 0xFE08: &"plant",
		0xFE09: &"rare", 0xFE0A: &"umbrella", 0xFE0B: &"paint", 0xFE0C: &"sign",
	}
	var on_floor: Array[StringName] = [&"furniture", &"rare", &"cloth", &"umbrella"]
	for room_id: StringName in ShopDisplay.STOCK_FG_TYPES:
		var slots: Array[Dictionary] = ShopDisplay.stock_slots(room_id)
		assert_int(slots.size()).is_greater(0)
		for slot: Dictionary in slots:
			var y: float = float(slot["y_gx"])
			assert_float(y).is_equal(0.0 if on_floor.has(slot["kind"]) else ShopDisplay.SHELF)
		if not FgCatalog.has_catalog():
			continue
		var items: PackedInt32Array = FgCatalog.items(int(ShopDisplay.STOCK_FG_TYPES[room_id]))
		var expected: Array = []
		for i: int in items.size():
			if kinds.has(items[i]):
				expected.append([kinds[items[i]], Vector2i(i % 16, i / 16)])
		var got: Array = []
		for slot: Dictionary in slots:
			got.append([slot["kind"], slot["cell"]])
		assert_that(got).is_equal(expected)


func test_every_nook_level_puts_its_goods_on_reserve_points() -> void:
	## Level → the floors that lay out its list (Nookington's has two).
	var floors: Array = [[&"shop0"], [&"shop1"], [&"shop2"], [&"shop3_1", &"shop3_2"]]
	var sales: Array[int] = [0, ShopBook.COMBINI_SUM, ShopBook.SUPER_SUM, ShopBook.DSUPER_SUM]
	for level: int in floors.size():
		_nook_at(sales[level])
		assert_int(Game.shops.nook_level()).is_equal(level)
		var lineup: Array[StringName] = Game.shops.lineup(ShopBook.NOOK_ID)
		var rare: StringName = Game.shops.rare_item()
		var shown: Dictionary = {}
		for room_id: StringName in floors[level]:
			var room: Room = InteriorCatalog.room_template(room_id)
			var rows: Array[Dictionary] = ShopDisplay.stock_placements_for_goods(lineup, room_id, rare)
			for row: Dictionary in rows:
				assert_bool(room.is_inner(row["cell"] as Vector2i)).is_true()
				assert_bool(shown.has(row["index"])).is_false()
				shown[row["index"]] = true
			## Presented stock sits on the placements only (no free-cell fallback).
			assert_int(_stock_positions(_present_stock(room_id)).size()).is_equal(rows.size())
		## Nook 'n' Go stocks three tools on two tool points (`l_conbini_goods`).
		assert_int(shown.size()).is_greater_equal(lineup.size() - (1 if level == 1 else 0))


func test_nookingtons_upstairs_shows_its_own_goods() -> void:
	_nook_at(ShopBook.DSUPER_SUM)
	var lineup: Array[StringName] = Game.shops.lineup(ShopBook.NOOK_ID)
	var rare: StringName = Game.shops.rare_item()
	var up: Array[Dictionary] = ShopDisplay.stock_placements_for_goods(lineup, &"shop3_2", rare)
	var down: Array[Dictionary] = ShopDisplay.stock_placements_for_goods(lineup, &"shop3_1", rare)
	assert_int(up.size()).is_greater(0)
	assert_int(_stock_positions(_present_stock(&"shop3_2")).size()).is_equal(up.size())
	var upstairs: Array = [ItemData.Category.CLOTH, ItemData.Category.WALL, ItemData.Category.FLOOR]
	for row: Dictionary in up:
		var data: ItemData = ItemCatalog.get_item(lineup[int(row["index"])])
		assert_bool(data is FurnitureData or upstairs.has(data.category)).is_true()
	for row: Dictionary in down:
		var data: ItemData = ItemCatalog.get_item(lineup[int(row["index"])])
		assert_bool(data is FurnitureData or upstairs.has(data.category)).is_false()
