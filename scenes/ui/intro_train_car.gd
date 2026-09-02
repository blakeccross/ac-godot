extends Node3D

## Train interior shell and window scenery — materials applied from the scene tree.

var _daylight: bool = false

@onready var _car_visual: Node3D = $GeneratedVisual
@onready var _window_visual: Node3D = $WindowScenery/GeneratedVisual


func _ready() -> void:
	IntroTrainPresentation.apply_car_surfaces(_car_visual)
	IntroTrainPresentation.apply_window_scenery(_window_visual, false)


func apply_daylight(daylight: bool) -> void:
	if _daylight == daylight:
		return
	_daylight = daylight
	IntroTrainPresentation.apply_car_glass(_car_visual, daylight)
	IntroTrainPresentation.apply_window_scenery(_window_visual, daylight)
