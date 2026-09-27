class_name PoliceTalk
extends RefCounted

## Booker's conversations (`ac_npc_police2_move.c_inc`): the walk-in greeting
## (`aPOL2_set_force_talk_info_message_ctrl2`), the A-button talk
## (`aPOL2_set_norm_talk_info_message_ctrl`) and the claim confirm
## (`aPOL2_set_force_talk_info_message_ctrl` → `aPOL2_check_answer`).
## Plain lines play the imported disc message (`msg_<n>`) when the dialogue bank has
## been generated; `booker_talk.json` carries the same flow otherwise.

const CONVERSATION_ID := &"booker_talk"
const OP := "police"
const VAR_MSG := "police_msg"
const VAR_CLAIM := "police_claim"

const MSG_TALK_ITEMS := 0x077D
const MSG_CLAIM := 0x077E
const MSG_POCKETS_FULL := 0x0781
const MSG_GREET_EMPTY := 0x0784
const MSG_GREET_ITEMS := 0x0785
const MSG_TALK_EMPTY := 0x0786
const MSG_TALK_EMPTY_AFTER := 0x0787

## Node in `booker_talk.json` for each message.
const MSG_KEYS: Dictionary = {
	MSG_TALK_ITEMS: "talk_items",
	MSG_CLAIM: "claim",
	MSG_GREET_EMPTY: "greet_empty",
	MSG_GREET_ITEMS: "greet_items",
	MSG_TALK_EMPTY: "talk_empty",
	MSG_TALK_EMPTY_AFTER: "talk_empty_after",
}


## `aPOL2_set_force_talk_info_message_ctrl2`: 0x0784 when empty, else 0x0785.
static func greet_msg(keep_sum: int) -> int:
	return MSG_GREET_EMPTY if keep_sum == 0 else MSG_GREET_ITEMS


## `aPOL2_set_norm_talk_info_message_ctrl`: 0x077D while anything is kept; once empty,
## 0x0787 if he greeted you with items this visit (`_99C`, i.e. you just emptied it),
## else 0x0786.
static func talk_msg(keep_sum: int, greeted_with_items: bool) -> int:
	if keep_sum > 0:
		return MSG_TALK_ITEMS
	return MSG_TALK_EMPTY_AFTER if greeted_with_items else MSG_TALK_EMPTY


## The imported message when present, else the authored graph started at its node.
static func conversation(msg_no: int, ctx: DialogueContext) -> DialogueData:
	if msg_no != MSG_CLAIM:
		var imported: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg_no))
		if imported != null:
			return imported
	if ctx != null:
		ctx.set_var(VAR_MSG, str(MSG_KEYS.get(msg_no, "talk_items")))
	return DialogueCatalog.conversation(CONVERSATION_ID)


## `mMsg_SET_ITEM_STR_ART(mMsg_ITEM_STR0, …)`: the kept item's name with its article.
static func fill_claim(ctx: DialogueContext, item_id: StringName) -> void:
	if ctx == null:
		return
	var data: ItemData = ItemCatalog.get_item(item_id)
	ctx.item0 = with_article(data.display_name if data != null else String(item_id))
	ctx.set_var(VAR_CLAIM, "")


static func with_article(item_name: String) -> String:
	if item_name.is_empty():
		return item_name
	var first: String = item_name.substr(0, 1).to_lower()
	return ("an " if first in ["a", "e", "i", "o", "u"] else "a ") + item_name


## `{op:"police", action:"claim"}` (CHOICE0): move the item into the pockets and write
## the outcome to `police_claim` ("ok" / "full") for the graph. Returns the outcome.
static func apply_event(event: Dictionary, ctx: DialogueContext, slot: int) -> PoliceBook.Claim:
	if str(event.get("op", "")) != OP or str(event.get("action", "")) != "claim":
		return PoliceBook.Claim.EMPTY
	if Game == null or Game.police == null:
		return PoliceBook.Claim.EMPTY
	var result: PoliceBook.Claim = Game.police.claim_result(slot, Game.inventory)
	if ctx != null:
		ctx.set_var(VAR_CLAIM, "full" if result == PoliceBook.Claim.POCKETS_FULL else "ok")
	return result
