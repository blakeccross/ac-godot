class_name TouchMenuPad
extends CanvasLayer

## Fingers on menus. While touch is the last device used and a menu is up (or there's no
## player yet: the title and the intro), arrows, OK and Back sit at the bottom corners and
## send the very keys a keyboard would (↑ ↓ ← →, Enter, Escape), so every overlay runs the
## handler its keys already call and none grows touch code of its own. An arrow held
## repeats. A tap anywhere else is OK while a page is waiting (talk, a letter, the title).
## The keys are marked as emulated so the device tracker doesn't count them as keyboard.

const GROUP := &"touch_menu_pad"
## The overlays the pad serves: every one opens with `is_open()`.
const MENU_GROUPS: Array[StringName] = [
	&"inventory_ui", &"map_ui", &"dialogue_ui", &"shop_ui", &"catalog_ui", &"bank_ui",
	&"repay_ui", &"birthday_ui", &"calendar_ui", &"diary_ui", &"notice_ui", &"town_tune_ui",
	&"letter_address_ui", &"letter_paper_picker_ui", &"letter_reader_ui", &"letter_writer_ui",
	&"name_entry_ui", &"pause_ui", &"settings_ui", &"design_ui", &"design_list_ui",
	&"design_album_ui",
]
## Where a tap off the pad is OK: a page waiting on the player.
const TAP_GROUPS: Array[StringName] = [&"dialogue_ui", &"letter_reader_ui"]

@onready var _root: Control = $Root
@onready var _repeat: Timer = $Repeat
@onready var _buttons: Dictionary = {
	$Root/Arrows/Up: KEY_UP,
	$Root/Arrows/Down: KEY_DOWN,
	$Root/Arrows/Left: KEY_LEFT,
	$Root/Arrows/Right: KEY_RIGHT,
	$Root/Confirm/Ok: KEY_ENTER,
	$Root/Confirm/Back: KEY_ESCAPE,
}

var _held_key: Key = KEY_NONE


static func find(tree: SceneTree) -> TouchMenuPad:
	return tree.get_first_node_in_group(GROUP) as TouchMenuPad if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	TouchSafeArea.fit(_root)
	for button: Button in _buttons:
		var key: Key = _buttons[button]
		if key in [KEY_ENTER, KEY_ESCAPE]:
			button.pressed.connect(send_key.bind(key))
		else:
			button.button_down.connect(_arrow_down.bind(key))
			button.button_up.connect(_arrow_up)
	_repeat.timeout.connect(_on_repeat)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	_root.visible = InputDeviceTracker.is_touch() and wanted()
	if not _root.visible:
		_arrow_up()


## A menu is up, or the game has no player yet (the title, the intro).
func wanted() -> bool:
	var tree := get_tree()
	if menu_open(tree):
		return true
	return Player.find(tree) == null


static func menu_open(tree: SceneTree) -> bool:
	for group: StringName in MENU_GROUPS:
		if _group_open(tree, group):
			return true
	return false


static func _group_open(tree: SceneTree, group: StringName) -> bool:
	for node: Node in tree.get_nodes_in_group(group):
		if node.has_method(&"is_open") and bool(node.call(&"is_open")):
			return true
	return false


## Whether a screen point is on the pad.
func covers(at: Vector2) -> bool:
	if not _root.visible:
		return false
	for button: Button in _buttons:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(at):
			return true
	return false


## Press then release `key`, as a keyboard would.
func send_key(key: Key) -> void:
	_key_event(key, true)
	_key_event(key, false)


func _key_event(key: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	event.device = InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(event)


func _arrow_down(key: Key) -> void:
	_held_key = key
	_key_event(key, true)
	_repeat.start(_repeat.wait_time * 3.0)


func _arrow_up() -> void:
	if _held_key == KEY_NONE:
		return
	_key_event(_held_key, false)
	_held_key = KEY_NONE
	_repeat.stop()


## Held: the key repeats, as an OS key repeat would (echo off, so `is_action_pressed` takes it).
func _on_repeat() -> void:
	if _held_key == KEY_NONE:
		return
	_key_event(_held_key, true)
	_repeat.start()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch) or not _root.visible:
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed or touch.index != 0 or covers(touch.position):
		return
	if taps_accept():
		send_key(KEY_ENTER)


## A tap off the pad is OK: a talk page or letter waiting, or the title / intro.
func taps_accept() -> bool:
	var tree := get_tree()
	for node: Node in tree.get_nodes_in_group(&"dialogue_ui"):
		if node is DialogueOverlay and (node as DialogueOverlay).is_open():
			## A choice is picked with its own button or the arrows and OK.
			return (node as DialogueOverlay).waits_for_page()
	if _group_open(tree, &"letter_reader_ui"):
		return true
	return Player.find(tree) == null and not menu_open(tree)
