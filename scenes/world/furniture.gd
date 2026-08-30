extends StaticBody3D

## Placed furniture. Verbs come from `FurnitureData` via `FurnitureUse`.

@export var data: FurnitureData
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"int_sum_chair01"
@export var cloth_index: int = -1

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	add_to_group("interactable")
	if data != null and data.visual_id != &"":
		visual_id = data.visual_id
	GeneratedVisual.attach(self, visual_id)
	if cloth_index >= 0:
		GeneratedVisual.apply_cloth(self, cloth_index)
	apply_footprint(2.0)
	apply_grid_yaw(grid_facing)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	grid_facing = facing
	rotation.y = WorldGrid.yaw_for_furniture(facing)


func apply_footprint(cell_size: float) -> void:
	var w: float = maxf(float(maxi(footprint.x, 1)) * cell_size * 0.85, 0.4)
	var d: float = maxf(float(maxi(footprint.y, 1)) * cell_size * 0.85, 0.4)
	var blocks: bool = data == null or data.blocks_walk
	if _collision != null and _collision.shape is BoxShape3D:
		(_collision.shape as BoxShape3D).size = Vector3(w, 0.8, d)
		_collision.position.y = 0.4
		_collision.disabled = not blocks
	if _mesh != null and _mesh.mesh is BoxMesh:
		(_mesh.mesh as BoxMesh).size = Vector3(w * 0.7, 0.7, d * 0.7)
		_mesh.position.y = 0.35
	collision_layer = 1 if blocks else 0


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	return FurnitureUse.actions(self, ctx)


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	return FurnitureUse.apply(action, self, ctx)
