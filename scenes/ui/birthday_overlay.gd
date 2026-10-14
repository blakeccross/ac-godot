class_name BirthdayOverlay
extends CanvasLayer

## "When's your birthday?" (`m_birthday_ovl.c`), opened when a villager asks
## (`aQMgr_order_input_birthday`). Month, day, then OK: ↑ / ↓ change the one picked (red),
## → / Space / Enter step on (Enter on OK closes), ← / Backspace step back, Escape (START)
## closes. Values wrap the way `mBR_move_Play` checks them against a leap year: a day past
## the month's end goes back to 1, below 1 to the month's last day, and a month change
## pulls the day into range. Closing saves the date (`Private.birthday`).

signal closed

const TEX_DIR := "res://assets/generated/ui/menu/%s.png"
const PROMPT := "When's your birthday?"
const OK := "OK"
## `color_type`: picked, not picked.
const RED := Color8(195, 0, 0)
const BLUE := Color8(70, 145, 225)
const PROMPT_POS := Vector2(119.0, 88.0)
const DAY_POS := Vector2(171.0, 124.0)
const OK_POS := Vector2(198.0, 124.0)
const FONT_PX := 16
## `work_time`'s year 2000: February has 29 days.
const LEAP_YEAR := 2000

enum Field { MONTH, DAY, OK }

var month: int = 1
var day: int = 1
var field: int = Field.MONTH

var _open: bool = false
var _tex: Dictionary = {}
var _font: Font = null
var _slide: MenuSlide = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas


func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("birthday_ui")
	_root.visible = false
	_font = LetterBoard.load_font()
	var names: Array[String] = ["br_win"]
	for m: int in range(1, 13):
		names.append("br_m%d_on" % m)
		names.append("br_m%d_off" % m)
	for name: String in names:
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


## `mBR_birthday_ovl_init`: in from the top at January 1st.
func open() -> void:
	if _open:
		return
	month = 1
	day = 1
	field = Field.MONTH
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)
	Audio.play_se(&"17c")
	_slide.slide_in(MenuSlide.Dir.IN_TOP)
	_canvas.queue_redraw()


## `mBR_window_close`: the date is kept.
func close() -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	if Game != null and Game.events != null:
		Game.events.birthday_md = EventDates.md(month, day)
	Audio.play_se(&"menu_exit")
	_slide.slide_out(MenuSlide.Dir.OUT_TOP, _on_slid_out)
	closed.emit()


func _on_slid_out() -> void:
	if not _open:
		_root.visible = false


static func last_day(m: int) -> int:
	return EventDates.days_in_month(LEAP_YEAR, m)


## `mBR_move_Play`'s ↑ / ↓ on the picked field. Returns {month, day}.
static func step(m: int, d: int, which: int, up: bool) -> Vector2i:
	if which == Field.MONTH:
		m += 1 if up else -1
		if m > 12:
			m = 1
		elif m < 1:
			m = 12
		d = mini(d, last_day(m))
	elif which == Field.DAY:
		d += 1 if up else -1
		if d > last_day(m):
			d = 1
		elif d < 1:
			d = last_day(m)
	return Vector2i(m, d)


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if _slide.is_moving():
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_UP, KEY_W, KEY_DOWN, KEY_S:
			if field != Field.OK:
				var v: Vector2i = step(month, day, field, k.keycode == KEY_UP or k.keycode == KEY_W)
				month = v.x
				day = v.y
				Audio.play_se(&"cursol")
		KEY_RIGHT, KEY_D, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if k.echo:
				return
			if field == Field.OK:
				if k.keycode != KEY_RIGHT and k.keycode != KEY_D:
					close()
			else:
				field += 1
				Audio.play_se(&"sentaku_kettei")
		KEY_LEFT, KEY_A, KEY_BACKSPACE, KEY_B:
			if field != Field.MONTH:
				field -= 1
				Audio.play_se(&"cursol")
		KEY_ESCAPE:
			if not k.echo:
				close()
	_canvas.queue_redraw()


func _blit(name: String) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex != null:
		_canvas.draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(320, 240)), false)


func _text(text: String, pos: Vector2, color: Color, scale: float = 1.0) -> void:
	if _font == null:
		return
	var px: int = roundi(FONT_PX * scale)
	_canvas.draw_string(_font, pos + Vector2(0.0, _font.get_ascent(px)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _draw_canvas() -> void:
	if not _root.visible:
		return
	_blit("br_win")
	_blit("br_m%d_%s" % [month, "on" if field == Field.MONTH else "off"])
	_text(PROMPT, PROMPT_POS, Color.WHITE, 0.875)
	_text("%2d" % day, DAY_POS, RED if field == Field.DAY else BLUE)
	_text(OK, OK_POS, RED if field == Field.OK else BLUE)
