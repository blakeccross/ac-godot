class_name GracieTalk
extends BankTalk

## Gracie (`ac_ev_designer_talk.c_inc`). Her lines come from two 27-entry tables — one if
## the player wears one of her (event-list) shirts (`wear_flag`), one if not.
##
## - First talk: by gender (idx 0–3 for boys, 4–7 for girls; idx 8 once somebody washed the
##   car this visit). With room in the pockets she asks for a wash (idx 19, or idx 26 "put
##   that thing away" while holding a tool) and the minigame starts when the window closes.
## - Start of the wash: idx 10. After it: idx 25, then by result 0 (fast) → idx 12 and an
##   event shirt, 1 (slow) → idx 14 and a common shirt, 2 (time up) → idx 16, nothing.
## - Already given a shirt: idx 17 (hers) / 18; washed but no gift: idx 21–23.

enum Kind { NORMAL, START, RESULT }

const MSG_NOT_WEARING: Array[int] = [
	0x0721, 0x0722, 0x0723, 0x0724, 0x0725, 0x0726, 0x0727, 0x0728,
	0x0729, 0x072A, 0x072B, 0x072C, 0x072D, 0x072E, 0x072F, 0x0730,
	0x0731, 0x0732, 0x0733, 0x0747, 0x0748, 0x0749, 0x074A, 0x074B,
	0x072B, 0x072C, 0x074C,
]
const MSG_WEARING: Array[int] = [
	0x0734, 0x0735, 0x0736, 0x0745, 0x0737, 0x0738, 0x0739, 0x0746,
	0x073A, 0x073B, 0x073C, 0x073D, 0x073E, 0x073F, 0x0740, 0x0741,
	0x0742, 0x0743, 0x0744, 0x0747, 0x0748, 0x0749, 0x074A, 0x074B,
	0x073C, 0x073D, 0x074C,
]
const RESULT_MSG_IDX: Array[int] = [12, 14, 16]

var kind: Kind = Kind.NORMAL
var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var wearing: bool = false
var female: bool = false
var holding_tool: bool = false
## This visit's wash already done by this player (`complete_flag`).
var complete: bool = false
## 0 fast / 1 slow / 2 time up.
var result: int = 2
var present: StringName = &""
## Set when the talk asked for a wash.
var wants_wash: bool = false
var _first: int = -1


func _init(p_kind: Kind, p_area: Dictionary, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	kind = p_kind
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


func msg_no(idx: int) -> int:
	return (MSG_WEARING if wearing else MSG_NOT_WEARING)[idx]


## `aEDSN_set_norm_talk_info` / `aEDSN_set_force_talk_info`.
func start_msg() -> int:
	match kind:
		Kind.START:
			_first = msg_no(10)
		Kind.RESULT:
			_first = msg_no(25)
		_:
			if complete:
				_first = msg_no(21 + rng.randi_range(0, 2))
			elif area.has("gift"):
				var mine := StringName(str(area["gift"]))
				_first = msg_no(17 if FtrCatalog.named_list("cloth", "Event").has(mine) else 18)
			elif bool(area.get("complete", false)):
				_first = msg_no(8)
			else:
				_first = msg_no((4 if female else 0) + rng.randi_range(0, 3))
	return _first


## `aEDSN_inventory_check_talk_proc` (the message's order 9) / `aEDSN_check_result_talk_proc`.
func next_step() -> Dictionary:
	if kind == Kind.RESULT and current_msg == _first:
		return _result()
	if kind == Kind.NORMAL and current_msg == _first and not complete and not area.has("gift"):
		if inventory == null or not inventory.has_space(1):
			return {}
		wants_wash = true
		return msg(msg_no(26 if holding_tool else 19))
	return {}


func _result() -> Dictionary:
	area["complete"] = true
	var given: Array = area.get("gifted", [])
	match result:
		0:
			present = FtrCatalog.pick_named("cloth", "Event", rng, given)
		1:
			present = FtrCatalog.pick_named("cloth", "A", rng, given)
	var n: int = msg_no(RESULT_MSG_IDX[clampi(result, 0, 2)])
	if present == &"":
		return msg(n)
	var data: ItemData = ItemCatalog.get_item(present)
	if data != null and inventory != null:
		inventory.add(data, 1)
	given.append(String(present))
	area["gifted"] = given
	area["gift"] = String(present)
	## The shirt changes hands after her lines (`aEDSN_demo_start_wait_talk_proc`).
	return msg(n)
