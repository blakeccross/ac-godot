extends "res://scenes/world/museum/museum_room.gd"

## Entrance hall — Blathers + wing link doors (no exhibits).


func present_exhibits(furniture: Node3D, session: Interior) -> void:
	var builder := InteriorBuilder.new()
	builder.add_blathers(furniture, session)
	builder.add_museum_clock(furniture, session)
