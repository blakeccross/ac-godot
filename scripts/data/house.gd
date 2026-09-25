class_name House
extends Resource

## A building's indoor rooms. Player size tiers follow `mHm_HOMESIZE_*`;
## NPC and public buildings are one (or linked) rooms, not player loan upgrades.
##
## The player fields mirror `mHm_rmsz_c` + the palette bytes of `mHm_hs_c`: an upgrade is
## *ordered* (`next_size_tier` + `order_*`) and only lands on a later day
## (`HouseUpgrade.check_rehouse_order`, `mHm_CheckRehouseOrder`).

enum SizeTier { SMALL, MEDIUM, LARGE, UPPER, STATUE }

## `mHm_OUTLOOK_PAL_NUM` — roof colour sets picked at Nook's.
const OUTLOOK_PAL_COUNT := 12

@export var id: StringName = &""
@export var occupant_id: StringName = &""
@export var outdoor_building_id: StringName = &""
@export var rooms: Array[StringName] = []
@export var size_tier: SizeTier = SizeTier.SMALL
## `size_info.next_size` — equals `size_tier` until an upgrade is ordered.
@export var next_size_tier: SizeTier = SizeTier.SMALL
## `flags.has_basement` (`mHm_SetBasement`).
@export var has_basement: bool = false
## `size_info.basement_ordered` / `statue_ordered` / `renew`.
@export var basement_ordered: bool = false
@export var statue_ordered: bool = false
## Set the day the build lands; Nook clears it when he collects the next loan.
@export var renew: bool = false
## `size_info.pad_1` — the basement was just finished on a large house, so Nook offers
## the upper floor next (`aNSC_MSG_REHOUSE_UPPER`).
@export var basement_just_built: bool = false
## `size_info.statue_rank` — 0 gold … 3 jade.
@export var statue_rank: int = 0
## `size_info.upgrade_order_date` — Y/M/D the last order was placed (0 = never).
@export var order_year: int = 0
@export var order_month: int = 0
@export var order_day: int = 0
## `outlook_pal` (current), `ordered_outlook_pal` (picked at Nook's), `next_outlook_pal`
## (villager / paint / other sources).
@export var outlook_pal: int = 0
@export var ordered_outlook_pal: int = 0
@export var next_outlook_pal: int = 0
## `keep_house_size` — packed size / next_size / renew snapshot taken on save.
@export var keep_house_size: int = 0
## `mHm_hs_c.music_box` — one bit per K.K. song the house owns (`MinidiskCatalog`).
@export var music_box: int = 0
## `mHm_goki_c`: cockroaches waiting in the house (0..10) and the day it was last played on
## (`goki.time`; year 0 = not recorded yet).
@export var goki_count: int = 0
@export var goki_year: int = 0
@export var goki_month: int = 0
@export var goki_day: int = 0
## `mHm_hs_c.flags.has_saved`: the owner has saved at the gyroid at least once
## (`aHNW_set_save_permission`). Until then a first-job player with no villager friends gets
## the "good luck with your part-time job" line instead of the menu.
@export var has_saved: bool = false
## `mHm_hs_c.haniwa` (`Haniwa_c`): the gyroid outside the house. Four held items, each
## `{ "item": StringName, "count": int, "cond": int (InventoryItem.Condition),
## "exchange": int (HaniwaStore.Exchange), "price": int }` — an empty slot has item &"".
## `haniwa_message` is shown to visitors (4 lines, `HANIWA_MESSAGE_LEN` 128); `haniwa_bells`
## is what visitors have paid and the owner has not collected yet.
@export var haniwa_items: Array[Dictionary] = []
@export var haniwa_message: String = ""
@export var haniwa_bells: int = 0
## `door_original`: player design slot (0-7) shown on the front door, 0xFF = the house mark.
@export var door_original: int = 0xFF


func entry_room_id() -> StringName:
	if rooms.is_empty():
		return &""
	return rooms[0]


## Decomp `mHm_HOMESIZE_*` value that decides the outdoor model and main-room layout.
## The statue stage keeps the last real house model (`myhome4`) with the statue beside it.
func model_tier() -> int:
	return mini(int(size_tier), int(SizeTier.UPPER))


func to_save() -> Dictionary:
	var ids: Array = []
	for room_id: StringName in rooms:
		ids.append(String(room_id))
	return {
		"id": String(id),
		"occupant_id": String(occupant_id),
		"outdoor_building_id": String(outdoor_building_id),
		"rooms": ids,
		"size_tier": int(size_tier),
		"next_size_tier": int(next_size_tier),
		"has_basement": has_basement,
		"basement_ordered": basement_ordered,
		"statue_ordered": statue_ordered,
		"renew": renew,
		"basement_just_built": basement_just_built,
		"statue_rank": statue_rank,
		"order_date": [order_year, order_month, order_day],
		"outlook_pal": outlook_pal,
		"ordered_outlook_pal": ordered_outlook_pal,
		"next_outlook_pal": next_outlook_pal,
		"keep_house_size": keep_house_size,
		## A string: JSON numbers are doubles and 55 bits do not fit.
		"music_box": str(music_box),
		"goki_count": goki_count,
		"goki_date": [goki_year, goki_month, goki_day],
		"has_saved": has_saved,
		"haniwa_items": _haniwa_items_to_save(),
		"haniwa_message": haniwa_message,
		"haniwa_bells": haniwa_bells,
		"door_original": door_original,
	}


func _haniwa_items_to_save() -> Array:
	var out: Array = []
	for rec: Dictionary in haniwa_items:
		var copy: Dictionary = rec.duplicate()
		copy["item"] = String(rec.get("item", ""))
		out.append(copy)
	return out


func apply_snapshot(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = data
	id = StringName(str(bag.get("id", String(id))))
	occupant_id = StringName(str(bag.get("occupant_id", String(occupant_id))))
	outdoor_building_id = StringName(
		str(bag.get("outdoor_building_id", String(outdoor_building_id)))
	)
	size_tier = clampi(int(bag.get("size_tier", int(size_tier))), 0, int(SizeTier.STATUE)) as SizeTier
	## Saves that predate ordering: no pending upgrade.
	next_size_tier = (
		clampi(int(bag.get("next_size_tier", int(size_tier))), 0, int(SizeTier.STATUE)) as SizeTier
	)
	has_basement = bool(bag.get("has_basement", has_basement))
	basement_ordered = bool(bag.get("basement_ordered", basement_ordered))
	statue_ordered = bool(bag.get("statue_ordered", statue_ordered))
	renew = bool(bag.get("renew", renew))
	basement_just_built = bool(bag.get("basement_just_built", basement_just_built))
	statue_rank = clampi(int(bag.get("statue_rank", statue_rank)), 0, 3)
	var stamp: Variant = bag.get("order_date", [])
	if typeof(stamp) == TYPE_ARRAY and (stamp as Array).size() >= 3:
		var parts: Array = stamp
		order_year = int(parts[0])
		order_month = int(parts[1])
		order_day = int(parts[2])
	outlook_pal = clampi(int(bag.get("outlook_pal", outlook_pal)), 0, OUTLOOK_PAL_COUNT - 1)
	ordered_outlook_pal = clampi(
		int(bag.get("ordered_outlook_pal", ordered_outlook_pal)), 0, OUTLOOK_PAL_COUNT - 1
	)
	next_outlook_pal = clampi(
		int(bag.get("next_outlook_pal", next_outlook_pal)), 0, OUTLOOK_PAL_COUNT - 1
	)
	keep_house_size = int(bag.get("keep_house_size", keep_house_size))
	music_box = int(str(bag.get("music_box", music_box)))
	goki_count = clampi(int(bag.get("goki_count", goki_count)), 0, 10)
	has_saved = bool(bag.get("has_saved", has_saved))
	var held: Variant = bag.get("haniwa_items", null)
	if typeof(held) == TYPE_ARRAY:
		haniwa_items.clear()
		for raw: Variant in held as Array:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var rec: Dictionary = raw as Dictionary
			haniwa_items.append({
				"item": StringName(str(rec.get("item", ""))),
				"count": int(rec.get("count", 1)),
				"cond": int(rec.get("cond", 0)),
				"exchange": int(rec.get("exchange", 0)),
				"price": int(rec.get("price", 0)),
			})
	haniwa_message = str(bag.get("haniwa_message", haniwa_message))
	haniwa_bells = maxi(0, int(bag.get("haniwa_bells", haniwa_bells)))
	door_original = int(bag.get("door_original", door_original))
	var goki_date: Variant = bag.get("goki_date", [])
	if typeof(goki_date) == TYPE_ARRAY and (goki_date as Array).size() >= 3:
		goki_year = int((goki_date as Array)[0])
		goki_month = int((goki_date as Array)[1])
		goki_day = int((goki_date as Array)[2])
	var ids: Variant = bag.get("rooms", [])
	if typeof(ids) != TYPE_ARRAY:
		return
	rooms.clear()
	for entry: Variant in ids:
		var room_id := StringName(str(entry))
		if room_id != &"":
			rooms.append(room_id)
