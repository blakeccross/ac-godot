extends Control

## Title: new game or continue into the acre.

@onready var _continue: Button = %ContinueButton
@onready var _new_game: Button = %NewGameButton

var _leaving: bool = false


func _ready() -> void:
	Game.notify_title_ready()
	Audio.play_bgm(&"title")
	_continue.disabled = not Game.has_continue()
	if _continue.disabled:
		_new_game.grab_focus()
	else:
		_continue.grab_focus()


func _on_new_game_pressed() -> void:
	## Full opening, like the original: K.K. player select → Rover's train →
	## station arrival (Porter / Nook / house pick) → first job.
	_leave(Game.start_intro_sequence)


func _on_generated_town_pressed() -> void:
	## Dev skip: straight into a deterministic generated town, no intro.
	_leave(func() -> void: Game.start_new_game(WorldData.Mode.GENERATED, WorldGenerator.DEFAULT_SEED))


func _on_intro_pressed() -> void:
	_leave(Game.start_intro_sequence)


func _on_intro_station_pressed() -> void:
	_leave(Game.start_intro_station)


func _on_continue_pressed() -> void:
	_leave(Game.continue_game)


func _leave(action: Callable) -> void:
	## One transition at a time — the wipe-out entry points are async.
	if _leaving:
		return
	_leaving = true
	action.call()
