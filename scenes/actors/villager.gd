extends CharacterBody3D

## Placeholder villager. Offers talk; dialogue UI comes later.

@export var data: VillagerData


func _ready() -> void:
	add_to_group("interactable")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var name: String = data.display_name if data else "Villager"
	return [Interaction.of(Interaction.TALK, "Talk to %s" % name, 20)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	var name: String = data.display_name if data else "Villager"
	var line: String = data.catchphrase if data and data.catchphrase != "" else "Hello!"
	Game.post_notice("%s: %s" % [name, line])
	return true
