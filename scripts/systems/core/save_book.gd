class_name SaveBook
extends RefCounted

## One part of the town save that `Game` holds (the museum, the post office, the calendar…).
## `Game` writes each under its own key, reads them back in one pass, and wipes them together
## for a new town, so a new book only has to be listed once (`Game._save_books`).


func to_save() -> Dictionary:
	return {}


## Replace this book with `data`, as written by `to_save`.
func apply_snapshot(_data: Variant) -> void:
	pass


func clear() -> void:
	pass


## A save from before this book was stored.
func apply_missing() -> void:
	apply_snapshot({})


## A brand-new town.
func start_new() -> void:
	clear()
