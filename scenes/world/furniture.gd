extends StaticBody3D

## Placed furniture. Sit, or pick up / rotate when the room allows decorating.

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
	if _collision != null and _collision.shape is BoxShape3D:
		(_collision.shape as BoxShape3D).size = Vector3(w, 0.8, d)
		_collision.position.y = 0.4
		_collision.disabled = data != null and not data.blocks_walk
	if _mesh != null and _mesh.mesh is BoxMesh:
		(_mesh.mesh as BoxMesh).size = Vector3(w * 0.7, 0.7, d * 0.7)
		_mesh.position.y = 0.35
	collision_layer = 1 if data == null or data.blocks_walk else 0


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var actions: Array[Interaction] = []
	var label: String = data.display_name if data else "Furniture"
	var sittable: bool = data == null or data.can_sit
	if sittable:
		actions.append(Interaction.of(Interaction.SIT, "Sit on %s" % label, 8))
	if Game.is_decorating():
		if data == null or not data.can_sit:
			actions.append(Interaction.of(Interaction.PICK_UP, "Pick up %s" % label, 8))
		actions.append(Interaction.of(Interaction.ROTATE, "Rotate %s" % label, 6))
	return actions


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if action.id == Interaction.SIT:
		Game.post_notice("You sit down.")
		return true
	if action.id == Interaction.PICK_UP:
		return Game.pick_up_furniture(occupant_id)
	if action.id == Interaction.ROTATE:
		return Game.rotate_furniture(occupant_id)
	return false
