class_name ReddStock
extends RefCounted

## Crazy Redd's three pieces for one visit (`init_sp_broker`) and who bought what
## (`mEv_broker_c`). Kept in the event save area `broker_sale`.
##
## Each piece is drawn from the event furniture list with 50–70% odds (`goods_power`
## shifts it), otherwise from Nook's A/B/C lists at the rarity `goods_power` favours — with
## no goods power (the player's Happy Room standing), that is the common list. Prices are
## the catalog price × 4 (`aEBR2_PRICE_MULT`). Two players may each buy one piece; the third
## sale closes the tent (`used == mEv_BROKER_ITEM_NUM`).

const ITEM_NUM := 3
const PRICE_MULT := 4
## `mSP_LISTTYPE_COMMON / UNCOMMON / RARE` → Nook's groups.
const LIST_BIRTH: Dictionary = {&"common": "grp_a", &"uncommon": "grp_b", &"rare": "grp_c"}


## Rolls a fresh visit into `area` (items, nobody served yet).
static func roll(area: Dictionary, rng: RandomNumberGenerator, goods_power: int = 0) -> void:
	area.clear()
	var common: int = 50 + goods_power
	var rare: int
	var uncommon: int
	var threshold: int
	if goods_power < 0:
		uncommon = goods_power + 35
		rare = 5
		threshold = 100 - (uncommon + 5)
	else:
		rare = goods_power + 5
		uncommon = 35
		threshold = 100 - (rare + 35)
	var list: StringName = &"common"
	if rare >= uncommon and rare >= threshold:
		list = &"rare"
	elif uncommon >= rare and uncommon >= threshold:
		list = &"uncommon"
	var event_chance: float = float(clampi(common, 50, 70))
	var items: Array = []
	for i: int in ITEM_NUM:
		var birth: String = "event" if rng.randf() * 100.0 <= event_chance else str(LIST_BIRTH[list])
		items.append(String(FtrCatalog.pick(birth, rng, items)))
	area["items"] = items
	area["used"] = 0
	area["sold"] = []


static func items(area: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in area.get("items", []):
		out.append(StringName(str(id)))
	return out


static func left(area: Dictionary) -> int:
	var n: int = 0
	for id: StringName in items(area):
		if id != &"":
			n += 1
	return n


static func price(item_id: StringName) -> int:
	var data: ItemData = ItemCatalog.get_item(item_id)
	return (data.buy_price if data != null else 0) * PRICE_MULT


## What this player bought this visit, or "".
static func bought(area: Dictionary) -> StringName:
	return StringName(str(area.get("bought", "")))


## `aEBR2_sell_after`: the piece leaves the floor and the sale is recorded.
static func sell(area: Dictionary, item_id: StringName) -> void:
	var list: Array = area.get("items", [])
	var idx: int = list.find(String(item_id))
	if idx >= 0:
		list[idx] = ""
	area["items"] = list
	var used: int = int(area.get("used", 0))
	if used < ITEM_NUM - 1:
		var sold: Array = area.get("sold", [])
		sold.append(String(item_id))
		area["sold"] = sold
		area["used"] = used + 1
		area["bought"] = String(item_id)
	else:
		area["used"] = ITEM_NUM
