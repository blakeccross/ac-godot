class_name InteractVolume
extends Area3D

## Sensor the player probe can see. The parent (or an ancestor) is the Interactable:
## it implements get_interactions() and interact(). This node has no object-type logic.

func _enter_tree() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true
