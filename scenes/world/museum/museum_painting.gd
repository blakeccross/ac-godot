extends "res://scenes/world/museum/museum_room.gd"

## Painting wing — mid-wall colliders + wall art exhibits.


func present_exhibits(furniture: Node3D, session: Interior) -> void:
	var terrain: Node3D = null
	if furniture != null and furniture.get_parent() != null:
		terrain = furniture.get_parent().get_node_or_null("Terrain") as Node3D
	var builder := InteriorBuilder.new()
	builder.add_museum_art_partitions(terrain, session.room, session.grid)
	MuseumPresenter.new().present_paintings(furniture, session)
