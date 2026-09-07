extends StaticBody3D

## Tom Nook in Nook's Cranny (`ac_npc_shop_master` / `SP_NPC_RCN_GUIDE2` during first job).

const ANIM_WAIT := "npc_1_wait1"
const GREETING_ID := &"nook_greeting"

## Prefer bank ids; authored JSON is the no-bank fallback.
const JOB_ARRIVE := &"msg_2030"
const JOB_ARRIVE_FALLBACK := &"nook_job_arrive"
const JOB_UNIFORM := &"msg_2033"
const JOB_UNIFORM_FALLBACK := &"nook_job_uniform"
const JOB_UNIFORM_WAIT := &"msg_2034"
const JOB_UNIFORM_WAIT_FALLBACK := &"nook_job_uniform_wait"
const JOB_UNIFORM_HINT := &"msg_2035"
const JOB_UNIFORM_HINT_FALLBACK := &"nook_job_uniform_hint"
const JOB_UNIFORM_DONE := &"msg_2036"
const JOB_UNIFORM_DONE_FALLBACK := &"nook_job_uniform_done"
const JOB_PLANT := &"msg_2038"
const JOB_PLANT_FALLBACK := &"nook_job_plant"
const JOB_PLANT_DONE := &"msg_2041"
const JOB_PLANT_DONE_FALLBACK := &"nook_job_plant_done"
const JOB_POCKETS_FULL := &"msg_2032"
const JOB_POCKETS_FULL_FALLBACK := &"nook_job_pockets_full"
const JOB_ALREADY_UNIFORM := &"msg_2103"
const JOB_ALREADY_UNIFORM_FALLBACK := &"nook_job_already_uniform"
const JOB_GOODS_BLOCK := &"msg_2076"
const JOB_GOODS_BLOCK_FALLBACK := &"nook_job_goods_block"
const JOB_INTRO := &"nook_job_intro"
const JOB_INTRO_HINT := &"nook_job_intro_hint"
const JOB_INTRO_DONE := &"nook_job_intro_done"
const JOB_FTR := FirstJob.DIALOGUE_FURNITURE
const JOB_FTR_HINT := FirstJob.DIALOGUE_FURNITURE_HINT
const JOB_FTR_DONE := &"nook_job_furniture_done"
const JOB_LETTER := FirstJob.DIALOGUE_LETTER
const JOB_LETTER_HINT := FirstJob.DIALOGUE_LETTER_HINT
const JOB_LETTER_DONE := &"nook_job_letter_done"
const JOB_OPEN := &"nook_job_open"
const JOB_OPEN_HINT := &"nook_job_open_hint"
const JOB_OPEN_DONE := &"nook_job_open_done"
const JOB_CARPET := FirstJob.DIALOGUE_CARPET
const JOB_CARPET_HINT := FirstJob.DIALOGUE_CARPET_HINT
const JOB_CARPET_DONE := &"nook_job_carpet_done"
const JOB_AXE := FirstJob.DIALOGUE_AXE
const JOB_AXE_HINT := FirstJob.DIALOGUE_AXE_HINT
const JOB_AXE_DONE := &"nook_job_axe_done"
const JOB_NOTICE := &"nook_job_notice"
const JOB_NOTICE_HINT := &"nook_job_notice_hint"
const JOB_ALL_DONE := &"nook_job_all_done"

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
var _pending_after: StringName = &""
var _force_greet_queued: bool = false


func _ready() -> void:
	## Not in `shop_set` — restock only clears shelf goods, not the shopkeeper.
	add_to_group("interactable")
	collision_layer = 1
	collision_mask = 0
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()
	call_deferred("_maybe_force_greet")


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
	var out: Array[Interaction] = [Interaction.of(Interaction.TALK, "Talk to Tom Nook", 20)]
	## During first-job chores, goods / buy / sell stay locked (`aNRG2_goods_talk`).
	if Game != null and Game.first_job != null and Game.first_job.is_active():
		return out
	out.append_array(ShopUse.actions(self, ctx))
	return out


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or Game == null:
		return false
	match action.id:
		Interaction.TALK:
			return _begin_talk(ctx)
		Interaction.BUY, Interaction.SELL, Interaction.SHOP:
			if Game.first_job != null and Game.first_job.is_active():
				return _play_job_line(JOB_GOODS_BLOCK, JOB_GOODS_BLOCK_FALLBACK, null, _listener(ctx))
			return ShopUse.apply(action, self, ctx)
		_:
			return false


func _maybe_force_greet() -> void:
	## `aNRG2_think_init` force-talk on first shop visit during FIRSTJOB_START.
	if Game == null or Game.first_job == null or not Game.first_job.is_active():
		return
	if Game.first_job.shop_greeted:
		return
	if _force_greet_queued:
		return
	_force_greet_queued = true
	if get_tree() != null:
		await get_tree().process_frame
		await get_tree().process_frame
	if not is_instance_valid(self):
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null
	var ctx := InteractionContext.new()
	ctx.actor = player
	_begin_talk(ctx)


func _begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = _listener(ctx)
	_face_toward(listener.global_position if listener != null else global_position)
	if Game != null and Game.first_job != null and Game.first_job.is_active():
		return _begin_first_job_talk(listener)
	return _begin_normal_talk(listener)


func _begin_normal_talk(listener: Node3D) -> bool:
	var data: DialogueData = DialogueCatalog.conversation(GREETING_ID)
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
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
		ui.call("say", "Yes, yes — welcome! Look around, and talk to me if you'd like to sell.", "Tom Nook")
	else:
		Game.post_notice("Tom Nook: Yes, yes — welcome!")
	_talked_today = true
	return true


func _begin_first_job_talk(listener: Node3D) -> bool:
	var job: FirstJob = Game.first_job
	_pending_after = &""
	_refresh_passive_progress(job)

	if not job.shop_greeted and job.kind == FirstJob.Kind.START:
		job.shop_greeted = true
		if job.wearing_uniform(Game.cloth_id):
			_pending_after = &"start_plant_from_uniform"
			return _play_job_line(JOB_ALREADY_UNIFORM, JOB_ALREADY_UNIFORM_FALLBACK, null, listener)
		if not job.can_start_change_cloth(Game.inventory):
			return _play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
		_pending_after = &"give_uniform"
		return _play_job_chain(
			[JOB_ARRIVE, JOB_UNIFORM],
			[JOB_ARRIVE_FALLBACK, JOB_UNIFORM_FALLBACK],
			listener
		)

	job.shop_greeted = true

	if job.chore_finished():
		_pending_after = &"advance"
		return _play_job_line(_done_bank_for(job.kind), _done_fallback_for(job.kind), null, listener)

	match job.kind:
		FirstJob.Kind.CHANGE_CLOTH:
			if Game.inventory.count_of(FirstJob.UNIFORM_ID) > 0:
				return _play_job_line(JOB_UNIFORM_HINT, JOB_UNIFORM_HINT_FALLBACK, null, listener)
			if job.can_start_change_cloth(Game.inventory):
				job.give_uniform(Game.inventory)
				return _play_job_line(JOB_UNIFORM, JOB_UNIFORM_FALLBACK, null, listener)
			return _play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
		FirstJob.Kind.PLANT_FLOWER:
			return _play_job_line(JOB_PLANT, JOB_PLANT_FALLBACK, null, listener)
		FirstJob.Kind.INTRODUCTIONS:
			return _play_job_line(&"", JOB_INTRO_HINT, null, listener)
		FirstJob.Kind.DELIVER_FTR:
			return _play_job_line(&"", JOB_FTR_HINT, null, listener)
		FirstJob.Kind.SEND_LETTER, FirstJob.Kind.SEND_LETTER2:
			if Game.inventory.count_of(FirstJob.PAPER_ID) <= 0 and job.can_start_delivery(Game.inventory):
				job.give_paper(Game.inventory)
			return _play_job_line(&"", JOB_LETTER_HINT, null, listener)
		FirstJob.Kind.OPEN:
			return _play_job_line(&"", JOB_OPEN_HINT, null, listener)
		FirstJob.Kind.DELIVER_CARPET:
			return _play_job_line(&"", JOB_CARPET_HINT, null, listener)
		FirstJob.Kind.DELIVER_AXE, FirstJob.Kind.DELIVER_AXE2:
			return _play_job_line(&"", JOB_AXE_HINT, null, listener)
		FirstJob.Kind.POST_NOTICE:
			return _play_job_line(&"", JOB_NOTICE_HINT, null, listener)
		FirstJob.Kind.START:
			if job.wearing_uniform(Game.cloth_id):
				_pending_after = &"start_plant_from_uniform"
				return _play_job_line(JOB_ALREADY_UNIFORM, JOB_ALREADY_UNIFORM_FALLBACK, null, listener)
			if not job.can_start_change_cloth(Game.inventory):
				return _play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
			_pending_after = &"give_uniform"
			return _play_job_line(JOB_UNIFORM, JOB_UNIFORM_FALLBACK, null, listener)
		_:
			return _begin_normal_talk(listener)


func _refresh_passive_progress(job: FirstJob) -> void:
	if job.plant_job_finished(Game.inventory):
		job.mark_plant_finished()
	if job.kind == FirstJob.Kind.INTRODUCTIONS:
		job.refresh_introductions()


func _done_bank_for(kind: FirstJob.Kind) -> StringName:
	match kind:
		FirstJob.Kind.CHANGE_CLOTH:
			return JOB_UNIFORM_DONE
		FirstJob.Kind.PLANT_FLOWER:
			return JOB_PLANT_DONE
		_:
			return &""


func _done_fallback_for(kind: FirstJob.Kind) -> StringName:
	match kind:
		FirstJob.Kind.CHANGE_CLOTH:
			return JOB_UNIFORM_DONE_FALLBACK
		FirstJob.Kind.PLANT_FLOWER:
			return JOB_PLANT_DONE_FALLBACK
		FirstJob.Kind.INTRODUCTIONS:
			return JOB_INTRO_DONE
		FirstJob.Kind.DELIVER_FTR:
			return JOB_FTR_DONE
		FirstJob.Kind.SEND_LETTER, FirstJob.Kind.SEND_LETTER2:
			return JOB_LETTER_DONE
		FirstJob.Kind.OPEN:
			return JOB_OPEN_DONE
		FirstJob.Kind.DELIVER_CARPET:
			return JOB_CARPET_DONE
		FirstJob.Kind.DELIVER_AXE, FirstJob.Kind.DELIVER_AXE2:
			return JOB_AXE_DONE
		FirstJob.Kind.POST_NOTICE:
			return JOB_ALL_DONE
		_:
			return JOB_PLANT_DONE_FALLBACK


func _assign_fallback_for(kind: FirstJob.Kind) -> StringName:
	match kind:
		FirstJob.Kind.PLANT_FLOWER:
			return JOB_PLANT_FALLBACK
		FirstJob.Kind.INTRODUCTIONS:
			return JOB_INTRO
		FirstJob.Kind.DELIVER_FTR:
			return JOB_FTR
		FirstJob.Kind.SEND_LETTER, FirstJob.Kind.SEND_LETTER2:
			return JOB_LETTER
		FirstJob.Kind.OPEN:
			return JOB_OPEN
		FirstJob.Kind.DELIVER_CARPET:
			return JOB_CARPET
		FirstJob.Kind.DELIVER_AXE, FirstJob.Kind.DELIVER_AXE2:
			return JOB_AXE
		FirstJob.Kind.POST_NOTICE:
			return JOB_NOTICE
		_:
			return &""


func _play_job_chain(
	ids: Array[StringName],
	fallbacks: Array[StringName],
	listener: Node3D
) -> bool:
	for i: int in ids.size():
		var id: StringName = ids[i]
		var fb: StringName = fallbacks[i] if i < fallbacks.size() else &""
		var data: DialogueData = DialogueCatalog.conversation(id)
		if data == null and fb != &"":
			data = DialogueCatalog.conversation(fb)
			id = fb
		if data == null:
			continue
		if i == 0 and ids.size() > 1:
			if id == JOB_ARRIVE or id == JOB_ARRIVE_FALLBACK:
				_pending_after = &"after_arrive"
				return _play_data(data, listener)
		return _play_data(data, listener)
	return _play_job_line(&"", JOB_ARRIVE_FALLBACK, null, listener)


func _play_job_line(
	id: StringName,
	fallback: StringName,
	_ctx: InteractionContext = null,
	listener: Node3D = null
) -> bool:
	var data: DialogueData = null
	if id != &"":
		data = DialogueCatalog.conversation(id)
	if data == null and fallback != &"":
		data = DialogueCatalog.conversation(fallback)
	if data == null:
		Game.post_notice("Tom Nook: Yes, yes!")
		_apply_pending_after()
		return true
	return _play_data(data, listener)


func _play_data(data: DialogueData, listener: Node3D) -> bool:
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	var play_data: DialogueData = data
	if (
		Game != null
		and Game.first_job != null
		and Game.first_job.needs_named_recipient()
		and play_data != null
		and play_data.id in FirstJob.recipient_dialogue_ids()
	):
		if Game.first_job.recipient_id == &"":
			push_error("FirstJob: playing recipient dialogue with empty recipient_id")
		play_data = FirstJob.ensure_dialogue_names_recipient(play_data)
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_method("play"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call("play", play_data, talk_ctx)
		return true
	_apply_pending_after()
	return true


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
	TalkCamera.end(get_tree())
	await _apply_pending_after()


func _apply_pending_after() -> void:
	var op: StringName = _pending_after
	_pending_after = &""
	if op == &"" or Game == null or Game.first_job == null:
		return
	var job: FirstJob = Game.first_job
	var listener: Node3D = (
		get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null
	)
	match op:
		&"after_arrive":
			_pending_after = &"give_uniform"
			_play_job_line(JOB_UNIFORM, JOB_UNIFORM_FALLBACK, null, listener)
		&"give_uniform":
			job.setup_change_cloth()
			await _hand_over_gift(listener, FirstJob.UNIFORM_ID)
			job.give_uniform(Game.inventory)
			Game.set_interact_prompt(job.prompt_for_kind())
			_play_job_line(JOB_UNIFORM_WAIT, JOB_UNIFORM_WAIT_FALLBACK, null, listener)
		&"start_plant_from_uniform":
			job.setup_change_cloth()
			job.tick_cloth(Game.cloth_id)
			if not job.advance_after_finished(Game.inventory):
				_play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
				return
			await _hand_over_gift(listener, job.gift_display_item())
			Game.set_interact_prompt(job.prompt_for_kind())
			_play_job_line(JOB_PLANT, JOB_PLANT_FALLBACK, null, listener)
		&"advance":
			if not job.advance_after_finished(Game.inventory):
				_play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
				return
			if not job.is_active():
				Game.set_interact_prompt("")
				return
			var gift: StringName = job.gift_display_item()
			if gift != &"":
				await _hand_over_gift(listener, gift)
			Game.set_interact_prompt(job.prompt_for_kind())
			var assign: StringName = _assign_fallback_for(job.kind)
			if assign != &"":
				_play_job_line(&"", assign, null, listener)


func _hand_over_gift(listener: Node3D, item_id: StringName) -> void:
	## `aNRG2_demo_start_wait` → NPC TRANSFER / player GET (`handOverItem`).
	if listener == null:
		return
	await HandOver.npc_gives_to_player(self, listener, item_id)


func play_wait_anim() -> void:
	_play_clip(ANIM_WAIT, true)


func animation_player() -> AnimationPlayer:
	return _body_anim


func _listener(ctx: InteractionContext) -> Node3D:
	return ctx.actor as Node3D if ctx != null else null


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
	var species: StringName = ShopDisplay.nook_species(_nook_level())
	var vis: Node3D = GeneratedVisual.attach_villager(_model, species)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.52, 0.28)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	## Permanent shop master leaves `cloth_idx` NONE (`aNPC_actor_init_for_special`).
	_body_anim = GeneratedVisual.find_animation_player(vis)
	_face.bind(vis, species)
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


func _nook_level() -> int:
	if Game != null and Game.current_room_id != &"":
		if ShopDisplay.nook_is_shop_room(Game.current_room_id) or Game.current_room_id == &"shop3_2":
			return ShopDisplay.nook_level_for_room(Game.current_room_id)
	if Game != null and Game.shops != null:
		return Game.shops.nook_level()
	return 0


func _resolve_clip(suffix: String) -> String:
	if _body_anim == null or suffix.is_empty():
		return ""
	if _body_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _body_anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
