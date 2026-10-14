class_name LetterReaderOverlay
extends CanvasLayer

## "Read a letter" (`m_board_ovl.c`, `mSM_BD_OPEN_READ`): the letter on its stationery
## via `LetterBoard` — the paper model, header, six body lines and right-aligned footer
## at the board's own offsets, in the paper's ink colour. The board drops in from the
## top (`mSM_MOVE_IN_TOP`) and closes on A / B / Start like `mBD_move_Wait`.

signal closed(mail: MailData)

## The board's slide (`m_submenu_ovl.c` row 12: `{0, 300, 0, 75}`): from 300 units up,
## reproduced as a tween.
const SLIDE_DISTANCE := 300.0
const SLIDE_IN_TIME := 0.32
const SLIDE_OUT_TIME := 0.22

var _open: bool = false
var _mail: MailData = null

@onready var _dim: ColorRect = %Dim
@onready var _screen: Control = %Screen
@onready var _board: LetterBoard = %Board

var _tween: Tween = null


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("letter_reader_ui")
	visible = false
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


func open(mail: MailData) -> void:
	if _open or mail == null:
		return
	_mail = mail
	_open = true
	visible = true
	set_process_unhandled_input(true)

	_fit_screen()
	_board.paper_type = mail.paper_type
	_board.header = mail.header
	_board.header_name = ""
	_board.body_lines = _board.wrap(mail.body)
	_board.footer = mail.footer

	mail.mark_read()
	if Game != null and Game.inventory != null:
		Game.inventory.mail_changed.emit()

	Audio.play_se(&"cursol")
	_slide(true)


func close() -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	Audio.play_se(&"menu_exit")
	await _slide(false)
	visible = false
	var mail := _mail
	_mail = null
	closed.emit(mail)


func _slide(opening: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_board.position_y = SLIDE_DISTANCE if opening else 0.0
	_dim.modulate.a = 0.0 if opening else 1.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	var target_y: float = 0.0 if opening else SLIDE_DISTANCE
	var duration: float = SLIDE_IN_TIME if opening else SLIDE_OUT_TIME
	_tween.tween_property(_board, "position_y", target_y, duration)
	_tween.tween_property(_dim, "modulate:a", 1.0 if opening else 0.0, duration)
	await _tween.finished


func _fit_screen() -> void:
	var root := _screen.get_parent() as Control
	var sz := root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = root.get_viewport_rect().size
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
