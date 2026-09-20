class_name Inventory
extends RefCounted

## Player pockets. 15 slots in a 5×3 grid (`mIV_ITEM_COLUMNS` / `mIV_ITEM_ROWS`).
## Stacking is data-driven via `ItemData.max_stack` (tools stay at 1).

const POCKET_SLOTS := 15
const MAIL_SLOTS := 10
const COLUMNS := 5
const ROWS := 3
## Letters sit in a tall 2×5 on the pocket paper (`inv_mwin` right column).
const MAIL_COLUMNS := 2
const MAIL_ROWS := 5
const WALLET_MAX := 99999
## First house loan (`mPr` / Nook). 0 once paid — bank account unlocks.
const DEFAULT_HOUSE_LOAN := 19800
## Debt left after the intro down payment (`mPlayer_DEBT0`, m_player.h). Nook takes
## the starting 1,000-bell bag on the station acre, then this is what you owe.
const INTRO_HOUSE_DEBT := 17400

signal changed
signal selection_changed(index: int)
signal wallet_changed(amount: int)
signal savings_changed(amount: int)
signal loan_changed(amount: int)
signal mail_changed
signal equipment_changed(item_id: StringName)
signal background_changed(item_id: StringName)

## Bag denominations (`ITM_MONEY_START`) — withdrawing produces one of these as a
## physical pocket item (`mTG_select_tag_decide_money`). Listed high→low; the popup
## only offers what the wallet can currently afford at each threshold.
const BAG_ITEM_IDS := {
	30000: &"money_30000",
	10000: &"money_10000",
	1000: &"money_1000",
	100: &"money_100",
}

var wallet: int = 0
## Post office savings (`mPr` bank after loans). No interest in this slice.
var savings: int = 0
## House loan owed to Nook (`Private_c.inventory.loan`).
var loan: int = 0
var equipment_id: StringName = &""
## Pockets-menu backdrop (`Now_Private->backgound_texture`, `mTG_TABLE_BG`). "" = default.
var background_id: StringName = &""
var selected_index: int = 0
var selected_mail_index: int = 0
## Hand hold (`m_hand_ovl` hold_idx). -1 = empty hand.
var hand_index: int = -1
## Multi-select marks (`mTG_mark_proc`, X button). Cleared on page switch / table switch
## by the UI layer, matching `mTG_mark_main_CLR`.
var _marked: Dictionary = {}

var _slots: Array[InventorySlot] = []
var _mail: Array[MailData] = []


func _init() -> void:
	_slots.clear()
	for i: int in POCKET_SLOTS:
		_slots.append(InventorySlot.new(i))
	_mail.clear()
	for _i: int in MAIL_SLOTS:
		_mail.append(MailData.new())


func clear() -> void:
	for slot: InventorySlot in _slots:
		slot.clear()
	for i: int in MAIL_SLOTS:
		_mail[i] = MailData.new()
	wallet = 0
	savings = 0
	loan = 0
	equipment_id = &""
	background_id = &""
	selected_index = 0
	selected_mail_index = 0
	hand_index = -1
	_marked.clear()
	changed.emit()
	selection_changed.emit(selected_index)
	wallet_changed.emit(wallet)
	savings_changed.emit(savings)
	loan_changed.emit(loan)
	mail_changed.emit()
	equipment_changed.emit(equipment_id)
	background_changed.emit(background_id)


func slot_at(index: int) -> InventorySlot:
	if index < 0 or index >= POCKET_SLOTS:
		return null
	return _slots[index]


func selected_slot() -> InventorySlot:
	return slot_at(selected_index)


func select(index: int) -> void:
	if index < 0 or index >= POCKET_SLOTS:
		return
	if selected_index == index:
		return
	selected_index = index
	selection_changed.emit(selected_index)


func move_cursor(dx: int, dy: int) -> void:
	var col: int = selected_index % COLUMNS
	var row: int = selected_index / COLUMNS
	col = clampi(col + dx, 0, COLUMNS - 1)
	row = clampi(row + dy, 0, ROWS - 1)
	select(row * COLUMNS + col)


## Returns leftover count that did not fit.
func add(item: ItemData, count: int = 1, condition: InventoryItem.Condition = InventoryItem.Condition.NORMAL) -> int:
	if item == null or item.id == &"" or count <= 0:
		return count
	## `mIV_set_collect_itemNo` reads the "obtained once" bitfield — a fish/bug
	## registers in the encyclopedia the moment it first reaches the pockets.
	if (item is FishData or item is BugData) and Game != null and Game.species_log != null:
		Game.species_log.record(item.id)
	var remaining: int = count
	var max_stack: int = maxi(1, item.max_stack)

	if max_stack > 1:
		for slot: InventorySlot in _slots:
			if slot.is_empty():
				continue
			var stack: InventoryItem = slot.item
			if stack.item_id != item.id or stack.condition != condition:
				continue
			var room: int = max_stack - stack.count
			if room <= 0:
				continue
			var put: int = mini(room, remaining)
			stack.count += put
			remaining -= put
			if remaining == 0:
				changed.emit()
				return 0

	for slot: InventorySlot in _slots:
		if not slot.is_empty():
			continue
		var put: int = mini(max_stack, remaining)
		slot.set_stack(item.id, put, condition)
		remaining -= put
		if remaining == 0:
			changed.emit()
			return 0

	changed.emit()
	return remaining


func remove(item_id: StringName, count: int = 1) -> int:
	if item_id == &"" or count <= 0:
		return count
	var remaining: int = count
	for i: int in range(POCKET_SLOTS - 1, -1, -1):
		var slot: InventorySlot = _slots[i]
		if slot.is_empty() or slot.item.item_id != item_id:
			continue
		var take: int = mini(slot.item.count, remaining)
		slot.item.count -= take
		remaining -= take
		if slot.item.count <= 0:
			slot.clear()
			if hand_index == i:
				hand_index = -1
			_marked.erase(i)
		if remaining == 0:
			changed.emit()
			return 0
	changed.emit()
	return remaining


func remove_from_slot(index: int, count: int = 1) -> InventoryItem:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty() or count <= 0:
		return InventoryItem.new()
	var take: int = mini(slot.item.count, count)
	var removed := InventoryItem.new(slot.item.item_id, take, slot.item.condition)
	slot.item.count -= take
	if slot.item.count <= 0:
		slot.clear()
		if hand_index == index:
			hand_index = -1
		_marked.erase(index)
	changed.emit()
	return removed


func count_of(item_id: StringName) -> int:
	var total: int = 0
	for slot: InventorySlot in _slots:
		if not slot.is_empty() and slot.item.item_id == item_id:
			total += slot.item.count
	return total


func has_space_for(item: ItemData, count: int = 1) -> bool:
	if item == null or count <= 0:
		return false
	return add_would_fit(item, count)


func add_would_fit(item: ItemData, count: int) -> bool:
	if item == null or count <= 0:
		return false
	var remaining: int = count
	var max_stack: int = maxi(1, item.max_stack)
	for slot: InventorySlot in _slots:
		if slot.is_empty():
			remaining -= max_stack
		elif slot.item.item_id == item.id and slot.item.condition == InventoryItem.Condition.NORMAL:
			remaining -= maxi(0, max_stack - slot.item.count)
		if remaining <= 0:
			return true
	return false


func has_space(count: int = 1) -> bool:
	## Backward-compatible: enough empty slots for `count` non-stacking inserts.
	return empty_slot_count() >= count


func empty_slot_count() -> int:
	var n: int = 0
	for slot: InventorySlot in _slots:
		if slot.is_empty():
			n += 1
	return n


func is_empty() -> bool:
	return count_of_occupied() == 0


func count_of_occupied() -> int:
	var n: int = 0
	for slot: InventorySlot in _slots:
		if not slot.is_empty():
			n += 1
	return n


func set_wallet(amount: int) -> void:
	var next: int = clampi(amount, 0, WALLET_MAX)
	if wallet == next:
		return
	wallet = next
	wallet_changed.emit(wallet)
	changed.emit()


func add_bells(amount: int) -> int:
	if amount <= 0:
		return 0
	var before: int = wallet
	set_wallet(wallet + amount)
	return wallet - before


func spend_bells(amount: int) -> bool:
	if amount <= 0:
		return true
	if wallet < amount:
		return false
	set_wallet(wallet - amount)
	return true


func set_savings(amount: int) -> void:
	var next: int = maxi(amount, 0)
	if savings == next:
		return
	savings = next
	savings_changed.emit(savings)
	changed.emit()


## Move bells from wallet into savings. Returns amount deposited.
func deposit_savings(amount: int) -> int:
	if amount <= 0:
		return 0
	var put: int = mini(amount, wallet)
	if put <= 0:
		return 0
	set_wallet(wallet - put)
	set_savings(savings + put)
	return put


## Move bells from savings into wallet (wallet cap). Returns amount withdrawn.
func withdraw_savings(amount: int) -> int:
	if amount <= 0:
		return 0
	var room: int = WALLET_MAX - wallet
	var take: int = mini(amount, mini(savings, room))
	if take <= 0:
		return 0
	set_savings(savings - take)
	set_wallet(wallet + take)
	return take


func set_loan(amount: int) -> void:
	var next: int = maxi(amount, 0)
	if loan == next:
		return
	loan = next
	loan_changed.emit(loan)
	changed.emit()


## Pay loan from wallet. Returns amount applied.
func repay_loan(amount: int) -> int:
	if amount <= 0 or loan <= 0:
		return 0
	var pay: int = mini(amount, mini(loan, wallet))
	if pay <= 0:
		return 0
	set_wallet(wallet - pay)
	set_loan(loan - pay)
	return pay


func has_bank_account() -> bool:
	## Bank unlocks after the house loan is cleared (`aPG_set_post_status` HAS_BANK).
	return loan <= 0


func mail_at(index: int) -> MailData:
	if index < 0 or index >= MAIL_SLOTS:
		return null
	return _mail[index]


## `mMB_get_last_mail_idx` (`m_mailbox_ovl.c`): scans backward from the last slot for the
## first occupied one, so the mailbox overlay's cursor lands on the newest letter instead
## of always resetting to slot 0. Falls back to slot 0 when every slot is empty.
func last_used_mail_index() -> int:
	var idx: int = MAIL_SLOTS
	while true:
		idx -= 1
		var mail: MailData = mail_at(idx)
		if (mail != null and not mail.is_empty()) or idx == 0:
			break
	return idx


func select_mail(index: int) -> void:
	if index < 0 or index >= MAIL_SLOTS:
		return
	if selected_mail_index == index:
		return
	selected_mail_index = index
	mail_changed.emit()


func move_mail_cursor(dx: int, dy: int) -> void:
	var col: int = selected_mail_index % MAIL_COLUMNS
	var row: int = selected_mail_index / MAIL_COLUMNS
	col = clampi(col + dx, 0, MAIL_COLUMNS - 1)
	row = clampi(row + dy, 0, MAIL_ROWS - 1)
	select_mail(row * MAIL_COLUMNS + col)


func empty_mail_slot_count() -> int:
	var n: int = 0
	for mail: MailData in _mail:
		if mail == null or mail.is_empty():
			n += 1
	return n


func count_mail() -> int:
	return MAIL_SLOTS - empty_mail_slot_count()


## Delivered letters sitting in the mailbox (`RECV*` fonts).
func received_mail_count() -> int:
	var n: int = 0
	for mail: MailData in _mail:
		if mail != null and not mail.is_empty() and mail.is_received():
			n += 1
	return n


## Delivered letters the player has not opened yet.
func unread_mail_count() -> int:
	var n: int = 0
	for mail: MailData in _mail:
		if mail == null or mail.is_empty() or not mail.is_received():
			continue
		if mail.font == MailData.LetterFont.RECV or mail.font == MailData.LetterFont.RECV_PRESENT:
			n += 1
	return n


## Returns slot index or -1.
func add_mail(mail: MailData) -> int:
	if mail == null or mail.is_empty():
		return -1
	for i: int in MAIL_SLOTS:
		if _mail[i] == null or _mail[i].is_empty():
			_mail[i] = mail.duplicate_mail()
			mail_changed.emit()
			changed.emit()
			return i
	return -1


## Deliver a letter from an NPC / service into the mailbox (`RECV*` fonts). Returns slot
## index or -1 when the mailbox is full.
func add_received_mail(mail: MailData) -> int:
	if mail == null or mail.is_empty():
		return -1
	for i: int in MAIL_SLOTS:
		if _mail[i] == null or _mail[i].is_empty():
			_mail[i] = mail.duplicate_mail()
			mail_changed.emit()
			changed.emit()
			return i
	return -1


func remove_mail(index: int) -> MailData:
	var mail: MailData = mail_at(index)
	if mail == null or mail.is_empty():
		return MailData.new()
	var taken: MailData = mail.duplicate_mail()
	_mail[index] = MailData.new()
	mail_changed.emit()
	changed.emit()
	return taken


func sendable_mail_indices() -> Array[int]:
	var out: Array[int] = []
	for i: int in MAIL_SLOTS:
		var mail: MailData = _mail[i]
		if mail != null and mail.is_sendable():
			out.append(i)
	return out


func equip_slot(index: int) -> bool:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return false
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null or not data.equippable:
		return false
	if slot.item.condition != InventoryItem.Condition.NORMAL:
		return false
	equipment_id = slot.item.item_id
	equipment_changed.emit(equipment_id)
	changed.emit()
	return true


func unequip() -> void:
	if equipment_id == &"":
		return
	equipment_id = &""
	equipment_changed.emit(equipment_id)
	changed.emit()


## Decomp `backgound_texture`: any owned shirt (`Category.CLOTH`) reskins the pockets
## backdrop with its real pattern, independent of what the player is currently
## wearing (`mHD_open_end_proc_item_type4`); empty id clears it back to the default.
func set_background(item_id: StringName) -> void:
	if background_id == item_id:
		return
	background_id = item_id
	background_changed.emit(background_id)
	changed.emit()


## `mTG_mark_proc` (X button). Toggling an empty slot is a no-op — nothing to bulk-act on.
func toggle_mark(index: int) -> bool:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return false
	if _marked.has(index):
		_marked.erase(index)
	else:
		_marked[index] = true
	changed.emit()
	return _marked.has(index)


func is_marked(index: int) -> bool:
	return _marked.has(index)


## `mTG_mark_main_CLR` — page switch / table switch (items ↔ mail) clears every mark.
func clear_marks() -> void:
	if _marked.is_empty():
		return
	_marked.clear()
	changed.emit()


func marked_indices() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _marked:
		out.append(int(key))
	out.sort()
	return out


## Turn a normal stack into a gift-wrapped one in place (`mTG_TYPE_TAG` wrap, reverse of
## the existing "Open" tag). Money, mail-only items, and anything not droppable can't be
## wrapped — mirrors decomp's giftable-item gating closely enough without new per-item data.
func wrap_slot(index: int) -> bool:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return false
	if slot.item.condition != InventoryItem.Condition.NORMAL:
		return false
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null or not data.droppable or data.bell_value > 0:
		return false
	slot.item.condition = InventoryItem.Condition.PRESENT
	changed.emit()
	return true


## `mTG_select_tag_decide_money` thresholds: showing denomination `d` requires
## `wallet >= d`, which — because the four amounts are nested (100 < 1000 < 10000 <
## 30000) — reproduces decomp's exact bracket behavior (≥30000 offers all four, ≥10000
## offers 100/1000/10000, ≥1000 offers 100/1000, ≥100 offers only 100, below 100 offers
## none) without needing to special-case each bracket.
func withdrawable_denominations() -> Array[int]:
	var out: Array[int] = []
	for amount: int in [30000, 10000, 1000, 100]:
		if wallet >= amount:
			out.append(amount)
	return out


## Spend `amount` and place the matching money-bag item straight into the hand, ready to
## be placed like anything else that was just picked up (`m_hand_ovl`'s withdraw flow).
## Fails if the amount isn't a valid denomination, can't be afforded, the hand is already
## full, or pockets have no empty slot.
func withdraw_to_hand(amount: int) -> bool:
	if hand_index != -1 or not BAG_ITEM_IDS.has(amount) or wallet < amount:
		return false
	var target: int = -1
	for i: int in POCKET_SLOTS:
		if _slots[i].is_empty():
			target = i
			break
	if target == -1:
		return false
	if not spend_bells(amount):
		return false
	_slots[target].set_stack(BAG_ITEM_IDS[amount], 1, InventoryItem.Condition.NORMAL)
	hand_index = target
	select(target)
	changed.emit()
	return true


## Returns use verb result text, or "" if nothing happened.
func use_slot(index: int) -> String:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return ""
	if slot.item.condition != InventoryItem.Condition.NORMAL:
		return ""
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null:
		return ""
	if data.equippable:
		if equip_slot(index):
			return "Equipped %s" % data.display_name
		return ""
	if not data.usable:
		return ""
	var removed: InventoryItem = remove_from_slot(index, 1)
	if removed.is_empty():
		return ""
	if data.bell_value > 0:
		add_bells(data.bell_value)
		return "Opened %s (+%d Bells)" % [data.display_name, data.bell_value]
	var verb: String = data.use_verb if data.use_verb != "" else "Used"
	return "%s %s" % [verb, data.display_name]


## Pull one (or `count`) from a slot for dropping into the world.
func drop_slot(index: int, count: int = 1) -> InventoryItem:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return InventoryItem.new()
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data != null and not data.droppable:
		return InventoryItem.new()
	if slot.item.condition == InventoryItem.Condition.QUEST:
		return InventoryItem.new()
	return remove_from_slot(index, count)


func pick_hand(index: int) -> bool:
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return false
	hand_index = index
	select(index)
	changed.emit()
	return true


func clear_hand() -> void:
	if hand_index < 0:
		return
	hand_index = -1
	changed.emit()


## Place/swap hand contents onto `target_index` (`m_hand_ovl` put).
func place_hand(target_index: int) -> bool:
	if hand_index < 0 or hand_index >= POCKET_SLOTS:
		return false
	if target_index < 0 or target_index >= POCKET_SLOTS:
		return false
	if hand_index == target_index:
		clear_hand()
		return true
	var from: InventorySlot = _slots[hand_index]
	var to: InventorySlot = _slots[target_index]
	if from.is_empty():
		clear_hand()
		return false
	if to.is_empty():
		to.item = from.item
		from.clear()
	else:
		var tmp: InventoryItem = to.item
		to.item = from.item
		from.item = tmp
	## Marks track the item, not the slot — follow it through the swap.
	var from_marked: bool = _marked.has(hand_index)
	var to_marked: bool = _marked.has(target_index)
	_marked.erase(hand_index)
	_marked.erase(target_index)
	if from_marked:
		_marked[target_index] = true
	if to_marked:
		_marked[hand_index] = true
	hand_index = -1
	select(target_index)
	changed.emit()
	return true


func tags_for_slot(index: int) -> PackedStringArray:
	## Field-default style verbs from `m_tag_ovl` (simplified).
	var tags: PackedStringArray = []
	var slot: InventorySlot = slot_at(index)
	if slot == null or slot.is_empty():
		return tags
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null:
		return tags
	if slot.item.condition == InventoryItem.Condition.PRESENT:
		tags.append("Open")
		return tags
	if slot.item.condition == InventoryItem.Condition.QUEST:
		## Intro down payment (`aNRG_menu_open_wait_talk_proc`): the money bag is the
		## only pocket item Nook will take on the station acre.
		if (
			Game != null
			and Game.intro_payment_pending
			and slot.item.item_id == &"money_1000"
		):
			tags.append("Hand over")
		return tags
	## A drawer or music player opened the pockets (`mTG_TYPE_PUTIN_ITEM`).
	if Game != null and Game.storage_putin_pending:
		if putin_allowed(data, Game.storage_putin_filter):
			tags.append("Put in")
		return tags
	## Blathers opened the pockets to receive a donation (`mMmd` IV_OPEN).
	if Game != null and Game.museum_donate_pending and MuseumDialogue.is_offerable(data):
		tags.append("Donate")
		return tags
	if data.equippable:
		## Decomp's equip slot is a swap (drop empty hand on it to clear); this port has no
		## separate equip slot to drop onto, so offer the reverse verb straight from the
		## item itself once it's the one currently equipped.
		tags.append("Unequip" if slot.item.item_id == equipment_id else "Equip")
	if data.category == ItemData.Category.CLOTH:
		tags.append("Wear")
		## `mTG_TABLE_BG` / decomp `backgound_texture`: the menu paper background is any
		## owned shirt's pattern, not a wallpaper item — simplified from decomp's
		## hand-drop-on-slot gesture to a tag, matching how this port already offers
		## "Equip"/"Wear" from the item itself rather than a drop target.
		tags.append("Set Background")
	if data.plant_id != &"":
		tags.append("Plant")
	elif data.usable:
		tags.append(data.use_verb if data.use_verb != "" else "Use")
	if data is FurnitureData and Game.is_decorating():
		tags.append("Place")
	if data.category == ItemData.Category.WALL:
		if Game.is_decorating():
			tags.append("Hang")
	if data.category == ItemData.Category.FLOOR and Game.is_decorating():
		tags.append("Lay")
	if data.droppable:
		## `mTG_TYPE_TAG_PUT_ALL`: a marked slot drops every marked item at once.
		tags.append("Drop All" if is_marked(index) else "Drop")
	if data.droppable and data.bell_value <= 0:
		tags.append("Wrap")
	tags.append("Move")
	return tags


## What a furniture "put in" prompt accepts: anything, or only K.K. discs for a music player.
static func putin_allowed(data: ItemData, filter: StringName) -> bool:
	if data == null:
		return false
	if filter == &"minidisk":
		return MinidiskCatalog.is_disc(data.id)
	return true


## `mSM_check_open_inventory_itemlist`: is there anything in the pockets to offer?
func has_putin_candidates(filter: StringName = &"any") -> bool:
	for slot: InventorySlot in _slots:
		if slot == null or slot.is_empty():
			continue
		if putin_allowed(ItemCatalog.get_item(slot.item.item_id), filter):
			return true
	return false


func to_save() -> Dictionary:
	var rows: Array = []
	for slot: InventorySlot in _slots:
		rows.append(slot.to_save())
	var mail_rows: Array = []
	for mail: MailData in _mail:
		if mail == null or mail.is_empty():
			mail_rows.append({})
		else:
			mail_rows.append(mail.to_save())
	return {
		"slots": rows,
		"mail": mail_rows,
		"wallet": wallet,
		"savings": savings,
		"loan": loan,
		"equipment": String(equipment_id),
		"background": String(background_id),
		"selected": selected_index,
		"selected_mail": selected_mail_index,
	}


func from_save(data: Variant) -> void:
	## Accepts new dict shape or legacy Array-of-slot-dicts.
	clear()
	var rows: Array = []
	if typeof(data) == TYPE_ARRAY:
		rows = data
	elif typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		var slots_v: Variant = d.get("slots", [])
		if typeof(slots_v) == TYPE_ARRAY:
			rows = slots_v
		set_wallet(int(d.get("wallet", 0)))
		set_savings(int(d.get("savings", 0)))
		set_loan(int(d.get("loan", 0)))
		equipment_id = StringName(str(d.get("equipment", "")))
		background_id = StringName(str(d.get("background", "")))
		selected_index = clampi(int(d.get("selected", 0)), 0, POCKET_SLOTS - 1)
		selected_mail_index = clampi(int(d.get("selected_mail", 0)), 0, MAIL_SLOTS - 1)
		var mail_v: Variant = d.get("mail", [])
		if typeof(mail_v) == TYPE_ARRAY:
			var mi: int = 0
			for entry: Variant in mail_v as Array:
				if mi >= MAIL_SLOTS:
					break
				var loaded_mail: MailData = MailData.from_save(entry)
				_mail[mi] = loaded_mail if not loaded_mail.is_empty() else MailData.new()
				mi += 1
	var i: int = 0
	for row: Variant in rows:
		if i >= POCKET_SLOTS:
			break
		if typeof(row) != TYPE_DICTIONARY:
			i += 1
			continue
		var loaded: InventoryItem = InventoryItem.from_save(row as Dictionary)
		if loaded.is_empty():
			_slots[i].clear()
		else:
			var data_item: ItemData = ItemCatalog.get_item(loaded.item_id)
			var max_stack: int = maxi(1, data_item.max_stack) if data_item != null else 1
			loaded.count = clampi(loaded.count, 1, max_stack)
			_slots[i].item = loaded
		i += 1
	changed.emit()
	selection_changed.emit(selected_index)
	wallet_changed.emit(wallet)
	savings_changed.emit(savings)
	loan_changed.emit(loan)
	mail_changed.emit()
	equipment_changed.emit(equipment_id)
	background_changed.emit(background_id)
