extends StaticBody3D

## Counter hull + talk sensor (`talk_distance` 85 GX). Forwards Talk to Pelly/Phyllis.


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("post_set")
	collision_layer = 1
	collision_mask = 0
	_ensure_interact()


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


func _ensure_interact() -> void:
	if get_node_or_null("InteractVolume") != null:
		return
	var volume := Area3D.new()
	volume.name = "InteractVolume"
	volume.collision_layer = 8
	volume.collision_mask = 0
	volume.monitoring = false
	volume.monitorable = true
	volume.set_script(load("res://scenes/world/interact_volume.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	## Cover the lobby side of the counter so Talk hits the desk, not the clerk.
	box.size = Vector3(5.2, 2.2, 2.4)
	shape.shape = box
	shape.position = Vector3(0.0, 0.2, 0.9)
	volume.add_child(shape)
	add_child(volume)
