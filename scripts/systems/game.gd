extends Node

## Composition root. Owns session phase, scene changes, interiors, shops, and world deltas that are not autoloads.

enum Phase { TITLE, PLAYING }

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const INTERIOR_SCENE := "res://scenes/world/interior.tscn"
const DEFAULT_SPAWN := Vector3(0.0, 0.1, 6.0)
const TEST_BELLS := 2000
const TEST_TOOL_IDS: Array[StringName] = [
	&"shovel",
	&"axe",
	&"net",
	&"fishing_rod",
	&"watering_can",
	&"apple_sapling",
	&"wood_chair",
	&"wood_table",
	&"wood_dresser",
	&"wood_tv",
	&"wall_blue",
	&"floor_tile",
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
var shops: ShopBook = ShopBook.new()
var current_room_id: StringName = &""
var outdoor_return: Vector3 = DEFAULT_SPAWN
var outdoor_return_yaw: float = 0.0
var spawn_at_room_door: bool = false
## After indoor leave, world plays structure leave + player GO_OUT (`mPlayer_INDEX_OUTDOOR`).
var emerge_from_door: bool = false
var interior_session: Interior
var player_name: String = DEFAULT_PLAYER_NAME
var town_name: String = DEFAULT_TOWN_NAME
## Session weather (`mEnv_WEATHER_*`). Rolled by `Weather` on `field_renewed`.
var weather: StringName = &"clear"
## `mEnv_WEATHER_INTENSITY_*` (none/light/normal/heavy).
var weather_intensity: int = int(Weather.Intensity.NONE)
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
## Town grass motif (`bg_tex_idx`): 0 triangle, 1 square, 2 circle.
var grass_pattern: int = WorldData.GrassPattern.TRIANGLE


func _init() -> void:
	villagers.book = relationships


func _ready() -> void:
	if not Clock.field_renewed.is_connected(_on_field_renewed):
		Clock.field_renewed.connect(_on_field_renewed)


func has_continue() -> bool:
	return SaveService.has_save()


func start_new_game(
	mode: WorldData.Mode = WorldData.Mode.TEST, seed_value: int = WorldGenerator.DEFAULT_SEED
) -> void:
	reset_session()
	world_mode = mode
	world_seed = seed_value
	if world_mode == WorldData.Mode.GENERATED:
		grass_pattern = WorldGenerator.decide_grass_pattern(seed_value)
	else:
		grass_pattern = WorldData.GrassPattern.TRIANGLE
	Clock.rtc_override = false
	Clock.sync_from_os()
	apply_weather_roll(Weather.roll())
	if world_mode == WorldData.Mode.TEST:
		give_test_tools()
	_change_scene(WORLD_SCENE)


func resolve_world_data() -> WorldData:
	var data: WorldData
	if world_mode == WorldData.Mode.GENERATED:
		data = WorldGenerator.generate(world_seed)
	else:
		data = WorldGenerator.authored_test_town()
	data.grass_pattern = grass_pattern
	FieldCatalog.set_grass_pattern(grass_pattern)
	return data


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
	shops.clear()
	interior_session = null
	current_room_id = &""
	outdoor_return = DEFAULT_SPAWN
	outdoor_return_yaw = 0.0
	spawn_at_room_door = false
	emerge_from_door = false
	villagers.clear()
	villagers.book = relationships
	VillagerWalk.reset()
	Fishing.reset()
	player_position = DEFAULT_SPAWN
	player_yaw = 0.0
	removed_interactables.clear()
	stump_interactables.clear()
	hole_interactables.clear()
	plant_states.clear()
	player_name = DEFAULT_PLAYER_NAME
	town_name = DEFAULT_TOWN_NAME
	weather = &"clear"
	weather_intensity = int(Weather.Intensity.NONE)
	dialogue_vars.clear()
	world_mode = WorldData.Mode.TEST
	world_seed = WorldGenerator.DEFAULT_SEED
	grass_pattern = WorldData.GrassPattern.TRIANGLE
	set_interact_prompt("")


func set_weather(next: StringName, intensity: int = -1) -> void:
	var next_intensity: int = intensity
	if next_intensity < 0:
		next_intensity = int(Weather.default_intensity_for(Weather.kind_from_name(next)))
	if weather == next and weather_intensity == next_intensity:
		return
	weather = next
	weather_intensity = next_intensity
	weather_changed.emit(weather)


func apply_weather_roll(result: Dictionary) -> void:
	## `{kind: Weather.Kind, intensity: Weather.Intensity}` from `Weather.roll`.
	var kind: Weather.Kind = result.get("kind", Weather.Kind.CLEAR) as Weather.Kind
	var intensity: Weather.Intensity = result.get("intensity", Weather.Intensity.NONE) as Weather.Intensity
	if kind == Weather.Kind.CLEAR:
		intensity = Weather.Intensity.NONE
	set_weather(Weather.kind_name(kind), int(intensity))


func cycle_weather_debug() -> void:
	## HUD debug: clear → rain → snow → sakura.
	var next: StringName = Weather.next_in_cycle(weather)
	set_weather(next)


func give_test_tools() -> void:
	for item_id: StringName in TEST_TOOL_IDS:
		if inventory.count_of(item_id) > 0:
			continue
		var data: ItemData = ItemCatalog.get_item(item_id)
		if data != null:
			inventory.add(data, 1)
	if inventory.wallet <= 0:
		inventory.add_bells(TEST_BELLS)


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
		"grass_pattern": grass_pattern,
		"villagers": villagers.to_save(),
		"relationships": relationships.to_save(),
		"interiors": interiors.to_save(),
		"shops": shops.to_save(),
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
		"weather_intensity": weather_intensity,
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
	if data.has("grass_pattern"):
		grass_pattern = WorldData.clamp_grass_pattern(int(data["grass_pattern"]))
	elif world_mode == WorldData.Mode.GENERATED:
		grass_pattern = WorldGenerator.decide_grass_pattern(world_seed)
	else:
		grass_pattern = WorldData.GrassPattern.TRIANGLE
	relationships.apply_snapshot(data.get("relationships", {}))
	interiors.apply_snapshot(data.get("interiors", {}))
	shops.apply_snapshot(data.get("shops", {}))
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
	if data.has("weather_intensity"):
		weather_intensity = int(data["weather_intensity"])
	elif data.has("weather_packed"):
		var unpacked: Dictionary = Weather.unpack(int(data["weather_packed"]))
		weather = Weather.kind_name(unpacked["kind"] as Weather.Kind)
		weather_intensity = int(unpacked["intensity"])
	else:
		weather_intensity = int(Weather.default_intensity_for(Weather.kind_from_name(weather)))
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
	close_shop()
	current_room_id = room_id
	spawn_at_room_door = true
	_change_scene(INTERIOR_SCENE)
	return true


func open_shop(shop_id: StringName, mode: StringName = Interaction.BUY) -> bool:
	if shop_id == &"":
		return false
	shops.ensure_today(shop_id)
	if get_tree() == null:
		return false
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("close"):
		inv_ui.call("close")
	var ui: Node = get_tree().get_first_node_in_group("shop_ui")
	if ui == null or not ui.has_method("open"):
		return false
	ui.call("open", shop_id, mode)
	return true


func close_shop() -> void:
	if get_tree() == null:
		return
	var ui: Node = get_tree().get_first_node_in_group("shop_ui")
	if ui != null and ui.has_method("close"):
		ui.call("close")


func refresh_shop_set() -> void:
	if get_tree() == null:
		return
	var host: Node = get_tree().get_first_node_in_group("interior")
	if host != null and host.has_method("refresh_shop_set"):
		host.call("refresh_shop_set")


func _on_field_renewed(days: int) -> void:
	shops.renew(days)
	refresh_shop_set()
	## One roll for the current date after renew (`mEnv_DecideWeather` / `aWeather_ChangeWeatherTime0`).
	apply_weather_roll(Weather.roll())


func exit_interior() -> bool:
	if not is_indoors():
		return false
	close_shop()
	var room: Room = interiors.room(current_room_id)
	if room != null and room.parent_room_id != &"":
		return try_enter_interior(room.parent_room_id)
	current_room_id = &""
	interior_session = null
	spawn_at_room_door = false
	player_position = outdoor_return
	player_yaw = outdoor_return_yaw
	emerge_from_door = true
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
		post_notice("Can't place that here.")
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
	if entry.layer == 0 and _has_surface_items(entry):
		post_notice("Clear that first.")
		return false
	var data: ItemData = ItemCatalog.get_item(entry.furniture_id)
	if data == null or not inventory.has_space_for(data, 1):
		return false
	if not _return_placement_contents(entry):
		return false
	var furniture_id: StringName = interior_session.pick_up(placement_id)
	if furniture_id == &"":
		return false
	inventory.add(data, 1)
	_select_item(data.id)
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


func _select_item(item_id: StringName) -> void:
	if item_id == &"":
		return
	for i: int in range(Inventory.POCKET_SLOTS - 1, -1, -1):
		var slot: InventorySlot = inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == item_id:
			inventory.select(i)


func held_furniture() -> FurnitureData:
	var slot: InventorySlot = inventory.selected_slot()
	if slot == null or slot.is_empty():
		return null
	return ItemCatalog.get_item(slot.item.item_id) as FurnitureData


func _selected_furniture() -> FurnitureData:
	return held_furniture()


func try_apply_cover(data: ItemData) -> bool:
	if data == null or interior_session == null or not is_decorating():
		return false
	if data.category == ItemData.Category.WALL:
		if not interior_session.decorate_wall(data.id):
			return false
		inventory.remove(data.id, 1)
		post_notice("Changed the wallpaper.")
		return true
	if data.category == ItemData.Category.FLOOR:
		if not interior_session.decorate_floor(data.id):
			return false
		inventory.remove(data.id, 1)
		post_notice("Changed the carpet.")
		return true
	return false


func _has_surface_items(entry: FurniturePlacement) -> bool:
	if entry == null or interior_session == null:
		return false
	var data: FurnitureData = interior_session.furniture_of(entry.furniture_id)
	var size: Vector2i = entry.resolved_footprint(data)
	for cell: Vector2i in interior_session.grid.footprint_cells(entry.cell, size, entry.facing):
		if interior_session.surface_item_at(cell) != null:
			return true
	return false


func _return_placement_contents(entry: FurniturePlacement) -> bool:
	if entry == null:
		return true
	var needed: Array[ItemData] = []
	if entry.display_id != &"":
		var shown: ItemData = ItemCatalog.get_item(entry.display_id)
		if shown != null:
			needed.append(shown)
	for raw: String in entry.stored:
		var packed: ItemData = ItemCatalog.get_item(StringName(raw))
		if packed != null:
			needed.append(packed)
	for item: ItemData in needed:
		if not inventory.has_space_for(item, 1):
			post_notice("Pockets are full.")
			return false
	if entry.display_id != &"":
		var shown: ItemData = ItemCatalog.get_item(entry.display_id)
		if shown != null:
			inventory.add(shown, 1)
		entry.display_id = &""
	for raw: String in entry.stored:
		var packed: ItemData = ItemCatalog.get_item(StringName(raw))
		if packed != null:
			inventory.add(packed, 1)
	entry.stored.clear()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAYING:
		return
	if event.is_action_pressed("pause_menu"):
		if (
			_group_is_open("inventory_ui")
			or _group_is_open("dialogue_ui")
			or _group_is_open("shop_ui")
		):
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
	Fishing.reset()
	var tree := get_tree()
	if tree == null:
		return
	tree.call_deferred("change_scene_to_file", path)
