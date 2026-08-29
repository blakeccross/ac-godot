class_name VillagerRoster
extends RefCounted

## Town animals[] analog: id → VillagerState. Owned by Game, not an autoload.

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
		_states[state.villager_id] = state
