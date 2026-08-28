extends CharacterBody3D

## Placeholder villager. Schedule comes from `Clock`; dialogue UI comes later.

@export var data: VillagerData

@onready var _volume: Area3D = $InteractVolume


func _ready() -> void:
	add_to_group("interactable")
	Clock.time_changed.connect(_sync_from_clock)
	var species: StringName = data.species if data else &""
	GeneratedVisual.attach_villager(self, species)
	_sync_from_clock()


func current_activity() -> StringName:
	if data == null or data.schedule == null:
		return &"field"
	return data.schedule.activity_now()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if current_activity() == &"sleep":
		return []
	var name: String = data.display_name if data else "Villager"
	return [Interaction.of(Interaction.TALK, "Talk to %s" % name, 20)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	if current_activity() == &"sleep":
		return false
	var name: String = data.display_name if data else "Villager"
	var line: String = data.catchphrase if data and data.catchphrase != "" else "Hello!"
	Game.post_notice("%s: %s" % [name, line])
	return true


func _sync_from_clock() -> void:
	var sleeping: bool = current_activity() == &"sleep"
	visible = not sleeping
	if _volume != null:
		_volume.monitorable = not sleeping
