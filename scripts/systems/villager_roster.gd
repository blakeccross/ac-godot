class_name VillagerRoster
extends RefCounted

## Town animals[] analog: id → VillagerState. Owned by Game, not an autoload.

var book: RelationshipBook
var _states: Dictionary = {}


func clear() -> void:
	_states.clear()


func get_or_create(villager_id: StringName) -> VillagerState:
	if villager_id == &"":
		var orphan := VillagerState.new()
		return orphan
	if _states.has(villager_id):
		return _states[villager_id] as VillagerState
	var state := VillagerState.new()
	state.villager_id = villager_id
	state.relationship = _bond_for(villager_id)
	_states[villager_id] = state
	return state


func has_id(villager_id: StringName) -> bool:
	return _states.has(villager_id)


func to_save() -> Dictionary:
	var out := {}
	for key: Variant in _states.keys():
		var state: VillagerState = _states[key] as VillagerState
		if state == null or state.villager_id == &"":
			continue
		out[String(state.villager_id)] = state.to_save()
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
		var state := VillagerState.new()
		state.apply_snapshot(entry as Dictionary)
		if state.villager_id == &"":
			state.villager_id = StringName(str(key))
		state.relationship = _adopt_bond(state)
		_states[state.villager_id] = state


func _bond_for(villager_id: StringName) -> Relationship:
	if book != null:
		return book.get_or_create(villager_id)
	var bond := Relationship.new()
	bond.villager_id = villager_id
	return bond


func _adopt_bond(state: VillagerState) -> Relationship:
	var bond: Relationship = state.relationship if state.relationship != null else Relationship.new()
	bond.villager_id = state.villager_id
	if book != null:
		book.put(state.villager_id, bond)
		return book.get_or_create(state.villager_id)
	return bond
