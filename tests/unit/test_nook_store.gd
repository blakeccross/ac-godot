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
	## Still open today; closed all of the day before reopening (`mSP_InRenewal` date match).
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.OPEN)
	_set_date(2001, 1, 11, 8)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.RENEW)
	_set_date(2001, 1, 11, 12)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.RENEW)
	assert_str(shop.closed_notice()).contains("renovation")
	## The upgrade lands at any hour of the booked day; Nook 'n' Go then opens at 7.
	_set_date(2001, 1, 12, 6)
	assert_int(shop.nook_status()).is_equal(ShopBook.Status.PRE)
	assert_str(shop.closed_notice()).contains("7:00")
	assert_int(shop.nook_level()).is_equal(1)
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
	assert_int(ItemCatalog.get_item(&"paper").max_stack).is_equal(4)


## `ac_npc_shop_common.c` `mPr_GetPossessionItemIdx(EMPTY_NO)`: a purchase needs a truly
## empty pocket, even when a partial stack of the same thing could take it.
func test_purchase_needs_an_empty_pocket() -> void:
	var shop: ShopBook = Game.shops
	shop.apply_snapshot({"shop0": {"goods": ["paper", "paper"], "renew": Clock.renew_index()}})
	var inv: Inventory = Game.inventory
	inv.set_wallet(1000)
	var paper: ItemData = ItemCatalog.get_item(&"paper")
	var shovel: ItemData = ItemCatalog.get_item(&"shovel")
	inv.add(paper, 1)
	for _i: int in Inventory.POCKET_SLOTS - 1:
		inv.add(shovel, 1)
	var res: Dictionary = shop.buy_result(ShopBook.NOOK_ID, &"paper", inv)
	assert_int(int(res["code"])).is_equal(ShopBook.Buy.POCKETS_FULL)
	assert_int(inv.wallet).is_equal(1000)
	## With a free pocket the whole pad goes there, not onto the partial stack.
	inv.remove(&"shovel", 1)
	res = shop.buy_result(ShopBook.NOOK_ID, &"paper", inv)
	assert_int(int(res["code"])).is_equal(ShopBook.Buy.OK)
	assert_int(inv.count_of(&"paper")).is_equal(5)
	assert_int(inv.empty_slot_count()).is_equal(0)


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


## `m_shop.c` `mSP_ItemNo2ItemPrice` / `SELL_BUY_RATIO`: fish and bugs pay a quarter of
## `fish_price_table` / `insect_price_table`.
func test_fish_and_bugs_sell_for_a_quarter_of_the_rom_price() -> void:
	var expected: Dictionary = {
		&"ant": 80, &"bee": 4500, &"giant_beetle": 10000, &"cockroach": 5,
		&"sea_bass": 120, &"coelacanth": 15000, &"crucian_carp": 120, &"stringfish": 15000,
	}
	for item_id: StringName in expected:
		var data: ItemData = ItemCatalog.get_item(item_id)
		assert_that(data).is_not_null()
		assert_int(ShopBook.sell_price(data)).is_equal(int(expected[item_id]))
	Game.inventory.add(ItemCatalog.get_item(&"sea_bass"), 1)
	Game.shops.sell(ShopBook.NOOK_ID, &"sea_bass", Game.inventory, 1)
	assert_int(Game.inventory.wallet).is_equal(120)


## `mSM_check_item_for_sell`: money bags are not in the sell menu.
func test_money_bags_are_not_for_sale() -> void:
	var inv: Inventory = Game.inventory
	inv.add(ItemCatalog.get_item(&"money_1000"), 1)
	var quote: Dictionary = Game.shops.sell_quote(&"money_1000", inv)
	assert_int(int(quote["code"])).is_equal(ShopBook.Sell.REFUSED)
	assert_int(int(quote["count"])).is_equal(0)
	var res: Dictionary = Game.shops.sell_result(ShopBook.NOOK_ID, &"money_1000", inv, 1)
	assert_int(int(res["code"])).is_equal(ShopBook.Sell.REFUSED)
	assert_int(inv.count_of(&"money_1000")).is_equal(1)
	assert_int(inv.wallet).is_equal(0)


## `aNSC_check_money_overflow`: a wallet reaching exactly 99,999 already spills a bag.
func test_wallet_at_max_spills_a_bag() -> void:
	var inv: Inventory = Game.inventory
	inv.set_wallet(99999 - 80)
	inv.add(ItemCatalog.get_item(&"wood_chair"), 1)
	assert_int(ShopBook.bags_needed(inv, 80)).is_equal(1)
	Game.shops.sell(ShopBook.NOOK_ID, &"wood_chair", inv, 1)
	assert_int(inv.count_of(ShopBook.BAG_30000)).is_equal(1)
	assert_int(inv.wallet).is_equal(99999 - 30000)


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


## `Kabu_get_price` is a plain read; `Kabu_manager` only runs on a date change / game start.
func test_stalk_market_reads_do_not_reroll() -> void:
	var market: KabuMarket = Game.shops.kabu
	## 2001-01-07 is a Sunday: many reads leave the trend chain and the week alone.
	_set_date(2001, 1, 7, 12)
	market.clear()
	var sunday: int = market.price_today()
	var before: Dictionary = market.to_save()
	var rng_state: int = market.rng.state
	for _i: int in 20:
		assert_int(market.price_today()).is_equal(sunday)
	assert_that(market.to_save()).is_equal(before)
	assert_int(market.rng.state).is_equal(rng_state)
	## Through the week too, Monday to Saturday.
	for d: int in range(8, 14):
		_set_date(2001, 1, d, 12)
		var price: int = market.price_today()
		assert_int(market.price_today()).is_equal(price)
		assert_int(price).is_equal(int((before["prices"] as Array)[d - 7]))
	assert_int(market.rng.state).is_equal(rng_state)
	## The next Sunday's date change rolls a new week once.
	_set_date(2001, 1, 14, 0)
	market.update(Clock.year, Clock.month, Clock.day)
	assert_int(market.week_ordinal).is_equal(EventDates.ordinal(2001, 1, 14))
	var rolled: int = market.rng.state
	market.price_today()
	assert_int(market.rng.state).is_equal(rolled)


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


# --- Counter talk flow -------------------------------------------------------------------


## Stand-in Nook: records what the shop paper hands back to him.
class PaperNook:
	extends Node
	var sold: Array = []
	var ordered: Array = []

	func quote_sell(item_id: StringName, count: int) -> bool:
		sold.append([item_id, count])
		return true

	func quote_order(item_id: StringName) -> bool:
		ordered.append(item_id)
		return true


func _run(conv_id: StringName, ctx: DialogueContext) -> DialogueRunner:
	var runner := DialogueRunner.new()
	runner.event_fired.connect(func(event: Dictionary) -> void: NookShopTalk.apply_event(event, ctx))
	runner.start(DialogueCatalog.conversation(conv_id), ctx)
	return runner


## Advance lines until a choice or the end.
func _to_choice(runner: DialogueRunner) -> void:
	var guard: int = 0
	while not runner.done and not runner.waiting_choice and guard < 16:
		runner.advance()
		guard += 1


func test_selling_asks_yes_no_with_the_total_first() -> void:
	## `aNSC_msg_win_open_wait` → `SELL_OFFER` → `aNSC_buy_check`.
	var inv: Inventory = Game.inventory
	inv.set_wallet(0)
	inv.add(ItemCatalog.get_item(&"wood_chair"), 2)
	var total: int = int(Game.shops.sell_quote(&"wood_chair", inv, 2)["total"])
	var ctx := DialogueContext.new()
	NookShopTalk.fill_sell(ctx, &"wood_chair", 2)
	assert_str(str(ctx.get_var(NookShopTalk.VAR_DEAL))).is_equal("sell_many")
	assert_str(ctx.frees[0]).is_equal(str(total))
	var runner := _run(NookShopTalk.DEAL_ID, ctx)
	_to_choice(runner)
	assert_bool(runner.waiting_choice).is_true()
	assert_int(inv.count_of(&"wood_chair")).is_equal(2)
	runner.choose(1)
	assert_int(inv.count_of(&"wood_chair")).is_equal(2)
	assert_int(inv.wallet).is_equal(0)
	runner = _run(NookShopTalk.DEAL_ID, ctx)
	_to_choice(runner)
	runner.choose(0)
	assert_int(inv.count_of(&"wood_chair")).is_equal(0)
	assert_int(inv.wallet).is_equal(total)
	## `SELL_NORMAL`: anything else to sell?
	_to_choice(runner)
	assert_str(String(runner.node_id)).is_equal("sell_more")


func test_catalog_order_asks_yes_no_first() -> void:
	## `aNSC_msg_win_open_wait2` → `ORDER_OFFER` → `aNSC_order_check`.
	var inv: Inventory = Game.inventory
	inv.add(ItemCatalog.get_item(&"wood_table"), 1)
	inv.set_wallet(5000)
	var price: int = ShopBook.buy_price(ItemCatalog.get_item(&"wood_table"))
	var ctx := DialogueContext.new()
	NookShopTalk.fill_order(ctx, &"wood_table")
	var runner := _run(NookShopTalk.DEAL_ID, ctx)
	_to_choice(runner)
	assert_int(Game.catalog.orders().size()).is_equal(0)
	runner.choose(1)
	assert_int(Game.catalog.orders().size()).is_equal(0)
	runner = _run(NookShopTalk.DEAL_ID, ctx)
	_to_choice(runner)
	runner.choose(0)
	assert_int(Game.catalog.orders().size()).is_equal(1)
	assert_int(inv.wallet).is_equal(5000 - price)
	## Short on Bells: refused, nothing ordered.
	inv.set_wallet(0)
	runner = _run(NookShopTalk.DEAL_ID, ctx)
	_to_choice(runner)
	runner.choose(0)
	assert_str(str(ctx.get_var(NookShopTalk.VAR_DEAL_RESULT))).is_equal("no_money")
	assert_int(Game.catalog.orders().size()).is_equal(1)


func test_shop_paper_has_no_buy_tab_and_hands_picks_to_nook() -> void:
	var paper: Node = load("res://scenes/ui/shop_overlay.tscn").instantiate()
	add_child(paper)
	auto_free(paper)
	var nook := PaperNook.new()
	nook.add_to_group("tom_nook")
	add_child(nook)
	auto_free(nook)
	Game.inventory.add(ItemCatalog.get_item(&"wood_chair"), 1)
	paper.call("open", ShopBook.NOOK_ID, Interaction.BUY)
	assert_that(paper.get("_mode")).is_equal(Interaction.SELL)
	paper.call("_on_row_pressed", 0)
	## Nothing sold yet: Nook quotes and asks first.
	assert_int(Game.inventory.count_of(&"wood_chair")).is_equal(1)
	assert_int(nook.sold.size()).is_equal(1)
	assert_bool(bool(paper.call("is_open"))).is_false()
	Game.inventory.add(ItemCatalog.get_item(&"wood_table"), 1)
	paper.call("open", ShopBook.NOOK_ID, ShopUse.ORDER)
	paper.call("_on_row_pressed", 0)
	assert_int(nook.ordered.size()).is_equal(1)
	assert_int(Game.catalog.orders().size()).is_equal(0)


func test_nook_greets_every_entry_and_offers_the_house_once_paid() -> void:
	## `aNSC_start_wait`: `START_CALL_NORMAL`, or house business (`..._start_wait1`).
	var house: House = Game.interiors.player_house()
	Game.inventory.set_loan(19800)
	var welcome: DialogueData = NookShopTalk.line(NookShopTalk.WELCOME_BANK, NookShopTalk.WELCOME_ID)
	assert_that(welcome).is_not_null()
	var talk: Dictionary = NookShopTalk.entry_talk(house, Game.inventory, 0)
	assert_that(talk["data"]).is_equal(welcome)
	## Every entry, not only the first.
	assert_that(NookShopTalk.entry_talk(house, Game.inventory, 0)["data"]).is_equal(welcome)
	Game.inventory.set_loan(0)
	talk = NookShopTalk.entry_talk(house, Game.inventory, 0)
	assert_that((talk["data"] as DialogueData).id).is_equal(NookHouseTalk.DIALOGUE_ID)
	assert_that(talk["house"]["scene"]).is_equal(HouseUpgrade.OFFER_MEDIUM)
	## A, by contrast, opens the counter menu.
	assert_that(NookShopTalk.counter_talk().id).is_equal(NookShopTalk.MENU_ID)


func test_nook_says_goodbye_facing_the_shop_exit() -> void:
	## `aNSC_message_ctrl` → `GOODBYE_WAIT` → `SAY_GOODBYE`.
	var room: Room = InteriorCatalog.room_template(&"shop0")
	var session := IndoorSession.new()
	session.bind(room)
	var door: Vector2i = room.door_cell
	var inside: Vector3 = session.grid.cell_to_world(Vector2i(door.x, door.y - 1))
	var at_door: Vector3 = session.grid.cell_to_world(door)
	var yaw: float = atan2(at_door.x - inside.x, at_door.z - inside.z)
	assert_bool(session.facing_exit(inside, yaw)).is_true()
	## Just walked in, facing the shop: no goodbye.
	assert_bool(session.facing_exit(inside, yaw + PI)).is_false()
	var deeper: Vector3 = session.grid.cell_to_world(Vector2i(door.x, door.y - 2))
	assert_bool(session.facing_exit(deeper, yaw)).is_false()
	assert_that(NookShopTalk.line(NookShopTalk.GOODBYE_BANK, NookShopTalk.GOODBYE_ID)).is_not_null()


func test_raffle_day_nook_only_runs_the_raffle() -> void:
	## `ac_npc_shop_mastersp`: no entry greeting, no house talk, prizes aren't for sale.
	_set_date(2001, 1, 31, 12)
	Game.inventory.set_loan(0)
	var house: House = Game.interiors.player_house()
	assert_bool(NookShopTalk.entry_talk(house, Game.inventory, 0).is_empty()).is_true()
	assert_that(NookShopTalk.counter_talk().id).is_equal(NookShopTalk.LOTTERY_ID)
	var shelf: DialogueData = NookShopTalk.line(
		NookShopTalk.LOTTERY_SHELF_BANK, NookShopTalk.LOTTERY_SHELF_ID
	)
	assert_that(NookShopTalk.shelf_talk()).is_equal(shelf)
	## Every prize won: he says so instead of offering a spin.
	var ticket: ItemData = ItemCatalog.get_item(&"ticket_01")
	for place: int in 3:
		Game.inventory.add(ticket, 5)
		Game.shops.draw_lottery(Game.inventory, [0, 10, 20][place])
	assert_bool(NookShopTalk.lottery_empty()).is_true()
	var empty: DialogueData = NookShopTalk.line(
		NookShopTalk.LOTTERY_EMPTY_BANK, NookShopTalk.LOTTERY_EMPTY_ID
	)
	assert_that(NookShopTalk.counter_talk()).is_equal(empty)
	## The day after, the shelf offer is back.
	_set_date(2001, 2, 1, 12)
	assert_that(NookShopTalk.shelf_talk().id).is_equal(NookShopTalk.OFFER_ID)


func test_tool_purchase_has_its_own_line() -> void:
	## `aNSC_sell_answer0`: `SELL_NET` / `AXE` / `SHOVEL` / `ROD` / `SIGN`.
	var cases: Dictionary = {
		&"net": "tool_net", &"axe": "tool_axe", &"shovel": "tool_shovel",
		&"fishing_rod": "tool_rod", &"signboard": "tool_sign", &"wood_chair": "ticket",
	}
	for item_id: StringName in cases:
		Game.shops.apply_snapshot({"shop0": {"goods": [String(item_id)], "renew": Clock.renew_index()}})
		Game.inventory.set_wallet(99999)
		var ctx := DialogueContext.new()
		NookShopTalk.fill_offer(ctx, item_id)
		var runner := _run(NookShopTalk.OFFER_ID, ctx)
		_to_choice(runner)
		runner.choose(0)
		assert_str(String(runner.node_id)).override_failure_message(String(item_id)).is_equal(
			str(cases[item_id])
		)


func test_shelf_goods_are_not_sold_after_closing() -> void:
	## `mSP_ShopOpen`: the door hours bound the counter too.
	var listed: Array[StringName] = Game.shops.goods(ShopBook.NOOK_ID)
	assert_bool(listed.is_empty()).is_false()
	Game.inventory.set_wallet(99999)
	_set_date(2001, 1, 10, 23)
	assert_bool(Game.shops.nook_is_open()).is_false()
	var res: Dictionary = Game.shops.buy_result(ShopBook.NOOK_ID, listed[0], Game.inventory)
	assert_int(int(res["code"])).is_equal(ShopBook.Buy.CLOSED)
	assert_int(Game.inventory.wallet).is_equal(99999)
	_set_date(2001, 1, 10, 12)
	res = Game.shops.buy_result(ShopBook.NOOK_ID, listed[0], Game.inventory)
	assert_int(int(res["code"])).is_not_equal(ShopBook.Buy.CLOSED)
