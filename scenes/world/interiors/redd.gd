extends StaticBody3D

## Crazy Redd in the tent (`ac_npc_black`). Talk, then browse the art if he's open today.

const SHOP_ID := &"broker_shop"

var _model: Node3D
var _talking: bool = false
var _listener: Node3D = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("broker_set")
	collision_layer = 1
	collision_mask = 0
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var out: Array[Interaction] = [Interaction.of(Interaction.TALK, "Talk to Redd", 20)]
	if Game != null and Game.redd != null and Game.redd.is_open_today():
		out.append(Interaction.of(Interaction.BUY, "Browse the art", 22))
	return out


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or Game == null:
		return false
	_listener = ctx.actor as Node3D if ctx != null else _listener
	match action.id:
		Interaction.TALK:
			return _talk()
		Interaction.BUY, Interaction.SHOP:
			return Game.open_shop(SHOP_ID, Interaction.BUY)
		_:
			return false


func _talk() -> bool:
	var open: bool = Game.redd != null and Game.redd.is_open_today()
	var line: String = (
		"Step in, step in. Fine art, cheap prices, no questions. Take a look around."
		if open
		else "Tent's closed, friend. Come back another day."
	)
	_say(line)
	return true


func _say(text: String) -> void:
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_method("say"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		if _listener != null:
			TalkCamera.begin(_listener, self, get_tree())
		if ui.has_signal("closed") and not ui.closed.is_connected(_on_closed):
			ui.closed.connect(_on_closed, CONNECT_ONE_SHOT)
		ui.call("say", text, "Redd")
		_talking = true
	elif Game != null:
		Game.post_notice("Redd: %s" % text)


func _on_closed() -> void:
	_talking = false
	TalkCamera.end(get_tree())


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.8, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.9, 0.0)
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
	box.size = Vector3(1.6, 2.0, 1.6)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	volume.add_child(shape)
	add_child(volume)


func _ensure_visual() -> void:
	if get_node_or_null("Model") != null:
		return
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var vis: Node3D = GeneratedVisual.attach_villager(_model, &"fox")
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.32
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.36, 0.22)
		mesh.material_override = mat
		_model.add_child(mesh)
