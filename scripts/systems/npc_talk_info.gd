class_name NpcTalkInfo
extends RefCounted

## Per-villager talk bookkeeping for this session (`mNpc_Talk_Info_c`, `m_npc.c`). Not saved:
## `mNpc_ClearTalkInfo` runs on every load.
##
## - `talk_num` counts conversations that end while `timer` (1000 ticks after the last one)
##   is still running. Past the looks' `over_impatient_num` the villager is mildly annoyed;
##   at `talk_num_max` they refuse (`mNpc_GetOverImpatient`).
## - `quest_request` is TRUE until the player hears "any work?" answered (`mNpc_SetQuestRequestOFF`);
##   it comes back once `unlock_timer` runs out.
## - `unlock_timer` only counts down 1000 ticks per acre visit: wading into another acre
##   (`mFI_CheckPlayerWade(mFI_WADE_START)`) re-arms the window (`mNpc_TalkInfoMove`).
## Ticks are decomp logic frames (`DecompTime.TICK_HZ`).

const SLOTS := TownResidents.ANIMAL_NUM_MAX + 1
const TALK_TIMER := 1000
const UNLOCK_WINDOW := 1000
## `l_npc_temper[mNpc_FEEL_*]` — {unlock_timer, over_impatient_num, talk_num_max}. Indexed by
## looks in the decomp (`mNpc_SetUnlockTimer(…, looks)` reads the feel table with a looks index).
const TEMPER: Array = [
	[4000, 12, 15],
	[3000, 10, 13],
	[4000, 12, 15],
	[4000, 10, 13],
	[5000, 9, 12],
	[5000, 9, 12],
]

enum Patience { MILDLY_ANNOYED, ANNOYED, NORMAL }

var _timer := PackedInt32Array()
var _talk_num := PackedInt32Array()
var _quest_request := PackedByteArray()
var _unlock := PackedInt32Array()
var _reset := PackedInt32Array()
## `mNpc_NpcList_c.quest_info`: a quest this villager offered but the player couldn't take
## (pockets full) or turned down; they offer the same kind again next time.
var _client_quest: Array[Dictionary] = []
var _tick_accum: float = 0.0


func _init() -> void:
	clear()


## `mNpc_ClearTalkInfo`.
func clear() -> void:
	_timer = _zeros()
	_talk_num = _zeros()
	_unlock = _zeros()
	_reset = _zeros()
	_quest_request.resize(SLOTS)
	_quest_request.fill(1)
	_client_quest.clear()
	for i: int in SLOTS:
		_client_quest.append(VillagerQuests.new_base())
	_tick_accum = 0.0


func advance(delta: float) -> void:
	_tick_accum += delta * DecompTime.TICK_HZ
	var n: int = int(_tick_accum)
	if n <= 0:
		return
	_tick_accum -= n
	tick(n)


## `mNpc_TalkInfoMove`, `n` times.
func tick(n: int = 1) -> void:
	for i: int in SLOTS:
		for _t: int in n:
			if _timer[i] > 0:
				_timer[i] -= 1
			if _unlock[i] > 0 and _unlock[i] > _reset[i] - UNLOCK_WINDOW:
				_unlock[i] -= 1
			if _unlock[i] == 0 and _reset[i] > 0:
				_talk_num[i] = 0
				_quest_request[i] = 1
				_reset[i] = 0


## `mFI_CheckPlayerWade(mFI_WADE_START)` branch of `mNpc_TalkInfoMove`.
func on_wade_start() -> void:
	for i: int in SLOTS:
		_reset[i] = _unlock[i]


## `mNpc_TalkEndMove`.
func talk_end(slot: int, looks: int) -> void:
	if not _valid(slot) or looks < 0 or looks >= TEMPER.size():
		return
	_timer[slot] = TALK_TIMER
	if _count_talk(slot, looks) and check_over_impatient(slot, looks):
		_set_unlock(slot, looks)


func _count_talk(slot: int, looks: int) -> bool:
	if _talk_num[slot] < int(TEMPER[looks][2]) and _timer[slot] > 0:
		_talk_num[slot] += 1
		return true
	return false


## `mNpc_CheckOverImpatient`.
func check_over_impatient(slot: int, looks: int) -> bool:
	return _valid(slot) and looks >= 0 and looks < TEMPER.size() and _talk_num[slot] >= int(TEMPER[looks][1])


## `mNpc_GetOverImpatient`.
func patience(slot: int, looks: int) -> Patience:
	if not check_over_impatient(slot, looks):
		return Patience.NORMAL
	if _talk_num[slot] >= int(TEMPER[looks][2]):
		return Patience.ANNOYED
	return Patience.MILDLY_ANNOYED


## `mNpc_CheckQuestRequest`.
func quest_request(slot: int) -> bool:
	return _valid(slot) and _quest_request[slot] == 1


## `mNpc_SetQuestRequestOFF`.
func set_quest_request_off(slot: int, looks: int) -> void:
	if not _valid(slot):
		return
	if _quest_request[slot] == 1 and looks >= 0 and looks < TEMPER.size():
		_set_unlock(slot, looks)
	_quest_request[slot] = 0


func client_quest(slot: int) -> Dictionary:
	return _client_quest[slot] if _valid(slot) else VillagerQuests.new_base()


## `aQMgr_actor_set_client_quest_info`.
func set_client_quest(slot: int, info: Dictionary) -> void:
	if _valid(slot):
		VillagerQuests.copy_base(_client_quest[slot], info)


## `aQMgr_actor_clear_client_quest_info`.
func clear_client_quest(slot: int) -> void:
	if _valid(slot):
		VillagerQuests.clear_base(_client_quest[slot])


func talk_num(slot: int) -> int:
	return _talk_num[slot] if _valid(slot) else 0


func _set_unlock(slot: int, looks: int) -> void:
	_unlock[slot] = int(TEMPER[looks][0])
	_reset[slot] = _unlock[slot]


static func _zeros() -> PackedInt32Array:
	var arr := PackedInt32Array()
	arr.resize(SLOTS)
	arr.fill(0)
	return arr


func _valid(slot: int) -> bool:
	return slot >= 0 and slot < SLOTS
