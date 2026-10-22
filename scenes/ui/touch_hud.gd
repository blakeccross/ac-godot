class_name TouchHud
extends CanvasLayer

## Corner buttons while playing by touch: B, Pockets, Map and Pause. Shown only on Android
## or iOS while touch is the last device used, and hidden under menus. B goes to the player's touch source (the
## player reads no events while it drives); the others send the same actions the keys do,
## as events, so the menus open exactly as from the keyboard.
##
## Chips: a tapped host with a verb on each button (a chair to sit on or move, a sign to read
## or pull up) shows one chip per verb above it, labelled with the verb's prompt. A chip
## walks up and presses that button; a tap anywhere else puts them away.

## Chips float this high above the host (metres).
const CHIP_LIFT := 2.2

const GROUP := &"touch_hud"

@onready var _root: Control = $Root
@onready var _b: Button = $Root/Buttons/B
@onready var _pockets: Button = $Root/Buttons/Pockets
@onready var _map: Button = $Root/Buttons/Map
@onready var _pause: Button = $Root/Buttons/Pause
@onready var _chips: Control = $Root/Chips
@onready var _chip_a: Button = $Root/Chips/ChipA
@onready var _chip_b: Button = $Root/Chips/ChipB

var _chip_volume: InteractVolume = null
var _chip_pick: Callable


static func find(tree: SceneTree) -> TouchHud:
	return tree.get_first_node_in_group(GROUP) as TouchHud if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	TouchSafeArea.fit(_root)
	_b.pressed.connect(press_b)
	_pockets.pressed.connect(send_action.bind(&"inventory"))
	_map.pressed.connect(send_action.bind(&"map"))
	_pause.pressed.connect(send_action.bind(&"pause_menu"))
	_chip_a.pressed.connect(_on_chip.bind(false))
	_chip_b.pressed.connect(_on_chip.bind(true))
	var tracker: Node = get_node_or_null("/root/InputDeviceTracker")
	if tracker != null:
		tracker.connect("device_changed", func(_d: int) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var touch: bool = InputDeviceTracker.shows_touch_buttons()
	var player := Player.find(get_tree())
	var menu: bool = player != null and (player._menu_open() or TouchMenuPad.menu_open(get_tree()))
	_root.visible = touch and player != null and not menu
	if _chips.visible:
		_place_chips()


## Offer the host behind `volume` as two chips; `pick(pickup)` runs on the chosen one.
func show_chips(volume: InteractVolume, a_label: String, b_label: String, pick: Callable) -> void:
	_chip_volume = volume
	_chip_pick = pick
	_chip_a.text = a_label if not a_label.is_empty() else "A"
	_chip_b.text = b_label if not b_label.is_empty() else "B"
	_chips.visible = true
	_place_chips()


## The buttons are up (a phone or tablet, played by touch, no menu open).
func is_showing() -> bool:
	return _root.visible


func hide_chips() -> void:
	_chips.visible = false
	_chip_volume = null
	_chip_pick = Callable()


func chips_showing() -> bool:
	return _chips.visible


func _place_chips() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if _chip_volume == null or not is_instance_valid(_chip_volume) or cam == null or not _root.visible:
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
	for button: Button in [_b, _pockets, _map, _pause, _chip_a, _chip_b]:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(at):
			return true
	return false


func press_b() -> void:
	var player := Player.find(get_tree())
	if player == null:
		return
	var driver := player.get_node_or_null("TouchDriver") as TouchDriver
	if driver != null and driver.install():
		driver.source.tap_b()


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
