extends Node

## Boots the train intro for offline recording. Pair with `--record-intro --write-movie`.


func _ready() -> void:
	Clock.paused = true
	Game.start_intro_sequence()
