class_name WispEvent
extends RefCounted

## The Wisp's night (`mEv_EVENT_GHOST`, `ac_ev_ghost`, `ac_ins_hitodama`). On a night the
## calendar picks (`EventCalendar.ghost_tonight`, 0:00–3:59) he wanders a random spot,
## invisible, in a town with at least eight weeds. Walk up and he speaks; close in and he
## shows himself and asks for his five spirits (`FOUND`, `ACTIVE`). Each lives in its own
## random acre (columns 1–5, rows B–E) and comes out as a field insect when the player
## enters that acre; netting one clears its acre. They stack in one pocket slot. All five
## back and he grants a wish — no weeds, a new roof colour, or something not yet in the
## catalogue — and is gone for the night (`RETURNED`). At 4:00 he leaves.
##
## `state()` is per night (`mEv_gst_c` / `mEv_gst_common_c`): {day, found, active, returned,
## name_no, acres: [[bx, bz], …]}.

const AREA := &"ghost"
const SPIRITS := 5
const SPIRIT_ID := &"spirit"
const TYPE_SPIRIT := 40
## `aEGH_MINIMUM_GRASS_COUNT`.
const MIN_WEEDS := 8
## `okoruhito_str_no`: who will yell at him (ROM strings from 0x62E).
const NAME_STRINGS := 32
const NAME_STRING_FIRST := 0x62E
## Spirit catch reports: 0x2F03 for the first, one more for each already in the pockets.
const MSG_CATCH := 0x2F03
const END_HOUR := 4


static func state() -> Dictionary:
	if Game == null or Game.events == null:
		return {}
	var s: Dictionary = Game.events.area(AREA)
	var today: String = Game.events.day_key()
	if str(s.get("day", "")) != today:
		s.clear()
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		s["day"] = today
		s["found"] = false
		s["active"] = false
		s["returned"] = false
		s["name_no"] = rng.randi_range(0, NAME_STRINGS - 1)
		s["acres"] = roll_acres(rng)
	return s


## `ghost_start`: five different acres, columns 1–5, rows 2–5.
static func roll_acres(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	while out.size() < SPIRITS:
		var acre := [1 + rng.randi_range(0, 4), 2 + rng.randi_range(0, 3)]
		if not out.has(acre):
			out.append(acre)
	return out


## A spirit waits in `acre` for the player to come in (`aSOI_check_hitodama_set_block`).
static func spirit_in_acre(acre: Vector2i) -> bool:
	var s: Dictionary = state()
	return bool(s.get("active", false)) and (s.get("acres", []) as Array).has([acre.x, acre.y])


## `aIHD_unregist_set_block_table`: caught, so that acre is empty now.
static func caught_in(acre: Vector2i) -> void:
	(state().get("acres", []) as Array).erase([acre.x, acre.y])


static func spirit_count(inventory: Inventory) -> int:
	return inventory.count_of(SPIRIT_ID) if inventory != null else 0


static func catch_msg(held_before: int) -> int:
	return MSG_CATCH + clampi(held_before, 0, SPIRITS - 1)


## `aEGH_okoruhito`.
static func boss_name(s: Dictionary) -> String:
	return DialogueCatalog.rom_string(NAME_STRING_FIRST + int(s.get("name_no", 0)))


## The Wisp stays away from a well-kept town until he has been found (`aEGH_actor_ct`).
static func shows_up(s: Dictionary, weeds: int) -> bool:
	if bool(s.get("returned", false)):
		return false
	return bool(s.get("found", false)) or weeds >= MIN_WEEDS


## `aEGH_not_collect_get`: something from the shop lists, the event and lottery lists, the
## gyroids or the umbrellas that the catalogue doesn't have yet; anything from them if it
## has everything.
static func wish_item(owned: Array, rng: RandomNumberGenerator) -> StringName:
	var pool: Array[StringName] = []
	for kind: String in ["ftr", "carpet", "wall", "cloth"]:
		for label: String in ["A", "B", "C"]:
			pool.append_array(ShopGoods.abc_list(kind, label))
	for birth: String in ["event", "lottery", "haniwa"]:
		pool.append_array(FtrCatalog.list(birth))
	pool.append_array(ShopGoods.umbrella_pool())
	var fresh: Array[StringName] = []
	for id: StringName in pool:
		if not owned.has(id) and ItemCatalog.get_item(id) != null:
			fresh.append(id)
	var from: Array[StringName] = fresh if not fresh.is_empty() else pool
	return from[rng.randi_range(0, from.size() - 1)] if not from.is_empty() else &"peach"


## `aEGH_select_wait`, the weeds: how bad it is decides the answer (0x2EF1–0x2EF5).
static func weeds_msg(weeds: int) -> int:
	if weeds < 50:
		return 0x2EF1
	if weeds < 150:
		return 0x2EF2
	if weeds < 450:
		return 0x2EF3
	if weeds < 900:
		return 0x2EF4
	return 0x2EF5
