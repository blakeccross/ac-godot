class_name NoticeBoardOverlay
extends CanvasLayer

## The community board's posts (`m_notice_ovl.c`), in 320x240 screen units. It opens on the
## latest post; ←/→ (C-left / C-right) turn one page, ↓ jumps to the first and ↑ to the
## latest (several pages turn one after another, at most three steps), Space / Enter (A)
## starts a new post and Escape / Backspace (B / START) leaves. Each page is the pinned
## sheet (`kei_win`) with "entry NN" and the post's date in blue and the body in dark red;
## the key hints (`kei_hyouji`) and page arrows sit below.
##
## A new post slides a blank page in from the right while the hints drop away, then the
## keyboard writes straight onto it (`LetterWriterOverlay.open_board`, 6 lines, 192
## characters) and "Is this OK?" (`mEE_TYPE_NOTICE`) posts it, rewrites, or throws it out
## (the page slides back to the latest post). Posting finishes Nook's first-job chore.

signal closed(posted: bool)

const TEX_DIR := "res://assets/generated/ui/menu/%s.png"
const PAGE_W := 320.0
const MAX_STEPS := 3
const STEP_PX := 74.0
const EASE := 0.4
const MIN_STEP := 2.5
const KEYS_HIDDEN := -100.0
const WRITE_LINES := 6
const BODY_COLOR := Color8(30, 0, 0)
const INFO_COLOR := Color8(0, 0, 255)
const INFO_SCALE := 0.75
const FONT_PX := 16
const BODY_ORIGIN := Vector2(63.0, 63.0)
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December"]

enum Mode { READ, MOVE, TO_WRITE, WRITING, TO_READ }

var now_page: int = 0
var disp_page: int = 0
var page_count: int = 0
var mode: int = Mode.READ
var page_x: float = 0.0
var keys_y: float = 0.0
var _move_time: int = 0
var _new_post: Dictionary = {}
var _posted: bool = false
var _open: bool = false
var _accum: float = 0.0
var _tex: Dictionary = {}
var _font: Font = null
var _slide: MenuSlide = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas


func _ready() -> void:
	layer = 21
	add_to_group("notice_ui")
	add_to_group("shop_ui")
	_root.visible = false
	_font = LetterBoard.load_font()
	for name: String in ["nt_win", "nt_keys", "nt_next", "nt_prev", "nt_st1"]:
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


func board() -> NoticeBoard:
	return Game.notice_board if Game != null else null


## `mNT_notice_ovl_init`: from the top, on the latest post.
func open() -> void:
	if _open or board() == null:
		return
	Game.update_notice_board()
	page_count = board().count()
	now_page = maxi(page_count - 1, 0)
	disp_page = now_page
	mode = Mode.READ
	page_x = 0.0
	keys_y = 0.0
	_move_time = 0
	_posted = false
	_open = true
	_root.visible = true
	set_process(true)
	set_process_unhandled_input(true)
	Audio.play_se(&"17c")
	_slide.slide_in(MenuSlide.Dir.IN_TOP)
	_canvas.queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	Audio.play_se(&"17d")
	_slide.slide_out(MenuSlide.Dir.OUT_TOP, _on_slid_out)
	closed.emit(_posted)


func _on_slid_out() -> void:
	if _open:
		return
	_root.visible = false
	set_process(false)


func _process(delta: float) -> void:
	_accum += delta * DecompTime.TICK_HZ
	var steps := 0
	while _accum >= 1.0 and steps < 8:
		_accum -= 1.0
		steps += 1
		_tick()
	if steps > 0:
		_canvas.queue_redraw()


## `add_calc`: ease `value` toward `target` by `fraction`, the step clamped to
## [`min_step`, `max_step`]; returns what is left.
static func add_calc(value: float, target: float, fraction: float, max_step: float, min_step: float) -> Vector2:
	var diff: float = target - value
	var step: float = clampf(diff * fraction, -max_step, max_step)
	if absf(step) < min_step:
		step = clampf(diff, -min_step, min_step)
	value += step
	return Vector2(value, target - value)


func _tick() -> void:
	match mode:
		Mode.MOVE:
			_tick_move()
		Mode.TO_WRITE:
			var p := add_calc(page_x, 0.0, EASE, STEP_PX, MIN_STEP)
			var k := add_calc(keys_y, KEYS_HIDDEN, EASE, STEP_PX, MIN_STEP)
			page_x = p.x
			keys_y = k.x
			if absf(p.y) < 0.1 and absf(k.y) < 0.1:
				page_x = 0.0
				keys_y = KEYS_HIDDEN
				disp_page = now_page
				mode = Mode.WRITING
				_open_writer()
		Mode.TO_READ:
			var p := add_calc(page_x, 0.0, EASE, STEP_PX, MIN_STEP)
			var k := add_calc(keys_y, 0.0, EASE, STEP_PX, MIN_STEP)
			page_x = p.x
			keys_y = k.x
			if absf(p.y) < 0.1 and absf(k.y) < 0.1:
				page_x = 0.0
				keys_y = 0.0
				disp_page = now_page
				mode = Mode.READ


## `mNT_Play_page_move`: one page eases in; several slide 74 a frame each.
func _tick_move() -> void:
	var done := false
	var forward := page_x > 0.0
	if _move_time == 1:
		var p := add_calc(page_x, 0.0, EASE, STEP_PX, MIN_STEP)
		page_x = p.x
		done = absf(p.y) < 0.1
	elif forward:
		page_x -= STEP_PX
		done = page_x <= 0.0
	else:
		page_x += STEP_PX
		done = page_x >= 0.0
	if not done:
		return
	_move_time -= 1
	disp_page = now_page
	if _move_time == 0:
		page_x = 0.0
		mode = Mode.READ
		return
	Audio.play_se(&"5f")
	if forward:
		page_x += PAGE_W
		now_page += (page_count - now_page - 1) / _move_time
	else:
		page_x -= PAGE_W
		now_page -= now_page / _move_time


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if mode != Mode.READ or _slide.is_moving():
		return
	var k := event as InputEventKey
	var move := 0
	match k.keycode:
		KEY_LEFT, KEY_A:
			if now_page != 0:
				move = -1
		KEY_RIGHT, KEY_D:
			if now_page < page_count - 1:
				move = 1
		KEY_DOWN, KEY_S:
			if now_page != 0:
				move = -now_page
		KEY_UP, KEY_W:
			if now_page < page_count - 1:
				move = page_count - now_page - 1
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				_start_write()
		KEY_ESCAPE, KEY_BACKSPACE, KEY_B:
			if not k.echo:
				close()
	if move != 0:
		turn(move)


## `mNT_Play_page_read`'s page move.
func turn(move: int) -> void:
	_move_time = mini(absi(move), MAX_STEPS)
	now_page += move / _move_time
	page_x = PAGE_W if move > 0 else -PAGE_W
	mode = Mode.MOVE
	Audio.play_se(&"5f")


## A: a blank page dated now comes in from the right.
func _start_write() -> void:
	mode = Mode.TO_WRITE
	now_page = NoticeBoard.POST_COUNT
	page_x = PAGE_W
	_new_post = {"text": "", "year": Clock.year, "month": Clock.month, "day": Clock.day, "hour": Clock.hour,
		"minute": Clock.minute}
	Audio.play_se(&"5f")


func _open_writer() -> void:
	var writer: Node = get_tree().get_first_node_in_group("letter_writer_ui") if get_tree() != null else null
	if writer == null or not writer.has_method("open_board"):
		_back_to_read()
		return
	var style := {"text": BODY_ORIGIN, "color": BODY_COLOR, "frame": false, "prompt": EditEndPrompt.Kind.NOTICE}
	writer.call("open_board", "", WRITE_LINES, NoticeBoard.BODY_LEN, _on_written, 0, style)
	if writer.has_signal("closed") and not writer.is_connected("closed", _on_writer_closed):
		writer.connect("closed", _on_writer_closed, CONNECT_ONE_SHOT)


## Yes on "Is this OK?": the post goes up and the board slides away.
func _on_written(text: String) -> void:
	if text.strip_edges() == "":
		return
	_new_post["text"] = text.substr(0, NoticeBoard.BODY_LEN)
	board().write(_new_post)
	_posted = true
	if Game != null and Game.first_job != null and Game.first_job.kind == FirstJob.Kind.POST_NOTICE \
			and Game.first_job.progress == FirstJob.PROGRESS_ACTIVE:
		Game.first_job.mark_notice_posted()


func _on_writer_closed() -> void:
	if _posted:
		close()
	else:
		_back_to_read()


## "Throw it out": back to the latest post from the left.
func _back_to_read() -> void:
	page_count = board().count()
	now_page = maxi(page_count - 1, 0)
	page_x = -PAGE_W
	mode = Mode.TO_READ


func _blit(name: String, offset: Vector2) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex != null:
		_canvas.draw_texture_rect(tex, Rect2(Vector2(offset.x, -offset.y), Vector2(320, 240)), false)


func _draw_canvas() -> void:
	if not _root.visible:
		return
	_draw_page(page_x, now_page)
	if disp_page != now_page:
		_draw_page(page_x + (-PAGE_W if now_page > disp_page else PAGE_W), disp_page)
	if mode == Mode.WRITING:
		return
	_blit("nt_keys", Vector2(0, keys_y))
	if mode == Mode.READ:
		if now_page < page_count - 1:
			_blit("nt_next", Vector2(0, keys_y))
		if now_page != 0:
			_blit("nt_prev", Vector2(0, keys_y))
	_blit("nt_st1", Vector2(0, keys_y))


## `mNT_set_page_dl`: the sheet, "entry NN", the date and the body.
func _draw_page(x: float, page: int) -> void:
	_blit("nt_win", Vector2(x, 0))
	if _font == null or board() == null:
		return
	var post: Dictionary
	var entry: int
	if page >= NoticeBoard.POST_COUNT:
		post = _new_post
		entry = mini(page_count + 1, NoticeBoard.POST_COUNT)
	elif page < board().count():
		post = board().posts[page]
		entry = page + 1
	else:
		return
	var px := int(round(FONT_PX * INFO_SCALE))
	var asc := _font.get_ascent(px)
	_canvas.draw_string(_font, Vector2(x + 63.0, 46.0 + asc), "entry %2d" % entry, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
		INFO_COLOR)
	var month: int = int(post.get("month", 1))
	var month_name: String = MONTHS[month - 1] if month >= 1 and month <= 12 else "???"
	var mw: float = _font.get_string_size(month_name, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_canvas.draw_string(_font, Vector2(x + 213.0 - mw, 46.0 + asc), month_name, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
		INFO_COLOR)
	_canvas.draw_string(_font, Vector2(x + 215.0, 46.0 + asc), "%2d" % int(post.get("day", 1)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, px, INFO_COLOR)
	_canvas.draw_string(_font, Vector2(x + 227.0, 46.0 + asc), ",", HORIZONTAL_ALIGNMENT_LEFT, -1, px, INFO_COLOR)
	_canvas.draw_string(_font, Vector2(x + 233.0, 46.0 + asc), "%04d" % int(post.get("year", 0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, px, INFO_COLOR)
	if mode == Mode.WRITING and page >= NoticeBoard.POST_COUNT:
		return
	var body_asc := _font.get_ascent(FONT_PX)
	var lines: PackedStringArray = str(post.get("text", "")).split("\n")
	for i: int in mini(lines.size(), WRITE_LINES):
		_canvas.draw_string(_font, Vector2(x, 0) + BODY_ORIGIN + Vector2(0, 16 * i + body_asc), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, BODY_COLOR)
