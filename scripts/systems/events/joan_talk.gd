class_name JoanTalk
extends BankTalk

## Joan's turnip stand (`ac_ev_kabuPeddler_move.c_inc`). First visit of the week: the
## introduction (0x06FD, with its optional turnip lesson); after that 0x0718. Both reach
## the price menu (0x070A: 10 / 50 / 100 / not buying) at Sunday's price
## (`kabu_price_schedule.daily_price[SUNDAY]`); a pick checks the pockets and the purse
## (`mSP_money_check`, bags count), takes the Bells, and hands the bunch over, then offers
## more (0x0719 → 0x0712–0x0715).

const MSG_FIRST := 0x06FD
const MSG_AGAIN := 0x0718
const MSG_PRICE := 0x070A
const MSG_MORE := 0x0719
const MSG_HERE_YOU_GO := 0x0711
## `next_msg_no` (first round) / `next_msg_no2` (after buying once): ok, no money, no room.
const AFTER_FIRST: Array[int] = [0x0711, 0x0710, 0x070F]
const AFTER_MORE: Array[int] = [0x0711, 0x0717, 0x0716]
## `sum[]`: bunch sizes for the price strings (free0 = one turnip).
const PRICE_SUMS: Array[int] = [1, 10, 50, 100]
const BUNCHES: Array[StringName] = [&"turnips_10", &"turnips_50", &"turnips_100"]
const BUNCH_SIZES: Array[int] = [10, 50, 100]

var price: int = 100
var inventory: Inventory
## Which menu the last pick came from: 0 = first round, 1 = "more".
var _round: int = 0
var _kind: int = -1


func _init(p_price: int = 100, p_inventory: Inventory = null) -> void:
	price = p_price
	inventory = p_inventory


## `aEKPD_check_look`: already spoke to her this week.
static func spoke_this_week(area: Dictionary) -> bool:
	return int(area.get("spoke_week", -1)) == _week()


static func _week() -> int:
	return KabuMarket.sunday_ordinal(Clock.year, Clock.month, Clock.day)


static func note_spoke(area: Dictionary) -> void:
	area["spoke_week"] = _week()


var _seen: bool = false


func setup(area: Dictionary) -> void:
	_seen = spoke_this_week(area)
	note_spoke(area)


func start_msg() -> int:
	return MSG_AGAIN if _seen else MSG_FIRST


## `aEKPD_set_price_str`.
func entered(msg_no: int) -> void:
	if msg_no == MSG_PRICE or msg_no == MSG_MORE:
		for i: int in PRICE_SUMS.size():
			set_free(i, number(price * PRICE_SUMS[i]))


## `aEKPD_sell_check`: 0–2 buy a bunch, 3 walks away.
func picked(msg_no: int, index: int) -> int:
	if msg_no == MSG_PRICE or msg_no == MSG_MORE:
		_round = 0 if msg_no == MSG_PRICE else 1
		_kind = index if index < 3 else -1
	return -1


## `aEKPD_sell_check_after`: at the end of "That'll be … Bells".
func next_step() -> Dictionary:
	if _kind < 0:
		return {}
	var table: Array[int] = AFTER_FIRST if _round == 0 else AFTER_MORE
	var kind: int = _kind
	_kind = -1
	var item: ItemData = ItemCatalog.get_item(BUNCHES[kind])
	if inventory == null or item == null or not inventory.has_space(1):
		return msg(table[2])
	var cost: int = price * BUNCH_SIZES[kind]
	if not ShopBook.can_afford(inventory, cost):
		return msg(table[1])
	ShopBook.pay(inventory, cost)
	inventory.add(item, 1)
	## `mPlib_request_main_give_type1(ITM_MONEY_10000)` then the bunch comes back (`NPC1`).
	return {"anim": {"take": &"money_10000"}, "then": {"anim": {"give": BUNCHES[kind]}, "msg": MSG_HERE_YOU_GO}}
