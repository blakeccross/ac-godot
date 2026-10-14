class_name PorterTalk
extends BankTalk

## Porter's talk on the platform in normal play (`ac_npc_station_master_talk.c_inc`,
## `ac_station_clip.c_inc`). A resident is asked "Are you planning on going on a trip?"
## (0x0943; 0x0945 if they have never saved). "Taking a trip!" runs the card check
## (`aSTM_cardproc`): no other town (0x0946), someone else's passport still out (0x095E, which
## can be overwritten), else "the next train should be arriving" (0x094B) and the save of the
## passport and town (0x094F, `Travel.depart`). A visitor is asked "you're leaving already?"
## (0x095C) and their way home saves this town and their passport (0x0955,
## `Travel.leave_as_visitor`). Then "preparations complete" (0x0964) and "Farewell!" (0x0965):
## `result` is `DEPART` and the train takes them to the title.

enum Result { NONE, DEPART, FAILED }

const ASK_TRIP := 0x0943
const NOT_GOING := 0x0944
const NEVER_SAVED := 0x0945
const NO_TOWN := 0x0946
const NEXT_TRAIN := 0x094B
const SAVE_PASSPORT := 0x094F
const SAVE_NEXTLAND := 0x0955
const STAY := 0x095B
const LEAVING := 0x095C
const LEAVE_OK := 0x095D
const OTHER_PASSPORT := 0x095E
const KEEP_PASSPORT := 0x095F
const ERASE_PASSPORT := 0x0960
const READY := 0x0964
const FAREWELL := 0x0965
## Force-talk on getting off the train at home (`aSTM_set_force_talk_info`).
const WELCOME_HOME := 0x0966

var result: int = Result.NONE
var visitor: bool = false
var has_saved: bool = true


func _init(p_visitor: bool, p_has_saved: bool) -> void:
	visitor = p_visitor
	has_saved = p_has_saved


func start_msg() -> int:
	if visitor:
		return LEAVING
	return ASK_TRIP if has_saved else NEVER_SAVED


func prepare() -> void:
	var here: String = SaveService.current_path
	var there: String = Travel.other_path(here)
	## `aSTM_set_slot_name`: FREE3 = the other slot, FREE4 / FREE5 = this one's partner.
	set_free(3, Travel.slot_name(here))
	set_free(4, Travel.slot_name(there))
	set_free(5, Travel.slot_name(there))


func picked(msg_no: int, index: int) -> int:
	match msg_no:
		ASK_TRIP:
			if index != 0:
				return NOT_GOING
			match Travel.departure_problem():
				"no_town":
					return NO_TOWN
				"passport_taken":
					return OTHER_PASSPORT
			return NEXT_TRAIN
		OTHER_PASSPORT:
			return ERASE_PASSPORT if index == 1 else KEEP_PASSPORT
		LEAVING:
			return LEAVE_OK if index == 0 else STAY
	return -1


## `aSTM_chk_train2_talk`: a visitor's town is saved with `0x0955`, not `0x094F`.
func continue_to(_from_msg: int, to_msg: int) -> int:
	if to_msg == SAVE_PASSPORT and visitor:
		return SAVE_NEXTLAND
	return to_msg


## `aSTM_save_talk`: the save runs while "I'm saving your data now" is up.
func entered(msg_no: int) -> void:
	if msg_no == SAVE_PASSPORT or msg_no == SAVE_NEXTLAND:
		var err: Error = Travel.leave_as_visitor() if visitor else Travel.depart()
		if err != OK:
			result = Result.FAILED


func next_step() -> Dictionary:
	match current_msg:
		SAVE_PASSPORT, SAVE_NEXTLAND:
			return {"msg": READY} if result != Result.FAILED else {}
	return {}


func finish() -> void:
	if current_msg == READY and result != Result.FAILED:
		result = Result.DEPART
