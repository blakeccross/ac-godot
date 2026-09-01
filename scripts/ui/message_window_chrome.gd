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
const TILE_W1 := "res://assets/generated/ui/message/msg_kaiwa_w1.png"
const TILE_W2 := "res://assets/generated/ui/message/msg_kaiwa_w2.png"
const TILE_W3 := "res://assets/generated/ui/message/msg_kaiwa_w3.png"
const NAME_PATH := "res://assets/generated/ui/message/msg_nameplate.png"
## Texel border thickness at 320×240 (`con_kaiwa2` corner / band sizes).
const BORDER_X := 32.0
const BORDER_Y := 64.0

const BODY_COLOR := Color(235.0 / 255.0, 1.0, 235.0 / 255.0, 1.0)
const NAME_BG := Color(160.0 / 255.0, 215.0 / 255.0, 30.0 / 255.0, 1.0)
const NAME_TEXT := Color(50.0 / 255.0, 90.0 / 255.0, 0.0, 1.0)
const BODY_TEXT := Color(0.08, 0.12, 0.06, 1.0)
const HINT_TEXT := Color(0.12, 0.18, 0.45, 1.0)

@onready var _name_fill: ColorRect = %NameFill
@onready var _body_fill: ColorRect = %BodyFill
@onready var _name_plate: TextureRect = %NamePlate
@onready var _name: Label = %NameLabel
@onready var _body: Label = %BodyLabel
@onready var _hint: Label = %HintLabel
@onready var _choices: VBoxContainer = %ChoiceList
@onready var _border_root: Control = %BorderRoot

var _corner_tl: TextureRect
var _corner_tr: TextureRect
var _corner_bl: TextureRect
var _corner_br: TextureRect
var _edge_top: TextureRect
var _edge_bottom: TextureRect
var _edge_left: TextureRect
var _edge_right: TextureRect
var _use_tiles: bool = false


func _ready() -> void:
	_build_border_tiles()
	_apply_textures()
	_layout_decomp()


func set_speaker(name: String) -> void:
	if not is_node_ready():
		return
	var show := name != ""
	_name.text = name
	_name.visible = show
	_name_plate.visible = show and _use_tiles
	_name_fill.visible = show and not _use_tiles


func set_body(text: String) -> void:
	_body.text = text


func set_hint(text: String) -> void:
	_hint.text = text


func clear_choices() -> void:
	for child: Node in _choices.get_children():
		child.queue_free()


func choice_container() -> VBoxContainer:
	return _choices


func _build_border_tiles() -> void:
	_corner_tl = _make_tile("CornerTL")
	_corner_tr = _make_tile("CornerTR")
	_corner_bl = _make_tile("CornerBL")
	_corner_br = _make_tile("CornerBR")
	_edge_top = _make_tile("EdgeTop")
	_edge_bottom = _make_tile("EdgeBottom")
	_edge_left = _make_tile("EdgeLeft")
	_edge_right = _make_tile("EdgeRight")


func _make_tile(node_name: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	_border_root.add_child(rect)
	return rect


func _apply_textures() -> void:
	var tex_w1: Texture2D = _load_tile(TILE_W1)
	var tex_w2: Texture2D = _load_tile(TILE_W2)
	var tex_w3: Texture2D = _load_tile(TILE_W3)
	_use_tiles = tex_w1 != null and tex_w2 != null and tex_w3 != null
	_body_fill.visible = true
	_body_fill.color = BODY_COLOR
	_set_tile(_corner_tl, tex_w1)
	_set_tile(_corner_tr, tex_w1, true, false)
	_set_tile(_corner_bl, tex_w1, false, true)
	_set_tile(_corner_br, tex_w1, true, true)
	_set_tile(_edge_top, tex_w3)
	_set_tile(_edge_bottom, tex_w3, false, true)
	_set_tile(_edge_left, tex_w2)
	_set_tile(_edge_right, tex_w2, true, false)
	for node: CanvasItem in [
		_corner_tl, _corner_tr, _corner_bl, _corner_br,
		_edge_top, _edge_bottom, _edge_left, _edge_right,
	]:
		node.visible = _use_tiles
	var name_tex: Texture2D = _load_tile(NAME_PATH)
	if name_tex != null:
		_name_plate.texture = name_tex
		_name_plate.visible = false
		_name_fill.visible = false
	else:
		_name_plate.visible = false
		_name_fill.color = NAME_BG
	_name.add_theme_color_override("font_color", NAME_TEXT)
	_body.add_theme_color_override("font_color", BODY_TEXT)
	_hint.add_theme_color_override("font_color", HINT_TEXT)


func _load_tile(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _set_tile(rect: TextureRect, tex: Texture2D, flip_h: bool = false, flip_v: bool = false) -> void:
	rect.texture = tex
	rect.flip_h = flip_h
	rect.flip_v = flip_v


func _layout_decomp() -> void:
	if not is_node_ready():
		return
	var ui_scale := minf(size.x / SCREEN_W, size.y / SCREEN_H)
	var win_size := WINDOW_SIZE * ui_scale
	var win_pos := Vector2(
		(WINDOW_CENTER.x - WINDOW_SIZE.x * 0.5) * ui_scale,
		(WINDOW_CENTER.y - WINDOW_SIZE.y * 0.5) * ui_scale
	)
	var bx := BORDER_X * ui_scale
	var by := BORDER_Y * ui_scale
	_body_fill.position = win_pos
	_body_fill.size = win_size
	if _use_tiles:
		_corner_tl.position = win_pos
		_corner_tl.size = Vector2(bx, by)
		_corner_tr.position = win_pos + Vector2(win_size.x - bx, 0.0)
		_corner_tr.size = Vector2(bx, by)
		_corner_bl.position = win_pos + Vector2(0.0, win_size.y - by)
		_corner_bl.size = Vector2(bx, by)
		_corner_br.position = win_pos + Vector2(win_size.x - bx, win_size.y - by)
		_corner_br.size = Vector2(bx, by)
		_edge_top.position = win_pos + Vector2(bx, 0.0)
		_edge_top.size = Vector2(win_size.x - bx * 2.0, by)
		_edge_bottom.position = win_pos + Vector2(bx, win_size.y - by)
		_edge_bottom.size = Vector2(win_size.x - bx * 2.0, by)
		_edge_left.position = win_pos + Vector2(0.0, by)
		_edge_left.size = Vector2(bx, win_size.y - by * 2.0)
		_edge_right.position = win_pos + Vector2(win_size.x - bx, by)
		_edge_right.size = Vector2(bx, win_size.y - by * 2.0)
	var name_pos := NAMEPLATE_POS * ui_scale
	var name_size := NAMEPLATE_SIZE * ui_scale
	_name_plate.position = name_pos
	_name_plate.size = name_size
	_name_fill.position = name_pos
	_name_fill.size = name_size
	var margin := Vector2(18.0, 14.0) * ui_scale
	_body.position = win_pos + margin
	_body.size = win_size - margin * 2.0 - Vector2(0.0, 22.0 * ui_scale)
	_name.position = name_pos + Vector2(10.0, 4.0) * ui_scale
	_name.size = name_size - Vector2(20.0, 8.0) * ui_scale
	_hint.position = win_pos + Vector2(win_size.x - 96.0 * ui_scale, win_size.y - 26.0 * ui_scale)
	_hint.size = Vector2(88.0 * ui_scale, 20.0 * ui_scale)
	_choices.position = _body.position + Vector2(0.0, _body.size.y * 0.35)
	_choices.size = Vector2(_body.size.x, _body.size.y * 0.55)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_decomp()
