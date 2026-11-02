class_name TestMobileInventory
extends GdUnitTestSuite

const OVERLAY_SCENE := preload("res://scenes/ui/inventory_overlay.tscn")
const CLOCK_SCENE := preload("res://scenes/ui/clock_widget.tscn")

var _overlay: InventoryOverlay
var _mobile: MobileInventory
var _grid: GridContainer
var _species_restore: Variant = null


func before_test() -> void:
	TestIsolation.forget_groups(get_tree(), [InventoryOverlay.GROUP])
	InputDeviceTracker.on_mobile = true
	InputDeviceTracker.portrait_override = 1
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	Game.inventory.clear()
	_overlay = auto_free(OVERLAY_SCENE.instantiate()) as InventoryOverlay
	add_child(_overlay)
	_mobile = _overlay.get_node("Root/MobileInventory") as MobileInventory
	_grid = _mobile.get_node("%Grid") as GridContainer
	_overlay.open()
	_overlay._slide.settle()


func after_test() -> void:
	_overlay._ignore_close_once = false
	_overlay.close()
	Game.inventory.clear()
	InputDeviceTracker.on_mobile = OS.has_feature("android") or OS.has_feature("ios")
	InputDeviceTracker.portrait_override = -1
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
	if _species_restore != null:
		Game.species_log.apply_snapshot(_species_restore)
		_species_restore = null


func _card(index: int) -> Button:
	return _grid.get_child(index) as Button


func _name(index: int) -> Label:
	return _card(index).get_node("Content/Name") as Label


func _quantity(index: int) -> Label:
	return _card(index).get_node("Content/Quantity") as Label


func _action(label: String) -> Button:
	for button: Button in _mobile.get_node("%ActionList").get_children():
		if button.text == label:
			return button
	return null


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_overlay._unhandled_input(event)


func test_mobile_grid_has_four_columns_and_all_fifteen_pockets() -> void:
	assert_bool(_overlay.uses_mobile_layout()).is_true()
	assert_bool(_mobile.is_visible_in_tree()).is_true()
	assert_bool(_overlay.get_node("Root/Center").visible).is_false()
	assert_int(_grid.columns).is_equal(4)
	assert_int(_grid.get_child_count()).is_equal(15)
	await get_tree().process_frame
	await get_tree().process_frame
	var first := _card(0).get_global_rect()
	assert_float(_card(3).get_global_rect().position.y).is_equal(first.position.y)
	assert_float(_card(4).get_global_rect().position.x).is_equal(first.position.x)
	assert_float(_card(4).get_global_rect().position.y).is_greater(first.position.y)


func test_mobile_sheet_leaves_the_world_and_bottom_bar_visible() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var sheet := _mobile.get_node("SafeArea/Sheet") as Control
	var screen := get_viewport().get_visible_rect()
	assert_float(sheet.get_global_rect().position.y).is_greater(screen.size.y * 0.3)
	assert_float(sheet.get_global_rect().end.y).is_less_equal(screen.end.y - 16.0 + 8.0)
	var safe_area := _mobile.get_node("SafeArea") as Control
	assert_float(sheet.size.x).is_equal_approx(safe_area.size.x, 1.0)
	assert_bool((_overlay.get_node("Root/Dim") as Control).visible).is_false()


func test_mobile_sheet_slides_up_and_closes_down() -> void:
	_overlay.close()
	_overlay._slide.settle()
	_overlay.open()
	var start := _overlay.offset.y
	assert_float(start).is_greater(get_viewport().get_visible_rect().size.y)
	assert_float(_overlay.offset.x).is_equal(0.0)
	_overlay._slide._process(MenuSlide.IN_SEC * 0.5)
	assert_float(_overlay.offset.y).is_between(0.0, start)
	_overlay._slide._process(MenuSlide.IN_SEC)
	assert_vector(_overlay.offset).is_equal(Vector2.ZERO)
	_overlay.close()
	_overlay._slide._process(MenuSlide.OUT_SEC * 0.5)
	assert_float(_overlay.offset.y).is_greater(0.0)
	_overlay._slide._process(MenuSlide.OUT_SEC)
	assert_bool((_overlay.get_node("Root") as Control).visible).is_false()


func test_matching_items_keep_separate_slots_and_live_quantities() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"apple"), 10)
	assert_str(_name(0).text).is_equal("Apple")
	assert_str(_name(1).text).is_equal("Apple")
	assert_str(_quantity(0).text).is_equal("9")
	assert_str(_quantity(1).text).is_equal("1")
	assert_str((_mobile.get_node("%Capacity") as Label).text).is_equal("2 / 15 pockets")
	assert_object((_card(0).get_node("Content/Icon") as TextureRect).texture).is_not_null()
	Game.inventory.remove_from_slot(0, 1)
	assert_str(_quantity(0).text).is_equal("8")
	assert_str(_quantity(1).text).is_equal("1")


func test_full_pockets_show_the_last_item_and_can_scroll_to_it() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"axe"), Inventory.POCKET_SLOTS)
	assert_str(_name(14).text).is_equal("Axe")
	await get_tree().process_frame
	_mobile.reveal_slot(14)
	await get_tree().process_frame
	var scroll := _mobile.get_node("%Scroll") as ScrollContainer
	assert_int(scroll.scroll_vertical).is_greater(0)
	assert_float(_card(14).get_global_rect().end.y).is_less_equal(scroll.get_global_rect().end.y + 1.0)


func _touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_swiping_over_an_item_scrolls_without_opening_its_actions() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"axe"), Inventory.POCKET_SLOTS)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := _mobile.get_node("%Scroll") as ScrollContainer
	var start := _card(0).get_global_rect().get_center()
	_touch(start, true)
	for step: int in range(1, 5):
		var drag := InputEventScreenDrag.new()
		drag.position = start - Vector2(0, step * 25)
		drag.relative = Vector2(0, -25)
		Input.parse_input_event(drag)
		Input.flush_buffered_events()
		await get_tree().process_frame
	_touch(start - Vector2(0, 100), false)
	assert_int(scroll.scroll_vertical).is_greater(0)
	assert_bool((_mobile.get_node("%Actions") as Control).visible).is_false()
	assert_int(Game.inventory.selected_index).is_equal(0)


func test_touching_an_item_without_dragging_still_opens_actions() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"axe"))
	await get_tree().process_frame
	await get_tree().process_frame
	var at := _card(0).get_global_rect().get_center()
	_touch(at, true)
	_touch(at, false)
	assert_bool((_mobile.get_node("%Actions") as Control).visible).is_true()
	assert_str((_mobile.get_node("%ActionName") as Label).text).is_equal("Axe")


func test_tapping_an_item_exposes_real_actions_and_equips_it() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"axe"))
	_card(0).pressed.emit()
	assert_bool((_mobile.get_node("%Actions") as Control).visible).is_true()
	assert_str((_mobile.get_node("%ActionName") as Label).text).is_equal("Axe")
	assert_object(_action("Equip")).is_not_null()
	_action("Equip").pressed.emit()
	assert_that(Game.inventory.equipment_id).is_equal(&"axe")
	assert_str(_quantity(0).text).contains("Held")
	assert_bool((_mobile.get_node("%Actions") as Control).visible).is_false()
	_card(0).pressed.emit()
	assert_object(_action("Unequip")).is_not_null()
	_action("Unequip").pressed.emit()
	assert_that(Game.inventory.equipment_id).is_equal(&"")


func test_wrapped_item_uses_present_icon_and_can_be_opened() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"apple"), 1, InventoryItem.Condition.PRESENT)
	assert_str(_name(0).text).is_equal("Wrapped present")
	_card(0).pressed.emit()
	assert_int(_mobile.get_node("%ActionList").get_child_count()).is_equal(1)
	_action("Open").pressed.emit()
	assert_that(Game.inventory.slot_at(0).item.condition).is_equal(InventoryItem.Condition.NORMAL)
	assert_str(_name(0).text).is_equal("Apple")


func test_empty_slots_are_visible_and_do_not_open_actions() -> void:
	_card(14).pressed.emit()
	assert_str(_name(14).text).is_equal("Empty")
	assert_bool((_mobile.get_node("%Actions") as Control).visible).is_false()


func test_cancel_dismisses_actions_without_changing_the_item() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"axe"))
	_card(0).pressed.emit()
	(_mobile.get_node("%Cancel") as Button).pressed.emit()
	assert_bool((_mobile.get_node("%Actions") as Control).visible).is_false()
	assert_that(Game.inventory.equipment_id).is_equal(&"")
	assert_bool(_overlay.is_open()).is_true()


func test_wallet_updates_and_uses_existing_wallet_actions() -> void:
	Game.inventory.set_wallet(1000)
	assert_str((_mobile.get_node("%Wallet") as Button).text).is_equal("1000 Bells")
	(_mobile.get_node("%Wallet") as Button).pressed.emit()
	assert_str((_mobile.get_node("%ActionName") as Label).text).is_equal("Bells")
	assert_object(_action("1000 Bells")).is_not_null()
	_action("1000 Bells").pressed.emit()
	assert_int(Game.inventory.wallet).is_equal(0)
	assert_int(Game.inventory.hand_index).is_equal(0)
	assert_that(Game.inventory.slot_at(0).item.item_id).is_equal(&"money_1000")


func test_move_action_can_place_an_item_in_an_empty_mobile_slot() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"axe"))
	_card(0).pressed.emit()
	_action("Move").pressed.emit()
	assert_int(Game.inventory.hand_index).is_equal(0)
	_card(14).pressed.emit()
	assert_int(Game.inventory.hand_index).is_equal(-1)
	assert_bool(Game.inventory.slot_at(0).is_empty()).is_true()
	assert_that(Game.inventory.slot_at(14).item.item_id).is_equal(&"axe")
	assert_str(_name(14).text).is_equal("Axe")
	await get_tree().create_timer(0.4).timeout


func test_letters_fish_and_insects_stay_on_the_portrait_sheet() -> void:
	_species_restore = Game.species_log.to_save()
	Game.species_log.clear()
	Game.species_log.record(&"crucian_carp")
	Game.species_log.record(&"common_butterfly")
	var mail := MailData.make_send(&"bob", "Bob", "Come visit the river.", "Player")
	Game.inventory.add_mail(mail)
	(_mobile.get_node("%PageLetters") as Button).pressed.emit()
	assert_bool(_mobile.get_node("%LettersScroll").visible).is_true()
	assert_bool(_overlay.get_node("Root/Center").visible).is_false()
	assert_str((_mobile.get_node("%LetterList").get_child(0).get_node("Content/Name") as Label).text).is_equal("To Bob")
	(_mobile.get_node("%LetterList").get_child(0) as Button).pressed.emit()
	assert_object(_action("Discard")).is_not_null()
	(_mobile.get_node("%PageFish") as Button).pressed.emit()
	assert_bool(_mobile.get_node("%CollectionScroll").visible).is_true()
	assert_str((_mobile.get_node("%Title") as Label).text).is_equal("Fish")
	assert_int(_mobile.get_node("%CollectionGrid").get_child_count()).is_equal(40)
	var fish_name := ItemCatalog.get_item(&"crucian_carp").display_name
	assert_str((_mobile.get_node("%CollectionGrid").get_child(0).get_node("Content/Name") as Label).text).is_equal(fish_name)
	assert_str((_mobile.get_node("%CollectionGrid").get_child(1).get_node("Content/Name") as Label).text).is_equal("???")
	(_mobile.get_node("%PageInsects") as Button).pressed.emit()
	assert_str((_mobile.get_node("%Title") as Label).text).is_equal("Insects")
	var bug_name := ItemCatalog.get_item(&"common_butterfly").display_name
	assert_str((_mobile.get_node("%CollectionGrid").get_child(0).get_node("Content/Name") as Label).text).is_equal(bug_name)
	(_mobile.get_node("%PageItems") as Button).pressed.emit()
	assert_bool(_mobile.get_node("%Scroll").visible).is_true()


func test_landscape_phone_uses_the_classic_inventory() -> void:
	InputDeviceTracker.portrait_override = 0
	_overlay._refresh()
	assert_bool(_overlay.uses_mobile_layout()).is_false()
	assert_bool(_mobile.visible).is_false()
	assert_bool(_overlay.get_node("Root/Center").visible).is_true()
	InputDeviceTracker.portrait_override = 1
	_overlay._refresh()
	assert_bool(_overlay.uses_mobile_layout()).is_true()


func test_desktop_click_outside_closes_like_escape() -> void:
	InputDeviceTracker.on_mobile = false
	_overlay.close()
	_overlay._slide.settle()
	_overlay.open()
	_overlay._slide.settle()
	await get_tree().process_frame
	await get_tree().process_frame
	Game.inventory.add(ItemCatalog.get_item(&"axe"))
	(_overlay.get_node("Root/Center/ShellStack/SlotLayer/ItemSlot0") as Button).pressed.emit()
	assert_bool(_overlay._tag_mode).is_true()
	var rect := _overlay.menu_rect()
	var outside := Vector2(4, 4)
	if rect.has_point(outside):
		outside = rect.position + Vector2(-12, rect.size.y * 0.5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = outside
	click.global_position = outside
	assert_bool(WindowDismiss.handle(get_tree(), click, not InputDeviceTracker.uses_mobile_ui())).is_true()
	assert_bool(_overlay.is_open()).is_true()
	assert_bool(_overlay._tag_mode).is_false()
	assert_bool(WindowDismiss.handle(get_tree(), click, not InputDeviceTracker.uses_mobile_ui())).is_true()
	assert_bool(_overlay.is_open()).is_false()
	_overlay.open()
	_overlay._slide.settle()
	await get_tree().process_frame
	var current := _overlay.menu_rect()
	if current.has_point(current.get_center()):
		click.position = current.get_center()
		click.global_position = click.position
		assert_bool(WindowDismiss.handle(get_tree(), click)).is_false()
		assert_bool(_overlay.is_open()).is_true()


func test_keyboard_navigation_matches_four_columns_without_changing_inventory_rules() -> void:
	_press(&"ui_down")
	assert_int(Game.inventory.selected_index).is_equal(4)
	Game.inventory.select(3)
	_press(&"ui_right")
	assert_int(Game.inventory.selected_index).is_equal(3)
	assert_bool(_overlay._focus_mail).is_false()
	Game.inventory.select(0)
	_press(&"ui_up")
	assert_int(Game.inventory.selected_index).is_equal(0)
	assert_bool(_overlay._focus_player).is_false()
	Game.inventory.select(14)
	_press(&"ui_down")
	assert_int(Game.inventory.selected_index).is_equal(14)


func test_desktop_keeps_classic_inventory_and_clock() -> void:
	InputDeviceTracker.on_mobile = false
	_overlay._refresh()
	assert_bool(_overlay.uses_mobile_layout()).is_false()
	assert_bool(_mobile.visible).is_false()
	assert_bool(_overlay.get_node("Root/Center").visible).is_true()
	var clock := auto_free(CLOCK_SCENE.instantiate()) as Control
	add_child(clock)
	assert_bool(clock.visible).is_true()
	Game.inventory.select(0)
	_press(&"ui_down")
	assert_int(Game.inventory.selected_index).is_equal(5)


func test_clock_stays_hidden_on_mobile_with_touch_or_keys() -> void:
	var clock := auto_free(CLOCK_SCENE.instantiate()) as Control
	add_child(clock)
	assert_bool(clock.visible).is_false()
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
	clock._process(0.1)
	assert_bool(clock.visible).is_false()


func test_native_mobile_inventory_hides_the_menu_pad_but_not_in_classic_mode() -> void:
	var pad := TouchMenuPad.find(get_tree())
	assert_bool(pad.wanted()).is_false()
	InputDeviceTracker.portrait_override = 0
	_overlay._refresh()
	assert_bool(pad.wanted()).is_true()
	InputDeviceTracker.portrait_override = 1
	_overlay._refresh()
	assert_bool(pad.wanted()).is_false()


func test_house_payment_shows_hand_over_and_ignores_the_opening_close() -> void:
	## The tap that parks Nook's money line can land on Close the moment the sheet
	## appears. That press must not dismiss the down payment.
	Game.inventory.clear()
	Game.intro.payment_pending = true
	Game.inventory.add(ItemCatalog.get_item(&"money_1000"), 1, InventoryItem.Condition.QUEST)
	Game.inventory.select(4)
	assert_bool(_overlay.present_handover(&"money_1000")).is_true()
	_overlay._slide.settle()
	assert_int(Game.inventory.selected_index).is_equal(0)
	assert_int(_overlay.layer).is_equal(30)
	assert_object(_action("Hand over")).is_not_null()
	(_mobile.get_node("%Close") as Button).pressed.emit()
	assert_bool(_overlay.is_open()).is_true()
	_overlay._ignore_close_once = false
	(_mobile.get_node("%Close") as Button).pressed.emit()
	assert_bool(_overlay.is_open()).is_false()
	Game.intro.payment_pending = false


func test_close_button_closes_inventory() -> void:
	(_mobile.get_node("%Close") as Button).pressed.emit()
	assert_bool(_overlay.is_open()).is_false()
