extends Node

## Composition root. Owns session phase, scene changes, and world deltas that are not autoloads.

enum Phase { TITLE, PLAYING }

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const DEFAULT_SPAWN := Vector3(0.0, 0.1, 6.0)

signal phase_changed(phase: Phase)
signal prompt_changed(text: String)
signal notice_posted(text: String)

var inventory: Inventory = Inventory.new()
var phase: Phase = Phase.TITLE
var player_position: Vector3 = DEFAULT_SPAWN
var player_yaw: float = 0.0
var removed_interactables: Array[String] = []
var interact_prompt: String = ""
var world_mode: WorldData.Mode = WorldData.Mode.TEST
var world_seed: int = WorldGenerator.DEFAULT_SEED


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
	_change_scene(WORLD_SCENE)


func resolve_world_data() -> WorldData:
	if world_mode == WorldData.Mode.GENERATED:
		return WorldGenerator.generate(world_seed)
	return WorldGenerator.authored_test_town()


func continue_game() -> void:
	if SaveService.load_game() != OK:
		start_new_game()
		return
	_change_scene(WORLD_SCENE)


func return_to_title() -> void:
	capture_player_from_tree()
	SaveService.save_game()
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


func notify_world_ready() -> void:
	_set_phase(Phase.PLAYING)


func notify_title_ready() -> void:
	_set_phase(Phase.TITLE)
	set_interact_prompt("")


func reset_session() -> void:
	inventory.clear()
	player_position = DEFAULT_SPAWN
	player_yaw = 0.0
	removed_interactables.clear()
	world_mode = WorldData.Mode.TEST
	world_seed = WorldGenerator.DEFAULT_SEED
	set_interact_prompt("")


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
		"world_mode": int(world_mode),
		"world_seed": world_seed,
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
	world_mode = int(data.get("world_mode", WorldData.Mode.TEST)) as WorldData.Mode
	world_seed = int(data.get("world_seed", WorldGenerator.DEFAULT_SEED))


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAYING:
		return
	if event.is_action_pressed("pause_menu"):
		return_to_title()
		get_viewport().set_input_as_handled()


func _set_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.call_deferred("change_scene_to_file", path)
