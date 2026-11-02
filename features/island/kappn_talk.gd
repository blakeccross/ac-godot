class_name KappnTalk
extends BankTalk

## Kapp'n's talks (`ac_npc_sendo_move.c_inc`, the `aSEN_TALK_*` states) without the Game Boy
## Advance: the island lives in the town's own data, so the trip's questions are the ride, the island's
## name (`aSEN_TALK_GET_ISLAND_NAME_MENU_*`) and the way back. Women hear the same lines from 210 on
## (`aSEN_get_msg_no`). The sea shanties he sings on the way are separate one-off talks.

enum Kind { TOWN, ISLAND, SONG, ARRIVE_ISLAND, ARRIVE_TOWN, SHOVE_OFF }

const MSG_RIDE := 0x3073
const MSG_RIDE_RAIN := 0x30B9
const MSG_NO_RIDE := 0x3074
const MSG_NAME_ASK := 0x3079
const MSG_BOARD := 0x30BE
const MSG_SHOVE_OFF := 0x30BF
const MSG_LEAVE_ASK := 0x3080
const MSG_LEAVE_NOT_YET := 0x3081
const MSG_HEAD_BACK := 0x3084
const MSG_ARRIVE_ISLAND := 0x307A
const MSG_ARRIVE_TOWN := 0x308B
const MSG_JUST_ARRIVED := 0x307B
const FEMALE_OFFSET := 210
## `aSEN_set_norm_talk_info`: Kapp'n's slot for the island-name order (`mDemo_ORDER_NPC0` 9).
const ORDER_SLOT := 9
const NAME_LEN := 6
## The shanty a trip sings (`aBTD_sing_sendo_start_wait_init`): per rider pattern (0 male out,
## 1 female out, 2 male back, 3 female back), the first part, the patter between and the second.
const SONG_FIRST: Array[int] = [0x3091, 0x3163, 0x3096, 0x3168]
const SONG_PATTER: Array[int] = [0x309B, 0x316D, 0x30A5, 0x3177]
const SONG_SECOND: Array[int] = [0x30AF, 0x3181, 0x30AF, 0x3181]

var kind: Kind = Kind.TOWN
var raining: bool = false
var female: bool = false
## Set by the choices: the player wants to ride / to go home.
var ride: bool = false
var _msg: int = -1
var _naming: bool = false


static func gendered(msg_no: int, is_female: bool) -> int:
	return msg_no + FEMALE_OFFSET if is_female else msg_no


## The shanty's three messages for rider `pattern` with song rolls `first`, `patter`, `second`.
static func song_messages(pattern: int, first: int, patter: int, second: int) -> Array[int]:
	return [SONG_FIRST[pattern] + first, SONG_PATTER[pattern] + patter, SONG_SECOND[pattern] + second]


## Rider pattern: leaving (0) or coming home (1), by gender.
static func pattern_for(leaving_island: bool, is_female: bool) -> int:
	return (2 if leaving_island else 0) + (1 if is_female else 0)


func _init(p_kind: Kind = Kind.TOWN, p_msg: int = -1) -> void:
	kind = p_kind
	_msg = p_msg


func start_msg() -> int:
	match kind:
		Kind.TOWN:
			return gendered(MSG_RIDE_RAIN if raining else MSG_RIDE, female)
		Kind.ISLAND:
			return gendered(MSG_LEAVE_ASK, female)
		Kind.ARRIVE_ISLAND:
			return gendered(MSG_ARRIVE_ISLAND, female)
		Kind.ARRIVE_TOWN:
			return gendered(MSG_ARRIVE_TOWN, female)
		Kind.SHOVE_OFF:
			return gendered(MSG_SHOVE_OFF, female)
	return _msg


func prepare() -> void:
	if context != null:
		context.frees = PackedStringArray([Game.town.island_name if Game != null else ""])


## `aSEN_pl_ride_on_check_talk_proc` / `aSEN_pl_ride_on_check2_talk_proc`.
func picked(msg_no: int, index: int) -> int:
	if kind == Kind.TOWN and (msg_no == gendered(MSG_RIDE, female) or msg_no == gendered(MSG_RIDE_RAIN, female)):
		if index != 0:
			return gendered(MSG_NO_RIDE, female)
		ride = true
		if Game.town.island_name.is_empty():
			return gendered(MSG_NAME_ASK, female)
		return gendered(MSG_BOARD, female)
	if kind == Kind.ISLAND and msg_no == gendered(MSG_LEAVE_ASK, female):
		if index != 0:
			return gendered(MSG_LEAVE_NOT_YET, female)
		ride = true
		return gendered(MSG_HEAD_BACK, female)
	return -1


## The name question ends on `mDemo_ORDER_NPC0` 9 (the menu opens).
func npc_order(target: String, slot: int, value: int) -> void:
	super.npc_order(target, slot, value)
	if kind == Kind.TOWN and target == "npc0" and slot == ORDER_SLOT and value != 0 and msg_is(MSG_NAME_ASK):
		_naming = true


func msg_is(base: int) -> bool:
	return current_msg == gendered(base, female)


func next_step() -> Dictionary:
	if _naming:
		_naming = false
		return {"text": {"initial": "", "lines": 1, "len": NAME_LEN}}
	return {}


## `mLE_TYPE_ISLAND_NAME` closed: keep the name and board.
func text_result(text: String) -> Dictionary:
	var name: String = text.strip_edges()
	if name.is_empty():
		ride = false
		return {"msg": gendered(MSG_NO_RIDE, female)}
	Game.town.island_name = name
	if context != null:
		context.frees = PackedStringArray([name])
	return {"msg": gendered(MSG_BOARD, female)}
