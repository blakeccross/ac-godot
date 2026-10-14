class_name TownTuneOverlay
extends CanvasLayer

## The town tune editor at the tune board (`m_mscore_ovl.c`), in 320x240 screen units.
## Sixteen frogs in two rows of eight, each one step of the tune: ←/→ (A / B, C-left /
## C-right) move the cursor, ↑/↓ (C-up / C-down) change the step (rest, tie, G low … E,
## random) and sound it, X plays the tune (the playing frog opens its mouth and the stick
## follows), Y asks "Are you sure?" and erases every step to a rest, START or A on END asks
## "Is this OK?" (Yes saves, Rewrite goes back, Throw it out restores the old tune), and R
## (e-Reader) leaves without saving. It plays the saved tune once as it opens.
##
## Pieces are baked by `menu_ui.py` into `ui/mscore/`: the window in place, the frogs,
## letters, stick and prompt at the origin.

signal closed(saved: bool)

const TEX_DIR := "res://assets/generated/ui/mscore/%s.png"
const END := 16
const OPEN_WAIT := 10
const PULSE_FRAMES := 18
## `note_moji` frame per step value and its letter / y offset.
const NOTE_FRAME: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 1, 2]
const NOTE_MOJI: Array[String] = ["g", "a", "b", "c", "d", "e", "f", "g", "a", "b", "c", "d", "e", "q", "z", "onpu8"]
const NOTE_OFS_Y: Array[float] = [-29, -29, -29, -23, -23, -23, -23, -23, -23, -23, -16, -16, -16, -20, -29, -29]
## `note_frame[].offset`: where the letter sits on each frame.
const FRAME_MOJI_OFS: Array[Vector2] = [Vector2(0, 0), Vector2(-1, 20), Vector2(1, 1), Vector2(-1, 5)]
const NOTE_BOUNDS := Rect2(-12.0, 22.0, 24.0, 44.0)
const MARK_BOUNDS := Rect2(-8.0, 8.0, 16.0, 16.0)
const SEN_BOUNDS := Rect2(-70.0, 60.0, 140.0, 120.0)
const LETTER_ON := Color(1, 0, 0)
const LETTER_OFF := Color(0, 0, 1)
const SURE_TITLE := "Are you sure?"
const SURE_ANSWERS := ["Yes", "No"]
const SURE_TITLE_COLOR := Color8(255, 60, 60)
const SURE_ON := Color8(70, 70, 225)
const SURE_OFF := Color8(140, 160, 205)
const FONT_PX := 16

enum Proc { PLAY, WAIT, OBEY }

var notes: PackedByteArray = PackedByteArray()
var cursor: int = -1
var _original: PackedByteArray = PackedByteArray()
var _open: bool = false
var _proc: int = Proc.PLAY
var _wait_timer: int = 0
var _anim_frame: int = 0
var _sure_idx: int = 0
var _sure_scale: float = 0.0
var _sure_dir: int = 0
var _accum: float = 0.0
var _tex: Dictionary = {}
var _font: Font = null
var _slide: MenuSlide = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas
@onready var _prompt: EditEndPrompt = $Root/Screen/Prompt


func _ready() -> void:
	layer = 21
	add_to_group("town_tune_ui")
	add_to_group("shop_ui")
	_root.visible = false
	_font = LetterBoard.load_font()
	for name: String in ["ms_win", "ms_owari_on", "ms_owari_off", "ms_bou", "ms_sen", "ms_sen_cursor"]:
		_tex[name] = _load(name)
	for n: int in 16:
		for playing: int in 2:
			_tex["ms_note%d_%d" % [n, playing]] = _load("ms_note%d_%d" % [n, playing])
	for moji: String in NOTE_MOJI:
		_tex["ms_moji_" + moji] = _load("ms_moji_" + moji)
	_canvas.draw.connect(_draw_canvas)
	_prompt.answered.connect(_on_prompt_answer)
	_slide = MenuSlide.attach(self)
	_root.resized.connect(_fit_screen)
	_fit_screen()
	set_process(false)
	set_process_unhandled_input(false)


func _load(name: String) -> Texture2D:
	var path := TEX_DIR % name
	return load(path) if ResourceLoader.exists(path) else null


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func is_open() -> bool:
	return _open


## `mMS_mscore_ovl_init`: slides in from the top, then plays the saved tune.
func open() -> void:
	if _open:
		return
	notes = TownTune.sanitize(Game.town_tune) if Game != null else TownTune.default_notes()
	_original = notes.duplicate()
	cursor = -1
	_proc = Proc.PLAY
	_wait_timer = OPEN_WAIT
	_anim_frame = 0
	_accum = 0.0
	_open = true
	_root.visible = true
	_prompt.close()
	set_process(true)
	set_process_unhandled_input(true)
	_slide.slide_in(MenuSlide.Dir.IN_TOP)
	_canvas.queue_redraw()


func close(saved: bool = false) -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	Audio.stop_melody()
	_slide.slide_out(MenuSlide.Dir.OUT_TOP, _on_slid_out)
	closed.emit(saved)


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


func _tick() -> void:
	if _slide.is_moving():
		return
	match _proc:
		Proc.PLAY:
			if _wait_timer > 0:
				_wait_timer -= 1
				if _wait_timer == 1:
					Audio.play_melody(notes)
				return
			if cursor == -1:
				cursor = 0
			_anim_frame = (_anim_frame + 1) % PULSE_FRAMES
		Proc.OBEY:
			if _sure_dir == 0:
				_sure_scale = minf(_sure_scale + 0.25, 1.0)
			elif _sure_dir == 1:
				_sure_scale -= 0.25
				if _sure_scale < 0.0:
					_sure_scale = 0.0
					_proc = Proc.PLAY
			_anim_frame = (_anim_frame + 1) % PULSE_FRAMES


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()
	if _slide.is_moving():
		return
	match _proc:
		Proc.WAIT:
			if not k.echo:
				_prompt.handle_key(k)
		Proc.OBEY:
			_obey_input(k)
		Proc.PLAY:
			if _wait_timer == 0 and Audio.melody_step() < 0:
				_play_input(k)


## `mMS_move_Play`.
func _play_input(k: InputEventKey) -> void:
	var before := cursor
	match k.keycode:
		KEY_X:
			Audio.play_melody(notes)
		KEY_Y, KEY_Z:
			_proc = Proc.OBEY
			_sure_idx = 0
			_sure_scale = 0.0
			_sure_dir = 0
			Audio.play_se(&"33")
		KEY_R:
			Audio.play_se(&"menu_exit")
			close(false)
			return
		KEY_ESCAPE:
			_open_prompt()
			return
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if cursor == END:
				_open_prompt()
				return
			cursor += 1
		KEY_RIGHT, KEY_D:
			if cursor != END:
				cursor += 1
		KEY_BACKSPACE, KEY_B, KEY_LEFT, KEY_A:
			if cursor != 0:
				cursor -= 1
		KEY_DOWN, KEY_S:
			if cursor != END:
				var was: int = notes[cursor]
				notes[cursor] = TownTune.step_down(was)
				if was != 0 and notes[cursor] != was:
					Audio.play_se(TownTune.note_se(notes[cursor]))
		KEY_UP, KEY_W:
			if cursor != END:
				var was: int = notes[cursor]
				notes[cursor] = TownTune.step_up(was)
				if notes[cursor] != was:
					Audio.play_se(TownTune.note_se(notes[cursor]))
	if cursor != before:
		_anim_frame = 0
		if cursor != END:
			Audio.play_se(TownTune.note_se(notes[cursor]))
		else:
			Audio.play_se(&"cursol")
	_canvas.queue_redraw()


## `mMS_move_Obey`: A on Yes rests every step; B or No backs out.
func _obey_input(k: InputEventKey) -> void:
	if _sure_dir != 0 or _sure_scale < 1.0:
		return
	match k.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if _sure_idx == 0:
				for i: int in TownTune.LENGTH:
					notes[i] = TownTune.REST
				Audio.play_se(&"114")
			else:
				Audio.play_se(&"3")
			_sure_dir = 1
		KEY_BACKSPACE, KEY_B, KEY_ESCAPE:
			Audio.play_se(&"3")
			_sure_dir = 1
		KEY_DOWN, KEY_S:
			if _sure_idx == 0:
				_sure_idx = 1
				Audio.play_se(&"cursol")
		KEY_UP, KEY_W:
			if _sure_idx == 1:
				_sure_idx = 0
				Audio.play_se(&"cursol")


func _open_prompt() -> void:
	_proc = Proc.WAIT
	_anim_frame = 0
	Audio.play_se(&"menu_exit")
	_prompt.open(EditEndPrompt.Kind.MSCORE)


## `mMS_move_Wait`: 0 saves, 1 goes back to the first step, 2 keeps the old tune.
func _on_prompt_answer(idx: int) -> void:
	_prompt.close()
	match idx:
		0:
			if Game != null:
				Game.town_tune = notes.duplicate()
			close(true)
		1:
			_anim_frame = 0
			cursor = 0
			_proc = Proc.PLAY
		_:
			notes = _original.duplicate()
			close(false)


## UI units (origin at the screen centre, y up) to the 320x240 canvas.
static func to_screen(p: Vector2) -> Vector2:
	return Vector2(160.0 + p.x, 120.0 - p.y)


func _blit(name: String, bounds: Rect2, at: Vector2, scale_by: Vector2 = Vector2.ONE, tint: Color = Color.WHITE) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex == null:
		return
	var top_left := to_screen(at) + Vector2(bounds.position.x, -bounds.position.y) * scale_by
	_canvas.draw_texture_rect(tex, Rect2(top_left, bounds.size * scale_by), false, tint)


func _draw_canvas() -> void:
	if not _open and not _root.visible:
		return
	var screen := Rect2(-160.0, 120.0, 320.0, 240.0)
	_blit("ms_win", screen, Vector2.ZERO)
	_blit("ms_owari_on" if cursor == END else "ms_owari_off", screen, Vector2.ZERO)
	var inst: int = Audio.melody_step()
	var cur: int = -1 if inst >= 0 else cursor
	var play_idx: int = inst if inst >= 0 else maxi(cursor, 0)
	if cur != END:
		var stick := Vector2(-91.0 + 21.2 * (play_idx % 8) + (0.0 if play_idx < 8 else 19.0),
			20.0 + (0.0 if play_idx < 8 else -50.0))
		_blit("ms_bou", MARK_BOUNDS, stick, Vector2.ONE, LETTER_OFF)
	var playing: int = inst
	var pulse: float = 1.0 + (1.0 - cos(float(_anim_frame) * PI / 9.0)) * 0.075
	for pass_no: int in 2:
		var base := Vector2(-91.0, 64.0)
		for i: int in TownTune.LENGTH:
			var n: int = notes[i]
			var s := Vector2.ONE * (pulse if i == cur else 1.0)
			if pass_no == 0:
				_blit("ms_note%d_%d" % [n, 1 if i == playing else 0], NOTE_BOUNDS, base + Vector2(0, NOTE_OFS_Y[n]), s)
			elif i != playing:
				var at: Vector2 = base + FRAME_MOJI_OFS[NOTE_FRAME[n]] + Vector2(0, NOTE_OFS_Y[n])
				_blit("ms_moji_" + NOTE_MOJI[n], MARK_BOUNDS, at, s, LETTER_ON if i == cur else LETTER_OFF)
			if i == 7:
				base = Vector2(-71.0, base.y - 50.0)
			else:
				base.x += 21.0
	if _proc == Proc.OBEY and _sure_scale > 0.0:
		_draw_sure()


## The "Are you sure?" window over the tune (`mMS_set_dl`, OBEY).
func _draw_sure() -> void:
	var s := _sure_scale
	var origin := Vector2(-17.0, -65.0)
	_blit("ms_sen", SEN_BOUNDS, origin + Vector2(16.0, 35.0) * s, Vector2(0.897059, 0.708333) * s)
	_blit("ms_sen_cursor", MARK_BOUNDS, origin + Vector2(-26.0, 51.0 - (_sure_idx + 1) * 16.0) * s, Vector2.ONE * s)
	if _font == null:
		return
	var px: int = maxi(1, int(round(FONT_PX * 0.875 * s)))
	var pos := Vector2(160.0 + (-17.0 - 22.0 * s), 120.0 - (-65.0 + 59.0 * s))
	_canvas.draw_string(_font, pos + Vector2(0, _font.get_ascent(px)), SURE_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
		SURE_TITLE_COLOR)
	for i: int in SURE_ANSWERS.size():
		pos.y += 16.0 * s
		_canvas.draw_string(_font, pos + Vector2(0, _font.get_ascent(px)), SURE_ANSWERS[i], HORIZONTAL_ALIGNMENT_LEFT,
			-1, px, SURE_ON if i == _sure_idx else SURE_OFF)
