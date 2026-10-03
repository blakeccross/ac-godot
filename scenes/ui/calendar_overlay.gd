class_name CalendarOverlay
extends CanvasLayer

## The calendar (`m_calendar_ovl.c`), opened from the diary in the player's room. Month
## pages from eleven months back to eleven ahead: ← / → turn a page (it slides 320 across),
## ↑ comes back to this month, Space / Enter (A) picks a day, Escape / Backspace (B) leaves.
## On a day, the arrows move the box (↑ / ↓ step through the day's events first when it has
## more than one), A opens the diary on that month and B goes back to the months. Each box
## is coloured by its day type (`box_prim_table`); played days carry a footprint, days with
## Tortimer a red one (`CalendarBook`); the event plate names the picked day's event, with a
## fish badge when the player took part.

signal closed

const TEX_DIR := "res://assets/generated/ui/menu/%s.png"
## `box_prim_table` / `number_prim_table` / `number2_prim_table` by `CalendarBook.DayType`.
const NUMBER_PRIM: Array[Color] = [
	Color8(0x82, 0x64, 0x3C), Color8(0x82, 0x64, 0x3C), Color8(0x7D, 0x5F, 0x55), Color8(0x82, 0x64, 0x3C),
	Color8(0x6E, 0x6E, 0x7D),
]
const NUMBER2_PRIM: Array[Color] = [
	Color8(0x82, 0x64, 0x3C), Color8(0x4B, 0x32, 0x32), Color8(0x55, 0x28, 0x28), Color8(0x4B, 0x32, 0x32),
	Color8(0x3C, 0x3C, 0x4B),
]
const CELL := Vector2(32.0, 20.0)
## `Matrix_translate(0, 4)`: the picked day's number, mark and cursor sit 4 units up.
const PICKED_LIFT := 4.0
## `mCD_disp_event_dl`: the event's name.
const NAME_POS := Vector2(128.0, 161.0)
const NAME_SCALE := 0.875
const FONT_PX := 16
## `calendar->_1034`, `-1.5`: the event arrows.
const ARROW_POS := Vector2(98.0, 1.5)
const SPAN := 11
const PAGE_W := 320.0
## `add_calc(…, 0.4, 37, 1.25)`; the key hints swap by sliding 100 down.
const EASE := 0.4
const EASE_MAX := 37.0
const EASE_MIN := 1.25
const HINT_DROP := 100.0

enum Mode { MONTHS, TURN, TO_DAY, DAY, TO_MONTHS, DIARY }

## Months from this one (−11 … +11) and the picked cell.
var month_off: int = 0
var cell: int = 0
var event_idx: int = 0
var mode: int = Mode.MONTHS

var _open: bool = false
var _tex: Dictionary = {}
var _font: Font = null
var _slide: MenuSlide = null
var _pages: Dictionary = {}
var _today: int = 0
var _slide_x: float = 0.0
var _turns: int = 0
var _hint1: float = 0.0
var _hint2: float = HINT_DROP
var _blink: float = 0.0
var _side: int = 0
var _accum: float = 0.0

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas


func _ready() -> void:
	layer = 21
	add_to_group("calendar_ui")
	_root.visible = false
	_font = LetterBoard.load_font()
	_canvas.draw.connect(_draw_canvas)
	_slide = MenuSlide.attach(self)
	_root.resized.connect(_fit_screen)
	_fit_screen()
	set_process(false)
	set_process_unhandled_input(false)


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := TEX_DIR % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func is_open() -> bool:
	return _open


## `mCD_calendar_ovl_init`: in from the top on this month, today noted as played.
func open() -> void:
	if _open:
		return
	_today = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	if Game != null:
		CalendarBook.played_on(Game.calendar, _today)
	_pages.clear()
	month_off = 0
	mode = Mode.MONTHS
	_slide_x = 0.0
	_hint1 = 0.0
	_hint2 = HINT_DROP
	_open = true
	_root.visible = true
	set_process(true)
	set_process_unhandled_input(true)
	Audio.play_se(&"17c")
	_slide.slide_in(MenuSlide.Dir.IN_TOP)
	_canvas.queue_redraw()


## Straight onto `day` of this month (the console's `calendar day N`).
func open_on_day(day: int) -> void:
	open()
	mode = Mode.DAY
	_hint1 = HINT_DROP
	_hint2 = 0.0
	_pick_cell(clampi(day, 1, EventDates.days_in_month(Clock.year, Clock.month)))


func close() -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	Audio.play_se(&"17d")
	_slide.slide_out(MenuSlide.Dir.OUT_TOP, _on_slid_out)
	closed.emit()


func _on_slid_out() -> void:
	if _open:
		return
	_root.visible = false
	set_process(false)


## (year, month) `off` months from now.
static func month_at(year: int, month: int, off: int) -> Vector2i:
	var n: int = year * 12 + (month - 1) + off
	return Vector2i(floori(n / 12.0), posmod(n, 12) + 1)


func page(off: int) -> Dictionary:
	if not _pages.has(off):
		var ym: Vector2i = month_at(Clock.year, Clock.month, off)
		var state: Dictionary = Game.calendar if Game != null else CalendarBook.new_state()
		var town_day: int = Game.events.town_day if Game != null and Game.events != null else 15
		_pages[off] = CalendarBook.page(ym.x, ym.y, state, _today, town_day, VillagerTalkManager.birthday())
	return _pages[off]


## The day's events, or [].
func day_events() -> Array:
	return (page(month_off)["events"] as Dictionary).get(cell, [])


func day_type() -> int:
	return int((page(month_off)["types"] as Array)[cell])


func _process(delta: float) -> void:
	_accum += delta * DecompTime.FRAME_HZ
	while _accum >= 1.0:
		_accum -= 1.0
		_frame()
	_side = int(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) \
		- int(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A))
	_canvas.queue_redraw()


func _frame() -> void:
	match mode:
		Mode.TURN:
			_slide_x = AcreCamera.add_calc(_slide_x, 0.0, EASE, EASE_MAX, EASE_MIN) if _turns <= 1 \
				else move_toward(_slide_x, 0.0, EASE_MAX)
			if absf(_slide_x) < 0.1:
				_turns -= 1
				if _turns <= 0:
					_slide_x = 0.0
					mode = Mode.MONTHS
				else:
					var dir: int = 1 if month_off < 0 else -1
					month_off += dir
					_slide_x = PAGE_W * dir
					Audio.play_se(&"5f")
		Mode.TO_DAY, Mode.TO_MONTHS:
			var to_day: bool = mode == Mode.TO_DAY
			_hint1 = AcreCamera.add_calc(_hint1, HINT_DROP if to_day else 0.0, EASE, EASE_MAX, EASE_MIN)
			_hint2 = AcreCamera.add_calc(_hint2, 0.0 if to_day else HINT_DROP, EASE, EASE_MAX, EASE_MIN)
			if is_equal_approx(_hint1, HINT_DROP if to_day else 0.0) and is_equal_approx(_hint2, 0.0 if to_day else HINT_DROP):
				if to_day:
					mode = Mode.DAY
					_pick_cell(Clock.day if month_off == 0 else 1)
				else:
					mode = Mode.MONTHS
		Mode.DAY:
			## `_1054`: the event arrows pulse once every two seconds.
			_blink = fmod(_blink + 1.0, 60.0)


func _pick_cell(day: int) -> void:
	cell = int(page(month_off)["first"]) + day - 1
	event_idx = 0
	_blink = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not _open or mode == Mode.DIARY or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if _slide.is_moving():
		return
	var k := event as InputEventKey
	if mode == Mode.MONTHS:
		_months_key(k)
	elif mode == Mode.DAY:
		_day_key(k)
	_canvas.queue_redraw()


## `mCD_MVPL_select`.
func _months_key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_ESCAPE, KEY_BACKSPACE, KEY_B:
			if not k.echo:
				close()
		KEY_LEFT, KEY_A:
			if month_off > -SPAN:
				_turn(-1, 1)
		KEY_RIGHT, KEY_D:
			if month_off < SPAN:
				_turn(1, 1)
		KEY_UP, KEY_W:
			if month_off != 0 and not k.echo:
				_turn(-signi(month_off), absi(month_off))
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				mode = Mode.TO_DAY
				Audio.play_se(&"5f")


func _turn(dir: int, count: int) -> void:
	month_off += dir
	_turns = count
	_slide_x = PAGE_W * dir
	mode = Mode.TURN
	Audio.play_se(&"5f")


## `mCD_MVPL_day`.
func _day_key(k: InputEventKey) -> void:
	var days: Array = page(month_off)["days"]
	var events: Array = day_events()
	match k.keycode:
		KEY_ESCAPE, KEY_BACKSPACE, KEY_B:
			if not k.echo:
				mode = Mode.TO_MONTHS
				Audio.play_se(&"menu_exit")
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				_open_diary()
		KEY_LEFT, KEY_A:
			if int(days[cell]) > 1:
				_move(-1)
		KEY_RIGHT, KEY_D:
			if cell < CalendarBook.CELLS - 1 and int(days[cell + 1]) > 0:
				_move(1)
		KEY_UP, KEY_W:
			if events.size() > 1 and event_idx > 0:
				event_idx -= 1
				Audio.play_se(&"cursol")
			elif int(days[cell]) > CalendarBook.WEEK:
				_move(-CalendarBook.WEEK)
		KEY_DOWN, KEY_S:
			if events.size() > 1 and event_idx + 1 < events.size():
				event_idx += 1
				Audio.play_se(&"cursol")
			elif cell + CalendarBook.WEEK < CalendarBook.CELLS and int(days[cell + CalendarBook.WEEK]) > 0:
				_move(CalendarBook.WEEK)


func _move(step: int) -> void:
	cell += step
	event_idx = 0
	_blink = 0.0
	Audio.play_se(&"cursol")


## A on a day: the diary opens on its month (`mSM_OVL_DIARY`); the calendar waits.
func _open_diary() -> void:
	var diary: Node = get_tree().get_first_node_in_group("diary_ui") if get_tree() != null else null
	if diary == null or not diary.has_method("open"):
		return
	Audio.play_se(&"5f")
	mode = Mode.DIARY
	_root.visible = false
	diary.call("open", month_at(Clock.year, Clock.month, month_off).y)
	if diary.has_signal("closed"):
		diary.connect("closed", _on_diary_closed, CONNECT_ONE_SHOT)


func _on_diary_closed() -> void:
	if not _open:
		return
	mode = Mode.DAY
	_root.visible = true
	_slide.slide_in(MenuSlide.Dir.IN_TOP)


func _blit(name: String, at: Vector2, tint: Color = Color.WHITE) -> void:
	var tex: Texture2D = _t(name)
	if tex != null:
		_canvas.draw_texture_rect(tex, Rect2(at, Vector2(320, 240)), false, tint)


func _draw_canvas() -> void:
	if not _root.visible:
		return
	if mode == Mode.TURN and _slide_x != 0.0:
		## The page being left, one width behind the one coming in.
		_draw_page(month_off - signi(int(signf(_slide_x))), _slide_x - signf(_slide_x) * PAGE_W)
	_draw_page(month_off, _slide_x)
	if mode in [Mode.MONTHS, Mode.TURN, Mode.TO_DAY, Mode.TO_MONTHS]:
		_draw_hints(Vector2(0.0, _hint1))
	if mode in [Mode.TO_DAY, Mode.DAY, Mode.TO_MONTHS, Mode.DIARY]:
		_blit("cal_hy2", Vector2(0.0, _hint2))
	if mode == Mode.DAY:
		_draw_event_name()


## `mCD_set_base_dl`.
func _draw_page(off: int, x: float) -> void:
	if off < -SPAN or off > SPAN:
		return
	var p: Dictionary = page(off)
	var ym: Vector2i = month_at(Clock.year, Clock.month, off)
	var at := Vector2(x, 0.0)
	var picked: int = cell if mode == Mode.DAY and off == month_off else -1
	var events: Array = day_events() if picked >= 0 else []
	_blit("cal_base_m%d" % ym.y, at)
	if events.is_empty():
		_blit("cal_event_t0", at)
	var year: int = ym.x
	for place: int in 4:
		_blit("cal_nen_p%d_d%d" % [place, year % 10], at)
		year /= 10
	_blit("cal_month_m%d" % ym.y, at)
	var days: Array = p["days"]
	var types: Array = p["types"]
	var icons: Array = p["icons"]
	for i: int in CalendarBook.CELLS:
		if i == picked:
			continue
		var c := at + Vector2((i % CalendarBook.WEEK) * CELL.x, (i / CalendarBook.WEEK) * CELL.y)
		var t: int = int(types[i])
		_blit("cal_box_t%d" % t, c)
		if int(days[i]) > 0:
			_blit("cal_num%d" % int(days[i]), c, NUMBER_PRIM[t])
		if int(icons[i]) > 0:
			_blit("cal_mark%d" % int(icons[i]), c)
	if picked < 0:
		return
	var t2: int = int(types[picked])
	var pc := at + Vector2((picked % CalendarBook.WEEK) * CELL.x, (picked / CalendarBook.WEEK) * CELL.y)
	_blit("cal_box2_t%d" % t2, pc)
	var lifted := pc - Vector2(0.0, PICKED_LIFT)
	if int(days[picked]) > 0:
		_blit("cal_num%d" % int(days[picked]), lifted, NUMBER2_PRIM[t2])
	if int(icons[picked]) > 0:
		_blit("cal_mark%d" % int(icons[picked]), lifted)
	_blit("cal_cursor", lifted)
	if events.is_empty():
		return
	_blit("cal_event_t%d" % t2, at)
	var ev: Array = events[clampi(event_idx, 0, events.size() - 1)]
	if bool(ev[1]):
		_blit("cal_sakana", at)
	if events.size() > 1:
		var pulse: float = clampf(1.0 - absf((_blink - 30.0) / 30.0), 0.0, 1.0)
		_blit("cal_yaji_b" if event_idx == events.size() - 1 else "cal_yaji_a", at + ARROW_POS,
			Color(1.0, 1.0, 1.0, pulse))


## `mCD_set_hyoji_dl`: the key hints, page arrows while choosing a month, and the stick
## (tilted, and turned round for →, while a page key is held).
func _draw_hints(at: Vector2) -> void:
	_blit("cal_hy", at)
	if mode == Mode.MONTHS:
		_blit("cal_hy_y", at)
		if month_off > -SPAN:
			_blit("cal_hy_ya", at)
		if month_off < SPAN:
			_blit("cal_hy_yb", at)
	var tex: Texture2D = _t("cal_hy_st5" if _side != 0 else "cal_hy_st1")
	if tex == null:
		return
	if _side > 0:
		_canvas.draw_set_transform(at + Vector2(320.0, 0.0), 0.0, Vector2(-1.0, 1.0))
		_canvas.draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(320, 240)), false)
		_canvas.draw_set_transform(Vector2.ZERO)
	else:
		_canvas.draw_texture_rect(tex, Rect2(at, Vector2(320, 240)), false)


func _draw_event_name() -> void:
	var events: Array = day_events()
	if events.is_empty() or _font == null:
		return
	var ev: Array = events[clampi(event_idx, 0, events.size() - 1)]
	var town: String = Game.town_name if Game != null else ""
	var px: int = roundi(FONT_PX * NAME_SCALE)
	_canvas.draw_string(_font, NAME_POS + Vector2(0.0, _font.get_ascent(px)), CalendarBook.event_name(int(ev[0]), town),
		HORIZONTAL_ALIGNMENT_LEFT, -1, px, NUMBER2_PRIM[day_type()])
