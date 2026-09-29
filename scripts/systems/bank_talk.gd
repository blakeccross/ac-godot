class_name BankTalk
extends RefCounted

## Script behind a disc-message conversation (`msg_*` banks). The original NPCs run their
## talk as a small state machine over `mMsg_*` / `mChoice_*` / `mDemo_*_OrderValue`; this is
## that state machine's shape for `DialogueRunner`:
##
## - `start_msg()` — the first message (`mDemo_Set_msg_num` in the talk request).
## - `entered(msg_no)` — a new message started (`mMsg_Get_msg_num`); set free strings here.
## - `picked(msg_no, index)` — a choice inside a message was taken (`mChoice_Get_ChoseNum`).
##   Return a message number to go there instead (`mMsg_Set_continue_msg_num`), or -1 to
##   follow the message's own branch.
## - `next_step()` — a message ended on `MSGCONTINUE` with nowhere to go: return
##   `{"msg": n}` to continue, `{"anim": {...}}` / `{"hand": {...}}` for a demo, or `{}`.
## - `npc_order(target, slot, value)` — `mDemo_ORDER_NPC0..2` values the messages set.
## - `finish()` — the talk closed.
##
## `VillagerTalkManager` (the quest manager) is the biggest one; event NPCs are small.

var context: DialogueContext
var current_msg: int = -1
## `mDemo_ORDER_NPC0..2` slots as the messages set them, `{"npc0": {slot: value}}`.
var orders: Dictionary = {}


func start_msg() -> int:
	return -1


func entered(_msg_no: int) -> void:
	pass


func picked(_msg_no: int, _index: int) -> int:
	return -1


func next_step() -> Dictionary:
	return {}


## Answer to a menu `next_step` put up with `{"msg", "choices"}`.
func choose(_index: int) -> Dictionary:
	return {}


## The pockets closed after a `{"hand": …}` step.
func hand_result(_item: StringName, _pocket: int = -1) -> Dictionary:
	return {}


## `mDemo_ORDER_QUEST` (villager quest talk only).
func order(_order_type: int, _value: int) -> void:
	pass


func npc_order(target: String, slot: int, value: int) -> void:
	var bank: Dictionary = orders.get(target, {})
	bank[slot] = value
	orders[target] = bank


func order_value(target: String, slot: int) -> int:
	return int((orders.get(target, {}) as Dictionary).get(slot, 0))


func clear_order(target: String, slot: int) -> void:
	var bank: Dictionary = orders.get(target, {})
	bank.erase(slot)
	orders[target] = bank


func finish() -> void:
	pass


## `mMsg_Set_free_str`: `{free<n>}` in the messages.
func set_free(index: int, text: String) -> void:
	if context == null:
		return
	if context.frees.size() <= index:
		context.frees.resize(index + 1)
	context.frees[index] = text


## `mFont_UnintToString(…, 5, TRUE, FALSE, TRUE)`: a price as the messages print it.
static func number(value: int) -> String:
	return str(value)


## Step helpers.
static func msg(n: int, choices: Array = []) -> Dictionary:
	if choices.is_empty():
		return {"msg": n}
	return {"msg": n, "choices": choices}


static func give(item: StringName) -> Dictionary:
	return {"anim": {"give": item}}


static func take(item: StringName) -> Dictionary:
	return {"anim": {"take": item}}
