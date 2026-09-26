class_name ShopBook
extends RefCounted

## Town shops. Owned by `Game`, not an autoload. Nook buys and sells; Able Sisters is a
## design shop with no Bell stock (`needlework`).
##
## Nook (`m_shop.c`, `ac_npc_shop_common.c`, `ac_shop_level.c`, `ac_npc_shop_mastersp`):
## - Lineup rerolls at 06:00 (`ShopGoods.roll`); sold listings stay empty until then.
## - `level` is stored (`shop_info.shop_level`). Sales (`mSP_PlusSales`) cap at the next
##   threshold, and once they reach it a two-day renovation is booked (`aSL_JudgeRenewShop`):
##   closed from opening time the day before, reopening upgraded on the booked day.
##   Nookington's also needs a visitor from another town (`visitor_flag`).
## - Hours by level; the last day of the month is raffle day (opens at 10, no goods).
## - Buying: bags in the pockets make up a short wallet (`mSP_money_check`); furniture,
##   clothes, wallpaper, carpet and umbrellas come with a raffle ticket (mailed if the
##   pockets are full); paint repaints the roof instead of going in the pockets.
## - Selling: catalog / 4 (`SELL_BUY_RATIO`), foreign fruit 2000 / 4, turnips at the
##   Stalk Market price (not on Sundays); worthless items are taken for free; quest items
##   are refused; wallet overflow becomes 30,000-bell bags. Sales earn half of what Nook pays.
## - Catalog orders (5 slots) arrive by mail the next morning.

enum Status { PRE, END, OPEN, RENEW }
enum Buy { OK, SOLD_OUT, NOT_FOR_SALE, POCKETS_FULL, NO_MONEY, CLOSED }
enum Sell { OK, JUNK, REFUSED, QUEST, SUNDAY_TURNIPS, NOTHING, OVERFLOW }

const NOOK_ID := &"shop0"
const ABLE_ID := &"needlework"
const SELL_RATIO := 4
const SHOP_IDS: Array[StringName] = [NOOK_ID, ABLE_ID]
## Sales thresholds → Cranny / Nook 'n' Go / Nookway / Nookington's.
const COMBINI_SUM := 25000
const SUPER_SUM := 90000
const DSUPER_SUM := 240000
const LEVEL_SUMS: Array[int] = [0, COMBINI_SUM, SUPER_SUM, DSUPER_SUM]
const NOOK_ROOM_IDS: Array[StringName] = [&"shop0", &"shop1", &"shop2", &"shop3_1"]
const NOOK_VISUAL_IDS: Array[StringName] = [
	&"obj_s_shop1", &"obj_s_shop2", &"obj_s_shop3", &"obj_s_shop4"
]
## `mSP_GetShopOpenTime` / `mSP_GetShopCloseTime`.
const OPEN_HOURS: Array[int] = [9, 7, 9, 9]
const CLOSE_HOURS: Array[int] = [22, 23, 22, 22]
const LOTTERY_OPEN_HOUR := 10
const SIGNBOARD_PRICE := 500
const FOREIGN_FRUIT_PRICE := 2000
## `mSP_ItemNo2ItemPrice` fruit special case (coconuts are not in it).
const FRUITS: Array[StringName] = [&"apple", &"cherry", &"pear", &"peach", &"orange"]
## Raffle (`aSHM_REQ_TICKET_NUM`, `aSHM_*_PLACE_PERCENT`, `aNSC_MAX_TICKETS`).
const TICKETS_PER_DRAW := 5
const TICKET_STACK := 5
const PRIZE_ODDS: Array[int] = [5, 15, 35]
const MAX_MAILED_TICKETS := 255
const BAG_30000 := &"money_30000"
## `mSP_sack_amount` / `mSP_itemNo`: sacks count toward a short wallet, smallest first.
const SACKS: Array[StringName] = [&"money_100", &"money_1000", &"money_10000", &"money_30000"]

var kabu: KabuMarket = KabuMarket.new()
var _shops: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	_shops.clear()
	kabu.clear()


func shop(shop_id: StringName) -> Dictionary:
	if shop_id == &"":
		return {}
	ensure_today(shop_id)
	return _shops[shop_id] as Dictionary


func goods(shop_id: StringName) -> Array[StringName]:
	var row: Dictionary = shop(shop_id)
	return _string_names(row.get("goods", []))


func allows_sell(shop_id: StringName) -> bool:
	return shop_id == NOOK_ID


func is_shop_room(room: Room) -> bool:
	return room != null and (room.kind == Room.Kind.SHOP or room.kind == Room.Kind.NEEDLEWORK)


func shop_id_for_room(room: Room) -> StringName:
	if room == null:
		return &""
	if room.id == ABLE_ID or room.kind == Room.Kind.NEEDLEWORK:
		return ABLE_ID
	if room.kind == Room.Kind.SHOP:
		return NOOK_ID
	return &""


# --- Prices ------------------------------------------------------------------------------


static func buy_price(item: ItemData) -> int:
	if item == null:
		return 0
	if item.id == ShopGoods.GRAB_BAG:
		## `mSP_ItemNo2ItemPrice(ITM_HUKUBUKURO_BAG)` returns the year.
		return Clock.year if Clock != null else 2001
	if item.id == ShopGoods.SIGNBOARD:
		return SIGNBOARD_PRICE
	if item.buy_price > 0:
		return item.buy_price * ShopGoods.pack_count(item.id)
	return maxi(item.sell_price, 0)


## What Nook pays for one of `item`.
static func sell_price(item: ItemData) -> int:
	if item == null:
		return 0
	if KabuMarket.is_turnip(item.id):
		return 0
	if item.id in FRUITS and item.id != town_fruit():
		return FOREIGN_FRUIT_PRICE / SELL_RATIO
	match item.category:
		ItemData.Category.FRUIT, ItemData.Category.FISH, ItemData.Category.BUG:
			return maxi(item.sell_price, 0)
		_:
			var unit: int = item.buy_price if item.buy_price > 0 else maxi(item.sell_price, 0)
			if item.id == ShopGoods.SIGNBOARD:
				unit = SIGNBOARD_PRICE
			return unit / SELL_RATIO


static func town_fruit() -> StringName:
	if Game != null and "town_fruit" in Game:
		return Game.town_fruit
	return &"apple"


## Nook's price for one turnip bundle today (0 on Sunday — Joan's day).
func turnip_price(item_id: StringName) -> int:
	if item_id == KabuMarket.SPOILED:
		return 0
	return kabu.price_today() * KabuMarket.bundle_size(item_id)


# --- Level, renovation, hours ------------------------------------------------------------


func sales_sum(shop_id: StringName = NOOK_ID) -> int:
	if not _shops.has(shop_id):
		return 0
	return int((_shops[shop_id] as Dictionary).get("sales", 0))


## 0 Cranny · 1 Nook 'n' Go · 2 Nookway · 3 Nookington's (the building you walk into).
func nook_level() -> int:
	_ensure_row(NOOK_ID)
	_apply_due_renewal()
	return int(_nook().get("level", 0))


## `mSP_GetRealShopLevel`: what the sales have earned.
func real_level() -> int:
	var sales: int = sales_sum(NOOK_ID)
	if sales >= DSUPER_SUM and bool(_nook().get("visitor", false)):
		return 3
	if sales >= SUPER_SUM:
		return 2
	if sales >= COMBINI_SUM:
		return 1
	return 0


## `mSP_SetNewVisitor`: a player from another town shopped here.
func set_visitor() -> void:
	_ensure_row(NOOK_ID)
	_nook()["visitor"] = true


func has_visitor() -> bool:
	return bool(_nook().get("visitor", false))


## `mSP_PlusSales`: capped at the next building's threshold until the renovation lands.
func plus_sales(amount: int) -> void:
	if amount <= 0:
		return
	_ensure_row(NOOK_ID)
	var row: Dictionary = _nook()
	var level: int = int(row.get("level", 0))
	var total: int = int(row.get("sales", 0)) + amount
	if level < 3:
		total = mini(total, LEVEL_SUMS[level + 1])
	row["sales"] = total
	_judge_renewal()


func nook_room_id() -> StringName:
	return NOOK_ROOM_IDS[clampi(nook_level(), 0, NOOK_ROOM_IDS.size() - 1)]


func nook_visual_id() -> StringName:
	return NOOK_VISUAL_IDS[clampi(nook_level(), 0, NOOK_VISUAL_IDS.size() - 1)]


func nook_open_hour() -> int:
	if ShopGoods.is_lottery_day(Clock.year, Clock.month, Clock.day):
		return LOTTERY_OPEN_HOUR
	return OPEN_HOURS[clampi(nook_level(), 0, 3)]


func nook_close_hour() -> int:
	return CLOSE_HOURS[clampi(nook_level(), 0, 3)]


## Ordinal of the booked reopening day, or -1.
func renewal_day() -> int:
	return int(_nook().get("renewal", -1))


## `mSP_InRenewal`: from opening time the day before the booked day until it lands.
func in_renewal() -> bool:
	_ensure_row(NOOK_ID)
	_judge_renewal()
	var booked: int = renewal_day()
	if booked < 0:
		return false
	var today: int = _today()
	if today < booked - 1:
		return false
	if today == booked - 1:
		return Clock.hour >= OPEN_HOURS[clampi(int(_nook().get("level", 0)), 0, 3)]
	return true


## `mSP_ShopOpen`.
func nook_status() -> Status:
	## Forced open during the part-time job (`mEv_CheckFirstJob`).
	if Game != null and Game.first_job != null and Game.first_job.is_active():
		return Status.OPEN
	_apply_due_renewal()
	if in_renewal():
		return Status.RENEW
	var hour: int = Clock.hour
	if hour >= nook_open_hour() and hour < nook_close_hour():
		return Status.OPEN
	if hour >= ClockService.FIELD_RENEW_HOUR and hour < nook_open_hour():
		return Status.PRE
	return Status.END


func nook_is_open() -> bool:
	return nook_status() == Status.OPEN


func is_lottery_day() -> bool:
	return ShopGoods.is_lottery_day(Clock.year, Clock.month, Clock.day)


func closed_notice() -> String:
	match nook_status():
		Status.RENEW:
			return "Closed for renovations."
		Status.PRE:
			return "The shop opens at %d:00." % nook_open_hour()
		_:
			return "The shop is closed."


## `aSL_JudgeRenewShop`: book a renovation two days out once sales earn the next building,
## unless raffle day or Sale Day falls inside the window; cancel if the clock ran backwards.
func _judge_renewal() -> void:
	var row: Dictionary = _nook()
	var booked: int = int(row.get("renewal", -1))
	var today: int = _today()
	if booked >= 0:
		if today < booked - 2:
			row["renewal"] = -1
		return
	if int(row.get("level", 0)) >= real_level():
		return
	for offset: int in 3:
		var d: Vector3i = EventDates.from_ordinal(today + offset)
		if ShopGoods.is_lottery_day(d.x, d.y, d.z) or ShopGoods.is_grab_bag_day(d.x, d.y, d.z):
			return
		if offset == 0 and Game != null and Game.events != null and Game.events.is_active(&"shop_sale"):
			return
	row["renewal"] = today + 2
	_queue_mail({"kind": "renovation", "level": int(row.get("level", 0)), "day": today + 2})


## `aSL_RenewShop`: on the booked day from the new building's opening hour.
func _apply_due_renewal() -> void:
	var row: Dictionary = _nook()
	var booked: int = int(row.get("renewal", -1))
	if booked < 0:
		return
	var today: int = _today()
	var target: int = real_level()
	if today < booked or (today == booked and Clock.hour < OPEN_HOURS[target]):
		return
	row["renewal"] = -1
	if target > int(row.get("level", 0)):
		row["level"] = target
		_queue_mail({"kind": "grand_opening", "level": target})
		restock(NOOK_ID)


# --- Stock ------------------------------------------------------------------------------


func ensure_today(shop_id: StringName) -> void:
	if shop_id == &"":
		return
	_ensure_row(shop_id)
	if shop_id == NOOK_ID:
		_apply_due_renewal()
		_judge_renewal()
	var row: Dictionary = _shops[shop_id]
	## Sold-out shelves stay empty until 06:00. Do not restock just because `goods` is empty.
	if int(row.get("renew", -1)) == Clock.renew_index():
		return
	restock(shop_id)


func restock(shop_id: StringName) -> void:
	_ensure_row(shop_id)
	var row: Dictionary = _shops[shop_id]
	row["renew"] = Clock.renew_index()
	if shop_id != NOOK_ID:
		## Able Sisters is a design/pattern shop, not a clothing store — it holds no
		## Bell-priced stock. Designs are traded through Mabel (`ac_npc_needlework`).
		row["goods"] = []
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _day_seed(shop_id)
	var lineup: Dictionary = ShopGoods.roll(
		int(row.get("level", 0)), int(row.get("sales", 0)), Clock.year, Clock.month, Clock.day,
		int(row.get("paint", 0)), rng
	)
	row["goods"] = _as_strings(lineup["goods"] as Array[StringName])
	row["rare"] = String(lineup["rare"])
	row["paint"] = int(lineup["paint_index"])
	## `mSP_ExchangeLineUp_InGame`: the raffle prizes change with the month.
	var month_key: int = Clock.year * 12 + Clock.month
	if int(row.get("lottery_month", -1)) != month_key:
		row["lottery_month"] = month_key
		var owned: Array[StringName] = Game.catalog.owned_ids() if Game != null and Game.catalog != null else []
		row["lottery"] = _as_strings(ShopGoods.roll_lottery(owned, rng))


func renew(_days: int = 1) -> void:
	for shop_id: StringName in SHOP_IDS:
		if shop_id == NOOK_ID:
			_ensure_row(NOOK_ID)
			_apply_due_renewal()
			_judge_renewal()
		restock(shop_id)
	kabu.update(Clock.year, Clock.month, Clock.day)


# --- Buying ------------------------------------------------------------------------------


static func ticket_id(month: int) -> StringName:
	return StringName("ticket_%02d" % clampi(month, 1, 12))


## `aNSC_check_item_with_ticket`.
static func earns_ticket(data: ItemData) -> bool:
	if data == null:
		return false
	if data is FurnitureData:
		return true
	if data is ToolData:
		return (data as ToolData).kind == ToolData.Kind.UMBRELLA
	return data.category in [ItemData.Category.CLOTH, ItemData.Category.WALL, ItemData.Category.FLOOR]


static func is_paint(item_id: StringName) -> bool:
	return item_id in ShopGoods.PAINTS


## `mSP_money_check`: wallet plus normal money sacks.
static func can_afford(inv: Inventory, amount: int) -> bool:
	return inv != null and spendable(inv) >= amount


static func spendable(inv: Inventory) -> int:
	var total: int = inv.wallet
	for sack: StringName in SACKS:
		var data: ItemData = ItemCatalog.get_item(sack)
		if data != null:
			total += _normal_count(inv, sack) * data.bell_value
	return total


## `mSP_get_sell_price`: wallet first; otherwise open sacks smallest-first, change to the wallet.
static func pay(inv: Inventory, amount: int) -> bool:
	if not can_afford(inv, amount):
		return false
	if inv.wallet >= amount:
		inv.set_wallet(inv.wallet - amount)
		return true
	var money: int = inv.wallet
	for sack: StringName in SACKS:
		var data: ItemData = ItemCatalog.get_item(sack)
		if data == null:
			continue
		while money < amount and _normal_count(inv, sack) > 0:
			_remove_normal(inv, sack)
			money += data.bell_value
		if money >= amount:
			break
	inv.set_wallet(money - amount)
	return true


func buy(shop_id: StringName, item_id: StringName, inv: Inventory) -> String:
	return str(buy_result(shop_id, item_id, inv).get("msg", ""))


## The shelf sale (`aNSC_sell_answer0` / `aNSC_sell_item_init`).
func buy_result(shop_id: StringName, item_id: StringName, inv: Inventory) -> Dictionary:
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or inv == null:
		return {"code": Buy.NOT_FOR_SALE, "msg": "That's not for sale."}
	var listed: Array[StringName] = goods(shop_id)
	var slot: int = listed.find(item_id)
	if slot < 0:
		return {"code": Buy.SOLD_OUT, "msg": "That's sold out."}
	var price: int = buy_price(data)
	if price <= 0:
		return {"code": Buy.NOT_FOR_SALE, "msg": "That's not for sale."}
	if not can_afford(inv, price):
		return {"code": Buy.NO_MONEY, "msg": "Not enough Bells."}
	var paint: bool = is_paint(item_id)
	var count: int = ShopGoods.pack_count(item_id)
	if not paint and not inv.has_space_for(data, count):
		return {"code": Buy.POCKETS_FULL, "msg": "Pockets are full."}
	pay(inv, price)
	var out: Dictionary = {"code": Buy.OK, "price": price, "ticket": ""}
	if paint:
		## `next_outlook_pal` + `mPr_FLAG_UPDATE_OUTLOOK_PENDING`: the roof changes when the
		## next game starts (`mHm_CheckRehouseOrder` in `m_start_data_init`).
		var house: House = Game.interiors.player_house() if Game != null and Game.interiors != null else null
		if house != null:
			house.next_outlook_pal = ShopGoods.PAINTS.find(item_id)
		out["paint"] = ShopGoods.PAINTS.find(item_id)
		out["msg"] = "Your roof will be %s the next time you play." % (
			data.display_name.trim_suffix(" Paint").to_lower()
		)
	else:
		inv.add(data, count)
		out["msg"] = "Bought %s for %d Bells." % [data.display_name, price]
		if earns_ticket(data):
			out["ticket"] = _give_ticket(inv)
	listed.remove_at(slot)
	_set_goods(shop_id, listed)
	if shop_id == NOOK_ID:
		plus_sales(price)
	return out


## One raffle ticket for this month: stacks onto a same-month stack (max 5) or an empty
## slot (`mPlib_Get_space_putin_item_forTICKET`), else waits for tomorrow's mail
## (`aNSC_setup_ticket_remain`). Returns "pocket" or "mail".
func _give_ticket(inv: Inventory) -> String:
	var ticket: ItemData = ItemCatalog.get_item(ticket_id(Clock.month))
	if ticket != null and inv.has_space_for(ticket, 1):
		inv.add(ticket, 1)
		return "pocket"
	_ensure_row(NOOK_ID)
	var row: Dictionary = _nook()
	var stored: int = int(row.get("ticket_mail", 0))
	if int(row.get("ticket_month", 0)) != Clock.month:
		stored = 0
		row["ticket_month"] = Clock.month
	row["ticket_mail"] = mini(stored + 1, MAX_MAILED_TICKETS)
	return "mail"


func mailed_tickets() -> int:
	return int(_nook().get("ticket_mail", 0))


# --- Selling -----------------------------------------------------------------------------


## Quote for selling `count` of `item_id` from the pockets (`aNSC_check_buy_item_single` +
## `aNSC_buy_check_init`). Quest items never count; presents are skipped too.
func sell_quote(item_id: StringName, inv: Inventory, count: int = -1) -> Dictionary:
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or inv == null:
		return {"code": Sell.NOTHING, "count": 0, "total": 0}
	var have: int = _normal_count(inv, item_id)
	if have <= 0:
		var quest: bool = inv.count_of(item_id) > 0
		return {"code": Sell.QUEST if quest else Sell.NOTHING, "count": 0, "total": 0}
	var n: int = have if count < 0 else mini(count, have)
	if KabuMarket.is_turnip(item_id):
		if item_id == KabuMarket.SPOILED:
			return {"code": Sell.JUNK, "count": n, "total": 0, "unit": 0}
		if Clock.weekday() == 0:
			return {"code": Sell.SUNDAY_TURNIPS, "count": 0, "total": 0}
		var unit_kabu: int = turnip_price(item_id)
		return {"code": Sell.OK, "count": n, "total": unit_kabu * n, "unit": unit_kabu}
	var unit: int = sell_price(data)
	if unit <= 0:
		return {"code": Sell.JUNK, "count": n, "total": 0, "unit": 0}
	return {"code": Sell.OK, "count": n, "total": unit * n, "unit": unit}


## Pay out `amount`, spilling over 99,999 into 30,000-bell bags (`aNSC_check_money_overflow`).
## `freed` slots will empty as part of the same sale.
static func bags_needed(inv: Inventory, amount: int) -> int:
	var total: int = inv.wallet + amount
	var bags: int = 0
	while total > Inventory.WALLET_MAX:
		total -= 30000
		bags += 1
	return bags


func sell(shop_id: StringName, item_id: StringName, inv: Inventory, count: int = 1) -> String:
	return str(sell_result(shop_id, item_id, inv, count).get("msg", ""))


func sell_result(shop_id: StringName, item_id: StringName, inv: Inventory, count: int = 1) -> Dictionary:
	if not allows_sell(shop_id):
		return {"code": Sell.REFUSED, "msg": "They don't buy items here."}
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or inv == null or count == 0:
		return {"code": Sell.NOTHING, "msg": "Can't sell that."}
	var quote: Dictionary = sell_quote(item_id, inv, count)
	var code: int = int(quote["code"])
	match code:
		Sell.NOTHING:
			return {"code": code, "msg": "You don't have that."}
		Sell.QUEST:
			return {"code": code, "msg": "Nook won't take something you're delivering."}
		Sell.SUNDAY_TURNIPS:
			return {"code": code, "msg": "Nook doesn't buy turnips on Sundays."}
	var n: int = int(quote["count"])
	var paid: int = int(quote["total"])
	var freed: int = _slots_freed(inv, item_id, n)
	var bags: int = bags_needed(inv, paid)
	if bags > inv.empty_slot_count() + freed:
		return {"code": Sell.OVERFLOW, "msg": "You can't carry that many Bells."}
	_remove_normal(inv, item_id, n)
	var total: int = inv.wallet + paid
	var bag_data: ItemData = ItemCatalog.get_item(BAG_30000)
	for _i: int in bags:
		total -= 30000
		inv.add(bag_data, 1)
	inv.set_wallet(total)
	if shop_id == NOOK_ID:
		plus_sales(paid / 2)
	if code == Sell.JUNK:
		return {"code": code, "paid": 0, "msg": "Nook took the %s off your hands." % data.display_name}
	return {"code": code, "paid": paid, "msg": "Sold %s for %d Bells." % [data.display_name, paid]}


# --- Catalog orders ------------------------------------------------------------------------


## `aNSC_order_check`: pay now, delivered by tomorrow's mail.
func order(item_id: StringName, inv: Inventory, catalog: CatalogBook) -> String:
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or catalog == null or inv == null or not catalog.has(item_id):
		return "That's not in your catalog."
	if not CatalogBook.is_orderable(data):
		return "Sorry, that item can't be ordered."
	if not catalog.has_free_order():
		return "You already have five orders waiting."
	var price: int = buy_price(data)
	if not can_afford(inv, price):
		return "Not enough Bells."
	pay(inv, price)
	catalog.add_order(item_id, nook_level())
	plus_sales(price)
	return "Ordered %s for %d Bells. It arrives by mail tomorrow." % [data.display_name, price]


# --- Raffle --------------------------------------------------------------------------------


## This month's three prizes; "" marks one already won.
func lottery_prizes() -> Array[StringName]:
	_ensure_row(NOOK_ID)
	ensure_today(NOOK_ID)
	return _string_names(_nook().get("lottery", []))


func ticket_count(inv: Inventory, month: int = -1) -> int:
	return _normal_count(inv, ticket_id(Clock.month if month < 0 else month))


## `aSHM_talk_try` + `fukubiki_before_process`: five of this month's tickets per draw;
## 5% 1st, 10% 2nd, 20% 3rd prize, else a miss (and a prize already taken is a miss).
## Returns {code: "closed"|"tickets"|"pockets"|"win"|"miss", place, item, msg}.
func draw_lottery(inv: Inventory, roll: int = -1) -> Dictionary:
	if not is_lottery_day():
		return {"code": "closed", "msg": "The raffle is on the last day of the month."}
	if ticket_count(inv) < TICKETS_PER_DRAW:
		return {"code": "tickets", "msg": "You need five of this month's tickets."}
	## The prize needs a pocket once the five tickets are handed over.
	if inv.empty_slot_count() + _slots_freed(inv, ticket_id(Clock.month), TICKETS_PER_DRAW) <= 0:
		return {"code": "pockets", "msg": "Your pockets are full."}
	_remove_normal(inv, ticket_id(Clock.month), TICKETS_PER_DRAW)
	var r: int = roll if roll >= 0 else _rng.randi_range(0, 99)
	var place: int = -1
	for i: int in PRIZE_ODDS.size():
		if r < PRIZE_ODDS[i]:
			place = i
			break
	var prizes: Array[StringName] = lottery_prizes()
	if place < 0 or place >= prizes.size() or prizes[place] == &"":
		return {"code": "miss", "msg": "Too bad... not a winner."}
	var item_id: StringName = prizes[place]
	var data: ItemData = ItemCatalog.get_item(item_id)
	inv.add(data, 1, InventoryItem.Condition.PRESENT)
	prizes[place] = &""
	_nook()["lottery"] = _as_strings(prizes)
	return {
		"code": "win", "place": place + 1, "item": item_id,
		"msg": "Prize #%d! You won the %s!" % [place + 1, data.display_name if data != null else String(item_id)],
	}


# --- Sale-event balloon ------------------------------------------------------------------


## `aNSC_check_present_balloon`: on the shop sale event Nook hands the first visitor with
## a free pocket slot one balloon (`ITM_BALLOON_START + RANDOM(8)`), once a day.
func take_sale_balloon(inv: Inventory) -> StringName:
	if Game == null or Game.events == null or not Game.events.is_active(&"shop_sale"):
		return &""
	_ensure_row(NOOK_ID)
	var row: Dictionary = _nook()
	if int(row.get("balloon_day", -1)) == _today() or inv.empty_slot_count() <= 0:
		return &""
	var item_id: StringName = ShopGoods.BALLOONS[_rng.randi_range(0, ShopGoods.BALLOONS.size() - 1)]
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return &""
	row["balloon_day"] = _today()
	inv.add(data, 1, InventoryItem.Condition.PRESENT)
	return item_id


# --- Mail --------------------------------------------------------------------------------


## Letters due at this renew: renovation notices, grand opening, mailed raffle tickets.
func take_mail() -> Array[MailData]:
	_ensure_row(NOOK_ID)
	var row: Dictionary = _nook()
	var out: Array[MailData] = []
	var queue: Variant = row.get("mail", [])
	if typeof(queue) == TYPE_ARRAY:
		for entry: Variant in queue as Array:
			var spec: Dictionary = entry as Dictionary
			match str(spec.get("kind", "")):
				"renovation":
					out.append(ShopMail.renovation_notice(int(spec.get("level", 0)), int(spec.get("day", 0))))
				"grand_opening":
					out.append(ShopMail.grand_opening(int(spec.get("level", 0))))
	row["mail"] = []
	var stored: int = int(row.get("ticket_mail", 0))
	var month: int = int(row.get("ticket_month", Clock.month))
	while stored > 0:
		var n: int = mini(stored, TICKET_STACK)
		out.append(ShopMail.ticket_letter(month, n))
		stored -= n
	row["ticket_mail"] = 0
	return out


func _queue_mail(spec: Dictionary) -> void:
	var row: Dictionary = _nook()
	var queue: Array = row.get("mail", []) as Array
	queue.append(spec)
	row["mail"] = queue


# --- Save --------------------------------------------------------------------------------


func to_save() -> Dictionary:
	var out := {}
	for key: Variant in _shops.keys():
		out[str(key)] = (_shops[key] as Dictionary).duplicate(true)
	if kabu.week_ordinal >= 0:
		out["_kabu"] = kabu.to_save()
	return out


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for key: Variant in (data as Dictionary).keys():
		var row: Variant = (data as Dictionary)[key]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(key) == "_kabu":
			kabu.apply_snapshot(row)
			continue
		_shops[StringName(str(key))] = (row as Dictionary).duplicate(true)
	## Saves from before the stored level: the building matches what sales earned.
	if _shops.has(NOOK_ID) and not (_shops[NOOK_ID] as Dictionary).has("level"):
		(_shops[NOOK_ID] as Dictionary)["level"] = real_level()
	for shop_id: StringName in SHOP_IDS:
		ensure_today(shop_id)


# --- Internals -----------------------------------------------------------------------------


func _nook() -> Dictionary:
	_ensure_row(NOOK_ID)
	return _shops[NOOK_ID] as Dictionary


func _ensure_row(shop_id: StringName) -> void:
	if not _shops.has(shop_id):
		_shops[shop_id] = _empty(shop_id)


func _empty(shop_id: StringName) -> Dictionary:
	return {
		"id": String(shop_id), "goods": [], "sales": 0, "renew": -1, "level": 0,
		"renewal": -1, "visitor": false, "paint": 0,
	}


func _today() -> int:
	return EventDates.ordinal(Clock.year, Clock.month, Clock.day)


func _set_goods(shop_id: StringName, listed: Array[StringName]) -> void:
	_ensure_row(shop_id)
	(_shops[shop_id] as Dictionary)["goods"] = _as_strings(listed)


func _as_strings(listed: Array[StringName]) -> Array:
	var out: Array = []
	for item_id: StringName in listed:
		out.append(String(item_id))
	return out


static func _string_names(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw as Array:
		out.append(StringName(str(entry)))
	return out


func _day_seed(shop_id: StringName) -> int:
	var seed_value: int = Game.world_seed if Game != null else 1
	return hash([seed_value, Clock.year, Clock.month, Clock.day, String(shop_id)])


static func _normal_count(inv: Inventory, item_id: StringName) -> int:
	var total: int = 0
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(i)
		if slot == null or slot.is_empty() or slot.item.item_id != item_id:
			continue
		if slot.item.condition == InventoryItem.Condition.NORMAL:
			total += slot.item.count
	return total


static func _remove_normal(inv: Inventory, item_id: StringName, count: int = 1) -> void:
	var remaining: int = count
	for i: int in range(Inventory.POCKET_SLOTS - 1, -1, -1):
		if remaining <= 0:
			return
		var slot: InventorySlot = inv.slot_at(i)
		if slot == null or slot.is_empty() or slot.item.item_id != item_id:
			continue
		if slot.item.condition != InventoryItem.Condition.NORMAL:
			continue
		var take: int = mini(slot.item.count, remaining)
		inv.remove_from_slot(i, take)
		remaining -= take


static func _slots_freed(inv: Inventory, item_id: StringName, count: int) -> int:
	var remaining: int = count
	var freed: int = 0
	for i: int in range(Inventory.POCKET_SLOTS - 1, -1, -1):
		if remaining <= 0:
			break
		var slot: InventorySlot = inv.slot_at(i)
		if slot == null or slot.is_empty() or slot.item.item_id != item_id:
			continue
		if slot.item.condition != InventoryItem.Condition.NORMAL:
			continue
		if slot.item.count <= remaining:
			freed += 1
		remaining -= slot.item.count
	return freed


## Kept for callers of the old API.
static func umbrella_pool() -> Array[StringName]:
	return ShopGoods.umbrella_pool()
