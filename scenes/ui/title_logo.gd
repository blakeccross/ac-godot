extends CanvasLayer

## Title logo overlay: the presentation half of `ac_animal_logo`. All timing and state live in
## `TitleLogoState`; this node steps it at 60 Hz, scrubs the three baked skeleton clips to its
## `anim_seconds()`, and mirrors its opacities onto the backdrop, copyright line and
## "PRESS START". Layout is authored in `title_logo.tscn` in the original 320x240 space
## (`mFont_SetMatrix`: ortho +-160x120 px, y up); generated art is attached here when present.

signal start_selected
signal start_chime

const VIRTUAL := Vector2(320.0, 240.0)
## One GLB unit = `scale 0.001` of a decomp vertex unit; the logo matrix is 0.135 and the
## font ortho is 16 units per pixel, so 1 GLB unit = 0.135 / 16 / 0.001 px.
const PX_PER_UNIT := 8.4375

const MODEL_ANIMAL := "res://assets/generated/ui/logo_us_animal.glb"
const MODEL_CROS := "res://assets/generated/ui/logo_us_cros.glb"
const MODEL_SING := "res://assets/generated/ui/logo_us_sing.glb"
const MODEL_BACK := "res://assets/generated/environment/logo_us_back.glb"
const MODEL_TM := "res://assets/generated/environment/logo_us_tm.glb"
const TITLE_TEXTURE := "res://assets/generated/ui/title/%s.png"

const MASK_SHADER := preload("res://shaders/title_logo_mask.gdshader")
## `aAL_back_draw`: prim (80, 60, 0). `aAL_tm_draw` inherits the copyright line's (40, 40, 45).
const BACK_COLOR := Color8(80, 60, 0)
const TM_COLOR := Color8(40, 40, 45)

var state: TitleLogoState = TitleLogoState.new()
var demo_index: int = 0
## Set by the owner: land loaded and the fade-in finished / demo not in its lockout / demo over.
var can_start: bool = false
var button_ok: bool = true
var demo_ended: bool = false

var _steps := FrameStepper.new()
var _start_latched: bool = false
var _clips: Array[AnimationPlayer] = []
var _back_materials: Array[ShaderMaterial] = []
var _has_models: bool = false

@onready var _viewport_box: SubViewportContainer = %Viewport3D
@onready var _camera: Camera3D = %Camera
@onready var _overlay: Control = %Overlay2D
@onready var _back_root: Node3D = %BackRoot
@onready var _animal_slot: Node3D = %Animal
@onready var _cros_slot: Node3D = %Cros
@onready var _sing_slot: Node3D = %Sing
@onready var _tm_slot: Node3D = %Tm
@onready var _copyright: Control = %Copyright
@onready var _press_start: Control = %PressStart
@onready var _fallback: Label = %FallbackTitle


func _ready() -> void:
	_camera.size = VIRTUAL.y / PX_PER_UNIT
	_attach_models()
	_attach_textures()
	_fallback.visible = not _has_models
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()


func _process(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		_tick()


func _unhandled_input(event: InputEvent) -> void:
	## START or A (`aAL_chk_start_key`).
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_start_latched = true
		get_viewport().set_input_as_handled()


func _tick() -> void:
	var pressed: bool = _start_latched
	_start_latched = false
	state.tick(pressed, can_start, button_ok, demo_ended)
	_refresh()
	if state.start_chime_requested:
		start_chime.emit()
	if state.select_requested:
		start_selected.emit()


func _refresh() -> void:
	var t: float = state.anim_seconds()
	for player: AnimationPlayer in _clips:
		player.seek(t, true)
	_back_root.visible = state.back_visible() and _has_models
	for mat: ShaderMaterial in _back_materials:
		mat.set_shader_parameter("opacity", float(state.back_opacity) / 255.0)
	_copyright.visible = state.copyright_visible()
	_copyright.modulate.a = float(state.copyright_opacity) / 255.0
	_tm_slot.visible = state.copyright_visible() and _has_models
	_press_start.visible = state.press_start_visible()
	_press_start.modulate.a = state.press_start_opacity / 255.0


## 4:3 stage, centred and scaled to the window height. The 3D logo renders into a viewport of
## exactly that size (crisp); the 2D lines scale from the same virtual space.
func _layout() -> void:
	var window: Vector2 = get_viewport().get_visible_rect().size
	var s: float = minf(window.x / VIRTUAL.x, window.y / VIRTUAL.y)
	var size: Vector2 = VIRTUAL * s
	var origin: Vector2 = (window - size) * 0.5
	_viewport_box.position = origin
	_viewport_box.size = size
	_overlay.position = origin
	_overlay.scale = Vector2(s, s)


func _attach_models() -> void:
	var animal: bool = _attach(_animal_slot, MODEL_ANIMAL)
	var cros: bool = _attach(_cros_slot, MODEL_CROS)
	var sing: bool = _attach(_sing_slot, MODEL_SING)
	var back: bool = _attach(_back_root, MODEL_BACK)
	var tm: bool = _attach(_tm_slot, MODEL_TM)
	_has_models = animal and cros and sing
	for slot: Node3D in [_animal_slot, _cros_slot, _sing_slot]:
		_unshade(slot)
		for found: Node in slot.find_children("*", "AnimationPlayer", true, false):
			var player := found as AnimationPlayer
			var names: PackedStringArray = player.get_animation_list()
			if names.is_empty():
				continue
			player.play(names[0])
			player.pause()
			_clips.append(player)
	if back:
		_mask_materials(_back_root, BACK_COLOR, _back_materials)
	if tm:
		var tm_materials: Array[ShaderMaterial] = []
		_mask_materials(_tm_slot, TM_COLOR, tm_materials)


func _attach(slot: Node3D, path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	slot.add_child(packed.instantiate())
	return true


## `G_CC_DECALRGBA`: colour and alpha straight from the texture, no lighting.
func _unshade(root: Node) -> void:
	for found: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		for i: int in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as StandardMaterial3D
			copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
			copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			mesh.set_surface_override_material(i, copy)


func _mask_materials(root: Node, color: Color, sink: Array[ShaderMaterial]) -> void:
	for found: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		for i: int in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var shader := ShaderMaterial.new()
			shader.shader = MASK_SHADER
			shader.set_shader_parameter("mask", mat.albedo_texture)
			shader.set_shader_parameter("prim_color", color)
			shader.set_shader_parameter("opacity", 1.0)
			mesh.set_surface_override_material(i, shader)
			sink.append(shader)


## Which of the five press-start palettes to show (`titledemo_no`).
func set_demo_index(index: int) -> void:
	demo_index = clampi(index, 0, TitleDemo.DEMO_COUNT - 1)
	if is_node_ready():
		_attach_press_start()


func _attach_textures() -> void:
	for i: int in 3:
		_set_texture(_copyright.get_node("Line%d" % i) as TextureRect, "copyright_%d" % i)
	_attach_press_start()


func _attach_press_start() -> void:
	for half: int in 2:
		var rect := _press_start.get_node("Half%d" % half) as TextureRect
		_set_texture(rect, "press_start_%d_%d" % [demo_index, half])


func _set_texture(rect: TextureRect, stem: String) -> void:
	var path: String = TITLE_TEXTURE % stem
	if ResourceLoader.exists(path):
		rect.texture = load(path) as Texture2D
