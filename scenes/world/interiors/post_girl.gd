extends StaticBody3D

## Pelly / Phyllis at the post desk (`ac_npc_post_girl` / `SP_NPC_POST_GIRL` / `POST_GIRL2`).

const ANIM_WAIT := "npc_1_wait1"

enum Pending { NONE, BANK, SEND, SAVE, REPAY }

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
var _species: StringName = PostDisplay.PELLY_SPECIES
var _pending: Pending = Pending.NONE
var _active_ui: Node = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("post_set")
	collision_layer = 1
	collision_mask = 0
	_species = PostDisplay.post_girl_species()
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
	var name: String = PostDisplay.post_girl_name(_species)
	return [Interaction.of(Interaction.TALK, "Talk to %s" % name, 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null:
		return false
	return begin_talk(ctx)


## Desk and clerk share this entry (`talk_distance` 85 GX across the counter).
func begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	_face_toward(listener.global_position if listener != null else global_position)
	var speaker: String = PostDisplay.post_girl_name(_species)
	var desk_full: bool = Game.post != null and Game.post.is_desk_full()
	var data: DialogueData = PostDisplay.talk_conversation(_species, desk_full)
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = speaker
	talk_ctx.already_talked = _talked_today
	PostUse.fill_bank_frees(talk_ctx)
	_pending = Pending.NONE
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and data != null and ui.has_method("play"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(listener)
		_bind_talk_session(ui)
		ui.call("play", data, talk_ctx)
	elif ui != null and ui.has_method("say"):
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call("say", _greeting_line(), speaker)
	else:
		Game.post_notice("%s: %s" % [speaker, _greeting_line()])
	_talked_today = true
	return true


func _greeting_line() -> String:
	if Game != null and Game.post != null and Game.post.is_desk_full():
		return "The desk is full — we'll deliver as soon as we can!"
	if _species == PostDisplay.PHYLLIS_SPECIES:
		return "Mmm... huh?\nWel-come!"
	return "Welcome!\nHow can I help you?"


func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	_play_clip(ANIM_WAIT, true)


func _bind_talk_session(ui: Node) -> void:
	_active_ui = ui
	if ui == null:
		return
	if ui.has_signal("event_fired") and not ui.is_connected("event_fired", _on_dialogue_event):
		ui.connect("event_fired", _on_dialogue_event)
	if ui.has_signal("closed"):
		if ui.is_connected("closed", _on_talk_closed):
			ui.disconnect("closed", _on_talk_closed)
		ui.connect("closed", _on_talk_closed, CONNECT_ONE_SHOT)
	## `close()` nulls the runner before `closed` — capture pending action on finish.
	if ui.has_method("runner"):
		var runner: Variant = ui.call("runner")
		if runner is DialogueRunner:
			var r: DialogueRunner = runner as DialogueRunner
			if not r.finished.is_connected(_on_runner_finished):
				r.finished.connect(_on_runner_finished, CONNECT_ONE_SHOT)
			if not r.line_shown.is_connected(_on_line_shown):
				r.line_shown.connect(_on_line_shown)


func _on_line_shown(_text: String) -> void:
	_note_pending_from_runner()


func _on_dialogue_event(_event: Dictionary) -> void:
	_note_pending_from_runner()


func _on_runner_finished() -> void:
	_note_pending_from_runner()
	if _active_ui != null and _active_ui.has_method("runner"):
		var runner: Variant = _active_ui.call("runner")
		if runner is DialogueRunner:
			var r: DialogueRunner = runner as DialogueRunner
			if r.line_shown.is_connected(_on_line_shown):
				r.line_shown.disconnect(_on_line_shown)


func _bind_talk_end(ui: Node) -> void:
	if ui == null or not ui.has_signal("closed"):
		return
	if ui.is_connected("closed", _on_talk_closed):
		return
	ui.connect("closed", _on_talk_closed, CONNECT_ONE_SHOT)


func _note_pending_from_runner() -> void:
	if _active_ui == null or not _active_ui.has_method("runner"):
		return
	var runner: Variant = _active_ui.call("runner")
	if runner == null or not (runner is DialogueRunner):
		return
	var conv: DialogueData = (runner as DialogueRunner).conversation
	if conv == null:
		return
	var node_id: StringName = (runner as DialogueRunner).node_id
	if PostDisplay.is_deposit_msg(conv.id) or PostDisplay.is_deposit_msg(node_id):
		_pending = Pending.BANK
	elif PostDisplay.is_send_mail_msg(conv.id) or PostDisplay.is_send_mail_msg(node_id):
		_pending = Pending.SEND
	elif PostDisplay.is_save_mail_msg(conv.id) or PostDisplay.is_save_mail_msg(node_id):
		_pending = Pending.SAVE
	elif PostDisplay.is_repay_msg(conv.id) or PostDisplay.is_repay_msg(node_id):
		_pending = Pending.REPAY


func _on_talk_closed() -> void:
	_note_pending_from_runner()
	if _active_ui != null and _active_ui.has_signal("event_fired"):
		if _active_ui.is_connected("event_fired", _on_dialogue_event):
			_active_ui.disconnect("event_fired", _on_dialogue_event)
	_active_ui = null
	_talking = false
	TalkCamera.end(get_tree())
	var next: Pending = _pending
	_pending = Pending.NONE
	match next:
		Pending.BANK:
			_open_followup(PostUse.bank_menu_conversation(_species))
		Pending.SEND:
			_open_followup(PostUse.send_mail_conversation())
		Pending.SAVE:
			_open_followup(PostUse.save_mail_conversation())
		Pending.REPAY:
			_open_followup(DialogueCatalog.conversation(PostDisplay.REPAY_AMOUNT_ID))
		_:
			pass


func _open_followup(data: DialogueData) -> void:
	if data == null:
		return
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui == null or not ui.has_method("play"):
		return
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = PostDisplay.post_girl_name(_species)
	PostUse.fill_bank_frees(talk_ctx)
	_start_talk_session(get_tree().get_first_node_in_group("player") as Node3D)
	_bind_talk_end(ui)
	ui.call("play", data, talk_ctx)


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
	## Prefer the desk volume in front; keep a small reach if the player is beside her.
	box.size = Vector3(1.2, 2.0, 1.2)
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
	var vis: Node3D = GeneratedVisual.attach_villager(_model, _species)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = (
			Color(0.95, 0.92, 0.85) if _species == PostDisplay.PELLY_SPECIES else Color(0.55, 0.45, 0.55)
		)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = GeneratedVisual.find_animation_player(vis)
	_face.bind(vis, _species)
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
