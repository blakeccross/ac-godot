extends Node

## Load/save split state to user://. Not a single Common_Get blob.

## 2: the town and up to four residents (`PlayerRoster`); 1 was one flat resident.
const SAVE_VERSION := 2
const DEFAULT_PATH := "user://save.json"
## The second town (the other Memory Card slot, `mCD` slot B).
const SLOT_B_PATH := "user://save_b.json"
## The two town files (tests point these elsewhere).
var slot_paths: Array[String] = [DEFAULT_PATH, SLOT_B_PATH]

## The town being played (or picked at the title): which file a call without a path uses.
var current_path: String = ""

## `Private_c.reset_code` read by the last `load_game`: non-zero means the session it was
## written for ended without a save (`mCD_CheckResetCode`).
var last_reset_code: int = 0
## Real seconds between the last save and this load (negative: the system clock went back).
var last_elapsed: int = 0
## The resident's part of the last `save_game` (a visitor's goes into the passport).
var last_private: Dictionary = {}


func has_save(path: String = "") -> bool:
	path = _path(path)
	return FileAccess.file_exists(path)


func save_game(path: String = "") -> Error:
	path = _path(path)
	## Inside another resident's house: their rooms go home first.
	Game.leave_resident_house()
	Game.capture_player_from_tree()
	var world: Dictionary = Game.to_save()
	var priv: Dictionary = PlayerRoster.split(world)
	priv[PlayerRoster.KEY_INVENTORY] = Game.inventory.to_save()
	last_private = priv
	## A visitor's own part travels in the passport, never in this town (`mPr_FOREIGNER`).
	if not Game.foreigner:
		Game.roster.slots[Game.roster.current] = priv
	world["roster"] = Game.roster.to_save()
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"clock": Clock.to_dict(),
		## Wall-clock moment of the save, so time keeps passing while the game is off.
		"os_time": int(Time.get_unix_time_from_system()),
		"world": world,
		## `mCD_ClearResetCode`: a proper save closes the session.
		"reset_code": 0,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


## Load the town and resident `slot` (-1: the one played last). An empty slot loads the town
## with a fresh resident, for a newcomer (`aNPS2_TALK_START_TYPE3`).
func load_game(path: String = "", slot: int = -1) -> Error:
	path = _path(path)
	var data: Dictionary = _read(path)
	if data.is_empty():
		return ERR_FILE_NOT_FOUND if not FileAccess.file_exists(path) else ERR_INVALID_DATA
	last_reset_code = int(data.get("reset_code", 0))
	Clock.apply_snapshot(data.get("clock", {}))
	last_elapsed = 0
	if data.has("os_time"):
		last_elapsed = int(Time.get_unix_time_from_system()) - int(data["os_time"])
	var town: Dictionary = town_of(data)
	Game.roster = roster_of(data)
	if slot >= 0 and slot != Game.roster.current:
		## Only the resident who played last carries the open-session stamp (`Private_c.reset_code`).
		last_reset_code = 0
		Game.roster.current = clampi(slot, 0, PlayerRoster.MAX - 1)
	var priv: Dictionary = Game.roster.slots[Game.roster.current]
	if not PlayerRoster.is_resident(priv):
		last_reset_code = 0
	var bags: Variant = priv.get(PlayerRoster.KEY_INVENTORY, {})
	if typeof(bags) == TYPE_DICTIONARY or typeof(bags) == TYPE_ARRAY:
		Game.inventory.from_save(bags)
	Game.apply_snapshot(PlayerRoster.merge(town, priv))
	return OK


## A visitor from another town (`mCD_START_COND_INCOMING_FOREIGNER`): this town as it is, with
## the traveller's own part from their passport and no slot of their own.
func load_visitor(passport: Dictionary, path: String = "") -> Error:
	path = _path(path)
	var data: Dictionary = _read(path)
	if data.is_empty():
		return ERR_FILE_NOT_FOUND
	last_reset_code = 0
	Clock.apply_snapshot(data.get("clock", {}))
	last_elapsed = 0
	if data.has("os_time"):
		last_elapsed = int(Time.get_unix_time_from_system()) - int(data["os_time"])
	Game.roster = roster_of(data)
	Game.roster.current = -1
	Game.foreigner = true
	var priv: Dictionary = passport.get("private", {}) if typeof(passport.get("private")) == TYPE_DICTIONARY else {}
	Game.inventory.from_save(priv.get(PlayerRoster.KEY_INVENTORY, {}))
	## No house here: the traveller's house record stays at home.
	var visiting: Dictionary = priv.duplicate(true)
	visiting.erase(PlayerRoster.KEY_HOUSE)
	visiting.erase(PlayerRoster.KEY_ROOMS)
	Game.apply_snapshot(PlayerRoster.merge(town_of(data), visiting))
	return OK


## The roster in a save, without loading it (K.K.'s player select).
func read_roster(path: String = "") -> PlayerRoster:
	path = _path(path)
	var data: Dictionary = _read(path)
	return roster_of(data) if not data.is_empty() else PlayerRoster.new()


## The town's id in a save (`Game.town_id`), or 0.
func read_town_id(path: String = "") -> int:
	path = _path(path)
	var data: Dictionary = _read(path)
	return int(town_of(data).get("town_id", 0)) if not data.is_empty() else 0


## The town's name in a save, or "".
func read_town_name(path: String = "") -> String:
	path = _path(path)
	var data: Dictionary = _read(path)
	return str(town_of(data).get("town_name", "")) if not data.is_empty() else ""


static func roster_of(data: Dictionary) -> PlayerRoster:
	var roster := PlayerRoster.new()
	var world: Dictionary = data.get("world", {}) if typeof(data.get("world")) == TYPE_DICTIONARY else {}
	if int(data.get("version", 1)) >= 2:
		roster.apply_snapshot(world.get("roster", {}))
	else:
		## A one-resident save from before the roster: it is resident 1.
		var flat: Dictionary = world.duplicate(true)
		var priv: Dictionary = PlayerRoster.split(flat)
		priv[PlayerRoster.KEY_INVENTORY] = data.get("inventory", {})
		roster.slots[0] = priv
	return roster


## The shared town part of a save (no resident in it).
static func town_of(data: Dictionary) -> Dictionary:
	var world: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if typeof(data.get("world")) == TYPE_DICTIONARY else {}
	if int(data.get("version", 1)) < 2:
		PlayerRoster.split(world)
	world.erase("roster")
	return world


func _path(path: String) -> String:
	return path if path != "" else current_path


## Slot index (0 = A, 1 = B) of a town file, or -1.
func slot_of(path: String) -> int:
	return slot_paths.find(path)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


## Write the save with `roster` and `world` replaced (demolishing a house). The rest stays.
func write_roster(roster: PlayerRoster, path: String = "") -> Error:
	path = _path(path)
	var data: Dictionary = _read(path)
	if data.is_empty():
		return ERR_FILE_NOT_FOUND
	var town: Dictionary = town_of(data)
	town["roster"] = roster.to_save()
	data["world"] = town
	data["version"] = SAVE_VERSION
	data.erase("inventory")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


## `mCD_SetResetCode` at load: stamp the file as an open session (and keep the reset count
## just raised), so quitting without saving is caught on the next load.
func mark_session_open(reset_count: int, path: String = "") -> Error:
	path = _path(path)
	var data: Dictionary = _read(path)
	if data.is_empty():
		return ERR_FILE_NOT_FOUND
	data["reset_code"] = randi_range(1, 0xFFFF)
	if typeof(data.get("world")) == TYPE_DICTIONARY:
		var world: Dictionary = data["world"]
		if int(data.get("version", 1)) >= 2 and typeof(world.get("roster")) == TYPE_DICTIONARY:
			var roster: Dictionary = world["roster"]
			var slots: Array = roster.get("slots", [])
			var cur: int = Game.roster.current if Game != null and Game.roster != null else int(roster.get("current", 0))
			roster["current"] = cur
			if cur >= 0 and cur < slots.size() and typeof(slots[cur]) == TYPE_DICTIONARY:
				(slots[cur] as Dictionary)["reset_count"] = reset_count
		else:
			world["reset_count"] = reset_count
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


func delete_save(path: String = "") -> void:
	path = _path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
