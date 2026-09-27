extends CanvasLayer

## "Save a pattern" — the design album (`mSM_OVL_NEEDLEWORK` opened with
## `mNW_OPEN_CPORIGINAL` + `m_cporiginal_ovl.c`). Top: one folder of the album,
## 12 designs, with the 8 folder tabs (`page_order`, the open folder comes to the
## front, `mCO_change_up_folder`). Bottom: the player's 8 designs. The hand picks a
## design up and drops it on another to swap them (`mCO_swap_image`): album ↔ album,
## album ↔ pockets, or two of your own (a display-order swap, `mNW_swap_image_no`).
## R renames the open folder (`mLE_TYPE_*` folder name, 12 characters).
##
## Closing asks whether to keep the changes (`mSM_OVL_EDITENDCHK`): keep writes the
## album back, discard restores everything as it was when the album opened.
##
## `open(callback)` — callback() runs after the album closes either way.

signal closed

enum Region { ALBUM, MINE }

const ALBUM_COLS := 6
const ALBUM_ROWS := 2
const MINE_COLS := 8

var _open: bool = false
var _cb: Callable = Callable()
var _page: int = 0
var _region: int = Region.ALBUM
var _sel: int = 0
## Picked-up design: `[region, page, idx]`, or empty.
var _held: Array = []
var _confirm: bool = false
var _backup: Dictionary = {}
var _worn_before: PackedByteArray = PackedByteArray()

@onready var _root: Control = $Root
@onready var _tabs: Control = $Root/Frame/Box/Tabs
@onready var _album: Control = $Root/Frame/Box/Album
@onready var _mine: Control = $Root/Frame/Box/Mine
@onready var _title: Label = $Root/Frame/Box/Header/Title
@onready var _name: Label = $Root/Frame/Box/Footer/DesignName
@onready var _hint: Label = $Root/Frame/Box/Footer/Hint


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("design_album_ui")
	_root.visible = false
	_tabs.draw.connect(_draw_tabs)
	_album.draw.connect(_draw_album)
	_mine.draw.connect(_draw_mine)
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


func open(callback: Callable = Callable()) -> void:
	if _open or Game == null or Game.designs == null:
		return
	_cb = callback
	_backup = Game.designs.to_save()
	_worn_before = _worn_pixels()
	_page = 0
	_region = Region.ALBUM
	_sel = 0
	_held = []
	_confirm = false
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")
	_refresh()


## `keep` false → put everything back as it was when the album opened.
func close(keep: bool = true) -> void:
	if not _open:
		return
	if not keep and not _backup.is_empty():
		Game.designs.apply_snapshot(_backup)
		Game.designs.changed.emit()
	DesignTexture.clear_cache()
	## `mCO_move_Wait` → `change_flg`: the worn slot now holds a different design, so the
	## player changes into it (`aNNW_TALK_CLOTH_CHANGE3`).
	if Game.worn_design_slot >= 0 and _worn_pixels() != _worn_before:
		Game.design_changed.emit()
	_open = false
	_root.visible = false
	set_process_unhandled_input(false)
	_backup = {}
	var cb := _cb
	_cb = Callable()
	closed.emit()
	if cb.is_valid():
		cb.call()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key := (event as InputEventKey).keycode
	if _confirm:
		match key:
			KEY_Y, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				close(true)
			KEY_N:
				close(false)
			KEY_ESCAPE, KEY_B:
				_confirm = false
				_refresh()
		return
	match key:
		KEY_LEFT, KEY_A: _move(-1, 0)
		KEY_RIGHT, KEY_D: _move(1, 0)
		KEY_UP, KEY_W: _move(0, -1)
		KEY_DOWN, KEY_S: _move(0, 1)
		KEY_Q, KEY_PAGEUP: flip_page(-1)
		KEY_E, KEY_PAGEDOWN: flip_page(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: activate()
		KEY_R: _rename_folder()
		KEY_ESCAPE, KEY_B:
			if not _held.is_empty():
				_held = []
			else:
				_confirm = true
	_refresh()


func _move(dx: int, dy: int) -> void:
	Audio.play_se(&"cursol")
	if _region == Region.ALBUM:
		var c: int = _sel % ALBUM_COLS
		var r: int = _sel / ALBUM_COLS
		if dy > 0 and r == ALBUM_ROWS - 1:
			_region = Region.MINE
			_sel = clampi(roundi(float(c) * (MINE_COLS - 1) / (ALBUM_COLS - 1)), 0, MINE_COLS - 1)
			return
		c = wrapi(c + dx, 0, ALBUM_COLS)
		r = clampi(r + dy, 0, ALBUM_ROWS - 1)
		_sel = r * ALBUM_COLS + c
	else:
		if dy < 0:
			_region = Region.ALBUM
			_sel = (ALBUM_ROWS - 1) * ALBUM_COLS + clampi(roundi(float(_sel) * (ALBUM_COLS - 1) / (MINE_COLS - 1)), 0, ALBUM_COLS - 1)
			return
		_sel = wrapi(_sel + dx, 0, MINE_COLS)


## Bring another folder to the front (`mCO_change_up_folder`).
func flip_page(step: int) -> void:
	_page = wrapi(_page + step, 0, DesignBook.ALBUM_PAGES)
	Audio.play_se(&"cursol")


## Pick the design under the hand up, or drop the held one here and swap.
func activate() -> void:
	var here: Array = _spot(_region, _sel)
	if _held.is_empty():
		_held = here
		Audio.play_se(&"cursol")
		return
	if _held == here:
		_held = []
		return
	swap(_held, here)
	_held = []
	Audio.play_se(&"cursol")


## A hand position: your designs don't belong to a folder.
func _spot(region: int, idx: int) -> Array:
	return [region, _page if region == Region.ALBUM else -1, idx]


## `mCO_swap_image` over two `[region, page, idx]` spots.
static func swap(a: Array, b: Array) -> void:
	var book: DesignBook = Game.designs
	var a_mine: bool = int(a[0]) == Region.MINE
	var b_mine: bool = int(b[0]) == Region.MINE
	if a_mine and b_mine:
		book.swap_player_order(int(a[2]), int(b[2]))
	elif not a_mine and not b_mine:
		book.album_swap(int(a[1]), int(a[2]), int(b[1]), int(b[2]))
	elif a_mine:
		book.album_swap_player(int(b[1]), int(b[2]), int(a[2]))
	else:
		book.album_swap_player(int(a[1]), int(a[2]), int(b[2]))


func _rename_folder() -> void:
	var name_ui: Node = get_tree().get_first_node_in_group("name_entry_ui")
	if name_ui == null or not name_ui.has_method("open"):
		return
	var page := _page
	## The name entry sits above this layer; hide the album until it's done.
	_root.visible = false
	set_process_unhandled_input(false)
	name_ui.call("open", Game.designs.album_names[page].strip_edges(), func(text: String) -> void:
		Game.designs.set_folder_name(page, text)
		_root.visible = _open
		set_process_unhandled_input(_open)
		_refresh())


func _worn_pixels() -> PackedByteArray:
	if Game == null or Game.designs == null or Game.worn_design_slot < 0:
		return PackedByteArray()
	return Game.designs.resolved(Game.worn_design_slot).pixels.duplicate()


func _design_at(region: int, page: int, idx: int) -> DesignPattern:
	if region == Region.MINE:
		return Game.designs.resolved(idx)
	return Game.designs.album_design(page, idx)


func _folder_label(page: int) -> String:
	var nm: String = Game.designs.album_names[page].strip_edges()
	return nm if nm != "" else "Folder %d" % (page + 1)


func _refresh() -> void:
	if not _open:
		return
	_title.text = "Design album — %s" % _folder_label(_page)
	var d := _design_at(_region, _page, _sel)
	_name.text = d.name if d != null and d.flag_set else ("(empty)" if _region == Region.ALBUM else d.name)
	if _confirm:
		_hint.text = "Save changes to the album?   Y/space keep  ·  N discard  ·  Esc back"
	elif not _held.is_empty():
		_hint.text = "space drop here to swap  ·  Esc put back"
	else:
		_hint.text = "arrows move  ·  space pick up  ·  Q/E folder  ·  R rename folder  ·  Esc done"
	_tabs.queue_redraw()
	_album.queue_redraw()
	_mine.queue_redraw()


func _draw_tabs() -> void:
	var w := _tabs.size.x / float(DesignBook.ALBUM_PAGES)
	var font := _tabs.get_theme_default_font()
	for p in DesignBook.ALBUM_PAGES:
		var r := Rect2(p * w + 2, 0, w - 4, _tabs.size.y)
		var on := p == _page
		_tabs.draw_rect(r, Color(0.98, 0.92, 0.78) if on else Color(0.78, 0.66, 0.5))
		_tabs.draw_rect(r, Color(0.45, 0.32, 0.2), false, 1.5)
		_tabs.draw_string(font, Vector2(r.position.x + 4, r.position.y + r.size.y - 6), _folder_label(p),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8, 11, Color(0.25, 0.18, 0.12))


func _draw_album() -> void:
	_draw_cells(_album, Region.ALBUM, ALBUM_COLS, ALBUM_ROWS)


func _draw_mine() -> void:
	_draw_cells(_mine, Region.MINE, MINE_COLS, 1)


func _draw_cells(host: Control, region: int, cols: int, rows: int) -> void:
	var cw := host.size.x / float(cols)
	var chh := host.size.y / float(rows)
	var font := host.get_theme_default_font()
	for i in cols * rows:
		var cx := (i % cols) * cw
		var cy := int(i / cols) * chh
		var pad := 6.0
		var cell := Rect2(cx + pad, cy + pad, cw - pad * 2, chh - pad * 2 - 12)
		var dp := _design_at(region, _page, i)
		host.draw_rect(cell, Color(1, 1, 1, 1))
		if dp != null and (dp.flag_set or region == Region.MINE):
			host.draw_texture_rect(ImageTexture.create_from_image(DesignTexture.image(dp)), cell, false)
		host.draw_rect(cell, Color(0.5, 0.4, 0.3, 1), false, 1.5)
		if region == Region.MINE and Game.worn_design_slot == i:
			host.draw_string(font, Vector2(cx + pad, cy + pad + 11), "WORN",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.1, 0.45, 0.1))
		if _held == _spot(region, i):
			host.draw_rect(Rect2(cx + 2, cy + 2, cw - 4, chh - 4), Color(1, 0.8, 0.1, 1), false, 3.0)
		if region == _region and i == _sel:
			host.draw_rect(Rect2(cx + 3, cy + 3, cw - 6, chh - 6), Color(1, 0.2, 0.2, 1), false, 3.0)
