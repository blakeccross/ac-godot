class_name BuildingPlacement
extends Resource

## One building on the cell grid. Kind is resolved by WorldBuilder.

@export var id: StringName = &""
@export var kind: StringName = &"house"
@export var cell: Vector2i = Vector2i.ZERO
@export var footprint: Vector2i = Vector2i(2, 2)
@export var facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
## Visual yaw only. Occupancy stays `facing` (axis-aligned). House/shop GLBs already bake joint-0.
@export var mesh_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
## Decomp `actor_ct` shift from the occupancy footprint center, in cells (`±20` GX = `±0.5`).
## Station is 1×1 on the FG unit, so this is the shift from the unit center.
@export var actor_shift: Vector2 = Vector2.ZERO
@export var occupy_grid: bool = true
@export var visual_id: StringName = &""
## Display name for generic `building` kind (Museum, Able Sisters, …).
@export var label: String = ""
## Verb the door offers: `enter` or `shop`.
@export var door_verb: StringName = &"enter"
## Villager who lives here. Empty on player / public buildings.
@export var resident_id: StringName = &""
