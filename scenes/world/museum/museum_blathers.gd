extends StaticBody3D

## Blathers in the museum entrance (`ac_npc_curator`). Wait anim + talk/donate.

const ANIM_WAIT := "npc_1_wait1"
const GREETING_ID := &"blathers_greeting"

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("museum_set")
	collision_layer = 1
	collision_mask = 0
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
		if ui != null and ui.has_method("is_uttering"):
			uttering = bool(ui.call("is_uttering"))
	_face.tick(delta, uttering)
	if _talking:
		_face_player()


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	var out: Array[Interaction] = [Interaction.of(Interaction.TALK, "Talk to Blathers", 20)]
	var item: ItemData = _selected_item(ctx)
	if item != null and Game != null and Game.museum != null:
		match Game.museum.display_info_for_item(item):
			MuseumBook.DisplayInfo.CAN_DONATE:
				out.append(
					Interaction.of(Interaction.DONATE, "Donate %s" % item.display_name, 25)
				)
			_:
				pass
	return out


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or Game == null:
		return false
	match action.id:
		Interaction.TALK:
			return _begin_talk(ctx)
		Interaction.DONATE:
			return _begin_donate(ctx)
		_:
			return false


func _begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	_face_toward(listener.global_position if listener != null else global_position)
	var data: DialogueData = DialogueCatalog.conversation(GREETING_ID)
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Blathers"
	talk_ctx.already_talked = _talked_today
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and data != null and ui.has_method("play"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call("play", data, talk_ctx)
	elif ui != null and ui.has_method("say"):
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call(
			"say",
			"Hoo — welcome to the museum. Bring me fossils, art, fish, or bugs!",
			"Blathers"
		)
	else:
		Game.post_notice("Blathers: Hoo — welcome to the museum!")
	_talked_today = true
	return true


func _begin_donate(ctx: InteractionContext) -> bool:
	var item: ItemData = _selected_item(ctx)
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	if item == null:
		Game.post_notice("Select something in your pockets first.")
		return true
	var msg: String = Game.donate_to_museum(item.id)
	_face_toward(listener.global_position if listener != null else global_position)
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_method("say"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call("say", msg, "Blathers")
	else:
		Game.post_notice(msg)
	return true


func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	## Decomp `Camera2_request_main_talk(play, player, npc)` — speaker = player.
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	_play_clip(ANIM_WAIT, true)


func _bind_talk_end(ui: Node) -> void:
	if ui == null or not ui.has_signal("closed"):
		return
	if ui.closed.is_connected(_on_talk_closed):
		ui.closed.disconnect(_on_talk_closed)
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)


func _on_talk_closed() -> void:
	_talking = false
	TalkCamera.end(get_tree())
	_play_clip(ANIM_WAIT, true)


func _face_player() -> void:
	if get_tree() == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_face_toward((player as Node3D).global_position)


func _face_toward(world_pos: Vector3) -> void:
	var to: Vector3 = world_pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var yaw: float = atan2(to.x, to.z)
	if _model != null:
		_model.rotation.y = yaw
	else:
		rotation.y = yaw


func _selected_item(ctx: InteractionContext) -> ItemData:
	var inv: Inventory = ctx.inventory if ctx != null and ctx.inventory != null else Game.inventory
	if inv == null:
		return null
	var slot: InventorySlot = inv.selected_slot()
	if slot == null or slot.is_empty():
		return null
	return ItemCatalog.get_item(slot.item.item_id)


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
	var vis: Node3D = GeneratedVisual.attach_villager(_model, &"owl")
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.42, 0.28)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = GeneratedVisual.find_animation_player(vis)
	_face.bind(vis, &"owl")
	_play_clip(ANIM_WAIT, true)


func _play_clip(suffix: String, loop: bool) -> void:
	if _body_anim == null:
		return
	var clip := _resolve_clip(suffix)
	if clip.is_empty():
		return
	if clip == _clip and _body_anim.is_playing():
		return
	_clip = clip
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_body_anim.speed_scale = 1.0
	_body_anim.play(clip, 0.12)


func _resolve_clip(suffix: String) -> String:
	if _body_anim == null or suffix.is_empty():
		return ""
	if _body_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _body_anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
