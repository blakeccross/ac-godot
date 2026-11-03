class_name TouchHud
extends CanvasLayer

## Map, Inventory and Settings while playing by touch: three round white icon buttons
## stacked down the top right, inside the safe area. Shown only during gameplay on Android
## or iOS while touch is the last device used.
## While the player walks the buttons slide off the right edge; once they have stood still
## for a moment they slide back. An open tab screen always keeps them up.
## Map and Inventory send their keyboard actions; Settings opens directly and pauses
## gameplay. The buttons stay
## up over their own three screens with that button lit: the lit button closes it, another one
## switches (close, then open next frame). Under any other screen (talk, a shop) it hides.
## Camera: a round button in the top left. It toggles a row of four more beside it: turn left,
## turn right, closer, farther (`Player.turn_camera`). They work in rooms that take the indoor
## C-stick camera (homes, the museum wings) and out in the town; anywhere else the button is
## dimmed and the row stays shut. The bar slides off the left edge with the right-hand one.
## There is no B: a tapped item is picked up with B by the touch driver.
##
## Chips: a tapped host with a verb on each button (a chair to sit on or move, a sign to read
## or pull up) shows one chip per verb above it, labelled with the verb's prompt. A chip
## walks up and presses that button; a tap anywhere else puts them away.
##
## Joystick: a drag draws a ring (`Base`) with a smaller knob inside it, anchored where the
## finger went down. The driver places both; lifting hides them. They ignore the pointer so
## the finger keeps dragging the world.

## Chips float this high above the host (metres).
const CHIP_LIFT := 2.2
## Button chrome in screen points (44 pt is the smallest comfortable touch target). The
## 1280-wide design grid is squeezed into a phone's width, so these are converted to pixels
## with `px_per_point` rather than used as design units.
const BUTTON_PT := 44.0
const ICON_PT := 24.0
const GAP_PT := 8.0
const SHADOW_PT := 4.0
## Distance from the safe area's top and right edges; chips keep this far off the buttons.
const MARGIN_PT := 12.0
## Slide away: the player moves faster than this (m/s), or the stick is out.
const WALK_SPEED := 0.2
## Slide back once the player has stood still this long.
const RETURN_DELAY_SEC := 0.35
const TUCK_SEC := 0.22
const UNTUCK_SEC := 0.3

const GROUP := &"touch_hud"
## Each tab: its id and the overlay group that is open while its screen is.
const TABS: Dictionary = {
	&"map": &"map_ui",
	&"inventory": &"inventory_ui",
	&"settings": &"settings_ui",
}

@onready var _root: Control = $Root
@onready var _tab_bar: Control = $Root/TabBar
@onready var _tab_stack: VBoxContainer = $Root/TabBar/Tabs
@onready var _tabs: Dictionary = {
	&"map": $Root/TabBar/Tabs/Map,
	&"inventory": $Root/TabBar/Tabs/Inventory,
	&"settings": $Root/TabBar/Tabs/Settings,
}
@onready var _camera_bar: Control = $Root/CameraBar
@onready var _camera_row: HBoxContainer = $Root/CameraBar/Row
@onready var _camera_button: Button = $Root/CameraBar/Row/Camera
@onready var _camera_steps: Dictionary = {
	$Root/CameraBar/Row/Left: Vector2i(0, -1),
	$Root/CameraBar/Row/Right: Vector2i(0, 1),
	$Root/CameraBar/Row/Closer: Vector2i(-1, 0),
	$Root/CameraBar/Row/Farther: Vector2i(1, 0),
}
@onready var _chips: Control = $Root/Chips
@onready var _chip_a: Button = $Root/Chips/ChipA
@onready var _chip_b: Button = $Root/Chips/ChipB
@onready var _stick: Control = $Root/Stick
@onready var _stick_base: Panel = $Root/Stick/Base
@onready var _stick_knob: Panel = $Root/Stick/Knob

## Buttons in the camera bar (the toggle, plus four when the row is out); the layout follows.
var _camera_cols: int = 1
## Distance the camera bar travels to clear the left edge.
var _camera_travel: float = BUTTON_PT
var _camera_w: float = BUTTON_PT
var _chip_volume: InteractVolume = null
var _chip_pick: Callable
var _margin_px: float = 12.0
var _idle_style: StyleBox
var _lit_style: StyleBox
## Distance the buttons travel to clear the right edge (their width, margin and inset).
var _travel: float = BUTTON_PT
var _stack_w: float = BUTTON_PT
## 0 = buttons up, 1 = off the right edge. Tweened; `_place_bar` follows it.
var _drop: float = 0.0:
	set(value):
		_drop = value
		_place_bar()
var _tucked: bool = false
var _still_sec: float = RETURN_DELAY_SEC
var _slide: Tween
var _stick_base_style: StyleBoxFlat
var _stick_knob_style: StyleBoxFlat


static func find(tree: SceneTree) -> TouchHud:
	return tree.get_first_node_in_group(GROUP) as TouchHud if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	## Settings pauses the tree; its tab still has to close it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	TouchSafeArea.fit(_root)
	_stick_base_style = (_stick_base.get_theme_stylebox(&"panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	_stick_knob_style = (_stick_knob.get_theme_stylebox(&"panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	_stick_base.add_theme_stylebox_override(&"panel", _stick_base_style)
	_stick_knob.add_theme_stylebox_override(&"panel", _stick_knob_style)
	for action: StringName in _tabs:
		(_tabs[action] as Button).pressed.connect(press_tab.bind(action))
	for step_button: Button in _camera_steps:
		step_button.pressed.connect(_on_camera_step.bind(_camera_steps[step_button]))
	_camera_button.toggled.connect(func(_on: bool) -> void: _refresh())
	_chip_a.pressed.connect(_on_chip.bind(false))
	_chip_b.pressed.connect(_on_chip.bind(true))
	var sample := _tabs[&"map"] as Button
	_idle_style = sample.get_theme_stylebox(&"normal")
	_lit_style = sample.get_theme_stylebox(&"pressed")
	var tracker: Node = get_node_or_null("/root/InputDeviceTracker")
	if tracker != null:
		tracker.connect("device_changed", func(_d: int) -> void: _refresh())
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_layout_tab_bar):
		vp.size_changed.connect(_layout_tab_bar)
	_layout_tab_bar()
	_refresh()


func _process(delta: float) -> void:
	_refresh()
	_update_tuck(delta)


func _refresh() -> void:
	var player := Player.find(get_tree())
	_root.visible = (
		InputDeviceTracker.shows_touch_buttons()
		and not Game.title_demo_active
		and player != null
	)
	var open: StringName = open_tab()
	_tab_bar.visible = not _menu_up() or open != &""
	var camera_ok := player != null and player.can_turn_camera()
	_camera_bar.visible = not _menu_up()
	_camera_button.disabled = not camera_ok
	_camera_button.modulate.a = 1.0 if camera_ok else 0.45
	var row_out: bool = camera_ok and _camera_button.button_pressed
	for step_button: Button in _camera_steps:
		step_button.visible = row_out
	var cols: int = 1 + (_camera_steps.size() if row_out else 0)
	if cols != _camera_cols:
		_camera_cols = cols
		_apply_tab_layout()
	for action: StringName in _tabs:
		(_tabs[action] as Button).set_pressed_no_signal(action == open)
	if _chips.visible:
		_place_chips()


func _layout_tab_bar() -> void:
	_apply_tab_layout()


## Content pixels in one screen point. iOS reports the window in pixels
## (`bounds * screen scale`), so divide that scale back out.
static func px_per_point(window_px: Vector2, screen_scale: float, content: Vector2) -> float:
	if content.x <= 1.0 or window_px.x <= 1.0:
		return 1.0
	var scale := screen_scale if screen_scale > 0.01 else 1.0
	var points_x := window_px.x / scale
	if points_x <= 1.0:
		return 1.0
	return content.x / points_x


func _measured_px() -> float:
	var vp := get_viewport()
	var content := vp.get_visible_rect().size if vp != null else Vector2.ZERO
	return px_per_point(Vector2(DisplayServer.window_get_size()), DisplayServer.screen_get_scale(), content)


## Sizes the buttons in points. `px_per_point` forces a scale and `inset_right` the safe
## area's right inset in tests; zero and a negative value measure the window.
func _apply_tab_layout(px_per_point: float = 0.0, inset_right: float = -1.0, inset_left: float = -1.0) -> void:
	var px := px_per_point if px_per_point > 0.0 else _measured_px()
	if inset_right < 0.0:
		inset_right = TouchSafeArea.insets(get_viewport()).z
	if inset_left < 0.0:
		inset_left = TouchSafeArea.insets(get_viewport()).x
	_margin_px = MARGIN_PT * px
	var side := BUTTON_PT * px
	var icon := int(round(ICON_PT * px))
	var pad := (side - icon) * 0.5
	var gap := int(round(GAP_PT * px))
	var idle := _round_style(_idle_style, side, pad, px)
	var lit := _round_style(_lit_style, side, pad, px)
	var buttons: Array[Button] = [_camera_button]
	buttons.append_array(_tabs.values())
	buttons.append_array(_camera_steps.keys())
	for button: Button in buttons:
		button.custom_minimum_size = Vector2(side, side)
		button.add_theme_constant_override(&"icon_max_width", icon)
		for state: StringName in [&"normal", &"hover", &"focus", &"disabled"]:
			button.add_theme_stylebox_override(state, idle)
		for state: StringName in [&"pressed", &"hover_pressed"]:
			button.add_theme_stylebox_override(state, lit)
	_tab_stack.add_theme_constant_override(&"separation", gap)
	var stack := Vector2(side, side * _tabs.size() + gap * (_tabs.size() - 1))
	_camera_row.add_theme_constant_override(&"separation", gap)
	_camera_w = side * _camera_cols + gap * (_camera_cols - 1)
	_camera_bar.offset_top = _margin_px
	_camera_bar.offset_bottom = _margin_px + side
	_camera_travel = side * (1 + _camera_steps.size()) + gap * _camera_steps.size() + _margin_px + inset_left + SHADOW_PT * px
	_tab_bar.offset_top = _margin_px
	_tab_bar.offset_bottom = _margin_px + stack.y
	_stack_w = stack.x
	_travel = stack.x + _margin_px + inset_right + SHADOW_PT * px
	_place_bar()


## A circle `side` across with the icon centred in it.
func _round_style(source: StyleBox, side: float, pad: float, px: float) -> StyleBox:
	var copy := source.duplicate() as StyleBox
	copy.content_margin_left = pad
	copy.content_margin_top = pad
	copy.content_margin_right = pad
	copy.content_margin_bottom = pad
	var flat := copy as StyleBoxFlat
	if flat != null:
		flat.set_corner_radius_all(int(ceil(side * 0.5)))
		flat.shadow_size = int(round(SHADOW_PT * px))
		flat.shadow_offset = Vector2(0.0, round(SHADOW_PT * 0.5 * px))
	return copy


## The stack hangs from the top right; `_drop` slides it right, off the screen.
func _place_bar() -> void:
	if _tab_bar == null:
		return
	var shift := _travel * _drop
	_tab_bar.offset_left = -_margin_px - _stack_w + shift
	_tab_bar.offset_right = -_margin_px + shift
	var camera_shift := _camera_travel * _drop
	_camera_bar.offset_left = _margin_px - camera_shift
	_camera_bar.offset_right = _camera_bar.offset_left + _camera_w


## Walking tucks the bar away; standing still brings it back. A tab screen keeps it up.
func _update_tuck(delta: float) -> void:
	var player := Player.find(get_tree())
	var walking := _stick.visible
	if player != null:
		walking = walking or Vector2(player.velocity.x, player.velocity.z).length() > WALK_SPEED
	_still_sec = 0.0 if walking else _still_sec + delta
	var tuck := open_tab() == &"" and (walking or _still_sec < RETURN_DELAY_SEC)
	if tuck == _tucked:
		return
	_tucked = tuck
	if _slide != null:
		_slide.kill()
	_slide = create_tween().set_trans(Tween.TRANS_CUBIC)
	_slide.set_ease(Tween.EASE_IN if tuck else Tween.EASE_OUT)
	_slide.tween_property(self, "_drop", 1.0 if tuck else 0.0, TUCK_SEC if tuck else UNTUCK_SEC)


## The bar has slid (or is sliding) off the screen.
func is_tucked() -> bool:
	return _tucked


## The tab whose screen is open (its id), or empty.
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
		await _toggle_tab(open)
		await get_tree().process_frame
	_toggle_tab(action)


func _toggle_tab(tab: StringName) -> void:
	if tab != &"settings":
		await send_action(tab)
		return
	var settings := SettingsOverlay.find(get_tree())
	if settings == null:
		push_error("TouchHud requires a SettingsOverlay to open Settings.")
		return
	if settings.is_open():
		settings.close()
	else:
		settings.open(true)


func _on_camera_step(step: Vector2i) -> void:
	var player := Player.find(get_tree())
	if player != null:
		player.turn_camera(step.x, step.y)


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
	var pos := cam.unproject_position(over) - Vector2(size.x * 0.5, size.y) - _root.get_global_position()
	_chips.position = _clear_of_tab_bar(pos, size)


## Keep a chip to the left of the tab buttons.
func _clear_of_tab_bar(pos: Vector2, size: Vector2) -> Vector2:
	if not _tab_bar.is_visible_in_tree():
		return pos
	var bar := _tab_bar.get_global_rect()
	bar.position -= _root.get_global_position()
	if not Rect2(pos, size).intersects(bar):
		return pos
	pos.x = bar.position.x - size.x - _margin_px
	return pos


func _on_chip(pickup: bool) -> void:
	var pick: Callable = _chip_pick
	hide_chips()
	if pick.is_valid():
		pick.call(pickup)


## Draw the joystick: `center` is where the finger went down, `finger` is where it is now.
## `radius` is the outer circle; the knob stays inside it.
func show_stick(center: Vector2, finger: Vector2, radius: float, knob_radius: float) -> void:
	if radius <= 1.0 or knob_radius <= 1.0 or _stick_base_style == null:
		return
	_stick.visible = true
	var diameter := radius * 2.0
	_stick.size = Vector2(diameter, diameter)
	_stick.position = center - _root.global_position - Vector2(radius, radius)
	_stick_base.position = Vector2.ZERO
	_stick_base.size = Vector2(diameter, diameter)
	_stick_base_style.set_corner_radius_all(ceili(radius))
	_stick_base_style.set_border_width_all(maxi(int(round(radius * 0.045)), 2))
	var knob_side := knob_radius * 2.0
	var travel := maxf(radius - knob_radius, 1.0)
	var knob_at := (finger - center).limit_length(travel)
	_stick_knob.size = Vector2(knob_side, knob_side)
	_stick_knob.position = Vector2(radius, radius) + knob_at - Vector2(knob_radius, knob_radius)
	_stick_knob_style.set_corner_radius_all(ceili(knob_radius))


func hide_stick() -> void:
	_stick.visible = false


## Test-only: no in-game callers; kept for tests.
func stick_showing() -> bool:
	return _stick.visible


## Whether a screen point is on one of the buttons (the driver leaves those to them).
func covers(at: Vector2) -> bool:
	if not _root.visible:
		return false
	if _tab_bar.is_visible_in_tree() and _tab_bar.get_global_rect().has_point(at):
		return true
	if _camera_bar.is_visible_in_tree() and _camera_bar.get_global_rect().has_point(at):
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
