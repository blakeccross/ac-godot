extends Node

## Load/save split state to user://. Not a single Common_Get blob.

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://save.json"

## `Private_c.reset_code` read by the last `load_game`: non-zero means the session it was
## written for ended without a save (`mCD_CheckResetCode`).
var last_reset_code: int = 0
## Real seconds between the last save and this load (negative: the system clock went back).
var last_elapsed: int = 0


func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


func save_game(path: String = DEFAULT_PATH) -> Error:
	Game.capture_player_from_tree()
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"clock": Clock.to_dict(),
		## Wall-clock moment of the save, so time keeps passing while the game is off.
		"os_time": int(Time.get_unix_time_from_system()),
		"inventory": Game.inventory.to_save(),
		"world": Game.to_save(),
		## `mCD_ClearResetCode`: a proper save closes the session.
		"reset_code": 0,
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
	last_reset_code = int(data.get("reset_code", 0))
	Clock.apply_snapshot(data.get("clock", {}))
	last_elapsed = 0
	if data.has("os_time"):
		last_elapsed = int(Time.get_unix_time_from_system()) - int(data["os_time"])
	var bags: Variant = data.get("inventory", {})
	if typeof(bags) == TYPE_DICTIONARY or typeof(bags) == TYPE_ARRAY:
		Game.inventory.from_save(bags)
	if data.has("world") and typeof(data["world"]) == TYPE_DICTIONARY:
		Game.apply_snapshot(data["world"] as Dictionary)
	return OK


## `mCD_SetResetCode` at load: stamp the file as an open session (and keep the reset count
## just raised), so quitting without saving is caught on the next load.
func mark_session_open(reset_count: int, path: String = DEFAULT_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var read := FileAccess.open(path, FileAccess.READ)
	if read == null:
		return FileAccess.get_open_error()
	var parsed: Variant = JSON.parse_string(read.get_as_text())
	read.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	var data: Dictionary = parsed
	data["reset_code"] = randi_range(1, 0xFFFF)
	if data.has("world") and typeof(data["world"]) == TYPE_DICTIONARY:
		(data["world"] as Dictionary)["reset_count"] = reset_count
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


func delete_save(path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
