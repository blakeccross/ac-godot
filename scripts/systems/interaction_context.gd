class_name InteractionContext
extends RefCounted

## What an interactable may use. Objects should not reach into the player scene.

var actor: Node3D
var inventory: Inventory
var world: Node


func release_occupant(occupant_id: StringName) -> void:
	if world != null and world.has_method("release_occupant"):
		world.call("release_occupant", occupant_id)
