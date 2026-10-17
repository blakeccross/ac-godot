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


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.DIG:
		return false
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return false
	var world := World.find(get_tree())
	var grid: WorldGrid = world.grid if world != null else null
	if grid == null:
		return false
	var cell: Vector2i = grid.world_to_cell(global_position)
	if not BuriedUse.dig(ctx, cell):
		return false
	## `GET_SCOOP`: the dirt comes up with the find.
	ToolUse.dig_effects(ctx, cell, true)
	await BuriedUse.report(ctx)
	return true


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
