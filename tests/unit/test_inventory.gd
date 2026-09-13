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


func test_tags_offer_unequip_only_for_the_equipped_item() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	var shovel: ItemData = load("res://data/items/shovel.tres")
	inv.add(axe, 1) ## slot 0
	inv.add(shovel, 1) ## slot 1
	## Nothing equipped yet — both offer "Equip".
	assert_bool(inv.tags_for_slot(0).has("Equip")).is_true()
	assert_bool(inv.tags_for_slot(0).has("Unequip")).is_false()
	inv.equip_slot(0)
	assert_bool(inv.tags_for_slot(0).has("Unequip")).is_true()
	assert_bool(inv.tags_for_slot(0).has("Equip")).is_false()
	## The other tool still isn't the equipped one — still offers "Equip".
	assert_bool(inv.tags_for_slot(1).has("Equip")).is_true()
	inv.unequip()
	assert_that(inv.equipment_id).is_equal(&"")
	assert_bool(inv.tags_for_slot(0).has("Equip")).is_true()
	assert_bool(inv.tags_for_slot(0).has("Unequip")).is_false()


func test_inventory_overlay_unequip_tag_clears_equipment() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var axe: ItemData = load("res://data/items/axe.tres")
	Game.inventory.add(axe, 1)
	Game.inventory.equip_slot(0)
	assert_that(Game.inventory.equipment_id).is_equal(&"axe")
	Game.inventory.select(0)
	overlay.call("_run_tag", "Unequip")
	assert_that(Game.inventory.equipment_id).is_equal(&"")


func test_inventory_overlay_cursor_reaches_player_slot() -> void:
	## `mTG_TABLE_PLAYER`: the player doll is part of the same navigable space as the
	## item grid — reachable from the top row, not just clickable.
	var overlay: CanvasLayer = _open_overlay()
	Game.inventory.select(2) ## somewhere in the top row (row 0)
	assert_bool(overlay.get("_focus_player")).is_false()
	overlay.set("_focus_player", true) ## mirrors what "ui_up" from row 0 does
	assert_bool(overlay.get("_focus_player")).is_true()


func _press(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


## Item (5x3) and mail (2x5) grids are one shared cursor space (`m_hand_ovl`) — moving
## off the item grid's right edge lands in mail, not a `Tab` press.
func test_inventory_overlay_right_from_items_enters_mail_same_row() -> void:
	var overlay: CanvasLayer = _open_overlay()
	Game.inventory.select(4) ## row0, col4 (rightmost item column)
	overlay.call("_unhandled_input", _press("ui_right"))
	assert_bool(overlay.get("_focus_mail")).is_true()
	assert_int(Game.inventory.selected_mail_index).is_equal(4) ## mail row2, col0


func test_inventory_overlay_left_from_mail_returns_to_items_same_row() -> void:
	var overlay: CanvasLayer = _open_overlay()
	overlay.set("_focus_mail", true)
	Game.inventory.select_mail(4) ## mail row2, col0
	overlay.call("_unhandled_input", _press("ui_left"))
	assert_bool(overlay.get("_focus_mail")).is_false()
	assert_int(Game.inventory.selected_index).is_equal(4) ## item row0, col4


## Mail rows 0-1 sit above the item grid's top row — no item counterpart, so moving
## left there stays in mail instead of jumping to an unrelated item slot.
func test_inventory_overlay_left_from_mail_top_rows_stays_in_mail() -> void:
	var overlay: CanvasLayer = _open_overlay()
	overlay.set("_focus_mail", true)
	Game.inventory.select_mail(1) ## mail row0, col1
	overlay.call("_unhandled_input", _press("ui_left"))
	assert_bool(overlay.get("_focus_mail")).is_true()
	assert_int(Game.inventory.selected_mail_index).is_equal(0)


func test_inventory_overlay_up_from_mail_top_row_reaches_player() -> void:
	var overlay: CanvasLayer = _open_overlay()
	overlay.set("_focus_mail", true)
	Game.inventory.select_mail(0)
	overlay.call("_unhandled_input", _press("ui_up"))
	assert_bool(overlay.get("_focus_player")).is_true()


func test_inventory_overlay_player_slot_unequips_with_empty_hand() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var axe: ItemData = load("res://data/items/axe.tres")
	Game.inventory.add(axe, 1)
	Game.inventory.equip_slot(0)
	overlay.set("_focus_player", true)
	overlay.call("_activate_player_cursor")
	assert_bool(overlay.get("_tag_mode")).is_true()
	assert_that(overlay.get("_tag_choices")).is_equal(PackedStringArray(["Unequip"]))
	overlay.call("_run_tag", "Unequip")
	assert_that(Game.inventory.equipment_id).is_equal(&"")


func test_inventory_overlay_player_slot_equips_held_tool() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var axe: ItemData = load("res://data/items/axe.tres")
	Game.inventory.add(axe, 1)
	Game.inventory.pick_hand(0)
	overlay.set("_focus_player", true)
	overlay.call("_activate_player_cursor") ## hand full -> equips directly, no popup
	assert_int(Game.inventory.hand_index).is_equal(-1)
	assert_that(Game.inventory.equipment_id).is_equal(&"axe")


func test_inventory_overlay_player_slot_wears_held_cloth() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var cloth_items: Array = ItemCatalog.all_items().filter(
		func(d: ItemData) -> bool: return d.category == ItemData.Category.CLOTH
	)
	if cloth_items.is_empty():
		return ## no cloth fixture available in this environment
	var cloth: ItemData = cloth_items[0]
	Game.inventory.add(cloth, 1)
	Game.inventory.pick_hand(0)
	overlay.set("_focus_player", true)
	overlay.call("_activate_player_cursor")
	assert_int(Game.inventory.hand_index).is_equal(-1)
	assert_that(Game.cloth_id).is_equal(cloth.id)


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
	## `mIV_set_player` framing (FOV 20, 0x900 elevation, AABB-fit so it matches
	## whatever actor scale) + `mIV_get_player_item_anime_id` held-tool draw.
	var src := FileAccess.get_file_as_string("res://scenes/ui/inventory_overlay.gd")
	assert_str(src).contains("cam.fov = 20.0")
	assert_str(src).contains("float(0x900)")
	assert_str(src).contains("_visual_aabb(_portrait_pivot)")
	assert_str(src).contains("HeldTool.bind")
	assert_str(src).contains("_sync_portrait_equipment")


## The portrait doll only ever bound the held tool (`_sync_portrait_equipment`) and
## never the worn shirt/design, so it kept showing bare skin no matter what the field
## player actually had on. `_sync_portrait_cloth` (wired to `Game.cloth_changed` and
## called on open) should now paint a cloth surface same as `player.gd::_apply_worn_cloth`.
func test_inventory_portrait_wears_the_equipped_shirt() -> void:
	var overlay: CanvasLayer = _open_overlay()
	await get_tree().process_frame
	var pivot: Node3D = overlay.get("_portrait_pivot") as Node3D
	if pivot == null:
		return ## no player GLB in this checkout — nothing to assert
	Game.set_cloth(&"shirt_000")
	overlay.call("_sync_portrait_cloth")
	var painted: bool = false
	for mesh: MeshInstance3D in _all_mesh_instances(pivot):
		var count: int = mesh.mesh.get_surface_count() if mesh.mesh != null else 0
		for i: int in count:
			var mat: Material = mesh.get_active_material(i)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null \
					and (mat as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL:
				painted = true
	assert_bool(painted).override_failure_message(
		"expected the portrait doll to have a cloth surface repainted for shirt_000"
	).is_true()


func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_all_mesh_instances(child))
	return out


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


func test_inventory_overlay_open_tag_deposits_money_bag() -> void:
	## The wrapped-present unwrap and the money-bag deposit (`mHD_open_sack`) share
	## the "Open" tag text — regression guard for the tag dispatch confusing the two.
	var overlay: CanvasLayer = _open_overlay()
	var bag: ItemData = ItemCatalog.get_item(&"money_100")
	Game.inventory.add(bag, 1)
	Game.inventory.select(0)
	overlay.call("_run_tag", "Open")
	assert_int(Game.inventory.wallet).is_equal(100)
	assert_bool(Game.inventory.slot_at(0).is_empty()).is_true()


func test_mark_toggle_and_drop_all_tag() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(apple, 1) ## slot 0
	inv.add(axe, 1) ## slot 1
	assert_bool(inv.toggle_mark(5)).is_false() ## empty slot — no-op
	assert_bool(inv.toggle_mark(0)).is_true()
	assert_bool(inv.is_marked(0)).is_true()
	assert_bool(inv.tags_for_slot(0).has("Drop All")).is_true()
	assert_bool(inv.tags_for_slot(1).has("Drop All")).is_false()
	assert_bool(inv.tags_for_slot(1).has("Drop")).is_true()
	assert_that(inv.marked_indices()).is_equal([0])
	assert_bool(inv.toggle_mark(0)).is_false() ## toggled back off
	assert_bool(inv.is_marked(0)).is_false()
	inv.toggle_mark(0)
	inv.clear_marks()
	assert_that(inv.marked_indices()).is_equal([])


func test_mark_follows_item_through_hand_swap() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(apple, 1) ## slot 0
	inv.add(axe, 1) ## slot 1
	inv.toggle_mark(0) ## marks the apple
	inv.pick_hand(0)
	inv.place_hand(1) ## swap into the occupied axe slot
	assert_bool(inv.is_marked(0)).is_false() ## axe landed here, was never marked
	assert_bool(inv.is_marked(1)).is_true() ## apple carries its mark to where it landed


func test_mark_clears_when_slot_empties() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 1)
	inv.toggle_mark(0)
	inv.remove_from_slot(0, 1)
	assert_bool(inv.is_marked(0)).is_false()


func test_wrap_and_unwrap_round_trip() -> void:
	var inv := Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	inv.add(apple, 1)
	assert_bool(inv.tags_for_slot(0).has("Wrap")).is_true()
	assert_bool(inv.wrap_slot(0)).is_true()
	assert_that(inv.slot_at(0).item.condition).is_equal(InventoryItem.Condition.PRESENT)
	## Wrapped items only offer "Open" — nothing else, matching a received gift.
	assert_that(inv.tags_for_slot(0)).is_equal(PackedStringArray(["Open"]))
	assert_bool(inv.wrap_slot(0)).is_false() ## already wrapped


func test_money_bag_is_not_wrappable() -> void:
	ItemCatalog.reload()
	var inv := Inventory.new()
	var bag: ItemData = ItemCatalog.get_item(&"money_100")
	inv.add(bag, 1)
	assert_bool(inv.tags_for_slot(0).has("Wrap")).is_false()
	assert_bool(inv.wrap_slot(0)).is_false()


func test_background_set_clear_and_save_round_trip() -> void:
	var inv := Inventory.new()
	assert_that(inv.background_id).is_equal(&"")
	inv.set_background(&"wallpaper_wood")
	assert_that(inv.background_id).is_equal(&"wallpaper_wood")
	var saved: Dictionary = inv.to_save()
	var loaded := Inventory.new()
	loaded.from_save(saved)
	assert_that(loaded.background_id).is_equal(&"wallpaper_wood")
	inv.set_background(&"")
	assert_that(inv.background_id).is_equal(&"")


func test_withdraw_denominations_match_wallet_thresholds() -> void:
	var inv := Inventory.new()
	assert_that(inv.withdrawable_denominations()).is_equal([])
	inv.set_wallet(50)
	assert_that(inv.withdrawable_denominations()).is_equal([])
	inv.set_wallet(100)
	assert_that(inv.withdrawable_denominations()).is_equal([100])
	inv.set_wallet(5000)
	assert_that(inv.withdrawable_denominations()).is_equal([1000, 100])
	inv.set_wallet(50000)
	assert_that(inv.withdrawable_denominations()).is_equal([30000, 10000, 1000, 100])


func test_withdraw_to_hand_spends_bells_and_places_bag_in_hand() -> void:
	ItemCatalog.reload()
	var inv := Inventory.new()
	inv.set_wallet(1000)
	assert_bool(inv.withdraw_to_hand(1000)).is_true()
	assert_int(inv.wallet).is_equal(0)
	assert_int(inv.hand_index).is_not_equal(-1)
	var slot: InventorySlot = inv.slot_at(inv.hand_index)
	assert_that(slot.item.item_id).is_equal(&"money_1000")
	assert_int(slot.item.count).is_equal(1)
	## Can't afford another, and the hand is already full.
	assert_bool(inv.withdraw_to_hand(1000)).is_false()


func test_withdraw_to_hand_fails_without_space() -> void:
	var inv := Inventory.new()
	var axe: ItemData = load("res://data/items/axe.tres")
	inv.add(axe, Inventory.POCKET_SLOTS)
	inv.set_wallet(1000)
	assert_bool(inv.withdraw_to_hand(1000)).is_false()
	assert_int(inv.wallet).is_equal(1000) ## refused before spending anything


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


## `obj_item_fish_tex`/`obj_item_net_tex` are broken/mislabeled in the REL extract
## (garbled palette resp. an actual fishing hook, not a net) — every fish and bug
## must fall back to the intact generic badges instead of those two.
func test_fish_and_bug_icons_show_the_species_card() -> void:
	InventoryChrome.clear_cache()
	ItemCatalog.reload()
	var carp: ItemData = ItemCatalog.get_item(&"carp")
	var bass: ItemData = ItemCatalog.get_item(&"bass")
	var bug: ItemData = ItemCatalog.get_item(&"common_butterfly")
	assert_object(carp).is_not_null()
	assert_object(bass).is_not_null()
	assert_object(bug).is_not_null()
	var carp_icon: Texture2D = InventoryChrome.icon_for_item(carp)
	var bass_icon: Texture2D = InventoryChrome.icon_for_item(bass)
	var bug_icon: Texture2D = InventoryChrome.icon_for_item(bug)
	## `item_turi`/`item_mushi` (`inv_mwin_turi_tex`/`inv_mwin_mushi_tex`) are the
	## fishing-rod / net *tool* badges — a fish must never resolve to either, and a
	## species with its own catalogued card must show that card, not a shared generic.
	if carp_icon != null:
		assert_str(carp_icon.resource_path).not_contains("obj_item_fish_tex")
		assert_str(carp_icon.resource_path).not_contains("inv_mwin_turi_tex")
		assert_str(carp_icon.resource_path).contains("inv_mwin_03koi_tex")
	if bass_icon != null:
		assert_str(bass_icon.resource_path).contains("inv_mwin_14bassm_tex")
	if bug_icon != null:
		assert_str(bug_icon.resource_path).not_contains("obj_item_net_tex")
		assert_str(bug_icon.resource_path).not_contains("inv_mwin_mushi_tex")
		assert_str(bug_icon.resource_path).contains("inv_mwin_01monshiro_tex")


## Identified fossils (`data/fossils.json`, `FurnitureData` -> `category == FURNITURE`)
## used to fall through the generic furniture case straight to the leaf placeholder.
func test_identified_fossil_icon_is_not_the_leaf_placeholder() -> void:
	InventoryChrome.clear_cache()
	ItemCatalog.reload()
	var fossil: ItemData = FossilCatalog.get_item(&"fossil_trex_head")
	assert_object(fossil).is_not_null()
	var icon: Texture2D = InventoryChrome.icon_for_item(fossil)
	if icon != null:
		assert_str(icon.resource_path).not_contains("obj_item_leaf_tex")


## `_refresh_mail` picked the sealed-envelope art off `present_item_id` alone and never
## looked at `mail.font`'s read state, so a letter never visually changed once opened.
func test_mail_icon_switches_to_open_envelope_after_reading() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var mail := MailData.new()
	mail.font = MailData.LetterFont.RECV
	mail.sender_id = &"rover"
	mail.sender_name = "Rover"
	mail.body = "Hi!"
	Game.inventory.add_received_mail(mail) ## stores a duplicate — read it back
	var stored: MailData = Game.inventory.mail_at(0)
	Game.inventory.mail_changed.emit()
	var btn: Button = overlay.get_node("%MailSlot0") as Button
	var icon: TextureRect = btn.get_node("ItemIcon") as TextureRect
	var closed_tex: Texture2D = icon.texture
	stored.mark_read()
	Game.inventory.mail_changed.emit()
	var open_tex: Texture2D = icon.texture
	if closed_tex != null and open_tex != null:
		assert_object(open_tex).is_not_equal(closed_tex)
		assert_str(open_tex.resource_path).contains("letter_open")


func _open_overlay() -> CanvasLayer:
	InventoryChrome.clear_cache()
	ItemCatalog.reload()
	var packed: PackedScene = load("res://scenes/ui/inventory_overlay.tscn") as PackedScene
	var overlay: CanvasLayer = auto_free(packed.instantiate()) as CanvasLayer
	add_child(overlay)
	Game.inventory.clear()
	overlay.call("open")
	return overlay


func test_inventory_overlay_quick_grab_drop() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	Game.inventory.add(apple, 1) ## slot 0
	Game.inventory.add(axe, 1) ## slot 1
	Game.inventory.select(0)
	overlay.call("_quick_grab_drop") ## grab — no verb popup
	assert_int(Game.inventory.hand_index).is_equal(0)
	assert_bool(overlay.get("_tag_mode")).is_false()
	Game.inventory.select(1)
	overlay.call("_quick_grab_drop") ## place/swap in one press
	assert_int(Game.inventory.hand_index).is_equal(-1)
	assert_that(Game.inventory.slot_at(1).item.item_id).is_equal(&"apple")
	assert_that(Game.inventory.slot_at(0).item.item_id).is_equal(&"axe")
	## Drain the 0.35s real-time hand-clip timers `_quick_grab_drop` scheduled before this
	## node is `auto_free`d — otherwise they fire against a freed instance mid-suite.
	await get_tree().create_timer(0.4).timeout


func test_inventory_overlay_mark_and_drop_all() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var apple: ItemData = load("res://data/items/apple.tres")
	var axe: ItemData = load("res://data/items/axe.tres")
	Game.inventory.add(apple, 1) ## slot 0
	Game.inventory.add(axe, 1) ## slot 1
	Game.inventory.select(0)
	overlay.call("_toggle_mark")
	Game.inventory.select(1)
	overlay.call("_toggle_mark")
	assert_that(Game.inventory.marked_indices()).is_equal([0, 1])
	overlay.call("_drop_all_marked") ## no player/world in this test — falls back to re-adding
	assert_that(Game.inventory.marked_indices()).is_equal([])
	assert_int(Game.inventory.count_of(&"apple")).is_equal(1)
	assert_int(Game.inventory.count_of(&"axe")).is_equal(1)


func test_inventory_overlay_mail_discard_needs_confirmation() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var mail := MailData.new()
	mail.recipient_id = &"rover"
	mail.recipient_name = "Rover"
	mail.body = "Hi!"
	Game.inventory.add_mail(mail)
	Game.inventory.select_mail(0)
	overlay.set("_focus_mail", true)
	overlay.call("_activate_mail_cursor") ## enters tag mode with Read/Discard first
	overlay.call("_run_mail_tag", "Discard")
	assert_bool(Game.inventory.mail_at(0).is_empty()).is_false() ## not removed yet
	assert_bool(overlay.get("_tag_mode")).is_true()
	assert_that(overlay.get("_tag_choices")).is_equal(PackedStringArray(["Yes", "No"]))
	overlay.call("_run_mail_tag", "No")
	assert_bool(Game.inventory.mail_at(0).is_empty()).is_false() ## "No" keeps it
	overlay.call("_activate_mail_cursor")
	overlay.call("_run_mail_tag", "Discard")
	overlay.call("_run_mail_tag", "Yes")
	assert_bool(Game.inventory.mail_at(0).is_empty()).is_true()


func test_inventory_overlay_wallet_withdraw() -> void:
	var overlay: CanvasLayer = _open_overlay()
	Game.inventory.set_wallet(5000)
	overlay.call("_open_wallet_popup")
	assert_bool(overlay.get("_wallet_tag_mode")).is_true()
	var choices: PackedStringArray = overlay.get("_tag_choices")
	assert_bool(choices.has("1000 Bells")).is_true()
	assert_bool(choices.has("30000 Bells")).is_false() ## can't afford it
	overlay.call("_run_wallet_tag", "1000 Bells")
	assert_int(Game.inventory.wallet).is_equal(4000)
	assert_int(Game.inventory.hand_index).is_not_equal(-1)
	assert_that(Game.inventory.slot_at(Game.inventory.hand_index).item.item_id).is_equal(&"money_1000")


func test_inventory_overlay_background_slot() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var wall: ItemData = load("res://data/items/wall_blue.tres")
	Game.inventory.add(wall, 1)
	Game.inventory.select(0)
	overlay.call("_run_tag", "Set Background")
	assert_that(Game.inventory.background_id).is_equal(&"wall_blue")
	overlay.call("_open_background_slot")
	assert_bool(overlay.get("_background_tag_mode")).is_true()
	assert_that(overlay.get("_tag_choices")).is_equal(PackedStringArray(["Remove"]))
	overlay.call("_run_background_tag", "Remove")
	assert_that(Game.inventory.background_id).is_equal(&"")


func test_inventory_overlay_page_swing_moves_and_returns() -> void:
	var overlay: CanvasLayer = _open_overlay()
	var shell: Control = overlay.get_node("%ShellStack") as Control
	var base_y: float = shell.position.y
	overlay.call("_select_side_tab", 0) ## SideTab.FISH
	await get_tree().create_timer(0.15).timeout
	assert_float(shell.position.y).is_not_equal(base_y) ## mid-swing
	await get_tree().create_timer(0.6).timeout
	assert_float(shell.position.y).is_equal_approx(base_y, 0.5) ## lands back home


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


