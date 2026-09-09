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

signal closed

enum ListMode { PICK_EDIT, PICK_TRADE, MANAGE }

const COLS := 4
const ROWS := 2

var _open: bool = false
var _mode: int = ListMode.PICK_EDIT
var _sel: int = 0
var _held: int = -1  ## MANAGE pick-up slot
var _cb: Callable = Callable()

@onready var _root: Control = $Root
@onready var _grid: Control = $Root/Frame/Box/Grid
@onready var _title: Label = $Root/Frame/Box/Header/Title
@onready var _name: Label = $Root/Frame/Box/Footer/DesignName
@onready var _hint: Label = $Root/Frame/Box/Footer/Hint


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("design_list_ui")
	_root.visible = false
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_on_grid_input)
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


func open(mode: String, callback: Callable = Callable()) -> void:
	if _open:
		return
	if Game == null or Game.designs == null:
		return
	match mode:
		"pick_edit": _mode = ListMode.PICK_EDIT
		"pick_trade": _mode = ListMode.PICK_TRADE
		_: _mode = ListMode.MANAGE
	_cb = callback
	_sel = 0
	_held = -1
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")
	_refresh()


func close(chosen: int = -1) -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
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
		KEY_W:
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


func _on_grid_input(event: InputEvent) -> void:
	if not _open:
		return
	var cell := _cell_at(event)
	if event is InputEventMouseMotion and cell >= 0:
		_sel = cell
		_refresh()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and cell >= 0:
		_sel = cell
		_activate()
		_refresh()


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
	return cy * COLS + cx


func _refresh() -> void:
	if not _open:
		return
	var titles := {
		ListMode.PICK_EDIT: "Which design?",
		ListMode.PICK_TRADE: "Pick a design",
		ListMode.MANAGE: "Design book",
	}
	_title.text = titles[_mode]
	var d: DesignPattern = Game.designs.player[Game.designs.resolved_index(_sel)]
	_name.text = d.name if d != null else ""
	if _mode == ListMode.MANAGE:
		var worn := Game.worn_design_slot if Game != null else -1
		_hint.text = "space swap  ·  E edit  ·  W %s  ·  B/Esc close%s" % [
			"take off" if worn == _sel else "wear",
			"   (wearing \"%s\")" % Game.designs.player[Game.designs.resolved_index(worn)].name if worn >= 0 else ""]
	else:
		_hint.text = "arrows choose  ·  space confirm  ·  B/Esc cancel"
	_grid.queue_redraw()


func _draw_grid() -> void:
	var cw := _grid.size.x / float(COLS)
	var chh := _grid.size.y / float(ROWS)
	var font := _grid.get_theme_default_font()
	for i in COLS * ROWS:
		var cx := (i % COLS) * cw
		var cy := int(i / COLS) * chh
		var pad := 8.0
		var cell := Rect2(cx + pad, cy + pad, cw - pad * 2, chh - pad * 2 - 14)
		_grid.draw_rect(cell, Color(1, 1, 1, 1))
		_grid.draw_rect(cell, Color(0.5, 0.4, 0.3, 1), false, 1.5)
		var idx := Game.designs.resolved_index(i)
		var dp: DesignPattern = Game.designs.player[idx]
		if dp != null:
			var img := DesignTexture.image(dp)
			var tex := ImageTexture.create_from_image(img)
			_grid.draw_texture_rect(tex, cell, false)
		var label := dp.name if dp != null else "blank"
		_grid.draw_string(font, Vector2(cx + pad, cy + chh - pad), label,
			HORIZONTAL_ALIGNMENT_LEFT, cw - pad * 2, 11, Color(0.2, 0.15, 0.1))
		if Game != null and Game.worn_design_slot == i:
			_grid.draw_string(font, Vector2(cx + pad, cy + pad + 12), "WORN",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.45, 0.1))
		if i == _held:
			_grid.draw_rect(Rect2(cx + 2, cy + 2, cw - 4, chh - 4), Color(1, 0.8, 0.1, 1), false, 3.0)
		if i == _sel:
			_grid.draw_rect(Rect2(cx + 4, cy + 4, cw - 8, chh - 8), Color(1, 0.2, 0.2, 1), false, 3.0)
