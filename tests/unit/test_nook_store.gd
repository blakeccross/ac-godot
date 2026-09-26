class_name TestNookStore
extends GdUnitTestSuite

## Nook's store behaviour from `m_shop.c` / `ac_npc_shop_common.c` / `ac_shop_level.c` /
## `ac_npc_shop_mastersp` / `m_kabu_manager.c`.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	_set_date(2001, 1, 10, 12)
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func _set_date(year: int, month: int, day: int, hour: int) -> void:
	Clock.apply_snapshot({"year": year, "month": month, "day": day, "hour": hour, "minute": 0})


func _count(listed: Array[StringName], item_id: StringName) -> int:
	var n: int = 0
	for entry: StringName in listed:
		if entry == item_id:
			n += 1
	return n


func _tools(listed: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: StringName in listed:
		if entry in ShopGoods.TOOL_TABLE:
			out.append(entry)
	return out


# --- Lineup --------------------------------------------------------------------------------


func test_cranny_tools_unlock_by_sales() -> void:
	var rng := RandomNumberGenerator.new()
	for _i: int in 20:
		assert_array(ShopGoods.tools(0, 0, 2, rng)).is_equal([&"shovel"] as Array[StringName])
	for _i: int in 20:
		var two: Array[StringName] = ShopGoods.tools(0, ShopGoods.NET_SALES_SUM, 2, rng)
		assert_int(two.size()).is_equal(2)
		assert_bool(&"fishing_rod" in two or &"axe" in two).is_false()
	for _i: int in 20:
		for tool: StringName in ShopGoods.tools(0, ShopGoods.ROD_SALES_SUM, 2, rng):
			assert_bool(tool == &"axe").is_false()
	## Past the Cranny every tool is on the table.
	var seen: Dictionary = {}
	for _i: int in 200:
		for tool: StringName in ShopGoods.tools(1, 0, 3, rng):
			seen[tool] = true
	assert_int(seen.size()).is_equal(4)


func test_nookway_adds_paint_signboard_and_cedar() -> void:
	var rng := RandomNumberGenerator.new()
	var roll: Dictionary = ShopGoods.roll(2, ShopBook.SUPER_SUM, 2001, 1, 10, 3, rng)
	var goods: Array[StringName] = roll["goods"]
	assert_int(_count(goods, ShopGoods.SIGNBOARD)).is_equal(1)
	assert_int(_count(goods, ShopGoods.PAINTS[3])).is_equal(1)
	assert_int(int(roll["paint_index"])).is_equal(4)
	assert_int(_count(goods, ShopGoods.CEDAR_SAPLING)).is_equal(1)
	assert_int(_count(goods, ShopGoods.SAPLING)).is_equal(1)
	assert_int(_count(goods, ShopGoods.PAPER)).is_equal(2)
	## Cranny has none of those and one of each basic kind.
	var cranny: Array[StringName] = ShopGoods.roll(0, 0, 2001, 1, 10, 0, rng)["goods"]
	assert_int(_count(cranny, ShopGoods.SIGNBOARD)).is_equal(0)
	assert_int(_count(cranny, ShopGoods.CEDAR_SAPLING)).is_equal(0)
	assert_int(_count(cranny, ShopGoods.SAPLING)).is_equal(1)
	assert_int(_count(cranny, ShopGoods.PAPER)).is_equal(1)
	var bags: int = 0
	for entry: StringName in cranny:
		if entry in ShopGoods.FLOWER_BAGS:
			bags += 1
	assert_int(bags).is_equal(2)


func test_paint_colour_rotates_each_restock() -> void:
	var shop: ShopBook = Game.shops
	## Loading a stale row restocks straight away.
	shop.apply_snapshot({"shop0": {"sales": ShopBook.SUPER_SUM, "level": 2, "paint": 11}})
	assert_int(_count(shop.goods(ShopBook.NOOK_ID), &"brown_paint")).is_equal(1)
	shop.restock(ShopBook.NOOK_ID)
	assert_int(_count(shop.goods(ShopBook.NOOK_ID), &"red_paint")).is_equal(1)


func test_flower_bags_never_repeat_and_halloween_sells_candy() -> void:
	var rng := RandomNumberGenerator.new()
	var plants: Array[StringName] = ShopGoods.plants(3, 5, 3, false, rng)
	var seen: Dictionary = {}
	for entry: StringName in plants:
		if entry in ShopGoods.FLOWER_BAGS:
			assert_bool(seen.has(entry)).is_false()
			seen[entry] = true
	assert_int(seen.size()).is_equal(5)
	assert_bool(ShopGoods.is_halloween_stock(10, 16)).is_true()
	assert_bool(ShopGoods.is_halloween_stock(10, 31)).is_false()
	var halloween: Array[StringName] = ShopGoods.plants(0, 2, 1, true, rng)
	assert_int(_count(halloween, ShopGoods.CANDY)).is_equal(2)
	assert_int(_count(halloween, ShopGoods.SAPLING)).is_equal(0)
	assert_int(halloween.size()).is_equal(3)


func test_raffle_day_has_no_goods_and_opens_at_ten() -> void:
	_set_date(2001, 1, 31, 12)
	Game.shops.restock(ShopBook.NOOK_ID)
	assert_int(Game.shops.goods(ShopBook.NOOK_ID).size()).is_equal(0)
	assert_int(Game.shops.nook_open_hour()).is_equal(10)
	assert_int(Game.shops.lottery_prizes().size()).is_equal(ShopGoods.LOTTERY_COUNT)
	_set_date(2001, 1, 31, 9)
	assert_int(Game.shops.nook_status()).is_equal(ShopBook.Status.PRE)
	_set_date(2001, 2, 28, 10)
	assert_bool(Game.shops.is_lottery_day()).is_true()


func test_sale_day_stocks_grab_bags_priced_at_the_year() -> void:
	## 2001: 4th Thursday of November is the 22nd.
	assert_bool(ShopGoods.is_grab_bag_day(2001, 11, 23)).is_true()
	assert_bool(ShopGoods.is_grab_bag_day(2001, 11, 22)).is_false()
	_set_date(2001, 11, 23, 12)
	Game.shops.restock(ShopBook.NOOK_ID)
	var goods: Array[StringName] = Game.shops.goods(ShopBook.NOOK_ID)
	## Cranny: paper 1 + tools 2 + plants 2 + sapling 1.
	assert_int(_count(goods, ShopGoods.GRAB_BAG)).is_equal(6)
	assert_int(_tools(goods).size()).is_equal(0)
	assert_int(ShopBook.buy_price(ItemCatalog.get_item(ShopGoods.GRAB_BAG))).is_equal(2001)


func test_grab_bag_needs_three_free_slots() -> void:
	var bag: ItemData = ItemCatalog.get_item(ShopGoods.GRAB_BAG)
	var chair: ItemData = ItemCatalog.get_item(&"wood_chair")
	Game.inventory.add(bag, 1)
	for _i: int in Inventory.POCKET_SLOTS - 3:
		Game.inventory.add(chair, 1)
	assert_str(Game.inventory.use_slot(0)).contains("three")
	assert_int(Game.inventory.count_of(ShopGoods.GRAB_BAG)).is_equal(1)
	Game.inventory.remove(&"wood_chair", 1)
	assert_str(Game.inventory.use_slot(0)).contains("Opened")
	assert_int(Game.inventory.count_of(ShopGoods.GRAB_BAG)).is_equal(0)
	assert_int(Game.inventory.empty_slot_count()).is_equal(1)


# --- Level & renovation ------------------------------------------------------------------


func test_sales_cap_at_next_threshold_until_renovation() -> void:
	var shop: ShopBook = Game.shops
	shop.plus_sales(ShopBook.COMBINI_SUM + 5000)
	assert_int(shop.sales_sum()).is_equal(ShopBook.COMBINI_SUM)
	assert_int(shop.nook_level()).is_equal(0)
	assert_int(shop.real_level()).is_equal(1)
	var booked: int = EventDates.ordinal(2001, 1, 12)
	assert_int(shop.renewal_day()).is_equal(booked)
	## Still open today; closed from opening time the day before reopening.
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.OPEN)
	_set_date(2001, 1, 11, 8)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.PRE)
	_set_date(2001, 1, 11, 12)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.RENEW)
	assert_str(shop.closed_notice()).contains("renovation")
	## Nook 'n' Go opens at 7 on the booked day.
	_set_date(2001, 1, 12, 6)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.RENEW)
	_set_date(2001, 1, 12, 7)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.OPEN)
	assert_int(shop.nook_level()).is_equal(1)
	assert_that(shop.nook_room_id()).is_equal(&"shop1")
	assert_int(shop.renewal_day()).is_equal(-1)
	var letters: Array[MailData] = shop.take_mail()
	assert_int(letters.size()).is_equal(2)
	assert_str(letters[0].body).contains("renovations")
	assert_str(letters[1].body).contains("Nook 'n' Go")


func test_renovation_waits_out_raffle_day() -> void:
	_set_date(2001, 1, 29, 12)
	Game.shops.plus_sales(ShopBook.COMBINI_SUM)
	assert_int(Game.shops.renewal_day()).is_equal(-1)
	_set_date(2001, 2, 1, 12)
	Game.shops.ensure_today(ShopBook.NOOK_ID)
	assert_int(Game.shops.renewal_day()).is_equal(EventDates.ordinal(2001, 2, 3))


func test_nookingtons_needs_a_visitor() -> void:
	var shop: ShopBook = Game.shops
	shop.apply_snapshot({"shop0": {"sales": ShopBook.DSUPER_SUM, "level": 2}})
	assert_int(shop.real_level()).is_equal(2)
	assert_int(shop.renewal_day()).is_equal(-1)
	shop.set_visitor()
	assert_int(shop.real_level()).is_equal(3)
	shop.ensure_today(ShopBook.NOOK_ID)
	assert_int(shop.renewal_day()).is_equal(EventDates.ordinal(2001, 1, 12))


func test_hours_follow_level() -> void:
	var shop: ShopBook = Game.shops
	_set_date(2001, 1, 10, 22)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.END)
	shop.apply_snapshot({"shop0": {"sales": ShopBook.COMBINI_SUM, "level": 1}})
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.OPEN)
	_set_date(2001, 1, 10, 3)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.END)
	assert_bool(InteriorCatalog.is_open_now(InteriorCatalog.room_template(&"shop1"))).is_false()


# --- Buying ------------------------------------------------------------------------------


func test_bags_cover_a_short_wallet_with_change() -> void:
	var inv: Inventory = Game.inventory
	inv.set_wallet(200)
	inv.add(ItemCatalog.get_item(&"money_1000"), 1)
	assert_bool(ShopBook.can_afford(inv, 1100)).is_true()
	assert_bool(ShopBook.can_afford(inv, 1300)).is_false()
	assert_bool(ShopBook.pay(inv, 500)).is_true()
	assert_int(inv.count_of(&"money_1000")).is_equal(0)
	assert_int(inv.wallet).is_equal(700)


func test_furniture_comes_with_a_raffle_ticket() -> void:
	var shop: ShopBook = Game.shops
	shop.apply_snapshot({"shop0": {"goods": ["wood_chair", "shovel"], "renew": Clock.renew_index()}})
	Game.inventory.set_wallet(5000)
	var res: Dictionary = shop.buy_result(ShopBook.NOOK_ID, &"wood_chair", Game.inventory)
	assert_int(int(res["code"])).is_equal(ShopBook.Buy.OK)
	assert_str(str(res["ticket"])).is_equal("pocket")
	assert_int(Game.inventory.count_of(&"ticket_01")).is_equal(1)
	res = shop.buy_result(ShopBook.NOOK_ID, &"shovel", Game.inventory)
	assert_str(str(res["ticket"])).is_equal("")
	assert_int(Game.inventory.count_of(&"ticket_01")).is_equal(1)
	assert_int(shop.sales_sum()).is_equal(320 + 500)


func test_ticket_is_mailed_when_pockets_fill() -> void:
	var shop: ShopBook = Game.shops
	shop.apply_snapshot({"shop0": {"goods": ["wood_chair"], "renew": Clock.renew_index()}})
	Game.inventory.set_wallet(5000)
	var shovel: ItemData = ItemCatalog.get_item(&"shovel")
	for _i: int in Inventory.POCKET_SLOTS - 1:
		Game.inventory.add(shovel, 1)
	var res: Dictionary = shop.buy_result(ShopBook.NOOK_ID, &"wood_chair", Game.inventory)
	assert_str(str(res["ticket"])).is_equal("mail")
	assert_int(shop.mailed_tickets()).is_equal(1)
	var letters: Array[MailData] = shop.take_mail()
	assert_int(letters.size()).is_equal(1)
	assert_that(letters[0].present_item_id).is_equal(&"ticket_01")
	assert_int(letters[0].present_count).is_equal(1)
	assert_int(shop.mailed_tickets()).is_equal(0)


func test_paint_orders_a_roof_instead_of_an_item() -> void:
	var shop: ShopBook = Game.shops
	shop.apply_snapshot({"shop0": {"goods": ["blue_paint"], "renew": Clock.renew_index(), "level": 2, "sales": ShopBook.SUPER_SUM}})
	Game.inventory.set_wallet(5000)
	var res: Dictionary = shop.buy_result(ShopBook.NOOK_ID, &"blue_paint", Game.inventory)
	assert_int(int(res["code"])).is_equal(ShopBook.Buy.OK)
	assert_int(Game.inventory.count_of(&"blue_paint")).is_equal(0)
	assert_int(Game.inventory.wallet).is_equal(5000 - 980)
	var house: House = Game.interiors.player_house()
	if house != null:
		assert_int(house.next_outlook_pal).is_equal(ShopGoods.PAINTS.find(&"blue_paint"))


func test_stationery_is_a_four_sheet_pad() -> void:
	var shop: ShopBook = Game.shops
	shop.apply_snapshot({"shop0": {"goods": ["paper"], "renew": Clock.renew_index()}})
	Game.inventory.set_wallet(1000)
	assert_int(ShopBook.buy_price(ItemCatalog.get_item(&"paper"))).is_equal(160)
	shop.buy(ShopBook.NOOK_ID, &"paper", Game.inventory)
	assert_int(Game.inventory.count_of(&"paper")).is_equal(4)


# --- Selling -----------------------------------------------------------------------------


func test_nook_takes_worthless_items_for_free() -> void:
	var inv: Inventory = Game.inventory
	inv.add(ItemCatalog.get_item(&"grab_bag"), 1)
	var res: Dictionary = Game.shops.sell_result(ShopBook.NOOK_ID, &"grab_bag", inv, 1)
	assert_int(int(res["code"])).is_equal(ShopBook.Sell.JUNK)
	assert_int(inv.count_of(&"grab_bag")).is_equal(0)
	assert_int(inv.wallet).is_equal(0)


func test_quest_items_are_refused() -> void:
	var inv: Inventory = Game.inventory
	inv.add(ItemCatalog.get_item(&"wood_chair"), 1, InventoryItem.Condition.QUEST)
	var res: Dictionary = Game.shops.sell_result(ShopBook.NOOK_ID, &"wood_chair", inv, 1)
	assert_int(int(res["code"])).is_equal(ShopBook.Sell.QUEST)
	assert_int(inv.count_of(&"wood_chair")).is_equal(1)


func test_selling_earns_half_toward_sales() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"wood_chair"), 1)
	Game.shops.sell(ShopBook.NOOK_ID, &"wood_chair", Game.inventory, 1)
	assert_int(Game.inventory.wallet).is_equal(80)
	assert_int(Game.shops.sales_sum()).is_equal(40)


func test_foreign_fruit_sells_high() -> void:
	var cherry := ItemData.new()
	cherry.id = &"cherry"
	cherry.category = ItemData.Category.FRUIT
	cherry.sell_price = 100
	assert_int(ShopBook.sell_price(cherry)).is_equal(500)
	Game.town_fruit = &"cherry"
	assert_int(ShopBook.sell_price(cherry)).is_equal(100)


func test_wallet_overflow_becomes_bags() -> void:
	var inv: Inventory = Game.inventory
	inv.set_wallet(99900)
	var tv: ItemData = ItemCatalog.get_item(&"wood_tv")
	inv.add(tv, 1)
	var unit: int = ShopBook.sell_price(tv)
	Game.shops.sell(ShopBook.NOOK_ID, &"wood_tv", inv, 1)
	assert_int(inv.count_of(ShopBook.BAG_30000)).is_equal(1)
	assert_int(inv.wallet).is_equal(99900 + unit - 30000)
	## Full pockets and the sale frees no slot: Nook won't pay out.
	inv.clear()
	inv.set_wallet(99999)
	var shovel: ItemData = ItemCatalog.get_item(&"shovel")
	for _i: int in Inventory.POCKET_SLOTS - 1:
		inv.add(shovel, 1)
	inv.add(ItemCatalog.get_item(&"apple"), 2)
	var res: Dictionary = Game.shops.sell_result(ShopBook.NOOK_ID, &"apple", inv, 1)
	assert_int(int(res["code"])).is_equal(ShopBook.Sell.OVERFLOW)
	assert_int(inv.count_of(&"apple")).is_equal(2)
	## Selling a whole slot frees room for the bag.
	res = Game.shops.sell_result(ShopBook.NOOK_ID, &"shovel", inv, 1)
	assert_int(int(res["code"])).is_equal(ShopBook.Sell.OK)
	assert_int(inv.count_of(ShopBook.BAG_30000)).is_equal(1)


# --- Turnips -----------------------------------------------------------------------------


func test_stalk_market_schedule() -> void:
	var market := KabuMarket.new()
	for _i: int in 50:
		market.decide_schedule(2001, 1, 7)
		assert_int(market.price_on(0)).is_between(70, 129)
		if market.trend == KabuMarket.Trend.FALLING:
			for d: int in range(1, 7):
				assert_int(market.price_on(d)).is_less_equal(market.price_on(d - 1))
		if market.trend == KabuMarket.Trend.SPIKE:
			var top: int = 0
			for d: int in range(1, 6):
				top = maxi(top, market.price_on(d))
			assert_int(top).is_equal(market.price_on(0) * 8)
	## Week starts on Sunday; a stale schedule re-rolls.
	market.update(2001, 1, 10)
	assert_int(market.week_ordinal).is_equal(EventDates.ordinal(2001, 1, 7))


func test_nook_buys_turnips_except_sundays() -> void:
	var inv: Inventory = Game.inventory
	inv.add(ItemCatalog.get_item(&"turnips_10"), 1)
	var price: int = Game.shops.kabu.price_today()
	var res: Dictionary = Game.shops.sell_result(ShopBook.NOOK_ID, &"turnips_10", inv, 1)
	assert_int(int(res["paid"])).is_equal(price * 10)
	## 2001-01-07 is a Sunday.
	_set_date(2001, 1, 7, 12)
	inv.add(ItemCatalog.get_item(&"turnips_50"), 1)
	res = Game.shops.sell_result(ShopBook.NOOK_ID, &"turnips_50", inv, 1)
	assert_int(int(res["code"])).is_equal(ShopBook.Sell.SUNDAY_TURNIPS)
	assert_int(inv.count_of(&"turnips_50")).is_equal(1)
	inv.add(ItemCatalog.get_item(KabuMarket.SPOILED), 1)
	res = Game.shops.sell_result(ShopBook.NOOK_ID, KabuMarket.SPOILED, inv, 1)
	assert_int(int(res["code"])).is_equal(ShopBook.Sell.JUNK)


# --- Catalog -----------------------------------------------------------------------------


func test_catalog_records_and_orders_arrive_next_morning() -> void:
	var inv: Inventory = Game.inventory
	inv.add(ItemCatalog.get_item(&"wood_table"), 1)
	inv.add(ItemCatalog.get_item(&"apple"), 1)
	assert_bool(Game.catalog.has(&"wood_table")).is_true()
	assert_bool(Game.catalog.has(&"apple")).is_false()
	inv.remove(&"wood_table", 1)
	inv.set_wallet(1000)
	assert_str(Game.shops.order(&"wood_chair", inv, Game.catalog)).contains("not in your catalog")
	assert_str(Game.shops.order(&"wood_table", inv, Game.catalog)).contains("Ordered")
	var price: int = ShopBook.buy_price(ItemCatalog.get_item(&"wood_table"))
	assert_int(inv.wallet).is_equal(1000 - price)
	assert_int(Game.shops.sales_sum()).is_equal(price)
	Clock.advance_minutes(20 * 60)
	var found: bool = false
	for i: int in Inventory.MAIL_SLOTS:
		var letter: MailData = inv.mail_at(i)
		if letter != null and letter.present_item_id == &"wood_table":
			found = true
	assert_bool(found).is_true()
	assert_int(Game.catalog.orders().size()).is_equal(0)


func test_five_order_slots() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"wood_table"), 1)
	Game.inventory.set_wallet(99999)
	for _i: int in CatalogBook.ORDER_SLOTS:
		assert_str(Game.shops.order(&"wood_table", Game.inventory, Game.catalog)).contains("Ordered")
	assert_str(Game.shops.order(&"wood_table", Game.inventory, Game.catalog)).contains("five")


# --- Raffle ------------------------------------------------------------------------------


func test_raffle_takes_five_tickets_and_pays_prizes_once() -> void:
	_set_date(2001, 1, 31, 12)
	var inv: Inventory = Game.inventory
	var ticket: ItemData = ItemCatalog.get_item(&"ticket_01")
	inv.add(ticket, 4)
	assert_str(str(Game.shops.draw_lottery(inv)["code"])).is_equal("tickets")
	inv.add(ticket, 6)
	var prizes: Array[StringName] = Game.shops.lottery_prizes()
	var first: Dictionary = Game.shops.draw_lottery(inv, 0)
	assert_str(str(first["code"])).is_equal("win")
	assert_int(int(first["place"])).is_equal(1)
	assert_int(inv.count_of(prizes[0])).is_greater_equal(1)
	assert_int(Game.shops.ticket_count(inv)).is_equal(5)
	## First prize is gone now: the same roll misses.
	assert_str(str(Game.shops.draw_lottery(inv, 0)["code"])).is_equal("miss")
	assert_int(Game.shops.ticket_count(inv)).is_equal(0)
	## Last month's tickets don't count.
	inv.add(ItemCatalog.get_item(&"ticket_12"), 5)
	assert_str(str(Game.shops.draw_lottery(inv)["code"])).is_equal("tickets")


func test_raffle_odds() -> void:
	_set_date(2001, 1, 31, 12)
	var ticket: ItemData = ItemCatalog.get_item(&"ticket_01")
	Game.inventory.add(ticket, 5)
	assert_int(int(Game.shops.draw_lottery(Game.inventory, 14)["place"])).is_equal(2)
	Game.inventory.add(ticket, 5)
	assert_int(int(Game.shops.draw_lottery(Game.inventory, 34)["place"])).is_equal(3)
	Game.inventory.add(ticket, 5)
	assert_str(str(Game.shops.draw_lottery(Game.inventory, 35)["code"])).is_equal("miss")


# --- Talk --------------------------------------------------------------------------------


func test_offer_talk_buys_and_reports_ticket() -> void:
	Game.shops.apply_snapshot({"shop0": {"goods": ["wood_chair"], "renew": Clock.renew_index()}})
	Game.inventory.set_wallet(1000)
	var ctx := DialogueContext.new()
	NookShopTalk.fill_offer(ctx, &"wood_chair")
	assert_str(ctx.frees[0]).is_equal("320")
	NookShopTalk.apply_event({"op": "nook_shop", "action": "buy"}, ctx)
	assert_str(str(ctx.get_var(NookShopTalk.VAR_BUY))).is_equal("ok")
	assert_str(str(ctx.get_var(NookShopTalk.VAR_TICKET))).is_equal("pocket")
	var res: Dictionary = NookShopTalk.apply_event({"op": "nook_shop", "action": "sell"}, ctx)
	assert_that(res["open"]).is_equal(&"sell")
	res = NookShopTalk.apply_event({"op": "nook_shop", "action": "order"}, ctx)
	assert_that(res["open"]).is_equal(&"order")


func test_store_dialogues_load() -> void:
	for conv_id: StringName in [NookShopTalk.MENU_ID, NookShopTalk.OFFER_ID, NookShopTalk.LOTTERY_ID]:
		assert_that(DialogueCatalog.conversation(conv_id)).is_not_null()


func test_shop_state_round_trips() -> void:
	Game.shops.plus_sales(ShopBook.COMBINI_SUM)
	Game.shops.set_visitor()
	Game.shops.kabu.decide_schedule(2001, 1, 7)
	var sunday: int = Game.shops.kabu.price_on(0)
	Game.inventory.add(ItemCatalog.get_item(&"wood_table"), 1)
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_int(Game.shops.renewal_day()).is_equal(EventDates.ordinal(2001, 1, 12))
	assert_bool(Game.shops.has_visitor()).is_true()
	assert_int(Game.shops.kabu.price_on(0)).is_equal(sunday)
	assert_bool(Game.catalog.has(&"wood_table")).is_true()
