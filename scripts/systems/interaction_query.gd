class_name InteractionQuery
extends RefCounted

## Resolves a facing probe to a host that implements get_interactions / interact.
## Not an autoload. The player never type-checks Tree vs Villager vs Item.

var host: Node
var action: Interaction


static func is_host(node: Object) -> bool:
	return (
		node != null
		and node.has_method("get_interactions")
		and node.has_method("interact")
	)


static func host_from(node: Node) -> Node:
	var cursor: Node = node
	while cursor != null:
		if is_host(cursor):
			return cursor
		cursor = cursor.get_parent()
	return null


static func best_in_areas(
	areas: Array, face_pt: Vector3, ctx: InteractionContext
) -> InteractionQuery:
	var best: InteractionQuery = null
	var best_d := INF
	for entry: Variant in areas:
		if not (entry is Area3D):
			continue
		var source: Node = host_from(entry as Area3D)
		if source == null:
			continue
		var offered: Array[Interaction] = []
		var raw: Variant = source.get_interactions(ctx)
		if raw is Array:
			offered.assign(raw)
		var action: Interaction = Interaction.primary(offered)
		if action == null:
			continue
		var d: float = face_pt.distance_squared_to((entry as Area3D).global_position)
		if d < best_d:
			best_d = d
			best = InteractionQuery.new()
			best.host = source
			best.action = action
	return best
