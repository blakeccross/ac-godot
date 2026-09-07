extends Node3D

## Buried dig mark: `obj_crack0` X for fossils, golden `ef_anahikari` rays for shine spots.

@export var occupant_id: StringName = &""
@export var persist_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"BURIED_CRACK"
@export var is_shine: bool = false

var _spin: Tween


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("buried")
	_apply_visual()


func refresh_seasonal_visual() -> void:
	_apply_visual()


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return []
	return [Interaction.of(Interaction.DIG, "Dig", 12, &"ply_1_dig1", 21.0)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.DIG:
		return false
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return false
	var world: Node = get_tree().get_first_node_in_group("world") if get_tree() != null else null
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid == null:
		return false
	return BuriedUse.dig(ctx, grid.world_to_cell(global_position))


func _apply_visual() -> void:
	if _spin != null:
		_spin.kill()
		_spin = null
	GeneratedVisual.detach(self)
	var attached: Node3D = GeneratedVisual.attach(self, visual_id)
	if is_shine and attached != null:
		_spin_rays(attached)


func _spin_rays(rays: Node3D) -> void:
	## Approximate `ef_anahikari` EVW scroll with a slow Y spin.
	_spin = create_tween()
	_spin.set_loops()
	_spin.tween_property(rays, "rotation:y", TAU, 4.0).from(0.0)
