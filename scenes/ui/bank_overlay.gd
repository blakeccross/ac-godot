class_name BankOverlay
extends CanvasLayer

## The post office ABD screen (`m_bank_ovl.c`), in 320x240 screen units: the piggy-bank
## window (`tyo_win`), "Your Account", Cash and Balance in their colours, the six-digit
## amount with the picked digit in red, OK, and the Deposit / Withdrawal captions lit for
## the way cash is moving. Keys: ←/→ digit, ↑ deposit, ↓ withdraw, Space / Enter on OK or
## Escape (START) settles, Backspace (B) leaves unchanged. Rules live in `BankTerminal`.

signal closed(committed: bool)

const TEX_DIR := "res://assets/generated/ui/menu/%s.png"
const TITLE := "Your Account"
const NORMAL := Color8(0, 50, 255)
const SELECT := Color8(195, 20, 20)
const BANK_COLOR := Color8(170, 60, 145)
const CASH_COLOR := Color8(115, 50, 215)
const FONT_PX := 16
const SMALL := 0.875
const NUM_RIGHT := 211.0

var terminal := BankTerminal.new()
var _open: bool = false
var _committed: bool = false
var _tex: Dictionary = {}
var _font: Font = null
var _slide: MenuSlide = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas


func _ready() -> void:
	layer = 21
	add_to_group("bank_ui")
	add_to_group("shop_ui")
	_root.visible = false
	_font = LetterBoard.load_font()
	for name: String in ["bk_win", "bk_dep_on", "bk_dep_off", "bk_wd_on", "bk_wd_off"]:
		var path := TEX_DIR % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	_canvas.draw.connect(_draw_canvas)
	_slide = MenuSlide.attach(self)
	_root.resized.connect(_fit_screen)
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


## `mBN_bank_ovl_init`: `move_drt` 5, in from the top.
func open() -> void:
	if _open or Game == null or Game.inventory == null:
		return
	terminal.open_from(Game.inventory)
	_committed = false
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)
	_slide.slide_in(MenuSlide.Dir.IN_TOP)
	_canvas.queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	Audio.play_se(&"menu_exit")
	_slide.slide_out(MenuSlide.Dir.OUT_TOP, _on_slid_out)
	closed.emit(_committed)


func _on_slid_out() -> void:
	if not _open:
		_root.visible = false


## `mBN_bank_ok`.
func commit() -> void:
	terminal.commit(Game.inventory)
	_committed = true
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if _slide.is_moving():
		return
	handle_key((event as InputEventKey).keycode)


## `mBN_move_Play`.
func handle_key(key: Key) -> void:
	match key:
		KEY_BACKSPACE, KEY_B:
			close()
			return
		KEY_ESCAPE:
			commit()
			return
	if terminal.cursor == BankTerminal.CURSOR_OK:
		match key:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				commit()
				return
			KEY_LEFT, KEY_A, KEY_UP, KEY_W:
				terminal.left()
				Audio.play_se(&"cursol")
	else:
		match key:
			KEY_LEFT, KEY_A:
				if terminal.left():
					Audio.play_se(&"cursol")
			KEY_RIGHT, KEY_D:
				if terminal.right():
					Audio.play_se(&"cursol")
			KEY_UP, KEY_W:
				Audio.play_se(&"426" if terminal.deposit() else &"3")
			KEY_DOWN, KEY_S:
				Audio.play_se(&"426" if terminal.withdraw() else &"3")
	_canvas.queue_redraw()


## `mFont_UnintToString` with commas: "1,234,567".
static func with_commas(n: int, pad_digits: int = 0) -> String:
	var digits := str(absi(n))
	while digits.length() < pad_digits:
		digits = "0" + digits
	var out := ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


func _blit(name: String) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex != null:
		_canvas.draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(320, 240)), false)


func _draw_canvas() -> void:
	if not _root.visible:
		return
	var t := terminal
	_blit("bk_win")
	_blit("bk_dep_on" if t.now_bell <= t.player_bell else "bk_dep_off")
	_blit("bk_wd_on" if t.now_bell >= t.player_bell else "bk_wd_off")
	if _font == null:
		return
	var small := int(round(FONT_PX * SMALL))
	var asc_s := _font.get_ascent(small)
	_canvas.draw_string(_font, Vector2(145, 65 + asc_s), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color.WHITE)
	_right_string(with_commas(t.bank_bell), 157.0, small, BANK_COLOR)
	_right_string(with_commas(t.now_bell), 98.0, small, CASH_COLOR)
	## The amount, digit by digit; the comma sits after the third.
	var amount := with_commas(t.bell, 6)
	var w: float = _font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
	var x: float = NUM_RIGHT - w
	var picked: int = t.cursor + (1 if t.cursor >= 3 else 0)
	var asc := _font.get_ascent(FONT_PX)
	for i: int in amount.length():
		var ch := amount[i]
		_canvas.draw_string(_font, Vector2(x, 124 + asc), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX,
			SELECT if i == picked else NORMAL)
		x += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
	_canvas.draw_string(_font, Vector2(208, 140 + asc_s), "OK", HORIZONTAL_ALIGNMENT_LEFT, -1, small,
		SELECT if t.cursor >= BankTerminal.CURSOR_OK else NORMAL)


func _right_string(text: String, y: float, px: int, color: Color) -> void:
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_canvas.draw_string(_font, Vector2(NUM_RIGHT - w, y + _font.get_ascent(px)), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		px, color)
