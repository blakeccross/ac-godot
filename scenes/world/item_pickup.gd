extends Node3D

## World pickup. Facing-tile interact puts one item in pockets (`mPr` refuse if full).

@export var item: ItemData
@export var persist_id: StringName = &"ground_apple"
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.ITEM


func _ready() -> void:
	if Game.is_interactable_removed(persist_id):
		queue_free()


func interact_prompt() -> String:
	if item == null:
		return "Pick up"
	return "Pick up %s" % item.display_name


func try_interact() -> void:
	if item == null:
		return
	if not Game.inventory.has_space(1):
		Game.post_notice("Pockets full")
		return
	if Game.inventory.add(item, 1) != 0:
		Game.post_notice("Pockets full")
		return
	Game.mark_interactable_removed(persist_id)
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("release_occupant"):
		var id: StringName = persist_id if persist_id != &"" else occupant_id
		world.call("release_occupant", id)
	Game.post_notice("Picked up %s" % item.display_name)
	queue_free()
