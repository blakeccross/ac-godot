class_name PocketRequests
extends RefCounted

## Four ways a talk or a piece of furniture asks the player to pick something from their
## pockets. Each request opens the inventory overlay and ends in one `*_resolved` signal:
## with the pick, or with nothing if the pockets close first.

## A villager asked for an item (`mSM_IV_OPEN_QUEST` / `_TAKE`). `handover_pocket` is the only
## pocket offered; `handover_mode` "fish" / "insect" offers any fish / bug instead.
signal handover_resolved(item_id: StringName, pocket: int)
## Blathers wants a donation (`mMmd` IV_OPEN).
signal donation_resolved(donated: bool)
## Nook's "I want to sell" (`mSM_IV_OPEN_SELL`).
signal sell_resolved(picked: bool)
## A drawer or music player wants something put in (`mSM_IV_OPEN_PUTIN_FTR` / `_MINIDISK`).
signal putin_resolved(item_id: StringName)

var handover_pending: bool = false
var handover_pocket: int = -1
var handover_mode: String = "quest"

var donation_pending: bool = false
## The last outcome of `MuseumDonation.donate`, for Blathers' reply.
var donation_result: Dictionary = {}

var sell_pending: bool = false
## Pocket slots picked by "Sell" / "Sell all".
var sell_slots: Array[int] = []

var putin_pending: bool = false
## `&"any"`, `&"minidisk"` or `&"code_gift"`.
var putin_filter: StringName = &"any"


func clear() -> void:
	handover_pending = false
	donation_pending = false
	donation_result = {}
	sell_pending = false
	sell_slots = []
	putin_pending = false


## The pockets closed: whichever request was waiting resolves empty-handed.
func cancel_all() -> void:
	cancel_donation()
	cancel_sell()
	cancel_putin()
	cancel_handover()


## Open the pockets so the player hands a villager their item.
func request_handover(pocket: int, mode: String = "quest") -> void:
	handover_pending = true
	handover_pocket = pocket
	handover_mode = mode
	if not _open_pockets():
		cancel_handover()


## May this pocket be handed over right now?
func handover_allows(pocket: int) -> bool:
	if not handover_pending:
		return false
	var slot: InventorySlot = Game.inventory.slot_at(pocket)
	if slot == null or slot.is_empty():
		return false
	match handover_mode:
		"fish":
			return _category_of(slot) == ItemData.Category.FISH
		"insect":
			return _category_of(slot) == ItemData.Category.BUG
		"take":
			## `mSM_IV_OPEN_TAKE`: any pocket (the peddler checks what it is).
			return true
		"shrine":
			## `mSM_IV_OPEN_SHRINE`: only quest items can go down the wishing well.
			return slot.item.condition == InventoryItem.Condition.QUEST
	return pocket == handover_pocket


func take_handover(pocket: int) -> void:
	if not handover_pending:
		return
	handover_pending = false
	var slot: InventorySlot = Game.inventory.slot_at(pocket)
	var item_id: StringName = slot.item.item_id if slot != null and not slot.is_empty() else &""
	handover_resolved.emit(item_id, pocket)


func cancel_handover() -> void:
	if not handover_pending:
		return
	handover_pending = false
	handover_resolved.emit(&"", -1)


func request_donation() -> void:
	donation_pending = true
	donation_result = {}
	_open_pockets()


## The player picked an item. Books the outcome and tells Blathers to respond; a rejection
## does not consume the item.
func take_donation(item_id: StringName) -> void:
	if not donation_pending:
		return
	donation_pending = false
	donation_result = MuseumDonation.donate(item_id)
	donation_result["item_id"] = String(item_id)
	donation_resolved.emit(true)


func cancel_donation() -> void:
	if not donation_pending:
		return
	donation_pending = false
	donation_result = {}
	donation_resolved.emit(false)


## Nook opens the pockets in sell mode (`aNSC_buy_menu_close_wait_init`).
func request_sell() -> void:
	sell_pending = true
	sell_slots = []
	_open_pockets()


func take_sell(slots: Array[int]) -> void:
	if not sell_pending:
		return
	sell_pending = false
	sell_slots = slots
	sell_resolved.emit(not slots.is_empty())


func cancel_sell() -> void:
	if not sell_pending:
		return
	sell_pending = false
	sell_slots = []
	sell_resolved.emit(false)


func request_putin(filter: StringName = &"any") -> void:
	putin_pending = true
	putin_filter = filter
	if not _open_pockets():
		cancel_putin()


func take_putin(item_id: StringName) -> void:
	if not putin_pending:
		return
	putin_pending = false
	putin_resolved.emit(item_id)


func cancel_putin() -> void:
	if not putin_pending:
		return
	putin_pending = false
	putin_resolved.emit(&"")


func _open_pockets() -> bool:
	var tree: SceneTree = Game.get_tree()
	if tree == null:
		return false
	var overlay: InventoryOverlay = InventoryOverlay.find(tree)
	if overlay == null:
		return false
	overlay.open()
	return true


func _category_of(slot: InventorySlot) -> int:
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	return data.category if data != null else -1
