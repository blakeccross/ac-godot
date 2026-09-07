extends Node3D

## Train interior shell and window scenery (`rom_train_out` UV scroll).

## Decomp `Train_Window_Actor_move` / tile scroll — game frames @ 60 Hz.
const _GAME_FPS := 60.0
const _TREE_TEXELS_PER_FRAME := 5.0
const _TREE_TILE_U := 128.0
## `aTrainWindow_DrawGoingOutTunnel` passes +30; `OperateScrollLimit` halves → 15.
const _EXIT_TEXELS_PER_FRAME := 15.0
const _CLOUD_TILE_U := 64.0
const _TUNNEL_TILE_U := 64.0
## `Single_Scrollx` / cloud scroll end (`TileScroll` xend = 1000).
const _EXIT_SCROLL_END := 1000.0

var _daylight: bool = false
var _tree_scroll_texels: float = 500.0
var _cloud_scroll_texels: float = 0.0
var _tunnel_scroll_texels: float = 0.0
var _exiting_tunnel: bool = false
var _cloud_mats: Array[StandardMaterial3D] = []
var _tree_mats: Array[StandardMaterial3D] = []
var _tunnel_mats: Array[StandardMaterial3D] = []

@onready var _car_visual: Node3D = $GeneratedVisual
@onready var _window_visual: Node3D = $WindowScenery/GeneratedVisual


func _ready() -> void:
	GeneratedVisual.fit_train_car_shell(_car_visual)
	GeneratedVisual.fit_train_window_shell(_window_visual, _car_visual)
	IntroTrainPresentation.apply_car_surfaces(_car_visual)
	_cloud_mats.clear()
	_tree_mats.clear()
	_tunnel_mats.clear()
	IntroTrainPresentation.apply_window_scenery(
		_window_visual, false, _cloud_mats, _tree_mats, _tunnel_mats
	)
	_apply_scroll_offsets()


func _process(delta: float) -> void:
	var frames: float = delta * _GAME_FPS
	_tree_scroll_texels += _TREE_TEXELS_PER_FRAME * frames
	if _exiting_tunnel:
		## `aTrainWindow_DrawGoingOutTunnel`: tunnel/sky (seg 11) + cloud scroll to 1000.
		_tunnel_scroll_texels = minf(
			_EXIT_SCROLL_END,
			_tunnel_scroll_texels + _EXIT_TEXELS_PER_FRAME * frames
		)
		_cloud_scroll_texels = minf(
			_EXIT_SCROLL_END,
			_cloud_scroll_texels + _EXIT_TEXELS_PER_FRAME * frames
		)
		if (
			_tunnel_scroll_texels >= _EXIT_SCROLL_END
			and _cloud_scroll_texels >= _EXIT_SCROLL_END
		):
			## `DrawGoneOutTunnel` — freeze exit scroll; trees keep moving.
			_exiting_tunnel = false
	_apply_scroll_offsets()


func apply_daylight(daylight: bool) -> void:
	if _daylight == daylight:
		return
	_daylight = daylight
	IntroTrainPresentation.apply_car_glass(_car_visual, daylight)
	_cloud_mats.clear()
	_tree_mats.clear()
	_tunnel_mats.clear()
	IntroTrainPresentation.apply_window_scenery(
		_window_visual, daylight, _cloud_mats, _tree_mats, _tunnel_mats
	)
	if daylight:
		## `sunlight_flag` → `aTrainWindow_DrawGoingOutTunnel`.
		_exiting_tunnel = true
		_tunnel_scroll_texels = 0.0
		_cloud_scroll_texels = 0.0
	_apply_scroll_offsets()


func _apply_scroll_offsets() -> void:
	var cloud_u: float = _cloud_scroll_texels / _CLOUD_TILE_U
	var tree_u: float = _tree_scroll_texels / _TREE_TILE_U
	var tunnel_u: float = _tunnel_scroll_texels / _TUNNEL_TILE_U
	for mat: StandardMaterial3D in _cloud_mats:
		mat.uv1_offset = Vector3(cloud_u, 0.0, 0.0)
	for mat: StandardMaterial3D in _tree_mats:
		mat.uv1_offset = Vector3(tree_u, 0.0, 0.0)
	for mat: StandardMaterial3D in _tunnel_mats:
		mat.uv1_offset = Vector3(tunnel_u, 0.0, 0.0)
