class_name Inventory
extends RefCounted

## Player pockets. 15 slots, one item each (`mPr_POCKETS_SLOT_COUNT` / `pockets[]` in m_private.h).
## GameCube pockets do not stack.

const POCKET_SLOTS := 15

signal changed

var _slots: Array[Dictionary] = []


func _init() -> void:
	clear()


func clear() -> void:
	_slots.clear()
	_slots.resize(POCKET_SLOTS)
	for i: int in POCKET_SLOTS:
		_slots[i] = { "id": &"", "count": 0 }
	changed.emit()


func add(item: ItemData, count: int = 1) -> int:
	if item == null or item.id == &"" or count <= 0:
		return count
	var remaining: int = count
	for slot: Dictionary in _slots:
		if slot["id"] != &"":
			continue
		slot["id"] = item.id
		slot["count"] = 1
		remaining -= 1
		if remaining == 0:
			changed.emit()
			return 0
	changed.emit()
	return remaining


func remove(item_id: StringName, count: int = 1) -> int:
	if item_id == &"" or count <= 0:
		return count
	var remaining: int = count
	for i: int in range(POCKET_SLOTS - 1, -1, -1):
		var slot: Dictionary = _slots[i]
		if slot["id"] != item_id:
			continue
		slot["id"] = &""
		slot["count"] = 0
		remaining -= 1
		if remaining == 0:
			changed.emit()
			return 0
	changed.emit()
	return remaining


func count_of(item_id: StringName) -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		if slot["id"] == item_id:
			total += 1
	return total


func is_empty() -> bool:
	return count_of_occupied() == 0


func count_of_occupied() -> int:
	var n: int = 0
	for slot: Dictionary in _slots:
		if slot["id"] != &"":
			n += 1
	return n


func to_save() -> Array:
	var out: Array = []
	for slot: Dictionary in _slots:
		out.append({ "id": String(slot["id"]), "count": int(slot["count"]) })
	return out


func from_save(rows: Array) -> void:
	clear()
	var i: int = 0
	for row: Variant in rows:
		if i >= POCKET_SLOTS:
			break
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = row
		var id := StringName(str(data.get("id", "")))
		_slots[i] = { "id": id, "count": 1 if id != &"" else 0 }
		i += 1
	changed.emit()
