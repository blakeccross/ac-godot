extends StaticBody3D

## Counter hull + talk sensor (`talk_distance` 85 GX). Forwards Talk to Pelly/Phyllis.


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("post_set")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var girl: Node = _post_girl()
	if girl != null and girl.has_method("get_interactions"):
		return girl.call("get_interactions", _ctx) as Array[Interaction]
	return [Interaction.of(Interaction.TALK, "Talk to clerk", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	var girl: Node = _post_girl()
	if girl != null and girl.has_method("begin_talk"):
		return bool(girl.call("begin_talk", ctx))
	if girl != null and girl.has_method("interact"):
		return bool(girl.call("interact", action, ctx))
	return false


func _post_girl() -> Node:
	var parent: Node = get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PostGirl")

