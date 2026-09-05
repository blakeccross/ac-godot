extends StaticBody3D

## Booker in the police box (`ac_npc_police2` / `SP_NPC_POLICE2`).

const ANIM_WAIT := "npc_1_wait1"
const GREETING_ID := &"booker_greeting"

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
## Slot the player asked about (`aPOL2` item_idx).
var _pending_slot: int = -1


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("police_set")
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


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Talk to Booker", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or Game == null:
		return false
	match action.id:
		Interaction.TALK:
			return _begin_talk(ctx, -1)
		Interaction.TAKE:
			return _begin_talk(ctx, int(action.get_meta("slot", -1)) if action.has_meta("slot") else -1)
		_:
			return false


## Claim flow when the player faces a lost-and-found RSV cell (`aPOL2_message_ctrl`).
func begin_claim(slot: int, ctx: InteractionContext) -> bool:
	return _begin_talk(ctx, slot)


func _begin_talk(ctx: InteractionContext, slot: int) -> bool:
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	_face_toward(listener.global_position if listener != null else global_position)
	_pending_slot = slot
	var line: String = _talk_line(slot)
	var data: DialogueData = DialogueCatalog.conversation(GREETING_ID)
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Booker"
	talk_ctx.already_talked = _talked_today
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if slot >= 0:
		## Confirm claim (`aPOL2_check_answer` CHOICE0).
		_start_talk_session(listener)
		if ui != null and ui.has_method("say"):
			_bind_talk_end(ui)
			ui.call("say", line, "Booker")
			_try_claim(slot)
		else:
			Game.post_notice("Booker: %s" % line)
			_try_claim(slot)
			_on_talk_closed()
		_talked_today = true
		return true
	if ui != null and data != null and ui.has_method("play"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call("play", data, talk_ctx)
	elif ui != null and ui.has_method("say"):
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call("say", line, "Booker")
	else:
		Game.post_notice("Booker: %s" % line)
	_talked_today = true
	return true


func _talk_line(slot: int) -> String:
	if Game == null or Game.police == null:
		return "Welcome to the police station."
	Game.police.ensure_init()
	if slot >= 0:
		var item_id: StringName = Game.police.item_at(slot)
		var data: ItemData = ItemCatalog.get_item(item_id)
		var label: String = data.display_name if data != null else "that"
		return "Is this %s yours? Here you go." % label
	if Game.police.keep_item_sum() == 0:
		return "The lost and found is empty today."
	return "Look around the lost and found — face an item and talk to me if it's yours."


func _try_claim(slot: int) -> void:
	if Game == null or Game.police == null or Game.inventory == null:
		return
	var msg: String = Game.police.claim(slot, Game.inventory)
	Game.post_notice(msg)
	Game.call_deferred("refresh_police_set")


func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	_play_clip(ANIM_WAIT, true)


func _bind_talk_end(ui: Node) -> void:
	if ui == null or not ui.has_signal("closed"):
		return
	if ui.is_connected("closed", _on_talk_closed):
		return
	ui.connect("closed", _on_talk_closed, CONNECT_ONE_SHOT)


func _on_talk_closed() -> void:
	_talking = false
	_pending_slot = -1
	TalkCamera.end(get_tree())


func _face_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
	if player is Node3D:
		_face_toward((player as Node3D).global_position)


func _face_toward(target: Vector3) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		rotation.y = atan2(to.x, to.z)


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
	var vis: Node3D = GeneratedVisual.attach_villager(_model, PoliceDisplay.BOOKER_SPECIES)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.45, 0.7)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = GeneratedVisual.find_animation_player(vis)
	_face.bind(vis, PoliceDisplay.BOOKER_SPECIES)
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
