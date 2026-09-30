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
##
## Drawn like the original screen: the folder window (`sav_win1`, baked by
## `design_ui.py`) with its per-folder cloth and colours, 3x4 wells, the stacked folder
## tabs down its right edge (the open one raised, `sav_sentaku_taguT`) and the folder
## name on its plate; the 8-slot book (`inv_original2`) sits to its left. The hand
## points at the selection; a picked-up design pulses green (`sav_mark_winT`).

signal closed

enum Region { ALBUM, MINE }

const ALBUM_COLS := 3
const ALBUM_ROWS := 4
const MINE_COLS := 2
const MINE_ROWS := 4
const ALBUM_WIDTH := 194.0
const BOOK2_WIDTH := 132.0
const CLOTH_TEXELS_PER_UNIT := 64.0 / 52.0

## `m_cporiginal_ovl.c` per-folder colours.
const TAB_PRIM := [0xCDC36E, 0xCDA55F, 0xC3914B, 0xAF7D37, 0x9B6923, 0x875F14, 0x735519, 0x5F2D14]
const TAB_ENV := [0xC3B964, 0xC39B5A, 0xB98746, 0xA57332, 0x915F1E, 0x7D550A, 0x694B14, 0x552D0A]
const SEL_TAB_PRIM := [0x91875F, 0x8C6E4B, 0x7D694B, 0x7D5F4B, 0x735F41, 0x73552D, 0x5F4B37, 0x5F4128]
const ENV := [0xFFF5A0, 0xFFD796, 0xF5C382, 0xE1AF6E, 0xCD9B5A, 0xB98746, 0xA57332, 0x9B5F28]
const TEXT_COLOR := [0x503232, 0x503232, 0x503232, 0x463232, 0x463232, 0x3C2828, 0x3C2828, 0x321E1E]

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

var _thumbs: Dictionary = {}

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _book: Control = $Root/Screen/Book
@onready var _album: Control = $Root/Screen/Album
@onready var _book_slots: Control = $Root/Screen/Book/Slots
@onready var _album_slots: Control = $Root/Screen/Album/Slots
@onready var _folder_name: Label = $Root/Screen/Album/FolderName
@onready var _name: Label = $Root/Screen/Name
@onready var _prompt: PanelContainer = $Root/Screen/Prompt
@onready var _hand: HandCursor = $Root/Hand


## `m_cporiginal_ovl.c`: in from the right, out to the right.
var _slide: MenuSlide = null


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("design_album_ui")
	_slide = MenuSlide.attach(self)
	_root.visible = false
	_book_slots.draw.connect(_draw_mine)
	_album_slots.draw.connect(_draw_album)
	_book.gui_input.connect(_on_input.bind(Region.MINE))
	_album.gui_input.connect(_on_input.bind(Region.ALBUM))
	_root.resized.connect(_fit_screen)
	for pair: Array in [[_book, "Cloth", "book2_mask"], [_book, "Under", "book2_under"], [_book, "Over", "book2_over"],
			[_album, "Cloth", "album_mask"], [_album, "Under", "album_under"], [_album, "Over", "album_over"],
			[_album, "Kage", "album_kage"]]:
		((pair[0] as Node).get_node(pair[1]) as TextureRect).texture = _design_tex(pair[2])
	_set_cloth(_book.get_node("Cloth"), _design_tex("book_cloth"), BOOK2_WIDTH)
	var tab_tex := _design_tex("ctl_win_tagu2_tex")
	var mark_shader: Shader = (_album.get_node("SelTab").material as ShaderMaterial).shader
	for i in DesignBook.ALBUM_PAGES:
		var tab := _album.get_node("Tab%d" % i) as TextureRect
		tab.texture = tab_tex
		var mat := ShaderMaterial.new()
		mat.shader = mark_shader
		mat.set_shader_parameter("prim", _rgb(TAB_PRIM[i]))
		mat.set_shader_parameter("env", _rgb(TAB_ENV[i]))
		tab.material = mat
	(_album.get_node("SelTab") as TextureRect).texture = _design_tex("ctl_win_tagu3_tex")
	_fit_screen()
	set_process(false)
	set_process_unhandled_input(false)


static func _rgb(v: int) -> Color:
	return Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


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
	_hand.size = Vector2(36, 36) * k
	_point_hand(false)


func _process(_delta: float) -> void:
	if not _held.is_empty():
		_book_slots.queue_redraw()
		_album_slots.queue_redraw()


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
	_slide.slide_in(MenuSlide.Dir.IN_RIGHT)
	_hand.visible = true
	set_process(true)
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
	_slide.slide_out(MenuSlide.Dir.OUT_RIGHT, _on_slid_out)
	_hand.visible = false
	set_process(false)
	set_process_unhandled_input(false)
	_backup = {}
	var cb := _cb
	_cb = Callable()
	closed.emit()
	if cb.is_valid():
		cb.call()


func _on_slid_out() -> void:
	if not _open:
		_root.visible = false


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


## The book's 2x4 wells sit left of the album's 3x4: stepping off one side's edge
## lands on the other at the same row.
func _move(dx: int, dy: int) -> void:
	Audio.play_se(&"cursol")
	var cols: int = ALBUM_COLS if _region == Region.ALBUM else MINE_COLS
	var c: int = _sel % cols + dx
	var r: int = clampi(_sel / cols + dy, 0, ALBUM_ROWS - 1)
	if _region == Region.ALBUM and c < 0:
		_region = Region.MINE
		c = MINE_COLS - 1
	elif _region == Region.MINE and c >= MINE_COLS:
		_region = Region.ALBUM
		c = 0
	else:
		c = clampi(c, 0, cols - 1)
	_sel = r * (ALBUM_COLS if _region == Region.ALBUM else MINE_COLS) + c


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
	_hand.visible = false
	set_process_unhandled_input(false)
	name_ui.call("open", Game.designs.album_names[page].strip_edges(), func(text: String) -> void:
		Game.designs.set_folder_name(page, text)
		_root.visible = _open
		_hand.visible = _open
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


## `sav_v` wells: 24x24 at x -12 + 32j, top 56 - 29k (album units, y up), in
## Album-local pixels (window left -62, top 86).
static func album_slot_rect(i: int) -> Rect2:
	var j := i % ALBUM_COLS
	var k := i / ALBUM_COLS
	return Rect2(-12.0 + 32.0 * j + 62.0, 86.0 - (56.0 - 29.0 * k), 24.0, 24.0)


## `inv_original2_mb1-8_model`: 24x24 at x -100 / -68, top 57 - 29k, in Book-local
## pixels (window left -139, top 81).
static func mine_slot_rect(i: int) -> Rect2:
	var x0: float = -100.0 if i % MINE_COLS == 0 else -68.0
	return Rect2(x0 + 139.0, 81.0 - (57.0 - 29.0 * float(i / MINE_COLS)), 24.0, 24.0)


func _on_input(event: InputEvent, region: int) -> void:
	if not _open or _confirm or not (event is InputEventMouse):
		return
	var p := (event as InputEventMouse).position
	var count: int = ALBUM_COLS * ALBUM_ROWS if region == Region.ALBUM else MINE_COLS * MINE_ROWS
	var hit := -1
	for i in count:
		var r := album_slot_rect(i) if region == Region.ALBUM else mine_slot_rect(i)
		if r.grow(3.0).has_point(p):
			hit = i
			break
	if region == Region.ALBUM and hit < 0 and event is InputEventMouseButton \
			and (event as InputEventMouseButton).pressed:
		for page in DesignBook.ALBUM_PAGES:
			var off := (page * 29) / 2
			if Rect2(152, 26 + off, 30, 14).has_point(p) and page != _page:
				flip_page(page - _page)
				_refresh()
				return
	if hit < 0:
		return
	if event is InputEventMouseMotion and (hit != _sel or region != _region):
		_region = region
		_sel = hit
		_refresh()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_region = region
		_sel = hit
		activate()
		_refresh()


func _refresh() -> void:
	if not _open:
		return
	_thumbs.clear()
	var d := _design_at(_region, _page, _sel)
	_name.text = d.name if d != null and (d.flag_set or _region == Region.MINE) else ""
	_folder_name.text = _folder_label(_page)
	_folder_name.add_theme_color_override("font_color", _rgb(TEXT_COLOR[_page]))
	_prompt.visible = _confirm
	if _confirm:
		(_prompt.get_node("Text") as Label).text = "Keep the changes to the album?\nY / space  keep      N  put it all back"
	_set_cloth(_album.get_node("Cloth"), _design_tex("album_cloth%d" % _page), ALBUM_WIDTH)
	## Rim and name plate in the folder's colours, baked per folder.
	(_album.get_node("Rim") as TextureRect).texture = _design_tex("album_rim%d" % _page)
	(_album.get_node("Plate") as TextureRect).texture = _design_tex("album_name%d" % _page)
	var sel_tab := _album.get_node("SelTab") as TextureRect
	_set_lerp(sel_tab, SEL_TAB_PRIM[_page], ENV[_page])
	## `mCO_set_frame_tagT_dl`: the open folder's tab, raised at (105, 52 - page*29/2).
	sel_tab.position.y = 26.0 + float((_page * 29) / 2)
	for i in DesignBook.ALBUM_PAGES:
		(_album.get_node("Tab%d" % i) as CanvasItem).visible = i != _page
	_book_slots.queue_redraw()
	_album_slots.queue_redraw()
	_point_hand(true)


## Textures must outlive the draw call that uses them, so thumbnails are kept until the
## next refresh.
func _thumb(dp: DesignPattern) -> Texture2D:
	if not _thumbs.has(dp):
		_thumbs[dp] = ImageTexture.create_from_image(DesignTexture.image(dp))
	return _thumbs[dp]


## The cloth scrolls under the window's mask at its own texel scale: 64 texels per 52
## window units (`sav_win1` / `inv_original2` quads), whatever the bake or ACHD size.
func _set_cloth(rect: TextureRect, cloth: Texture2D, window_width: float) -> void:
	var mat := rect.material as ShaderMaterial
	if mat == null or cloth == null or rect.texture == null:
		return
	var shell_px_per_unit := rect.texture.get_width() / window_width
	var cloth_px_per_unit := CLOTH_TEXELS_PER_UNIT * cloth.get_width() / 32.0
	mat.set_shader_parameter("paper_tex", cloth)
	mat.set_shader_parameter("paper_px_per_shell_px", cloth_px_per_unit / shell_px_per_unit)


func _set_lerp(node: Node, prim: int, env: int) -> void:
	var mat := (node as CanvasItem).material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("prim", _rgb(prim))
		mat.set_shader_parameter("env", _rgb(env))


func _point_hand(animate: bool) -> void:
	if _hand == null or not _open:
		return
	var host: Control = _album if _region == Region.ALBUM else _book
	var r := album_slot_rect(_sel) if _region == Region.ALBUM else mine_slot_rect(_sel)
	var tip := host.position + r.position + r.size * Vector2(0.55, 0.45)
	_hand.point_at(_screen.position + tip * _screen.scale, animate)


func _draw_album() -> void:
	for i in ALBUM_COLS * ALBUM_ROWS:
		_draw_slot(_album_slots, album_slot_rect(i), Region.ALBUM, i)


func _draw_mine() -> void:
	for i in MINE_COLS * MINE_ROWS:
		_draw_slot(_book_slots, mine_slot_rect(i), Region.MINE, i)


func _draw_slot(host: Control, r: Rect2, region: int, i: int) -> void:
	var dp := _design_at(region, _page, i)
	if dp != null and (dp.flag_set or region == Region.MINE):
		host.draw_texture_rect(_thumb(dp), r, false)
	if _held == _spot(region, i):
		## `mNW_draw_sav_mark_before`: a 40-frame green pulse.
		var g := int(Time.get_ticks_msec() / 1000.0 * 60.0) % 40
		if g > 20:
			g = 40 - g
		host.draw_rect(r.grow(1.5), Color8(g * 3, 150 + g * 4, g * 3), false, 2.0)
