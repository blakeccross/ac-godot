class_name JingleTalk
extends BankTalk

## Jingle on Toy Day (`ac_ev_santa`). He has to be found in a new acre for every step
## (talking again where he was only gets 0x07BC–0x07BE): hello, two questions whose answers
## pick furniture / clothing / wallpaper / carpet, a final check, then a wrapped present
## from that Christmas list. Afterwards he knows the player by their shirt; in a shirt he
## hasn't seen (up to ten) he half-recognises them (0x2B4C), and if they come back in the
## same one, he hands over another present.

enum Wish { FTR, CLOTH, WALL, CARPET }

const MSG_SAME_PLAYER := 0x07BF
const MSG_PRESENT := 0x07BA
const MSG_FULL := 0x07B9
const MSG_SAME_ACRE := 0x07BC
const MSG_HELLO := 0x07AA
const MSG_CHECK_1ST := 0x07AB
const MSG_CHECK_2ND := 0x07AE
## `aESNT_TALK_CHK_FINAL + present`.
const MSG_CHECK_FINAL: Array[int] = [0x07B2, 0x07B4, 0x07B1, 0x07B3]
const MSG_ALMOST := 0x2B4C
const MSG_PRESENT2 := 0x2B59
const MSG_FULL2 := 0x2B58
const MSG_NO_MORE := 0x2B5B
## `MSG_SANTA_WISH_*` (0x2B4C picks one at random): what he offers this time.
const MSG_WISH: Dictionary = {0x2B54: Wish.FTR, 0x2B55: Wish.WALL, 0x2B56: Wish.CARPET, 0x2B57: Wish.CLOTH}
const CLOTH_MAX := 10
const LIST := "Christmas"

## `mEv_santa_event_c` + `_common_c`: `{given, cloth: [ids], counter, present, block, last_cloth}`.
var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var block: Vector2i = Vector2i(-1, -1)
var cloth: StringName = &""
var gift: StringName = &""


func _init(p_area: Dictionary, p_inventory: Inventory = null, p_rng: RandomNumberGenerator = null) -> void:
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


func _counter() -> int:
	return int(area.get("counter", 0))


## `aESNT_getP_talk_data`.
func start_msg() -> int:
	if bool(area.get("given", false)):
		return _after()
	if area.get("block", Vector2i(-2, -2)) == block:
		return MSG_SAME_ACRE + rng.randi_range(0, 2)
	var n: int
	if _counter() >= 4:
		n = _present(false)
	else:
		match _counter():
			0:
				n = MSG_HELLO
			1:
				n = MSG_CHECK_1ST
			2:
				n = MSG_CHECK_2ND
			_:
				n = MSG_CHECK_FINAL[clampi(int(area.get("present", 0)), 0, 3)]
		area["counter"] = _counter() + 1
	if n != MSG_FULL:
		area["block"] = block
	return n


## `aESNT_after_talk_same_pl_decide_talk_data_idx`.
func _after() -> int:
	var seen: Array = area.get("cloth", [])
	if String(cloth) in seen:
		area["counter"] = 0
		return MSG_SAME_PLAYER + rng.randi_range(0, 2)
	if seen.size() >= CLOTH_MAX:
		return MSG_NO_MORE + rng.randi_range(0, 2)
	if _counter() != 0 and str(area.get("last_cloth", "")) == String(cloth):
		return _present(true)
	area["last_cloth"] = String(cloth)
	area["counter"] = 1 if _counter() != 0 else _counter() + 1
	return MSG_ALMOST


## `aESNT_before_talk_present_decide_talk_data_idx`.
func _present(again: bool) -> int:
	if inventory == null or not inventory.has_space(1):
		return MSG_FULL2 if again else MSG_FULL
	var kinds: Array[String] = ["ftr", "cloth", "wall", "carpet"]
	var wish: int = clampi(int(area.get("present", 0)), 0, 3)
	gift = FtrCatalog.pick_named(kinds[wish], LIST, rng)
	var data: ItemData = ItemCatalog.get_item(gift)
	if data != null:
		inventory.add(data, 1, InventoryItem.Condition.PRESENT)
	area["given"] = true
	area["counter"] = 0
	var seen: Array = area.get("cloth", [])
	seen.append(String(cloth))
	area["cloth"] = seen
	return MSG_PRESENT2 if again else MSG_PRESENT


## `aESNT_chk_wish_1st` / `_final`.
func picked(msg_no: int, index: int) -> int:
	var present: int = int(area.get("present", 0))
	if msg_no == MSG_CHECK_1ST:
		area["present"] = present | (0 if index == 0 else 1)
	elif msg_no == MSG_CHECK_2ND:
		area["present"] = present | ((0 if index == 0 else 1) << 1)
	elif msg_no in MSG_CHECK_FINAL:
		if index == 0:
			area["present"] = present & 1
		else:
			area["present"] = Wish.WALL if present & 2 != 0 else Wish.CARPET
	return -1


## `aESNT_chk_wish_more`: the line 0x2B4C lands on says what's on offer next time.
func entered(msg_no: int) -> void:
	if MSG_WISH.has(msg_no):
		area["present"] = int(MSG_WISH[msg_no])
