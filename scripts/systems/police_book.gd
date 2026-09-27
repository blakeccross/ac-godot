class_name PoliceBook
extends RefCounted

## Police-box lost and found (`PoliceBox_c` / `m_police_box.c`). Owned by `Game`.
##
## Twenty `keep_items` slots, filled front-to-back. The room draws slot N on the
## `RSV_POLICE_ITEM_N` unit (`bg_police_item`), so a claimed slot stays a gap until
## the player leaves and `copy_item_buf` packs the list (`aPOL2_player_getout_check`).

const STORAGE_COUNT := 20
const MAX_GROW_SIZE := 5

## `mPB_get_force_set_item` category thresholds (inclusive upper bounds of a 0–99 roll):
## goods 0–85, tools 86–90, flower bags 91–95, umbrella 96–99.
const CATEGORY_GOODS := 0
const CATEGORY_ITEM := 1
const CATEGORY_FLOWER := 2
const CATEGORY_UMBRELLA := 3
const CATEGORY_PROB: Array[int] = [85, 90, 95, 100]
## `mPB_get_force_set_item_goods`: furniture 0–35, stationery –58, clothing –88,
## carpet –94, wallpaper –100 (`mSP_KIND_*`, common list).
const GOODS_PROB: Array[int] = [35, 58, 88, 94, 100]
## `mPB_get_force_set_item_item`: `(int)(fqrand() * 6)` over this table.
const GROW_TOOLS: Array[StringName] = [
	&"net", &"axe", &"shovel", &"fishing_rod", &"sapling", &"cedar_sapling"
]
## `ITM_WHITE_PANSY_BAG + (int)(fqrand() * 8)`: the first eight bags, never the ninth.
const GROW_FLOWER_BAG_COUNT := 8

## `aPOL2_check_answer` outcomes.
enum Claim { OK, POCKETS_FULL, EMPTY }

var _items: Array[StringName] = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()
	clear()


func clear() -> void:
	_items.clear()
	_items.resize(STORAGE_COUNT)
	for i: int in STORAGE_COUNT:
		_items[i] = &""


## `mPB_police_box_init`, run once when a town is made (`m_start_data_init`): one
## furniture and two shirts, the rest empty. An emptied lost and found stays empty
## until the 06:00 renew tops it up (`force_set_keep_item`).
func init_town() -> void:
	clear()
	var furniture: Array[StringName] = _random_from(ShopGoods.furniture_pool(), 1)
	var shirts: Array[StringName] = _random_from(
		ShopGoods.category_pool(ItemData.Category.CLOTH), 2
	)
	var slot := 0
	for id: StringName in furniture + shirts:
		if slot < STORAGE_COUNT:
			_items[slot] = id
			slot += 1


func keep_items() -> Array[StringName]:
	return _items.duplicate()


func keep_item_sum() -> int:
	var sum := 0
	for id: StringName in _items:
		if id != &"":
			sum += 1
	return sum


func item_at(slot: int) -> StringName:
	if slot < 0 or slot >= _items.size():
		return &""
	return _items[slot]


## `mPB_keep_item` — ITEM1 / FTR only. Written at index `keep_item_sum()`, so a gap
## left by a claim is overwritten from the back. Full storage drops slot 0 and
## shifts the rest down one.
func keep_item(item_id: StringName) -> bool:
	if not is_keepable(item_id):
		return false
	var sum: int = keep_item_sum()
	if sum >= STORAGE_COUNT:
		for i: int in range(1, STORAGE_COUNT):
			_items[i - 1] = _items[i]
		sum = STORAGE_COUNT - 1
	_items[sum] = item_id
	return true


## `mPB_copy_itemBuf` over its own storage: pack the occupied slots to the front.
## Booker calls it as the player steps onto `EXIT_DOOR1`.
func copy_item_buf() -> void:
	var packed: Array[StringName] = []
	for id: StringName in _items:
		if id != &"":
			packed.append(id)
	clear()
	for i: int in packed.size():
		_items[i] = packed[i]


## `mPB_keep_all_item_in_block`: move every keepable item lying in an acre into the
## lost and found. Past twenty new items, each extra one lands on a random slot of the
## new batch; old items are then dropped from the front to fit the batch.
## `acre_items` is the acre's items in unit order; returns the ones that were taken.
func keep_all_items(acre_items: Array[StringName]) -> Array[StringName]:
	var taken: Array[StringName] = []
	var batch: Array[StringName] = []
	for id: StringName in acre_items:
		if not is_keepable(id):
			continue
		taken.append(id)
		if batch.size() < STORAGE_COUNT:
			batch.append(id)
		else:
			batch[rng.randi_range(0, STORAGE_COUNT - 1)] = id
	if batch.is_empty():
		return taken
	## Indexes by the occupied count, as the original does — like `keep_item`, this
	## assumes the list is packed (it is outside the police box).
	var sum: int = keep_item_sum()
	var start: int = sum
	var drop: int = sum + batch.size() - STORAGE_COUNT
	if drop > 0:
		start = sum - drop
		for i: int in maxi(start, 0):
			_items[i] = _items[i + drop]
	for i: int in batch.size():
		_items[start + i] = batch[i]
	return taken


## `aPOL2_check_answer` CHOICE0: tickets stack onto a ticket slot
## (`mPlib_Get_space_putin_item_forTICKET`), everything else needs a free pocket
## (`mPlib_Get_space_putin_item`). Pockets full → msg 0x0781 and the item stays.
func claim_result(slot: int, inventory: Inventory) -> Claim:
	var item_id: StringName = item_at(slot)
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or inventory == null:
		return Claim.EMPTY
	var count: int = ShopGoods.pack_count(item_id)
	if is_ticket(item_id):
		if not inventory.has_space_for(data, count):
			return Claim.POCKETS_FULL
		inventory.add(data, count)
	else:
		if inventory.empty_slot_count() <= 0:
			return Claim.POCKETS_FULL
		inventory.add_to_empty_slot(data, count)
	_items[slot] = &""
	return Claim.OK


## `mPB_force_set_keep_item` (06:00 renew): with five or fewer items kept, a
## `qrand() >= 0` coin flip adds one random item.
func force_set_keep_item() -> bool:
	if keep_item_sum() > MAX_GROW_SIZE:
		return false
	if rng.randi() & 1 != 0:
		return false
	var item_id: StringName = random_grow_item()
	if item_id == &"":
		return false
	return keep_item(item_id)


## `mPB_get_force_set_item`: roll the category, then the item inside it.
func random_grow_item() -> StringName:
	match pick_bucket(CATEGORY_PROB, rng.randi_range(0, 99)):
		CATEGORY_GOODS:
			return _random_goods()
		CATEGORY_ITEM:
			return GROW_TOOLS[rng.randi_range(0, GROW_TOOLS.size() - 1)]
		CATEGORY_FLOWER:
			var bags: int = mini(GROW_FLOWER_BAG_COUNT, ShopGoods.FLOWER_BAGS.size())
			return ShopGoods.FLOWER_BAGS[rng.randi_range(0, bags - 1)]
		_:
			var umbrellas: Array[StringName] = _random_from(ShopGoods.umbrella_pool(), 1)
			return umbrellas[0] if not umbrellas.is_empty() else &""


## First table index whose threshold is ≥ `roll` (`roll <= prob_table[i]`).
static func pick_bucket(table: Array[int], roll: int) -> int:
	for i: int in table.size():
		if roll <= table[i]:
			return i
	return table.size() - 1


## `ITEM_IS_ITEM1(n) || ITEM_IS_FTR(n)`: anything that can sit in pockets or a room.
## Flowers, trees and structures are FG objects, never `ItemData`.
static func is_keepable(item_id: StringName) -> bool:
	return item_id != &"" and ItemCatalog.get_item(item_id) != null


static func is_ticket(item_id: StringName) -> bool:
	return String(item_id).begins_with("ticket_")


func to_save() -> Dictionary:
	var raw: Array = []
	for id: StringName in _items:
		raw.append(String(id))
	return {"keep_items": raw}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data as Dictionary
	var raw: Variant = row.get("keep_items", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	var i := 0
	for entry: Variant in raw as Array:
		if i >= STORAGE_COUNT:
			break
		_items[i] = StringName(str(entry))
		i += 1


func _random_goods() -> StringName:
	var pool: Array[StringName]
	match pick_bucket(GOODS_PROB, rng.randi_range(0, 99)):
		0:
			pool = ShopGoods.furniture_pool()
		1:
			pool = [ShopGoods.PAPER]
		2:
			pool = ShopGoods.category_pool(ItemData.Category.CLOTH)
		3:
			pool = ShopGoods.category_pool(ItemData.Category.FLOOR)
		_:
			pool = ShopGoods.category_pool(ItemData.Category.WALL)
	var picked: Array[StringName] = _random_from(pool, 1)
	return picked[0] if not picked.is_empty() else &""


func _random_from(pool: Array[StringName], count: int) -> Array[StringName]:
	var live: Array[StringName] = []
	for id: StringName in pool:
		if ItemCatalog.get_item(id) != null:
			live.append(id)
	## `mSP_SelectRandomItem_New` never picks the same item twice.
	var out: Array[StringName] = []
	for _i: int in mini(count, live.size()):
		var pick: int = rng.randi_range(0, live.size() - 1)
		out.append(live[pick])
		live.remove_at(pick)
	return out
