class_name ToolUse
extends RefCounted

## Equipped-tool lookup and empty-tile field verbs. Not an autoload.
## Hosts ask `has(ctx, kind)`; the player never switches on Shovel vs Axe.

static func equipped(ctx: InteractionContext) -> ToolData:
	if ctx == null or ctx.inventory == null:
		return null
	var data: ItemData = ItemCatalog.get_item(ctx.inventory.equipment_id)
	return data as ToolData


static func kind(ctx: InteractionContext) -> ToolData.Kind:
	var tool: ToolData = equipped(ctx)
	if tool == null:
		return ToolData.Kind.NONE
	return tool.kind


static func has(ctx: InteractionContext, want: ToolData.Kind) -> bool:
	return kind(ctx) == want


static func field_action(ctx: InteractionContext) -> Interaction:
	var tool: ToolData = equipped(ctx)
	if tool == null or tool.field_verb == &"":
		return null
	if not _field_ok(tool, ctx):
		return null
	var prompt: String = tool.field_prompt
	if prompt.is_empty():
		prompt = tool.display_name
	return Interaction.of(tool.field_verb, prompt, tool.field_priority, tool.field_anim)


## Prefer a higher-priority field verb (net swing, rod cast) over a weaker host.
static func resolve(hit: InteractionQuery, ctx: InteractionContext) -> InteractionQuery:
	var field: Interaction = field_action(ctx)
	if field == null:
		return hit
	if hit == null or hit.action == null or field.priority > hit.action.priority:
		var query := InteractionQuery.new()
		query.host = null
		query.action = field
		return query
	return hit


static func apply_field(action: Interaction, ctx: InteractionContext) -> bool:
	var tool: ToolData = equipped(ctx)
	if tool == null or action == null:
		return false
	if action.id != tool.field_verb:
		return false
	if not _field_ok(tool, ctx):
		return false
	if tool.field_require == ToolData.FieldRequire.EMPTY_GROUND:
		if not HoleUse.dig(ctx, facing_cell(ctx)):
			return false
	if tool.field_notice != "":
		Game.post_notice(tool.field_notice)
	return true


static func facing_cell(ctx: InteractionContext) -> Vector2i:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or ctx == null or ctx.actor == null:
		return Vector2i(-1, -1)
	return grid.world_to_cell(_facing_point(ctx, grid.cell_size))


static func _field_ok(tool: ToolData, ctx: InteractionContext) -> bool:
	match tool.field_require:
		ToolData.FieldRequire.WATER:
			return _facing_water(ctx)
		ToolData.FieldRequire.EMPTY_GROUND:
			return _facing_empty_ground(ctx)
		_:
			return true


static func _facing_water(ctx: InteractionContext) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null:
		return false
	return grid.terrain_at(facing_cell(ctx)) == WorldGrid.Terrain.WATER


static func _facing_empty_ground(ctx: InteractionContext) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null:
		return false
	var cell: Vector2i = facing_cell(ctx)
	var terrain: WorldGrid.Terrain = grid.terrain_at(cell)
	if (
		terrain != WorldGrid.Terrain.GRASS
		and terrain != WorldGrid.Terrain.SOIL
		and terrain != WorldGrid.Terrain.SAND
	):
		return false
	return not grid.is_occupied(cell)


static func _facing_point(ctx: InteractionContext, distance: float) -> Vector3:
	var origin: Vector3 = ctx.actor.global_position
	var yaw: float = 0.0
	if ctx.actor.has_method("facing_yaw"):
		yaw = float(ctx.actor.call("facing_yaw"))
	return origin + Vector3(sin(yaw), 0.0, cos(yaw)) * distance


static func _grid(ctx: InteractionContext) -> WorldGrid:
	if ctx == null or ctx.world == null:
		return null
	var value: Variant = ctx.world.get("grid")
	return value as WorldGrid
