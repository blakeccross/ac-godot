extends CanvasLayer

## The pixel design editor (`m_design_ovl.c` / `mSM_OVL_DESIGN`). Edits one of the
## player's 8 original designs in place: 32x32, 16-colour indexed, one of the 16
## preset palettes.
##
## 1:1 port of the tool set: PEN (1 / 2x2 / 3x3 + drag line), NURI fill
## (flood / v-bands / h-bands / grid / polka / all), WAKU shapes
## (rect / ellipse / filled rect / filled ellipse / line), MARK stamps
## (heart / star / circle / square), UNDO (3-way swap). PALLET mode swaps the
## palette and picks the paint colour; GRID toggles the guide; the TOOL tab is a
## 5-row icon picker. `L` / `R` cycle the mode tabs, `Start` opens the
## save / keep-editing / discard prompt (`mSM_OVL_EDITENDCHK`).
##
## Chrome is Godot-drawn (`des_*` ROM art not extracted). Controls are keyboard +
## mouse; the decomp C-stick / D-pad / C-button bindings map to arrows, `[` `]`,
## `Tab`, `Z`, `,` `.` and number keys.

signal closed

const W := DesignPattern.WIDTH
const H := DesignPattern.HEIGHT

enum Mode { MAIN, PALLET, GRID, TOOL }
enum Tool { PEN, NURI, WAKU, MARK, UNDO }

## `mDE_paint_mizutama` — 16x16 polka tile (`m_design_ovl.c:186`).
const MIZUTAMA := [
	0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,
	0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,
	0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,
	0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,
	1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,
	1,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,
	1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,
	1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,
	1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,
	1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,
	1,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,
	1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,
	0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,
	0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,
	0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,
	0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,
]
## 12x12 MARK glyphs (`m_design_ovl.c:51-109`).
const MARK_HEART := [
	0,1,1,1,0,0,0,0,1,1,1,0, 1,1,1,1,1,0,0,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1, 0,1,1,1,1,1,1,1,1,1,1,0,
	0,1,1,1,1,1,1,1,1,1,1,0, 0,0,1,1,1,1,1,1,1,1,0,0, 0,0,0,1,1,1,1,1,1,0,0,0,
	0,0,0,0,1,1,1,1,0,0,0,0, 0,0,0,0,0,1,1,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,
]
const MARK_STAR := [
	0,0,0,0,0,1,1,0,0,0,0,0, 0,0,0,0,0,1,1,0,0,0,0,0, 0,0,0,0,1,1,1,1,0,0,0,0,
	0,0,0,0,1,1,1,1,0,0,0,0, 1,1,1,1,1,1,1,1,1,1,1,1, 0,1,1,1,1,1,1,1,1,1,1,0,
	0,0,1,1,1,1,1,1,1,1,0,0, 0,0,0,1,1,1,1,1,1,0,0,0, 0,0,1,1,1,1,1,1,1,1,0,0,
	0,0,1,1,1,0,0,1,1,1,0,0, 0,1,1,1,0,0,0,0,1,1,1,0, 0,1,1,0,0,0,0,0,0,1,1,0,
]
const MARK_CIRCLE := [
	0,0,0,0,1,1,1,1,0,0,0,0, 0,0,1,1,0,0,0,0,1,1,0,0, 0,1,0,0,0,0,0,0,0,0,1,0,
	0,1,0,0,0,0,0,0,0,0,1,0, 1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1,
	1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1, 0,1,0,0,0,0,0,0,0,0,1,0,
	0,1,0,0,0,0,0,0,0,0,1,0, 0,0,1,1,0,0,0,0,1,1,0,0, 0,0,0,0,1,1,1,1,0,0,0,0,
]
const MARK_SQUARE := [
	1,1,1,1,1,1,1,1,1,1,1,1, 1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1,
	1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1,
	1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1,
	1,0,0,0,0,0,0,0,0,0,0,1, 1,0,0,0,0,0,0,0,0,0,0,1, 1,1,1,1,1,1,1,1,1,1,1,1,
]

const TOOL_ROWS := [3, 6, 5, 4, 1]  ## columns per tool row (pen/nuri/waku/mark/undo)
const TOOL_LABELS := [
	["1px", "2x2", "3x3"],
	["Fill", "V-bands", "H-bands", "Grid", "Polka", "All"],
	["Rect", "Ellipse", "Rect fill", "Ellipse fill", "Line"],
	["Heart", "Star", "Circle", "Square"],
	["Undo"],
]
const TOOL_NAMES := ["Pen", "Fill", "Shape", "Stamp", "Undo"]

var _open: bool = false
var _slot: int = -1
var _design: DesignPattern = null
var _work: PackedByteArray = PackedByteArray()
var _undo: PackedByteArray = PackedByteArray()
var _redo_toggle: bool = false

var _palette_no: int = 0
var _paint: int = 1  ## `_6A4`, 1-15
var _cursor := Vector2i(15, 15)
var _grid_on: bool = true
var _mode: int = Mode.MAIN
var _tool: int = Tool.PEN
var _pen_size: int = 0
var _fill_mode: int = 0
var _shape: int = 0
var _stamp: int = 0

## WAKU rubber-band anchor.
var _waku_armed: bool = false
var _waku_anchor := Vector2i.ZERO

## PALLET row: 0 = palette selector, 1-15 = colour pick.
var _pal_row: int = 0
## TOOL grid position.
var _tool_row: int = 0
var _tool_col: int = 0

## PEN drag.
var _drawing: bool = false
var _last_paint := Vector2i(-1, -1)

## Save prompt (`mSM_OVL_EDITENDCHK`).
var _prompt: bool = false
var _prompt_idx: int = 0

var _on_done: Callable = Callable()

@onready var _root: Control = $Root
@onready var _canvas: Control = $Root/Frame/Box/Middle/Canvas
@onready var _title: Label = $Root/Frame/Box/Header/Title
@onready var _status: Label = $Root/Frame/Box/Footer/Status
@onready var _hint: Label = $Root/Frame/Box/Footer/Hint
@onready var _swatches: Control = $Root/Frame/Box/Middle/Side/SwatchRow/Swatches
@onready var _panel: Control = $Root/Frame/Box/Middle/Side/SwatchRow/Panel
@onready var _promptbox: PanelContainer = $Root/Prompt


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("design_ui")
	_root.visible = false
	_canvas.draw.connect(_draw_canvas)
	_swatches.draw.connect(_draw_swatches)
	_panel.draw.connect(_draw_panel)
	_canvas.gui_input.connect(_on_canvas_input)
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


## `aNNW_talk_design_open` → `mSM_OVL_DESIGN`. `slot` is a player display slot (0-7).
func open(slot: int, on_done: Callable = Callable()) -> void:
	if _open:
		return
	if Game == null or Game.designs == null:
		return
	_slot = slot
	_on_done = on_done
	_design = Game.designs.resolved(slot)
	_work = _design.pixels.duplicate()
	_undo = _work.duplicate()
	_redo_toggle = false
	_palette_no = _design.palette
	_paint = 1
	_cursor = Vector2i(15, 15)
	_grid_on = true
	_mode = Mode.MAIN
	_tool = Tool.PEN
	_pen_size = 0
	_fill_mode = 0
	_shape = 0
	_stamp = 0
	_waku_armed = false
	_prompt = false
	_drawing = false
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	set_process_unhandled_input(false)
	var saved := _slot >= 0 and _design != null and _design.flag_set
	var slot := _slot
	_slot = -1
	var cb := _on_done
	_on_done = Callable()
	closed.emit()
	if cb.is_valid():
		cb.call(slot, saved)


# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	if k.echo and k.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_W, KEY_A, KEY_S, KEY_D]:
		return

	if _prompt:
		_prompt_key(k.keycode)
		return

	match k.keycode:
		KEY_BRACKETLEFT:
			_cycle_mode(-1)
			return
		KEY_BRACKETRIGHT:
			_cycle_mode(1)
			return
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
			_open_prompt()
			return

	match _mode:
		Mode.MAIN: _main_key(k.keycode)
		Mode.PALLET: _pallet_key(k.keycode)
		Mode.GRID: _grid_key(k.keycode)
		Mode.TOOL: _tool_key(k.keycode)
	_refresh()


func _main_key(kc: int) -> void:
	var moved := _move_cursor_key(kc)
	if moved:
		if _tool == Tool.PEN and _drawing:
			_stroke_to(_cursor)
		return
	match kc:
		KEY_SPACE:
			_apply_tool_press()
		KEY_SHIFT, KEY_B:
			_paint = _pal_at(_cursor.x, _cursor.y)
			Audio.play_se(&"cursol")
		KEY_TAB:
			_grid_on = not _grid_on
			Audio.play_se(&"cursol")
		KEY_Z, KEY_Y:
			_do_undo()
		KEY_COMMA, KEY_MINUS:
			_step_paint(-1)
		KEY_PERIOD, KEY_EQUAL:
			_step_paint(1)
		KEY_1: _tool = Tool.PEN; _mode = Mode.MAIN
		KEY_2: _tool = Tool.NURI
		KEY_3: _tool = Tool.WAKU; _waku_armed = false
		KEY_4: _tool = Tool.MARK
		KEY_5: _tool = Tool.UNDO


func _pallet_key(kc: int) -> void:
	match kc:
		KEY_UP, KEY_W:
			_pal_row = wrapi(_pal_row - 1, 0, 16)
			Audio.play_se(&"cursol")
		KEY_DOWN, KEY_S:
			_pal_row = wrapi(_pal_row + 1, 0, 16)
			Audio.play_se(&"cursol")
		KEY_SPACE:
			if _pal_row == 0:
				_palette_no = wrapi(_palette_no + 1, 0, 16)
				Audio.play_se(&"cursol")
			else:
				_paint = _pal_row
				_mode = Mode.MAIN
				Audio.play_se(&"cursol")
		KEY_B, KEY_SHIFT:
			if _pal_row == 0:
				_palette_no = wrapi(_palette_no - 1, 0, 16)
				Audio.play_se(&"cursol")


func _grid_key(kc: int) -> void:
	if kc == KEY_SPACE:
		_grid_on = not _grid_on
		Audio.play_se(&"cursol")


func _tool_key(kc: int) -> void:
	match kc:
		KEY_UP, KEY_W:
			_tool_row = wrapi(_tool_row - 1, 0, 5)
			_tool_col = mini(_tool_col, int(TOOL_ROWS[_tool_row]) - 1)
			Audio.play_se(&"cursol")
		KEY_DOWN, KEY_S:
			_tool_row = wrapi(_tool_row + 1, 0, 5)
			_tool_col = mini(_tool_col, int(TOOL_ROWS[_tool_row]) - 1)
			Audio.play_se(&"cursol")
		KEY_LEFT, KEY_A:
			_tool_col = wrapi(_tool_col - 1, 0, int(TOOL_ROWS[_tool_row]))
			Audio.play_se(&"cursol")
		KEY_RIGHT, KEY_D:
			_tool_col = wrapi(_tool_col + 1, 0, int(TOOL_ROWS[_tool_row]))
			Audio.play_se(&"cursol")
		KEY_SPACE:
			_commit_tool_pick()


func _commit_tool_pick() -> void:
	Audio.play_se(&"cursol")
	match _tool_row:
		0: _tool = Tool.PEN; _pen_size = _tool_col
		1: _tool = Tool.NURI; _fill_mode = _tool_col
		2: _tool = Tool.WAKU; _shape = _tool_col; _waku_armed = false
		3: _tool = Tool.MARK; _stamp = _tool_col
		4: _tool = Tool.UNDO
	_mode = Mode.MAIN


func _move_cursor_key(kc: int) -> bool:
	var d := Vector2i.ZERO
	match kc:
		KEY_LEFT, KEY_A: d = Vector2i(-1, 0)
		KEY_RIGHT, KEY_D: d = Vector2i(1, 0)
		KEY_UP, KEY_W: d = Vector2i(0, -1)
		KEY_DOWN, KEY_S: d = Vector2i(0, 1)
		_: return false
	_cursor.x = clampi(_cursor.x + d.x, 0, W - 1)
	_cursor.y = clampi(_cursor.y + d.y, 0, H - 1)
	if _waku_armed:
		Audio.play_se(&"cursol")
	return true


func _prompt_key(kc: int) -> void:
	match kc:
		KEY_LEFT, KEY_A, KEY_UP, KEY_W:
			_prompt_idx = wrapi(_prompt_idx - 1, 0, 3)
			Audio.play_se(&"cursol")
			_refresh()
		KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
			_prompt_idx = wrapi(_prompt_idx + 1, 0, 3)
			Audio.play_se(&"cursol")
			_refresh()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_resolve_prompt(_prompt_idx)
		KEY_ESCAPE, KEY_B:
			_prompt = false
			_promptbox.visible = false


# --- mouse ---------------------------------------------------------------

func _on_canvas_input(event: InputEvent) -> void:
	if not _open or _prompt or _mode != Mode.MAIN:
		return
	var cell := _cell_from_local(event)
	if event is InputEventMouseMotion:
		if cell.x >= 0:
			_cursor = cell
			if _drawing and _tool == Tool.PEN:
				_stroke_to(cell)
			_refresh()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_step_paint(1); _refresh(); return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_step_paint(-1); _refresh(); return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if cell.x >= 0:
				_paint = _pal_at(cell.x, cell.y)
				_refresh()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and cell.x >= 0:
			_cursor = cell
			_apply_tool_press()
		elif not mb.pressed:
			_drawing = false
			_last_paint = Vector2i(-1, -1)
		_refresh()


func _cell_from_local(event: InputEvent) -> Vector2i:
	var pos: Vector2 = _canvas.get_local_mouse_position()
	if event is InputEventMouse:
		pos = (event as InputEventMouse).position
	var sz := _canvas.size
	var px := int(pos.x / (sz.x / float(W)))
	var py := int(pos.y / (sz.y / float(H)))
	if px < 0 or px >= W or py < 0 or py >= H:
		return Vector2i(-1, -1)
	return Vector2i(px, py)


# --- tool application (mirror m_design_ovl.c) ---------------------------

func _apply_tool_press() -> void:
	match _tool:
		Tool.PEN:
			_snapshot()
			_drawing = true
			_last_paint = _cursor
			_pen_dab(_cursor)
			_pen_sfx()
		Tool.NURI:
			_snapshot()
			_do_fill()
			Audio.play_se(&"cursol")
		Tool.WAKU:
			if not _waku_armed:
				_waku_armed = true
				_waku_anchor = _cursor
				Audio.play_se(&"cursol")
			else:
				_snapshot()
				_do_shape()
				_waku_armed = false
				Audio.play_se(&"cursol")
		Tool.MARK:
			_snapshot()
			_stamp_glyph()
			Audio.play_se(&"cursol")
		Tool.UNDO:
			_do_undo()


func _pen_sfx() -> void:
	Audio.play_se(&"cursol")


## `mDE_main_pen_move` — dab 1 / 2x2 / 3x3 at (c). Template offsets from
## `mDE_set_texture_template(pen_2, cx, cy, 2,2, 0,1)` and `(pen_3, cx,cy, 3,3, 0,2)`.
func _pen_dab(c: Vector2i) -> void:
	match _pen_size:
		1:
			for j in 2:
				for i in 2:
					_set_px(c.x + i, c.y + j - 1)
		2:
			for j in 3:
				for i in 3:
					_set_px(c.x + i, c.y + j - 2)
		_:
			_set_px(c.x, c.y)


## `mDE_waku_line` (Bresenham) with the active paint index.
func _stroke_to(to: Vector2i) -> void:
	if _last_paint.x < 0:
		_last_paint = to
	_line(_last_paint, to)
	_last_paint = to


func _line(a: Vector2i, b: Vector2i) -> void:
	var dx: int = absi(b.x - a.x)
	var dy: int = absi(b.y - a.y)
	var sx: int = 1 if b.x > a.x else -1
	var sy: int = 1 if b.y > a.y else -1
	var x := a.x
	var y := a.y
	if dx >= dy:
		var err := -dx
		for _i in dx + 1:
			_pen_dab(Vector2i(x, y))
			err += dy * 2
			x += sx
			if err >= 0:
				y += sy
				err -= dx * 2
	else:
		var err := -dy
		for _i in dy + 1:
			_pen_dab(Vector2i(x, y))
			err += dx * 2
			y += sy
			if err >= 0:
				x += sx
				err -= dy * 2


## `mDE_paint` — the 6 fill modes.
func _do_fill() -> void:
	match _fill_mode:
		0:
			_flood(_cursor.x, _cursor.y)
		1:
			for x in W:
				for y in H:
					if int(x / 4.0) % 2 == 0:
						_work[y * W + x] = _paint
		2:
			for x in W:
				for y in H:
					if int(y / 4.0) % 2 == 0:
						_work[y * W + x] = _paint
		3:
			for x in W:
				for y in H:
					if int(x / 4.0) % 2 == 0 or int(y / 4.0) % 2 == 0:
						_work[y * W + x] = _paint
		4:
			for ty in 2:
				for tx in 2:
					for i in 256:
						if MIZUTAMA[i] != 0:
							var x := tx * 16 + (i % 16)
							var y := ty * 16 + int(i / 16.0)
							_set_px(x, y)
		_:
			for i in W * H:
				_work[i] = _paint


## `mDE_farbado` scanline flood fill.
func _flood(sx: int, sy: int) -> void:
	var target := _work[sy * W + sx]
	if target == _paint:
		return
	var stack: Array[Vector2i] = [Vector2i(sx, sy)]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		var x := p.x
		if _work[p.y * W + x] != target:
			continue
		while x > 0 and _work[p.y * W + x - 1] == target:
			x -= 1
		var x2 := p.x
		while x2 < W - 1 and _work[p.y * W + x2 + 1] == target:
			x2 += 1
		for ix in range(x, x2 + 1):
			_work[p.y * W + ix] = _paint
			if p.y > 0 and _work[(p.y - 1) * W + ix] == target:
				stack.push_back(Vector2i(ix, p.y - 1))
			if p.y < H - 1 and _work[(p.y + 1) * W + ix] == target:
				stack.push_back(Vector2i(ix, p.y + 1))


## `mDE_waku_square_write` / `mDE_waku_circle_write` / `mDE_waku_line`.
func _do_shape() -> void:
	var a := _waku_anchor
	var b := _cursor
	var x0: int = mini(a.x, b.x)
	var x1: int = maxi(a.x, b.x)
	var y0: int = mini(a.y, b.y)
	var y1: int = maxi(a.y, b.y)
	match _shape:
		0:
			for x in range(x0, x1 + 1):
				_work[y0 * W + x] = _paint
				_work[y1 * W + x] = _paint
			for y in range(y0, y1 + 1):
				_work[y * W + x0] = _paint
				_work[y * W + x1] = _paint
		2:
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					_work[y * W + x] = _paint
		1:
			_ellipse(x0, y0, x1, y1, false)
		3:
			_ellipse(x0, y0, x1, y1, true)
		4:
			_line(a, b)


func _ellipse(x0: int, y0: int, x1: int, y1: int, fill: bool) -> void:
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var rx := maxf((x1 - x0) * 0.5, 0.5)
	var ry := maxf((y1 - y0) * 0.5, 0.5)
	var steps := int(maxf(rx, ry) * 8.0) + 8
	if fill:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var nx := (x - cx) / rx
				var ny := (y - cy) / ry
				if nx * nx + ny * ny <= 1.0:
					_set_px(x, y)
	else:
		for s in steps:
			var a := TAU * s / float(steps)
			_set_px(int(round(cx + cos(a) * rx)), int(round(cy + sin(a) * ry)))


## `mDE_set_texture_template` MARK stamp at cursor - (5, 6).
func _stamp_glyph() -> void:
	var g := MARK_HEART
	match _stamp:
		1: g = MARK_STAR
		2: g = MARK_CIRCLE
		3: g = MARK_SQUARE
	for i in 144:
		if g[i] != 0:
			_set_px(_cursor.x + (i % 12) - 5, _cursor.y + int(i / 12.0) - 6)


# --- undo / paint helpers ---------------------------------------------

func _set_px(x: int, y: int) -> void:
	if x < 0 or x >= W or y < 0 or y >= H:
		return
	_work[y * W + x] = _paint


func _pal_at(x: int, y: int) -> int:
	return _work[clampi(y, 0, H - 1) * W + clampi(x, 0, W - 1)]


func _snapshot() -> void:
	_undo = _work.duplicate()
	_redo_toggle = false


## `mDE_undo` — 3-way swap (redoable single step).
func _do_undo() -> void:
	var t := _work
	_work = _undo
	_undo = t
	_redo_toggle = not _redo_toggle
	Audio.play_se(&"cursol")
	_refresh()


func _step_paint(dir: int) -> void:
	_paint = wrapi(_paint + dir, 1, 16)
	Audio.play_se(&"cursol")


func _cycle_mode(dir: int) -> void:
	_mode = wrapi(_mode + dir, 0, 4)
	_waku_armed = false
	_drawing = false
	if _mode == Mode.TOOL:
		_tool_row = _tool
		_tool_col = [_pen_size, _fill_mode, _shape, _stamp, 0][_tool]
	elif _mode == Mode.PALLET:
		_pal_row = _paint
	Audio.play_se(&"cursol")
	_refresh()


# --- save prompt ----------------------------------------------------

func _open_prompt() -> void:
	_prompt = true
	_prompt_idx = 0
	_drawing = false
	_promptbox.visible = true
	Audio.play_se(&"cursol")
	_refresh()


## 0 Save, 1 Keep editing, 2 Discard, 3 (wrap of -1) also Discard-cancel.
func _resolve_prompt(idx: int) -> void:
	match idx:
		0:
			_design.palette = _palette_no
			_design.pixels = _work.duplicate()
			_design.flag_set = true
			if Game != null and Game.designs != null:
				Game.designs.changed.emit()
			DesignTexture.clear_cache()
			if Game != null and Game.worn_design_slot == _slot:
				Game.design_changed.emit()
			Audio.play_se(&"cursol")
			close()
		1:
			_prompt = false
			_promptbox.visible = false
			_refresh()
		_:
			Audio.play_se(&"cursol")
			close()


# --- rendering ------------------------------------------------------

func _refresh() -> void:
	if not _open:
		return
	_title.text = "Design  —  %s" % (_design.name if _design != null else "?")
	var tn: String = TOOL_NAMES[_tool]
	var sub := ""
	match _tool:
		Tool.PEN: sub = TOOL_LABELS[0][_pen_size]
		Tool.NURI: sub = TOOL_LABELS[1][_fill_mode]
		Tool.WAKU: sub = TOOL_LABELS[2][_shape]
		Tool.MARK: sub = TOOL_LABELS[3][_stamp]
	var mode_names := ["MAIN", "PALETTE", "GRID", "TOOL"]
	_status.text = "%s  |  %s %s  |  colour %d  |  palette %d  |  (%d,%d)" % [
		mode_names[_mode], tn, sub, _paint, _palette_no, _cursor.x, _cursor.y]
	if _tool == Tool.WAKU and _waku_armed:
		_hint.text = "space set the far corner  ·  B cancel  ·  [ ] tabs  ·  enter save"
	elif _mode == Mode.PALLET:
		_hint.text = "↑↓ row  ·  space pick / next palette  ·  B prev palette  ·  [ ] tabs"
	elif _mode == Mode.TOOL:
		_hint.text = "arrows move  ·  space choose  ·  [ ] tabs"
	else:
		_hint.text = "arrows move  ·  space paint  ·  B eyedrop  ·  Z undo  ·  Tab grid  ·  , . colour  ·  1-5 tool  ·  [ ] tabs  ·  enter save"
	_promptbox.visible = _prompt
	if _prompt:
		var opts := ["Save it", "Keep editing", "Throw it out"]
		var pl: Label = _promptbox.get_node("V/Options")
		pl.text = "   ".join(range(3).map(func(i): return ("▶ " if i == _prompt_idx else "  ") + opts[i]))
	_canvas.queue_redraw()
	_swatches.queue_redraw()
	_panel.queue_redraw()


func _preview_work() -> PackedByteArray:
	## Live preview including the WAKU rubber-band (not committed to _work).
	if _tool == Tool.WAKU and _waku_armed:
		var save := _work
		_work = _work.duplicate()
		_do_shape()
		var out := _work
		_work = save
		return out
	return _work


func _draw_canvas() -> void:
	var sz := _canvas.size
	var cw := sz.x / float(W)
	var ch := sz.y / float(H)
	var pal := NeedleworkPalettes.colors(_palette_no)
	var px := _preview_work()
	for y in H:
		for x in W:
			_canvas.draw_rect(Rect2(x * cw, y * ch, cw + 1.0, ch + 1.0), pal[px[y * W + x] & 0xF])
	if _grid_on:
		var gc := Color(0, 0, 0, 0.18)
		for i in range(1, W):
			var lw := 1.5 if i % 4 == 0 else 0.6
			_canvas.draw_line(Vector2(i * cw, 0), Vector2(i * cw, sz.y), gc, lw)
			_canvas.draw_line(Vector2(0, i * ch), Vector2(sz.x, i * ch), gc, lw)
	# cursor / brush rect
	var bs := Vector2i(1, 1)
	if _tool == Tool.PEN and _pen_size == 1: bs = Vector2i(2, 2)
	elif _tool == Tool.PEN and _pen_size == 2: bs = Vector2i(3, 3)
	elif _tool == Tool.MARK: bs = Vector2i(12, 12)
	var c0 := _cursor
	if _tool == Tool.MARK: c0 -= Vector2i(5, 6)
	elif _tool == Tool.PEN and _pen_size >= 1: c0 -= Vector2i(1, 1)
	_canvas.draw_rect(Rect2(c0.x * cw, c0.y * ch, bs.x * cw, bs.y * ch), Color(1, 1, 1, 0.9), false, 2.0)
	_canvas.draw_rect(Rect2(_cursor.x * cw, _cursor.y * ch, cw, ch), Color(1, 0.2, 0.2, 1), false, 2.0)
	if _tool == Tool.WAKU and _waku_armed:
		_canvas.draw_rect(Rect2(_waku_anchor.x * cw, _waku_anchor.y * ch, cw, ch), Color(0.2, 0.8, 1, 1), false, 2.0)


func _draw_swatches() -> void:
	var pal := NeedleworkPalettes.colors(_palette_no)
	var n := NeedleworkPalettes.COLOR_COUNT
	var h := _swatches.size.y / float(n)
	for i in n:
		var r := Rect2(0, i * h, _swatches.size.x, h - 1.0)
		_swatches.draw_rect(r, pal[i])
		var sel := (i == _paint) or (_mode == Mode.PALLET and i == _pal_row)
		if sel:
			_swatches.draw_rect(r, Color(1, 1, 1, 1), false, 2.0)
		if i == _paint:
			_swatches.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(1, 0.85, 0.1, 1))


func _draw_panel() -> void:
	var font := _panel.get_theme_default_font()
	var fs := 13
	var y := 16.0
	var col := Color(0.15, 0.12, 0.1)
	_panel.draw_string(font, Vector2(6, y), "PALETTE %d" % _palette_no, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	y += 22
	if _mode == Mode.TOOL:
		for row in 5:
			_panel.draw_string(font, Vector2(6, y), TOOL_NAMES[row], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.9, 0.4, 0.1) if row == _tool_row else col)
			y += 16
			var labels: Array = TOOL_LABELS[row]
			for c in labels.size():
				var mark := "▶" if (row == _tool_row and c == _tool_col) else "  "
				_panel.draw_string(font, Vector2(16, y), "%s %s" % [mark, labels[c]], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
				y += 13
			y += 4
	else:
		var lines := [
			"[ / ]  mode tab",
			"1-5    tool",
			"Tab    grid " + ("on" if _grid_on else "off"),
			", .    colour",
			"B      eyedropper",
			"Z      undo/redo",
			"Enter  save / exit",
		]
		for s in lines:
			_panel.draw_string(font, Vector2(6, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
			y += 15
