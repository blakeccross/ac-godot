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
	## A line already out replaces the cast verb, and survives the player turning away.
	if tool.field_verb == Interaction.CAST and Fishing.is_active():
		return Fishing.field_action()
	if not _field_ok(tool, ctx):
		return null
	var prompt: String = tool.field_prompt
	if prompt.is_empty():
		prompt = tool.display_name
	## The cast is the one field verb whose effect lands mid-swing rather than after it.
	var effect_frame: float = -1.0
	if tool.field_verb == Interaction.CAST:
		effect_frame = Fishing.CAST_RELEASE_FRAME
	elif tool.field_verb == Interaction.SWING_NET:
		effect_frame = Netting.SWING_CATCH_FRAME
	return Interaction.of(
		tool.field_verb, prompt, tool.field_priority, tool.field_anim, effect_frame
	)


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
	if tool.field_verb == Interaction.CAST:
		return _apply_rod(tool, action, ctx)
	if tool.field_verb == Interaction.SWING_NET:
		return _apply_net(tool, action, ctx)
	if action.id != tool.field_verb:
		return false
	if not _field_ok(tool, ctx):
		return false
	if tool.field_require == ToolData.FieldRequire.EMPTY_GROUND:
		if not HoleUse.dig(ctx, facing_cell(ctx)):
			return false
	if tool.field_notice != "" and tool.field_verb != Interaction.SWING_NET:
		Game.post_notice(tool.field_notice)
	_scare_fish(ctx)
	_stress_bugs(ctx)
	return true


## `mPlib_Check_HitAxe` / `_StopNet` / `_HitScoop`: a swung tool sends nearby fish off. The
## rod returns early above, so casting never scares the fish you are casting at.
static func _scare_fish(ctx: InteractionContext) -> void:
	var school: FishSchool = Fishing.school_of(ctx)
	if school != null:
		school.notify_tool_swing()


static func _stress_bugs(ctx: InteractionContext) -> void:
	var field: BugField = Netting.field_of(ctx)
	if field != null:
		field.notify_tool_swing()


static func _apply_net(tool: ToolData, action: Interaction, ctx: InteractionContext) -> bool:
	if action.id != tool.field_verb or not _field_ok(tool, ctx):
		return false
	_scare_fish(ctx)
	_stress_bugs(ctx)
	var origin: Vector3 = ctx.actor.global_position if ctx != null and ctx.actor != null else Vector3.ZERO
	var yaw: float = 0.0
	if ctx != null and ctx.actor != null and ctx.actor.has_method("facing_yaw"):
		yaw = float(ctx.actor.call("facing_yaw"))
	var direction := Vector3(sin(yaw), 0.0, cos(yaw))
	var out: Netting.Outcome = Netting.swing(ctx, origin, direction)
	if out.missed:
		Game.post_notice("You swung the net, but didn't catch anything!")
	elif out.pockets_full:
		Game.post_notice("Your pockets are full!")
	return true


static func _apply_rod(tool: ToolData, action: Interaction, ctx: InteractionContext) -> bool:
	if Fishing.is_active():
		if action.id != Interaction.HOOK:
			return false
		Fishing.hook(ctx, Fishing.school_of(ctx))
		return true
	if action.id != tool.field_verb or not _field_ok(tool, ctx):
		return false
	if not Fishing.cast(ctx, cast_point(ctx)):
		return false
	if tool.field_notice != "":
		Game.post_notice(tool.field_notice)
	return true


static func facing_cell(ctx: InteractionContext) -> Vector2i:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or ctx == null or ctx.actor == null:
		return Vector2i(-1, -1)
	return grid.world_to_cell(_facing_point(ctx, grid.cell_size))


## `m_player_main_ready_rod`: the landing spot is a fixed `Fishing.CAST_METERS` along the
## player's facing. Not the cell in front of them — the rod outreaches a cell by a long way.
static func cast_point(ctx: InteractionContext) -> Vector3:
	if ctx == null or ctx.actor == null:
		return Vector3.ZERO
	return _facing_point(ctx, Fishing.CAST_METERS)


static func _field_ok(tool: ToolData, ctx: InteractionContext) -> bool:
	match tool.field_require:
		ToolData.FieldRequire.WATER:
			return _cast_water_ok(ctx)
		ToolData.FieldRequire.EMPTY_GROUND:
			return _facing_empty_ground(ctx)
		_:
			return true


## `Player_actor_request_proc_index_fromReady_rod` probes the landing spot plus four corners
## at ±10 GX and needs every one to be water, so you cannot drop the bobber onto a spit of
## land or straddle the far bank. `FieldRequire.WATER` is the rod's alone; a tool that wants
## water in the cell it is standing next to should ask for its own requirement.
static func _cast_water_ok(ctx: InteractionContext) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or ctx == null or ctx.actor == null:
		return false
	var centre: Vector3 = cast_point(ctx)
	var d: float = Fishing.CAST_PROBE_METERS
	var probes: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-d, 0.0, d),
		Vector3(d, 0.0, d),
		Vector3(-d, 0.0, -d),
		Vector3(d, 0.0, -d),
	]
	for offset: Vector3 in probes:
		if grid.terrain_at(grid.world_to_cell(centre + offset)) != WorldGrid.Terrain.WATER:
			return false
	return true


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
