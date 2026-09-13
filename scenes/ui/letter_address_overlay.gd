extends CanvasLayer

## Address book (`m_address_ovl.c`) — step 1 of writing a letter. Lists "Museum"
## (`mPr_CheckMuseumAddress`, used only to mail a raw fossil in for identification) plus
## every villager who has a "memory" of the player (`mNpc_GetAnimalMemoryIdx`,
## `Relationship.MET` here — `PostUse.met_villager_candidates()`). Decomp also lists
## other player-residents via memory card; this port has no multiplayer, so that's
## skipped entirely rather than simplified.
##
## Picking an entry closes this overlay and opens the paper picker
## (`letter_paper_picker_overlay`) directly — no callback plumbing, matching how
## `design_list_overlay.gd` hands off to `design_editor_overlay.gd`.

var _open: bool = false
var _entries: Array[Dictionary] = []
var _sel: int = 0

@onready var _root: Control = $Root
@onready var _list: Control = $Root/Frame/Box/List
@onready var _hint: Label = $Root/Frame/Box/Hint


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("letter_address_ui")
	_root.visible = false
	_list.draw.connect(_draw_list)
	_list.gui_input.connect(_on_list_input)
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_entries = [{"id": PostUse.MUSEUM_RECIPIENT_ID, "name": PostUse.MUSEUM_RECIPIENT_NAME}]
	_entries.append_array(PostUse.met_villager_candidates())
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
		KEY_UP, KEY_W:
			_sel = wrapi(_sel - 1, 0, _entries.size())
			Audio.play_se(&"cursol")
		KEY_DOWN, KEY_S:
			_sel = wrapi(_sel + 1, 0, _entries.size())
			Audio.play_se(&"cursol")
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_confirm()
			return
		KEY_ESCAPE, KEY_B:
			close()
			return
	_refresh()


func _on_list_input(event: InputEvent) -> void:
	if not _open:
		return
	var idx := _row_at(event)
	if event is InputEventMouseMotion and idx >= 0:
		_sel = idx
		_refresh()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and idx >= 0:
		_sel = idx
		_confirm()


func _row_at(event: InputEvent) -> int:
	if not (event is InputEventMouse) or _entries.is_empty():
		return -1
	var y: float = (event as InputEventMouse).position.y
	var row_h: float = _list.size.y / float(_entries.size())
	var idx := int(y / row_h)
	return idx if idx >= 0 and idx < _entries.size() else -1


func _confirm() -> void:
	if _entries.is_empty():
		close()
		return
	var recipient: Dictionary = _entries[_sel]
	Audio.play_se(&"cursol")
	close()
	var picker: Node = get_tree().get_first_node_in_group("letter_paper_picker_ui")
	if picker != null and picker.has_method("open"):
		picker.call("open", recipient)


func _refresh() -> void:
	if not _open:
		return
	_hint.text = "arrows choose  ·  space confirm  ·  B/Esc cancel" if not _entries.is_empty() \
		else "No one to write to yet — get to know a neighbour first!"
	_list.queue_redraw()


func _draw_list() -> void:
	var font := _list.get_theme_default_font()
	if _entries.is_empty():
		return
	var row_h: float = _list.size.y / float(_entries.size())
	for i in _entries.size():
		var rect := Rect2(0, i * row_h, _list.size.x, row_h - 2.0)
		var bg := Color(1, 0.92, 0.55, 1) if i == _sel else Color(1, 1, 1, 0.85)
		_list.draw_rect(rect, bg)
		var name: String = str(_entries[i].get("name", ""))
		_list.draw_string(font, rect.position + Vector2(10, row_h * 0.65), name,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20, 15, Color(0.2, 0.15, 0.1))
