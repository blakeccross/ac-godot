class_name InteractionQuery
extends RefCounted

## What A will do: the facing probe's best `InteractVolume` and its chosen action, or a
## field action with no host (`ToolUse.pick`). Not an autoload. The player never
## type-checks Tree vs Villager vs Item: every host speaks through its volume.

## The actor the action is on (`volume.host`), or null for a field action.
var host: Node
var volume: InteractVolume
var action: Interaction


## `action` on the host behind `volume` (a tapped piece of furniture, say).
static func on(p_volume: InteractVolume, p_action: Interaction) -> InteractionQuery:
	var query := InteractionQuery.new()
	query.volume = p_volume
	query.host = p_volume.host if p_volume != null else null
	query.action = p_action
	return query


## The nearest volume among `areas` with something to offer, and its primary action.
static func best_in_areas(
	areas: Array, face_pt: Vector3, ctx: InteractionContext
) -> InteractionQuery:
	var best: InteractionQuery = null
	var best_d := INF
	for entry: Variant in areas:
		var volume := entry as InteractVolume
		if volume == null or volume.host == null:
			continue
		var action: Interaction = Interaction.primary(volume.offers(ctx))
		if action == null:
			continue
		var d: float = face_pt.distance_squared_to(volume.global_position)
		if d < best_d:
			best_d = d
			best = on(volume, action)
	return best


## Carry the action out on its host. Awaitable; false when nothing took it.
func run(ctx: InteractionContext) -> bool:
	if volume == null or action == null:
		return false
	return await volume.activate(action, ctx)
