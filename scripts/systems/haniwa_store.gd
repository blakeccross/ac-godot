class_name HaniwaStore
extends RefCounted

## What the house gyroid holds (`Haniwa_c` on the player's `House`): four consigned items, the
## message for visitors and the bells visitors have paid. Owner side is `m_haniwa_ovl` in
## `mSM_IV_OPEN_HANIWA_ENTRUST` (put in / take back / set terms); visitor side is
## `mSM_IV_OPEN_HANIWA_TAKE` (`mTG_present_open_proc`: pay and take). Pure rules — the
## inventory overlay and `haniwa.gd` drive them.

## `mHm_HANIWA_TRADE_*`: free to take, display only, for sale at `price`.
enum Exchange { FREE, DISPLAY, SALE }

## `HANIWA_ITEM_HOLD_NUM`.
const SLOTS := 4
## `mTG_mv_priceSet`: five digits, 0–99 999; setting 0 makes the item free.
const PRICE_MAX := 99999
const PRICE_STEPS: Array[int] = [10000, 1000, 100, 10, 1]
## `mHm_haniwa_msg` / `title_game_haniwa_data_init`: `mString_HANIWA_MSG0`–`3`, one per line.
const DEFAULT_MESSAGE_IDS: Array[int] = [0x76A, 0x76B, 0x76C, 0x76D]
const MESSAGE_LEN := 128
const MESSAGE_LINES := 4
## `mTG_money_amount` — bags are spent smallest first when the wallet is short.
const BAG_SPEND_ORDER: Array[int] = [100, 1000, 10000, 30000]
## `aHNW_check_handOver_proceeds`: overflow goes out in 30 000-bell bags.
const PROCEEDS_BAG := 30000

## `m_haniwa_ovl` status lines (`mHW_make_cond_message`), by what the cursor is on.
const MSG_HOW_CAN_I_HELP := "How can I help?"
const MSG_CHOOSE_ONE := "Choose one."
const MSG_MAY_I_HELP := "May I help you?"
const MSG_HOW_MUCH := "How much?"
const MSG_GOT_IT := "Got it!"
const MSG_NO_ROOM := "You don't have room."
const MSG_CANT_AFFORD := "You can't afford that."
const MSG_THANKS := "Thank you very much!"
const MSG_FREE := "That's free"
const MSG_GIVE_AWAY := "Give Away"
const MSG_DISPLAY_ONLY := "That's display only."


static func empty_slot() -> Dictionary:
	return {"item": &"", "count": 0, "cond": 0, "exchange": Exchange.FREE, "price": 0}


## Pad / trim the house's list to `SLOTS` entries.
static func ensure(house: House) -> void:
	if house == null:
		return
	while house.haniwa_items.size() < SLOTS:
		house.haniwa_items.append(empty_slot())
	while house.haniwa_items.size() > SLOTS:
		house.haniwa_items.pop_back()


static func item_at(house: House, slot: int) -> Dictionary:
	ensure(house)
	if house == null or slot < 0 or slot >= SLOTS:
		return empty_slot()
	return house.haniwa_items[slot]


static func is_empty_slot(house: House, slot: int) -> bool:
	return StringName(item_at(house, slot).get("item", &"")) == &""


## `aHNW_check_keep_item`.
static func has_items(house: House) -> bool:
	for i: int in SLOTS:
		if not is_empty_slot(house, i):
			return true
	return false


## `title_game_haniwa_data_init`: the four ROM lines joined with newlines. "" when the string
## bank is not converted.
static func default_message() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for id: int in DEFAULT_MESSAGE_IDS:
		var line: String = DialogueCatalog.rom_string(id)
		if line == "":
			return ""
		lines.append(line)
	return "\n".join(lines).substr(0, MESSAGE_LEN)


## The message visitors read, falling back to the default when none has been set.
static func message(house: House) -> String:
	if house == null:
		return ""
	return house.haniwa_message if house.haniwa_message != "" else default_message()


## Owner puts pocket item `pocket` into empty gyroid slot `slot` on the given terms
## (`mTG_haniwa_put_item` → `mTG_set_trade_cond`). A price of 0 is free.
static func entrust(
	house: House, slot: int, inv: Inventory, pocket: int, exchange: Exchange, price: int = 0
) -> bool:
	ensure(house)
	if house == null or inv == null or slot < 0 or slot >= SLOTS or not is_empty_slot(house, slot):
		return false
	var pocket_slot: InventorySlot = inv.slot_at(pocket)
	if pocket_slot == null or pocket_slot.is_empty():
		return false
	if inv.hand_index == pocket:
		inv.clear_hand()
	var taken: InventoryItem = inv.remove_from_slot(pocket, pocket_slot.item.count)
	house.haniwa_items[slot] = {
		"item": taken.item_id,
		"count": taken.count,
		"cond": int(taken.condition),
		"exchange": Exchange.FREE,
		"price": 0,
	}
	set_terms(house, slot, exchange, price)
	return true


## `mTG_set_trade_cond`: free / display only / for sale. Sale at 0 bells is free.
static func set_terms(house: House, slot: int, exchange: Exchange, price: int = 0) -> void:
	if is_empty_slot(house, slot):
		return
	var rec: Dictionary = house.haniwa_items[slot]
	var p: int = clampi(price, 0, PRICE_MAX)
	if exchange == Exchange.SALE and p == 0:
		exchange = Exchange.FREE
	rec["exchange"] = exchange
	rec["price"] = p if exchange == Exchange.SALE else 0


## `mTG_mv_priceSet` digit step: `digit` 0..4 (10 000 … 1), `dir` ±1, clamped to 0..99 999.
static func step_price(price: int, digit: int, dir: int) -> int:
	var step: int = PRICE_STEPS[clampi(digit, 0, PRICE_STEPS.size() - 1)]
	return clampi(price + step * signi(dir), 0, PRICE_MAX)


## Owner grabs an item back (`mTG_tag_word_tukamu` on the gyroid table): into the pockets.
static func take_back(house: House, slot: int, inv: Inventory) -> bool:
	if inv == null or is_empty_slot(house, slot):
		return false
	var rec: Dictionary = house.haniwa_items[slot]
	var data: ItemData = ItemCatalog.get_item(StringName(rec["item"]))
	if data == null or inv.add(data, int(rec["count"]), int(rec["cond"]) as InventoryItem.Condition) > 0:
		return false
	house.haniwa_items[slot] = empty_slot()
	return true


## Money the visitor can spend: wallet plus normal-condition bell bags in the pockets.
static func spendable(inv: Inventory) -> int:
	var total: int = inv.wallet
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inv.slot_at(i)
		if s == null or s.is_empty() or s.item.condition != InventoryItem.Condition.NORMAL:
			continue
		total += _bag_value(s.item.item_id) * s.item.count
	return total


## Visitor takes an item (`mTG_present_open_proc`). Returns &"ok", &"no_room" (no empty pocket),
## &"no_money", &"display" (display only) or &"" (nothing there). Paying drains the wallet
## first, then bell bags smallest first; the price goes onto the gyroid's bells.
static func buy(house: House, slot: int, inv: Inventory) -> StringName:
	if inv == null or is_empty_slot(house, slot):
		return &""
	var rec: Dictionary = house.haniwa_items[slot]
	if int(rec["exchange"]) == Exchange.DISPLAY:
		return &"display"
	if not inv.has_space(1):
		return &"no_room"
	var price: int = int(rec["price"]) if int(rec["exchange"]) == Exchange.SALE else 0
	if spendable(inv) < price:
		return &"no_money"
	var keep: int = inv.wallet - price
	for amount: int in BAG_SPEND_ORDER:
		while keep < 0:
			var idx: int = _find_bag(inv, amount)
			if idx < 0:
				break
			inv.remove_from_slot(idx, 1)
			keep += amount
		if keep >= 0:
			break
	inv.set_wallet(keep)
	var data: ItemData = ItemCatalog.get_item(StringName(rec["item"]))
	if data != null:
		inv.add(data, int(rec["count"]), int(rec["cond"]) as InventoryItem.Condition)
	house.haniwa_bells += price
	house.haniwa_items[slot] = empty_slot()
	return &"ok"


## `aHNW_check_handOver_proceeds`: the owner collects `haniwa_bells`. Under the wallet cap it all
## goes in the wallet; over it, the overflow goes out in 30 000-bell bags when there are enough
## free pocket slots. Returns `{ "ok": bool, "bags": int }` — `bags` is how many slots are
## needed when it fails (`{free1}`).
static func collect_proceeds(house: House, inv: Inventory) -> Dictionary:
	if house == null or inv == null:
		return {"ok": false, "bags": 0}
	var money: int = inv.wallet + house.haniwa_bells
	if money < Inventory.WALLET_MAX:
		inv.set_wallet(money)
		house.haniwa_bells = 0
		return {"ok": true, "bags": 0}
	var bags: int = (money - Inventory.WALLET_MAX) / PROCEEDS_BAG + 1
	if inv.empty_slot_count() < bags:
		return {"ok": false, "bags": bags}
	var bag: ItemData = ItemCatalog.get_item(Inventory.BAG_ITEM_IDS[PROCEEDS_BAG])
	for _i: int in bags:
		if bag != null:
			inv.add(bag, 1)
		money -= PROCEEDS_BAG
	inv.set_wallet(money)
	house.haniwa_bells = 0
	return {"ok": true, "bags": 0}


## `mHW_make_message_normal`: the status line for the slot under the cursor. `owner`: entrust
## mode (`data0 == 0`).
static func status_line(house: House, slot: int, owner: bool) -> String:
	if slot < 0 or is_empty_slot(house, slot):
		return MSG_HOW_CAN_I_HELP if owner else MSG_MAY_I_HELP
	var rec: Dictionary = house.haniwa_items[slot]
	match int(rec["exchange"]):
		Exchange.FREE:
			return MSG_FREE if owner else MSG_GIVE_AWAY
		Exchange.SALE:
			return "It's %d Bells" % int(rec["price"])
	return MSG_DISPLAY_ONLY


static func _bag_value(item_id: StringName) -> int:
	for amount: int in Inventory.BAG_ITEM_IDS:
		if Inventory.BAG_ITEM_IDS[amount] == item_id:
			return amount
	return 0


static func _find_bag(inv: Inventory, amount: int) -> int:
	var want: StringName = Inventory.BAG_ITEM_IDS.get(amount, &"")
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inv.slot_at(i)
		if s != null and not s.is_empty() and s.item.item_id == want \
				and s.item.condition == InventoryItem.Condition.NORMAL:
			return i
	return -1
