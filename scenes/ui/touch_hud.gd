class_name TouchHud
extends CanvasLayer

## Corner buttons while playing by touch: B, Pockets, Map and Pause. Shown only while touch
## is the last device used, and hidden under menus. B goes to the player's touch source (the
## player reads no events while it drives); the others send the same actions the keys do,
## as events, so the menus open exactly as from the keyboard.

const GROUP := &"touch_hud"

@onready var _root: Control = $Root
@onready var _b: Button = $Root/Buttons/B
@onready var _pockets: Button = $Root/Buttons/Pockets
@onready var _map: Button = $Root/Buttons/Map
@onready var _pause: Button = $Root/Buttons/Pause


static func find(tree: SceneTree) -> TouchHud:
	return tree.get_first_node_in_group(GROUP) as TouchHud if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	_b.pressed.connect(press_b)
	_pockets.pressed.connect(send_action.bind(&"inventory"))
	_map.pressed.connect(send_action.bind(&"map"))
	_pause.pressed.connect(send_action.bind(&"pause_menu"))
	var tracker: Node = get_node_or_null("/root/InputDeviceTracker")
	if tracker != null:
		tracker.connect("device_changed", func(_d: int) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var touch: bool = InputDeviceTracker.is_touch()
	var player := Player.find(get_tree())
	var menu: bool = player != null and player._menu_open()
	_root.visible = touch and player != null and not menu


## Whether a screen point is on one of the buttons (the driver leaves those to them).
func covers(at: Vector2) -> bool:
	if not _root.visible:
		return false
	for button: Button in [_b, _pockets, _map, _pause]:
		if button.visible and button.get_global_rect().has_point(at):
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
