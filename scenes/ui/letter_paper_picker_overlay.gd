extends CanvasLayer

## Stationery picker — the first step of writing a letter. The original writes on the
## stationery item chosen in the pockets (`mTG_write_proc`); this port has no
## stationery items, so the player flips through all 64 papers instead, shown full-size
## on the board (`LetterBoard`) as they will be written on, with the question in the
## address book's message window. An approved simplification, not a missing feature.
##
## Left / right flip a paper, up / down eight; A (Space / Enter) takes it; B / Esc backs out.

const PAPER_COUNT := LetterChrome.PAPER_COUNT
const TITLE := "Which stationery?"
const TITLE_COLOR := Color8(80, 80, 230)
## The message window sits under the paper (`lat_mes_winT_model` is 216x40 at the origin).
const TITLE_Y := -98.0

var _open: bool = false
var _recipient: Dictionary = {}
var _sel: int = 0
var _mes: Texture2D = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _board: LetterBoard = $Root/Screen/Board
@onready var _title: Control = $Root/Screen/Title


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("letter_paper_picker_ui")
	_root.visible = false
	_title.draw.connect(_draw_title)
	_root.resized.connect(_fit_screen)
	var path := "res://assets/generated/ui/menu/adr_mes.png"
	_mes = load(path) if ResourceLoader.exists(path) else null
	_fit_screen()
	set_process_unhandled_input(false)


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func is_open() -> bool:
	return _open


## Without a recipient the board opens next with the address book over it (the
## original order: paper, then board + address book).
func open(recipient: Dictionary = {}) -> void:
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
		KEY_LEFT, KEY_A: _step(-1)
		KEY_RIGHT, KEY_D: _step(1)
		KEY_UP, KEY_W: _step(-8)
		KEY_DOWN, KEY_S: _step(8)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		KEY_ESCAPE, KEY_B:
			Audio.play_se(&"cursol")
			close()


func _step(d: int) -> void:
	_sel = wrapi(_sel + d, 0, PAPER_COUNT)
	Audio.play_se(&"cursol")
	_refresh()


func _confirm() -> void:
	var paper_type := _sel
	Audio.play_se(&"cursol")
	close()
	var writer: Node = get_tree().get_first_node_in_group("letter_writer_ui")
	if writer == null:
		return
	if _recipient.is_empty() and writer.has_method("open_letter"):
		writer.call("open_letter", paper_type)
	elif writer.has_method("open"):
		writer.call("open", _recipient, paper_type)


func _refresh() -> void:
	if not _open:
		return
	_board.paper_type = _sel
	_title.queue_redraw()


func _draw_title() -> void:
	var font := _board.font()
	var off := Vector2(0, -TITLE_Y)
	if _mes != null:
		_title.draw_texture_rect(_mes, Rect2(off, Vector2(320, 240)), false)
	var text := "%s   %d / %d" % [TITLE, _sel + 1, PAPER_COUNT]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_title.draw_string(font, Vector2(160 - w * 0.5, 120 - TITLE_Y - 8 + font.get_ascent(16)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TITLE_COLOR)
