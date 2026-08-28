extends Control

## Title: new game or continue into the acre.

@onready var _continue: Button = %ContinueButton
@onready var _new_game: Button = %NewGameButton


func _ready() -> void:
	Game.notify_title_ready()
	_continue.disabled = not Game.has_continue()
	if _continue.disabled:
		_new_game.grab_focus()
	else:
		_continue.grab_focus()


func _on_new_game_pressed() -> void:
	Game.start_new_game()


func _on_continue_pressed() -> void:
	Game.continue_game()
