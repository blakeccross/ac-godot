extends StaticBody3D

## e-Reader Transfer Machine (`ac_pterminal` / left side of the post office).

var _busy: bool = false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("post_set")
	collision_layer = 1
	collision_mask = 0
	_ensure_collision()
	_ensure_interact()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Use e-Reader Transfer Machine", 18)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null or _busy:
		return false
	return _begin_use(ctx)


func _begin_use(ctx: InteractionContext) -> bool:
	var data: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % PostDisplay.PTERMINAL_MSG)
	)
	if data == null:
		Game.post_notice("The e-Reader Transfer Machine is quiet.")
		return true
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = ""
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui == null or not ui.has_method("play"):
		Game.post_notice("Welcome. Thank you for using the e-Reader Transfer Machine.")
		return true
	if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
		ui.call("close")
	_busy = true
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	if ui.has_signal("event_fired") and not ui.is_connected("event_fired", _on_dialogue_event):
		ui.connect("event_fired", _on_dialogue_event)
	if ui.has_signal("closed"):
		if ui.is_connected("closed", _on_closed):
			ui.disconnect("closed", _on_closed)
		ui.connect("closed", _on_closed, CONNECT_ONE_SHOT)
	ui.call("play", data, talk_ctx)
	return true


func _on_dialogue_event(event: Dictionary) -> void:
	## Connect wait (`demo_order` slot 9) → exact “GBA not connected” bank lines.
	if str(event.get("op", "")) != "demo_order":
		return
	if int(event.get("slot", -1)) != 9:
		return
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui == null or not ui.has_method("runner"):
		return
	var runner: Variant = ui.call("runner")
	if runner == null or not (runner is DialogueRunner):
		return
	var conv: DialogueData = (runner as DialogueRunner).conversation
	if conv == null or not PostDisplay.is_etm_connect_msg(conv.id):
		return
	var fail: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % PostDisplay.PTERMINAL_NO_GBA_MSG)
	)
	if fail != null:
		(runner as DialogueRunner).jump_to(fail.id)


func _on_closed() -> void:
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_signal("event_fired") and ui.is_connected("event_fired", _on_dialogue_event):
		ui.disconnect("event_fired", _on_dialogue_event)
	_busy = false
	TalkCamera.end(get_tree())


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var half: Vector3 = PostDisplay.PTERMINAL_HALF_GX * FieldCatalog.GX_TO_METERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	shape.shape = box
	shape.position = Vector3(0.0, half.y, 0.0)
	add_child(shape)


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
	box.size = Vector3(2.0, 2.2, 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.4)
	volume.add_child(shape)
	add_child(volume)
