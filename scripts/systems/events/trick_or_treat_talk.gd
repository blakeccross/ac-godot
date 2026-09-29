class_name TrickOrTreatTalk
extends BankTalk

## Halloween night: Jack (`ac_ev_pumpkin`, messages 0x09B5–0x09C1) and the residents out in
## his costume (`ac_halloween_npc`, 0x098B + looks * 6). Both shout "Trick or treat!"
## (0x098A) and ask for candy. Candy makes them happy — Jack wraps a present (the spooky rug
## or wall 1 in 12, else a Halloween piece); an empty hand or anything else earns a trick:
## half the time (if there's something to swap) a pocket item turns into a jack-o'-lantern
## or jack-in-the-box, otherwise the player's shirt changes (`ITM_CLOTH017`). Tools are
## handed back. Everything else given is kept.

const MSG_TRICK_OR_TREAT := 0x098A
## Jack's bank.
const JACK_ASK := 0x09B5
const JACK_EMPTY := 0x09B6
const JACK_TRICKED := 0x09B7
const JACK_OTHER := 0x09B8
const JACK_CANDY := 0x09B9
const JACK_BYE := 0x09BA
const JACK_TOOL := 0x09BB
const JACK_AGAIN := 0x09BC
## A resident's bank: base + looks * 6.
const NPC_ASK := 0x098B
const NPC_EMPTY := 0x098C
const NPC_TRICKED := 0x098D
const NPC_OTHER := 0x098E
const NPC_CANDY := 0x098F
const NPC_TOOL := 0x0990
const NPC_AFTER := 0x09AF
const CANDY := &"candy"
const TRICK_CLOTH := 17
## `FTR_SUM_HAL_PKIN`, `FTR_SUM_HAL_BOX01`: never swapped away.
const TRICK_KEEP_LIST := "Halloween2"

var jack: bool = true
var looks: int = 0
var inventory: Inventory
var rng: RandomNumberGenerator
## Jack in the acre he last talked in: just a chat (`aEPK_set_talk_info`).
var same_acre: bool = false
## A resident already met tonight (`aHWN_norm_talk_request`).
var met: bool = false
var present: StringName = &""
var tricked_item: StringName = &""
var tricked_cloth: bool = false
var _item: StringName = &""


func _init(p_jack: bool, p_looks: int, p_inventory: Inventory = null, p_rng: RandomNumberGenerator = null) -> void:
	jack = p_jack
	looks = p_looks
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


func _m(jack_msg: int, npc_msg: int) -> int:
	return jack_msg if jack else npc_msg + looks * 6


func start_msg() -> int:
	if jack and same_acre:
		return JACK_AGAIN + rng.randi_range(0, 5)
	if not jack and met:
		return NPC_AFTER + looks
	return MSG_TRICK_OR_TREAT


## "Trick or treat!" → the ask (`aEPK_first_call_talk_proc`); the tricks after the lines
## that end on order 9 (`aEPK_trick_timing_wait_talk_proc`); Jack's present after "take this".
func next_step() -> Dictionary:
	if current_msg == MSG_TRICK_OR_TREAT:
		return msg(_m(JACK_ASK, NPC_ASK))
	if current_msg in [_m(JACK_EMPTY, NPC_EMPTY), _m(JACK_OTHER, NPC_OTHER), _m(JACK_TOOL, NPC_TOOL)]:
		return _trick()
	if jack and current_msg == JACK_CANDY and present != &"":
		var gift: StringName = present
		present = &""
		return {"anim": {"give": gift}, "msg": JACK_BYE}
	return {}


## "Yes" opens the pockets (`mSM_IV_OPEN_GIVE`); "no" runs on to the empty-hand line.
func pick_step(msg_no: int, index: int) -> Dictionary:
	if msg_no == _m(JACK_ASK, NPC_ASK) and index == 0:
		return {"hand": {"pocket": -1, "mode": "take"}}
	return {}


## `aEPK_menu_close_wait_talk_proc`.
func hand_result(item: StringName, _pocket: int = -1) -> Dictionary:
	_item = item
	if item == &"":
		return msg(_m(JACK_EMPTY, NPC_EMPTY))
	var data: ItemData = ItemCatalog.get_item(item)
	if item == CANDY:
		inventory.remove(item, 1)
		if jack:
			present = decide_present(rng)
			var gift: ItemData = ItemCatalog.get_item(present)
			if gift != null:
				inventory.add(gift, 1, InventoryItem.Condition.PRESENT)
		return {"anim": {"take": item}, "msg": _m(JACK_CANDY, NPC_CANDY)}
	if data != null and data.category == ItemData.Category.TOOL:
		return {"anim": {"take": item}, "then": {"anim": {"give": item}, "msg": _m(JACK_TOOL, NPC_TOOL)}}
	inventory.remove(item, 1)
	return {"anim": {"take": item}, "msg": _m(JACK_OTHER, NPC_OTHER)}


## `aEPK_decide_present`.
static func decide_present(r: RandomNumberGenerator) -> StringName:
	match r.randi_range(0, 11):
		0:
			return FtrCatalog.goods_id("carpet", 17)
		1:
			return FtrCatalog.goods_id("wall", 17)
	var id: StringName = FtrCatalog.pick_named("ftr", "Halloween", r)
	return id if id != &"" else FtrCatalog.goods_id("carpet", 17)


## `aEPK_get_trick_type`: swap a pocket item, else change the shirt.
func _trick() -> Dictionary:
	var keep: Array[StringName] = FtrCatalog.named_list("ftr", TRICK_KEEP_LIST)
	var slots: Array[int] = []
	if inventory != null:
		for i: int in Inventory.POCKET_SLOTS:
			var s: InventorySlot = inventory.slot_at(i)
			if s == null or s.is_empty() or s.item.condition == InventoryItem.Condition.QUEST:
				continue
			var data: ItemData = ItemCatalog.get_item(s.item.item_id)
			if data == null or data.category == ItemData.Category.TOOL or s.item.item_id in keep:
				continue
			slots.append(i)
	if not slots.is_empty() and rng.randf() < 0.5:
		var swap: StringName = FtrCatalog.pick_named("ftr", TRICK_KEEP_LIST, rng)
		if swap != &"":
			var idx: int = slots[rng.randi_range(0, slots.size() - 1)]
			var s: InventorySlot = inventory.slot_at(idx)
			s.set_stack(swap, 1, InventoryItem.Condition.NORMAL)
			inventory.changed.emit()
			tricked_item = swap
			return msg(_m(JACK_TRICKED, NPC_TRICKED))
	tricked_cloth = true
	if Game != null:
		Game.set_cloth(FtrCatalog.goods_id("cloth", TRICK_CLOTH))
	return msg(_m(JACK_TRICKED, NPC_TRICKED))
