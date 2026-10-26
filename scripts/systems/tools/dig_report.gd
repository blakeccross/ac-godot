class_name DigReport
extends BankTalk

## "Check it out! I dug up …!" (`Player_actor_Get_scoop_demo_ct`, `MessageControl_Get_scoop`):
## the find held up under the dig jingle. With the pockets full it asks whether to swap
## something out or bury the find again (0x17B3; `submenu_flag`).

const MSG_GOT := 0x17AF
const MSG_FULL := 0x17B3
## `mBGMPsComp_make_ps_fanfare(0x28, …)`.
const FANFARE := 0x28
## `main_scoop->timer < 86`: ticks the find is held up before the report.
const REPORT_TICKS := 86
const ANIM_GET := "ply_1_get_d1"

var item: StringName
var banked: bool = true
## "Swap" picked on 0x17B3.
var swap: bool = false


func _init(p_item: StringName, p_banked: bool) -> void:
	item = p_item
	banked = p_banked


func prepare() -> void:
	var data: ItemData = ItemCatalog.get_item(item)
	context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")


func start_msg() -> int:
	return MSG_GOT


func next_step() -> Dictionary:
	if current_msg == MSG_GOT and not banked:
		return msg(MSG_FULL)
	return {}


func picked(msg_no: int, index: int) -> int:
	if msg_no == MSG_FULL:
		swap = index == 0
	return -1
