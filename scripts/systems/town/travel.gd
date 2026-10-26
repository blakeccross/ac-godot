class_name Travel
extends RefCounted

## Travelling between towns (`m_card.c` `mCD_SaveStation_*`, `ac_station_clip.c_inc`). Each town is
## a save file in a title slot (`SaveService.slot_paths`). Porter takes a resident's own part
## (`Private_c`, pockets and cash included) into a passport file, leaves them marked away at home,
## and the train goes. Started from another town's slot, K.K. finds the passport and the traveller
## arrives there as a visitor (`mPr_FOREIGNER`): no house, and the only way out is Porter again,
## who saves that town and the passport (`NEXTLAND`). Started from home, K.K. finds it again and
## copies the traveller back (`START_TYPE1`).
##
## Passport: `{home_path, home_town, home_town_id, resident, player_name, private, visited}`.

const PASSPORT_PATH := "user://passport.json"
## Where the passport is kept (tests point it elsewhere).
static var passport_path: String = PASSPORT_PATH
## `Private_c.exists`: FALSE while the resident is out travelling.
const KEY_AWAY := "away"


static func new_town_id() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 0x7FFFFFFF)


static func has_passport() -> bool:
	return FileAccess.file_exists(passport_path)


static func read_passport() -> Dictionary:
	if not has_passport():
		return {}
	var f := FileAccess.open(passport_path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


static func write_passport(data: Dictionary) -> Error:
	var f := FileAccess.open(passport_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	return OK


static func delete_passport() -> void:
	if has_passport():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(passport_path))


## Another town's file to travel to, or "" when none (`mCD_TRANS_ERR_NO_TOWN_DATA`).
## With several title slots, the first other save wins (Porter still has one destination).
static func other_path(path: String) -> String:
	var i: int = SaveService.slot_of(path)
	if i < 0:
		return ""
	for j: int in SaveService.slot_paths.size():
		if j != i and SaveService.has_save(SaveService.slot_paths[j]):
			return SaveService.slot_paths[j]
	return ""


## Label for a town file in talk: the town name, or "Save N" when empty.
static func slot_name(path: String) -> String:
	if path != "" and SaveService.has_save(path):
		var town: String = SaveService.read_town_name(path)
		if town != "":
			return town
	var i: int = SaveService.slot_of(path)
	return "Save %d" % (i + 1) if i >= 0 else "Save"


## Who a passport is for, seen from the town in `path`: `HOME` (their own town), `VISIT`
## (somewhere else) or `NONE`.
enum Kind { NONE, HOME, VISIT }


static func passport_kind(passport: Dictionary, town_id: int) -> int:
	if passport.is_empty():
		return Kind.NONE
	return Kind.HOME if int(passport.get("home_town_id", 0)) == town_id else Kind.VISIT


## Porter's checks before a native leaves (`mCD_CheckStation_bg`): there must be another town
## to go to. Returns "" when the trip can go ahead, else why not:
## `no_town` (0x946), `passport_taken` (another traveller's passport is out, 0x95E).
static func departure_problem() -> String:
	var other: String = other_path(SaveService.current_path)
	if other == "" or not SaveService.has_save(other):
		return "no_town"
	var passport: Dictionary = read_passport()
	if not passport.is_empty() and str(passport.get("player_name", "")) != Game.resident.player_name:
		return "passport_taken"
	return ""


## `mCD_SaveStation_Passport_bg`: the passport takes the traveller's own part; home keeps
## them as away, without the things they carry.
static func depart() -> Error:
	var err: Error = SaveService.save_game()
	if err != OK:
		return err
	var priv: Dictionary = SaveService.last_private.duplicate(true)
	var home: Dictionary = priv.duplicate(true)
	home[KEY_AWAY] = true
	home[PlayerRoster.KEY_INVENTORY] = Inventory.new().to_save()
	Game.roster.slots[Game.roster.current] = home
	err = SaveService.write_roster(Game.roster)
	if err != OK:
		return err
	return write_passport({
		"home_path": SaveService.current_path,
		"home_town": Game.town.town_name,
		"home_town_id": Game.town.town_id,
		"resident": Game.roster.current,
		"player_name": Game.resident.player_name,
		"private": priv,
		"visited": [],
	})


## `mCD_SaveStation_NextLand_bg`: a visitor goes home — this town is saved without them and
## the passport carries what they have now.
static func leave_as_visitor() -> Error:
	var passport: Dictionary = read_passport()
	var err: Error = SaveService.save_game()
	if err != OK:
		return err
	passport["private"] = SaveService.last_private.duplicate(true)
	var visited: Array = passport.get("visited", [])
	if not visited.has(Game.town.town_id):
		visited.append(Game.town.town_id)
	passport["visited"] = visited
	return write_passport(passport)


## `aNPS2_TALK_START_TYPE1`: the traveller's passport goes back into their slot at home.
static func adopt_passport(path: String = "") -> int:
	var passport: Dictionary = read_passport()
	if passport.is_empty():
		return -1
	var roster: PlayerRoster = SaveService.read_roster(path)
	var slot: int = clampi(int(passport.get("resident", 0)), 0, PlayerRoster.MAX - 1)
	var priv: Dictionary = (passport.get("private", {}) as Dictionary).duplicate(true)
	priv.erase(KEY_AWAY)
	roster.slots[slot] = priv
	roster.current = slot
	if SaveService.write_roster(roster, path) != OK:
		return -1
	delete_passport()
	return slot


static func is_away(roster: PlayerRoster, slot: int) -> bool:
	return slot >= 0 and slot < PlayerRoster.MAX and bool(roster.slots[slot].get(KEY_AWAY, false))
