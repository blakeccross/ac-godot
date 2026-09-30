extends CanvasLayer

## The 8-slot design list (`mSM_OVL_NEEDLEWORK` / `m_needlework_ovl.c`). Shows the
## player's 8 original designs in display order (`my_org_no_table`) with a hand
## cursor. Three modes:
##   PICK_EDIT   — choose a slot to open in the editor (`aNNW_talk_design_which`).
##   PICK_TRADE  — choose a slot for the current trade op (`aNNW_talk_trade_which*`).
##   MANAGE      — reorder designs (`mNW_swap_image_no`): space picks up, space
##                 again on another slot swaps; opens the editor on a set slot.
##
## `open(mode, callback)` — callback receives the chosen display slot (0-7), or -1
## if cancelled. MANAGE passes no callback.
##
## Drawn as the original book (`mNW_set_frame_dl`): the `inv_original` window baked by
## `design_ui.py` (scrolling cloth, rim, slot wells, frame), the eight designs in its
## 2x4 `mb1-8` wells, the pulsing green mark on a picked-up slot (`sav_mark_winT`)
## and the pointing hand.

signal closed

enum ListMode { PICK_EDIT, PICK_TRADE, MANAGE }

const COLS := 2
const ROWS := 4
## Book window in screen units, centred 10 right of the menu origin (`mNW_OPEN_DESIGN`).
const BOOK_SIZE := Vector2(150, 180)

var _open: bool = false
var _mode: int = ListMode.PICK_EDIT
var _sel: int = 0
var _held: int = -1  ## MANAGE pick-up slot
var _cb: Callable = Callable()

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _book: Control = $Root/Screen/Book
@onready var _slots: Control = $Root/Screen/Book/Slots
@onready var _name: Label = $Root/Screen/Name
@onready var _hand: HandCursor = $Root/Hand

var _thumbs: Array[Texture2D] = []


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("design_list_ui")
	_root.visible = false
	_slots.draw.connect(_draw_slots)
	_book.gui_input.connect(_on_book_input)
	_root.resized.connect(_fit_screen)
	for layer_name: String in ["Cloth:book_mask", "Under:book_under", "Over:book_over"]:
		var parts := layer_name.split(":")
		(_book.get_node(parts[0]) as TextureRect).texture = _design_tex(parts[1])
	## The cloth scrolls under the mask at 64 texels per 60 window units (`w1T` quads),
	## whatever the bake or ACHD size.
	var cloth_rect := _book.get_node("Cloth") as TextureRect
	var cloth := _design_tex("book_cloth")
	var mat := cloth_rect.material as ShaderMaterial
	if mat != null and cloth != null and cloth_rect.texture != null:
		var shell_px_per_unit := cloth_rect.texture.get_width() / BOOK_SIZE.x
		var cloth_px_per_unit := (64.0 / 60.0) * cloth.get_width() / 32.0
		mat.set_shader_parameter("paper_tex", cloth)
		mat.set_shader_parameter("paper_px_per_shell_px", cloth_px_per_unit / shell_px_per_unit)
	_fit_screen()
	set_process(false)
	set_process_unhandled_input(false)


func _design_tex(name: String) -> Texture2D:
	var path := "res://assets/generated/ui/design/%s.png" % name
	return load(path) if ResourceLoader.exists(path) else null


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5
	_hand.size = Vector2(40, 40) * k
	_point_hand(false)


func _process(_delta: float) -> void:
	if _held >= 0:
		_slots.queue_redraw()


func is_open() -> bool:
	return _open


## `beside_inventory`: opened from the pockets' pencil tab (`mNW_OPEN_INV`) — the book
## sits 46 right of centre over the pockets' letter column instead of 10, with no dim.
func open(mode: String, callback: Callable = Callable(), beside_inventory: bool = false) -> void:
	if _open:
		return
	if Game == null or Game.designs == null:
		return
	match mode:
		"pick_edit": _mode = ListMode.PICK_EDIT
		"pick_trade": _mode = ListMode.PICK_TRADE
		_: _mode = ListMode.MANAGE
	_cb = callback
	_book.position.x = 160.0 + (46.0 if beside_inventory else 10.0) - BOOK_SIZE.x * 0.5
	var dim := _root.get_node("Dim") as ColorRect
	dim.color.a = 0.0 if beside_inventory else 0.5
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE if beside_inventory else Control.MOUSE_FILTER_STOP
	_root.mouse_filter = dim.mouse_filter
	_sel = 0
	_held = -1
	_open = true
	_root.visible = true
	_hand.visible = true
	set_process(true)
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")
	_refresh()


func close(chosen: int = -1) -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_hand.visible = false
	set_process(false)
	set_process_unhandled_input(false)
	var cb := _cb
	_cb = Callable()
	closed.emit()
	if cb.is_valid():
		cb.call(chosen)


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match (event as InputEventKey).keycode:
		KEY_LEFT, KEY_A: _sel = _wrap(_sel - 1); Audio.play_se(&"cursol")
		KEY_RIGHT, KEY_D: _sel = _wrap(_sel + 1); Audio.play_se(&"cursol")
		KEY_UP, KEY_W: _sel = _wrap(_sel - COLS); Audio.play_se(&"cursol")
		KEY_DOWN, KEY_S: _sel = _wrap(_sel + COLS); Audio.play_se(&"cursol")
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: _activate()
		KEY_E:
			if _mode == ListMode.MANAGE:
				_edit_selected()
				return
		KEY_C:
			if _mode == ListMode.MANAGE:
				_wear_selected()
		KEY_ESCAPE, KEY_B:
			if _held >= 0:
				_held = -1
			else:
				close(-1)
				return
	_refresh()


func _wrap(i: int) -> int:
	return wrapi(i, 0, COLS * ROWS)


func _edit_selected() -> void:
	var editor: Node = get_tree().get_first_node_in_group("design_ui")
	if editor != null and editor.has_method("open"):
		var s := _sel
		close(-1)
		editor.call("open", s)


## `cloth.idx >= CLOTH_NUM + 1` — wear this design as a shirt, or take it off if
## it is already the worn one.
func _wear_selected() -> void:
	if Game == null:
		return
	Game.worn_design_slot = -1 if Game.worn_design_slot == _sel else _sel
	Game.design_changed.emit()
	Audio.play_se(&"cursol")
	_refresh()


func _activate() -> void:
	match _mode:
		ListMode.PICK_EDIT:
			Audio.play_se(&"cursol")
			close(_sel)
		ListMode.PICK_TRADE:
			Audio.play_se(&"cursol")
			close(_sel)
		ListMode.MANAGE:
			if _held < 0:
				_held = _sel
				Audio.play_se(&"cursol")
			elif _held == _sel:
				## drop on itself → open the editor on this slot
				var editor: Node = get_tree().get_first_node_in_group("design_ui")
				_held = -1
				if editor != null and editor.has_method("open"):
					close(-1)
					editor.call("open", _sel)
					return
			else:
				Game.designs.swap_player_order(_held, _sel)
				_held = -1
				Audio.play_se(&"cursol")


func _on_book_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventMouse):
		return
	var cell := _slot_at((event as InputEventMouse).position)
	if event is InputEventMouseMotion and cell >= 0 and cell != _sel:
		_sel = cell
		_refresh()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and cell >= 0:
		_sel = cell
		_activate()
		_refresh()


## `inv_original_mb1-8_model`: 30x30 wells, two columns at x -34 / 4, rows 34 apart
## from y 65 (window units, y up). Returned in Book-local pixels.
static func slot_rect(i: int) -> Rect2:
	var x0: float = -34.0 if i % COLS == 0 else 4.0
	var top: float = 65.0 - 34.0 * float(i / COLS)
	return Rect2(x0 + 75.0, 90.0 - top, 30.0, 30.0)


func _slot_at(local: Vector2) -> int:
	for i in COLS * ROWS:
		if slot_rect(i).grow(2.0).has_point(local):
			return i
	return -1


func _refresh() -> void:
	if not _open:
		return
	_thumbs.clear()
	for i in COLS * ROWS:
		var dp: DesignPattern = Game.designs.player[Game.designs.resolved_index(i)]
		_thumbs.append(ImageTexture.create_from_image(DesignTexture.image(dp)) if dp != null else null)
	var d: DesignPattern = Game.designs.player[Game.designs.resolved_index(_sel)]
	var label := d.name if d != null else ""
	if _mode == ListMode.MANAGE and Game != null and Game.worn_design_slot == _sel and label != "":
		label += "  (wearing)"
	_name.text = label
	_slots.queue_redraw()
	_point_hand(true)


func _point_hand(animate: bool) -> void:
	if _hand == null or not _open:
		return
	var r := slot_rect(_sel)
	var tip_screen := _book.position + r.position + r.size * Vector2(0.55, 0.45)
	_hand.point_at(_screen.position + tip_screen * _screen.scale, animate)


func _draw_slots() -> void:
	for i in COLS * ROWS:
		var r := slot_rect(i)
		if i < _thumbs.size() and _thumbs[i] != null:
			_slots.draw_texture_rect(_thumbs[i], r, false)
		if i == _held:
			## `mNW_draw_sav_mark_before`: a 40-frame green pulse.
			var g := int(Time.get_ticks_msec() / 1000.0 * 60.0) % 40
			if g > 20:
				g = 40 - g
			var c := Color8(g * 3, 210 + g * 2, g * 3).lerp(Color8(0, 95 + g * 9 / 2, 0), 0.5)
			_slots.draw_rect(r.grow(1.5), c, false, 2.0)
