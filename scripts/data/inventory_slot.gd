class_name InventorySlot
extends RefCounted

## One of 15 pocket cells (`mPr` pockets[i]). Empty when `item` is null.

var index: int = 0
var item: InventoryItem


func _init(p_index: int = 0, p_item: InventoryItem = null) -> void:
	index = p_index
	item = p_item


func is_empty() -> bool:
	return item == null or item.is_empty()


func clear() -> void:
	item = null


func set_stack(item_id: StringName, count: int, condition: InventoryItem.Condition = InventoryItem.Condition.NORMAL) -> void:
	if item_id == &"" or count <= 0:
		clear()
		return
	item = InventoryItem.new(item_id, count, condition)


func to_save() -> Dictionary:
	if is_empty():
		return { "id": "", "count": 0, "condition": 0 }
	return item.to_save()
