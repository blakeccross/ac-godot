@tool
class_name MessageWindowChrome
extends Control

## `m_msg` talk window. Cloud/nameplate silhouettes are baked from `con_kaiwa2_modelT` /
## `con_kaiwaname_modelT` at native size — the scalloped border cannot be nine-patched.

const SCREEN_W := 320.0
const SCREEN_H := 240.0
## Baked `con_kaiwa2` bounds at `mMsg_init` placement (center 160, 185.4).
const WINDOW_SIZE := Vector2(261.0, 105.0)
const WINDOW_CENTER_X := 167.5
const WINDOW_BOTTOM_V := 238.0
const MAX_BODY_LINES := 4

const CLOUD_TEX_PATHS: Array[String] = [
	"res://assets/generated/ui/message/msg_window_cloud.png",
	"res://assets/custom/ui/message/msg_window_cloud.png",
]
const NAMEPLATE_TEX_PATHS: Array[String] = [
	"res://assets/generated/ui/message/msg_nameplate_cloud.png",
	"res://assets/custom/ui/message/msg_nameplate_cloud.png",
]
const MIN_NAMEPLATE_SIZE := Vector2(99.0, 29.0)

## Sub-rects as fractions of the cloud rect (GC frame). Negative V is above the cloud top.
const NAME_UV := Rect2(0.041, -0.108, 0.362, 0.271)
const BODY_UV := Vector2(0.0828, 0.2059)
const BODY_LINE_PITCH_V := 0.1568
const ARROW_UV := Rect2(0.8724, 0.6928, 0.0299, 0.0752)
const CHOICE_RIGHT_U := 0.95
const CHOICE_TOP_V := 0.24
const CHOICE_BOTTOM_V := 0.92
const CHOICE_FONT_PX := 14.0

const NAME_TEXT := Color(50.0 / 255.0, 90.0 / 255.0, 0.0, 1.0)
const NAME_OUTLINE := Color(0.0, 23.0 / 255.0, 0.0, 1.0)
const BODY_TEXT := Color(50.0 / 255.0, 60.0 / 255.0, 50.0 / 255.0, 1.0)
const BODY_OUTLINE := Color(16.0 / 255.0, 41.0 / 255.0, 16.0 / 255.0, 1.0)
const NAME_BG := Color(137.0 / 255.0, 235.0 / 255.0, 10.0 / 255.0, 1.0)
const CLOUD_RIM := Color(206.0 / 255.0, 226.0 / 255.0, 198.0 / 255.0, 0.95)

const BODY_FONT_PX := 14.0
const NAME_FONT_PX := 17.0
const GLYPH_CONDENSE := -0.10
const SPACE_RELIEF := 1.6
const OUTLINE_PX := 2.0

@onready var _cloud: TextureRect = %Cloud
@onready var _name_plate: TextureRect = %NamePlate
@onready var _name: Label = %NameLabel
@onready var _body: Label = %BodyLabel
@onready var _arrow: MessageContinueArrow = %ContinueArrow
@onready var _choices: VBoxContainer = %ChoiceList

@export var editor_preview: bool = true:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_editor_preview()

var _ui_scale: float = 1.0


func _ready() -> void:
	_apply_textures()
	_apply_text_theme()
	_layout()
	if Engine.is_editor_hint():
		_apply_editor_preview()


static func cloud_rect() -> Rect2:
	return Rect2(Vector2(WINDOW_CENTER_X - WINDOW_SIZE.x * 0.5, WINDOW_BOTTOM_V - WINDOW_SIZE.y), WINDOW_SIZE)


func set_speaker(speaker: String) -> void:
	if not is_node_ready():
		return
	var show := speaker != ""
	_name.text = speaker
	_name_plate.visible = show
	_name.visible = show


func set_body(text: String) -> void:
	_body.text = text


func set_continue_visible(show: bool) -> void:
	if not is_node_ready():
		return
	if show and not _arrow.visible:
		_arrow.restart()
	_arrow.visible = show


func clear_choices() -> void:
	for child: Node in _choices.get_children():
		child.queue_free()


func choice_container() -> VBoxContainer:
	return _choices


func style_choice(btn: Button, selected: bool) -> void:
	var bg := NAME_BG if selected else Color(CLOUD_RIM.r, CLOUD_RIM.g, CLOUD_RIM.b, 0.95)
	var radius := int(round(9.0 * _ui_scale))
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = bg.lightened(0.08) if state == &"hover" else bg
		box.border_color = Color(BODY_TEXT, 0.35)
		box.set_border_width_all(1)
		box.set_corner_radius_all(radius)
		box.content_margin_left = 10.0 * _ui_scale
		box.content_margin_right = 10.0 * _ui_scale
		box.content_margin_top = 2.0 * _ui_scale
		box.content_margin_bottom = 2.0 * _ui_scale
		btn.add_theme_stylebox_override(state, box)
	btn.add_theme_color_override("font_color", NAME_TEXT if selected else BODY_TEXT)
	btn.add_theme_color_override("font_hover_color", NAME_TEXT if selected else BODY_TEXT)
	btn.add_theme_color_override("font_outline_color", NAME_OUTLINE if selected else BODY_OUTLINE)
	btn.add_theme_constant_override("outline_size", maxi(1, int(round(2.0 * _ui_scale))))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	var size_px := maxi(1, int(round(CHOICE_FONT_PX * _ui_scale)))
	btn.add_theme_font_size_override("font_size", size_px)
	var font: Font = _condensed_font(btn, size_px)
	if font != null:
		btn.add_theme_font_override("font", font)


func _apply_textures() -> void:
	## Scene-assigned `TextureRect.texture` values win so you can swap art in the editor.
	_setup_sprite(_cloud, _cloud.texture if _cloud.texture != null else _load_first_texture(CLOUD_TEX_PATHS))
	_setup_sprite(
		_name_plate,
		_name_plate.texture if _name_plate.texture != null else _load_first_texture(NAMEPLATE_TEX_PATHS),
	)


func _setup_sprite(sprite: TextureRect, texture: Texture2D) -> void:
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## Scale the baked sprite to the virtual 320×240 layout rect (STRETCH_KEEP stays at
	## texture pixels and leaves a tiny box in the corner on hi-DPI windows).
	sprite.stretch_mode = TextureRect.STRETCH_SCALE


func _load_first_texture(paths: Array[String]) -> Texture2D:
	for path: String in paths:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _apply_text_theme() -> void:
	_body.add_theme_color_override("font_color", BODY_TEXT)
	_name.add_theme_color_override("font_color", NAME_TEXT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _layout() -> void:
	if not is_node_ready():
		return
	var ui_scale := minf(size.x / SCREEN_W, size.y / SCREEN_H)
	_ui_scale = ui_scale
	var origin := (size - Vector2(SCREEN_W, SCREEN_H) * ui_scale) * 0.5
	var cloud := cloud_rect()
	var cloud_pos := origin + cloud.position * ui_scale
	var cloud_size := cloud.size * ui_scale

	_cloud.position = cloud_pos
	_cloud.size = cloud_size

	var name_pos := cloud_pos + Vector2(NAME_UV.position.x, NAME_UV.position.y) * cloud_size
	var name_size := MIN_NAMEPLATE_SIZE * ui_scale
	_name_plate.position = name_pos
	_name_plate.size = name_size
	_name.position = name_pos
	_name.size = name_size
	_apply_font(_name, NAME_FONT_PX * ui_scale, 0.0)

	var body_pos := cloud_pos + BODY_UV * cloud_size
	var body_font_px := BODY_FONT_PX * ui_scale
	var pitch := BODY_LINE_PITCH_V * cloud_size.y
	_apply_font(_body, body_font_px, pitch)
	_body.position = Vector2(body_pos.x, body_pos.y - body_font_px * 0.25)
	_body.size = Vector2(
		cloud_size.x * (ARROW_UV.position.x - BODY_UV.x),
		pitch * float(MAX_BODY_LINES) + body_font_px * 0.5,
	)

	_arrow.position = cloud_pos + ARROW_UV.position * cloud_size
	_arrow.size = ARROW_UV.size * cloud_size

	var choice_w := cloud_size.x * (CHOICE_RIGHT_U - BODY_UV.x)
	_choices.position = Vector2(
		cloud_pos.x + CHOICE_RIGHT_U * cloud_size.x - choice_w,
		cloud_pos.y + CHOICE_TOP_V * cloud_size.y,
	)
	_choices.size = Vector2(choice_w, cloud_size.y * (CHOICE_BOTTOM_V - CHOICE_TOP_V))
	_choices.alignment = BoxContainer.ALIGNMENT_BEGIN
	_choices.add_theme_constant_override("separation", int(round(3.0 * ui_scale)))


func _apply_font(label: Label, font_px: float, pitch: float) -> void:
	var size_px := maxi(1, int(round(font_px)))
	label.add_theme_font_size_override("font_size", size_px)
	var font: Font = _condensed_font(label, size_px)
	if font != null:
		label.add_theme_font_override("font", font)
	if pitch <= 0.0:
		return
	var line_h: float = font.get_height(size_px) if font != null else float(size_px)
	label.add_theme_constant_override("line_spacing", int(round(pitch - line_h)))


func _condensed_font(control: Control, size_px: int) -> Font:
	var base: Font = control.get_theme_font("font")
	if base is FontVariation:
		base = (base as FontVariation).base_font
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	var condense: float = GLYPH_CONDENSE * float(size_px)
	variation.spacing_glyph = int(round(condense))
	variation.spacing_space = int(round(-condense * SPACE_RELIEF))
	return variation


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if is_node_ready():
			_layout()
		return
	if what == NOTIFICATION_ENTER_TREE and Engine.is_editor_hint():
		call_deferred("_layout")
		call_deferred("_apply_editor_preview")


func _apply_editor_preview() -> void:
	if not Engine.is_editor_hint() or not editor_preview or not is_node_ready():
		return
	_name_plate.visible = true
	_name.visible = true
	_arrow.visible = true
	if _body.text.is_empty():
		_body.text = "Hello! This is a preview line of dialogue."
	if _name.text.is_empty():
		_name.text = "Villager"
