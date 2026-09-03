extends Node3D

## Train interior shell and window scenery (`rom_train_out` UV scroll).

## Decomp `Train_Window_Actor_move` / tile scroll — game frames @ 60 Hz.
const _GAME_FPS := 60.0
const _TREE_TEXELS_PER_FRAME := 5.0
const _TREE_TILE_U := 128.0
const _CLOUD_TEXELS_PER_FRAME := 15.0 ## OperateScrollLimit halves the +30 GoingOut amount.
const _CLOUD_TILE_U := 64.0
const _CLOUD_SCROLL_END := 1000.0

var _daylight: bool = false
var _tree_scroll_texels: float = 500.0
var _cloud_scroll_texels: float = 0.0
var _exiting_tunnel: bool = false
var _cloud_mats: Array[StandardMaterial3D] = []
var _tree_mats: Array[StandardMaterial3D] = []

@onready var _car_visual: Node3D = $GeneratedVisual
@onready var _window_visual: Node3D = $WindowScenery/GeneratedVisual


func _ready() -> void:
	GeneratedVisual.fit_train_car_shell(_car_visual)
	GeneratedVisual.fit_train_window_shell(_window_visual)
	IntroTrainPresentation.apply_car_surfaces(_car_visual)
	_cloud_mats.clear()
	_tree_mats.clear()
	IntroTrainPresentation.apply_window_scenery(
		_window_visual, false, _cloud_mats, _tree_mats
	)
	_apply_scroll_offsets()


func _process(delta: float) -> void:
	var frames: float = delta * _GAME_FPS
	_tree_scroll_texels += _TREE_TEXELS_PER_FRAME * frames
	if _exiting_tunnel:
		_cloud_scroll_texels = minf(
			_CLOUD_SCROLL_END,
			_cloud_scroll_texels + _CLOUD_TEXELS_PER_FRAME * frames
		)
		if _cloud_scroll_texels >= _CLOUD_SCROLL_END:
			_exiting_tunnel = false
	_apply_scroll_offsets()


func apply_daylight(daylight: bool) -> void:
	if _daylight == daylight:
		return
	_daylight = daylight
	IntroTrainPresentation.apply_car_glass(_car_visual, daylight)
	_cloud_mats.clear()
	_tree_mats.clear()
	IntroTrainPresentation.apply_window_scenery(
		_window_visual, daylight, _cloud_mats, _tree_mats
	)
	if daylight:
		## `sunlight_flag` → `aTrainWindow_DrawGoingOutTunnel`.
		_exiting_tunnel = true
	_apply_scroll_offsets()


func _apply_scroll_offsets() -> void:
	var cloud_u: float = _cloud_scroll_texels / _CLOUD_TILE_U
	var tree_u: float = _tree_scroll_texels / _TREE_TILE_U
	for mat: StandardMaterial3D in _cloud_mats:
		mat.uv1_offset = Vector3(cloud_u, 0.0, 0.0)
	for mat: StandardMaterial3D in _tree_mats:
		mat.uv1_offset = Vector3(tree_u, 0.0, 0.0)
