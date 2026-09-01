class_name MessageWindowChrome
extends Control

## `m_msg` talk window. The window rect and every colour below are the `mMsg_init` values
## from the decomp; the silhouette and the sub-rect placements are measured off a GC frame
## because `con_kaiwa2_modelT` overshoots the nominal rect and the name text is centred by
## `mFont_SetLineStrings_AndSpace`, so neither falls out of the struct alone.

const SCREEN_W := 320.0
const SCREEN_H := 240.0
## `mMsg_init`: center (160, 185.4), 245 x 96.
const WINDOW_CENTER := Vector2(160.0, 185.4)
const WINDOW_SIZE := Vector2(245.0, 96.0)
## The drawn cloud matches the nominal width but its lobes stand ~6% past top and bottom.
const CLOUD_OVERSHOOT := Vector2(1.0, 1.0594)

## Sub-rects as fractions of the cloud rect (GC frame). Negative V is above the cloud top.
const NAME_UV := Rect2(0.041, -0.108, 0.362, 0.271)
const NAME_BASELINE_V := 0.085
const BODY_UV := Vector2(0.0828, 0.2059)
const BODY_LINE_PITCH_V := 0.1568
const ARROW_UV := Rect2(0.8724, 0.6928, 0.0299, 0.0752)

## `window_background_color` is PRIM eb/ff/eb, but `con_kaiwa2`'s texture modulates it down
## and the window is XLU; these are what the composited GC frame actually reads.
const CLOUD_FILL := Color(178.0 / 255.0, 192.0 / 255.0, 166.0 / 255.0, 0.85)
const CLOUD_RIM := Color(206.0 / 255.0, 226.0 / 255.0, 198.0 / 255.0, 0.95)
## `name_background_color` is PRIM a0/d7/1e; the frame reads the brighter modulated lime.
const NAME_BG := Color(137.0 / 255.0, 235.0 / 255.0, 10.0 / 255.0, 1.0)
## `name_text_color` 32/5a/00 and `mMsg_init_FontColor` 50/60/50, both with the font outline.
const NAME_TEXT := Color(50.0 / 255.0, 90.0 / 255.0, 0.0, 1.0)
const NAME_OUTLINE := Color(0.0, 23.0 / 255.0, 0.0, 1.0)
const BODY_TEXT := Color(50.0 / 255.0, 60.0 / 255.0, 50.0 / 255.0, 1.0)
const BODY_OUTLINE := Color(16.0 / 255.0, 41.0 / 255.0, 16.0 / 255.0, 1.0)

## Cap heights measured off the GC frame. `mFont`'s glyphs are narrower per advance than
## Godot's default face at the same cap height, so the advance is pulled in to match.
const BODY_FONT_PX := 14.0
const NAME_FONT_PX := 17.0
const GLYPH_CONDENSE := -0.10
## The condense applies to every advance, spaces included, which welds words together.
## Give it back on the space glyph so word gaps stay as open as the GC frame's.
const SPACE_RELIEF := 1.6
const OUTLINE_PX := 2.0

const _SHADER := preload("res://shaders/message_window.gdshader")

@onready var _cloud: ColorRect = %Cloud
@onready var _name_plate: ColorRect = %NamePlate
@onready var _name: Label = %NameLabel
@onready var _body: Label = %BodyLabel
@onready var _arrow: MessageContinueArrow = %ContinueArrow
@onready var _choices: VBoxContainer = %ChoiceList

var _cloud_mat: ShaderMaterial
var _name_mat: ShaderMaterial


func _ready() -> void:
	_build_materials()
	_apply_text_theme()
	_layout()


## Cloud rect in virtual 320x240 units, before the viewport scale.
static func cloud_rect() -> Rect2:
	var cloud_size := WINDOW_SIZE * CLOUD_OVERSHOOT
	return Rect2(WINDOW_CENTER - cloud_size * 0.5, cloud_size)


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


static func style_choice_button(btn: Button, selected: bool) -> void:
	## AC draws choices in their own small window; keep the same palette as the cloud so
	## they read as part of the same chrome rather than as engine buttons.
	var bg := NAME_BG if selected else Color(CLOUD_RIM.r, CLOUD_RIM.g, CLOUD_RIM.b, 0.95)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = bg.lightened(0.08) if state == &"hover" else bg
		box.draw_center = true
		box.border_color = Color(BODY_TEXT, 0.35)
		box.set_border_width_all(1)
		box.set_corner_radius_all(9)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		btn.add_theme_stylebox_override(state, box)
	btn.add_theme_color_override("font_color", NAME_TEXT if selected else BODY_TEXT)
	btn.add_theme_color_override("font_hover_color", NAME_TEXT if selected else BODY_TEXT)
	btn.add_theme_color_override("font_outline_color", NAME_OUTLINE if selected else BODY_OUTLINE)
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_font_size_override("font_size", 17)


func _build_materials() -> void:
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = _SHADER
	_cloud_mat.set_shader_parameter("fill_color", CLOUD_FILL)
	_cloud_mat.set_shader_parameter("rim_color", CLOUD_RIM)
	_cloud.material = _cloud_mat
	_cloud.color = Color.WHITE

	## Nameplate: same SDF, lobes off. `con_kaiwaname` is flatter than an ellipse across the
	## middle of its long edges, so the exponent sits above 2.
	_name_mat = ShaderMaterial.new()
	_name_mat.shader = _SHADER
	_name_mat.set_shader_parameter("fill_color", NAME_BG)
	_name_mat.set_shader_parameter("rim_color", NAME_BG)
	_name_mat.set_shader_parameter("rim_width", 0.0)
	_name_mat.set_shader_parameter("body_axis_x", 0.5)
	_name_mat.set_shader_parameter("body_exponent", 2.6)
	_name_mat.set_shader_parameter("lobe_radius", 0.0)
	_name_plate.material = _name_mat
	_name_plate.color = Color.WHITE


func _apply_text_theme() -> void:
	_body.add_theme_color_override("font_color", BODY_TEXT)
	_body.add_theme_color_override("font_outline_color", BODY_OUTLINE)
	_name.add_theme_color_override("font_color", NAME_TEXT)
	_name.add_theme_color_override("font_outline_color", NAME_OUTLINE)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _layout() -> void:
	if not is_node_ready():
		return
	var ui_scale := minf(size.x / SCREEN_W, size.y / SCREEN_H)
	## Letterbox the virtual screen so the cloud keeps its 4:3 placement on any window.
	var origin := (size - Vector2(SCREEN_W, SCREEN_H) * ui_scale) * 0.5
	var cloud := cloud_rect()
	var cloud_pos := origin + cloud.position * ui_scale
	var cloud_size := cloud.size * ui_scale

	_cloud.position = cloud_pos
	_cloud.size = cloud_size
	_cloud_mat.set_shader_parameter("rect_px", cloud_size)

	var name_pos := cloud_pos + Vector2(NAME_UV.position.x, NAME_UV.position.y) * cloud_size
	var name_size := Vector2(NAME_UV.size.x, NAME_UV.size.y) * cloud_size
	_name_plate.position = name_pos
	_name_plate.size = name_size
	_name_mat.set_shader_parameter("rect_px", name_size)
	_name.position = name_pos
	_name.size = name_size
	_apply_font(_name, NAME_FONT_PX * ui_scale, 0.0)

	var body_pos := cloud_pos + BODY_UV * cloud_size
	## Godot lays a Label's first line from the box top, not the cap top.
	var body_font_px := BODY_FONT_PX * ui_scale
	var pitch := BODY_LINE_PITCH_V * cloud_size.y
	_apply_font(_body, body_font_px, pitch)
	_body.position = Vector2(body_pos.x, body_pos.y - body_font_px * 0.25)
	_body.size = Vector2(
		cloud_size.x * (ARROW_UV.position.x - BODY_UV.x), pitch * 3.0 + body_font_px
	)

	_arrow.position = cloud_pos + ARROW_UV.position * cloud_size
	_arrow.size = ARROW_UV.size * cloud_size

	_choices.position = Vector2(body_pos.x, body_pos.y + pitch)
	_choices.size = Vector2(_body.size.x, pitch * 2.5)
	_choices.add_theme_constant_override("separation", int(round(3.0 * ui_scale)))


func _apply_font(label: Label, font_px: float, pitch: float) -> void:
	var size_px := maxi(1, int(round(font_px)))
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_constant_override(
		"outline_size", maxi(1, int(round(OUTLINE_PX * font_px / BODY_FONT_PX)))
	)
	var font: Font = _condensed_font(label, size_px)
	if font != null:
		label.add_theme_font_override("font", font)
	if pitch <= 0.0:
		return
	var line_h: float = font.get_height(size_px) if font != null else float(size_px)
	label.add_theme_constant_override("line_spacing", int(round(pitch - line_h)))


func _condensed_font(label: Label, size_px: int) -> Font:
	var base: Font = label.get_theme_font("font")
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
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()
