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


## The context is set; fill strings the first page needs.
func prepare() -> void:
	pass


func entered(_msg_no: int) -> void:
	pass


func picked(_msg_no: int, _index: int) -> int:
	return -1


## A message is about to chain to `to_msg` by itself: return another number to go there
## instead (`mMsg_Set_continue_msg_num` set while the message was up).
func continue_to(_from_msg: int, to_msg: int) -> int:
	return to_msg


## A choice that opens a demo instead of a message (`{"hand"|"text"|"anim": …}`).
func pick_step(_msg_no: int, _index: int) -> Dictionary:
	return {}


## The text editor closed after a `{"text": {"initial", "lines", "len"}}` step
## (`mSM_OVL_LEDIT`).
func text_result(_text: String) -> Dictionary:
	return {}


func next_step() -> Dictionary:
	return {}


## A page is about to move on (`mMsg_SET_LOCKCONTINUE`): return `{"anim": {...}}` to play
## a demo first, or `{}`.
func lock_continue() -> Dictionary:
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


## One message and whatever it chains to by itself (`aNTT_set_force_talk_info` and co.).
class Fixed:
	extends BankTalk

	var first: int = -1
	## `mMsg_Set_item_str` slots to fill before the first page, `{n: text}`.
	var item_strs: Dictionary = {}

	func _init(msg_no: int, p_items: Dictionary = {}) -> void:
		first = msg_no
		item_strs = p_items

	func start_msg() -> int:
		return first

	func prepare() -> void:
		for n: Variant in item_strs:
			context.set_item_str(int(n), str(item_strs[n]))
