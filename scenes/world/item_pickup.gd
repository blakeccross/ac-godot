extends Node3D

## World pickup. Facing-tile interact puts one item in pockets (`mPr` refuse if full).

@export var item: ItemData
@export var persist_id: StringName = &"ground_apple"


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
	Game.post_notice("Picked up %s" % item.display_name)
	queue_free()
