class_name DiaryOverlay
extends CanvasLayer

## The diary (`m_diary_ovl.c`): one long page per month, `mDI_ENTRY_SIZE` (992) characters in
## up to 31 lines 192 px wide, on three stacked sheets (`dia_win`, `dia_win2` 194 below,
## `dia_win3` 358 below) under the month's tab ("April Entry", `month_tex_adjust`). Read
## mode scrolls the page with ↑/↓, ←/→ turn to the month before or after, Space / Enter (A)
## writes: the keyboard types onto the page and the page rolls to keep the line in view
## (`mDI_roll_control`), then "Is this OK?" (`mEE_TYPE_BOARD`). Escape / Backspace leaves.
## It opens from the calendar (`CalendarOverlay`, `m_calendar_ovl.c`) on a diary in the
## player's room, on the month of the day picked there.

signal closed

const TEX_DIR := "res://assets/generated/ui/menu/%s.png"
const ENTRY_SIZE := 992
const LINES := 31
const TEXT_ORIGIN := Vector2(64.0, 64.0)
## `letter_color`.
const TEXT_COLOR := Color8(60, 60, 85)
const FONT_PX := 16
## Where the second and third sheets sit below the first (`Matrix_translate(0, -194)`,
## then `-164`).
const SHEET_2 := 194.0
const SHEET_3 := 358.0
## The last line is in view with a little paper below it.
const MAX_SCROLL := 344.0
const SCROLL_STEP := 4.0
## `month_tex_adjust`: the caption ("Entry") slides left behind shorter month words.
const MONTH_ADJUST: Array[float] = [-26, -16, -40, -52, -57, -52, -57, -32, 0, -23, -6, -6]

var month: int = 1
var scroll: float = 0.0
var writing: bool = false

var _open: bool = false
var _tex: Dictionary = {}
var _font: Font = null
var _slide: MenuSlide = null
var _hold: int = 0
var _accum: float = 0.0

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas


func _ready() -> void:
	layer = 21
	add_to_group("diary_ui")
	_root.visible = false
	_font = LetterBoard.load_font()
	var names: Array[String] = ["dia_w1", "dia_w2", "dia_w3", "dia_moji"]
	for m: int in range(1, 13):
		names.append("dia_m%d" % m)
	for name: String in names:
		var path := TEX_DIR % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
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


func is_open() -> bool:
	return _open


## `mDI_diary_ovl_init`: in from the left on `p_month`'s page (1–12).
func open(p_month: int = -1) -> void:
	if _open:
		return
	month = clampi(p_month if p_month > 0 else Clock.month, 1, 12)
	scroll = 0.0
	writing = false
	_open = true
	_root.visible = true
	set_process(true)
	set_process_unhandled_input(true)
	Audio.play_se(&"5f")
	_slide.slide_in(MenuSlide.Dir.IN_LEFT)
	_canvas.queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	Audio.play_se(&"17d")
	_slide.slide_out(MenuSlide.Dir.OUT_LEFT, _on_slid_out)
	closed.emit()


func _on_slid_out() -> void:
	if _open:
		return
	_root.visible = false
	set_process(false)


static func entry(m: int) -> String:
	return str(Game.diary.get(m, "")) if Game != null else ""


## Up to 31 lines and 992 characters, as the editor hands them back.
static func clip(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	while lines.size() > LINES:
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines).substr(0, ENTRY_SIZE)


func _process(delta: float) -> void:
	if writing:
		return
	_accum += delta * DecompTime.TICK_HZ
	var dir: int = int(Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)) \
		- int(Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W))
	while _accum >= 1.0:
		_accum -= 1.0
		if dir != 0:
			scroll = clampf(scroll + dir * SCROLL_STEP, 0.0, MAX_SCROLL)
			_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or writing or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if _slide.is_moving():
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_LEFT, KEY_A:
			_turn(-1)
		KEY_RIGHT, KEY_D:
			_turn(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				_write()
		KEY_ESCAPE, KEY_BACKSPACE, KEY_B:
			if not k.echo:
				close()


func _turn(step: int) -> void:
	month = posmod(month - 1 + step, 12) + 1
	scroll = 0.0
	Audio.play_se(&"5f")
	_canvas.queue_redraw()


## A: the keyboard writes on this month's page.
func _write() -> void:
	var writer: Node = get_tree().get_first_node_in_group("letter_writer_ui") if get_tree() != null else null
	if writer == null or not writer.has_method("open_board"):
		return
	writing = true
	scroll = 0.0
	var style := {
		"text": TEXT_ORIGIN, "color": TEXT_COLOR, "frame": false, "prompt": EditEndPrompt.Kind.BOARD,
		"roll": func(offset: float) -> void:
			scroll = clampf(offset, 0.0, MAX_SCROLL)
			_canvas.queue_redraw(),
	}
	writer.call("open_board", entry(month), LINES, ENTRY_SIZE, _on_written, 0, style)
	if writer.has_signal("closed") and not writer.is_connected("closed", _on_writer_closed):
		writer.connect("closed", _on_writer_closed, CONNECT_ONE_SHOT)
	_canvas.queue_redraw()


func _on_written(text: String) -> void:
	if Game == null:
		return
	var kept: String = clip(text)
	if kept.strip_edges() == "":
		Game.diary.erase(month)
	else:
		Game.diary[month] = kept


func _on_writer_closed() -> void:
	writing = false
	scroll = 0.0
	_canvas.queue_redraw()


func _blit(name: String, dy: float, dx: float = 0.0) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex != null:
		_canvas.draw_texture_rect(tex, Rect2(Vector2(dx, dy), Vector2(320, 240)), false)


## `mDI_set_frame_dl` + `mDI_set_writing_body`.
func _draw_canvas() -> void:
	if not _open and not _root.visible:
		return
	var top: float = -scroll
	_blit("dia_w1", top)
	_blit("dia_w2", top + SHEET_2)
	_blit("dia_w3", top + SHEET_3)
	_blit("dia_m%d" % month, top)
	_blit("dia_moji", top, MONTH_ADJUST[month - 1])
	## While writing, the editor draws the words over the page.
	if writing or _font == null:
		return
	var asc: float = _font.get_ascent(FONT_PX)
	var lines: PackedStringArray = entry(month).split("\n")
	for i: int in mini(lines.size(), LINES):
		var y: float = TEXT_ORIGIN.y + 16.0 * i + top
		if lines[i] != "" and y > -16.0 and y < 240.0:
			_canvas.draw_string(_font, Vector2(TEXT_ORIGIN.x, y + asc), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, TEXT_COLOR)
