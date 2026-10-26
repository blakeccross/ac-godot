extends StaticBody3D

## Counter hull + talk sensor (`talk_distance` 85 GX). Forwards Talk to Pelly/Phyllis.


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("post_set")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var girl: PostGirl = _post_girl()
	if girl != null:
		return girl.get_interactions(_ctx)
	return [Interaction.of(Interaction.TALK, "Talk to clerk", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	var girl: PostGirl = _post_girl()
	if girl != null:
		return girl.begin_talk(ctx)
	return false


func _post_girl() -> PostGirl:
	var parent: Node = get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PostGirl") as PostGirl

