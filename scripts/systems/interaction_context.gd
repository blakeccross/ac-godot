class_name InteractionContext
extends RefCounted

## What an interactable may use. Objects should not reach into the player scene.

var actor: Node3D
var inventory: Inventory
var world: Node
## Which face of a piece of furniture the player is gripping (`FurnitureGrip.ContactSide`),
## or −1 when the verb did not come from a grip. Drawers and music players only answer from
## the front (`aMR_CONTACT_DIR_FRONT`).
var contact_side: int = -1


func release_occupant(occupant_id: StringName) -> void:
	if world != null and world.has_method("release_occupant"):
		world.call("release_occupant", occupant_id)
