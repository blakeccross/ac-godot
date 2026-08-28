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
	## Decomp new town: mSDI → mRF with live RNG (not the fixed test acre).
	var seed_value: int = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	Game.start_new_game(WorldData.Mode.GENERATED, seed_value)


func _on_generated_town_pressed() -> void:
	## Deterministic seed for debugging / tests.
	Game.start_new_game(WorldData.Mode.GENERATED, WorldGenerator.DEFAULT_SEED)


func _on_continue_pressed() -> void:
	Game.continue_game()
