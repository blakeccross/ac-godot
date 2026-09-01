class_name MessageWindowChrome
extends Control

## `m_msg` dialogue shell (`con_kaiwa2_modelT` + `con_kaiwaname_modelT`).

const SCREEN_W := 320.0
const SCREEN_H := 240.0
## Decomp defaults (`m_msg_main.c_inc`).
const WINDOW_CENTER := Vector2(160.0, 185.4)
const WINDOW_SIZE := Vector2(245.0, 96.0)
const NAMEPLATE_POS := Vector2(61.0, 64.0)
const NAMEPLATE_SIZE := Vector2(144.0, 32.0)
const BODY_PATH := "res://assets/generated/ui/message/msg_window_body.png"
const NAME_PATH := "res://assets/generated/ui/message/msg_nameplate.png"
const PATCH := 32

const BODY_COLOR := Color(235.0 / 255.0, 1.0, 235.0 / 255.0, 1.0)
const NAME_BG := Color(160.0 / 255.0, 215.0 / 255.0, 30.0 / 255.0, 1.0)
const NAME_TEXT := Color(50.0 / 255.0, 90.0 / 255.0, 0.0, 1.0)
const BODY_TEXT := Color(0.08, 0.12, 0.06, 1.0)
const HINT_TEXT := Color(0.12, 0.18, 0.45, 1.0)

@onready var _name_bg: NinePatchRect = %NamePlate
@onready var _body_bg: NinePatchRect = %BodyPlate
@onready var _name_fill: ColorRect = %NameFill
@onready var _body_fill: ColorRect = %BodyFill
@onready var _name: Label = %NameLabel
@onready var _body: Label = %BodyLabel
@onready var _hint: Label = %HintLabel
@onready var _choices: VBoxContainer = %ChoiceList


func _ready() -> void:
	_apply_textures()
	_layout_decomp()


func set_speaker(name: String) -> void:
	_name.text = name
	_name.visible = name != ""
	_name_bg.visible = name != ""


func set_body(text: String) -> void:
	_body.text = text


func set_hint(text: String) -> void:
	_hint.text = text


func clear_choices() -> void:
	for child: Node in _choices.get_children():
		child.queue_free()


func choice_container() -> VBoxContainer:
	return _choices


func _apply_textures() -> void:
	var has_body := ResourceLoader.exists(BODY_PATH)
	var has_name := ResourceLoader.exists(NAME_PATH)
	if has_body:
		var body_tex: Texture2D = load(BODY_PATH) as Texture2D
		if body_tex != null:
			_body_bg.texture = body_tex
			_body_bg.patch_margin_left = PATCH
			_body_bg.patch_margin_top = PATCH
			_body_bg.patch_margin_right = PATCH
			_body_bg.patch_margin_bottom = PATCH
			_body_fill.visible = false
	else:
		_body_bg.visible = false
		_body_fill.visible = true
		_body_fill.color = BODY_COLOR
	if has_name:
		var name_tex: Texture2D = load(NAME_PATH) as Texture2D
		if name_tex != null:
			_name_bg.texture = name_tex
			_name_bg.patch_margin_left = 16
			_name_bg.patch_margin_top = 8
			_name_bg.patch_margin_right = 16
			_name_bg.patch_margin_bottom = 8
			_name_fill.visible = false
	else:
		_name_bg.visible = false
		_name_fill.visible = true
		_name_fill.color = NAME_BG
	_name.add_theme_color_override("font_color", NAME_TEXT)
	_body.add_theme_color_override("font_color", BODY_TEXT)
	_hint.add_theme_color_override("font_color", HINT_TEXT)


func _layout_decomp() -> void:
	var scale := minf(size.x / SCREEN_W, size.y / SCREEN_H)
	var win_size := WINDOW_SIZE * scale
	var win_pos := Vector2(
		(WINDOW_CENTER.x - WINDOW_SIZE.x * 0.5) * scale,
		(WINDOW_CENTER.y - WINDOW_SIZE.y * 0.5) * scale
	)
	_body_bg.position = win_pos
	_body_bg.size = win_size
	_body_fill.position = win_pos
	_body_fill.size = win_size
	var name_pos := NAMEPLATE_POS * scale
	_name_bg.position = name_pos
	_name_bg.size = NAMEPLATE_SIZE * scale
	_name_fill.position = name_pos
	_name_fill.size = NAMEPLATE_SIZE * scale
	var margin := Vector2(18.0, 14.0) * scale
	_body.position = win_pos + margin
	_body.size = win_size - margin * 2.0 - Vector2(0.0, 22.0 * scale)
	_name.position = name_pos + Vector2(10.0, 4.0) * scale
	_name.size = _name_bg.size - Vector2(20.0, 8.0) * scale
	_hint.position = win_pos + Vector2(win_size.x - 96.0 * scale, win_size.y - 26.0 * scale)
	_hint.size = Vector2(88.0 * scale, 20.0 * scale)
	_choices.position = _body.position + Vector2(0.0, _body.size.y * 0.35)
	_choices.size = Vector2(_body.size.x, _body.size.y * 0.55)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_decomp()
