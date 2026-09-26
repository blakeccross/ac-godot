class_name ShopGoods
extends RefCounted

## Nook's daily lineup (`mSP_MakeGoodsList` / `mSP_MakeRandomGoodsList` / `mSP_SelectTool` /
## `mSP_SelectPlant`) and the special-day calendar (`mSP_CheckFukubikiDay`,
## `mSP_Chk_HukubukuroSail`, `mSP_CheckHallowinDay`). Pure functions over a level, a sales
## sum and a date — `ShopBook` owns the state.
##
## Not modelled: the ABC priority lists (`mSP_GetGoodsPercent`), which only matter once
## the furniture/clothing catalog holds the full ROM lists.

enum Kind { PAPER, CLOTH, FTR, RARE_FTR, CARPET, WALL, SAPLING, TOOL, PLANT }

## `l_zakka_goods` / `l_conbini_goods` / `l_super_goods` / `l_dsuper_goods`.
const COUNTS: Array[Dictionary] = [
	{Kind.PAPER: 1, Kind.CLOTH: 1, Kind.FTR: 1, Kind.RARE_FTR: 0, Kind.CARPET: 1, Kind.WALL: 1,
		Kind.SAPLING: 1, Kind.TOOL: 2, Kind.PLANT: 2},
	{Kind.PAPER: 2, Kind.CLOTH: 2, Kind.FTR: 2, Kind.RARE_FTR: 0, Kind.CARPET: 1, Kind.WALL: 1,
		Kind.SAPLING: 1, Kind.TOOL: 3, Kind.PLANT: 3},
	{Kind.PAPER: 2, Kind.CLOTH: 3, Kind.FTR: 3, Kind.RARE_FTR: 1, Kind.CARPET: 2, Kind.WALL: 2,
		Kind.SAPLING: 2, Kind.TOOL: 2, Kind.PLANT: 4},
	{Kind.PAPER: 4, Kind.CLOTH: 5, Kind.FTR: 5, Kind.RARE_FTR: 1, Kind.CARPET: 3, Kind.WALL: 3,
		Kind.SAPLING: 3, Kind.TOOL: 3, Kind.PLANT: 5},
]

## `mSP_NET_SALES_SUM` / `ROD` / `AXE`: Cranny-only tool unlocks by lifetime sales.
const NET_SALES_SUM := 3000
const ROD_SALES_SUM := 8000
const AXE_SALES_SUM := 12000
## `mSP_SelectTool` table order: shovel, net, rod, axe.
const TOOL_TABLE: Array[StringName] = [&"shovel", &"net", &"fishing_rod", &"axe"]
## `ITM_RED_PAINT` … `ITM_BROWN_PAINT` (`PAINT_NUM` 12), rotated one per restock.
const PAINTS: Array[StringName] = [
	&"red_paint", &"orange_paint", &"yellow_paint", &"pale_green_paint", &"green_paint",
	&"sky_blue_paint", &"blue_paint", &"purple_paint", &"pink_paint", &"black_paint",
	&"white_paint", &"brown_paint",
]
## `ITM_WHITE_PANSY_BAG` … (`FLOWER_NUM` 9).
const FLOWER_BAGS: Array[StringName] = [
	&"white_pansy_bag", &"purple_pansy_bag", &"yellow_pansy_bag",
	&"white_cosmos_bag", &"pink_cosmos_bag", &"blue_cosmos_bag",
	&"red_tulip_bag", &"white_tulip_bag", &"yellow_tulip_bag",
]
## `ITM_YELLOW_PINWHEEL` … (grab-bag bonus).
const PINWHEELS: Array[StringName] = [
	&"yellow_pinwheel", &"red_pinwheel", &"tiger_pinwheel", &"green_pinwheel", &"pink_pinwheel",
]
## `ITM_BALLOON_START + RANDOM(8)`: the sale-event gift.
const BALLOONS: Array[StringName] = [
	&"red_balloon", &"yellow_balloon", &"blue_balloon", &"green_balloon", &"purple_balloon",
	&"bunny_p_balloon", &"bunny_b_balloon", &"bunny_o_balloon",
]
const SAPLING := &"sapling"
const CEDAR_SAPLING := &"cedar_sapling"
const SIGNBOARD := &"signboard"
const CANDY := &"candy"
const GRAB_BAG := &"grab_bag"
const PAPER := &"paper"
## Stationery is stocked as a 4-sheet pad (`binsen_list` entries sit at stack index 3).
const PAPER_PACK := 4
const LOTTERY_COUNT := 3


## `mSP_CheckFukubikiDay`: the last day of every month is raffle day.
static func is_lottery_day(year: int, month: int, day: int) -> bool:
	return day == EventDates.days_in_month(year, month)


## `mSP_Chk_HukubukuroSail`: Sale Day, the day after the 4th Thursday of November.
static func is_grab_bag_day(year: int, month: int, day: int) -> bool:
	return month == 11 and day == EventDates.nth_weekday_day(year, 11, 4, 4) + 1


## `mSP_CheckHallowinDay`: candy replaces the flower bags Oct 16–30.
static func is_halloween_stock(month: int, day: int) -> bool:
	return month == 10 and day >= 16 and day <= 30


## Units of `item_id` one shelf listing hands over (stationery comes as a pad).
static func pack_count(item_id: StringName) -> int:
	return PAPER_PACK if item_id == PAPER else 1


## One day's lineup. `paint_index` is the rotating paint colour; the result's
## `"paint_index"` is the next one to store.
static func roll(
	level: int, sales: int, year: int, month: int, day: int, paint_index: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var out: Dictionary = {"goods": [] as Array[StringName], "rare": &"", "paint_index": paint_index}
	if is_lottery_day(year, month, day):
		return out
	var lv: int = clampi(level, 0, COUNTS.size() - 1)
	var counts: Dictionary = COUNTS[lv]
	var goods: Array[StringName] = []
	var grab_bags: bool = is_grab_bag_day(year, month, day)
	if int(counts[Kind.RARE_FTR]) > 0:
		var rare: Array[StringName] = _pick(_rare_pool(), 1, rng)
		if not rare.is_empty():
			out["rare"] = rare[0]
			goods.append(rare[0])
	goods.append_array(_pick(furniture_pool(), int(counts[Kind.FTR]), rng))
	var bag_count: int = 0
	if grab_bags:
		bag_count += int(counts[Kind.PAPER]) + (1 if lv >= 2 else 0)
	else:
		for _i: int in int(counts[Kind.PAPER]):
			goods.append(PAPER)
	goods.append_array(_pick(_category_pool(ItemData.Category.CLOTH), int(counts[Kind.CLOTH]), rng))
	goods.append_array(_pick(_category_pool(ItemData.Category.FLOOR), int(counts[Kind.CARPET]), rng))
	goods.append_array(_pick(_category_pool(ItemData.Category.WALL), int(counts[Kind.WALL]), rng))
	if grab_bags:
		bag_count += int(counts[Kind.TOOL]) + int(counts[Kind.PLANT]) + int(counts[Kind.SAPLING])
		if lv >= 2:
			bag_count += 2
		for _i: int in bag_count:
			goods.append(GRAB_BAG)
		return _finish(out, goods)
	goods.append_array(tools(lv, sales, int(counts[Kind.TOOL]), rng))
	if lv >= 2:
		goods.append(PAINTS[posmod(paint_index, PAINTS.size())])
		out["paint_index"] = posmod(paint_index + 1, PAINTS.size())
		goods.append(SIGNBOARD)
	goods.append_array(_pick(umbrella_pool(), 1, rng))
	goods.append_array(
		plants(lv, int(counts[Kind.PLANT]), int(counts[Kind.SAPLING]), is_halloween_stock(month, day), rng)
	)
	return _finish(out, goods)


static func _finish(out: Dictionary, goods: Array[StringName]) -> Dictionary:
	var live: Array[StringName] = []
	for item_id: StringName in goods:
		if ItemCatalog.get_item(item_id) != null:
			live.append(item_id)
	out["goods"] = live
	return out


## `mSP_SelectTool`: the Cranny unlocks net / rod / axe by sales; bigger shops stock any.
static func tools(level: int, sales: int, count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var tool_max: int = 4
	if level <= 0:
		if sales < NET_SALES_SUM:
			tool_max = 1
		elif sales < ROD_SALES_SUM:
			tool_max = 2
		elif sales < AXE_SALES_SUM:
			tool_max = 3
	var allowed: Array[StringName] = []
	for i: int in tool_max:
		allowed.append(TOOL_TABLE[i])
	return _pick(allowed, mini(count, tool_max), rng)


## `mSP_SelectPlant`: Halloween turns the flower count into candy and saplings into flowers;
## Nookway+ swaps one sapling for a cedar; flower bags never repeat.
static func plants(
	level: int, flower_count: int, sapling_count: int, halloween: bool, rng: RandomNumberGenerator
) -> Array[StringName]:
	var out: Array[StringName] = []
	if halloween:
		for _i: int in flower_count:
			out.append(CANDY)
		flower_count = sapling_count
		sapling_count = 0
	if level >= 2 and sapling_count > 0:
		out.append(CEDAR_SAPLING)
		sapling_count -= 1
	for _i: int in sapling_count:
		out.append(SAPLING)
	out.append_array(_pick(FLOWER_BAGS, flower_count, rng))
	return out


## `mSP_MakeLotteryList`: three raffle prizes, the first one the player doesn't own yet.
static func roll_lottery(owned: Array[StringName], rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = furniture_pool()
	var fresh: Array[StringName] = []
	for item_id: StringName in pool:
		if not owned.has(item_id):
			fresh.append(item_id)
	var out: Array[StringName] = []
	var first: Array[StringName] = _pick(fresh, 1, rng)
	if not first.is_empty():
		out.append(first[0])
		pool.erase(first[0])
	out.append_array(_pick(pool, LOTTERY_COUNT - out.size(), rng))
	return out


## `mTG_hukubukuro_open_proc` (Sale Day bag): three goods from the rare lists, one slot
## may be a pinwheel instead (50%).
static func open_grab_bag(rng: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = []
	var pin_slot: int = rng.randi_range(0, 2)
	var pools: Array = [
		_category_pool(ItemData.Category.CLOTH), _category_pool(ItemData.Category.FLOOR),
		_category_pool(ItemData.Category.WALL), furniture_pool(),
	]
	for i: int in 3:
		if i == pin_slot and rng.randf() <= 0.5:
			out.append(PINWHEELS[rng.randi_range(0, PINWHEELS.size() - 1)])
			continue
		var pool: Array[StringName] = pools[mini(int(rng.randf() * 4.0), 3)]
		var rare: Array[StringName] = []
		for item_id: StringName in pool:
			var data: ItemData = ItemCatalog.get_item(item_id)
			if data != null and data.shop_rare:
				rare.append(item_id)
		var picked: Array[StringName] = _pick(rare if not rare.is_empty() else pool, 1, rng)
		out.append(picked[0] if not picked.is_empty() else PINWHEELS[0])
	return out


## `ITM_UMBRELLA00` + `RANDOM(UMBRELLA_NUM)`: every umbrella tool in the catalog.
static func umbrella_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for item: ItemData in ItemCatalog.all_items():
		if item is ToolData and (item as ToolData).kind == ToolData.Kind.UMBRELLA:
			out.append(item.id)
	out.sort()
	return out


## Furniture Nook can stock: authored FTR with a price that isn't on the rare list.
static func furniture_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for item: ItemData in ItemCatalog.all_items():
		if item is FurnitureData and not item.shop_rare and ShopBook.buy_price(item) > 0:
			out.append(item.id)
	out.sort()
	return out


static func _rare_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for item: ItemData in ItemCatalog.all_items():
		if item is FurnitureData and item.shop_rare and ShopBook.buy_price(item) > 0:
			out.append(item.id)
	out.sort()
	return out


static func _category_pool(category: ItemData.Category) -> Array[StringName]:
	var out: Array[StringName] = []
	for item: ItemData in ItemCatalog.all_items():
		if item is FurnitureData or item.category != category or item.shop_rare:
			continue
		if ShopBook.buy_price(item) > 0:
			out.append(item.id)
	out.sort()
	return out


static func _pick(pool: Array[StringName], count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var live: Array[StringName] = []
	for item_id: StringName in pool:
		if ItemCatalog.get_item(item_id) != null:
			live.append(item_id)
	var out: Array[StringName] = []
	if live.is_empty() or count <= 0:
		return out
	var bag: Array[StringName] = live.duplicate()
	for _i: int in count:
		if bag.is_empty():
			bag = live.duplicate()
		var idx: int = rng.randi_range(0, bag.size() - 1)
		out.append(bag[idx])
		bag.remove_at(idx)
	return out
