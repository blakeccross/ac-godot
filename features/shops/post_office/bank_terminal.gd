class_name BankTerminal
extends RefCounted

## The post office's ABD (`m_bank_ovl.c`). Cash counts the wallet plus every money bag in
## the pockets; the six-digit amount is how far cash has moved from where it started.
## ←/→ pick a digit (100,000s … 1s) or OK; ↑ deposits that digit's worth (no more than cash,
## never past the starting cash when it had grown, balance capped at 999,999,999), ↓
## withdraws it (no more than the balance, never past what the pockets can carry: the
## wallet's 99,999 plus 30,000 per bag or empty pocket). OK / START settles it
## (`mBN_bank_ok`): bags go first to cover a deposit, and cash beyond the wallet's cap is
## paid out as 30,000-bell bags. B leaves without changes.

const CURSOR_MAX := 5
const CURSOR_OK := 6
const DEPOSIT_MAX := 999999999
const BAG_AMOUNTS: Array[int] = [100, 1000, 10000, 30000]
const BAG_IDS: Array[StringName] = [&"money_100", &"money_1000", &"money_10000", &"money_30000"]

var now_bell: int = 0
var player_bell: int = 0
var bank_bell: int = 0
var player_max_bell: int = 0
## The amount shown, |now − start| (`mBN_now_bell_2_bell`).
var bell: int = 0
var cursor: int = 0


## `mBN_bank_ovl_init`.
func open_from(inv: Inventory) -> void:
	now_bell = inv.wallet + bag_total(inv)
	player_bell = now_bell
	bell = 0
	player_max_bell = Inventory.WALLET_MAX
	for id: StringName in BAG_IDS:
		player_max_bell += inv.count_of(id) * BAG_AMOUNTS[3]
	player_max_bell += inv.empty_slot_count() * BAG_AMOUNTS[3]
	bank_bell = inv.savings
	cursor = 0


static func bag_total(inv: Inventory) -> int:
	var total := 0
	for i: int in BAG_IDS.size():
		total += inv.count_of(BAG_IDS[i]) * BAG_AMOUNTS[i]
	return total


## `mBN_cursol_2_keta`: 100,000 at the first digit, 1 at the last.
static func digit_value(at: int) -> int:
	var v := 1
	for _i: int in range(at, CURSOR_MAX):
		v *= 10
	return v


func left() -> bool:
	if cursor > 0:
		cursor -= 1
		return true
	return false


func right() -> bool:
	if cursor < CURSOR_OK:
		cursor += 1
		return true
	return false


## C-up: returns false (the buzz) when nothing moves.
func deposit() -> bool:
	if cursor > CURSOR_MAX:
		return false
	var keta: int = mini(digit_value(cursor), now_bell)
	if keta + bank_bell > DEPOSIT_MAX:
		keta = DEPOSIT_MAX - bank_bell
	if keta == 0:
		return false
	if now_bell > player_bell and now_bell - keta < player_bell:
		keta = now_bell - player_bell
	bank_bell += keta
	now_bell -= keta
	bell = absi(now_bell - player_bell)
	return true


## C-down.
func withdraw() -> bool:
	if cursor > CURSOR_MAX:
		return false
	var keta: int = mini(digit_value(cursor), bank_bell)
	if now_bell + keta > player_max_bell:
		keta = player_max_bell - now_bell
	if keta == 0:
		return false
	if now_bell < player_bell and now_bell + keta > player_bell:
		keta = player_bell - now_bell
	bank_bell -= keta
	now_bell += keta
	bell = absi(now_bell - player_bell)
	return true


## `mBN_bank_ok`: the balance, then the pockets — bags spent to cover the cash, then
## bags upgraded and added for what the wallet can't hold.
func commit(inv: Inventory) -> void:
	bank_bell = clampi(bank_bell, 0, DEPOSIT_MAX)
	inv.set_savings(bank_bell)
	var i := 0
	while now_bell < bag_total(inv) and i < BAG_IDS.size():
		var slot: int = _slot_of(inv, BAG_IDS[i])
		if slot < 0:
			i += 1
		else:
			inv.slot_at(slot).clear()
	var remain: int = now_bell - bag_total(inv)
	i = 0
	while remain > Inventory.WALLET_MAX and i < BAG_IDS.size() - 1:
		var slot: int = _slot_of(inv, BAG_IDS[i])
		if slot < 0:
			i += 1
		else:
			inv.slot_at(slot).set_stack(BAG_IDS[3], 1, InventoryItem.Condition.NORMAL)
			remain -= BAG_AMOUNTS[3] - BAG_AMOUNTS[i]
	while remain > Inventory.WALLET_MAX:
		var empty: int = _empty_slot(inv)
		if empty < 0:
			break
		inv.slot_at(empty).set_stack(BAG_IDS[3], 1, InventoryItem.Condition.NORMAL)
		remain -= BAG_AMOUNTS[3]
	inv.set_wallet(clampi(now_bell - bag_total(inv), 0, Inventory.WALLET_MAX))
	inv.changed.emit()


static func _slot_of(inv: Inventory, id: StringName) -> int:
	for s: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(s)
		if slot != null and not slot.is_empty() and slot.item.item_id == id:
			return s
	return -1


static func _empty_slot(inv: Inventory) -> int:
	for s: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(s)
		if slot != null and slot.is_empty():
			return s
	return -1


## `l_mml_postoffice_info`: [handbill, present, flag bit, balance].
const GIFTS: Array = [
	[0x246, &"ftr_1004", 1, 1000000],
	[0x247, &"ftr_1003", 2, 10000000],
	[0x248, &"ftr_1189", 4, 100000000],
	[0x249, &"ftr_1032", 8, 999999999],
]


## `mMl_send_postoffice_mail`: the first milestone reached whose gift hasn't been sent
## (one per game start), or {}.
static func due_gift(balance: int, sent_flags: int) -> Dictionary:
	for g: Array in GIFTS:
		if balance >= int(g[3]) and (sent_flags & int(g[2])) == 0:
			return {"mail_no": int(g[0]), "present": g[1], "flag": int(g[2])}
	return {}


static func gift_letter(gift: Dictionary, town: String, player: String) -> MailData:
	var text: Dictionary = MailBank.letter(int(gift["mail_no"]), player, {0: town, 1: player})
	var mail := MailData.new()
	mail.sender_id = &"post_office"
	mail.sender_name = "Post Office"
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.font = MailData.LetterFont.RECV_PRESENT
	mail.present_item_id = gift["present"]
	mail.header = str(text.get("header", ""))
	mail.body = str(text.get("body", ""))
	mail.footer = str(text.get("footer", ""))
	return mail
