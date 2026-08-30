class_name ShopBook
extends RefCounted

## Town shops. Owned by `Game`, not an autoload. Nook buy/sell; Able Sisters buy-only.
## Daily lineup at 06:00 (`Clock.field_renewed`). Sell-to-shop is catalog / 4 (`SELL_BUY_RATIO`).

const NOOK_ID := &"shop0"
const ABLE_ID := &"needlework"
const SELL_RATIO := 4
const SHOP_IDS: Array[StringName] = [NOOK_ID, ABLE_ID]

var _shops: Dictionary = {}


func clear() -> void:
	_shops.clear()


func shop(shop_id: StringName) -> Dictionary:
	if shop_id == &"":
		return {}
	if not _shops.has(shop_id):
		_shops[shop_id] = _empty(shop_id)
	ensure_today(shop_id)
	return _shops[shop_id] as Dictionary


func goods(shop_id: StringName) -> Array[StringName]:
	var row: Dictionary = shop(shop_id)
	var raw: Variant = row.get("goods", [])
	var out: Array[StringName] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw as Array:
		out.append(StringName(str(entry)))
	return out


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


static func buy_price(item: ItemData) -> int:
	if item == null:
		return 0
	if item.buy_price > 0:
		return item.buy_price
	return maxi(item.sell_price, 0)


static func sell_price(item: ItemData) -> int:
	if item == null:
		return 0
	match item.category:
		ItemData.Category.FRUIT, ItemData.Category.FISH, ItemData.Category.BUG:
			return maxi(item.sell_price, 0)
		_:
			return buy_price(item) / SELL_RATIO


func buy(shop_id: StringName, item_id: StringName, inv: Inventory) -> String:
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or inv == null:
		return "That's not for sale."
	var listed: Array[StringName] = goods(shop_id)
	var slot: int = listed.find(item_id)
	if slot < 0:
		return "That's sold out."
	var price: int = buy_price(data)
	if price <= 0:
		return "That's not for sale."
	if not inv.has_space_for(data, 1):
		return "Pockets are full."
	if not inv.spend_bells(price):
		return "Not enough Bells."
	inv.add(data, 1)
	listed.remove_at(slot)
	_set_goods(shop_id, listed)
	_add_sales(shop_id, price)
	return "Bought %s for %d Bells." % [data.display_name, price]


func sell(shop_id: StringName, item_id: StringName, inv: Inventory, count: int = 1) -> String:
	if not allows_sell(shop_id):
		return "They don't buy items here."
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or inv == null or count <= 0:
		return "Can't sell that."
	var have: int = inv.count_of(item_id)
	if have <= 0:
		return "You don't have that."
	var take: int = mini(count, have)
	var unit: int = sell_price(data)
	if unit <= 0:
		return "They won't buy that."
	if inv.remove(item_id, take) > 0:
		return "Can't sell that."
	var paid: int = unit * take
	inv.add_bells(paid)
	return "Sold %s for %d Bells." % [data.display_name, paid]


func sales_sum(shop_id: StringName) -> int:
	if not _shops.has(shop_id):
		return 0
	return int((_shops[shop_id] as Dictionary).get("sales", 0))


func ensure_today(shop_id: StringName) -> void:
	if shop_id == &"":
		return
	if not _shops.has(shop_id):
		_shops[shop_id] = _empty(shop_id)
	var row: Dictionary = _shops[shop_id]
	## Sold-out shelves stay empty until 06:00. Do not restock just because `goods` is empty.
	if int(row.get("renew", -1)) == Clock.renew_index():
		return
	restock(shop_id)


func restock(shop_id: StringName) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _day_seed(shop_id)
	var picks: Array[StringName] = _roll(shop_id, rng)
	_shops[shop_id] = {
		"id": String(shop_id),
		"goods": _as_strings(picks),
		"sales": int((_shops.get(shop_id, {}) as Dictionary).get("sales", 0)),
		"renew": Clock.renew_index(),
	}


func renew(_days: int = 1) -> void:
	for shop_id: StringName in SHOP_IDS:
		restock(shop_id)


func to_save() -> Dictionary:
	var out := {}
	for key: Variant in _shops.keys():
		out[str(key)] = (_shops[key] as Dictionary).duplicate(true)
	return out


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for key: Variant in (data as Dictionary).keys():
		var row: Variant = (data as Dictionary)[key]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_shops[StringName(str(key))] = (row as Dictionary).duplicate(true)
	for shop_id: StringName in SHOP_IDS:
		ensure_today(shop_id)


func _empty(shop_id: StringName) -> Dictionary:
	return {"id": String(shop_id), "goods": [], "sales": 0, "renew": -1}


func _set_goods(shop_id: StringName, listed: Array[StringName]) -> void:
	if not _shops.has(shop_id):
		_shops[shop_id] = _empty(shop_id)
	var row: Dictionary = _shops[shop_id]
	row["goods"] = _as_strings(listed)
	_shops[shop_id] = row


func _add_sales(shop_id: StringName, amount: int) -> void:
	if not _shops.has(shop_id):
		_shops[shop_id] = _empty(shop_id)
	var row: Dictionary = _shops[shop_id]
	row["sales"] = int(row.get("sales", 0)) + amount
	_shops[shop_id] = row


func _as_strings(listed: Array[StringName]) -> Array:
	var out: Array = []
	for item_id: StringName in listed:
		out.append(String(item_id))
	return out


func _day_seed(shop_id: StringName) -> int:
	var seed_value: int = Game.world_seed if Game != null else 1
	return hash(
		[
			seed_value,
			Clock.year,
			Clock.month,
			Clock.day,
			String(shop_id),
		]
	)


func _roll(shop_id: StringName, rng: RandomNumberGenerator) -> Array[StringName]:
	if shop_id == ABLE_ID:
		return _pick(_cloth_pool(), 4, rng)
	var out: Array[StringName] = []
	out.append_array(_pick(_tool_pool(), 2, rng))
	out.append_array(_pick(_furniture_pool(), 1, rng))
	out.append_array(_pick(_wall_pool(), 1, rng))
	out.append_array(_pick(_floor_pool(), 1, rng))
	out.append_array(_pick(_sapling_pool(), 1, rng))
	out.append_array(_pick(_plant_pool(), 2, rng))
	return out


func _pick(pool: Array[StringName], count: int, rng: RandomNumberGenerator) -> Array[StringName]:
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


func _tool_pool() -> Array[StringName]:
	return [&"shovel", &"axe", &"net", &"fishing_rod", &"watering_can"]


func _furniture_pool() -> Array[StringName]:
	return [&"wood_chair", &"wood_table", &"wood_dresser", &"wood_tv"]


func _wall_pool() -> Array[StringName]:
	return [&"wall_blue"]


func _floor_pool() -> Array[StringName]:
	return [&"floor_tile"]


func _sapling_pool() -> Array[StringName]:
	return [&"apple_sapling"]


func _plant_pool() -> Array[StringName]:
	return [&"flower"]


func _cloth_pool() -> Array[StringName]:
	return [&"shirt_000", &"shirt_001", &"shirt_002", &"shirt_003"]
