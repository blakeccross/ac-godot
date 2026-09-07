class_name TestInventory
extends GdUnitTestSuite


func test_add_and_count() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_int(inv.add(apple, 2)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(2)
	assert_int(inv.count_of_occupied()).is_equal(1)


func test_stacking_respects_max_stack() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_int(apple.max_stack).is_equal(9)
	assert_int(inv.add(apple, 10)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(10)
	assert_int(inv.count_of_occupied()).is_equal(2)
	assert_int(inv.slot_at(0).item.count).is_equal(9)
	assert_int(inv.slot_at(1).item.count).is_equal(1)


func test_tools_do_not_stack() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	assert_int(inv.add(axe, 2)).is_equal(0)
	assert_int(inv.count_of_occupied()).is_equal(2)


func test_remove() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 3)
	assert_int(inv.remove(&"apple", 2)).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(1)
	assert_int(inv.remove(&"apple", 5)).is_equal(4)
	assert_int(inv.count_of(&"apple")).is_equal(0)


func test_has_space_for_stacking() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	assert_bool(inv.has_space_for(apple, 1)).is_true()
	assert_int(inv.add(axe, Inventory.POCKET_SLOTS)).is_equal(0)
	assert_bool(inv.has_space_for(axe, 1)).is_false()
	assert_bool(inv.has_space(1)).is_false()


func test_select_and_use_fruit() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 2)
	inv.select(0)
	var msg: String = inv.use_slot(0)
	assert_str(msg).contains("Eat")
	assert_int(inv.count_of(&"apple")).is_equal(1)


func test_equip_tool() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(axe, 1)
	assert_bool(inv.equip_slot(0)).is_true()
	assert_that(inv.equipment_id).is_equal(&"axe")


func test_drop_slot() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 2)
	var removed: InventoryItem = inv.drop_slot(0, 1)
	assert_that(removed.item_id).is_equal(&"apple")
	assert_int(removed.count).is_equal(1)
	assert_int(inv.count_of(&"apple")).is_equal(1)


func test_inventory_drop_arcs_item_after_close() -> void:
	## `mTG_field_put_proc` closes the submenu; `bIT_actor_player_drop_entry` arcs from +50 GX
	## onto GetBgY(..., −1 GX).
	var src := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.gd")
	assert_str(src).contains("begin_fall")
	assert_str(src).contains("50.0 * FieldCatalog.GX_TO_METERS")
	assert_str(src).contains("FieldCollision.FG_GROUND_DIST")
	assert_str(src).contains("close()")


func test_inventory_plant_closes_then_putin_or_ground() -> void:
	## `mTG_plant_proc`: shovel+hole → putin scoop; else throw-put grow-in after close.
	var src := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.gd")
	assert_str(src).contains("take_plant_from_slot")
	assert_str(src).contains("plant_from_submenu")
	assert_str(src).contains("use_scoop")
	var player_src := FileAccess.get_file_as_string("res://scenes/actors/player.gd")
	assert_str(player_src).contains("PUTIN_SCOOP_ANIM")
	assert_str(player_src).contains("PUTIN_HOLE_EFFECT_FRAME")


func test_inventory_portrait_follows_equipment() -> void:
	## `mIV_set_player` framing + `mIV_get_player_item_anime_id` held-tool draw.
	var src := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.gd")
	assert_str(src).contains("330.0 * FieldCatalog.GX_TO_METERS")
	assert_str(src).contains("25.0 * FieldCatalog.GX_TO_METERS")
	assert_str(src).contains("HeldTool.bind")
	assert_str(src).contains("_sync_portrait_equipment")


func test_inventory_overlay_is_scene_first() -> void:
	## Pocket UI is authored in the `.tscn`; script must not rebuild layout at runtime.
	var scene := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.tscn")
	var src := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.gd")
	assert_str(scene).contains("ItemSlot0")
	assert_str(scene).contains("ItemSlot14")
	assert_str(scene).contains("MailSlot0")
	assert_str(scene).contains("MailSlot9")
	assert_str(scene).contains("PortraitClip")
	assert_str(src).contains("_wire_slot_buttons")
	assert_str(src).contains("_apply_chrome")
	assert_bool(src.contains("_rebuild_slots") or src.contains("_place_catalog_chrome")).is_false()


func test_inventory_hand_cursor_and_tabs() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.gd")
	var scene := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.tscn")
	assert_str(src).contains("hnd.glb")
	assert_str(src).contains("hnd_sasu")
	assert_str(src).contains("_setup_hand_cursor")
	assert_str(src).contains("_select_side_tab")
	assert_str(src).contains("_wire_side_tabs")
	assert_str(src).contains("_cycle_side_tab")
	assert_str(src).contains("InventoryChrome.icon_for_item")
	assert_str(src).contains("_set_slot_picture")
	assert_str(src).contains("MOUSE_FILTER_IGNORE")
	assert_str(scene).contains("mouse_filter = 2")


func test_hand_move() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(axe, 1)
	assert_bool(inv.pick_hand(0)).is_true()
	assert_int(inv.hand_index).is_equal(0)
	assert_bool(inv.place_hand(3)).is_true()
	assert_bool(inv.slot_at(0).is_empty()).is_true()
	assert_bool(inv.slot_at(3).is_empty()).is_false()


func test_wallet() -> void:
	var inv := Inventory.new()
	assert_int(inv.add_bells(500)).is_equal(500)
	assert_bool(inv.spend_bells(200)).is_true()
	assert_int(inv.wallet).is_equal(300)
	assert_bool(inv.spend_bells(999)).is_false()


func test_savings_deposit_and_withdraw() -> void:
	var inv := Inventory.new()
	inv.set_wallet(2500)
	assert_int(inv.deposit_savings(1000)).is_equal(1000)
	assert_int(inv.wallet).is_equal(1500)
	assert_int(inv.savings).is_equal(1000)
	assert_int(inv.deposit_savings(99999)).is_equal(1500)
	assert_int(inv.wallet).is_equal(0)
	assert_int(inv.savings).is_equal(2500)
	assert_int(inv.withdraw_savings(1000)).is_equal(1000)
	assert_int(inv.wallet).is_equal(1000)
	assert_int(inv.savings).is_equal(1500)
	inv.set_wallet(Inventory.WALLET_MAX)
	assert_int(inv.withdraw_savings(100)).is_equal(0)
	assert_int(inv.savings).is_equal(1500)


func test_open_money_bag_adds_bells() -> void:
	ItemCatalog.reload()
	var inv := Inventory.new()
	var bag: ItemData = ItemCatalog.get_item(&"money_100")
	assert_that(bag).is_not_null()
	inv.add(bag, 1)
	var msg: String = inv.use_slot(0)
	assert_str(msg).contains("100")
	assert_int(inv.wallet).is_equal(100)
	assert_bool(inv.slot_at(0).is_empty()).is_true()


func test_save_round_trip() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(apple, 4)
	inv.add(axe, 1)
	inv.set_wallet(1234)
	inv.set_savings(500)
	inv.set_loan(19800)
	inv.add_mail(MailData.make_send(&"filbert", "Filbert", "Hello"))
	inv.equip_slot(1)
	var other := Inventory.new()
	other.from_save(inv.to_save())
	assert_int(other.count_of(&"apple")).is_equal(4)
	assert_int(other.count_of(&"axe")).is_equal(1)
	assert_int(other.wallet).is_equal(1234)
	assert_int(other.savings).is_equal(500)
	assert_int(other.loan).is_equal(19800)
	assert_int(other.count_mail()).is_equal(1)
	assert_that(other.equipment_id).is_equal(&"axe")


func test_mail_slots() -> void:
	var inv := Inventory.new()
	assert_int(inv.empty_mail_slot_count()).is_equal(Inventory.MAIL_SLOTS)
	assert_int(inv.add_mail(MailData.make_send(&"filbert", "Filbert", "Hi"))).is_equal(0)
	assert_int(inv.count_mail()).is_equal(1)
	assert_int(inv.sendable_mail_indices().size()).is_equal(1)
	var taken: MailData = inv.remove_mail(0)
	assert_str(taken.recipient_name).is_equal("Filbert")
	assert_int(inv.count_mail()).is_equal(0)


func test_loan_repay() -> void:
	var inv := Inventory.new()
	inv.set_wallet(3000)
	inv.set_loan(5000)
	assert_int(inv.repay_loan(1000)).is_equal(1000)
	assert_int(inv.loan).is_equal(4000)
	assert_bool(inv.has_bank_account()).is_false()
	inv.set_loan(0)
	assert_bool(inv.has_bank_account()).is_true()


func test_legacy_array_save() -> void:
	var inv := Inventory.new()
	inv.from_save([{ "id": "apple", "count": 1 }, { "id": "axe", "count": 1 }])
	assert_int(inv.count_of(&"apple")).is_equal(1)
	assert_int(inv.count_of(&"axe")).is_equal(1)


func test_plant_tag_for_sapling() -> void:
	ItemCatalog.reload()
	var inv := Inventory.new()
	var sapling: ItemData = ItemCatalog.get_item(&"apple_sapling")
	inv.add(sapling, 1)
	var tags: PackedStringArray = inv.tags_for_slot(0)
	assert_bool("Plant" in tags).is_true()
	assert_bool("Eat" in tags).is_false()
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	inv.add(apple, 1)
	var eat_tags: PackedStringArray = inv.tags_for_slot(1)
	assert_bool("Eat" in eat_tags).is_true()
	assert_bool("Plant" in eat_tags).is_false()


func test_item_catalog() -> void:
	ItemCatalog.reload()
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	assert_object(apple).is_not_null()
	assert_str(apple.display_name).is_equal("Apple")
	var net: ToolData = ItemCatalog.get_item(&"net") as ToolData
	assert_object(net).is_not_null()
	assert_that(net.kind).is_equal(ToolData.Kind.NET)


func test_inventory_chrome_resolves_item_icons() -> void:
	## Category sprites live under generated textures when the disc pipeline has run.
	InventoryChrome.clear_cache()
	ItemCatalog.reload()
	var axe: ItemData = ItemCatalog.get_item(&"axe")
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	var axe_icon: Texture2D = InventoryChrome.icon_for_item(axe)
	var apple_icon: Texture2D = InventoryChrome.icon_for_item(apple)
	var present_icon: Texture2D = InventoryChrome.icon_for_item(
		apple, InventoryItem.Condition.PRESENT
	)
	if ResourceLoader.exists("res://assets/generated/textures/rel/obj_item_axe_tex.png"):
		assert_object(axe_icon).is_not_null()
		assert_object(apple_icon).is_not_null()
		assert_object(present_icon).is_not_null()
		assert_str(axe_icon.resource_path).contains("obj_item_axe")
		assert_str(apple_icon.resource_path).contains("obj_item_apple")
	elif ResourceLoader.exists("res://assets/generated/textures/rel/inv_mwin_ono_tex.png"):
		assert_object(axe_icon).is_not_null()
		assert_object(apple_icon).is_not_null()
	else:
		## No disc extract in CI — resolver still returns without error.
		assert_bool(true).is_true()


func test_inventory_overlay_assigns_slot_icons() -> void:
	## Live overlay must put pictures on pocket buttons, not just resolve textures.
	if not ResourceLoader.exists("res://assets/generated/textures/rel/obj_item_axe_tex.png"):
		return
	InventoryChrome.clear_cache()
	ItemCatalog.reload()
	var packed: PackedScene = load("res://scenes/ui/inventory_overlay.tscn") as PackedScene
	var overlay: CanvasLayer = auto_free(packed.instantiate()) as CanvasLayer
	add_child(overlay)
	await get_tree().process_frame
	Game.inventory.clear()
	assert_int(Game.inventory.add(ItemCatalog.get_item(&"axe"), 1)).is_equal(0)
	assert_int(Game.inventory.add(ItemCatalog.get_item(&"apple"), 3)).is_equal(0)
	assert_int(Game.inventory.add(ItemCatalog.get_item(&"shovel"), 1)).is_equal(0)
	overlay.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	for i: int in 3:
		var btn: Button = overlay.get_node("%%ItemSlot%d" % i) as Button
		assert_object(btn).is_not_null()
		var pic: TextureRect = btn.get_node_or_null("ItemIcon") as TextureRect
		assert_object(pic).is_not_null()
		assert_object(pic.texture).is_not_null()
		assert_bool(pic.visible).is_true()
	var axe_pic: TextureRect = (
		overlay.get_node("%ItemSlot0").get_node_or_null("ItemIcon") as TextureRect
	)
	assert_str(axe_pic.texture.resource_path).contains("obj_item_axe")
	var apple_pic: TextureRect = (
		overlay.get_node("%ItemSlot1").get_node_or_null("ItemIcon") as TextureRect
	)
	assert_str(apple_pic.texture.resource_path).contains("obj_item_apple")
	var empty: Button = overlay.get_node("%ItemSlot5") as Button
	var empty_pic: TextureRect = empty.get_node_or_null("ItemIcon") as TextureRect
	assert_object(empty_pic).is_not_null()
	assert_bool(empty_pic.visible).is_false()
	## Hand cursor should stay smaller than a pocket slot (~75px).
	var src := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.gd")
	assert_str(src).contains("HAND_SIZE := 56.0")
	overlay.call("close")
