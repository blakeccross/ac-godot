extends Node

## Dev helper: seated farewell pose matching the GC intro frame.

const INTRO_SCENE := "res://scenes/ui/intro_train.tscn"


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var packed: PackedScene = load(INTRO_SCENE) as PackedScene
	var intro: Node3D = packed.instantiate() as Node3D
	intro.preview_seated_daylight = true
	intro.preview_dialogue_text = "Thanks again!"
	add_child(intro)
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()
