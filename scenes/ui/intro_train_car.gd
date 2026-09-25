extends Node3D

## Train interior shell and window scenery (`ac_train_window` / `rom_train_out`).
## Scroll offsets are `tex_scroll2` tile origins (10.2 fixed → raw / 4 texels); the tile
## origin is subtracted from the sample coordinate, so UV offsets are negative.

## `rom_train_out` ENV colours / PRIM_LOD_FRAC per draw (`Train_Window_Actor_draw`).
const CLOUD_ENV := Color(127.0 / 255.0, 127.0 / 255.0, 100.0 / 255.0)
const TREE_ENV := Color(60.0 / 255.0, 60.0 / 255.0, 35.0 / 255.0)
const TREE_PRIM_OFFSET := Color(-80.0 / 255.0, -70.0 / 255.0, -160.0 / 255.0)
const TUNNEL_LOD := 43.0 / 255.0
const CLOUD_LOD := 127.0 / 255.0
const TREE_LOD := 27.0 / 255.0
## Decomp tile widths (texels) for UV normalisation.
const TREE_TILE_S := 128.0
const TUNNEL_TILE_S := 64.0
const SHINE_TILE_S := 64.0
const CLOUD_TILE_T := 64.0
## `TreeScrollx` starts 500, += 5 per frame.
const TREE_SCROLL_START := 500.0
const TREE_SCROLL_STEP := 5.0
## `aTrainWindow_DrawGoingOutTunnel`: +30 >> 1 per frame to 1000 (Single_Scrollx / Two_Scrollx1).
const EXIT_SCROLL_STEP := 15.0
const EXIT_SCROLL_END := 1000.0
## `aTrainWindow_out_cloud {0, -2}` EVW dolphin scroll: 2 units/frame = 1/4 texel in T.
const CLOUD_TEXELS_PER_FRAME := 2.0 / 8.0
## `window->scroll_speed` for SCENE_START_DEMO; `xlu_alpha` starts 254.
const XLU_ALPHA_RATE := 0.07
const LOD_FACTOR_RATE := 0.3
const _LOGIC_HZ := PlayerLocomotion.LOGIC_HZ

var _daylight: bool = false
var _exiting_tunnel: bool = false
var _tree_scroll: float = TREE_SCROLL_START
var _exit_scroll: float = 0.0
var _cloud_frames: float = 0.0
var _xlu_alpha: float = 254.0
var _lod_factor: float = 0.0
var _frame_accum: float = 0.0
var _sky_mats: Array[StandardMaterial3D] = []
var _tunnel_mats: Array[StandardMaterial3D] = []
var _cloud_mats: Array[StandardMaterial3D] = []
var _tree_mats: Array[StandardMaterial3D] = []
var _shine_mats: Array[ShaderMaterial] = []

@onready var _car_visual: Node3D = $GeneratedVisual
@onready var _window_visual: Node3D = $WindowScenery/GeneratedVisual


func _ready() -> void:
	VisualTrain.fit_train_car_shell(_car_visual)
	VisualTrain.fit_train_window_shell(_window_visual, _car_visual)
	IntroTrainPresentation.apply_car_surfaces(_car_visual)
	var roles: Dictionary = IntroTrainPresentation.apply_window_scenery(_window_visual)
	_sky_mats = roles[&"sky"]
	_tunnel_mats = roles[&"tunnel"]
	_cloud_mats = roles[&"cloud"]
	_tree_mats = roles[&"tree"]
	_shine_mats.assign(roles[&"shine"])
	_apply_window()


func _process(delta: float) -> void:
	_frame_accum = minf(_frame_accum + delta * _LOGIC_HZ, 8.0)
	while _frame_accum >= 1.0:
		_frame_accum -= 1.0
		_step_frame()
	_apply_window()


## `Train_Window_Actor_move` + the scroll half of `draw_type`, once per decomp frame.
func _step_frame() -> void:
	_tree_scroll = fmod(_tree_scroll + TREE_SCROLL_STEP, 2048.0) ## `x & 0x7FF`
	_cloud_frames += 1.0
	_xlu_alpha = AcreCamera.add_calc(_xlu_alpha, now_xlu_alpha(Clock.now_sec()), XLU_ALPHA_RATE, 50.0, 1.0)
	_lod_factor = AcreCamera.add_calc(_lod_factor, now_lod_factor(Clock.now_sec()), LOD_FACTOR_RATE, 50.0, 1.0)
	if _exiting_tunnel:
		_exit_scroll = minf(_exit_scroll + EXIT_SCROLL_STEP, EXIT_SCROLL_END)
		if _exit_scroll >= EXIT_SCROLL_END:
			## `DrawGoneOutTunnel`: exit scroll frozen at 1000.
			_exiting_tunnel = false


## `sunlight_flag` → `aTrainWindow_DrawInTunnel` switches to `DrawGoingOutTunnel`.
func apply_daylight(daylight: bool) -> void:
	if _daylight == daylight:
		return
	_daylight = daylight
	IntroTrainPresentation.apply_car_glass(_car_visual, daylight)
	if daylight:
		_exiting_tunnel = true
	else:
		_exiting_tunnel = false
		_exit_scroll = 0.0
	_apply_window()


## `aTW_GetNowAlpha` — XLU alpha target (0 at 04:00 / 20:00, 255 at noon).
static func now_xlu_alpha(now_sec: int) -> float:
	var sec := float(now_sec)
	if now_sec >= 14400 and now_sec < 72000:
		if now_sec < 43200:
			return floorf(255.0 * ((sec - 14400.0) / 28800.0))
		return floorf(255.0 * (1.0 - (sec - 43200.0) / 28800.0))
	if now_sec < 14400:
		return floorf(200.0 * (1.0 - (0.5 + sec / 28800.0)))
	return floorf(200.0 * ((sec - 72000.0) / 28800.0))


## `Train_Window_Actor_move` `lod_factor` target (shineglass strength).
static func now_lod_factor(now_sec: int) -> float:
	var sec := float(now_sec)
	if now_sec < 14400 or now_sec >= 72000:
		return 0.0
	if now_sec >= 43200:
		return 160.0 - 160.0 * ((sec - 43200.0) / 28800.0)
	return 160.0 * ((sec - 14400.0) / 28800.0)


## `aTrainWindow_SetLightPrimColorDetail`: clamp(global ambient + sun colour + offset).
static func prim_color(offset: Color = Color(0, 0, 0)) -> Color:
	var light: Dictionary = IntroTrainPresentation.current_light()
	var amb: Color = light["ambient"] as Color
	var sun: Color = light["sun_scaled"] as Color
	return Color(
		clampf(amb.r + sun.r + offset.r, 0.0, 1.0),
		clampf(amb.g + sun.g + offset.g, 0.0, 1.0),
		clampf(amb.b + sun.b + offset.b, 0.0, 1.0)
	)


func _apply_window() -> void:
	var prim: Color = prim_color()
	var tree_prim: Color = prim_color(TREE_PRIM_OFFSET)
	var xlu_a: float = clampf(floorf(_xlu_alpha), 0.0, 255.0) / 255.0
	var lod_a: float = clampf(_lod_factor, 0.0, 255.0) / 255.0
	var tree_u: float = -(_tree_scroll / 4.0) / TREE_TILE_S
	var exit_texels: float = _exit_scroll / 4.0
	var cloud_v: float = -fmod(_cloud_frames * CLOUD_TEXELS_PER_FRAME, CLOUD_TILE_T) / CLOUD_TILE_T
	for mat: StandardMaterial3D in _sky_mats:
		mat.albedo_color = Color(prim, 1.0)
	for mat: StandardMaterial3D in _tunnel_mats:
		mat.albedo_color = Color(prim * TUNNEL_LOD, 1.0)
		mat.uv1_offset = Vector3(-exit_texels / TUNNEL_TILE_S, 0.0, 0.0)
	for mat: StandardMaterial3D in _cloud_mats:
		mat.albedo_color = _lod_env(prim, CLOUD_LOD, CLOUD_ENV, xlu_a)
		mat.uv1_offset = Vector3(0.0, cloud_v, 0.0)
	for mat: StandardMaterial3D in _tree_mats:
		mat.albedo_color = _lod_env(tree_prim, TREE_LOD, TREE_ENV, 1.0)
		mat.uv1_offset = Vector3(tree_u, 0.0, 0.0)
	for mat: ShaderMaterial in _shine_mats:
		mat.set_shader_parameter(&"prim_color", Color(prim, 1.0))
		mat.set_shader_parameter(&"lod_frac", lod_a)
		mat.set_shader_parameter(&"shine_offset", -exit_texels / SHINE_TILE_S)


## Combiner `(PRIM − 0) × PRIM_LOD_FRAC + ENV`.
static func _lod_env(prim: Color, lod: float, env: Color, alpha: float) -> Color:
	return Color(
		minf(prim.r * lod + env.r, 1.0),
		minf(prim.g * lod + env.g, 1.0),
		minf(prim.b * lod + env.b, 1.0),
		alpha
	)
