class_name ActorFacing
extends RefCounted

## Which way an actor faces. The player reports its own facing (`Player.facing_yaw`, which
## leads its body's rotation mid-turn); so do the stand-ins tests use for it. The one place
## that asks an actor for `facing_yaw` by name.


static func has_facing(node: Object) -> bool:
	return node != null and node.has_method(&"facing_yaw")


## `node`'s facing yaw, or `fallback` when it doesn't report one.
static func yaw_or(node: Object, fallback: float) -> float:
	return float(node.call(&"facing_yaw")) if has_facing(node) else fallback


## `node`'s facing yaw, or its body's rotation when it doesn't report one.
static func yaw(node: Node3D) -> float:
	return yaw_or(node, node.rotation.y)
