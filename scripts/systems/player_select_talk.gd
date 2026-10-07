class_name PlayerSelectTalk
extends BankTalk

## K.K.'s player select for a town that already exists (`ac_npc_p_sel2_talk.c_inc`). He asks
## "Shall we get started?"; "Yes!" asks the player's name from the residents plus "I'm new"
## (`aNPS2_set_choice_str`, four names and no newcomer once the town is full), then gets the
## town ready for them or for a newcomer. "Before I go..." opens the options: sound and rumble
## (acknowledged; this port has no such settings), and "Other things" — demolish a house
## (`aNPS2_chk_clr_pl_data*`, two names a page with "Someone else." when there are four), build
## a new town (erases it) or set the clock (the game follows the system clock). Messages are
## `MSG_5106` on (`base_msg_table[looks]`; K.K. has one).
##
## The scene reads `result` when the talk closes: `LOAD` / `NEW` with `chosen`, `NEW_TOWN`, or
## `NONE`. Demolished residents are in `demolished` (the caller writes the save).

enum Result { NONE, LOAD, NEW, NEW_TOWN, VISIT, RETURN }
enum Menu { NONE, WHO, DEMOLISH }

const BASE := 5106
## `aNPS2_make_msg` offsets.
const GREETING := 0
const SHALL_WE := 2
const OPTIONS := 3
const SOUND := 4
const SET_CLOCK := 5
const DEMOLISH_WHO := 7
const DEMOLISH_SURE := 8
const DEMOLISH_AWAY := 9
const TEARING := 10
const TORN := 11
const KEEP_HOUSES := 12
const NEW_TOWN_ASK := 13
const NEW_TOWN_YES := 14
const NEW_TOWN_GONE := 15
const NEW_TOWN_NO := 16
const WHO := 17
const KNOWN := 18
const NEWCOMER := 19
const CARD_HOME := 22
const CARD_VISIT := 24
const LAST_HOUSE := 25
const TRAVELLER := 29
const TRAVELLER_OK := 30
const BACK_ALREADY := 35
const BACK_COPY := 36
const BACK_KEEP := 37
const RUMBLE := 26
const OTHER_THINGS := 32
const DEMOLISH_OTHER := 34
## `select_data` choice strings (`mChoice_Load_ChoseStringFromRom`).
const SEL_MAYBE_NOT := 0x29
const SEL_SOMEONE_ELSE := 0x1B9
## `aNPS2_set_slot_name`: ROM strings "Slot A" / "Slot B".
const SLOT_NAME_FIRST := 0x6CD
const NEW_PLAYER := "I'm new"

var roster: PlayerRoster
var town_name: String = ""
var save_slot: int = 0
var result: int = Result.NONE
var chosen: int = -1
var demolished: Array[int] = []
var _menu: int = Menu.NONE
var _options: Array[int] = []
var _page: int = 0
var _target: int = -1
## A passport on the other card (`mCD_CheckPassportFile`) and this town's id.
var passport: Dictionary = {}
var town_id: int = 0


func _init(p_roster: PlayerRoster, p_town: String, p_save_slot: int = 0) -> void:
	roster = p_roster
	town_name = p_town
	save_slot = p_save_slot


static func at(offset: int) -> int:
	return BASE + offset


func start_msg() -> int:
	return at(GREETING)


func prepare() -> void:
	context.town_name = town_name
	set_free(4, DialogueCatalog.rom_string(SLOT_NAME_FIRST + clampi(save_slot, 0, 1)))


func entered(msg_no: int) -> void:
	if msg_no == at(TORN) and _target >= 0:
		## `aNPS2_clr_pl_data`: the house and its resident are gone.
		roster.erase(_target)
		demolished.append(_target)
		_target = -1
	elif msg_no == at(NEW_TOWN_GONE):
		result = Result.NEW_TOWN


func pick_step(msg_no: int, index: int) -> Dictionary:
	if msg_no == at(SHALL_WE) and index == 0:
		var card: Dictionary = _passport_step()
		return card if not card.is_empty() else _who()
	## "Umm, hang on!" to playing the left-behind data: the names again.
	if msg_no == at(TRAVELLER) and index == 1:
		return _who()
	if msg_no == at(OTHER_THINGS) and index == 0:
		if roster.count() <= 1:
			set_free(1, roster.name_of(roster.resident_slots()[0]) if roster.count() == 1 else "")
			context.player_name = roster.name_of(roster.resident_slots()[0]) if roster.count() == 1 else context.player_name
			return {"msg": at(LAST_HOUSE)}
		_page = 0
		return _demolish_list(at(DEMOLISH_WHO))
	return {}


func picked(msg_no: int, index: int) -> int:
	match msg_no - BASE:
		SHALL_WE:
			return at(OPTIONS)
		OPTIONS:
			return [at(SOUND), at(RUMBLE), at(OTHER_THINGS), at(SHALL_WE)][clampi(index, 0, 3)]
		OTHER_THINGS:
			return [-1, at(NEW_TOWN_ASK), at(SET_CLOCK), at(SHALL_WE)][clampi(index, 0, 3)]
		DEMOLISH_SURE:
			return at(TEARING) if index == 1 else at(KEEP_HOUSES)
		NEW_TOWN_ASK:
			return at(NEW_TOWN_YES) if index == 1 else at(NEW_TOWN_NO)
		TRAVELLER:
			result = Result.LOAD
			return at(TRAVELLER_OK)
		BACK_ALREADY:
			if index == 0:
				result = Result.RETURN
				return at(BACK_COPY)
			return at(BACK_KEEP)
	return -1


## A message ended on `MSGCONTINUE` with nowhere to go: back to "Shall we get started?".
func next_step() -> Dictionary:
	if current_msg == at(SOUND) or current_msg == at(RUMBLE):
		return {"msg": at(SHALL_WE)}
	return {}


func choose(index: int) -> Dictionary:
	var pick: int = _options[index] if index >= 0 and index < _options.size() else -1
	match _menu:
		Menu.WHO:
			_menu = Menu.NONE
			if pick >= 0:
				chosen = pick
				context.player_name = roster.name_of(pick)
				## Out travelling: the data left behind, without their things (0x5135).
				if Travel.is_away(roster, pick):
					result = Result.NONE
					return {"msg": at(TRAVELLER)}
				result = Result.LOAD
				return {"msg": at(KNOWN)}
			chosen = roster.free_slot()
			result = Result.NEW
			return {"msg": at(NEWCOMER)}
		Menu.DEMOLISH:
			_menu = Menu.NONE
			if pick >= 0:
				_target = pick
				set_free(1, roster.name_of(pick))
				return {"msg": at(DEMOLISH_SURE)}
			if pick == -2:
				_page = 1 - _page
				return _demolish_list(at(DEMOLISH_OTHER))
			return {"msg": at(KEEP_HOUSES)}
	return {}


## `aNPS2_whats_happen` choice 0: a passport on the card decides first. A visitor from another
## town is welcomed in (`START_TYPE2`); this town's own traveller is copied home (`START_TYPE1`),
## or, back already, asked whether to use the travel data anyway.
func _passport_step() -> Dictionary:
	var kind: int = Travel.passport_kind(passport, town_id)
	if kind == Travel.Kind.NONE:
		return {}
	var traveller: String = str(passport.get("player_name", ""))
	set_free(2, traveller)
	set_free(3, DialogueCatalog.rom_string(SLOT_NAME_FIRST + (1 - clampi(save_slot, 0, 1))))
	context.player_name = traveller
	if kind == Travel.Kind.VISIT:
		result = Result.VISIT
		return {"msg": at(CARD_VISIT)}
	chosen = int(passport.get("resident", 0))
	if Travel.is_away(roster, chosen):
		result = Result.RETURN
		return {"msg": at(CARD_HOME)}
	return {"msg": at(BACK_ALREADY)}


## `aNPS2_set_choice_str(…, 1)`: every resident, then "I'm new" while there is room.
func _who() -> Dictionary:
	_menu = Menu.WHO
	_options.clear()
	var labels: Array[String] = []
	for s: int in roster.resident_slots():
		_options.append(s)
		labels.append(roster.name_of(s))
	if roster.free_slot() >= 0:
		_options.append(-1)
		labels.append(NEW_PLAYER)
	return {"msg": at(WHO), "choices": labels}


## `aNPS2_set_choice_str(…, 0)` / `aNPS2_set_choice_str2`: names then "Maybe not...", or two
## names a page with "Someone else." when all four houses are taken. -1 = maybe not,
## -2 = the other page.
func _demolish_list(msg_no: int) -> Dictionary:
	_menu = Menu.DEMOLISH
	_options.clear()
	var labels: Array[String] = []
	var slots: Array[int] = roster.resident_slots()
	if slots.size() >= PlayerRoster.MAX:
		for s: int in slots.slice(_page * 2, _page * 2 + 2):
			_options.append(s)
			labels.append(roster.name_of(s))
		_options.append(-2)
		labels.append(DialogueCatalog.choice_label(SEL_SOMEONE_ELSE))
	else:
		for s: int in slots:
			_options.append(s)
			labels.append(roster.name_of(s))
	_options.append(-1)
	labels.append(DialogueCatalog.choice_label(SEL_MAYBE_NOT))
	return {"msg": msg_no, "choices": labels}
