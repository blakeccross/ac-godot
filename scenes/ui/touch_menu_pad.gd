class_name TouchMenuPad
extends CanvasLayer

## A tap is OK on the title, a letter, or the intro. Talk pages are turned by the
## finger's mouse click, not by this pad. There are no on-screen arrow, OK, or Back
## buttons. The key is marked as a finger's so the device tracker doesn't count it as
## a keyboard.

const GROUP := &"touch_menu_pad"
## The overlays a tap must not steal from: every one opens with `is_open()`.
const MENU_GROUPS: Array[StringName] = [
	&"inventory_ui", &"map_ui", &"dialogue_ui", &"shop_ui", &"catalog_ui", &"bank_ui",
	&"repay_ui", &"birthday_ui", &"calendar_ui", &"diary_ui", &"notice_ui", &"town_tune_ui",
	&"letter_address_ui", &"letter_paper_picker_ui", &"letter_reader_ui", &"letter_writer_ui",
	&"name_entry_ui", &"pause_ui", &"settings_ui", &"design_ui", &"design_list_ui",
	&"design_album_ui",
]
## The title logo: the demo town behind it has a player, but a tap is still START.
const TITLE_GROUP := &"title_ui"


static func find(tree: SceneTree) -> TouchMenuPad:
	return tree.get_first_node_in_group(GROUP) as TouchMenuPad if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS


## A menu is up, or the game has no player yet (the title, the intro).
func wanted() -> bool:
	var tree := get_tree()
	if Menus.is_open(tree, MapOverlay.GROUP):
		return false
	var inventory := InventoryOverlay.find(tree)
	if inventory != null and inventory.is_open() and inventory.uses_mobile_layout():
		return false
	if menu_open(tree):
		return true
	return Player.find(tree) == null


static func menu_open(tree: SceneTree) -> bool:
	return Menus.any_open(tree, MENU_GROUPS)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	if not InputDeviceTracker.on_mobile or not InputDeviceTracker.is_touch() or not wanted():
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed or touch.index != 0:
		return
	if taps_accept():
		_accept()


## Press then release Enter, as a keyboard would.
func _accept() -> void:
	_key_event(KEY_ENTER, true)
	_key_event(KEY_ENTER, false)


func _key_event(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	event.device = InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(event)


## A tap is OK on the title, a letter, or the intro. A talk page is not: the finger
## already arrives as a mouse click (`emulate_mouse_from_touch` → `_page_click`), and
## sending Enter as well turns two pages. The second one lands on the pockets the
## moment Nook asks for the house money and closes them before they can be seen.
func taps_accept() -> bool:
	var tree := get_tree()
	if not tree.get_nodes_in_group(TITLE_GROUP).is_empty() and not menu_open(tree):
		return true
	for node: Node in tree.get_nodes_in_group(&"dialogue_ui"):
		if node is DialogueOverlay and (node as DialogueOverlay).is_open():
			return false
	if Menus.is_open(tree, &"letter_reader_ui"):
		return true
	return Player.find(tree) == null and not menu_open(tree)
