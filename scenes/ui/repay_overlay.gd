class_name RepayOverlay
extends CanvasLayer

## The post office's loan screen (`m_repay_ovl.c`), in 320x240 screen units: "Your Loan",
## Cash, the six-digit amount with the picked digit in red, OK, and what is still owed.
## Keys: ←/→ digit, ↑/↓ change the amount, Space / Enter on OK or Escape (START) pays,
## Backspace (B) leaves unchanged. Rules live in `RepayCounter`. The window is the baked
## `rp_win` (`fkm_win_model`); a plain panel stands in without generated assets.

const GROUP := &"repay_ui"

signal closed(paid: bool)

const TEX := "res://assets/generated/ui/menu/rp_win.png"
const TITLE := "Your Loan"
## `mRP_set_*` colours.
const NORMAL := Color8(70, 120, 245)
const SELECT := Color8(215, 0, 0)
const CASH_COLOR := Color8(100, 40, 255)
const LOAN_COLOR := Color8(40, 185, 110)
const PANEL := Color8(250, 240, 205)
const PANEL_EDGE := Color8(140, 110, 70)
const FONT_PX := 16
const SMALL := 0.875
const NUM_RIGHT := 206.0

var counter := RepayCounter.new()
var _open: bool = false
var _paid: bool = false
var _font: Font = null
var _win: Texture2D = null
var _slide: MenuSlide = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas


## The one in `tree`, or null.
static func find(tree: SceneTree) -> RepayOverlay:
	return tree.get_first_node_in_group(GROUP) as RepayOverlay if tree != null else null


func _ready() -> void:
	layer = 21
	add_to_group(GROUP)
	add_to_group("shop_ui")
	_root.visible = false
	_font = LetterBoard.load_font()
	_win = load(TEX) as Texture2D if ResourceLoader.exists(TEX) else null
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


## `mRP_repay_ovl_init`: in from the top.
func open() -> void:
	if _open or Game == null or Game.inventory == null:
		return
	counter.open_from(Game.inventory)
	_paid = false
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
	closed.emit(_paid)


func _on_slid_out() -> void:
	if not _open:
		_root.visible = false


func commit() -> void:
	_paid = counter.commit(Game.inventory)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if _slide.is_moving():
		return
	handle_key((event as InputEventKey).keycode)


## `mRP_move_Play`.
func handle_key(key: Key) -> void:
	match key:
		KEY_BACKSPACE, KEY_B:
			close()
			return
		KEY_ESCAPE:
			commit()
			return
	if counter.cursor == RepayCounter.CURSOR_OK:
		match key:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				commit()
				return
			KEY_LEFT, KEY_A, KEY_UP, KEY_W:
				counter.left()
				Audio.play_se(&"cursol")
	else:
		match key:
			KEY_LEFT, KEY_A:
				if counter.left():
					Audio.play_se(&"cursol")
			KEY_RIGHT, KEY_D:
				if counter.right():
					Audio.play_se(&"cursol")
			KEY_UP, KEY_W:
				Audio.play_se(&"426" if counter.up() else &"3")
			KEY_DOWN, KEY_S:
				Audio.play_se(&"426" if counter.down() else &"3")
	_canvas.queue_redraw()


func _draw_canvas() -> void:
	if not _root.visible:
		return
	var c := counter
	if _win != null:
		_canvas.draw_texture_rect(_win, Rect2(Vector2.ZERO, Vector2(320, 240)), false)
	else:
		var panel := Rect2(Vector2(132, 52), Vector2(96, 120))
		_canvas.draw_rect(panel, PANEL)
		_canvas.draw_rect(panel, PANEL_EDGE, false, 2.0)
	if _font == null:
		return
	var small := int(round(FONT_PX * SMALL))
	var asc_s := _font.get_ascent(small)
	_canvas.draw_string(_font, Vector2(153, 64 + asc_s), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color.WHITE)
	_right_string(BankOverlay.with_commas(c.money), 91.0, small, CASH_COLOR)
	## The amount, digit by digit; the comma sits after the third.
	var amount := BankOverlay.with_commas(c.amount, 6)
	var w: float = _font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
	var x: float = NUM_RIGHT - w
	var picked: int = c.cursor + (1 if c.cursor >= 3 else 0)
	var asc := _font.get_ascent(FONT_PX)
	for i: int in amount.length():
		var ch := amount[i]
		_canvas.draw_string(_font, Vector2(x, 112 + asc), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX,
			SELECT if i == picked else NORMAL)
		x += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
	_canvas.draw_string(_font, Vector2(207, 128 + asc_s), "OK", HORIZONTAL_ALIGNMENT_LEFT, -1, small,
		SELECT if c.cursor >= RepayCounter.CURSOR_OK else NORMAL)
	_right_string(BankOverlay.with_commas(c.loan), 155.0, small, LOAN_COLOR, 209.0)


func _right_string(text: String, y: float, px: int, color: Color, right: float = NUM_RIGHT) -> void:
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_canvas.draw_string(_font, Vector2(right - w, y + _font.get_ascent(px)), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		px, color)
