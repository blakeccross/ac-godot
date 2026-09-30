extends CanvasLayer

## Address book (`m_address_ovl.c`), opened over the letter board once the paper is on
## it. Lists "Museum" (`mPr_CheckMuseumAddress`, for mailing a fossil in) on the first
## page, then every villager who remembers the player (`mNpc_GetAnimalMemoryIdx`,
## `Relationship.MET` — `PostUse.met_villager_candidates()`) eight to a page. Other
## player-residents are a memory-card feature this port doesn't have.
##
## Drawn like the original: "Choose an addressee." in the message window
## (`mAD_set_first_tag`) until A, then the pages as stacked address cards
## (`mAD_set_addressSel_tag`), each stretched to its entry count, tinted by page and
## depth, and fanned out 5 units a card (`mAD_pile_init`), at the header's name point
## on the board. Names are the game font at 0.75 scale.
##
## `open(on_pick, anchor_x)`: `on_pick(recipient: Dictionary)` receives the pick (or {}
## when cancelled); `anchor_x` is the board's `ofs_x` (header width before the name
## - 60). Without a callback, picking opens the paper picker like the old flow.

const MAX_ENTRIES := 8
const TITLE := "Choose an addressee."
## `mAD_set_first_tag` title offsets (the second is the empty-book title's).
const TITLE_OFFSET := [Vector2(-66, 8), Vector2(-90, 8)]
const TITLE_COLOR := Color8(80, 80, 230)
## `prim_color[player page / villager page][depth]`.
const CARD_COLOR := [
	[Color8(215, 225, 70), Color8(205, 205, 80), Color8(150, 150, 40)],
	[Color8(145, 255, 100), Color8(115, 225, 80), Color8(100, 190, 60)],
]
## `address_color`: player page, villager page, museum, selected, selected museum.
const NAME_PLAYER := Color8(110, 115, 50)
const NAME_VILLAGER := Color8(0, 135, 20)
const NAME_MUSEUM := Color8(150, 120, 20)
const NAME_SELECTED := Color8(55, 30, 50)
const NAME_SELECTED_MUSEUM := Color8(75, 60, 0)
const NAME_PX := 12

var _open: bool = false
var _entries: Array[Dictionary] = []
## Entries per page: [museum], then villagers 8 to a page.
var _pages: Array = []
var _page: int = 0
var _sel: int = 0
var _choosing: bool = false
var _on_pick: Callable = Callable()
var _anchor_x: float = -56.0
var _font: Font = null
var _tex: Dictionary = {}

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen


func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("letter_address_ui")
	_root.visible = false
	_screen.draw.connect(_draw_book)
	_root.resized.connect(_fit_screen)
	_font = LetterBoard.load_font()
	_fit_screen()
	set_process_unhandled_input(false)


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func _layer(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := "res://assets/generated/ui/menu/%s.png" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func is_open() -> bool:
	return _open


func open(on_pick: Callable = Callable(), anchor_x: float = -56.0) -> void:
	if _open:
		return
	_on_pick = on_pick
	_anchor_x = anchor_x
	_entries = [{"id": PostUse.MUSEUM_RECIPIENT_ID, "name": PostUse.MUSEUM_RECIPIENT_NAME}]
	_entries.append_array(PostUse.met_villager_candidates())
	_pages = [[_entries[0]]]
	var villagers := _entries.slice(1)
	for i in range(0, villagers.size(), MAX_ENTRIES):
		_pages.append(villagers.slice(i, i + MAX_ENTRIES))
	_page = 0
	_sel = 0
	_choosing = false
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")
	_screen.queue_redraw()


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
	var key := (event as InputEventKey).keycode
	if key in [KEY_ESCAPE, KEY_B]:
		_cancel()
		return
	if not _choosing:
		if key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_choosing = true
			Audio.play_se(&"cursol")
		_screen.queue_redraw()
		return
	var count: int = (_pages[_page] as Array).size()
	match key:
		KEY_UP, KEY_W:
			if _sel > 0:
				_sel -= 1
				Audio.play_se(&"cursol")
			else:
				_turn(-1)
		KEY_DOWN, KEY_S:
			if _sel < count - 1:
				_sel += 1
				Audio.play_se(&"cursol")
			else:
				_turn(1)
		KEY_LEFT, KEY_A:
			_turn(-1)
		KEY_RIGHT, KEY_D:
			_turn(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_confirm()
			return
	_screen.queue_redraw()


## `mAD_move_between`: the next / previous page comes to the front.
func _turn(dir: int) -> void:
	if _pages.size() < 2:
		return
	_page = wrapi(_page + dir, 0, _pages.size())
	_sel = 0 if dir > 0 else (_pages[_page] as Array).size() - 1
	Audio.play_se(&"cursol")


func _cancel() -> void:
	Audio.play_se(&"cursol")
	close()
	if _on_pick.is_valid():
		_on_pick.call({})


func _confirm() -> void:
	var recipient: Dictionary = (_pages[_page] as Array)[_sel]
	Audio.play_se(&"cursol")
	close()
	if _on_pick.is_valid():
		_on_pick.call(recipient)
		return
	var picker: Node = get_tree().get_first_node_in_group("letter_paper_picker_ui")
	if picker != null and picker.has_method("open"):
		picker.call("open", recipient)


func _draw_book() -> void:
	if not _open:
		return
	if not _choosing:
		_draw_title()
		return
	## `mAD_set_addressSel_tag`: two pages behind the current one, back to front.
	var n := _pages.size()
	var pile := [0.0, 0.0, 0.0]
	if n == 2:
		pile = [0.0, 5.0, 0.0] if _page == 0 else [5.0, 0.0, 5.0]
	elif n >= 3:
		pile[_page % 3] = 0.0
		pile[(_page + 1) % 3] = 5.0
		pile[(_page + 2) % 3] = 10.0
	var base := Vector2(_anchor_x + 4.0, 76.0 - 20.0)
	for depth in range(mini(n, 3) - 1, -1, -1):
		var idx := wrapi(_page + depth, 0, n)
		var p: float = pile[idx % 3]
		_draw_card(idx, base + Vector2(p, -p), depth)


func _draw_title() -> void:
	var tex := _layer("adr_mes")
	if tex != null:
		_screen.draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(320, 240)), false)
	## The Museum is always listed, so the empty-book title (`mAD_PROC_REFUSE`) never shows.
	var off: Vector2 = TITLE_OFFSET[0]
	_screen.draw_string(_font, Vector2(160 + off.x, 120 - off.y + _font.get_ascent(16)), TITLE,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TITLE_COLOR)


## One page's card at `pos` (units, y up) and its names (`mAD_set_addressSel_tag_character`).
func _draw_card(idx: int, pos: Vector2, depth: int) -> void:
	var entries: Array = _pages[idx]
	var count := clampi(entries.size(), 1, MAX_ENTRIES)
	var rect := Rect2(Vector2(pos.x, -pos.y), Vector2(320, 240))
	var shadow := _layer("adr_shadow_%d" % count)
	if shadow != null:
		_screen.draw_texture_rect(shadow, rect, false)
	var card := _layer("adr_card_%d" % count)
	if card != null:
		_screen.draw_texture_rect(card, rect, false, CARD_COLOR[1 if idx != 0 else 0][depth])
	var ofs_y := 11.0 + (count - 1) * (3.0 / (MAX_ENTRIES - 1))
	var x := 160.0 + pos.x + 7.0 - 34.0
	var y := 120.0 - (pos.y - ofs_y + 17.0)
	var asc := _font.get_ascent(NAME_PX)
	for i in entries.size():
		var museum: bool = idx == 0 and i == entries.size() - 1
		var col := NAME_VILLAGER
		if depth == 0 and i == _sel:
			col = NAME_SELECTED_MUSEUM if museum else NAME_SELECTED
		elif idx == 0:
			col = NAME_MUSEUM if museum else NAME_PLAYER
		_screen.draw_string(_font, Vector2(x, y + asc), str(entries[i].get("name", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_PX, col)
		y += 12.0
