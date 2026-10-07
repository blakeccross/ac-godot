class_name PlayerRoster
extends RefCounted

## The town's human residents (`Save_Get(private_data[PLAYER_NUM])`): up to four, one played at
## a time. Each slot keeps that resident's own part of the save (`Private_c`): who they are,
## their pockets and letters, catalogue, encyclopedia, own designs, friendships and errands,
## diary, calendar, birthday and mail state, and their house with its rooms. Everything else
## (the map, villagers, shops, museum, events…) belongs to the town and is shared.
##
## `Game.to_save()` writes one flat dictionary; `split` lifts the private keys out of it and
## `merge` puts a slot's back before `Game.apply_snapshot`. The slot being played is only a
## snapshot from the last save; the live state is in `Game`.

const MAX := 4
## Top-level `Game.to_save()` keys that belong to the resident.
const PRIVATE_KEYS: Array[String] = [
	"player", "sunburn", "diary", "species_log", "catalog", "worn_design_slot",
	"current_room_id", "outdoor_return", "player_name", "player_gender", "player_face",
	"cloth_id", "destiny", "has_map", "reset_count", "complete_flags", "first_job",
	"first_job_hint_count", "valentine_year", "celebrated_birthday_year",
	"birthday_present_npc", "birthday_card_day", "mother_mail", "calendar", "relationships",
	"quests", "hra", "farway", "bank_gift_flags", "met_blanca", "mask_cat_scheduled",
	"golden_shovel_shown",
]
## `DesignBook` keys that are the resident's own eight designs (`my_org`).
const PRIVATE_DESIGN_KEYS: Array[String] = ["player", "order"]
const KEY_INVENTORY := "inventory"
const KEY_ROOMS := "player_rooms"
const KEY_HOUSE := "player_house"
const KEY_DESIGNS := "own_designs"

var slots: Array[Dictionary] = [{}, {}, {}, {}]
var current: int = 0
## Other residents' houses opened this session (gyroid sales, the outdoor model), by slot.
var _houses: Dictionary = {}


static func is_resident(slot: Dictionary) -> bool:
	return not slot.is_empty() and str(slot.get("player_name", "")) != ""


## Lift the resident's part out of a full `Game.to_save()` dictionary (`world` is changed).
static func split(world: Dictionary) -> Dictionary:
	var priv: Dictionary = {}
	for key: String in PRIVATE_KEYS:
		if world.has(key):
			priv[key] = world[key]
			world.erase(key)
	var interiors: Variant = world.get("interiors", {})
	if typeof(interiors) == TYPE_DICTIONARY:
		var rooms: Dictionary = (interiors as Dictionary).get("rooms", {})
		var mine_rooms: Dictionary = {}
		for key: Variant in rooms.keys():
			if PlayerHouse.is_player_room(StringName(str(key))):
				mine_rooms[key] = rooms[key]
		for key: Variant in mine_rooms.keys():
			rooms.erase(key)
		priv[KEY_ROOMS] = mine_rooms
		var houses: Dictionary = (interiors as Dictionary).get("houses", {})
		var own_id := String(InteriorCatalog.PLAYER_HOUSE_ID)
		if houses.has(own_id):
			priv[KEY_HOUSE] = houses[own_id]
			houses.erase(own_id)
	var designs: Variant = world.get("designs", {})
	if typeof(designs) == TYPE_DICTIONARY:
		var own: Dictionary = {}
		for key: String in PRIVATE_DESIGN_KEYS:
			if (designs as Dictionary).has(key):
				own[key] = (designs as Dictionary)[key]
				(designs as Dictionary).erase(key)
		priv[KEY_DESIGNS] = own
	return priv


## The town dictionary with a resident's part put back (a new copy).
static func merge(town: Dictionary, priv: Dictionary) -> Dictionary:
	var out: Dictionary = town.duplicate(true)
	for key: String in PRIVATE_KEYS:
		if priv.has(key):
			out[key] = priv[key]
	var interiors: Dictionary = out.get("interiors", {}) if typeof(out.get("interiors")) == TYPE_DICTIONARY else {}
	var rooms: Dictionary = interiors.get("rooms", {}) if typeof(interiors.get("rooms")) == TYPE_DICTIONARY else {}
	var mine: Variant = priv.get(KEY_ROOMS, {})
	if typeof(mine) == TYPE_DICTIONARY:
		for key: Variant in (mine as Dictionary).keys():
			rooms[key] = (mine as Dictionary)[key]
	var houses: Dictionary = interiors.get("houses", {}) if typeof(interiors.get("houses")) == TYPE_DICTIONARY else {}
	if priv.has(KEY_HOUSE):
		houses[String(InteriorCatalog.PLAYER_HOUSE_ID)] = priv[KEY_HOUSE]
	interiors["rooms"] = rooms
	interiors["houses"] = houses
	out["interiors"] = interiors
	var designs: Dictionary = out.get("designs", {}) if typeof(out.get("designs")) == TYPE_DICTIONARY else {}
	var own: Variant = priv.get(KEY_DESIGNS, {})
	if typeof(own) == TYPE_DICTIONARY:
		for key: Variant in (own as Dictionary).keys():
			designs[key] = (own as Dictionary)[key]
	out["designs"] = designs
	return out


func clear() -> void:
	slots = [{}, {}, {}, {}]
	current = 0
	_houses.clear()


func count() -> int:
	var n: int = 0
	for s: Dictionary in slots:
		if is_resident(s):
			n += 1
	return n


## Played slots in order (`aNPS2_get_pl_no`).
func resident_slots() -> Array[int]:
	var out: Array[int] = []
	for i: int in MAX:
		if is_resident(slots[i]):
			out.append(i)
	return out


## `aNPS2_get_free_pl_no`: the first empty slot, or -1 when the town is full.
func free_slot() -> int:
	for i: int in MAX:
		if not is_resident(slots[i]):
			return i
	return -1


func name_of(slot: int) -> String:
	return str(slots[slot].get("player_name", "")) if slot >= 0 and slot < MAX else ""


## Outdoor plot (`player_house`, `player_house_1`…) a slot lives on, or "".
func plot_of(slot: int) -> StringName:
	if slot < 0 or slot >= MAX:
		return &""
	var h: Variant = slots[slot].get(KEY_HOUSE, {})
	return StringName(str((h as Dictionary).get("outdoor_building_id", ""))) if typeof(h) == TYPE_DICTIONARY else &""


## Slot of the resident living on `building_id`, or -1. The slot being played answers from
## `owned_building_id` (its house may have been picked after the last save).
func slot_on_plot(building_id: StringName) -> int:
	if building_id == &"":
		return -1
	if PlayerHouse.owned_building_id() == building_id:
		return current
	for i: int in MAX:
		if i != current and is_resident(slots[i]) and plot_of(i) == building_id:
			return i
	return -1


## Plots other residents live on (not the one being played).
func other_plots() -> Array[StringName]:
	var out: Array[StringName] = []
	for i: int in MAX:
		if i != current and is_resident(slots[i]) and plot_of(i) != &"":
			out.append(plot_of(i))
	return out


## Another resident's house record, live for this session (writes go back on `flush_houses`).
func house_of(slot: int) -> House:
	if slot == current and Game != null and Game.interiors != null:
		return Game.interiors.player_house()
	if slot < 0 or slot >= MAX or not is_resident(slots[slot]):
		return null
	if not _houses.has(slot):
		var h := House.new()
		h.id = InteriorCatalog.PLAYER_HOUSE_ID
		h.apply_snapshot(slots[slot].get(KEY_HOUSE, {}))
		_houses[slot] = h
	return _houses[slot] as House


func flush_houses() -> void:
	for key: Variant in _houses.keys():
		var slot: int = int(key)
		if slot != current and is_resident(slots[slot]):
			slots[slot][KEY_HOUSE] = (_houses[key] as House).to_save()


## The player-house rooms and record now in `interiors`, as a slot keeps them.
static func capture_house(interiors: InteriorBook) -> Dictionary:
	var data: Dictionary = interiors.player_house_save()
	return {KEY_ROOMS: data["rooms"], KEY_HOUSE: data["house"]}


## Put a slot's house (or a stash from `capture_house`) into `interiors`.
static func restore_house(interiors: InteriorBook, priv: Dictionary) -> void:
	interiors.replace_player_house(priv.get(KEY_ROOMS, {}), priv.get(KEY_HOUSE, {}))


## Drop a cached house record after its slot was written some other way.
func forget_house(slot: int) -> void:
	_houses.erase(slot)


## A letter for another resident lands in their mailbox. False when it is full.
func deliver_mail(slot: int, mail: MailData) -> bool:
	if slot < 0 or slot >= MAX or slot == current or not is_resident(slots[slot]):
		return false
	var inv := Inventory.new()
	inv.from_save(slots[slot].get(KEY_INVENTORY, {}))
	if inv.add_received_mail(mail) < 0:
		return false
	slots[slot][KEY_INVENTORY] = inv.to_save()
	return true


## `aNPS2_clr_pl_data`: the resident and their house are gone.
func erase(slot: int) -> void:
	if slot < 0 or slot >= MAX:
		return
	slots[slot] = {}
	_houses.erase(slot)


func to_save() -> Dictionary:
	flush_houses()
	return {"current": current, "slots": slots.duplicate(true)}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var raw: Variant = (data as Dictionary).get("slots", [])
	if typeof(raw) == TYPE_ARRAY:
		for i: int in mini((raw as Array).size(), MAX):
			var s: Variant = (raw as Array)[i]
			slots[i] = (s as Dictionary).duplicate(true) if typeof(s) == TYPE_DICTIONARY else {}
	current = clampi(int((data as Dictionary).get("current", 0)), 0, MAX - 1)
