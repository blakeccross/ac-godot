class_name AnglerTalk
extends BankTalk

## Chip at the bass-fishing tourney (`ac_ev_angler`, messages from 0x10E8). The first talk
## explains the rules and signs the player up; later ones ask "did you catch one?" and open
## the pockets (`mSM_IV_OPEN_TAKE`). A bass is measured (`mFR_fish_rndsize` by its size) and
## eaten: beat the day's record and he hands over a prize from Nook's A/B/C lists. Other
## fish and junk he offers back; tools are never accepted. The tourney runs 6:00–18:00.

const MSG_RULES := 0x10E8
const MSG_CLOSED := 0x10EE
const MSG_CAUGHT_ONE := 0x10EF
const MSG_NOTHING := 0x10F0
const MSG_HAND_IT_OVER := 0x10F1
const MSG_NOT_A_FISH := 0x10F2
const MSG_TOO_VALUABLE := 0x17E5
const MSG_NOTHING_TOP := 0x111E
## `aTRC_clip_get_msgno`: the three bass sizes (+1 no record, +2 record).
const MSG_BASS: Dictionary = {&"small_bass": 0x1112, &"bass": 0x1116, &"large_bass": 0x111A}
## Already on top, and this one doesn't beat it (`get_message_number_fish_zannen`).
const MSG_BASS_TOP_ZANNEN: Dictionary = {&"small_bass": 0x111F, &"bass": 0x1120, &"large_bass": 0x1121}
const MSG_BEAT_SELF := 0x1122
## `aTRC_clip_get_msgno` for every other fish, by `ITM_FISH` index.
const MSG_FISH: Array[int] = [
	0x10F6, 0x10F7, 0x10F8, 0x10F9, 0x10FA, 0x1112, 0x1116, 0x111A, 0x10FB, 0x10FC, 0x10FD, 0x10FE,
	0x10FF, 0x1100, 0x1101, 0x1102, 0x110C, 0x1103, 0x1104, 0x1105, 0x1106, 0x1107, 0x1108, 0x1109,
	0x110A, 0x110B, 0x110D, 0x17E6, 0x17E7, 0x17E8, 0x17E9, 0x17EA, 0x2FB0, 0x2FAF, 0x2FB2, 0x2FB3,
	0x2FB4, 0x2FB5, 0x2FB6, 0x2FB1,
]
## `mString_Load_NumberStringAddUnitFromRom(…, 0x29E)` → "inches".
const UNIT_STRING := 0x29E
enum Size { SMALL, MEDIUM, LARGE }

## The day's record (`aEANG_event_data_c`): `{size, top, top_player, entered}`.
var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var hour: int = 12
## What the pockets gave, and its measured size.
var item: StringName = &""
var size: int = 0
var prize: StringName = &""
## The tourney records a new top goes into (`mEv_fishRecord_set`); `Game.fish_records`.
var records: Array = []
var _offered_back: bool = false


func _init(p_area: Dictionary, p_inventory: Inventory = null, p_rng: RandomNumberGenerator = null, p_hour: int = 12) -> void:
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	hour = p_hour
	if Game != null:
		records = Game.fish_records


## `mFR_fish_rndsize`, in inches.
static func fish_size(rank: int, r: float) -> int:
	match rank:
		Size.LARGE:
			return int((50.0 + 20.0 * r * r) / 2.54)
		Size.MEDIUM:
			return int((30.0 + 20.0 * r) / 2.54)
	return int((30.0 - 20.0 * r * r) / 2.54)


## `aTRC_clip_random_topsize`: a villager may have landed a bigger one since (Chip rolls
## once each time he's set up). `names` are tonight's anglers.
static func roll_npc_record(p_area: Dictionary, p_hour: int, names: Array, r: RandomNumberGenerator) -> void:
	var rank: int = Size.SMALL
	if p_hour >= 15:
		rank = r.randi_range(0, 2)
	elif p_hour >= 9:
		rank = r.randi_range(0, 1)
	var s: int = fish_size(rank, r.randf())
	if s > int(p_area.get("size", 0)):
		p_area["size"] = s
		p_area["top_player"] = false
		p_area["top"] = str(names[r.randi_range(0, names.size() - 1)]) if not names.is_empty() else "Someone"


func _closed() -> bool:
	return hour < 6 or hour >= 18


func _top_is_player() -> bool:
	return bool(area.get("top_player", false))


## `aTRC_clip_set_topname`: free0 the holder, free1 the size.
func _set_top_name() -> void:
	set_free(0, str(area.get("top", "")))
	set_free(1, inches(int(area.get("size", 0))))


static func inches(n: int) -> String:
	return "%d %s" % [n, DialogueCatalog.rom_string(UNIT_STRING)]


func start_msg() -> int:
	if _closed():
		return MSG_CLOSED
	if bool(area.get("entered", false)):
		return MSG_CAUGHT_ONE
	area["entered"] = true
	return MSG_RULES


## `aEANG_say_tureta`: "no" → today's record; the fish choices of the offer-back ask.
func picked(msg_no: int, index: int) -> int:
	if msg_no == MSG_CAUGHT_ONE and index == 1:
		_set_top_name()
		return MSG_NOTHING_TOP if _top_is_player() else MSG_NOTHING
	if _offered_back:
		## `aEANG_demo_give_me`: 0 takes it back; otherwise Chip keeps it.
		_offered_back = false
		if index != 0 and inventory != null and item != &"":
			inventory.remove(item, 1)
	return -1


func next_step() -> Dictionary:
	if current_msg == MSG_HAND_IT_OVER:
		return {"hand": {"pocket": -1, "mode": "take"}}
	if item != &"" and MSG_BASS.has(item) and current_msg == int(MSG_BASS[item]):
		return _measured()
	return {}


## `aEANG_msg_win_open_wait`: what came out of the pockets.
func hand_result(p_item: StringName, _pocket: int = -1) -> Dictionary:
	item = p_item
	if item == &"":
		_set_top_name()
		return msg(MSG_NOTHING_TOP if _top_is_player() else MSG_NOTHING)
	var data: ItemData = ItemCatalog.get_item(item)
	if MSG_BASS.has(item):
		## `aEANG_demo_measure_init`.
		var rank: int = Size.SMALL
		if item == &"large_bass":
			rank = Size.LARGE
		elif item == &"bass":
			rank = Size.MEDIUM
		size = fish_size(rank, rng.randf())
		set_free(2, inches(size))
		return {"anim": {"take": item}, "msg": int(MSG_BASS[item])}
	if data != null and data.category == ItemData.Category.FISH:
		_offered_back = true
		var idx: int = FishData.TYPE_IDS.find(item)
		var n: int = MSG_FISH[idx] if idx >= 0 and idx < MSG_FISH.size() else MSG_NOT_A_FISH
		return {"anim": {"take": item}, "msg": n}
	if data != null and data.category == ItemData.Category.TOOL:
		return {"anim": {"take": item}, "then": {"anim": {"give": item}, "msg": MSG_TOO_VALUABLE}}
	_offered_back = true
	return {"anim": {"take": item}, "msg": MSG_NOT_A_FISH}


## `aEANG_demo_measure`: record or not, the bass is his.
func _measured() -> Dictionary:
	var bass: StringName = item
	item = &""
	if inventory != null:
		inventory.remove(bass, 1)
	var was_top: bool = _top_is_player()
	_set_top_name()
	if size > int(area.get("size", 0)):
		area["size"] = size
		area["top_player"] = true
		area["top"] = context.player_name if context != null else ""
		FishRecord.set_record(records, str(area["top"]), true, size,
			EventDates.ordinal(Clock.year, Clock.month, Clock.day), hour * 60 + Clock.minute)
		prize = _pick_prize()
		var data: ItemData = ItemCatalog.get_item(prize)
		if data != null and inventory != null:
			inventory.add(data, 1)
		if context != null:
			context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")
		var n: int = MSG_BEAT_SELF if was_top else int(MSG_BASS[bass]) + 2
		return {"anim": {"give": prize}, "msg": n}
	if was_top:
		return msg(int(MSG_BASS_TOP_ZANNEN[bass]))
	return msg(int(MSG_BASS[bass]) + 1)


## `aEANG_SelectRandomItem`: a shirt or a piece of furniture from Nook's A/B/C lists.
func _pick_prize() -> StringName:
	var label: String = ["A", "B", "C"][rng.randi_range(0, 2)]
	var kind: String = "cloth" if rng.randf() > 0.5 else "ftr"
	var id: StringName = FtrCatalog.pick_named(kind, label, rng)
	return id if id != &"" else &"apple"
