extends StaticBody3D

## Museum plaque. Lists donated species in its group (`Museum_*_Set_Msg*Info`).

@export var label: String = "Exhibit"
var _lines: PackedStringArray = PackedStringArray()


func setup(p_label: String, lines: PackedStringArray) -> void:
	label = p_label
	_lines = lines
	name = "Plaque_%s" % p_label.replace(" ", "_")


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("museum_set")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var action := Interaction.new()
	action.id = Interaction.TALK
	action.prompt = "Read %s" % label
	action.priority = 20
	return [action]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	if _lines.is_empty():
		Game.post_notice("This exhibit is empty.")
		return true
	Game.post_notice("%s\n%s" % [label, "\n".join(_lines)])
	return true
