extends Node

## Composition root. Owns session phase, scene changes, interiors, and world deltas that are not autoloads.

enum Phase { TITLE, PLAYING }

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const INTERIOR_SCENE := "res://scenes/world/interior.tscn"
const DEFAULT_SPAWN := Vector3(0.0, 0.1, 6.0)
const TEST_TOOL_IDS: Array[StringName] = [
	&"shovel",
	&"axe",
	&"net",
	&"fishing_rod",
	&"watering_can",
	&"apple_sapling",
	&"wood_chair",
	&"wood_table",
]

signal phase_changed(phase: Phase)
signal prompt_changed(text: String)
signal notice_posted(text: String)
signal weather_changed(weather: StringName)

const DEFAULT_PLAYER_NAME := "Player"
const DEFAULT_TOWN_NAME := "Town"

var inventory: Inventory = Inventory.new()
var villagers: VillagerRoster = VillagerRoster.new()
var relationships: RelationshipBook = RelationshipBook.new()
var interiors: InteriorBook = InteriorBook.new()
var current_room_id: StringName = &""
var outdoor_return: Vector3 = DEFAULT_SPAWN
var outdoor_return_yaw: float = 0.0
var spawn_at_room_door: bool = false
var interior_session: Interior
var player_name: String = DEFAULT_PLAYER_NAME
var town_name: String = DEFAULT_TOWN_NAME
## Hook for dialogue / later weather (`mEnv_WEATHER_*`). Not a weather system.
var weather: StringName = &"clear"
var dialogue_vars: Dictionary = {}
var phase: Phase = Phase.TITLE
var player_position: Vector3 = DEFAULT_SPAWN
var player_yaw: float = 0.0
var removed_interactables: Array[String] = []
var stump_interactables: Array[String] = []
var hole_interactables: Array[String] = []
var plant_states: Dictionary = {}
var interact_prompt: String = ""
var world_mode: WorldData.Mode = WorldData.Mode.TEST
var world_seed: int = WorldGenerator.DEFAULT_SEED


func _init() -> void:
	villagers.book = relationships


func has_continue() -> bool:
	return SaveService.has_save()


func start_new_game(
	mode: WorldData.Mode = WorldData.Mode.TEST, seed_value: int = WorldGenerator.DEFAULT_SEED
) -> void:
	reset_session()
	world_mode = mode
	world_seed = seed_value
	Clock.rtc_override = false
	Clock.sync_from_os()
	if world_mode == WorldData.Mode.TEST:
		give_test_tools()
	_change_scene(WORLD_SCENE)


func resolve_world_data() -> WorldData:
	if world_mode == WorldData.Mode.GENERATED:
		return WorldGenerator.generate(world_seed)
	return WorldGenerator.authored_test_town()


func continue_game() -> void:
	if SaveService.load_game() != OK:
		start_new_game()
		return
	if current_room_id != &"":
		_change_scene(INTERIOR_SCENE)
	else:
		_change_scene(WORLD_SCENE)


func return_to_title() -> void:
	capture_player_from_tree()
	SaveService.save_game()
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


func notify_world_ready() -> void:
	if world_mode == WorldData.Mode.TEST:
		give_test_tools()
	_set_phase(Phase.PLAYING)


func notify_title_ready() -> void:
	_set_phase(Phase.TITLE)
	set_interact_prompt("")


func reset_session() -> void:
	inventory.clear()
	relationships.clear()
	interiors.clear()
	interior_session = null
	current_room_id = &""
	outdoor_return = DEFAULT_SPAWN
	outdoor_return_yaw = 0.0
	spawn_at_room_door = false
	villagers.clear()
	villagers.book = relationships
	VillagerWalk.reset()
	player_position = DEFAULT_SPAWN
	player_yaw = 0.0
	removed_interactables.clear()
	stump_interactables.clear()
	hole_interactables.clear()
	plant_states.clear()
	player_name = DEFAULT_PLAYER_NAME
	town_name = DEFAULT_TOWN_NAME
	weather = &"clear"
	dialogue_vars.clear()
	world_mode = WorldData.Mode.TEST
	world_seed = WorldGenerator.DEFAULT_SEED
	set_interact_prompt("")


func set_weather(next: StringName) -> void:
	if weather == next:
		return
	weather = next
	weather_changed.emit(weather)


func give_test_tools() -> void:
	for item_id: StringName in TEST_TOOL_IDS:
		if inventory.count_of(item_id) > 0:
			continue
		var data: ItemData = ItemCatalog.get_item(item_id)
		if data != null:
			inventory.add(data, 1)


func capture_player_from_tree() -> void:
	if get_tree() == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player_position = player.global_position
	if player.has_method("facing_yaw"):
		player_yaw = float(player.call("facing_yaw"))


func is_interactable_removed(persist_id: StringName) -> bool:
	if persist_id == &"":
		return false
	return removed_interactables.has(String(persist_id))


func mark_interactable_removed(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	var key := String(persist_id)
	if not removed_interactables.has(key):
		removed_interactables.append(key)
	clear_stump(persist_id)


func is_stump(persist_id: StringName) -> bool:
	if persist_id == &"":
		return false
	return stump_interactables.has(String(persist_id))


func mark_stump(persist_id: StringName) -> void:
	if persist_id == &"" or is_interactable_removed(persist_id):
		return
	var key := String(persist_id)
	if not stump_interactables.has(key):
		stump_interactables.append(key)


func clear_stump(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	stump_interactables.erase(String(persist_id))


func is_hole(persist_id: StringName) -> bool:
	if persist_id == &"":
		return false
	return hole_interactables.has(String(persist_id))


func mark_hole(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	var key := String(persist_id)
	if not hole_interactables.has(key):
		hole_interactables.append(key)


func clear_hole(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	hole_interactables.erase(String(persist_id))


func set_interact_prompt(text: String) -> void:
	if interact_prompt == text:
		return
	interact_prompt = text
	prompt_changed.emit(text)


func post_notice(text: String) -> void:
	notice_posted.emit(text)


func to_save() -> Dictionary:
	return {
		"player": {
			"x": player_position.x,
			"y": player_position.y,
			"z": player_position.z,
			"yaw": player_yaw,
		},
		"removed_interactables": removed_interactables.duplicate(),
		"stump_interactables": stump_interactables.duplicate(),
		"hole_interactables": hole_interactables.duplicate(),
		"plants": plant_states.duplicate(true),
		"world_mode": int(world_mode),
		"world_seed": world_seed,
		"villagers": villagers.to_save(),
		"relationships": relationships.to_save(),
		"interiors": interiors.to_save(),
		"current_room_id": String(current_room_id),
		"outdoor_return": {
			"x": outdoor_return.x,
			"y": outdoor_return.y,
			"z": outdoor_return.z,
			"yaw": outdoor_return_yaw,
		},
		"player_name": player_name,
		"town_name": town_name,
		"weather": String(weather),
		"dialogue_vars": dialogue_vars.duplicate(true),
	}


func apply_snapshot(data: Dictionary) -> void:
	var pose: Variant = data.get("player", {})
	if typeof(pose) == TYPE_DICTIONARY:
		var p: Dictionary = pose
		player_position = Vector3(
			float(p.get("x", DEFAULT_SPAWN.x)),
			float(p.get("y", DEFAULT_SPAWN.y)),
			float(p.get("z", DEFAULT_SPAWN.z))
		)
		player_yaw = float(p.get("yaw", 0.0))
	else:
		player_position = DEFAULT_SPAWN
		player_yaw = 0.0
	removed_interactables.clear()
	var removed: Variant = data.get("removed_interactables", [])
	if typeof(removed) == TYPE_ARRAY:
		for entry: Variant in removed:
			removed_interactables.append(str(entry))
	stump_interactables.clear()
	var stumps: Variant = data.get("stump_interactables", [])
	if typeof(stumps) == TYPE_ARRAY:
		for entry: Variant in stumps:
			var key := str(entry)
			if not removed_interactables.has(key):
				stump_interactables.append(key)
	hole_interactables.clear()
	var holes: Variant = data.get("hole_interactables", [])
	if typeof(holes) == TYPE_ARRAY:
		for entry: Variant in holes:
			hole_interactables.append(str(entry))
	plant_states.clear()
	var plants: Variant = data.get("plants", {})
	if typeof(plants) == TYPE_DICTIONARY:
		for key: Variant in (plants as Dictionary).keys():
			var rec: Variant = plants[key]
			if typeof(rec) == TYPE_DICTIONARY:
				plant_states[str(key)] = (rec as Dictionary).duplicate()
	world_mode = int(data.get("world_mode", WorldData.Mode.TEST)) as WorldData.Mode
	world_seed = int(data.get("world_seed", WorldGenerator.DEFAULT_SEED))
	relationships.apply_snapshot(data.get("relationships", {}))
	interiors.apply_snapshot(data.get("interiors", {}))
	current_room_id = StringName(str(data.get("current_room_id", "")))
	var outdoor: Variant = data.get("outdoor_return", {})
	if typeof(outdoor) == TYPE_DICTIONARY:
		var o: Dictionary = outdoor
		outdoor_return = Vector3(
			float(o.get("x", DEFAULT_SPAWN.x)),
			float(o.get("y", DEFAULT_SPAWN.y)),
			float(o.get("z", DEFAULT_SPAWN.z))
		)
		outdoor_return_yaw = float(o.get("yaw", 0.0))
	else:
		outdoor_return = DEFAULT_SPAWN
		outdoor_return_yaw = 0.0
	villagers.book = relationships
	villagers.apply_snapshot(data.get("villagers", {}))
	player_name = str(data.get("player_name", DEFAULT_PLAYER_NAME))
	town_name = str(data.get("town_name", DEFAULT_TOWN_NAME))
	weather = StringName(str(data.get("weather", "clear")))
	dialogue_vars.clear()
	var vars_raw: Variant = data.get("dialogue_vars", {})
	if typeof(vars_raw) == TYPE_DICTIONARY:
		dialogue_vars = (vars_raw as Dictionary).duplicate(true)


func is_indoors() -> bool:
	return current_room_id != &""


func is_decorating() -> bool:
	if not is_indoors():
		return false
	var room: Room = interiors.room(current_room_id)
	return room != null and room.can_decorate


func try_enter_interior(target: StringName) -> bool:
	var room_id: StringName = InteriorCatalog.resolve_entry(target)
	if room_id == &"":
		return false
	var room: Room = interiors.room(room_id)
	if room == null:
		return false
	if not InteriorCatalog.is_open_now(room):
		post_notice(InteriorCatalog.closed_notice(room))
		return false
	if not is_indoors():
		capture_player_from_tree()
		outdoor_return = player_position
		outdoor_return_yaw = player_yaw
	current_room_id = room_id
	spawn_at_room_door = true
	_change_scene(INTERIOR_SCENE)
	return true


func exit_interior() -> bool:
	if not is_indoors():
		return false
	var room: Room = interiors.room(current_room_id)
	if room != null and room.parent_room_id != &"":
		return try_enter_interior(room.parent_room_id)
	current_room_id = &""
	interior_session = null
	spawn_at_room_door = false
	player_position = outdoor_return
	player_yaw = outdoor_return_yaw
	_change_scene(WORLD_SCENE)
	return true


func bind_interior(session: Interior) -> void:
	interior_session = session


func try_place_furniture(actor: Node3D) -> bool:
	if actor == null or interior_session == null or not is_decorating():
		return false
	var data: FurnitureData = _selected_furniture()
	if data == null:
		return false
	var facing: WorldGrid.Facing = WorldGrid.facing_from_yaw(
		float(actor.call("facing_yaw")) if actor.has_method("facing_yaw") else actor.rotation.y
	)
	var cell: Vector2i = interior_session.grid.world_to_cell(actor.global_position)
	cell = interior_session.grid.step(cell, facing)
	var entry: FurniturePlacement = interior_session.place(data, cell, facing)
	if entry == null:
		return false
	inventory.remove(data.id, 1)
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() else null
	if host != null and host.has_method("spawn_placement"):
		host.call("spawn_placement", entry)
	post_notice("Placed %s." % data.display_name)
	return true


func pick_up_furniture(placement_id: StringName) -> bool:
	if interior_session == null or not is_decorating():
		return false
	var entry: FurniturePlacement = interior_session.room.placement_by_id(placement_id)
	if entry == null:
		return false
	var data: ItemData = ItemCatalog.get_item(entry.furniture_id)
	if data == null or not inventory.has_space_for(data, 1):
		return false
	var furniture_id: StringName = interior_session.pick_up(placement_id)
	if furniture_id == &"":
		return false
	inventory.add(data, 1)
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() else null
	if host != null and host.has_method("despawn_placement"):
		host.call("despawn_placement", placement_id)
	post_notice("Picked up %s." % data.display_name)
	return true


func rotate_furniture(placement_id: StringName) -> bool:
	if interior_session == null or not is_decorating():
		return false
	if not interior_session.rotate(placement_id, 1):
		return false
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() else null
	if host != null and host.has_method("refresh_placement"):
		host.call("refresh_placement", placement_id)
	return true


func held_furniture() -> FurnitureData:
	var slot: InventorySlot = inventory.selected_slot()
	if slot == null or slot.is_empty():
		return null
	return ItemCatalog.get_item(slot.item.item_id) as FurnitureData


func _selected_furniture() -> FurnitureData:
	return held_furniture()


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAYING:
		return
	if event.is_action_pressed("pause_menu"):
		if _group_is_open("inventory_ui") or _group_is_open("dialogue_ui"):
			return
		return_to_title()
		get_viewport().set_input_as_handled()


func _set_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func _group_is_open(group: String) -> bool:
	if get_tree() == null:
		return false
	var ui: Node = get_tree().get_first_node_in_group(group)
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.call_deferred("change_scene_to_file", path)
