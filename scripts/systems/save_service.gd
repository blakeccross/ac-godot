extends Node

## Load/save split state to user://. Not a single Common_Get blob.

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://save.json"


func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


func save_game(path: String = DEFAULT_PATH) -> Error:
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"clock": Clock.to_dict(),
		"inventory": Game.inventory.to_save(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


func load_game(path: String = DEFAULT_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	var data: Dictionary = parsed
	Clock.apply_snapshot(data.get("clock", {}))
	var bags: Variant = data.get("inventory", [])
	if typeof(bags) == TYPE_ARRAY:
		Game.inventory.from_save(bags)
	return OK


func delete_save(path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
