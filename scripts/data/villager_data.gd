class_name VillagerData
extends Resource

## Definition of a villager. Runtime actors instance a scene and point here.

@export var id: StringName = &""
@export var display_name: String = ""
@export var species: StringName = &""
@export var catchphrase: String = ""
@export var schedule: ScheduleData
