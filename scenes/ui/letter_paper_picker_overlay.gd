extends CanvasLayer

## Stationery picker — step 2 of writing a letter. Decomp ties the paper design to
## whichever stationery *item* you own and select (`mTG_write_proc`); this port has no
## stationery-item economy, so the player instead freely picks any of the 64 real
## designs `LetterChrome` already renders — a deliberate, approved simplification (see
## the plan doc), not a missing feature.

const COLS := 8
const ROWS := 8
const PAPER_COUNT := LetterChrome.PAPER_COUNT

var _open: bool = false
var _recipient: Dictionary = {}
var _sel: int = 0

@onready var _root: Control = $Root
@onready var _grid: Control = $Root/Frame/Box/Grid
@onready var _hint: Label = $Root/Frame/Box/Hint


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("letter_paper_picker_ui")
	_root.visible = false
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_on_grid_input)
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


func open(recipient: Dictionary) -> void:
	if _open:
		return
	_recipient = recipient
	_sel = 0
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


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match (event as InputEventKey).keycode:
		KEY_LEFT, KEY_A: _sel = wrapi(_sel - 1, 0, PAPER_COUNT); Audio.play_se(&"cursol")
		KEY_RIGHT, KEY_D: _sel = wrapi(_sel + 1, 0, PAPER_COUNT); Audio.play_se(&"cursol")
		KEY_UP, KEY_W: _sel = wrapi(_sel - COLS, 0, PAPER_COUNT); Audio.play_se(&"cursol")
		KEY_DOWN, KEY_S: _sel = wrapi(_sel + COLS, 0, PAPER_COUNT); Audio.play_se(&"cursol")
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_confirm()
			return
		KEY_ESCAPE, KEY_B:
			close()
			return
	_refresh()


func _on_grid_input(event: InputEvent) -> void:
	if not _open:
		return
	var idx := _cell_at(event)
	if event is InputEventMouseMotion and idx >= 0:
		_sel = idx
		_refresh()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and idx >= 0:
		_sel = idx
		_confirm()


func _cell_at(event: InputEvent) -> int:
	if not (event is InputEventMouse):
		return -1
	var p: Vector2 = (event as InputEventMouse).position
	var cw := _grid.size.x / float(COLS)
	var chh := _grid.size.y / float(ROWS)
	var cx := int(p.x / cw)
	var cy := int(p.y / chh)
	if cx < 0 or cx >= COLS or cy < 0 or cy >= ROWS:
		return -1
	var idx := cy * COLS + cx
	return idx if idx < PAPER_COUNT else -1


func _confirm() -> void:
	var paper_type := _sel
	Audio.play_se(&"cursol")
	close()
	var writer: Node = get_tree().get_first_node_in_group("letter_writer_ui")
	if writer != null and writer.has_method("open"):
		writer.call("open", _recipient, paper_type)


func _refresh() -> void:
	if not _open:
		return
	_hint.text = "arrows choose  ·  space confirm  ·  B/Esc cancel"
	_grid.queue_redraw()


func _draw_grid() -> void:
	var cw := _grid.size.x / float(COLS)
	var chh := _grid.size.y / float(ROWS)
	for i in PAPER_COUNT:
		var cx := (i % COLS) * cw
		var cy := int(i / COLS) * chh
		var pad := 3.0
		var cell := Rect2(cx + pad, cy + pad, cw - pad * 2, chh - pad * 2)
		var tex: Texture2D = LetterChrome.paper_texture(i)
		if tex != null:
			_grid.draw_texture_rect(tex, cell, false)
		else:
			_grid.draw_rect(cell, Color(1, 1, 1, 1))
		if i == _sel:
			_grid.draw_rect(cell, Color(1, 0.2, 0.2, 1), false, 3.0)
