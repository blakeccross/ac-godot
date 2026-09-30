class_name EditEndPrompt
extends Control

## "Is this OK?" after writing or drawing (`m_editEndChk_ovl.c`), in 320x240 screen
## units. The question plate pulses until A, then the answer window scales in (0.2 a
## frame) and the red mark picks an answer. Pieces are baked by `menu_ui.py` at the
## origin and placed at the type's `win_data` offsets.
##
## `answered(idx)`: 0 Yes, 1 Rewrite, 2 Throw it out. B answers Rewrite.

signal answered(idx: int)

enum Kind { BOARD, NOTICE, MSCORE, CPACK, ORIGINAL_DESIGN }

## `win_data`: answers, window, mark, text origin, answer origin, question origin.
const WIN_DATA := [
	[2, "ee_a2", Vector2(-45, 43), Vector2(65, -74), Vector2(0, 0)],
	[3, "ee_a3", Vector2(-81, 58), Vector2(60, -71), Vector2(1, -4)],
	[3, "ee_a3", Vector2(-81, 58), Vector2(42, -55), Vector2(1, 15)],
	[3, "ee_a3", Vector2(-81, 58), Vector2(60, -71), Vector2(0, 0)],
	[3, "ee_a3", Vector2(-81, 58), Vector2(60, -71), Vector2(1, -4)],
]
const QUESTION := "Is this OK?"
const ANSWERS := ["Yes", "Rewrite", "Throw it out"]
const QUESTION_COLOR := Color8(80, 80, 230)
const ANSWER_COLOR := Color8(165, 185, 185)
const ANSWER_SELECTED := Color8(100, 130, 245)
const FONT_PX := 16

var kind: int = Kind.BOARD
var selected: int = 0
var _answers_shown: bool = false
var _scale: float = 0.0
var _pulse_step: int = 0
var _font: Font = null
var _tex: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = LetterBoard.load_font()
	for n: String in ["ee_q", "ee_q_c", "ee_a2", "ee_a2_c", "ee_a3", "ee_a3_c"]:
		var path := "res://assets/generated/ui/menu/%s.png" % n
		_tex[n] = load(path) if ResourceLoader.exists(path) else null
	set_process(false)


func open(prompt_kind: int) -> void:
	kind = clampi(prompt_kind, 0, WIN_DATA.size() - 1)
	selected = 0
	_answers_shown = false
	_scale = 0.0
	_pulse_step = 0
	visible = true
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)


func _process(_delta: float) -> void:
	if _answers_shown and _scale < 1.0:
		_scale = minf(_scale + 0.2, 1.0)
	elif not _answers_shown:
		_pulse_step = (_pulse_step + 1) % 30
	queue_redraw()


func handle_key(k: InputEventKey) -> void:
	var data: Array = WIN_DATA[kind]
	match k.keycode:
		KEY_UP, KEY_W:
			if _answers_shown and _scale >= 1.0 and selected > 0:
				selected -= 1
				Audio.play_se(&"cursol")
		KEY_DOWN, KEY_S:
			if _answers_shown and _scale >= 1.0 and selected < int(data[0]) - 1:
				selected += 1
				Audio.play_se(&"cursol")
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not _answers_shown:
				_answers_shown = true
				_scale = 0.0
				Audio.play_se(&"cursol")
			else:
				Audio.play_se(&"cursol")
				answered.emit(selected)
		KEY_ESCAPE, KEY_B, KEY_BACKSPACE:
			Audio.play_se(&"cursol")
			answered.emit(1)


func _draw() -> void:
	var data: Array = WIN_DATA[kind]
	var q: Vector2 = data[4]
	var q_off := Vector2(q.x, -q.y)
	_layer("ee_q", q_off, 1.0, Color.WHITE)
	## `question_alpha`: 0-255 over 15 frames and back, only before A.
	var a := 0.0
	if not _answers_shown:
		a = float(_pulse_step if _pulse_step < 15 else 30 - _pulse_step) / 15.0
	_layer("ee_q_c", q_off, 1.0, Color(1, 1, 1, a))
	var asc := _font.get_ascent(FONT_PX)
	draw_string(_font, Vector2(107 + q.x, 194 - q.y + asc), QUESTION, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX,
		QUESTION_COLOR)
	if not _answers_shown:
		return
	var ans: Vector2 = data[3]
	var pivot := Vector2(160 + ans.x, 120 - ans.y)
	_layer(data[1], Vector2(ans.x, -ans.y), _scale, Color.WHITE)
	if _scale >= 1.0:
		_layer(data[1] + "_c", Vector2(ans.x, -ans.y + 16.0 * selected), 1.0, Color.WHITE)
	var char_off: Vector2 = data[2]
	var pos := pivot + Vector2(char_off.x, -char_off.y) * _scale
	var px := maxi(1, int(round(FONT_PX * _scale)))
	for i in int(data[0]):
		var col := ANSWER_SELECTED if i == selected else ANSWER_COLOR
		draw_string(_font, pos + Vector2(0, _font.get_ascent(px)), ANSWERS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		pos.y += 16.0 * _scale


## A full-screen layer baked at the origin, drawn with the model translated by
## `offset` (screen px) and scaled by `scale_by` about that translated origin
## (`Matrix_translate` then `Matrix_scale`).
func _layer(name: String, offset: Vector2, scale_by: float, tint: Color) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex == null or scale_by <= 0.0:
		return
	var rect := Rect2(Vector2(160, 120) * (1.0 - scale_by) + offset, Vector2(320, 240) * scale_by)
	draw_texture_rect(tex, rect, false, tint)
