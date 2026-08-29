class_name Inventory
extends RefCounted

## Player pockets. 15 slots in a 5×3 grid (`mIV_ITEM_COLUMNS` / `mIV_ITEM_ROWS`).
## Stacking is data-driven via `ItemData.max_stack` (tools stay at 1).

const POCKET_SLOTS := 15
const COLUMNS := 5
const ROWS := 3
const WALLET_MAX := 99999

signal changed
signal selection_changed(index: int)
signal wallet_changed(amount: int)
signal equipment_changed(item_id: StringName)

var wallet: int = 0
var equipment_id: StringName = &""
var selected_index: int = 0
## Hand hold (`m_hand_ovl` hold_idx). -1 = empty hand.
var hand_index: int = -1

var _slots: Array[InventorySlot] = []


func _init() -> void:
	_slots.clear()
	for i: int in POCKET_SLOTS:
		_slots.append(InventorySlot.new(i))


func clear() -> void:
	for slot: InventorySlot in _slots:
		slot.clear()
	wallet = 0
	equipment_id = &""
	selected_index = 0
	hand_index = -1
	changed.emit()
	selection_changed.emit(selected_index)
	wallet_changed.emit(wallet)
	equipment_changed.emit(equipment_id)


func slot_at(index: int) -> InventorySlot:
	if index < 0 or index >= POCKET_SLOTS:
		return null
	return _slots[index]


func selected_slot() -> InventorySlot:
	return slot_at(selected_index)


func select(index: int) -> void:
	if index < 0 or index >= POCKET_SLOTS:
		return
	if selected_index == index:
		return
	selected_index = index
	selection_changed.emit(selected_index)


func move_cursor(dx: int, dy: int) -> void:
	var col: int = selected_index % COLUMNS
	var row: int = selected_index / COLUMNS
	col = clampi(col + dx, 0, COLUMNS - 1)
	row = clampi(row + dy, 0, ROWS - 1)
	select(row * COLUMNS + col)


## Returns leftover count that did not fit.
func add(item: ItemData, count: int = 1, condition: InventoryItem.Condition = InventoryItem.Condition.NORMAL) -> int:
	if item == null or item.id == &"" or count <= 0:
		return count
	var remaining: int = count
	var max_stack: int = maxi(1, item.max_stack)

	if max_stack > 1:
		for slot: InventorySlot in _slots:
			if slot.is_empty():
				continue
			var stack: InventoryItem = slot.item
			if stack.item_id != item.id or stack.condition != condition:
				continue
			var room: int = max_stack - stack.count
			if room <= 0:
				continue
			var put: int = mini(room, remaining)
			stack.count += put
			remaining -= put
			if remaining == 0:
				changed.emit()
				return 0

	for slot: InventorySlot in _slots:
		if not slot.is_empty():
			continue
		var put: int = mini(max_stack, remaining)
		slot.set_stack(item.id, put, condition)
		remaining -= put
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
		var slot: InventorySlot = _slots[i]
		if slot.is_empty() or slot.item.item_id != item_id:
			continue
		var take: int = mini(slot.item.count, remaining)
		slot.item.count -= take
		remaining -= take
		if slot.item.count <= 0:
			slot.clear()
			if hand_index == i:
				hand_index = -1
		if remaining == 0:
			changed.emit()
			return 0
	changed.emit()
	return remaining


func remove_from_slot(index: int, count: int = 1) -> InventoryItem:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty() or count <= 0:
		return InventoryItem.new()
	var take: int = mini(slot.item.count, count)
	var removed := InventoryItem.new(slot.item.item_id, take, slot.item.condition)
	slot.item.count -= take
	if slot.item.count <= 0:
		slot.clear()
		if hand_index == index:
			hand_index = -1
	changed.emit()
	return removed


func count_of(item_id: StringName) -> int:
	var total: int = 0
	for slot: InventorySlot in _slots:
		if not slot.is_empty() and slot.item.item_id == item_id:
			total += slot.item.count
	return total


func has_space_for(item: ItemData, count: int = 1) -> bool:
	if item == null or count <= 0:
		return false
	return add_would_fit(item, count)


func add_would_fit(item: ItemData, count: int) -> bool:
	if item == null or count <= 0:
		return false
	var remaining: int = count
	var max_stack: int = maxi(1, item.max_stack)
	for slot: InventorySlot in _slots:
		if slot.is_empty():
			remaining -= max_stack
		elif slot.item.item_id == item.id and slot.item.condition == InventoryItem.Condition.NORMAL:
			remaining -= maxi(0, max_stack - slot.item.count)
		if remaining <= 0:
			return true
	return false


func has_space(count: int = 1) -> bool:
	## Backward-compatible: enough empty slots for `count` non-stacking inserts.
	return empty_slot_count() >= count


func empty_slot_count() -> int:
	var n: int = 0
	for slot: InventorySlot in _slots:
		if slot.is_empty():
			n += 1
	return n


func is_empty() -> bool:
	return count_of_occupied() == 0


func count_of_occupied() -> int:
	var n: int = 0
	for slot: InventorySlot in _slots:
		if not slot.is_empty():
			n += 1
	return n


func set_wallet(amount: int) -> void:
	var next: int = clampi(amount, 0, WALLET_MAX)
	if wallet == next:
		return
	wallet = next
	wallet_changed.emit(wallet)
	changed.emit()


func add_bells(amount: int) -> int:
	if amount <= 0:
		return 0
	var before: int = wallet
	set_wallet(wallet + amount)
	return wallet - before


func spend_bells(amount: int) -> bool:
	if amount <= 0:
		return true
	if wallet < amount:
		return false
	set_wallet(wallet - amount)
	return true


func equip_slot(index: int) -> bool:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return false
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null or not data.equippable:
		return false
	if slot.item.condition != InventoryItem.Condition.NORMAL:
		return false
	equipment_id = slot.item.item_id
	equipment_changed.emit(equipment_id)
	changed.emit()
	return true


func unequip() -> void:
	if equipment_id == &"":
		return
	equipment_id = &""
	equipment_changed.emit(equipment_id)
	changed.emit()


## Returns use verb result text, or "" if nothing happened.
func use_slot(index: int) -> String:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return ""
	if slot.item.condition != InventoryItem.Condition.NORMAL:
		return ""
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null:
		return ""
	if data.equippable:
		if equip_slot(index):
			return "Equipped %s" % data.display_name
		return ""
	if not data.usable:
		return ""
	var removed: InventoryItem = remove_from_slot(index, 1)
	if removed.is_empty():
		return ""
	var verb: String = data.use_verb if data.use_verb != "" else "Used"
	return "%s %s" % [verb, data.display_name]


## Pull one (or `count`) from a slot for dropping into the world.
func drop_slot(index: int, count: int = 1) -> InventoryItem:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return InventoryItem.new()
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data != null and not data.droppable:
		return InventoryItem.new()
	if slot.item.condition == InventoryItem.Condition.QUEST:
		return InventoryItem.new()
	return remove_from_slot(index, count)


func pick_hand(index: int) -> bool:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return false
	hand_index = index
	select(index)
	changed.emit()
	return true


func clear_hand() -> void:
	if hand_index < 0:
		return
	hand_index = -1
	changed.emit()


## Place/swap hand contents onto `target_index` (`m_hand_ovl` put).
func place_hand(target_index: int) -> bool:
	if hand_index < 0 or hand_index >= POCKET_SLOTS:
		return false
	if target_index < 0 or target_index >= POCKET_SLOTS:
		return false
	if hand_index == target_index:
		clear_hand()
		return true
	var from: InventorySlot = _slots[hand_index]
	var to: InventorySlot = _slots[target_index]
	if from.is_empty():
		clear_hand()
		return false
	if to.is_empty():
		to.item = from.item
		from.clear()
	else:
		var tmp: InventoryItem = to.item
		to.item = from.item
		from.item = tmp
	hand_index = -1
	select(target_index)
	changed.emit()
	return true


func tags_for_slot(index: int) -> PackedStringArray:
	## Field-default style verbs from `m_tag_ovl` (simplified).
	var tags: PackedStringArray = []
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return tags
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null:
		return tags
	if slot.item.condition == InventoryItem.Condition.PRESENT:
		tags.append("Open")
		return tags
	if slot.item.condition == InventoryItem.Condition.QUEST:
		return tags
	if data.equippable:
		tags.append("Equip")
	if data.plant_id != &"":
		tags.append("Plant")
	elif data.usable:
		tags.append(data.use_verb if data.use_verb != "" else "Use")
	if data.droppable:
		tags.append("Drop")
	tags.append("Move")
	return tags


func to_save() -> Dictionary:
	var rows: Array = []
	for slot: InventorySlot in _slots:
		rows.append(slot.to_save())
	return {
		"slots": rows,
		"wallet": wallet,
		"equipment": String(equipment_id),
		"selected": selected_index,
	}


func from_save(data: Variant) -> void:
	## Accepts new dict shape or legacy Array-of-slot-dicts.
	clear()
	var rows: Array = []
	if typeof(data) == TYPE_ARRAY:
		rows = data
	elif typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		var slots_v: Variant = d.get("slots", [])
		if typeof(slots_v) == TYPE_ARRAY:
			rows = slots_v
		set_wallet(int(d.get("wallet", 0)))
		equipment_id = StringName(str(d.get("equipment", "")))
		selected_index = clampi(int(d.get("selected", 0)), 0, POCKET_SLOTS - 1)
	var i: int = 0
	for row: Variant in rows:
		if i >= POCKET_SLOTS:
			break
		if typeof(row) != TYPE_DICTIONARY:
			i += 1
			continue
		var loaded: InventoryItem = InventoryItem.from_save(row as Dictionary)
		if loaded.is_empty():
			_slots[i].clear()
		else:
			var data_item: ItemData = ItemCatalog.get_item(loaded.item_id)
			var max_stack: int = maxi(1, data_item.max_stack) if data_item != null else 1
			loaded.count = clampi(loaded.count, 1, max_stack)
			_slots[i].item = loaded
		i += 1
	changed.emit()
	selection_changed.emit(selected_index)
	wallet_changed.emit(wallet)
	equipment_changed.emit(equipment_id)
