class_name KatrinaTalk
extends BankTalk

## Katrina's reading (`ac_ev_gypsy_move.c_inc`). 0x0970 "a reading for 50 Bells?" — no
## 0x0971, yes with the Bells 0x0973, without 0x0972. The reading takes 50 Bells, fills four
## words from the disc's word lists (adjective / noun / verb / place, 32 each) and picks the
## day's destiny: half the time normal (0x0974), else popular / unpopular / bad luck /
## money luck / goods luck (0x0975–0x0979). Already read today: 0x097B then the reminder
## (0x097C–0x0980); again in the same visit: 0x0982.

const MSG_ASK := 0x0970
const MSG_NO := 0x0971
const MSG_BROKE := 0x0972
const MSG_READING := 0x0973
const MSG_RESULT := 0x0974
const MSG_ALREADY := 0x097B
const MSG_REMINDER := 0x097C
const MSG_AGAIN := 0x0982
const PRICE := 50
## `aEGPS_set_string`: `string_num[]` per item-string slot (adjective, noun, verb, place).
const WORD_BASES: Array[int] = [0x1A4, 0x1C4, 0x184, 0x164]

enum Destiny { NORMAL, POPULAR, UNPOPULAR, BAD_LUCK, MONEY_LUCK, GOODS_LUCK }

var destiny: int = Destiny.NORMAL
var given_this_visit: bool = false
var inventory: Inventory
var rng: RandomNumberGenerator


func _init(p_destiny: int, p_given: bool, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	destiny = p_destiny
	given_this_visit = p_given
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


func start_msg() -> int:
	if given_this_visit:
		return MSG_AGAIN
	if destiny == Destiny.NORMAL:
		return MSG_ASK
	return MSG_ALREADY


## `aEGPS_call_in`.
func picked(msg_no: int, index: int) -> int:
	if msg_no != MSG_ASK:
		return -1
	if index != 0:
		return MSG_NO
	if inventory == null or inventory.wallet < PRICE:
		return MSG_BROKE
	## `aEGPS_decide_result_init`.
	inventory.set_wallet(inventory.wallet - PRICE)
	for slot: int in WORD_BASES.size():
		context.set_item_str(slot, DialogueCatalog.rom_string(WORD_BASES[slot] + rng.randi_range(0, 31)))
	given_this_visit = true
	return MSG_READING


## `aEGPS_decide_result` at the message's order 9.
func next_step() -> Dictionary:
	if current_msg == MSG_READING:
		var selected: int = maxi(rng.randi_range(0, 9), 4) - 4
		destiny = selected
		return msg(MSG_RESULT + selected)
	if current_msg == MSG_ALREADY:
		return msg(MSG_REMINDER + destiny - 1)
	return {}
