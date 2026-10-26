class_name TouchHud
extends CanvasLayer

## A tab bar along the bottom while playing by touch: Map, Pockets and Menu (pause). Shown
## only on Android or iOS while touch is the last device used. A tab sends the same action
## its key does, as an event, so its screen opens exactly as from the keyboard. The bar stays
## up over its own three screens with that tab lit: the lit tab closes it, another tab
## switches (close, then open next frame). Under any other screen (talk, a shop) it hides.
## There is no B: a tapped item is picked up with B by the touch driver.
##
## Chips: a tapped host with a verb on each button (a chair to sit on or move, a sign to read
## or pull up) shows one chip per verb above it, labelled with the verb's prompt. A chip
## walks up and presses that button; a tap anywhere else puts them away.

## Chips float this high above the host (metres).
const CHIP_LIFT := 2.2

const GROUP := &"touch_hud"
## Each tab: its action and the overlay group that is open while its screen is.
const TABS: Dictionary = {
	&"map": &"map_ui",
	&"inventory": &"inventory_ui",
	&"pause_menu": &"pause_ui",
}

@onready var _root: Control = $Root
@onready var _tab_bar: Control = $Root/TabBar
@onready var _tabs: Dictionary = {
	&"map": $Root/TabBar/Tabs/Map,
	&"inventory": $Root/TabBar/Tabs/Pockets,
	&"pause_menu": $Root/TabBar/Tabs/Menu,
}
@onready var _chips: Control = $Root/Chips
@onready var _chip_a: Button = $Root/Chips/ChipA
@onready var _chip_b: Button = $Root/Chips/ChipB

var _chip_volume: InteractVolume = null
var _chip_pick: Callable


static func find(tree: SceneTree) -> TouchHud:
	return tree.get_first_node_in_group(GROUP) as TouchHud if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	## The pause screen pauses the tree; its tab still has to close it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	TouchSafeArea.fit(_root)
	for action: StringName in _tabs:
		(_tabs[action] as Button).pressed.connect(press_tab.bind(action))
	_chip_a.pressed.connect(_on_chip.bind(false))
	_chip_b.pressed.connect(_on_chip.bind(true))
	var tracker: Node = get_node_or_null("/root/InputDeviceTracker")
	if tracker != null:
		tracker.connect("device_changed", func(_d: int) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var player := Player.find(get_tree())
	_root.visible = InputDeviceTracker.shows_touch_buttons() and player != null
	var open: StringName = open_tab()
	_tab_bar.visible = not _menu_up() or open != &""
	for action: StringName in _tabs:
		(_tabs[action] as Button).set_pressed_no_signal(action == open)
	if _chips.visible:
		_place_chips()


## The tab whose screen is open (its action), or empty.
func open_tab() -> StringName:
	var tree := get_tree()
	for action: StringName in TABS:
		if Menus.is_open(tree, TABS[action]):
			return action
	return &""


## Open that tab's screen; the open one closes, another one switches.
func press_tab(action: StringName) -> void:
	var open: StringName = open_tab()
	if open != &"" and open != action:
		await send_action(open)
		await get_tree().process_frame
	send_action(action)


## Offer the host behind `volume` as two chips; `pick(pickup)` runs on the chosen one.
func show_chips(volume: InteractVolume, a_label: String, b_label: String, pick: Callable) -> void:
	_chip_volume = volume
	_chip_pick = pick
	_chip_a.text = a_label if not a_label.is_empty() else "A"
	_chip_b.text = b_label if not b_label.is_empty() else "B"
	_chips.visible = true
	_place_chips()


## Playing by touch on a phone or tablet with no screen open: chips can show.
func is_showing() -> bool:
	return _root.visible and not _menu_up()


func _menu_up() -> bool:
	var player := Player.find(get_tree())
	return (player != null and player._menu_open()) or TouchMenuPad.menu_open(get_tree())


func hide_chips() -> void:
	_chips.visible = false
	_chip_volume = null
	_chip_pick = Callable()


## Test-only: no in-game callers; kept for tests.
func chips_showing() -> bool:
	return _chips.visible


func _place_chips() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if _chip_volume == null or not is_instance_valid(_chip_volume) or cam == null or not is_showing():
		hide_chips()
		return
	var over: Vector3 = _chip_volume.global_position + Vector3.UP * CHIP_LIFT
	if cam.is_position_behind(over):
		hide_chips()
		return
	var size: Vector2 = _chips.get_combined_minimum_size()
	_chips.size = size
	_chips.position = cam.unproject_position(over) - Vector2(size.x * 0.5, size.y)


func _on_chip(pickup: bool) -> void:
	var pick: Callable = _chip_pick
	hide_chips()
	if pick.is_valid():
		pick.call(pickup)


## Whether a screen point is on one of the buttons (the driver leaves those to them).
func covers(at: Vector2) -> bool:
	if not _root.visible:
		return false
	if _tab_bar.is_visible_in_tree() and _tab_bar.get_global_rect().has_point(at):
		return true
	for button: Button in [_chip_a, _chip_b]:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(at):
			return true
	return false


## Press then release `action` as an event (`Input.action_press` alone sends none).
func send_action(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
