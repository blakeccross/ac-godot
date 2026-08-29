class_name PlantData
extends Resource

## Growing plant (tree, flower). Not a pocket item.
## `stage_days` are cumulative 06:00 renews to leave Seed / Growing / Mature.

enum Kind { TREE, FLOWER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.TREE
@export var fruit: ItemData
## Days-since-plant to enter Growing, Mature, Harvestable (4th value unused).
@export var stage_days: PackedInt32Array = PackedInt32Array([1, 3, 5, 7])
@export var needs_water: bool = false
@export var winter_pauses: bool = false
## Empty = grass + soil. Palm uses sand (`WorldGrid.Terrain`).
@export var terrains: PackedInt32Array = PackedInt32Array()
@export var visual_seed: StringName = &""
@export var visual_growing: StringName = &""
@export var visual_mature: StringName = &""
@export var visual_harvestable: StringName = &""
