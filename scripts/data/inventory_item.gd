class_name InventoryItem
extends RefCounted

## One stack inside a pocket slot (`mActor_name_t` + count + condition).

enum Condition { NORMAL, PRESENT, QUEST }

var item_id: StringName = &""
var count: int = 0
var condition: Condition = Condition.NORMAL


func _init(
	p_id: StringName = &"",
	p_count: int = 0,
	p_condition: Condition = Condition.NORMAL
) -> void:
	item_id = p_id
	count = p_count
	condition = p_condition


func is_empty() -> bool:
	return item_id == &"" or count <= 0


func duplicate_item() -> InventoryItem:
	return InventoryItem.new(item_id, count, condition)


func to_save() -> Dictionary:
	return {
		"id": String(item_id),
		"count": count,
		"condition": int(condition),
	}


static func from_save(data: Dictionary) -> InventoryItem:
	var id := StringName(str(data.get("id", "")))
	var n: int = int(data.get("count", 0))
	if id == &"" or n <= 0:
		return InventoryItem.new()
	var cond: Condition = int(data.get("condition", Condition.NORMAL)) as Condition
	return InventoryItem.new(id, n, cond)
