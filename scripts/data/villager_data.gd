class_name VillagerData
extends Resource

## Definition of a villager. Runtime actors instance one scene and point here.

@export var id: StringName = &""
@export var display_name: String = ""
@export var species: StringName = &""
@export var catchphrase: String = ""
@export var personality: VillagerPersonality
## Optional override. Empty → personality looks table (`mNPS_schedule[looks]`).
@export var schedule: ScheduleData
@export var dialogue: DialogueData
## New-town eligible (`mNpc_GROW_STARTER`). Move-in-only animals stay out of the starter pick.
@export var starter: bool = true
## Island-only animal (`mNpc_GROW_ISLANDER`). Greeting uses the island hello table.
@export var islander: bool = false
## Interior wallpaper / carpet index (`npc_house_list` / `mRmTp_CopyWallData`).
@export var wall_index: int = 0
@export var floor_index: int = 0
## Outdoor house shape / palette (`ac_house`). Not applied yet.
@export var house_type: int = 0
@export var house_palette: int = 0


func wall_style_id() -> StringName:
	return StringName("wall_%02d" % clampi(wall_index, 0, 70))


func floor_style_id() -> StringName:
	return StringName("floor_%02d" % clampi(floor_index, 0, 70))


func schedule_table() -> ScheduleData:
	if schedule != null:
		return schedule
	if personality != null:
		return personality.schedule_table()
	return null


func walk_speed() -> float:
	if personality != null:
		return personality.walk_speed
	return 1.5


func wander_radius() -> float:
	if personality != null:
		return personality.wander_radius
	return 6.0


func field_activity_ids() -> Array[StringName]:
	if personality != null:
		return personality.field_activity_ids()
	return [ActivityKind.WANDER]


func placeholder_color() -> Color:
	if personality != null:
		return personality.placeholder_color
	return Color(0.85, 0.55, 0.4, 1)
