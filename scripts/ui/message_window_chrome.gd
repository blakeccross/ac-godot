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
const BODY_TEXT := Color(50.0 / 255.0, 60.0 / 255.0, 50.0 / 255.0, 1.0)
const CHOICE_TEXT := Color(180.0 / 255.0, 150.0 / 255.0, 110.0 / 255.0, 1.0)
const CHOICE_TEXT_SELECTED := Color(120.0 / 255.0, 50.0 / 255.0, 50.0 / 255.0, 1.0)

const BODY_FONT_PX := 14.0
const NAME_FONT_PX := 17.0
const GLYPH_CONDENSE := -0.10
const SPACE_RELIEF := 1.6
## `mFont` CHARSCALE / LINESCALE unit: 32 = 1.0.
const FONT_SCALE_UNIT := 32.0
const _STYLE_TAG_RE := "\\{([cs]):([0-9,]+)\\}"

@onready var _cloud: TextureRect = %Cloud
@onready var _name_plate: TextureRect = %NamePlate
@onready var _name: Label = %NameLabel
@onready var _body: RichTextLabel = %BodyLabel
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
	if not is_node_ready():
		return
	_body.clear()
	_body.append_text(_to_bbcode(text))


## Visible glyph count for typewriter (`RichTextLabel.visible_characters`).
func set_body_visible_chars(count: int) -> void:
	if not is_node_ready():
		return
	_body.visible_characters = count


func body_visible_char_count() -> int:
	if not is_node_ready():
		return 0
	## `get_total_character_count` ignores BBCode tags.
	return _body.get_total_character_count()


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
	## `mChoice_DrawFont`: plain coloured text + cyan mark — no outline, no bordered chip.
	var empty := StyleBoxEmpty.new()
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		btn.add_theme_stylebox_override(state, empty)
	var color := CHOICE_TEXT_SELECTED if selected else CHOICE_TEXT
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", color)
	btn.add_theme_color_override("font_pressed_color", color)
	btn.add_theme_color_override("font_focus_color", color)
	btn.add_theme_constant_override("outline_size", 0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	var size_px := maxi(1, int(round(CHOICE_FONT_PX * _ui_scale)))
	btn.add_theme_font_size_override("font_size", size_px)
	var font: Font = _condensed_font(btn, size_px)
	if font != null:
		btn.add_theme_font_override("font", font)
	var mark := "▶ " if selected else "  "
	var label := str(btn.get_meta("choice_label")) if btn.has_meta("choice_label") else btn.text
	if not btn.has_meta("choice_label"):
		## Strip a prior mark if re-highlighting before meta was set.
		btn.set_meta("choice_label", label.trim_prefix("▶ ").trim_prefix("  "))
		label = str(btn.get_meta("choice_label"))
	btn.text = mark + label


func _to_bbcode(raw: String) -> String:
	## Expand `{c:r,g,b}` / `{s:n}` from the dialogue converter into BBCode.
	var base_px := maxi(1, int(round(BODY_FONT_PX * _ui_scale)))
	var out := ""
	var i := 0
	var open_color := false
	var open_scale := false
	var re := RegEx.new()
	re.compile(_STYLE_TAG_RE)
	while i < raw.length():
		var m: RegExMatch = re.search(raw, i)
		if m == null:
			out += _bb_escape(raw.substr(i))
			break
		var start: int = m.get_start()
		if start > i:
			out += _bb_escape(raw.substr(i, start - i))
		var kind: String = m.get_string(1)
		var payload: String = m.get_string(2)
		if kind == "c":
			var rgb: PackedStringArray = payload.split(",")
			if rgb.size() >= 3:
				if open_color:
					out += "[/color]"
				var hex := "%02x%02x%02x" % [
					clampi(int(rgb[0]), 0, 255),
					clampi(int(rgb[1]), 0, 255),
					clampi(int(rgb[2]), 0, 255),
				]
				out += "[color=#%s]" % hex
				open_color = true
		elif kind == "s":
			var unit := maxi(1, int(payload))
			var px := maxi(1, int(round(float(base_px) * float(unit) / FONT_SCALE_UNIT)))
			if open_scale:
				out += "[/font_size]"
			if unit == int(FONT_SCALE_UNIT):
				open_scale = false
			else:
				out += "[font_size=%d]" % px
				open_scale = true
		i = m.get_end()
	if open_scale:
		out += "[/font_size]"
	if open_color:
		out += "[/color]"
	return out


func _bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")


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
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_color_override("default_color", BODY_TEXT)
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
	_apply_rich_font(_body, body_font_px, pitch)
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


func _apply_rich_font(label: RichTextLabel, font_px: float, pitch: float) -> void:
	var size_px := maxi(1, int(round(font_px)))
	label.add_theme_font_size_override("normal_font_size", size_px)
	var font: Font = _condensed_font(label, size_px)
	if font != null:
		label.add_theme_font_override("normal_font", font)
	if pitch <= 0.0:
		return
	var line_h: float = font.get_height(size_px) if font != null else float(size_px)
	label.add_theme_constant_override("line_separation", int(round(pitch - line_h)))


func _condensed_font(control: Control, size_px: int) -> Font:
	var base: Font = control.get_theme_font("font")
	if base == null and control is RichTextLabel:
		base = control.get_theme_font("normal_font")
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
	if _body.get_total_character_count() == 0:
		set_body("Hello! This is a preview line of dialogue.")
	if _name.text.is_empty():
		_name.text = "Villager"
