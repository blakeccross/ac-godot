class_name LetterReaderOverlay
extends CanvasLayer

## "Read a letter" board overlay (`m_board_ovl.c`, `mSM_BD_OPEN_READ`). Shows the
## letter's real stationery art with header/body/footer text in the sender's ink
## color, matching decomp's text-safe box: left/right margins at 11.3% of the paper
## width (192px of a 248px-wide card, `mBD_MAX_WIDTH`/paper bounds, `m_board_ovl.c:
## 1220-1235`), header one line down from the top, a 6-line body, footer right-aligned
## to the same right margin. Paper art + ink color come from `LetterChrome`.
##
## READ mode never uses write-mode-only mechanics (caret, body pagination,
## `mBD_roll_control`) — confirmed dead code paths for `mSM_BD_OPEN_READ`
## (`m_board_ovl.c:1282,1312`), so this overlay is read-only and closes on any of
## A/B/Start, same as `mBD_move_Wait` (`m_board_ovl.c:830-835`).

signal closed(mail: MailData)

## `mSM_OVL_BOARD`'s slide-in (`m_submenu_ovl.c` data table row 12: `{0,300,0,75}`) —
## fast drop from off-screen top, decelerating into rest. Reproduced as a simple tween
## rather than the original's per-frame speed ramp; visually equivalent.
const SLIDE_DISTANCE := 420.0
const SLIDE_IN_TIME := 0.32
const SLIDE_OUT_TIME := 0.22

var _open: bool = false
var _mail: MailData = null

@onready var _dim: ColorRect = %Dim
@onready var _anchor: Control = %PaperAnchor
@onready var _paper: TextureRect = %Paper
@onready var _header: Label = %Header
@onready var _body: Label = %Body
@onready var _footer: Label = %Footer

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

	var paper_type: int = LetterChrome.clamp_paper_type(mail.paper_type)
	_paper.texture = LetterChrome.paper_texture(paper_type)
	var ink: Color = LetterChrome.ink_color(paper_type)
	_header.add_theme_color_override("font_color", ink)
	_body.add_theme_color_override("font_color", ink)
	_footer.add_theme_color_override("font_color", ink)
	_header.text = mail.header
	_body.text = mail.body
	_footer.text = mail.footer

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
	_anchor.position.y = -SLIDE_DISTANCE if opening else 0.0
	_dim.modulate.a = 0.0 if opening else 1.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	var target_y: float = 0.0 if opening else -SLIDE_DISTANCE
	var duration: float = SLIDE_IN_TIME if opening else SLIDE_OUT_TIME
	_tween.tween_property(_anchor, "position:y", target_y, duration)
	_tween.tween_property(_dim, "modulate:a", 1.0 if opening else 0.0, duration)
	await _tween.finished


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
