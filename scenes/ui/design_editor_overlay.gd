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
## Presentation follows the original screen: the `des_win_shitaT_model` board (baked to
## `ui/design/window_shell.png`), the four mode areas, the 1:1 preview, the canvas,
## the 15-colour column with the palette switch and number, the tool icons and the
## per-tool cursor, all at their `des_win` / `des_tool` coordinates. Textures come
## from `tools/asset_pipeline/design_ui.py` (`--kind design-ui`).
##
## Controls are keyboard + mouse; the decomp C-stick / D-pad / C-button bindings map to
## arrows, `[` `]`, `Tab`, `Z`, `,` `.` and number keys.

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
@onready var _screen: Control = $Root/Screen
@onready var _chrome: Control = $Root/Screen/Chrome
@onready var _tools: Control = $Root/Screen/Tools
@onready var _marks: Control = $Root/Screen/Marks
@onready var _color_mark: Control = $Root/Screen/ColorMark
@onready var _pal_mark: Control = $Root/Screen/PalMark
@onready var _cursor_view: Control = $Root/Screen/Cursor
@onready var _promptbox: PanelContainer = $Root/Prompt

var _tex_cache: Dictionary = {}


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("design_ui")
	_root.visible = false
	_chrome.draw.connect(_draw_chrome)
	_tools.draw.connect(_draw_tools)
	_marks.draw.connect(_draw_marks)
	_color_mark.draw.connect(_draw_color_mark)
	_pal_mark.draw.connect(_draw_pal_mark)
	_cursor_view.draw.connect(_draw_cursor)
	_screen.gui_input.connect(_on_screen_input)
	_root.resized.connect(_fit_screen)
	_fit_screen()
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

## Mouse maps onto the regions the pad cursor visits: the canvas (MAIN), the colour
## column and palette switch (PALLET), the 1:1 preview (GRID), the tool icons (TOOL)
## and the Start / Quit buttons.
func _on_screen_input(event: InputEvent) -> void:
	if not _open or _prompt or not (event is InputEventMouse):
		return
	var u := _units((event as InputEventMouse).position)
	var cell := _cell_at(u)
	if event is InputEventMouseMotion:
		if cell.x >= 0 and _mode == Mode.MAIN:
			_cursor = cell
			if _drawing and _tool == Tool.PEN:
				_stroke_to(cell)
			_refresh()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drawing = false
			_last_paint = Vector2i(-1, -1)
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_step_paint(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_step_paint(1)
		MOUSE_BUTTON_RIGHT:
			if cell.x >= 0:
				_paint = _pal_at(cell.x, cell.y)
			elif KIRIKAE.has_point(u):
				_palette_no = wrapi(_palette_no - 1, 0, 16)
				Audio.play_se(&"cursol")
		MOUSE_BUTTON_LEFT:
			_click(u, cell)
		_:
			return
	_refresh()


func _click(u: Vector2, cell: Vector2i) -> void:
	if cell.x >= 0:
		if _mode != Mode.MAIN:
			_mode = Mode.MAIN
			_waku_armed = false
		_cursor = cell
		_apply_tool_press()
		return
	if KIRIKAE.has_point(u):
		_mode = Mode.PALLET
		_pal_row = 0
		_palette_no = wrapi(_palette_no + 1, 0, 16)
		Audio.play_se(&"cursol")
		return
	if SWATCH_COLUMN.has_point(u):
		_paint = clampi(1 + int((SWATCH_COLUMN.end.y - u.y) / 10.0), 1, 15)
		_mode = Mode.MAIN
		Audio.play_se(&"cursol")
		return
	if (AREAS[Mode.GRID] as Rect2).has_point(u):
		_grid_on = not _grid_on
		Audio.play_se(&"cursol")
		return
	if START_BUTTON.has_point(u) or QUIT_BUTTON.has_point(u):
		_open_prompt()
		return
	var hit := _tool_at(u)
	if hit.x >= 0:
		_tool_row = hit.x
		_tool_col = hit.y if _mode == Mode.TOOL else int([_pen_size, _fill_mode, _shape, _stamp, 0][hit.x])
		_commit_tool_pick()


## Screen-local pixels (320x240, top-left origin) → design-window units (centre, y up).
func _units(local: Vector2) -> Vector2:
	return Vector2(local.x - 160.0, 120.0 - local.y)


func _cell_at(u: Vector2) -> Vector2i:
	if not CANVAS.has_point(u):
		return Vector2i(-1, -1)
	var px := int((u.x - CANVAS.position.x) / 5.0)
	var py := int((CANVAS.end.y - u.y) / 5.0)
	return Vector2i(clampi(px, 0, W - 1), clampi(py, 0, H - 1))


## (row, col) of the tool icon under `u`, or (-1, -1). Only column 0 shows outside TOOL
## mode (`des_tool_*1T_model`).
func _tool_at(u: Vector2) -> Vector2i:
	for row in 5:
		var cols: int = int(TOOL_ROWS[row]) if _mode == Mode.TOOL else 1
		for col in range(cols - 1, -1, -1):
			if _tool_rect(row, col).has_point(u):
				return Vector2i(row, col)
	return Vector2i(-1, -1)


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
#
# Layout is `des_win.c` / `des_tool.c` / `des_suuji.c` / `des_marking.c` / `des_cursor.c`
# in their own 320x240 screen units (centre origin, y up); `Screen` is that space scaled
# to fit. Rects below are (min corner, size) in those units.

const CANVAS := Rect2(-81, -80, 160, 160)  ## `des_win_main_model`
const PREVIEW := Rect2(-128, 48, 32, 32)  ## `des_win_toubai_model` (1:1)
const KIRIKAE := Rect2(97, 58, 26, 26)  ## palette switch
const SWATCH_COLUMN := Rect2(98, -92, 24, 150)  ## `des_win_waku2_model`
const START_BUTTON := Rect2(38, -101, 18, 18)
const QUIT_BUTTON := Rect2(55, -98, 28, 14)
## `area_table` in `mDE_set_frame_main_dl`, indexed by Mode (area1, area2, area4, area3).
const AREAS := [Rect2(-87, -86, 172, 172), Rect2(90, -101, 40, 200), Rect2(-132, 44, 40, 40), Rect2(-130, -98, 36, 132)]
const AREA_ACTIVE := Color(40 / 255.0, 235 / 255.0, 160 / 255.0, 180 / 255.0)
const AREA_IDLE := Color(90 / 255.0, 70 / 255.0, 40 / 255.0, 180 / 255.0)
## `des_win_waku_model`: frames behind the canvas and the preview.
const WAKU := [Rect2(-82, -81, 162, 162), Rect2(-129, 47, 34, 34)]
const DARK := Color(60 / 255.0, 60 / 255.0, 60 / 255.0)
const GRID_DOTS := Color(0, 0, 0, 100 / 255.0)
## `des_win_grid2_model`: centre cross on the canvas and the preview.
const GRID2 := [Rect2(-1, -80, 2, 160), Rect2(-81, -1, 160, 2), Rect2(-113, 48, 2, 32), Rect2(-128, 63, 32, 2)]
const GRID2_COLOR := Color(60 / 255.0, 85 / 255.0, 70 / 255.0, 120 / 255.0)
const SUUJI_PALLET := Color(215 / 255.0, 30 / 255.0, 30 / 255.0, 1.0)
const SUUJI_IDLE := Color(1.0, 245 / 255.0, 215 / 255.0, 180 / 255.0)
const MARK_TOOL := Color(185 / 255.0, 50 / 255.0, 50 / 255.0)
const MARK_IDLE := Color(215 / 255.0, 195 / 255.0, 195 / 255.0)
const CURSOR_PRIM := Color(60 / 255.0, 70 / 255.0, 60 / 255.0)
## Tool icon UVs run -1.34..33.34 over a 26-unit quad (clamped edges).
const ICON_SRC := Rect2(-1.34375, -1.34375, 34.6875, 34.6875)
const TOOL_TEX := ["des_tool_pen%d_tex_rgb_ia8", "des_tool_nuri%d_tex_rgb_ia8", "des_tool_waku%d_tex_rgb_ia8", "des_tool_mark%d_tex_rgb_ia8"]


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func _tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := "res://assets/generated/ui/design/%s.png" % name
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[name] = t
	return t


## Units rect → Screen-local pixels.
func _px(r: Rect2) -> Rect2:
	return Rect2(r.position.x + 160.0, 120.0 - r.end.y, r.size.x, r.size.y)


func _at(center: Vector2, size: Vector2) -> Rect2:
	return _px(Rect2(center - size * 0.5, size))


func _tool_rect(row: int, col: int) -> Rect2:
	return Rect2(-125 + 24 * col, 3 - 24 * row, 26, 26)


func _refresh() -> void:
	if not _open:
		return
	var cm := _color_mark.material as ShaderMaterial
	if cm != null:
		cm.set_shader_parameter("prim", Color8(235, 235, 235) if _mode == Mode.PALLET else Color8(205, 185, 185))
		cm.set_shader_parameter("env", Color8(105, 85, 115))
	var pm := _pal_mark.material as ShaderMaterial
	if pm != null:
		pm.set_shader_parameter("prim", Color8(255, 80, 80))
		pm.set_shader_parameter("env", Color8(30, 30, 30))
	_promptbox.visible = _prompt
	if _prompt:
		var opts := ["Save it", "Keep editing", "Throw it out"]
		var pl: Label = _promptbox.get_node("V/Options")
		pl.text = "   ".join(range(3).map(func(i): return ("▶ " if i == _prompt_idx else "  ") + opts[i]))
	for n: CanvasItem in [_chrome, _tools, _marks, _color_mark, _pal_mark, _cursor_view]:
		n.queue_redraw()


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


## `mDE_set_frame_main_dl`: board areas, buttons, frames, preview, canvas, colours, grid;
## then `mDE_set_frame_suuji_dl`'s palette number.
func _draw_chrome() -> void:
	var ci := _chrome
	for m in AREAS.size():
		ci.draw_rect(_px(AREAS[m]), AREA_ACTIVE if m == _mode else AREA_IDLE)
	var start := _tex("des_win_start_tex")
	if start != null:
		ci.draw_texture_rect(start, _px(START_BUTTON), false)
	var quit := _tex("kei_win_quit_tex")
	if quit != null:
		ci.draw_texture_rect(quit, _px(QUIT_BUTTON), false)
	for r: Rect2 in WAKU:
		ci.draw_rect(_px(r), DARK)
	var pal := NeedleworkPalettes.colors(_palette_no)
	var px := _preview_work()
	_draw_pixels(ci, _px(PREVIEW), px, pal)
	_draw_pixels(ci, _px(CANVAS), px, pal)

	var swatch := _tex("des_win_color_tex")
	for i in 15:
		var r := _px(Rect2(98, 48 - 10 * i, 24, 10))
		if swatch != null:
			ci.draw_texture_rect_region(swatch, r, Rect2(0, 0, 32, 16), pal[i + 1])
		else:
			ci.draw_rect(r, pal[i + 1])
	var cwaku := _tex("des_win_cwaku_tex")
	if cwaku != null:
		ci.draw_texture_rect_region(cwaku, _px(SWATCH_COLUMN), Rect2(0, 0, 32, 240), DARK)

	if _grid_on:
		var sen := _tex("des_win_sen_tex")
		if sen != null:
			ci.draw_texture_rect_region(sen, _px(CANVAS), Rect2(0, 0, 512, 512), GRID_DOTS)
		for r: Rect2 in GRID2:
			ci.draw_rect(_px(r), GRID2_COLOR)

	var prim := SUUJI_PALLET if _mode == Mode.PALLET else SUUJI_IDLE
	var slash := PackedVector2Array()
	for p: Vector2 in [Vector2(112, 96), Vector2(110, 96), Vector2(108, 87), Vector2(110, 87)]:
		slash.append(Vector2(p.x + 160.0, 120.0 - p.y))
	ci.draw_colored_polygon(slash, prim)
	var no := _palette_no + 1
	if no >= 10:
		_draw_digit(ci, 1, 93, prim)
		_draw_digit(ci, no % 10, 100, prim)
	else:
		_draw_digit(ci, no, 98, prim)
	_draw_digit(ci, 1, 113, prim)
	_draw_digit(ci, 6, 120, prim)


func _draw_digit(ci: CanvasItem, d: int, x0: float, prim: Color) -> void:
	var t := _tex("des_win_suuji%d_tex_rgb_i4" % d)
	if t != null:
		ci.draw_texture_rect_region(t, _px(Rect2(x0, 87, 7, 12)), Rect2(1.59375, 0, 11.21875, 16), prim)


func _draw_pixels(ci: CanvasItem, r: Rect2, px: PackedByteArray, pal: PackedColorArray) -> void:
	var cw := r.size.x / float(W)
	var ch := r.size.y / float(H)
	for y in H:
		for x in W:
			ci.draw_rect(Rect2(r.position.x + x * cw, r.position.y + y * ch, cw + 0.02, ch + 0.02), pal[px[y * W + x] & 0xF])


## `mDE_set_frame_tool_dl`: every variant in TOOL mode, otherwise each row's current one.
func _draw_tools() -> void:
	var ci := _tools
	var kirikae := _tex("des_win_kirikae_tex")
	if kirikae != null:
		ci.draw_texture_rect_region(kirikae, _px(KIRIKAE), ICON_SRC)
	var current := [_pen_size, _fill_mode, _shape, _stamp]
	for row in 4:
		var cols: int = int(TOOL_ROWS[row]) if _mode == Mode.TOOL else 1
		for col in cols:
			var variant: int = col if _mode == Mode.TOOL else int(current[row])
			var t := _tex(TOOL_TEX[row] % (variant + 1))
			if t == null:
				continue
			var src := Rect2(0, 0, 32, 32) if (row == 1 and col == 5) else ICON_SRC
			ci.draw_texture_rect_region(t, _px(_tool_rect(row, col)), src)
	var undo := _tex("des_tool_undo_tex")
	if undo != null:
		ci.draw_texture_rect_region(undo, _px(_tool_rect(4, 0)), ICON_SRC)


## `mDE_set_frame_mark_dl`: the tool frame and the palette-switch frame.
func _draw_marks() -> void:
	var t := _tex("des_win_marking_tex")
	if t == null:
		return
	var c := Vector2(-112, 16 - _tool * 24)
	var col := MARK_IDLE
	if _mode == Mode.TOOL:
		c = Vector2(-112 + _tool_col * 24, 16 - _tool_row * 24)
		col = MARK_TOOL
	_marks.draw_texture_rect_region(t, _at(c, Vector2(28, 28)), Rect2(0, 0, 32, 32), col)
	if _mode == Mode.PALLET and _pal_row == 0:
		_marks.draw_texture_rect_region(t, _at(Vector2(110, 71), Vector2(28, 28)), Rect2(0, 0, 32, 32), MARK_TOOL)


func _draw_color_mark() -> void:
	var t := _tex("des_win_marking3_tex")
	if t != null:
		_color_mark.draw_texture_rect_region(t, _at(Vector2(110, 63 - _paint * 10), Vector2(26, 12)), Rect2(0, 0, 32, 16))


func _draw_pal_mark() -> void:
	var t := _tex("des_win_marking3_tex")
	if t != null and _mode == Mode.PALLET and _pal_row > 0:
		_pal_mark.draw_texture_rect_region(t, _at(Vector2(110, 63 - _pal_row * 10), Vector2(26, 12)), Rect2(0, 0, 32, 16))


## `mDE_set_frame_cursor_dl` (MAIN only): the tool's cursor sprite, offset from the
## cell so the pencil tip / bucket spout / stamp sits on it.
func _draw_cursor() -> void:
	if _mode != Mode.MAIN or _prompt:
		return
	var base := Vector2(_cursor.x * 5 - 75, 75 - _cursor.y * 5)
	match _tool:
		Tool.PEN:
			_cursor_sprite("des_cursor_pen_tex", base + Vector2(8, 13), 22, Rect2(0, 0, 32, 32), Color.WHITE)
		Tool.NURI:
			_cursor_sprite("des_cursor_nuri_tex", base + Vector2(1, 11), 20, Rect2(0, 0, 32, 32), Color.WHITE)
		Tool.WAKU:
			if _waku_armed:
				var anchor := Vector2(_waku_anchor.x * 5 - 75, 75 - _waku_anchor.y * 5)
				_cursor_sprite("des_cursor_sen_tex", anchor + Vector2(-3, 10), 16, Rect2(0, 0, 32, 32), Color.WHITE)
				_cursor_sprite("des_cursor_waku_tex", base + Vector2(-4, 3), 16, Rect2(0, 32, 32, 32), Color.WHITE)
			else:
				_cursor_sprite("des_cursor_waku_tex", base + Vector2(-3, 2), 16, Rect2(0, 0, 32, 32), Color.WHITE)
		Tool.MARK:
			_cursor_sprite("des_cursor_mark%d_tex" % (_stamp + 1), base + Vector2(-1, 8), 20, Rect2(0, 0, 32, 32), CURSOR_PRIM)
		Tool.UNDO:
			_cursor_sprite("des_cursor_undo_tex", base + Vector2(-1, 8), 20, Rect2(0, 0, 32, 32), CURSOR_PRIM)


func _cursor_sprite(name: String, center: Vector2, size: float, src: Rect2, tint: Color) -> void:
	var t := _tex(name)
	if t != null:
		_cursor_view.draw_texture_rect_region(t, _at(center, Vector2(size, size)), src, tint)
