class_name CatalogOverlay
extends CanvasLayer

## The player's catalog at Nook's counter (`m_catalog_ovl.c` + the catalog tables of
## `m_tag_ovl.c`). Nine stacked pages with a tab column; the front page lists seven
## names at a time over its scrolling paper, with the highlighted entry turning in the
## preview ring, its price (or "Not for Sale"), the "n / total" count and the star once
## the page is complete. Chrome is baked from the page's display lists by `menu_ui.py`
## (`assets/generated/ui/catalog/`); everything here is in 320x240 screen units about
## the menu position, y up like the C code, and the page flip is `mCL_move_Play`'s.
##
## Keys: arrows move the hand (right / left between the names and the tabs), Page Up /
## Page Down scroll seven (C up / down), Home / End jump to the top / bottom (C left /
## right). A (Space / Enter) opens "Order / Quit" on a name or turns to a tab's page;
## B (Esc / Backspace) backs out. Closing emits `closed` with the ordered item, or &"".

signal closed(item_id: StringName)

const TEX_DIR := "res://assets/generated/ui/catalog/%s.png"
const PAGE_COUNT := 9
const ROWS := 7
## `mCL_set_page_dl` / `mTG_catalog_line_pos`: 18-unit name rows from y 60 (units, up).
const ROW_PITCH := 18.0
## `CATALOG_PAGE` in `menu_ui.py`: left, top (up), width, height.
const PAGE_RECT := Rect2(-143.0, 97.0, 280.0, 201.0)
const MARK_SIZE := Vector2(16.0, 16.0)
## `mTG_catalog_col_pos` / `mTG_catalog_wc_*`: where the hand points.
const LIST_HAND_X := 65.0
const LIST_HAND_Y0 := 60.0
const TAB_HAND_X := 93.0
const TAB_HAND_Y0 := 64.0
const TAB_PITCH := 16.0
const FONT_PX := 14
## `item_name_color`.
const NAME_OFF := Color8(155, 155, 155)
const NAME_ON := Color.WHITE
const COUNT_COLOR := Color8(20, 20, 70)
const PRICE_COLOR := Color8(205, 0, 0)
## `gDPSetPrimColor(0, 50, 255, alpha)` on the scroll arrows.
const ARROW_COLOR := Color8(0, 50, 255)
const NOT_FOR_SALE := "Not for Sale"
## The preview ring (`clg_mwin2_model`'s `inv_mwin_3Dma_tex`): x -116..-48, y -28..40.
const RING_RECT := Rect2(-116.0, 40.0, 68.0, 68.0)
## `mCL_item_move`: 1.25 degrees a frame.
const TURN_DEG := 1.25
## `m_submenu_ovl.c` `texture_pos` step, in pattern texels a frame.
const SCROLL_TEXELS := 0.3535
const TAGS := ["Order", "Quit"]

enum Hand { LIST, TABS }

var position := Vector2.ZERO

var _open: bool = false
var _pages: CatalogPages = null
## `page_order`: the front page first.
var _order: Array[int] = []
var _page_no: int = 0
var _top: Array[int] = []
var _row: Array[int] = []
var _page_timer: int = 0
## `menu_info->position[1]` during a flip.
var _flip: float = 0.0
var _hand: int = Hand.LIST
var _tab_row: int = 0
var _tag_open: bool = false
var _tag_index: int = 0
var _counter: int = 0
var _alpha: float = 0.0
var _accum: float = 0.0
var _item: StringName = &""
var _prev_item: StringName = &""
var _turn: float = 0.0
var _music_timer: int = 60
var _font: Font = null
var _tex: Dictionary = {}
var _layer_scale: float = 3.0

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _back: Control = $Root/Screen/Back
@onready var _back_fill: TextureRect = $Root/Screen/Back/Fill
@onready var _back_body: Control = $Root/Screen/Back/Body
@onready var _front: Control = $Root/Screen/Front
@onready var _front_fill: TextureRect = $Root/Screen/Front/Fill
@onready var _front_body: Control = $Root/Screen/Front/Body
@onready var _preview: TextureRect = $Root/Screen/Front/Preview
@onready var _tabs: Control = $Root/Screen/Tabs
@onready var _tag: Control = $Root/Screen/Tag
@onready var _tag_shadow: NinePatchRect = $Root/Screen/Tag/Shadow
@onready var _tag_frame: NinePatchRect = $Root/Screen/Tag/Frame
@onready var _tag_arrow: TextureRect = $Root/Screen/Tag/Arrow
@onready var _tag_text: Control = $Root/Screen/Tag/Text
@onready var _hand_node: HandCursor = $Root/Hand
@onready var _viewport: SubViewport = $Root/PreviewViewport
@onready var _pivot: Node3D = $Root/PreviewViewport/World/Pivot
@onready var _camera: Camera3D = $Root/PreviewViewport/World/Camera


func _ready() -> void:
	layer = 21
	add_to_group("shop_ui")
	add_to_group("catalog_ui")
	_root.visible = false
	_hand_node.visible = false
	_font = LetterBoard.load_font()
	for name: String in ["clg_fill", "clg_frame", "clg_info", "clg_bell", "clg_arrow", "clg_star", "clg_music"]:
		_tex[name] = _load(name)
	for row: int in ROWS:
		for state: String in ["on", "off"]:
			_tex["clg_slot%d_%s" % [row, state]] = _load("clg_slot%d_%s" % [row, state])
	for i: int in PAGE_COUNT:
		for state: String in ["on", "off"]:
			_tex["clg_tab%d_%s" % [i, state]] = _load("clg_tab%d_%s" % [i, state])
		_tex["clg_pattern%d" % i] = _load("clg_pattern%d" % i)
	var fill: Texture2D = _tex["clg_fill"]
	if fill != null:
		_layer_scale = fill.get_width() / PAGE_RECT.size.x
	for f: TextureRect in [_back_fill, _front_fill]:
		f.texture = fill
		f.size = PAGE_RECT.size
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/inventory_shell_paper.gdshader")
		f.material = mat
	_back_body.draw.connect(_draw_page.bind(_back_body, false))
	_front_body.draw.connect(_draw_page.bind(_front_body, true))
	_tabs.draw.connect(_draw_tabs)
	_tag_text.draw.connect(_draw_tag_text)
	_tag_frame.texture = InventoryChrome.load_tex("tag_frame")
	_tag_shadow.texture = InventoryChrome.load_tex("tag_shadow")
	_tag_arrow.texture = InventoryChrome.load_tex("tag_arrow")
	_preview.texture = _viewport.get_texture()
	_root.resized.connect(_fit_screen)
	_fit_screen()
	set_process(false)
	set_process_unhandled_input(false)


func _load(name: String) -> Texture2D:
	var path := TEX_DIR % name
	return load(path) if ResourceLoader.exists(path) else null


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5
	_hand_node.size = Vector2(36, 36) * k
	if _open:
		_point_hand(false)


func is_open() -> bool:
	return _open


## `mCL_catalog_ovl_init`: every page from the top, the furniture page in front.
func open(book: CatalogBook = null) -> void:
	if _open:
		return
	_pages = CatalogPages.build(book if book != null else Game.catalog)
	_order.clear()
	_top.clear()
	_row.clear()
	for i: int in PAGE_COUNT:
		_order.append(i)
		_top.append(0)
		_row.append(0)
	_page_no = 0
	_page_timer = 0
	_flip = 0.0
	_hand = Hand.LIST
	_tab_row = 0
	_tag_open = false
	_counter = 0
	_accum = 0.0
	_prev_item = &""
	_set_item()
	_open = true
	_root.visible = true
	_hand_node.visible = true
	_tag.visible = false
	set_process(true)
	set_process_unhandled_input(true)
	_refresh()
	_point_hand(false)


func close(item_id: StringName = &"") -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_hand_node.visible = false
	set_process(false)
	set_process_unhandled_input(false)
	_clear_preview()
	closed.emit(item_id)


## The entry the hand is on (&"" on an empty page).
func current_item() -> StringName:
	var p: int = _order[0] if not _order.is_empty() else 0
	var ids: Array = _pages.page(p) if _pages != null else []
	var i: int = _top[p] + _row[p] if not _top.is_empty() else 0
	return ids[i] as StringName if i >= 0 and i < ids.size() else &""


func front_page() -> int:
	return _order[0] if not _order.is_empty() else 0


# --- Input --------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()
	if _page_timer > 0:
		return
	if _tag_open:
		_tag_input(k)
		return
	match k.keycode:
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_RIGHT:
			if _hand == Hand.LIST:
				_hand = Hand.TABS
				_tab_row = front_page()
				Audio.play_se(&"cursol")
		KEY_LEFT:
			if _hand == Hand.TABS:
				_hand = Hand.LIST
				Audio.play_se(&"cursol")
		KEY_PAGEUP:
			_jump(-ROWS)
		KEY_PAGEDOWN:
			_jump(ROWS)
		KEY_HOME:
			_jump(-100000)
		KEY_END:
			_jump(100000)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_decide()
		KEY_ESCAPE, KEY_BACKSPACE:
			Audio.play_se(&"menu_exit")
			close()
			return
		_:
			return
	_refresh()
	_point_hand(true)


func _tag_input(k: InputEventKey) -> void:
	match k.keycode:
		KEY_UP, KEY_DOWN:
			_tag_index = wrapi(_tag_index + (1 if k.keycode == KEY_DOWN else -1), 0, TAGS.size())
			Audio.play_se(&"cursol")
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if _tag_index == 0:
				## `mTG_order_proc`: the catalog closes with the item for Nook to quote.
				Audio.play_se(&"33")
				close(current_item())
				return
			_tag_open = false
		KEY_ESCAPE, KEY_BACKSPACE:
			_tag_open = false
		_:
			return
	_refresh()


## `mTG_move_cursol_in_catalog` (stick): the hand walks rows 1-5 and the list scrolls
## under it at the ends; the tab column is a plain 9-row table.
func _move(dir: int) -> void:
	if _hand == Hand.TABS:
		var r: int = clampi(_tab_row + dir, 0, PAGE_COUNT - 1)
		if r != _tab_row:
			_tab_row = r
			Audio.play_se(&"cursol")
		return
	var p: int = front_page()
	var count: int = _pages.page(p).size()
	var target: int = _top[p] + _row[p]
	var changed := false
	if dir > 0 and target < count - 1:
		if _row[p] < 5 or (target == count - 2 and _row[p] < 6):
			_row[p] += 1
		else:
			_top[p] += 1
		changed = true
	elif dir < 0 and target > 0:
		if _row[p] > 1 or (target == 1 and _row[p] > 0):
			_row[p] -= 1
		else:
			_top[p] -= 1
		changed = true
	if changed:
		Audio.play_se(&"cursol")
		_set_item()


## C up / down (a page of seven) and C left / right (top / bottom).
func _jump(delta: int) -> void:
	if _hand != Hand.LIST:
		return
	var p: int = front_page()
	var count: int = _pages.page(p).size()
	if count == 0:
		return
	var old: Vector2i = Vector2i(_top[p], _row[p])
	if absi(delta) > ROWS:
		if delta < 0:
			_top[p] = 0
			_row[p] = 0
		elif count < ROWS:
			_top[p] = 0
			_row[p] = count - 1
		else:
			_top[p] = count - ROWS
			_row[p] = ROWS - 1
	elif delta > 0:
		var last_top: int = count - ROWS
		if _top[p] + ROWS <= last_top:
			_top[p] += ROWS
		elif _top[p] + _row[p] < count - 1:
			_top[p] = maxi(last_top, 0)
			_row[p] = count - _top[p] - 1
	else:
		if _top[p] - ROWS >= 0:
			_top[p] -= ROWS
		elif _top[p] + _row[p] > 0:
			_top[p] = 0
			_row[p] = 0
	if Vector2i(_top[p], _row[p]) != old:
		Audio.play_se(&"cursol")
		_set_item()


func _decide() -> void:
	if _hand == Hand.TABS:
		## `mTG_select_tag_decide_catalog_wchange`.
		if _tab_row != front_page() and _page_timer == 0:
			_page_no = _tab_row
			_page_timer = 40
			_top[_page_no] = 0
			_row[_page_no] = 0
			_prev_item = _item
			_set_item(_page_no)
			Audio.play_se(&"41c")
		return
	if current_item() == &"":
		return
	## `mTG_select_tag_decide_catalog`: an entry gets "Order / Quit".
	_tag_open = true
	_tag_index = 0
	Audio.play_se(&"cursol")


# --- Per frame ------------------------------------------------------------------------


func _process(delta: float) -> void:
	_accum += delta * DecompTime.TICK_HZ
	var steps: int = 0
	while _accum >= 1.0 and steps < 8:
		_accum -= 1.0
		steps += 1
		_tick()
	if steps > 0:
		_refresh()


## `mCL_move_Play` + `mCL_catalog_ovl_move`.
func _tick() -> void:
	_counter = (_counter + 1) % 35
	_alpha = (float(_counter) / 17.0) if _counter < 17 else (float(35 - _counter) / 18.0)
	if _page_timer > 0:
		_page_timer -= 1
		_flip = 100.0 * sin(float(_page_timer) * 0.078539819)
		if _page_timer == 20:
			_order.erase(_page_no)
			_order.push_front(_page_no)
		elif _page_timer == 0:
			_flip = 0.0
			_prev_item = &""
			_point_hand(true)
	_turn = fmod(_turn + TURN_DEG, 360.0)
	_music_timer -= 1
	if _pivot != null:
		_pivot.rotation_degrees.y = _turn


# --- Drawing ----------------------------------------------------------------------------


## Page units (y up, about the menu position) to screen.
func _u(v: Vector2) -> Vector2:
	return Vector2(160.0 + position.x + v.x, 120.0 - position.y - v.y)


## Which page each layer shows: the front node the front page, the back node the page
## being turned under or over it.
func _back_page() -> int:
	if _page_timer == 0:
		return -1
	return _order[1] if _order[0] == _page_no else _page_no


## `mCL_set_page_dl`: pos_y is +position[1] for the page being turned to, - for the other.
func _page_y(page: int) -> float:
	return _flip if page == _page_no else -_flip


func _refresh() -> void:
	if not _open:
		return
	var front: int = _order[0]
	var back: int = _back_page()
	## Before the half-way swap the old page is still on top.
	_back.visible = back >= 0
	for pair: Array in [[_front_fill, front], [_back_fill, back]]:
		var fill: TextureRect = pair[0]
		var page: int = pair[1]
		if page < 0:
			continue
		fill.position = _u(Vector2(PAGE_RECT.position.x, PAGE_RECT.position.y + _page_y(page)))
		var pattern: Texture2D = _tex.get("clg_pattern%d" % page)
		var mat := fill.material as ShaderMaterial
		if mat != null and pattern != null:
			var texels_per_unit: float = pattern.get_width() / 32.0
			mat.set_shader_parameter("paper_tex", pattern)
			mat.set_shader_parameter("paper_px_per_shell_px", texels_per_unit / _layer_scale)
			mat.set_shader_parameter("scroll_texels_per_sec", Vector2.ONE * SCROLL_TEXELS * texels_per_unit
				* DecompTime.TICK_HZ)
	_front_body.set_meta("page", front)
	_back_body.set_meta("page", back)
	_front_body.queue_redraw()
	_back_body.queue_redraw()
	_tabs.queue_redraw()
	_update_preview(front)
	_update_tag()


func _draw_page(canvas: Control, is_front: bool) -> void:
	var page: int = int(canvas.get_meta("page", -1))
	if page < 0 or _pages == null:
		return
	var py: float = _page_y(page)
	var origin := Vector2(0.0, py)
	var rect := Rect2(_u(Vector2(PAGE_RECT.position.x, PAGE_RECT.position.y + py)), PAGE_RECT.size)
	_layer(canvas, "clg_frame", rect)
	var ids: Array = _pages.page(page)
	var top: int = _top[page]
	for i: int in ROWS:
		_layer(canvas, "clg_slot%d_%s" % [i, "on" if i == _row[page] else "off"], rect)
	## The item shown: the new one on the page being turned to, the old one on the other.
	var item: StringName = _item if (page == _page_no or _page_timer == 0) else _prev_item
	if ids.is_empty():
		item = &""
	var price: int = CatalogPages.price_of(item) if item != &"" else 0
	_layer(canvas, "clg_info", rect)
	if item != &"" and price > 0:
		_layer(canvas, "clg_bell", rect)
	## Scroll arrows (`clg_win_shirushi1T_model`), pulsing.
	var arrow: Texture2D = _tex.get("clg_arrow")
	if arrow != null:
		var col := Color(ARROW_COLOR, _alpha)
		if top != 0:
			canvas.draw_texture_rect(arrow, Rect2(_u(origin + Vector2(-11, 80)) - MARK_SIZE * 0.5, MARK_SIZE), false, col)
		if top + ROWS < ids.size():
			var c := _u(origin + Vector2(-11, -66))
			canvas.draw_set_transform(c, PI, Vector2.ONE)
			canvas.draw_texture_rect(arrow, Rect2(-MARK_SIZE * 0.5, MARK_SIZE), false, col)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	## Names (`mFont_SetLineStrings` at 0.875).
	var asc: float = _font.get_ascent(FONT_PX)
	for i: int in ROWS:
		var idx: int = top + i
		if idx >= ids.size():
			break
		var data: ItemData = ItemCatalog.get_item(ids[idx] as StringName)
		var label: String = data.display_name if data != null else String(ids[idx])
		var col2: Color = NAME_ON if i == _row[page] else NAME_OFF
		canvas.draw_string(_font, Vector2(120.0 + position.x, 53.0 - position.y - py + ROW_PITCH * i + asc), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, col2)
	## "n / total" and the star.
	var n: int = (top + _row[page] + 1) if not ids.is_empty() else 0
	var y: float = 181.0 - position.y - py + asc
	var n_str := str(n)
	canvas.draw_string(_font, Vector2(188.0 + position.x - _w(n_str), y), n_str, HORIZONTAL_ALIGNMENT_LEFT, -1,
		FONT_PX, COUNT_COLOR)
	var total := str(ids.size())
	canvas.draw_string(_font, Vector2(198.0 + position.x, y), total, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX,
		COUNT_COLOR)
	var star: Texture2D = _tex.get("clg_star")
	if star != null and _pages.completed(page):
		var sx: float = 38.0 + 7.0 + total.length() * 7.0
		canvas.draw_texture_rect(star, Rect2(_u(origin + Vector2(sx, -66)) - MARK_SIZE * 0.5, MARK_SIZE), false)
	if item == &"":
		return
	_draw_item(canvas, item, origin, is_front)
	## `mCL_price_draw`.
	var py_text: float = 167.0 - position.y - py + asc
	if price == 0:
		canvas.draw_string(_font, Vector2(48.0 + position.x, py_text), NOT_FOR_SALE, HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_PX, PRICE_COLOR)
	else:
		var p_str := _bells(price)
		canvas.draw_string(_font, Vector2(86.5 + position.x - _w(p_str), py_text), p_str, HORIZONTAL_ALIGNMENT_LEFT,
			-1, FONT_PX, PRICE_COLOR)


## `mCL_item_draw` for the flat kinds; furniture turns in the preview viewport.
func _draw_item(canvas: Control, item: StringName, origin: Vector2, is_front: bool) -> void:
	var data: ItemData = ItemCatalog.get_item(item)
	if data == null:
		return
	## `Matrix_translate(-143 + 58, 97 + pos_y)` then the kind's own pos_y and scale.
	var base := origin + Vector2(-85.0, 97.0)
	if MinidiskCatalog.is_disc(item):
		var music: Texture2D = _tex.get("clg_music")
		if music == null:
			return
		## `mCL_item_move`: the note bobs and sways; `mCL_music_draw` rocks it.
		var t: float = float(_music_timer)
		var c := base + Vector2(sin(deg_to_rad(t * 3.0)) * 6.0, -90.0 + sin(deg_to_rad(t * 6.0)) * 6.0)
		var sz := Vector2(80.0, 80.0) * 0.55
		canvas.draw_set_transform(_u(c), deg_to_rad(cos(t * 0x222 * TAU / 65536.0) * 22.5), Vector2.ONE)
		canvas.draw_texture_rect(music, Rect2(-sz * 0.5, sz), false)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var flat: Texture2D = null
	var drop: float = -90.0
	if data.id == ShopGoods.PAPER:
		flat = LetterChrome.paper_texture(0)
		var scale: float = 0.28
		drop = -93.0
		if flat != null:
			## The paper model spans `PAPER_BOUNDS` (-124, 100, 248, 186) about its origin.
			var top_left := _u(base + Vector2(0.0, drop) + Vector2(-124.0, 100.0) * scale)
			canvas.draw_texture_rect(flat, Rect2(top_left, Vector2(248.0, 186.0) * scale), false)
		return
	flat = _tex.get(_style_path(data), null) as Texture2D
	if flat != null:
		## The room sample fills the ring (`mCL_rom_myhome1_*_model` at 0.54).
		var side := 44.0
		var c2 := _u(base + Vector2(0.0, drop + 6.0))
		canvas.draw_texture_rect(flat, Rect2(c2 - Vector2(side, side) * 0.5, Vector2(side, side)), false)


static func _style_path(data: ItemData) -> String:
	match data.category:
		ItemData.Category.WALL:
			return InteriorStyleCatalog.wall_texture_path(data.id)
		ItemData.Category.FLOOR:
			return InteriorStyleCatalog.floor_texture_path(data.id)
	return ""


## Wallpaper / carpet samples load when the entry is picked, not while drawing.
func _cache_style(item: StringName) -> void:
	var data: ItemData = ItemCatalog.get_item(item)
	var path: String = _style_path(data) if data != null else ""
	if path != "" and not _tex.has(path) and ResourceLoader.exists(path):
		_tex[path] = load(path)


func _layer(canvas: Control, name: String, rect: Rect2) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex != null:
		canvas.draw_texture_rect(tex, rect, false)


func _w(s: String) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x


## `mFont_UnintToString` with the thousands comma.
static func _bells(v: int) -> String:
	var s := str(v)
	return s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3) if s.length() > 3 else s


## `mCL_set_wchange_dl`: the other tabs ride the page going down, the chosen one the
## page coming up.
func _draw_tabs() -> void:
	if not _open:
		return
	for i: int in PAGE_COUNT:
		if i == _page_no:
			continue
		_layer(_tabs, "clg_tab%d_off" % i, Rect2(_u(Vector2(PAGE_RECT.position.x, PAGE_RECT.position.y - _flip)),
			PAGE_RECT.size))
	_layer(_tabs, "clg_tab%d_on" % _page_no, Rect2(_u(Vector2(PAGE_RECT.position.x, PAGE_RECT.position.y + _flip)),
		PAGE_RECT.size))


# --- Preview ----------------------------------------------------------------------------


func _set_item(page: int = -1) -> void:
	if page < 0:
		page = front_page()
	var ids: Array = _pages.page(page) if _pages != null else []
	var i: int = _top[page] + _row[page]
	_item = ids[i] as StringName if i >= 0 and i < ids.size() else &""
	_turn = 0.0
	_music_timer = 60
	_cache_style(_item)
	_build_preview(_item)


func _clear_preview() -> void:
	if _pivot == null:
		return
	for child: Node in _pivot.get_children():
		child.queue_free()


## `mCL_furniture_init` / `mCL_item_draw`: the piece turns in the ring under
## `mSM_change_view`'s camera (20 degree lens, 0x900 above the look-at point).
func _build_preview(item: StringName) -> void:
	_clear_preview()
	_preview.visible = false
	if item == &"" or _pivot == null:
		return
	var data: ItemData = ItemCatalog.get_item(item)
	var visual: StringName = ShopDisplay.display_visual_for_item(item)
	if data == null or visual == &"" or data.category == ItemData.Category.WALL \
			or data.category == ItemData.Category.FLOOR:
		return
	var host := Node3D.new()
	var attached: Node3D = GeneratedVisual.attach(host, visual)
	if attached == null:
		host.free()
		return
	_pivot.add_child(host)
	if data.cloth_index >= 0:
		VisualCloth.apply_cloth(host, data.cloth_index)
	GeneratedVisual.apply_preview_materials(host)
	_pivot.rotation = Vector3.ZERO
	var box: AABB = VisualFit.world_aabb_named(host, "")
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	host.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var radius: float = maxf(box.size.length() * 0.5, 0.05)
	var elev: float = float(0x900) * MLib.S16
	var dist: float = radius / tan(deg_to_rad(_camera.fov * 0.5)) * 1.05
	var look := Vector3(0.0, box.size.y * 0.5, 0.0)
	_camera.position = look + Vector3(0.0, sin(elev), cos(elev)) * dist
	_camera.look_at(look, Vector3.UP)
	_preview.visible = true


func _update_preview(front: int) -> void:
	if _preview == null:
		return
	var y: float = _page_y(front)
	_preview.position = _u(Vector2(RING_RECT.position.x, RING_RECT.position.y + y))
	_preview.size = RING_RECT.size
	## The preview belongs to the page being turned to; hide it while the old page is on top.
	_preview.visible = _preview.visible and _pivot.get_child_count() > 0 and (_page_timer == 0 or front == _page_no)


# --- Hand and tag ------------------------------------------------------------------------


func _hand_tip() -> Vector2:
	if _hand == Hand.TABS:
		return _u(Vector2(TAB_HAND_X, TAB_HAND_Y0 - TAB_PITCH * _tab_row))
	return _u(Vector2(LIST_HAND_X, LIST_HAND_Y0 - ROW_PITCH * _row[front_page()]))


func _point_hand(animate: bool) -> void:
	if not _open:
		return
	_hand_node.visible = _page_timer == 0
	_hand_node.point_at(_screen.position + _hand_tip() * _screen.scale, animate)


## The "Order / Quit" window beside the entry, or the page's name beside a tab
## (`mTG_catalog_str`).
func _update_tag() -> void:
	var lines: Array = []
	if _tag_open:
		lines = TAGS
	elif _hand == Hand.TABS and _page_timer == 0:
		lines = [CatalogPages.PAGE_NAMES[_tab_row]]
	_tag.visible = not lines.is_empty()
	if lines.is_empty():
		return
	_tag.set_meta("lines", lines)
	var w: float = 0.0
	for s: String in lines:
		w = maxf(w, _w(s))
	var size := Vector2(w + 28.0, 16.0 * lines.size() + 14.0)
	var tip := _hand_tip()
	var pos := Vector2(tip.x + 14.0, tip.y - size.y * 0.5) if _hand == Hand.LIST \
		else Vector2(tip.x - 26.0 - size.x, tip.y - size.y * 0.5)
	_tag_frame.position = pos
	_tag_frame.size = size
	_tag_shadow.position = pos + Vector2(3, 4)
	_tag_shadow.size = size
	_tag_arrow.flip_h = _hand != Hand.LIST
	_tag_arrow.size = Vector2(11, 12)
	_tag_arrow.position = Vector2(pos.x - 11.0, tip.y - 6.0) if _hand == Hand.LIST \
		else Vector2(pos.x + size.x, tip.y - 6.0)
	_tag_text.position = pos
	_tag_text.size = size
	_tag_text.queue_redraw()


func _draw_tag_text() -> void:
	var lines: Array = _tag.get_meta("lines", [])
	var asc: float = _font.get_ascent(FONT_PX)
	for i: int in lines.size():
		var on: bool = _tag_open and i == _tag_index
		_tag_text.draw_string(_font, Vector2(14.0, 7.0 + 16.0 * i + asc), str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT,
			-1, FONT_PX, Color8(30, 20, 10) if on or not _tag_open else Color8(118, 102, 82))
