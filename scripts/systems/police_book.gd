class_name PoliceBook
extends RefCounted

## Police-box lost and found (`PoliceBox_c` / `m_police_box.c`). Owned by `Game`.

const STORAGE_COUNT := 20
const MAX_GROW_SIZE := 5

var _items: Array[StringName] = []


func _init() -> void:
	clear()


func clear() -> void:
	_items.clear()
	_items.resize(STORAGE_COUNT)
	for i: int in STORAGE_COUNT:
		_items[i] = &""


func ensure_init() -> void:
	## `mPB_police_box_init`: one furniture + two shirts when still empty.
	if keep_item_sum() > 0:
		return
	var furniture: Array[StringName] = [&"wood_chair", &"wood_table", &"wood_dresser", &"wood_tv"]
	var shirts: Array[StringName] = [&"shirt_000", &"shirt_001", &"shirt_002", &"shirt_003"]
	_items[0] = furniture[randi() % furniture.size()]
	_items[1] = shirts[randi() % shirts.size()]
	_items[2] = shirts[randi() % shirts.size()]


func keep_items() -> Array[StringName]:
	ensure_init()
	var out: Array[StringName] = []
	for id: StringName in _items:
		out.append(id)
	return out


func keep_item_sum() -> int:
	var sum := 0
	for id: StringName in _items:
		if id != &"":
			sum += 1
	return sum


func item_at(slot: int) -> StringName:
	ensure_init()
	if slot < 0 or slot >= _items.size():
		return &""
	return _items[slot]


## `mPB_keep_item` — ITEM1 / FTR only; full storage shifts oldest out.
func keep_item(item_id: StringName) -> bool:
	if item_id == &"" or not _is_keepable(item_id):
		return false
	ensure_init()
	var sum: int = keep_item_sum()
	if sum >= STORAGE_COUNT:
		for i: int in range(1, STORAGE_COUNT):
			_items[i - 1] = _items[i]
		sum = STORAGE_COUNT - 1
	_items[sum] = item_id
	return true


func claim(slot: int, inventory: Inventory) -> String:
	ensure_init()
	if inventory == null:
		return "No pockets."
	if slot < 0 or slot >= _items.size() or _items[slot] == &"":
		return "Nothing there."
	var item_id: StringName = _items[slot]
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return "Nothing there."
	if not inventory.has_space_for(data, 1):
		return "Your pockets are full."
	inventory.add(data, 1)
	_items[slot] = &""
	return "Received %s." % data.display_name


## `mPB_force_set_keep_item` when sum ≤ 5 and a coin flip passes.
func force_set_keep_item() -> void:
	ensure_init()
	if keep_item_sum() > MAX_GROW_SIZE:
		return
	if randi() & 1 != 0:
		return
	keep_item(_random_grow_item())


func to_save() -> Dictionary:
	ensure_init()
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


static func _is_keepable(item_id: StringName) -> bool:
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return false
	if data is FurnitureData:
		return true
	## ITEM1-class: tools, cloth, fruit, etc. Skip raw terrain / empty.
	match data.category:
		ItemData.Category.TOOL, ItemData.Category.CLOTH, ItemData.Category.FRUIT:
			return true
		ItemData.Category.WALL, ItemData.Category.FLOOR:
			return true
		_:
			return data is ToolData or String(item_id).begins_with("shirt_")


func _random_grow_item() -> StringName:
	## `mPB_get_force_set_item` category roll (goods / tool / flower / umbrella).
	var roll: int = randi() % 100
	if roll <= 85:
		var goods: Array[StringName] = [
			&"wood_chair", &"wood_table", &"shirt_000", &"shirt_001", &"wall_blue", &"floor_tile"
		]
		return goods[randi() % goods.size()]
	if roll <= 90:
		var tools: Array[StringName] = [&"net", &"axe", &"shovel", &"fishing_rod", &"apple_sapling"]
		return tools[randi() % tools.size()]
	if roll <= 95:
		return &"flower"
	return &"shirt_002"
