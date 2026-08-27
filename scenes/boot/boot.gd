extends Control

## Phase 0 boot screen. Confirms the project launches; not gameplay.

@onready var _version_label: Label = %Version


func _ready() -> void:
	var info: Dictionary = Engine.get_version_info()
	_version_label.text = "Godot %s.%s.%s" % [info.major, info.minor, info.patch]
