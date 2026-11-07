class_name VillagerQuestTalk
extends RefCounted

## The quest half of a villager's talk (`ac_quest_manager.c`, `ac_quest_talk_init.c`): looks at
## the player's deliveries / errands and this villager's contest (`VillagerQuests`) and picks the
## step — a reward still owed, a finished quest, a reminder, a give-up, a new request, or
## "Nothing much going on". `VillagerTalkManager` owns it and runs it with `run`; choosing
## "Let's talk!" hands back to the manager's everyday chat (`start_normal`).
##
## It reads the talk's inputs (villager, pockets, date, quest books) through `talk`.

const SELECT_TALK_MSG := 0x2A6
const NO_WORK_MSG := 0x282
const CANCEL_MSG := 0x254A

## `aQMgr_talk_quest_select_get_choice` default: random pick inside each select group.
const CHOICE_HELP := 0x7F
const CHOICE_TALK := 0x89
const CHOICE_NEVERMIND := 0x16A

## `aQMgr_TALK_STEP_*` (plus `DONE` once the talk is over).
enum Step {
	SELECT,
	RECONF_OR_NORMAL,
	ROOT_RECONF_OR_NORMAL,
	NO_OR_NORMAL,
	FULL_ITEM_OR_NORMAL,
	RENEW_ERRAND_OR_NORMAL,
	NEW_QUEST_OR_NORMAL,
	NORMAL,
	OCCUR_QUEST,
	GIVEUP,
	GIVEUP_ITEM,
	FIN_QUEST_START,
	FIN_QUEST_START_NOT_HAND,
	FIN_QUEST_REWARD,
	FIN_QUEST_THANKS,
	AFTER_REWARD,
	AFTER_REWARD_THANKS,
	GET_ITEM,
	CHANGE_WAIT,
	RENEW_ERRAND_IRAI_END,
	RENEW_ERRAND_IRAI_END_GIVE_ITEM,
	CONTEST_OTHER_OR_NORMAL,
	FINISH_LETTER,
	FINISH,
	DONE,
}

## The talk this belongs to; held weakly because the talk owns this.
var talk: VillagerTalkManager:
	get:
		return _talk.get_ref() as VillagerTalkManager
var step: Step = Step.SELECT
## `manager->choice.talk_action`: the menu pick this step answers, -1 for none.
var _talk_action: int = -1
var _entries: Array[Dictionary] = []
var _entry_idx: int = -1
var _msg_category: int = VillagerQuests.Msg.NONE
var _category_start: int = 0
## `manager->target`.
var _target: Dictionary = {}
var _talk: WeakRef


func _init(p_talk: VillagerTalkManager) -> void:
	_talk = weakref(p_talk)


## `aQMgr_talk_quest_change_normal_or_hint`: "Never mind" cancels; anything else is a chat
## (+1 friendship) — `aQMgr_TALK_COMMON_CHANGE_TALK_NORMAL`.
func _change_normal_or_hint() -> TalkStep:
	if _talk_action == 2:
		return cancel_msg(CANCEL_MSG)
	if talk.state != null:
		talk.state.add_friendship(1)
	step = Step.NORMAL
	return TalkStep.show(talk.start_normal())


## `aQMgr_talk_quest_select_get_choice` labels.
const CHOICE_DELIVERY := 0x94


const CHOICE_FORGOT := 0x95


const CHOICE_FRUIT := 0x96


const CHOICE_PICKUP := 0x97


const CHOICE_BALL := 0x98


const CHOICE_SNOWMAN := 0x99


const CHOICE_FLOWERS := 0x9A


const CHOICE_UM := 0x9B


const CHOICE_FISH := 0xEA


const CHOICE_BUG := 0xEB


## `aQMgr_talk_quest_start_choice`: accept / turn down.
const CHOICE_ACCEPT := 0x43


const CHOICE_REJECT := 0x4D


const FULL_POCKETS_MSG := 0x440


const ROOT_RECONF_MSG := 0x3D4


const ERRAND_FORGET_MSG := 0x2B73


const THIEF_MSG := 0x499


const NO_REWARD_MSG := 0x4AB


const LETTER_THANKS_MSG := 0x1B17


const LETTER_OTHER_MSG := 0x1B29


const LETTER_FULL_MSG := 0x1B05


const FLOWER_SHORT_MSG := 0x1069


## `l_*reward_msg`, by `Reward` kind.
const REWARD_MSG: Array[int] = [0x011B, 0x00D3, 0x00E5, 0x00F7, 0x0109, 0x013F, 0x012D, 0x081D]


const CONTEST_REWARD_MSG: Array = [
	[0x011B, 0x00D3, 0x00E5, 0x1146, 0x1158, 0x116A, 0x00E5, 0x081D],
	[0x0DA3, 0x00D3, 0x00E5, 0x0DB5, 0x0DC7, 0x013F, 0x00E5, 0x081D],
	[0x0E57, 0x00D3, 0x00E5, 0x0E69, 0x0E7B, 0x013F, 0x00E5, 0x081D],
	[0x0FD9, 0x00D3, 0x00E5, 0x0FEB, 0x0FFD, 0x013F, 0x00E5, 0x081D],
	[0x157A, 0x00D3, 0x00E5, 0x1556, 0x1568, 0x013F, 0x00E5, 0x081D],
	[0x15F8, 0x00D3, 0x00E5, 0x15D4, 0x15E6, 0x013F, 0x00E5, 0x081D],
	[0x011B, 0x00D3, 0x00E5, 0x00F7, 0x0109, 0x013F, 0x012D, 0x081D],
]


const AFTER_REWARD_MSG: Array[int] = [0x0304, 0x0000, 0x0000, 0x0316, 0x0328, 0x0000, 0x0000, 0x0000]


## `aQMgr_actor_talk_after_reward` swaps in the soccer / snowman / flower tables.
const AFTER_CONTEST_SWAP := [CONTEST_REWARD_MSG[1], CONTEST_REWARD_MSG[2], CONTEST_REWARD_MSG[3]]


## `l_contest_hoka_msg_no`: "someone else already did it".
const CONTEST_OTHER_MSG: Array[int] = [0x1134, 0x0E21, 0x0ED5, 0x1057, 0x1544, 0x15C2, 0x1AF3]


## `l_quest_type_table_fj` / `_qst` and their kind tables.
const FJ_KINDS: Array = [[VillagerQuests.DELIVERY_NORMAL, VillagerQuests.DELIVERY_LOST], [VillagerQuests.ERRAND_REQUEST]]


const QST_KINDS: Array = [
	[VillagerQuests.DELIVERY_NORMAL, VillagerQuests.DELIVERY_FOREIGN, VillagerQuests.DELIVERY_REMOVE, VillagerQuests.DELIVERY_LOST],
	[VillagerQuests.ERRAND_REQUEST],
	[0, 1, 2, 3, 4, 5, 6],
]


## `aQMgr_actor_set_quest_data` results.
enum NewQuest { ERROR, SUCCESS, NO_SPACE, NO_FOREIGN_ID, NO_REMOVE_ANIMAL_ID }


## `aQMgr_actor_move_talk_init`: run the step the last message was waiting for.
func run(action: int) -> TalkStep:
	_talk_action = action
	match step:
		Step.SELECT:
			return _select_talk()
		Step.RECONF_OR_NORMAL:
			if _talk_action == 0:
				_msg_category = VillagerQuests.Msg.REQUEST_RECONF
				return _msg()
			return _change_normal_or_hint()
		Step.ROOT_RECONF_OR_NORMAL:
			if _talk_action == 0:
				_category_start = ROOT_RECONF_MSG
				return _msg()
			return _change_normal_or_hint()
		Step.NO_OR_NORMAL:
			if _talk_action == 0:
				_finish_first_job_open_quest()
				_target["free"] = {}
				_category_start = NO_WORK_MSG
				return _msg()
			return _change_normal_or_hint()
		Step.FULL_ITEM_OR_NORMAL:
			if _talk_action == 0:
				if (_target.get("set_data", []) as Array).is_empty():
					_category_start = FULL_POCKETS_MSG
				else:
					_msg_category = VillagerQuests.Msg.FULL_ITEM
				return _msg()
			return _change_normal_or_hint()
		Step.RENEW_ERRAND_OR_NORMAL:
			return _renew_errand_or_normal()
		Step.NEW_QUEST_OR_NORMAL:
			return _new_quest_or_normal()
		Step.OCCUR_QUEST:
			return _occur_quest()
		Step.GIVEUP:
			return _giveup()
		Step.FIN_QUEST_START:
			if _talk_action == 0:
				return _open_menu()
			return _change_normal_or_hint()
		Step.FIN_QUEST_START_NOT_HAND:
			if _talk_action == 2:
				return cancel_msg(CANCEL_MSG)
			step = Step.FIN_QUEST_REWARD
			_msg_category = VillagerQuests.Msg.COMPLETE_INIT
			return _msg()
		Step.FIN_QUEST_REWARD:
			return _fin_quest_reward()
		Step.FIN_QUEST_THANKS:
			_msg_category = VillagerQuests.Msg.COMPLETE_END
			step = Step.CHANGE_WAIT
			return _with_anim(_msg(), TalkStep.Handover.NPC_GIVES, _target.get("reward_item", &""))
		Step.AFTER_REWARD:
			return _after_reward()
		Step.AFTER_REWARD_THANKS:
			_msg_category = VillagerQuests.Msg.AFTER_REWARD_THANKS
			_talk_finish()
			step = Step.CHANGE_WAIT
			return _with_anim(_msg(), TalkStep.Handover.NPC_GIVES, _target.get("reward_item", &""))
		Step.RENEW_ERRAND_IRAI_END_GIVE_ITEM:
			step = Step.CHANGE_WAIT
			_msg_category = VillagerQuests.Msg.REQUEST_END
			_talk_finish()
			return _with_anim(_msg(), TalkStep.Handover.NPC_GIVES, _target.get("quest_item", &""))
		Step.RENEW_ERRAND_IRAI_END:
			_msg_category = VillagerQuests.Msg.REQUEST_END
			_talk_finish()
			return _msg()
		Step.CONTEST_OTHER_OR_NORMAL:
			return _contest_other_or_normal()
		Step.FINISH_LETTER:
			return _finish_letter()
		Step.FINISH:
			_talk_finish()
			step = Step.DONE
			return null
		Step.CHANGE_WAIT:
			## `aQMgr_talk_quest_change_wait`: message 0 — only reached after a message that
			## already closed the window.
			step = Step.DONE
			return null
	step = Step.DONE
	return null


## `aQMgr_actor_talk_select_talk` (a town villager; islanders aren't ported).
func _select_talk() -> TalkStep:
	_init_quest()
	_clear_target()
	var sel_entry: int = -1
	var target_flag: bool = true
	var r: int = _check_still_reward()
	if r != -1:
		_msg_category = VillagerQuests.Msg.AFTER_REWARD
		step = Step.AFTER_REWARD
	else:
		r = _check_own(true)
		if r != -1:
			var q: Dictionary = _entries[r]["quest"]
			var type: int = int(q["type"])
			var kind: int = int(q["kind"])
			if _check_finish(_entries[r]):
				_category_start = SELECT_TALK_MSG
				if type == VillagerQuests.Type.CONTEST and kind == VillagerQuests.CONTEST_LETTER:
					if _send_remail(q):
						step = Step.FINISH_LETTER
					else:
						step = Step.CONTEST_OTHER_OR_NORMAL
				elif type == VillagerQuests.Type.CONTEST and kind in [
					VillagerQuests.CONTEST_SOCCER, VillagerQuests.CONTEST_SNOWMAN, VillagerQuests.CONTEST_FLOWER
				]:
					talk.set_free_str(12, str(q.get("player_name", "")))
					step = Step.FIN_QUEST_START_NOT_HAND
				else:
					step = Step.FIN_QUEST_START
			else:
				if type == VillagerQuests.Type.ERRAND:
					step = Step.RENEW_ERRAND_OR_NORMAL
					sel_entry = r
					r = -1
				elif type == VillagerQuests.Type.CONTEST:
					if not VillagerQuests.limit_over(q, talk.now_minute):
						if int(q["progress"]) == 0:
							if bool(q["player"]):
								step = Step.NO_OR_NORMAL
								_clear_target()
								target_flag = false
							else:
								step = Step.RECONF_OR_NORMAL
						else:
							step = Step.RECONF_OR_NORMAL
					else:
						step = Step.NO_OR_NORMAL
						_clear_target()
						target_flag = false
						_entry_idx = r
						_talk_finish()
				_category_start = SELECT_TALK_MSG
		else:
			r = _check_own(false)
			if r != -1:
				var q: Dictionary = _entries[r]["quest"]
				if not VillagerQuests.limit_over(q, talk.now_minute):
					step = Step.RECONF_OR_NORMAL
					_category_start = SELECT_TALK_MSG
				else:
					if _is_open_errand(q):
						_expire_errand(r)
						target_flag = false
					step = Step.GIVEUP
					_msg_category = VillagerQuests.Msg.FAILURE_INIT
			else:
				r = _check_errand_from()
				if r != -1:
					var q: Dictionary = _entries[r]["quest"]
					if not VillagerQuests.limit_over(q, talk.now_minute):
						step = Step.ROOT_RECONF_OR_NORMAL
						_category_start = SELECT_TALK_MSG
					else:
						step = Step.GIVEUP
						_msg_category = VillagerQuests.Msg.FAILURE_INIT
						if _is_open_errand(q):
							_expire_errand(r)
							if int(q["kind"]) == VillagerQuests.ERRAND_REQUEST:
								_msg_category = VillagerQuests.Msg.NONE
								_category_start = ERRAND_FORGET_MSG
							target_flag = false
				elif talk.talk_info.quest_request(talk.slot):
					step = Step.NEW_QUEST_OR_NORMAL
					_category_start = SELECT_TALK_MSG
				else:
					step = Step.NO_OR_NORMAL
					_category_start = SELECT_TALK_MSG
					_clear_target()
					target_flag = false
	if target_flag:
		if r != -1:
			_entry_idx = r
			_set_target_from_entry()
			if step != Step.AFTER_REWARD:
				_target["inv_idx"] = _get_item_idx()
		else:
			r = _new_quest(sel_entry)
		if int(_target["info"]["type"]) != VillagerQuests.Type.NONE:
			_set_free_str(r)
		_entry_idx = r
	return _msg(_quest_choices())


## A timed-out errand whose item hasn't been picked up: forget it right away.
func _is_open_errand(q: Dictionary) -> bool:
	return int(q["type"]) == VillagerQuests.Type.ERRAND and int(q["kind"]) in [
		VillagerQuests.ERRAND_REQUEST, VillagerQuests.ERRAND_REQUEST_CONTINUE
	]


func _expire_errand(r: int) -> void:
	_entry_idx = r
	_set_target_from_entry()
	_target["inv_idx"] = _get_item_idx()
	_set_free_str(r)
	_target["free"] = {}
	_target["free_idx"] = -1
	_talk_finish()


## `aQMgr_actor_init_quest` + `aQMgr_actor_regist_quest_move`.
func _init_quest() -> void:
	talk.quests.sync_residents(talk.residents)
	talk.quests.move(talk.now_minute, talk.month, talk.day)
	_entries = talk.quests.registry(talk.inventory, talk.residents)
	_entry_idx = -1


## `aQMgr_talk_common_clear_talk_info` (target part).
func _clear_target() -> void:
	_target = {
		"info": VillagerQuests.new_base(),
		"from": &"",
		"to": &"",
		"inv_idx": -1,
		"quest_item": &"",
		"reward_kind": -1,
		"reward_item": &"",
		"pay": 0,
		"limit": 0,
		"set_data": [],
		"free_idx": -1,
		"free": {},
		"errand_type": VillagerQuests.ERRAND_TYPE_NONE,
		"flower_goal": 0,
	}


## `aQMgr_actor_check_still_reward`: a reward the player's pockets couldn't take last time.
func _check_still_reward() -> int:
	for i: int in _entries.size():
		var q: Dictionary = _entries[i]["quest"]
		if bool(q.get("give_reward", false)) and _entries[i]["to"] == _client() and _entry_has_player(i):
			return i
	return -1


func _entry_has_player(i: int) -> bool:
	var q: Dictionary = _entries[i]["quest"]
	if int(q["type"]) == VillagerQuests.Type.CONTEST:
		return bool(q.get("player", false))
	return true


## `aQMgr_actor_check_own_quest`.
func _check_own(to: bool) -> int:
	for i: int in _entries.size():
		if _entries[i]["to" if to else "from"] == _client():
			return i
	return -1


## `aQMgr_actor_check_errand_from`: a chain that started with this villager.
func _check_errand_from() -> int:
	for i: int in _entries.size():
		var q: Dictionary = _entries[i]["quest"]
		if int(q["type"]) == VillagerQuests.Type.ERRAND and int(q["kind"]) == VillagerQuests.ERRAND_REQUEST_CONTINUE:
			if (q["used_ids"] as Array)[0] == _client():
				return i
	return -1


## `aQMgr_actor_check_finish` with the contest `l_contest_check` procs.
func _check_finish(entry: Dictionary) -> bool:
	var q: Dictionary = entry["quest"]
	if int(q["type"]) != VillagerQuests.Type.CONTEST:
		return int(q["progress"]) == 0
	var progress: int = int(q["progress"])
	match int(q["kind"]):
		VillagerQuests.CONTEST_FRUIT:
			return progress == 1 and _pocket_of(q["requested"]) != -1
		VillagerQuests.CONTEST_SOCCER:
			return progress == 1
		VillagerQuests.CONTEST_SNOWMAN:
			return progress == 1 and bool(q["player"])
		VillagerQuests.CONTEST_FLOWER:
			return _check_flower(q)
		VillagerQuests.CONTEST_FISH:
			return progress == 1 and not bool(q["player"]) and _pocket_of_category(ItemData.Category.FISH) != -1
		VillagerQuests.CONTEST_INSECT:
			return progress == 1 and not bool(q["player"]) and _pocket_of_category(ItemData.Category.BUG) != -1
		VillagerQuests.CONTEST_LETTER:
			return progress == 1
	return false


## `aQMgr_actor_check_flower`: enough flowers by the house; a shortfall forgets who planted.
func _check_flower(q: Dictionary) -> bool:
	if int(q["progress"]) != 1:
		return false
	var seed_num: int = int(_home_counts().get("seed", -1))
	if seed_num < 0:
		return false
	if int(q["flowers_requested"]) <= seed_num:
		return true
	q["player"] = false
	q["player_name"] = ""
	return false


## `aQMgr_talk_common_regist_set_target`.
func _set_target_from_entry() -> void:
	var e: Dictionary = _entries[_entry_idx]
	var q: Dictionary = e["quest"]
	_target["info"]["type"] = int(q["type"])
	_target["info"]["kind"] = int(q["kind"])
	_target["set_data"] = VillagerQuests.set_data(int(q["type"]), int(q["kind"]))
	_target["quest_item"] = e["item"]
	_target["to"] = e["to"]
	_target["from"] = e["from"]


## `aQMgr_talk_common_get_item_idx`.
func _get_item_idx() -> int:
	if _entry_idx < 0 or _entry_idx >= _entries.size():
		return -1
	var e: Dictionary = _entries[_entry_idx]
	var q: Dictionary = e["quest"]
	match int(q["type"]):
		VillagerQuests.Type.DELIVERY:
			return int(e["idx"])
		VillagerQuests.Type.ERRAND:
			return int(q["pocket"])
		VillagerQuests.Type.CONTEST:
			match int(q["kind"]):
				VillagerQuests.CONTEST_FISH:
					return _pocket_of_category(ItemData.Category.FISH)
				VillagerQuests.CONTEST_INSECT:
					return _pocket_of_category(ItemData.Category.BUG)
				_:
					return _pocket_of(q["requested"])
	return -1


## `aQMgr_actor_new_quest`. Returns the regist index the quest came from (errand renewals).
func _new_quest(entry_idx: int) -> int:
	var quest: Dictionary = {}
	var stage: int = 0
	var exist: bool
	var sel: int = -1
	if entry_idx != -1:
		var e: Dictionary = _entries[entry_idx]
		quest = e["quest"]
		_target["info"]["type"] = int(quest["type"])
		var slot_idx: int = int(e["idx"])
		var next: int = Game.session.errand_next[slot_idx] if slot_idx >= 0 and slot_idx < Game.session.errand_next.size() else 0
		var next_type: int = 0
		if next == 0:
			next_type = talk.rand(2)
		elif next <= 2:
			next_type = next - 1
		_set_errand_next(slot_idx, next_type + 1)
		stage = 0 if next_type == 0 else int(quest["progress"]) - 1
		_target["info"]["kind"] = (
			VillagerQuests.ERRAND_REQUEST_FINAL if stage == 0 else VillagerQuests.ERRAND_REQUEST_CONTINUE
		)
		_target["free"] = quest
		_target["free_idx"] = slot_idx
		sel = entry_idx
		exist = true
	else:
		exist = _decide_quest()
	var result: int = NewQuest.ERROR
	if exist:
		_target["set_data"] = VillagerQuests.set_data(int(_target["info"]["type"]), int(_target["info"]["kind"]))
		result = _set_quest_data(quest)
		if result == NewQuest.SUCCESS:
			if entry_idx != -1:
				_target["from"] = _client()
				if stage != 0:
					_target["info"]["progress"] = stage
				_set_errand_next(int(_entries[entry_idx]["idx"]), 0)
		elif result == NewQuest.NO_SPACE:
			if int(_target["info"]["type"]) == VillagerQuests.Type.DELIVERY:
				talk.talk_info.set_client_quest(talk.slot, _target["info"])
			step = Step.FULL_ITEM_OR_NORMAL
		else:
			exist = false
	if not exist:
		if int(talk.talk_info.client_quest(talk.slot).get("type", VillagerQuests.Type.NONE)) != VillagerQuests.Type.NONE:
			step = Step.FULL_ITEM_OR_NORMAL
		elif int(_target["info"]["type"]) == VillagerQuests.Type.DELIVERY and (_target["set_data"] as Array).is_empty():
			step = Step.FULL_ITEM_OR_NORMAL
			_target["set_data"] = VillagerQuests.set_data(int(_target["info"]["type"]), int(_target["info"]["kind"]))
		else:
			step = Step.NO_OR_NORMAL
			talk.talk_info.set_quest_request_off(talk.slot, talk.looks)
		_target["info"] = VillagerQuests.new_base()
		_target["free"] = {}
		_target["free_idx"] = -1
	return sel


func _set_errand_next(idx: int, value: int) -> void:
	if idx >= 0 and idx < Game.session.errand_next.size():
		Game.session.errand_next[idx] = value


## `aQMgr_actor_decide_quest`: re-offer what was turned down, else a 3-in-4 chance of a new
## request that can happen right now.
func _decide_quest() -> bool:
	var client_info: Dictionary = talk.talk_info.client_quest(talk.slot)
	if int(client_info.get("type", VillagerQuests.Type.NONE)) != VillagerQuests.Type.NONE:
		VillagerQuests.copy_base(_target["info"], client_info)
		_get_free_quest(int(_target["info"]["type"]))
		if not (_target["free"] as Dictionary).is_empty():
			return true
		if int(_target["info"]["type"]) == VillagerQuests.Type.DELIVERY:
			talk.talk_info.set_client_quest(talk.slot, _target["info"])
		return false
	if talk.rand(4) == 0:
		return false
	var fj: bool = talk.first_job_active()
	var types: Array = FJ_KINDS if fj else QST_KINDS
	var type: int = talk.rand(types.size())
	var kinds: Array = types[type]
	var kind: int = int(kinds[talk.rand(kinds.size())])
	if not _check_occur(type, kind):
		return false
	_target["info"]["type"] = type
	_target["info"]["kind"] = kind
	_get_free_quest(type)
	if not (_target["free"] as Dictionary).is_empty():
		return true
	if type == VillagerQuests.Type.DELIVERY:
		talk.talk_info.set_client_quest(talk.slot, _target["info"])
	return false


## `aQMgr_actor_check_occur`: contests one at a time per town and by season; deliveries to
## other towns need a remembered foreigner / departed villager, which a single-town save
## never has (`stored_anm_id` / `last_removed_animal_id` stay empty).
func _check_occur(type: int, kind: int) -> bool:
	if type == VillagerQuests.Type.CONTEST:
		if talk.quests.occured_contest_idx(kind) != -1:
			return false
		match kind:
			VillagerQuests.CONTEST_SNOWMAN:
				return (
					(talk.month == 1 or (talk.month == 2 and talk.day <= 17) or (talk.month == 12 and talk.day >= 25))
					and Clock.hour >= 8 and Clock.hour <= 16
				)
			VillagerQuests.CONTEST_FLOWER:
				if not ((talk.month == 2 and talk.day >= 25) or (talk.month >= 3 and talk.month <= 8)):
					return false
				var counts: Dictionary = _home_counts()
				return int(counts.get("null", -1)) >= 4 and int(counts.get("flower", -1)) <= 20
			VillagerQuests.CONTEST_INSECT:
				return (talk.month >= 3 and talk.month <= 10) or (talk.month == 11 and talk.day <= 28)
		return true
	if type == VillagerQuests.Type.DELIVERY:
		return kind != VillagerQuests.DELIVERY_FOREIGN and kind != VillagerQuests.DELIVERY_REMOVE
	return true


## `aQMgr_actor_get_free_quest_p`.
func _get_free_quest(type: int) -> void:
	_target["free"] = {}
	_target["free_idx"] = -1
	match type:
		VillagerQuests.Type.DELIVERY:
			for i: int in talk.quests.deliveries.size():
				if VillagerQuests.is_free(talk.quests.deliveries[i]) and _pocket_empty(i):
					_target["inv_idx"] = i
					_target["free"] = talk.quests.deliveries[i]
					_target["free_idx"] = i
					return
		VillagerQuests.Type.ERRAND:
			for i: int in talk.quests.errands.size():
				if VillagerQuests.is_free(talk.quests.errands[i]):
					_target["free"] = talk.quests.errands[i]
					_target["free_idx"] = i
					return
		VillagerQuests.Type.CONTEST:
			if talk.slot >= 0 and talk.slot < talk.quests.contests.size() and VillagerQuests.is_free(talk.quests.contests[talk.slot]):
				_target["free"] = talk.quests.contests[talk.slot]
				_target["free_idx"] = talk.slot


## `aQMgr_actor_set_quest_data`: who it's for, what item, the pocket for it, the deadline.
func _set_quest_data(quest: Dictionary) -> int:
	var data: Array = _target["set_data"]
	if data.is_empty():
		return NewQuest.ERROR
	_target["from"] = _client()
	match int(data[0]):
		VillagerQuests.Target.RANDOM:
			var to: StringName = other_resident([_client()], _home_block(), true)
			if to == &"":
				return NewQuest.ERROR
			_target["to"] = to
		VillagerQuests.Target.RANDOM_EXCLUDED:
			var exclude: Array[StringName] = [&"", &"", &"", &""]
			if not quest.is_empty():
				for i: int in VillagerQuests.CHAIN_ANIMAL_NUM:
					exclude[i] = (quest["used_ids"] as Array)[i]
			exclude[VillagerQuests.CHAIN_ANIMAL_NUM] = _client()
			var to: StringName = other_resident(exclude, _home_block(), true)
			if to == &"":
				return NewQuest.ERROR
			_target["to"] = to
			_target["errand_type"] = VillagerQuests.ERRAND_TYPE_CHAIN
		VillagerQuests.Target.ORIGINAL_TARGET:
			_target["to"] = (quest["used_ids"] as Array)[0] if not quest.is_empty() else _client()
		VillagerQuests.Target.FOREIGN:
			return NewQuest.NO_FOREIGN_ID
		VillagerQuests.Target.LAST_REMOVE:
			return NewQuest.NO_REMOVE_ANIMAL_ID
		VillagerQuests.Target.CLIENT:
			_target["to"] = _client()
	match int(data[4]):
		VillagerQuests.ItemSrc.RANDOM:
			_target["quest_item"] = VillagerQuests.QUEST_ITEMS[talk.rand(VillagerQuests.QUEST_ITEMS.size())]
		VillagerQuests.ItemSrc.FRUIT:
			_target["quest_item"] = VillagerQuests.other_fruit(talk.context.rng)
		VillagerQuests.ItemSrc.CLOTH:
			_target["quest_item"] = _decide_cloth(talk.cloth_at_start)
		VillagerQuests.ItemSrc.CURRENT_ITEM:
			_target["quest_item"] = quest["item"] if not quest.is_empty() else FirstJob.DEFAULT_CLOTH_ID
		VillagerQuests.ItemSrc.NONE:
			_target["quest_item"] = &""
		_:
			return NewQuest.ERROR
	if bool(data[3]):
		var idx: int = talk.first_empty_pocket()
		if idx == -1:
			_target["inv_idx"] = -1
			return NewQuest.NO_SPACE
		_target["inv_idx"] = idx
	else:
		_target["inv_idx"] = -1
	var days: int = int(data[1])
	if days != 0:
		_target["limit"] = talk.now_minute + days * 1440
		_target["info"]["limit_on"] = true
	else:
		_target["info"]["limit_on"] = false
	_target["info"]["progress"] = int(data[2])
	if int(_target["info"]["type"]) == VillagerQuests.Type.CONTEST and int(_target["info"]["kind"]) == VillagerQuests.CONTEST_FLOWER:
		## `aQMgr_actor_set_contest_work_data`: three more than grow there now.
		_target["flower_goal"] = int(_home_counts().get("seed", -1)) + VillagerQuests.FLOWER_GOAL_NUM
	return NewQuest.SUCCESS


## `aQMgr_actor_decide_cloth`: shop clothing other than `exclude`.
func _decide_cloth(exclude: StringName) -> StringName:
	var pool: Array[StringName] = []
	for id: StringName in ShopGoods.category_pool(ItemData.Category.CLOTH):
		if id != exclude:
			pool.append(id)
	if pool.is_empty():
		return FirstJob.DEFAULT_CLOTH_ID
	return pool[talk.rand(pool.size())]


## `aQMgr_actor_set_quest_info`: write the quest into its save slot, and the parcel into the
## pocket (flagged as a quest item).
func _set_quest_info() -> void:
	var free: Dictionary = _target["free"]
	if free.is_empty():
		return
	var info: Dictionary = _target["info"]
	var type: int = int(info["type"])
	VillagerQuests.copy_base(free, info)
	free["limit"] = int(_target["limit"])
	match type:
		VillagerQuests.Type.DELIVERY:
			free["from"] = _client()
			free["to"] = _target["to"]
		VillagerQuests.Type.ERRAND:
			free["from"] = _client()
			free["to"] = _target["to"]
			free["item"] = _target["quest_item"]
			free["pocket"] = int(_target["inv_idx"])
			free["errand_type"] = int(_target["errand_type"])
			if int(_target["errand_type"]) == VillagerQuests.ERRAND_TYPE_CHAIN:
				var used: Array = free["used_ids"]
				if int(info["kind"]) == VillagerQuests.ERRAND_REQUEST:
					free["used_ids"] = [&"", &"", &""]
					free["used_num"] = 0
					used = free["used_ids"]
				for i: int in used.size():
					if used[i] == &"":
						used[i] = _client()
						break
				free["used_num"] = int(free["used_num"]) + 1
		VillagerQuests.Type.CONTEST:
			free["owner"] = _client()
			free["requested"] = _target["quest_item"]
			if int(info["kind"]) == VillagerQuests.CONTEST_FLOWER:
				free["flowers_requested"] = int(_target["flower_goal"])
			elif int(info["kind"]) == VillagerQuests.CONTEST_LETTER:
				free["letter_score"] = 0
				free["letter_present"] = &""
	var idx: int = int(_target["inv_idx"])
	if idx != -1 and talk.inventory != null and _target["quest_item"] != &"":
		var s: InventorySlot = talk.inventory.slot_at(idx)
		if s != null:
			s.set_stack(_target["quest_item"], 1)
			s.item.condition = InventoryItem.Condition.QUEST
			talk.inventory.changed.emit()


## `aQMgr_actor_talk_finish`: a finished quest clears; a new one registers.
func _talk_finish() -> void:
	if _entry_idx >= 0 and _entry_idx < _entries.size():
		var q: Dictionary = _entries[_entry_idx]["quest"]
		match int(q["type"]):
			VillagerQuests.Type.DELIVERY:
				VillagerQuests.clear_delivery(q)
			VillagerQuests.Type.ERRAND:
				VillagerQuests.clear_errand(q)
			VillagerQuests.Type.CONTEST:
				VillagerQuests.clear_contest(q)
		_entries.clear()
		_entry_idx = -1


## `aQMgr_actor_talk_new_quest_or_normal`: "Need any help?" → the request.
func _new_quest_or_normal() -> TalkStep:
	if _talk_action != 0:
		return _change_normal_or_hint()
	_finish_first_job_open_quest()
	step = Step.OCCUR_QUEST
	_msg_category = VillagerQuests.Msg.REQUEST_INIT
	if int(_target["info"]["type"]) == VillagerQuests.Type.CONTEST:
		## Contests start as soon as they're asked for — even if turned down.
		_set_quest_info()
		talk.talk_info.clear_client_quest(talk.slot)
	return _msg(_start_choices())


## `aQMgr_actor_talk_occur_quest`: accept (−), decline (−3 friendship), or cancel.
func _occur_quest() -> TalkStep:
	if _talk_action == 1:
		talk.talk_info.set_client_quest(talk.slot, _target["info"])
		_msg_category = VillagerQuests.Msg.REQUEST_REJECT
		if talk.state != null:
			talk.state.add_friendship(-3)
		return _msg()
	if _talk_action == 2:
		return cancel_msg(CANCEL_MSG)
	_msg_category = VillagerQuests.Msg.REQUEST_END
	_set_quest_info()
	talk.talk_info.clear_client_quest(talk.slot)
	var free: Dictionary = _target["free"]
	var type: int = int(free.get("type", VillagerQuests.Type.NONE))
	if _talk_action == 0 and (type != VillagerQuests.Type.ERRAND or int(free.get("progress", 0)) == 0):
		## `aQMgr_talk_quest_wait_talk`: hand the parcel over, then "please do your best".
		_msg()
		_msg_category = VillagerQuests.Msg.REQUEST_END
		_talk_finish()
		step = Step.CHANGE_WAIT
		var out: TalkStep = _msg()
		if int(_target["inv_idx"]) != -1:
			out = _with_anim(out, TalkStep.Handover.NPC_GIVES, _target["quest_item"])
		return out
	if _talk_action == 0:
		step = Step.FINISH
	return _msg()


## `aQMgr_actor_talk_renew_errand_or_normal`: "I'm picking up!" → the chain moves on.
func _renew_errand_or_normal() -> TalkStep:
	if _talk_action != 0:
		return _change_normal_or_hint()
	_msg_category = VillagerQuests.Msg.REQUEST_INIT
	_set_quest_info()
	talk.talk_info.clear_client_quest(talk.slot)
	_entries.clear()
	_entry_idx = -1
	var free: Dictionary = _target["free"]
	if int(free.get("type", VillagerQuests.Type.NONE)) == VillagerQuests.Type.ERRAND and int(free.get("progress", 0)) == 0:
		step = Step.RENEW_ERRAND_IRAI_END_GIVE_ITEM
	else:
		step = Step.RENEW_ERRAND_IRAI_END
	return _msg(_start_choices())


## `aQMgr_actor_talk_giveup`: after "give it back", open the pockets on the parcel.
func _giveup() -> TalkStep:
	var idx: int = int(_target.get("inv_idx", -1))
	if idx == -1:
		step = Step.DONE
		return null
	step = Step.GIVEUP_ITEM
	return TalkStep.open_pockets("quest", idx)


## `aQMgr_talk_quest_open_menu`: fish / bug contests take any fish / bug; the rest only the
## quest item.
func _open_menu() -> TalkStep:
	step = Step.GET_ITEM
	var info: Dictionary = _target["info"]
	var mode: String = "quest"
	if int(info["type"]) == VillagerQuests.Type.CONTEST:
		if int(info["kind"]) == VillagerQuests.CONTEST_FISH:
			mode = "fish"
		elif int(info["kind"]) == VillagerQuests.CONTEST_INSECT:
			mode = "insect"
	return TalkStep.open_pockets(mode, int(_target["inv_idx"]))


## The pockets closed on a quest hand-over (`aQMgr_talk_quest_get_item` /
## `aQMgr_talk_quest_giveup_item`). `item` is what was handed over, or `&""`.
func hand_result(item: StringName, pocket: int = -1) -> TalkStep:
	var handed: bool = item != &""
	if handed:
		_take_from_pocket(item, pocket if pocket >= 0 else int(_target.get("inv_idx", -1)))
	if step == Step.GIVEUP_ITEM:
		if not handed:
			_category_start = THIEF_MSG
			step = Step.GIVEUP
			return _msg()
		_msg_category = VillagerQuests.Msg.FAILURE_END
		var data: Array = _target["set_data"]
		if not data.is_empty() and talk.state != null:
			match VillagerQuests.set_msg(data, VillagerQuests.Msg.FAILURE_END):
				0x2B8:
					talk.state.add_friendship(-5)
				0x452:
					talk.state.add_friendship(-2)
				0x2CA:
					talk.state.add_friendship(-1)
		var out: TalkStep = _msg()
		## `aQMgr_talk_quest_giveup_npc_item`.
		_talk_finish()
		step = Step.CHANGE_WAIT
		return _with_anim(out, TalkStep.Handover.PLAYER_GIVES, item)
	## GET_ITEM.
	if not handed:
		_category_start = NO_REWARD_MSG
		step = Step.CHANGE_WAIT
		if talk.state != null:
			talk.state.add_friendship(-1)
		return _msg()
	_msg_category = VillagerQuests.Msg.COMPLETE_INIT
	step = Step.FIN_QUEST_REWARD
	var data_item: ItemData = ItemCatalog.get_item(item)
	talk.set_free_str(2, _article_name(item))
	if data_item != null and data_item.category == ItemData.Category.CLOTH and talk.state != null:
		## `Common_Set(npc_chg_cloth, …)`: the villager changes into what they were given.
		talk.state.cloth_id = item
	return _with_anim(_msg(), TalkStep.Handover.PLAYER_GIVES, item)


## `aQMgr_actor_talk_fin_quest_reward`.
func _fin_quest_reward() -> TalkStep:
	var q: Dictionary = _entries[_entry_idx]["quest"] if _entry_idx >= 0 and _entry_idx < _entries.size() else {}
	_set_reward()
	if _hand_reward():
		_set_free_str_reward()
		if not q.is_empty() and int(q["type"]) == VillagerQuests.Type.CONTEST:
			var kind: int = mini(int(q["kind"]), VillagerQuests.CONTEST_LETTER)
			_category_start = int((CONTEST_REWARD_MSG[kind] as Array)[int(_target["reward_kind"])])
		else:
			_category_start = REWARD_MSG[int(_target["reward_kind"])]
		step = Step.FIN_QUEST_THANKS
		if talk.state != null:
			talk.state.add_friendship(3)
	else:
		_msg_category = VillagerQuests.Msg.REWARD_FULL_ITEM
		if not q.is_empty():
			q["give_reward"] = true
		_entry_idx = -1
		step = Step.CHANGE_WAIT
	if not q.is_empty() and int(q["type"]) == VillagerQuests.Type.CONTEST:
		if int(q["progress"]) != 0:
			q["progress"] = int(q["progress"]) - 1
			q["limit"] = int(q["limit"]) + 3 * 1440
			q["player"] = true
			q["player_name"] = talk.context.player_name if talk.context != null else ""
		_entry_idx = -1
	_talk_finish()
	return _msg()


## `aQMgr_actor_talk_after_reward`: the reward that didn't fit last time.
func _after_reward() -> TalkStep:
	var q: Dictionary = _entries[_entry_idx]["quest"] if _entry_idx >= 0 and _entry_idx < _entries.size() else {}
	_set_reward()
	if _hand_reward():
		_set_free_str_reward()
		var kind: int = int(_target["reward_kind"])
		_category_start = AFTER_REWARD_MSG[kind]
		if not q.is_empty() and int(q["type"]) == VillagerQuests.Type.CONTEST:
			var ck: int = int(q["kind"])
			if ck >= VillagerQuests.CONTEST_SOCCER and ck <= VillagerQuests.CONTEST_FLOWER:
				_category_start = int((AFTER_CONTEST_SWAP[ck - 1] as Array)[kind])
		step = Step.AFTER_REWARD_THANKS
	else:
		_msg_category = VillagerQuests.Msg.REWARD_FULL_ITEM2
		step = Step.CHANGE_WAIT
	return _msg()


## `aQMgr_talk_quest_contest_hoka_or_normal`.
func _contest_other_or_normal() -> TalkStep:
	if _talk_action != 0:
		return _change_normal_or_hint()
	var q: Dictionary = _entries[_entry_idx]["quest"]
	_finish_first_job_open_quest()
	_target["free"] = {}
	talk.set_free_str(12, str(q.get("player_name", "")))
	if int(q["kind"]) == VillagerQuests.CONTEST_LETTER and bool(q["player"]):
		_category_start = LETTER_FULL_MSG
	else:
		_category_start = _contest_other_msg(q)
		if int(q["kind"]) != VillagerQuests.CONTEST_LETTER:
			_talk_finish()
	step = Step.CHANGE_WAIT
	return _msg()


func _contest_other_msg(q: Dictionary) -> int:
	var kind: int = int(q["kind"])
	if kind == VillagerQuests.CONTEST_FLOWER and int(q["flowers_requested"]) > int(_home_counts().get("seed", -1)):
		return FLOWER_SHORT_MSG
	return CONTEST_OTHER_MSG[clampi(kind, 0, CONTEST_OTHER_MSG.size() - 1)]


## `aQMgr_actor_talk_finish_letter`: the reply is in the mailbox.
func _finish_letter() -> TalkStep:
	var q: Dictionary = _entries[_entry_idx]["quest"]
	talk.set_free_str(12, str(q.get("player_name", "")))
	_category_start = LETTER_THANKS_MSG if bool(q["player"]) else LETTER_OTHER_MSG
	var out: TalkStep = _msg()
	step = Step.CHANGE_WAIT
	_target["free"] = {}
	_talk_finish()
	return out


## `mQst_SendRemail`.
func _send_remail(q: Dictionary) -> bool:
	if not bool(q.get("player", false)) or not talk.send_mail.is_valid():
		return false
	var mail: MailData = VillagerQuests.letter_reply(
		talk.villager, int(q["letter_score"]), q["letter_present"] as StringName,
		talk.context.player_name if talk.context != null else ""
	)
	if mail == null:
		return false
	return bool(talk.send_mail.call(mail))


## `aQMgr_talk_quest_finish_firstjob_open_quest`: during the job's "go ask for work" chore,
## asking a villager for work finishes it.
func _finish_first_job_open_quest() -> void:
	var job: FirstJob = Game.first_job
	if job.kind == FirstJob.Kind.OPEN and job.progress == FirstJob.PROGRESS_ACTIVE:
		job.mark_open_finished()


## `aQMgr_actor_set_reward`.
func _set_reward() -> void:
	var percents: Array
	var base_pay: int
	if int(_target["info"]["type"]) == VillagerQuests.Type.ERRAND and _entry_idx >= 0 and _entry_idx < _entries.size():
		var r: Dictionary = VillagerQuests.errand_reward(int(_entries[_entry_idx]["quest"].get("used_num", 0)))
		percents = r["percents"]
		base_pay = int(r["pay"])
	else:
		var data: Array = _target["set_data"]
		percents = data[5] if not data.is_empty() else [0, 0, 0, 0, 0, 0, 0, 0]
		base_pay = int(data[6]) if not data.is_empty() else 0
	var table := PackedInt32Array()
	table.resize(100)
	table.fill(0)
	var j: int = 0
	for i: int in percents.size():
		for _p: int in int(percents[i]):
			if j >= 100:
				break
			table[j] = i
			j += 1
	var kind: int = table[talk.rand(100)]
	_target["reward_kind"] = kind
	match kind:
		VillagerQuests.Reward.MONEY:
			_target["pay"] = VillagerQuests.pay(base_pay, talk.money_power, talk.context.rng)
			_target["reward_item"] = &"money_1000"
		VillagerQuests.Reward.WORN_CLOTH:
			if talk.state != null and talk.state.cloth_design >= 0:
				## `RSV_CLOTH` (an Able design): some other shirt instead.
				_target["reward_item"] = _decide_cloth(Game.resident.cloth_id)
				_target["reward_kind"] = VillagerQuests.Reward.CLOTH
			else:
				_target["reward_item"] = talk.cloth_at_start
		_:
			_target["reward_item"] = _goods_for_reward(kind)


## `mQst_GetGoods_common`: furniture is 1-in-10 something from the villager's own room.
func _goods_for_reward(kind: int) -> StringName:
	match kind:
		VillagerQuests.Reward.FTR:
			if talk.rand(10) == 0:
				var own: StringName = npc_furniture(talk.villager.id if talk.villager != null else &"", talk.context.rng)
				if own != &"":
					return own
			return _pick_pool(ShopGoods.furniture_pool())
		VillagerQuests.Reward.STATIONERY:
			return ShopGoods.PAPER
		VillagerQuests.Reward.CLOTH:
			return _pick_pool(ShopGoods.category_pool(ItemData.Category.CLOTH))
		VillagerQuests.Reward.CARPET:
			return _pick_pool(ShopGoods.category_pool(ItemData.Category.FLOOR))
		VillagerQuests.Reward.WALLPAPER:
			return _pick_pool(ShopGoods.category_pool(ItemData.Category.WALL))
	return &""


func _pick_pool(pool: Array[StringName]) -> StringName:
	return pool[talk.rand(pool.size())] if not pool.is_empty() else &""


## `mNpc_GetNpcFurniture`: a random piece from the villager's room.
static func npc_furniture(villager_id: StringName, rng: RandomNumberGenerator) -> StringName:
	var placements: Array = InteriorCatalogNpc._layout(villager_id).get("placements", []) as Array
	var ids: Array[StringName] = []
	for raw: Variant in placements:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var visual := StringName(str((raw as Dictionary).get("visual_id", "")))
		var data: FurnitureData = ItemCatalog.furniture_for_visual(visual) if visual != &"" else null
		if data != null:
			ids.append(data.id)
	if ids.is_empty():
		return &""
	return ids[rng.randi_range(0, ids.size() - 1)]


## `aQMgr_actor_hand_reward`: bells into the wallet (30,000-bell bags past the cap), goods
## into the parcel's pocket or the first free one.
func _hand_reward() -> bool:
	if talk.inventory == null:
		return false
	var kind: int = int(_target["reward_kind"])
	var idx: int = int(_target.get("inv_idx", -1))
	if kind == VillagerQuests.Reward.MONEY:
		var money: int = talk.inventory.wallet + int(_target["pay"])
		if money <= Inventory.WALLET_MAX:
			talk.inventory.set_wallet(money)
			talk.inventory.changed.emit()
			return true
		if money > Inventory.WALLET_MAX + _empty_pockets() * 30000:
			return false
		if idx != -1 and _pocket_empty(idx):
			talk.inventory.slot_at(idx).set_stack(talk.MONEY_30000, 1)
			money -= 30000
		while money > Inventory.WALLET_MAX:
			var empty: int = talk.first_empty_pocket()
			if empty == -1:
				money = Inventory.WALLET_MAX
				break
			talk.inventory.slot_at(empty).set_stack(talk.MONEY_30000, 1)
			money -= 30000
		talk.inventory.set_wallet(money)
		talk.inventory.changed.emit()
		return true
	if kind == -1 or _target["reward_item"] == &"":
		return false
	if idx == -1 or not _pocket_empty(idx):
		idx = talk.first_empty_pocket()
	if idx == -1:
		return false
	talk.inventory.slot_at(idx).set_stack(_target["reward_item"], 1)
	talk.inventory.changed.emit()
	return true


## `aQMgr_actor_set_free_str_reward`.
func _set_free_str_reward() -> void:
	if int(_target["reward_kind"]) == VillagerQuests.Reward.MONEY:
		talk.set_free_str(9, str(int(_target["pay"])))
	else:
		talk.set_item_text(0, _article_name(_target["reward_item"]))


## `aQMgr_actor_set_free_str`: FREE0 who asked, FREE1 who it's for, FREE2 the item,
## FREE3/4 their towns, FREE5 who started the errand chain.
func _set_free_str(entry_idx: int) -> void:
	talk.set_free_str(0, _name_of(_target["from"]))
	if _target["to"] != &"":
		talk.set_free_str(1, _name_of(_target["to"]))
		talk.set_free_str(3, talk.context.town_name if talk.context != null else "")
	if _target["quest_item"] != &"":
		talk.set_free_str(2, _article_name(_target["quest_item"]))
	talk.set_free_str(4, talk.context.town_name if talk.context != null else "")
	if entry_idx >= 0 and entry_idx < _entries.size():
		var q: Dictionary = _entries[entry_idx]["quest"]
		if int(q["type"]) == VillagerQuests.Type.ERRAND:
			var first: StringName = (q["used_ids"] as Array)[0]
			if first != &"":
				talk.set_free_str(5, _name_of(first))


func _name_of(id: StringName) -> String:
	var v: VillagerData = VillagerCatalog.get_villager(id)
	return v.display_name if v != null else ""


## Item strings carry their article (`mIN_get_item_article`).
func _article_name(item_id: StringName) -> String:
	var data: ItemData = ItemCatalog.get_item(item_id)
	var name: String = data.display_name if data != null else String(item_id)
	if data is FurnitureData or name == "":
		return name
	return PoliceTalk.with_article(name)


## `aQMgr_talk_quest_select_get_choice` for the step `_select_talk` landed on.
func _quest_choices() -> Array[String]:
	var info: Dictionary = _target.get("info", {})
	var type: int = int(info.get("type", VillagerQuests.Type.NONE))
	var kind: int = int(info.get("kind", 0))
	var first: int
	var second: int
	match step:
		Step.RENEW_ERRAND_OR_NORMAL:
			first = CHOICE_PICKUP
			second = CHOICE_TALK
		Step.FIN_QUEST_START:
			first = CHOICE_DELIVERY
			if type == VillagerQuests.Type.DELIVERY and kind in [VillagerQuests.DELIVERY_FOREIGN, VillagerQuests.DELIVERY_REMOVE]:
				first = CHOICE_FORGOT
			elif type == VillagerQuests.Type.ERRAND and kind != VillagerQuests.ERRAND_REQUEST_FINAL:
				first = CHOICE_PICKUP
			elif type == VillagerQuests.Type.CONTEST:
				match kind:
					VillagerQuests.CONTEST_FRUIT:
						first = CHOICE_FRUIT
					VillagerQuests.CONTEST_FISH:
						first = CHOICE_FISH
					VillagerQuests.CONTEST_INSECT:
						first = CHOICE_BUG
			second = _choice_rand(CHOICE_TALK, 10)
		Step.FIN_QUEST_START_NOT_HAND:
			first = CHOICE_BALL
			if kind == VillagerQuests.CONTEST_SNOWMAN:
				first = CHOICE_SNOWMAN
			elif kind == VillagerQuests.CONTEST_FLOWER:
				first = CHOICE_FLOWERS
			second = CHOICE_UM
		Step.FULL_ITEM_OR_NORMAL:
			first = CHOICE_PICKUP if type == VillagerQuests.Type.ERRAND else _choice_rand(CHOICE_HELP, 10)
			second = _choice_rand(CHOICE_TALK, 10)
		_:
			first = _choice_rand(CHOICE_HELP, 10)
			second = _choice_rand(CHOICE_TALK, 10)
	return _labels([first, second, _choice_rand(CHOICE_NEVERMIND, 5)])


## `aQMgr_talk_quest_start_choice`.
func _start_choices() -> Array[String]:
	return _labels([_choice_rand(CHOICE_ACCEPT, 10), _choice_rand(CHOICE_REJECT, 10)])


func _choice_rand(start: int, count: int) -> int:
	return start + talk.rand(count)


func _labels(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in ids:
		out.append(DialogueCatalog.choice_label(int(id)))
	return out


## `aQMgr_talk_quest_set_cancel_msg_com`.
func cancel_msg(base: int) -> TalkStep:
	_msg_category = VillagerQuests.Msg.NONE
	_category_start = base
	step = Step.CHANGE_WAIT
	return _msg()


## `aQMgr_talk_common_set_msg_no`: a set data message or a fixed start, plus looks × 3 and
## 0–2 (except 0 and 15).
func _msg(choices: Array[String] = []) -> TalkStep:
	if _msg_category != VillagerQuests.Msg.NONE:
		_category_start = VillagerQuests.set_msg(_target.get("set_data", []), _msg_category)
	var base: int = _category_start
	var msg_no: int = base
	if base != 15 and base != 0:
		msg_no = talk.my_msg(base)
	_msg_category = VillagerQuests.Msg.NONE
	_category_start = 0
	return TalkStep.show(msg_no, choices)


func _with_anim(out: TalkStep, kind: TalkStep.Handover, item: Variant) -> TalkStep:
	var id := StringName(str(item))
	if id != &"":
		out.handover = kind
		out.item = id
	return out


func _client() -> StringName:
	return talk.villager.id if talk.villager != null else &""


func _home_block() -> Vector2i:
	if talk.residents == null or talk.slot < 0:
		return Vector2i(-1, -1)
	var home: Vector2i = talk.residents.home_of(talk.slot)
	if home == TownResidents.NO_HOME:
		return Vector2i(-1, -1)
	return VillagerWalk.block_from_cell(home)


func _home_counts() -> Dictionary:
	if talk.field_counts.is_valid():
		return talk.field_counts.call(_home_block()) as Dictionary
	return {}


## `mNpc_GetOtherAnimalPersonalIDOtherBlock`: a random resident not in `exclude` and (with
## `check_block`) not living in `block`. Kept as the decomp walks it, including neighbours in
## the block eating into the random index.
func other_resident(exclude: Array[StringName], block: Vector2i, check_block: bool) -> StringName:
	if talk.residents == null:
		return &""
	if block.x < 0:
		check_block = false
	var count: int = exclude.size()
	var ids: int = count
	var live: Array[bool] = []
	for i: int in count:
		live.append(exclude[i] != &"")
		if not live[i]:
			ids -= 1
	var in_block: int = 0
	var blocks: Array[Vector2i] = []
	for j: int in TownResidents.ANIMAL_NUM_MAX:
		var b := Vector2i(-2, -2)
		if not talk.residents.is_free(j) and talk.residents.home_of(j) != TownResidents.NO_HOME:
			b = VillagerWalk.block_from_cell(talk.residents.home_of(j))
		blocks.append(b)
	if check_block:
		for j: int in TownResidents.ANIMAL_NUM_MAX:
			if blocks[j] != block:
				continue
			in_block += 1
			var id: StringName = talk.residents.slots[j].get("id", &"") as StringName
			for i: int in count:
				if live[i] and exclude[i] == id:
					ids -= 1
					live[i] = false
					break
	var npc_max: int = talk.residents.animal_num()
	if npc_max <= ids + in_block or count >= TownResidents.ANIMAL_NUM_MAX:
		return &""
	var pick: int = talk.rand(npc_max - ids - in_block)
	for j: int in TownResidents.ANIMAL_NUM_MAX:
		if talk.residents.is_free(j):
			continue
		var id: StringName = talk.residents.slots[j]["id"] as StringName
		var other: int = 0
		for i: int in count:
			if live[i] and exclude[i] != id:
				other += 1
		var valid: bool = true
		if other != ids:
			valid = false
		elif check_block and blocks[j] == block:
			if pick > 0:
				pick -= 1
			valid = false
		if valid:
			if pick == 0:
				return id
			pick -= 1
	return &""


func _pocket_empty(i: int) -> bool:
	if talk.inventory == null:
		return false
	var s: InventorySlot = talk.inventory.slot_at(i)
	return s != null and s.is_empty()


func _empty_pockets() -> int:
	var n: int = 0
	for i: int in Inventory.POCKET_SLOTS:
		if _pocket_empty(i):
			n += 1
	return n


## `mPr_GetPossessionItemIdx`.
func _pocket_of(item_id: StringName) -> int:
	if talk.inventory == null or item_id == &"":
		return -1
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = talk.inventory.slot_at(i)
		if s != null and not s.is_empty() and s.item.item_id == item_id:
			return i
	return -1


## `mPr_GetPossessionItemIdxItem1Category`.
func _pocket_of_category(category: int) -> int:
	if talk.inventory == null:
		return -1
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = talk.inventory.slot_at(i)
		if s == null or s.is_empty():
			continue
		var data: ItemData = ItemCatalog.get_item(s.item.item_id)
		if data != null and data.category == category:
			return i
	return -1


## The hand-over puts the item away (`mSM_IV_ITEM_PUT_AWAY`).
func _take_from_pocket(item: StringName, pocket: int) -> void:
	if talk.inventory == null:
		return
	var idx: int = pocket
	var s: InventorySlot = talk.inventory.slot_at(idx) if idx >= 0 else null
	if s == null or s.is_empty() or s.item.item_id != item:
		idx = _pocket_of(item)
		s = talk.inventory.slot_at(idx) if idx >= 0 else null
	if s == null or s.is_empty():
		return
	if s.item.count > 1:
		s.item.count -= 1
	else:
		s.clear()
	talk.inventory.changed.emit()
