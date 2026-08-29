class_name RelationshipBook
extends RefCounted

## Player ↔ villager memories. Owned by Game, not an autoload. Not a dialogue graph.

var _bonds: Dictionary = {}


func clear() -> void:
	_bonds.clear()


func get_or_create(villager_id: StringName) -> Relationship:
	if villager_id == &"":
		return Relationship.new()
	if _bonds.has(villager_id):
		return _bonds[villager_id] as Relationship
	var bond := Relationship.new()
	bond.villager_id = villager_id
	_bonds[villager_id] = bond
	return bond


func put(villager_id: StringName, bond: Relationship) -> void:
	if villager_id == &"" or bond == null:
		return
	bond.villager_id = villager_id
	_bonds[villager_id] = bond


func has_id(villager_id: StringName) -> bool:
	return _bonds.has(villager_id)


func record_talk(villager_id: StringName, day_key: String) -> int:
	return get_or_create(villager_id).record_talk(day_key)


func record_gift(villager_id: StringName, item_id: StringName, day_key: String) -> int:
	return get_or_create(villager_id).record_gift(item_id, day_key)


func give_gift(
	villager_id: StringName, item_id: StringName, inventory: Inventory, day_key: String
) -> bool:
	if inventory == null or item_id == &"":
		return false
	if inventory.count_of(item_id) <= 0:
		return false
	inventory.remove(item_id, 1)
	record_gift(villager_id, item_id, day_key)
	return true


func to_save() -> Dictionary:
	var out := {}
	for key: Variant in _bonds.keys():
		var bond: Relationship = _bonds[key] as Relationship
		if bond == null or bond.villager_id == &"":
			continue
		out[String(bond.villager_id)] = bond.to_save()
	return out


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = data
	for key: Variant in bag.keys():
		var entry: Variant = bag[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var bond := Relationship.new()
		bond.apply_snapshot(entry as Dictionary)
		if bond.villager_id == &"":
			bond.villager_id = StringName(str(key))
		_bonds[bond.villager_id] = bond
