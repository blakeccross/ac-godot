extends StaticBody3D

## Pelly / Phyllis at the post desk (`ac_npc_post_girl` / `SP_NPC_POST_GIRL` / `POST_GIRL2`).

const ANIM_WAIT := "npc_1_wait1"

enum Pending { NONE, BANK, SEND, SAVE, REPAY, FARWAY }

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
var _species: StringName = PostDisplay.PELLY_SPECIES
var _pending: Pending = Pending.NONE
var _active_ui: DialogueOverlay = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("post_set")
	_species = PostDisplay.post_girl_species()
	_ensure_visual()


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
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
	## `aPG_set_talk_info`: April Fools' Day's trick instead of the counter.
	var trick: DialogueData = AprilFools.conversation(&"phyllis" if _species == PostDisplay.PHYLLIS_SPECIES else &"pelly")
	if trick != null:
		data = trick
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = speaker
	talk_ctx.already_talked = _talked_today
	PostUse.fill_bank_frees(talk_ctx)
	_pending = Pending.NONE
	var ui := DialogueOverlay.find(get_tree())
	if ui != null and data != null:
		if ui.is_open():
			ui.close()
		_start_talk_session(listener)
		_bind_talk_session(ui)
		ui.play(data, talk_ctx)
	elif ui != null:
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.say(_greeting_line(), speaker)
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


func _bind_talk_session(ui: DialogueOverlay) -> void:
	_active_ui = ui
	if ui == null:
		return
	if not ui.event_fired.is_connected(_on_dialogue_event):
		ui.event_fired.connect(_on_dialogue_event)
	if ui.closed.is_connected(_on_talk_closed):
		ui.closed.disconnect(_on_talk_closed)
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)
	## `close()` nulls the runner before `closed` — capture pending action on finish.
	var runner: Variant = ui.runner()
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
	if _active_ui != null:
		var runner: Variant = _active_ui.runner()
		if runner is DialogueRunner:
			var r: DialogueRunner = runner as DialogueRunner
			if r.line_shown.is_connected(_on_line_shown):
				r.line_shown.disconnect(_on_line_shown)


func _bind_talk_end(ui: DialogueOverlay) -> void:
	if ui == null:
		return
	if ui.closed.is_connected(_on_talk_closed):
		return
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)


func _note_pending_from_runner() -> void:
	if _active_ui == null:
		return
	var runner: Variant = _active_ui.runner()
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
	elif conv.id == &"post_farway" or node_id == &"farway":
		_pending = Pending.FARWAY


func _on_talk_closed() -> void:
	_note_pending_from_runner()
	if _active_ui != null:
		if _active_ui.event_fired.is_connected(_on_dialogue_event):
			_active_ui.event_fired.disconnect(_on_dialogue_event)
	_active_ui = null
	_talking = false
	TalkCamera.end(get_tree())
	var next: Pending = _pending
	_pending = Pending.NONE
	match next:
		Pending.BANK:
			_open_bank()
		Pending.SEND:
			_open_followup(PostUse.send_mail_conversation())
		Pending.SAVE:
			_open_followup(PostUse.save_mail_conversation())
		Pending.REPAY:
			_open_followup(DialogueCatalog.conversation(PostDisplay.REPAY_AMOUNT_ID))
		Pending.FARWAY:
			_open_followup(PostUse.farway_send_conversation())
		_:
			pass


## `aPG_deposit_menu_close_wait`: the ABD opens; once it closes she reads out the balance
## (0x2DE2 + draw type, `{free3}`). Without the terminal the authored menu stands in.
func _open_bank() -> void:
	var bank: BankOverlay = BankOverlay.find(get_tree())
	if bank == null:
		_open_followup(PostUse.bank_menu_conversation(_species))
		return
	bank.connect("closed", func(_committed: bool) -> void:
		var after: DialogueData = DialogueCatalog.conversation(
			StringName("msg_%d" % (PostUse.BANK_AFTER_MSG + PostDisplay.draw_type(_species))))
		if after != null:
			_open_followup(after), CONNECT_ONE_SHOT)
	bank.open()


func _open_followup(data: DialogueData) -> void:
	if data == null:
		return
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		return
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = PostDisplay.post_girl_name(_species)
	PostUse.fill_bank_frees(talk_ctx)
	_start_talk_session(Player.find(get_tree()))
	_bind_talk_end(ui)
	ui.play(data, talk_ctx)


func _face_player() -> void:
	var player := Player.find(get_tree())
	if player is Node3D:
		_face_toward((player as Node3D).global_position)


func _face_toward(target: Vector3) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		rotation.y = atan2(to.x, to.z)


func _ensure_visual() -> void:
	if _model != null:
		return
	_model = $Model
	var vis: Node3D = GeneratedVisual.attach_villager(_model, _species)
	($Model/Placeholder as Node3D).visible = vis == null
	if vis == null:
		(($Model/Placeholder as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = (
			Color(0.95, 0.92, 0.85) if _species == PostDisplay.PELLY_SPECIES else Color(0.55, 0.45, 0.55)
		)
		return
	_body_anim = VisualAnimation.find_animation_player(vis)
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
