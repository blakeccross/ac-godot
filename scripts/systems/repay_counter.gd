class_name RepayCounter
extends RefCounted

## The post office's loan screen (`m_repay_ovl.c`, opened by the clerk). Money is the wallet
## plus every NORMAL money bag in the pockets; the amount starts at 0 and can't pass
## `max_repay = min(loan, money)`. ←/→ pick a digit (100,000s … 1s) or OK; ↑ adds that
## digit's worth (clamped to the max; buzzes at the max), ↓ takes it off (to 0 if less;
## buzzes at 0). OK / START pays (`mRP_money_repay`): the wallet alone if it covers the
## amount, else bags smallest kind first in pocket order until they do, the change going
## to the wallet. B leaves without changes.

const CURSOR_MAX := BankTerminal.CURSOR_MAX
const CURSOR_OK := BankTerminal.CURSOR_OK

var money: int = 0
var max_money: int = 0
var loan_start: int = 0
var loan: int = 0
var amount: int = 0
var max_repay: int = 0
## Starts on the 100,000s digit.
var cursor: int = 0


## `mRP_repay_ovl_init`.
func open_from(inv: Inventory) -> void:
	max_money = inv.wallet + normal_bag_total(inv)
	money = max_money
	loan_start = inv.loan
	loan = loan_start
	amount = 0
	max_repay = mini(loan_start, max_money)
	cursor = 0


## NORMAL bags only: a wrapped present or a quest bag isn't money to spend.
static func normal_bag_total(inv: Inventory) -> int:
	var total := 0
	for s: int in Inventory.POCKET_SLOTS:
		var kind: int = _bag_kind(inv.slot_at(s))
		if kind >= 0:
			total += BankTerminal.BAG_AMOUNTS[kind] * inv.slot_at(s).item.count
	return total


func left() -> bool:
	if cursor >= CURSOR_OK:
		cursor = CURSOR_MAX
		return true
	if cursor > 0:
		cursor -= 1
		return true
	return false


func right() -> bool:
	if cursor < CURSOR_OK:
		cursor += 1
		return true
	return false


## ↑: false (a buzz) when already at the most that can be paid.
func up() -> bool:
	if cursor >= CURSOR_OK or amount >= max_repay:
		return false
	amount = mini(amount + BankTerminal.digit_value(cursor), max_repay)
	_show()
	return true


## ↓: false (a buzz) when already at 0.
func down() -> bool:
	if cursor >= CURSOR_OK or amount <= 0:
		return false
	var step: int = BankTerminal.digit_value(cursor)
	amount = 0 if amount < step else amount - step
	_show()
	return true


func _show() -> void:
	money = max_money - amount
	loan = loan_start - amount


## Settle: pay `amount` and lower the loan. Returns whether anything was paid.
func commit(inv: Inventory) -> bool:
	if amount <= 0:
		return false
	var change: int = pay(inv, amount)
	inv.set_wallet(clampi(change, 0, Inventory.WALLET_MAX))
	inv.set_loan(maxi(loan_start - amount, 0))
	inv.changed.emit()
	return true


## `mRP_money_repay`: spend `amount` and return the wallet left over. The wallet alone when it
## covers the amount; otherwise every bag kind from 100 up, each in pocket order, until the
## wallet plus the bags taken cover it.
static func pay(inv: Inventory, amount: int) -> int:
	if inv.wallet >= amount:
		return inv.wallet - amount
	var total: int = inv.wallet
	for kind: int in BankTerminal.BAG_IDS.size():
		for s: int in Inventory.POCKET_SLOTS:
			if total >= amount:
				return total - amount
			var slot: InventorySlot = inv.slot_at(s)
			if _bag_kind(slot) != kind:
				continue
			total += BankTerminal.BAG_AMOUNTS[kind] * slot.item.count
			slot.clear()
	return maxi(total - amount, 0)


static func _bag_kind(slot: InventorySlot) -> int:
	if slot == null or slot.is_empty() or slot.item.condition != InventoryItem.Condition.NORMAL:
		return -1
	return BankTerminal.BAG_IDS.find(slot.item.item_id)
