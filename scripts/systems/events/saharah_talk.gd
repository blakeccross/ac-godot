class_name SaharahTalk
extends BankTalk

## Saharah the carpet peddler (`ac_ev_carpetPeddler.c_inc`, messages from
## `MSG_CARPETPEDDLER_START` 0x048A). She trades one of her exotic carpets (the event carpet
## list) for any carpet of yours plus Bells: 3,000, doubling with each trade-in this visit
## (`arabian.used`, capped at 4 → 48,000).
##
## 0x048A "trade-in?" → no 0x048B; yes 0x048C (her carpet, the price) → no 0x048B; yes:
## no carpet in the pockets 0x048E, short of Bells 0x048D, else 0x048F and the pockets open
## ("take"). Nothing chosen 0x0490; not a carpet 0x0493 (handed back) then 0x0494 and the
## pockets again; a carpet: it changes hands with the Bells, then hers comes back
## (0x0491 → 0x0492).

const MSG_START := 0x048A
const MSG_NO := 0x048B
const MSG_OFFER := 0x048C
const MSG_BROKE := 0x048D
const MSG_NO_CARPET := 0x048E
const MSG_CHOOSE := 0x048F
const MSG_CHANGED_MIND := 0x0490
const MSG_TRADE := 0x0491
const MSG_REFUSE := 0x0493
const MSG_CHOOSE_AGAIN := 0x0494
const PRICE_START := 3000
const PRICE_MULT_CAP := 4

var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var carpet: StringName = &""
var price: int = PRICE_START


func _init(p_area: Dictionary, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


func start_msg() -> int:
	return MSG_START


## `aECPD_1st_check_init`: price for this trade, and her carpet for this talk.
func prepare() -> void:
	price = PRICE_START
	for _i: int in int(area.get("used", 0)):
		price *= 2
	set_free(0, number(price))
	carpet = FtrCatalog.pick_named("carpet", "Event", rng)
	var data: ItemData = ItemCatalog.get_item(carpet)
	context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")


## `aECPD_2nd_check`.
func picked(msg_no: int, index: int) -> int:
	if msg_no != MSG_OFFER:
		return -1
	if index != 0:
		return MSG_NO
	if not has_carpet():
		return MSG_NO_CARPET
	if inventory == null or not ShopBook.can_afford(inventory, price):
		return MSG_BROKE
	return MSG_CHOOSE


func has_carpet() -> bool:
	if inventory == null:
		return false
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inventory.slot_at(i)
		if slot != null and not slot.is_empty():
			var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
			if data != null and data.category == ItemData.Category.FLOOR:
				return true
	return false


## `aECPD_grad_message` → `mSM_OVL_INVENTORY` (`mSM_IV_OPEN_TAKE`).
func next_step() -> Dictionary:
	if current_msg == MSG_CHOOSE or current_msg == MSG_CHOOSE_AGAIN:
		return {"hand": {"pocket": -1, "mode": "take"}}
	return {}


## `aECPD_menu_close_wait` / `aECPD_demo0_end_wait`.
func hand_result(item: StringName, _pocket: int = -1) -> Dictionary:
	if item == &"":
		return msg(MSG_CHANGED_MIND)
	var data: ItemData = ItemCatalog.get_item(item)
	if data == null or data.category != ItemData.Category.FLOOR:
		## Handed straight back (`aECPD_refuse_trade_in`).
		return {"anim": {"take": item}, "then": {"anim": {"give": item}, "msg": MSG_REFUSE}}
	## `aECPD_demo0_end_wait_init`: her carpet takes the slot, the Bells go.
	area["used"] = mini(int(area.get("used", 0)) + 1, PRICE_MULT_CAP)
	inventory.remove(item, 1)
	var mine: ItemData = ItemCatalog.get_item(carpet)
	if mine != null:
		inventory.add(mine, 1)
	ShopBook.pay(inventory, price)
	return {"anim": {"take": item}, "then": {"anim": {"give": carpet}, "msg": MSG_TRADE}}
