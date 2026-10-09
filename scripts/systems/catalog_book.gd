class_name CatalogBook
extends RefCounted

## The player's catalog (`m_catalog_ovl`, `mSP_CollectCheck`): every furniture, clothing,
## wallpaper, carpet, stationery, umbrella and K.K. record that has ever reached the
## pockets, plus the Nook mail-order queue (`Private_c.catalog_orders`,
## `mPr_CATALOG_ORDER_NUM` = 5).
## Orders are paid at the counter and arrive enclosed in a letter at the next 06:00
## (`mPO_delivery_mail_with_order_ftr`). Owned by `Game`.

const ORDER_SLOTS := 5

## item_id (String) → true, in first-seen order.
var _owned: Dictionary = {}
## [{item: String, level: int}] — `mPr_catalog_order_c` (item + shop level at order time).
var _orders: Array[Dictionary] = []
## Insect types (`aINS_INSECT_TYPE_*`) ever caught: `mSM_COLLECT_INSECT_SET` keeps these in the
## same `furniture_collected_bitfield`, from bit 0x2F2.
var _insects: Dictionary = {}


func clear() -> void:
	_owned.clear()
	_orders.clear()
	_insects.clear()


static func is_catalog_item(data: ItemData) -> bool:
	if data == null:
		return false
	if data is FurnitureData:
		return true
	if data is ToolData:
		return (data as ToolData).is_stock_umbrella()
	match data.category:
		ItemData.Category.CLOTH, ItemData.Category.WALL, ItemData.Category.FLOOR:
			return true
	## K.K. records have their own page (`music_collected_bitfield`).
	return data.id == ShopGoods.PAPER or MinidiskCatalog.is_disc(data.id)


## Catalog pages keep the item even after it leaves the pockets.
func record(item_id: StringName) -> bool:
	if item_id == &"" or _owned.has(String(item_id)):
		return false
	if not is_catalog_item(ItemCatalog.get_item(item_id)):
		return false
	_owned[String(item_id)] = true
	return true


func record_inventory(inv: Inventory) -> void:
	if inv == null:
		return
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(i)
		if slot != null and not slot.is_empty():
			record(slot.item.item_id)


func has(item_id: StringName) -> bool:
	return _owned.has(String(item_id))


## `mSM_COLLECT_INSECT_SET`.
func record_insect(type_index: int) -> void:
	if type_index >= 0:
		_insects[type_index] = true


## `mSM_COLLECT_INSECT_GET`.
func has_insect(type_index: int) -> bool:
	return _insects.has(type_index)


## `mSM_CHECK_ALL_INSECT_GET_SUB`.
func insect_count() -> int:
	return _insects.size()


func owned_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _owned.keys():
		out.append(StringName(str(key)))
	return out


## `aNSC_msg_win_open_wait2`: a catalog page with no order slot is "not for sale".
static func is_orderable(data: ItemData) -> bool:
	## Records are never for sale (`mCL_music_init` price 0).
	return (is_catalog_item(data) and ShopBook.buy_price(data) > 0 and not data.shop_rare
		and not MinidiskCatalog.is_disc(data.id))


func orders() -> Array[Dictionary]:
	return _orders.duplicate(true)


func has_free_order() -> bool:
	return _orders.size() < ORDER_SLOTS


## `aNSC_set_ftr_order`. Payment is the caller's job (`ShopBook.order`).
func add_order(item_id: StringName, shop_level: int) -> bool:
	if not has_free_order():
		return false
	_orders.append({"item": String(item_id), "level": shop_level})
	return true


## Letters for every order placed before this renew; the queue empties.
func take_deliveries() -> Array[MailData]:
	var out: Array[MailData] = []
	for row: Dictionary in _orders:
		out.append(ShopMail.order_letter(StringName(str(row.get("item", ""))), int(row.get("level", 0))))
	_orders.clear()
	return out


func to_save() -> Dictionary:
	return {
		"owned": _owned.keys().duplicate(),
		"orders": _orders.duplicate(true),
		"insects": _insects.keys().duplicate(),
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data
	var owned: Variant = row.get("owned", [])
	if typeof(owned) == TYPE_ARRAY:
		for entry: Variant in owned as Array:
			_owned[str(entry)] = true
	var insects: Variant = row.get("insects", [])
	if typeof(insects) == TYPE_ARRAY:
		for entry: Variant in insects as Array:
			record_insect(int(entry))
	var orders_raw: Variant = row.get("orders", [])
	if typeof(orders_raw) == TYPE_ARRAY:
		for entry: Variant in orders_raw as Array:
			if typeof(entry) == TYPE_DICTIONARY and _orders.size() < ORDER_SLOTS:
				_orders.append((entry as Dictionary).duplicate())
